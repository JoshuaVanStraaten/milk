// supabase/functions/products-clicks/index.ts
// Proxies product requests to Clicks via Algolia search API
//
// POST body: {
//   "store_code": "clicks-01",       // Optional: ignored (national pricing)
//   "query": "vitamins",             // Optional: search term
//   "category": "Snacks",            // Optional: category name
//   "page": 0,                       // Optional: page number (0-indexed)
//   "page_size": 20                  // Optional: items per page (max 40)
// }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const ALGOLIA_APP_ID = Deno.env.get("ALGOLIA_APP_ID") || "";
const ALGOLIA_API_KEY = Deno.env.get("ALGOLIA_API_KEY") || "";
const ALGOLIA_INDEX = "Prod_ProductIndex";
const ALGOLIA_URL = `https://${ALGOLIA_APP_ID.toLowerCase()}-dsn.algolia.net/1/indexes/*/queries`;

// Category → search term mapping
// Clicks is pharmacy-first — categories match their product strengths
const CLICKS_CATEGORY_SEARCH: Record<string, string> = {
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

  try {
    const {
      query,
      category,
      page = 0,
      page_size = 20,
    } = await req.json();

    // Build search query — category uses simple search terms (no facet filters)
    const searchQuery = query || (category ? CLICKS_CATEGORY_SEARCH[category] : null) || "vitamins";

    const params = `hitsPerPage=${Math.min(page_size, 40)}&page=${page}&query=${encodeURIComponent(searchQuery)}`;

    console.log(
      `[Clicks] Query: "${searchQuery}", Page: ${page}`,
    );

    const response = await fetch(
      `${ALGOLIA_URL}?x-algolia-api-key=${ALGOLIA_API_KEY}&x-algolia-application-id=${ALGOLIA_APP_ID}`,
      {
        method: "POST",
        headers: {
          "content-type": "application/x-www-form-urlencoded",
          Origin: "https://clicks.co.za",
          Referer: "https://clicks.co.za/",
        },
        body: JSON.stringify({
          requests: [
            {
              indexName: ALGOLIA_INDEX,
              params,
            },
          ],
        }),
      },
    );

    if (!response.ok) {
      const errorText = await response.text();
      console.error(
        `[Clicks] Algolia returned ${response.status}: ${errorText.substring(0, 200)}`,
      );
      return new Response(
        JSON.stringify({
          error: `Clicks API returned ${response.status}`,
          source: "live",
          retailer: "Clicks",
        }),
        {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const data = await response.json();
    const result = data.results?.[0];
    const hits = result?.hits || [];
    const products = hits
      .filter((h: any) => h.inStockFlag)
      .map(normalizeProduct);

    console.log(
      `[Clicks] Returned ${products.length} products (total: ${result?.nbHits})`,
    );

    return new Response(
      JSON.stringify({
        products,
        pagination: {
          current_page: result?.page ?? 0,
          total_pages: result?.nbPages ?? 0,
          total_results: result?.nbHits ?? 0,
          page_size: result?.hitsPerPage ?? page_size,
        },
        retailer: "Clicks",
        source: "live",
        timestamp: new Date().toISOString(),
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error("[Clicks] Unexpected error:", err);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        retailer: "Clicks",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

function normalizeProduct(hit: any) {
  // --- Name ---
  const name = hit.brandWithProductName || hit.productName || "Unknown product";

  // --- Price ---
  const price = hit.price != null ? `R${hit.price.toFixed(2)}` : "Price not available";

  // --- Promotion ---
  let promotion_price = "No promo";
  let promotion_valid = "";

  if (hit.promoWithAppliedGrossPriceValue && hit.promoWithAppliedGrossPriceValue < hit.price) {
    promotion_price = `R${hit.promoWithAppliedGrossPriceValue.toFixed(2)}`;
  }

  if (hit.promoDescriptions?.length > 0) {
    const desc = hit.promoDescriptions[0];
    // Extract validity: "... Valid until 24 March 2026~..."
    const validMatch = desc.match(/Valid until ([^~]+)/i);
    if (validMatch) {
      promotion_valid = `Valid until ${validMatch[1].trim()}`;
    }
    // Use promoOffers for a cleaner display if available
    if (hit.promoOffers?.length > 0) {
      promotion_price = hit.promoOffers[0];
    }
  }

  // --- Image ---
  let image_url: string | null = null;
  if (hit.img300Wx300H) {
    image_url = `https://clicks.co.za${hit.img300Wx300H}`;
  } else if (hit.img180Wx180H) {
    image_url = `https://clicks.co.za${hit.img180Wx180H}`;
  }

  // --- Categories ---
  const categories: string[] = [];
  if (hit.categories?.lvl0) categories.push(...hit.categories.lvl0);

  return {
    id: hit.baseProductCode || hit.objectID || null,
    name,
    price,
    promotion_price,
    promotion_valid,
    retailer: "Clicks",
    image_url,
    categories,
  };
}
