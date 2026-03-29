// supabase/functions/products-dischem/index.ts
// Proxies product requests to Dis-Chem via Klevu search API
//
// POST body: {
//   "store_code": "dischem-01",      // Optional: ignored (national pricing)
//   "query": "vitamins",             // Optional: search term
//   "category": "Snacks",            // Optional: category name
//   "page": 0,                       // Optional: page number (0-indexed)
//   "page_size": 24                  // Optional: items per page (max 48)
// }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { checkRateLimit } from "../_shared/rate_limiter.ts";

const KLEVU_ENDPOINT =
  "https://eucs7.ksearchnet.com/cloud-search/n-search/search";
const KLEVU_TICKET = Deno.env.get("KLEVU_TICKET") || "";

// Category → search term mapping
// Dis-Chem is pharmacy-first — categories match their product strengths
const DISCHEM_CATEGORY_SEARCH: Record<string, string> = {
  "Vitamins": "vitamins",
  "Supplements": "supplements",
  "Baby": "baby",
  "Skincare": "skincare",
  "Haircare": "haircare",
  "Medicine": "medicine",
  "Protein": "protein",
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://sfnavipqilqgzmtedfuh.supabase.co",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const rateLimited = checkRateLimit(req, corsHeaders);
  if (rateLimited) return rateLimited;

  try {
    const {
      query,
      category,
      page = 0,
      page_size = 24,
    } = await req.json();

    const searchTerm =
      query || (category ? DISCHEM_CATEGORY_SEARCH[category] : null);

    if (!searchTerm) {
      // Default browse: show popular items
      return await fetchAndRespond("vitamins", page, page_size);
    }

    return await fetchAndRespond(searchTerm, page, page_size);
  } catch (err) {
    console.error("[Dis-Chem] Unexpected error:", err);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        retailer: "Dis-Chem",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

async function fetchAndRespond(
  searchTerm: string,
  page: number,
  pageSize: number,
) {
  const clampedSize = Math.min(pageSize, 48);
  const paginationStart = page * clampedSize;

  const params = new URLSearchParams({
    ticket: KLEVU_TICKET,
    term: searchTerm,
    paginationStartsFrom: String(paginationStart),
    sortPrice: "false",
    ipAddress: "undefined",
    analyticsApiKey: KLEVU_TICKET,
    showOutOfStockProducts: "true",
    klevuFetchPopularTerms: "false",
    klevu_priceInterval: "50",
    klevu_multiSelectFilters: "true",
    noOfResults: String(clampedSize),
    klevuSort: "rel",
    enableFilters: "false",
    layoutVersion: "2.0",
    autoComplete: "false",
    autoCompleteFilters: "category",
    filterResults: "",
    visibility: "search",
    klevu_filterLimit: "50",
    sv: "382",
    lsqt: "",
    responseType: "json",
    resultForZero: "1",
    klevu_loginCustomerGroup: "",
  });

  const url = `${KLEVU_ENDPOINT}?${params.toString()}`;

  console.log(
    `[Dis-Chem] Query: "${searchTerm}", Page: ${page}`,
  );

  const response = await fetch(url, {
    headers: {
      accept: "application/json",
      "user-agent":
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36",
      origin: "https://www.dischem.co.za",
      referer: "https://www.dischem.co.za/",
    },
  });

  if (!response.ok) {
    const errorText = await response.text();
    console.error(
      `[Dis-Chem] Klevu API returned ${response.status}: ${errorText.substring(0, 200)}`,
    );
    return new Response(
      JSON.stringify({
        error: `Dis-Chem API returned ${response.status}`,
        source: "live",
        retailer: "Dis-Chem",
      }),
      {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }

  const data = await response.json();
  const meta = data.meta || {};
  const items = data.result || [];
  const totalCount = meta.totalResultsFound || 0;
  const totalPages = Math.ceil(totalCount / clampedSize);

  const products = items
    .filter((item: any) => item.typeOfRecord === "KLEVU_PRODUCT")
    .map(normalizeProduct);

  console.log(
    `[Dis-Chem] Returned ${products.length} products (total: ${totalCount})`,
  );

  return new Response(
    JSON.stringify({
      products,
      pagination: {
        current_page: page,
        total_pages: totalPages,
        total_results: totalCount,
        page_size: clampedSize,
      },
      retailer: "Dis-Chem",
      source: "live",
      timestamp: new Date().toISOString(),
    }),
    { headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
}

function normalizeProduct(item: any) {
  // --- Name ---
  const name = item.name || "Unknown product";

  // --- Price ---
  const salePrice = parseFloat(item.salePrice);
  const price = !isNaN(salePrice)
    ? `R${salePrice.toFixed(2)}`
    : "Price not available";

  // --- Promotion ---
  let promotion_price = "No promo";
  const promotion_valid = "";

  // Check promo_discount_sap — if present, it's the discounted price
  const promoDiscount = parseFloat(item.promo_discount_sap);
  if (!isNaN(promoDiscount) && promoDiscount > 0 && promoDiscount < salePrice) {
    promotion_price = `R${promoDiscount.toFixed(2)}`;
  }

  // --- Image ---
  // Klevu provides 200x200 images; use as-is
  const image_url = item.image || item.imageUrl || null;

  return {
    id: item.sku || String(item.id) || null,
    name,
    price,
    promotion_price,
    promotion_valid,
    retailer: "Dis-Chem",
    image_url,
    categories: [],
  };
}
