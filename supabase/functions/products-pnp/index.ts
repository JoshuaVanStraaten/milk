// supabase/functions/products-pnp/index.ts
// Proxies product requests to Pick n Pay's Hybris API
//
// POST body: {
//   "store_code": "NC30",        // Required: PnP store code
//   "query": "milk",             // Optional: search term (omit for browse)
//   "category": "pnpbase",       // Optional: category code (default: all products)
//   "page": 0,                   // Optional: page number (0-indexed)
//   "page_size": 48              // Optional: items per page (max 48)
// }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { checkRateLimit } from "../_shared/rate_limiter.ts";

const PNP_API = "https://www.pnp.co.za/pnphybris/v2/pnp-spa/products/search";

// Maps display category names → PnP Hybris category slugs
// Format confirmed from network tab: :relevance:allCategories:pnpbase:category:<slug>
const PNP_CATEGORIES: Record<string, string> = {
  "Fruit & Veg": "fresh-fruit-and-vegetables-423144840",
  "Meat & Poultry": "fresh-meat-poultry-and-seafood-423144840",
  "Dairy & Eggs": "milk-dairy-and-eggs-423144840",
  "Bakery": "bakery-423144840",
  "Frozen": "frozen-food-423144840",
  "Food Cupboard": "food-cupboard-423144840",
  "Snacks": "chocolates-chips-and-snacks-423144840",
  "Beverages": "beverages-423144840",
};

const PRODUCT_FIELDS = [
  "code",
  "name",
  "price(FULL)",
  "images(DEFAULT)",
  "potentialPromotions(FULL)",
  "categoryNames",
].join(",");

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
      store_code,
      query,
      category = "pnpbase",
      page = 0,
      page_size = 48,
    } = await req.json();

    if (!store_code) {
      return new Response(JSON.stringify({ error: "store_code is required" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const fields = `products(${PRODUCT_FIELDS}),pagination(DEFAULT)`;

    // Build the Hybris query string
    // Search mode: use the search term directly
    // Browse mode: use facet query for category
    let hybrisQuery: string;
    if (query) {
      hybrisQuery = query;
    } else {
      const categorySlug = category ? PNP_CATEGORIES[category] : null;
      hybrisQuery = categorySlug
        ? `:relevance:allCategories:pnpbase:category:${categorySlug}`
        : `:relevance:allCategories:${category || "pnpbase"}`;
    }

    const params = new URLSearchParams({
      fields,
      query: hybrisQuery,
      pageSize: String(Math.min(page_size, 48)),
      currentPage: String(page),
      storeCode: store_code,
      lang: "en",
      curr: "ZAR",
    });

    console.log(
      `[PnP] Store: ${store_code}, Query: "${query || "browse"}", Page: ${page}`,
    );

    const response = await fetch(`${PNP_API}?${params}`, {
      method: "POST",
      headers: {
        accept: "application/json",
        "content-type": "application/json",
        origin: "https://www.pnp.co.za",
        referer: "https://www.pnp.co.za/c/pnpbase",
        "user-agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
      },
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error(
        `[PnP] API returned ${response.status}: ${errorText.substring(0, 200)}`,
      );
      return new Response(
        JSON.stringify({
          error: `PnP API returned ${response.status}`,
          source: "live",
          retailer: "Pick n Pay",
        }),
        {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const data = await response.json();
    const products = (data.products || []).map(normalizeProduct);
    const pagination = data.pagination || {};

    console.log(
      `[PnP] Returned ${products.length} products (total: ${pagination.totalResults})`,
    );

    return new Response(
      JSON.stringify({
        products,
        pagination: {
          current_page: pagination.currentPage ?? 0,
          total_pages: pagination.totalPages ?? 0,
          total_results: pagination.totalResults ?? 0,
          page_size: pagination.pageSize ?? page_size,
        },
        retailer: "Pick n Pay",
        store_code,
        source: "live",
        timestamp: new Date().toISOString(),
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error("[PnP] Unexpected error:", err);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        retailer: "Pick n Pay",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

function normalizeProduct(item: any) {
  // --- Image ---
  let image_url: string | null = null;
  const images = item.images || [];
  // Prefer 'carousel' format (highest res), then 'product', then first available
  for (const format of ["carousel", "product", "thumbnail"]) {
    const img = images.find((i: any) => i.format === format);
    if (img?.url) {
      image_url = img.url.startsWith("http")
        ? img.url
        : `https://cdn-prd-02.pnp.co.za${img.url}`;
      break;
    }
  }
  if (!image_url && images.length > 0 && images[0].url) {
    image_url = images[0].url.startsWith("http")
      ? images[0].url
      : `https://cdn-prd-02.pnp.co.za${images[0].url}`;
  }

  // --- Price ---
  const price = item.price?.formattedValue || "Price not available";

  // --- Promotion ---
  const promos = item.potentialPromotions || [];
  let promotion_price = "No promo";
  let promotion_valid = "";

  if (promos.length > 0) {
    const promo = promos[0];
    promotion_price = promo.promotionTextMessage?.trim() || "No promo";

    if (promo.endDate) {
      try {
        const end = new Date(promo.endDate);
        promotion_valid = `Valid until ${end.toLocaleDateString("en-ZA", {
          day: "numeric",
          month: "long",
          year: "numeric",
        })}`;
      } catch {
        // Ignore date parsing errors
      }
    }
  }

  return {
    id: item.code || null,
    name: item.name || "Unknown product",
    price,
    promotion_price,
    promotion_valid,
    retailer: "Pick n Pay",
    image_url,
    categories: item.categoryNames || [],
  };
}
