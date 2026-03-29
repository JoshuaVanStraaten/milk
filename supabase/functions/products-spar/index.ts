// supabase/functions/products-spar/index.ts
// POC: Proxies product requests to SPAR via KwikSPAR API (prices) + Commerce API (product details/images)
//
// POST body: {
//   "query": "milk",              // Required: search term
//   "page": 1,                    // Optional: page number (1-indexed)
//   "page_size": 24               // Optional: items per page
// }
//
// Data sources:
// 1. KwikSPAR (hillcrestkwikspar.co.za) — product search with prices (CSRF session)
// 2. SPAR Commerce API (api.spar.co.za) — product details, images, GTINs (JWT auth)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { checkRateLimit } from "../_shared/rate_limiter.ts";

const KWIKSPAR_BASE = "https://hillcrestkwikspar.co.za";
const KWIKSPAR_SEARCH = `${KWIKSPAR_BASE}/shop/searchproduct`;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// ─── KwikSPAR Session (CSRF + cookies) ───

interface KwikSparSession {
  csrf: string;
  cookies: string;
  expiresAt: number;
}

let cachedSession: KwikSparSession | null = null;

async function getKwikSparSession(): Promise<KwikSparSession> {
  // Reuse session if still valid (5 min TTL)
  if (cachedSession && Date.now() < cachedSession.expiresAt) {
    return cachedSession;
  }

  const resp = await fetch(`${KWIKSPAR_BASE}/shop/`, {
    headers: {
      "User-Agent":
        "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36",
    },
  });

  const html = await resp.text();

  // Extract CSRF token from meta tag
  const csrfMatch = html.match(/csrf-token"\s+content="([^"]+)"/);
  if (!csrfMatch) {
    throw new Error("Failed to extract CSRF token from KwikSPAR");
  }

  // Extract session cookies
  const setCookies = resp.headers.getSetCookie?.() ?? [];
  const cookieStr = setCookies
    .map((c: string) => c.split(";")[0])
    .join("; ");

  if (!cookieStr) {
    throw new Error("No session cookies from KwikSPAR");
  }

  cachedSession = {
    csrf: csrfMatch[1],
    cookies: cookieStr,
    expiresAt: Date.now() + 5 * 60 * 1000, // 5 min
  };

  return cachedSession;
}

// ─── KwikSPAR Product Search ───

interface KwikSparProduct {
  item_id: string;
  item_name: string;
  price: number;
  discount?: number;
  currency: string;
  item_brand: string;
  item_category: string | null;
}

async function searchKwikSpar(
  query: string,
  page: number,
  pageSize: number
): Promise<{ products: KwikSparProduct[]; total: number }> {
  const session = await getKwikSparSession();

  const resp = await fetch(KWIKSPAR_SEARCH, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      "X-CSRF-TOKEN": session.csrf,
      "X-Requested-With": "XMLHttpRequest",
      Cookie: session.cookies,
      Accept: "application/json",
    },
    body: new URLSearchParams({
      productname: query,
      reference: "",
      pageno: String(page),
      globalsearch: "true",
    }),
  });

  if (!resp.ok) {
    // Session expired — clear cache and retry once
    if (resp.status === 419 || resp.status === 403) {
      cachedSession = null;
      const retrySession = await getKwikSparSession();
      const retryResp = await fetch(KWIKSPAR_SEARCH, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
          "X-CSRF-TOKEN": retrySession.csrf,
          "X-Requested-With": "XMLHttpRequest",
          Cookie: retrySession.cookies,
          Accept: "application/json",
        },
        body: new URLSearchParams({
          productname: query,
          reference: "",
          pageno: String(page),
          globalsearch: "true",
        }),
      });
      if (!retryResp.ok) {
        throw new Error(`KwikSPAR search failed: ${retryResp.status}`);
      }
      const data = await retryResp.json();
      return { products: data.returnProduct ?? [], total: data.count ?? 0 };
    }
    throw new Error(`KwikSPAR search failed: ${resp.status}`);
  }

  const data = await resp.json();
  return { products: data.returnProduct ?? [], total: data.count ?? 0 };
}

// ─── Product Name Parsing ───

function parseKwikSparProduct(p: KwikSparProduct): {
  name: string;
  price: string;
  promotion_price: string;
  retailer: string;
  image_url: string;
  promotion_valid: string;
} {
  // KwikSPAR names look like: "SPAR FULL CREAM MILK UHT 1L SK6001008619403"
  // Extract the barcode/SKU from the end of the name
  let name = p.item_name;
  let barcode = "";

  const skuMatch = name.match(/\s+SK(\d{6,14})$/i);
  if (skuMatch) {
    barcode = skuMatch[1];
    name = name.replace(/\s+SK\d{6,14}$/i, "").trim();
  }

  // Title case the name
  name = name
    .toLowerCase()
    .replace(/\b\w/g, (c) => c.toUpperCase())
    .replace(/\bUht\b/g, "UHT")
    .replace(/\bMl\b/g, "ml")
    .replace(/\bKg\b/g, "kg")
    .replace(/\bG\b/g, "g")
    .replace(/\bL\b/g, "L");

  const price = `R${p.price.toFixed(2)}`;
  const promoPrice = p.discount ? `R${p.discount.toFixed(2)}` : "No promo";

  // KwikSPAR doesn't serve product images and products.spar.net requires signed URLs.
  // Leave empty — the app's ImageLookupService or fallback will handle it.
  const imageUrl = "";

  return {
    name,
    price,
    promotion_price: promoPrice,
    retailer: "SPAR",
    image_url: imageUrl,
    promotion_valid: p.discount ? "On promotion" : "",
  };
}

// ─── Main Handler ───

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const rateLimited = checkRateLimit(req, corsHeaders);
  if (rateLimited) return rateLimited;

  try {
    const { query, page = 1, page_size = 24 } = await req.json();

    if (!query) {
      return new Response(
        JSON.stringify({ error: "query is required" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Search KwikSPAR for products with prices
    const { products: kwikProducts, total } = await searchKwikSpar(
      query,
      page,
      page_size
    );

    // Normalize products to the standard format
    const products = kwikProducts.map(parseKwikSparProduct);

    const totalPages = Math.ceil(total / page_size);

    return new Response(
      JSON.stringify({
        products,
        pagination: {
          current_page: page,
          total_pages: totalPages,
          total_results: total,
          page_size,
        },
        retailer: "SPAR",
        source: "kwikspar_live",
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    return new Response(
      JSON.stringify({ error: message }),
      {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
