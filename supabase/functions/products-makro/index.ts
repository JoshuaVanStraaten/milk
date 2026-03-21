// supabase/functions/products-makro/index.ts
// Proxies product requests to Makro's Flipkart Commerce Cloud API
//
// POST body: {
//   "store_code": "makro-01",       // Optional: ignored (national pricing)
//   "query": "milk",                // Optional: search term (omit for browse)
//   "category": "Dairy & Eggs",     // Optional: category name
//   "page": 1,                      // Optional: page number (1-indexed)
//   "page_size": 40                 // Optional: items per page (max 40)
// }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const MAKRO_API = "https://www.makro.co.za/fccng/api/4/page/fetch";

// Category → search term mapping (Makro doesn't expose category facets via API,
// so we search within the food store instead)
const MAKRO_CATEGORY_SEARCH: Record<string, string> = {
  "Food Cupboard": "food",
  "Snacks": "snacks",
  "Beverages": "juice",
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const BROWSER_UA =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const {
      query,
      category,
      page = 1,
      page_size = 40,
    } = await req.json();

    // Build the pageUri for Makro's FCC API
    let pageUri: string;
    const searchTerm = query || (category ? MAKRO_CATEGORY_SEARCH[category] : null);

    if (searchTerm) {
      // Search within food store
      pageUri = `/search?q=${encodeURIComponent(searchTerm)}&store=eat`;
    } else {
      // Browse all food products
      pageUri = "/food-products/pr?sid=eat";
    }

    const isPaginated = page > 1;

    const requestBody = {
      pageUri,
      pageContext: {
        fetchSeoData: false,
        paginatedFetch: isPaginated,
        pageNumber: page,
        ...(isPaginated && {
          paginationContextMap: {
            federator: {
              productsOffset: (page - 1) * page_size,
              pageNumber: page - 1,
              PRODUCT: page_size,
              productsEnd: (page - 1) * page_size,
              "store.path": "search.flipkart.com",
              "redirection.store.path": "eat",
              layout: "grid",
              productTypeClusterStart: (page - 1) * page_size + 1,
            },
          },
        }),
      },
      requestContext: {
        type: "BROWSE_PAGE",
      },
    };

    console.log(
      `[Makro] Query: "${searchTerm || "browse"}", Page: ${page}`,
    );

    const response = await fetch(MAKRO_API, {
      method: "POST",
      headers: {
        accept: "*/*",
        "content-type": "application/json",
        origin: "https://www.makro.co.za",
        referer: `https://www.makro.co.za${pageUri}`,
        "user-agent": BROWSER_UA,
        "x-user-agent": `${BROWSER_UA} FKUA/website/42/website/Desktop`,
      },
      body: JSON.stringify(requestBody),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error(
        `[Makro] API returned ${response.status}: ${errorText.substring(0, 200)}`,
      );
      return new Response(
        JSON.stringify({
          error: `Makro API returned ${response.status}`,
          source: "live",
          retailer: "Makro",
        }),
        {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const data = await response.json();
    const slots = data?.RESPONSE?.slots || [];

    // Extract products from PRODUCT_SUMMARY widgets
    const products: any[] = [];
    for (const slot of slots) {
      if (slot?.widget?.type === "PRODUCT_SUMMARY") {
        const slotProducts = slot.widget.data?.products || [];
        for (const p of slotProducts) {
          const normalized = normalizeProduct(p);
          if (normalized) products.push(normalized);
        }
      }
    }

    // Extract pagination from PAGINATION_BAR widget
    let totalPages = 1;
    const paginationSlot = slots.find(
      (s: any) => s?.widget?.type === "PAGINATION_BAR",
    );
    if (paginationSlot) {
      const navPages = paginationSlot.widget.data?.navigationPages || [];
      totalPages = navPages.length || 1;
      // If there are more pages beyond what's shown in navigation
      const lastPage = navPages[navPages.length - 1];
      if (lastPage?.number) totalPages = Math.max(totalPages, lastPage.number);
    }

    console.log(
      `[Makro] Returned ${products.length} products (page ${page}/${totalPages})`,
    );

    return new Response(
      JSON.stringify({
        products,
        pagination: {
          current_page: page - 1, // Normalize to 0-indexed for Flutter client
          total_pages: totalPages,
          total_results: totalPages * page_size, // Makro doesn't expose exact total
          page_size,
        },
        retailer: "Makro",
        source: "live",
        timestamp: new Date().toISOString(),
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error("[Makro] Unexpected error:", err);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        retailer: "Makro",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

function normalizeProduct(product: any) {
  const val = product?.productInfo?.value;
  if (!val) return null;

  // Skip out-of-stock items
  if (val.availability?.displayState !== "IN_STOCK") return null;

  // --- Name ---
  const title = val.titles?.title || "Unknown product";

  // --- Price ---
  const finalPrice = val.pricing?.finalPrice?.value;
  const mrpPrice = val.pricing?.mrp?.value;
  const price = finalPrice != null ? `R${finalPrice.toFixed(2)}` : "Price not available";

  // --- Promotion ---
  let promotion_price = "No promo";
  let promotion_valid = "";

  if (mrpPrice && finalPrice && mrpPrice > finalPrice) {
    const discount = val.pricing?.totalDiscount || 0;
    if (discount > 0) {
      promotion_price = `${discount}% off - Was R${mrpPrice.toFixed(2)}`;
    } else {
      promotion_price = `Save R${(mrpPrice - finalPrice).toFixed(2)}`;
    }
  }

  // Check for price tags — only use if they indicate an actual discount.
  // Makro priceTags can include non-promo labels like "New", "Best Seller",
  // "Bundle Deal" which would falsely mark products as on promotion.
  const priceTags = val.pricing?.priceTags;
  if (priceTags && Array.isArray(priceTags) && priceTags.length > 0) {
    for (const tag of priceTags) {
      const tagText = (tag.title || tag.text || "").toLowerCase();
      // Only use tags that clearly indicate a price promotion
      if (tagText.includes("off") || tagText.includes("save") ||
          tagText.includes("% ") || tagText.includes("for r") ||
          tagText.includes("was r") || tagText.includes("half price")) {
        promotion_price = tag.title || tag.text;
        break;
      }
    }
  }

  // --- Image ---
  let image_url: string | null = null;
  const images = val.media?.images || [];
  if (images.length > 0 && images[0].url) {
    image_url = images[0].url
      .replace("{@width}", "312")
      .replace("{@height}", "312")
      .replace("{@quality}", "70");
  }

  return {
    id: val.id || null,
    name: title,
    price,
    promotion_price,
    promotion_valid,
    retailer: "Makro",
    image_url,
    categories: val.analyticsData
      ? [val.analyticsData.superCategory, val.analyticsData.category, val.analyticsData.subCategory].filter(Boolean)
      : [],
  };
}
