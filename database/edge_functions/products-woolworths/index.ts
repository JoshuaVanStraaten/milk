// supabase/functions/products-woolworths/index.ts
//
// Woolworths Live Product API Proxy
// Pure JSON API — no HTML parsing, no CSRF, no browser needed
//
// Flow (matches the working Python scraper exactly):
//   1. POST /server/confirmPlace with placeId + nickname → get session cookies
//      (Do NOT visit the homepage — it triggers Cloudflare bot protection)
//   2. GET /server/searchCategory with category or search query → products JSON
//   3. Normalize and return

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const BASE_URL = "https://www.woolworths.co.za";
const SEARCH_URL = `${BASE_URL}/server/searchCategory`;
const CONFIRM_PLACE_URL = `${BASE_URL}/server/confirmPlace`;

const USER_AGENT =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// Woolworths food categories: name -> ATG navigation code
const CATEGORIES: Record<string, string> = {
  "Fruit-Vegetables-Salads": "lllnam",
  "Meat-Poultry-Fish": "d87rb7",
  "Milk-Dairy-Eggs": "1sqo44p",
  "Ready-Meals": "s2csbp",
  "Deli-Entertaining": "13b8g51",
  "Food-To-Go": "11buko0",
  Bakery: "1bm2new",
  "Frozen-Food": "j8pkwq",
  Pantry: "1lw4dzx",
  "Chocolates-Sweets-Snacks": "1yz1i0m",
  "Beverages-Juices": "mnxddc",
  Household: "vvikef",
  Cleaning: "o1v4pe",
  "Toiletries-Health": "1q1wl1r",
  Kids: "ymaf0z",
  Baby: "1rij75n",
  Pets: "l1demz",
};

const DEFAULT_PAGE_SIZE = 24;

// Types
interface NormalizedProduct {
  name: string;
  price: string;
  promotion_price: string;
  retailer: string;
  image_url: string | null;
  promotion_valid: string;
}

interface ProductsResponse {
  products: NormalizedProduct[];
  pagination: {
    current_page: number;
    total_pages: number | null;
    total_results: number | null;
    page_size: number;
  };
  retailer: string;
  source: string;
  categories?: string[];
}

// ── Cookie Management ────────────────────────────────────────────────────────

function extractCookies(
  response: Response,
  existingCookies: Map<string, string>,
): Map<string, string> {
  const setCookies: string[] = [];
  if (typeof (response.headers as any).getSetCookie === "function") {
    setCookies.push(...(response.headers as any).getSetCookie());
  } else {
    const raw = response.headers.get("set-cookie") || "";
    if (raw) setCookies.push(...raw.split(/,(?=\s*[A-Za-z_][A-Za-z0-9_]*=)/));
  }
  for (const cookieStr of setCookies) {
    if (!cookieStr) continue;
    const parts = cookieStr.split(";")[0].trim();
    const eqIdx = parts.indexOf("=");
    if (eqIdx > 0) {
      existingCookies.set(
        parts.substring(0, eqIdx).trim(),
        parts.substring(eqIdx + 1).trim(),
      );
    }
  }
  return existingCookies;
}

function cookieString(cookies: Map<string, string>): string {
  return Array.from(cookies.entries())
    .map(([k, v]) => `${k}=${v}`)
    .join("; ");
}

// ── Session Management ───────────────────────────────────────────────────────

/**
 * Create a Woolworths session via confirmPlace.
 *
 * IMPORTANT: Do NOT visit the homepage first — it triggers Cloudflare.
 * Go straight to confirmPlace, exactly like the Python scraper does.
 */
async function createSession(
  placeId: string,
  nickname: string,
): Promise<{
  cookies: Map<string, string>;
  error?: string;
}> {
  const cookies = new Map<string, string>();

  try {
    const confirmResp = await fetch(CONFIRM_PLACE_URL, {
      method: "POST",
      headers: {
        "User-Agent": USER_AGENT,
        Accept: "application/json, text/plain, */*",
        "Content-Type": "application/json",
        "x-requested-by": "Woolworths Online",
        Referer: `${BASE_URL}/`,
      },
      body: JSON.stringify({
        deliveryType: "Standard",
        address: { placeId, nickname },
        addSuburbToOrder: true,
      }),
    });

    extractCookies(confirmResp, cookies);

    if (!confirmResp.ok) {
      const text = await confirmResp.text();
      return {
        cookies,
        error: `confirmPlace returned ${confirmResp.status}: ${text.substring(0, 200)}`,
      };
    }

    await confirmResp.text(); // consume body
    console.log(`[Woolworths] Session created: ${cookies.size} cookies`);
    return { cookies };
  } catch (e) {
    return {
      cookies,
      error: `Session creation failed: ${(e as Error).message}`,
    };
  }
}

// ── Constructor.io Search ─────────────────────────────────────────────────────

const CONSTRUCTOR_BASE = "https://wpkmgeuco-zone.cnstrc.com";
const CONSTRUCTOR_KEY = "key_tw9hKe0fkfgEf36D";

/**
 * Search Woolworths products via Constructor.io /v1/search API.
 * This is a public API with a static key — no cookies needed.
 * Uses the full search endpoint (not autocomplete) for proper pagination and richer data.
 */
async function searchProducts(
  query: string,
  page: number,
  pageSize: number,
): Promise<{ records: any[]; totalResults: number | null }> {
  // Build the variations_map for price aggregation
  const variationsMap = JSON.stringify({
    group_by: [{ name: "style", field: "data.styleid" }],
    values: {
      image_url: { field: "data.image_url", aggregation: "first" },
      p10_min: { field: "data.p10", aggregation: "min" },
      p10_max: { field: "data.p10", aggregation: "max" },
      p10_wp: { field: "data.p10_wp", aggregation: "max" },
      p30_min: { field: "data.p30", aggregation: "min" },
      p30_max: { field: "data.p30", aggregation: "max" },
      p30_wp: { field: "data.p30_wp", aggregation: "max" },
      p60_min: { field: "data.p60", aggregation: "min" },
      p60_max: { field: "data.p60", aggregation: "max" },
      p60_wp: { field: "data.p60_wp", aggregation: "max" },
    },
    dtype: "object",
  });

  const params = new URLSearchParams({
    variations_map: variationsMap,
    key: CONSTRUCTOR_KEY,
    "filters[visibility][]": "all",
    sort_by: "relevance",
    sort_order: "descending",
    num_results_per_page: String(pageSize),
    page: String(page + 1), // Constructor.io uses 1-based pages
    us: "default",
    i: crypto.randomUUID(),
    s: "1",
  });

  // Add the second visibility filter value
  const url = `${CONSTRUCTOR_BASE}/v1/search/${encodeURIComponent(query)}?${params}&filters%5Bvisibility%5D%5B%5D=web+and+app`;

  console.log(`[Woolworths] Constructor search: ${query}, page ${page}`);

  const resp = await fetch(url, {
    headers: {
      Accept: "application/json, text/plain, */*",
      "User-Agent": USER_AGENT,
      "X-Requested-By": "Woolworths Online",
      Origin: "https://www.woolworths.co.za",
      Referer: "https://www.woolworths.co.za/",
    },
  });

  if (!resp.ok) {
    console.error(`[Woolworths] Constructor search returned ${resp.status}`);
    return { records: [], totalResults: null };
  }

  const data = await resp.json();

  const results = data.response?.results || [];
  const totalResults = data.response?.total_num_results || null;

  // Map Constructor.io results to the same format as searchCategory records
  const records = results.map((item: any) => {
    const d = item.data || {};

    // Promo info is in data.promo (array of strings) and data.badges
    const promoArray: string[] = d.promo || [];
    const badges = d.badges || {};
    // Use first promo text, or check for SAVE badge
    const promoText =
      promoArray.length > 0
        ? promoArray[0] // Use the first (non-MyDifference) promo
        : undefined;

    return {
      attributes: {
        p_displayName: d.description || item.value || "",
        p_externalImageReference: d.image_url || null,
        p_productid: d.id || "",
        PROMOTION: promoText,
        SAVE: badges.SAVE ? "true" : undefined,
      },
      startingPrice: {
        p_pl10: d.p10 || null,
        p_pl10_wp: d.p10_wp || 0,
        p_pl30: d.p30 || null,
        p_pl30_wp: d.p30_wp || 0,
        p_pl60: d.p60 || null,
        p_pl60_wp: d.p60_wp || 0,
      },
    };
  });

  return { records, totalResults };
}

// ── Product Fetching (Browse) ────────────────────────────────────────────────

async function fetchProducts(
  cookies: Map<string, string>,
  options: { category?: string; page: number; pageSize: number },
): Promise<{
  records: any[];
  totalResults: number | null;
  httpStatus: number;
}> {
  const { category, page, pageSize } = options;
  const offset = page * pageSize;

  const categoryName = category || Object.keys(CATEGORIES)[0];
  const categoryCode = CATEGORIES[categoryName] || Object.values(CATEGORIES)[0];
  const pageURL = `/cat/Food/${categoryName}/_/N-${categoryCode}`;

  const params = new URLSearchParams({
    pageURL,
    No: String(offset),
    Nrpp: String(pageSize),
  });

  console.log(`[Woolworths] Fetching: ${SEARCH_URL}?${params}`);

  const resp = await fetch(`${SEARCH_URL}?${params}`, {
    headers: {
      Accept: "application/json, text/plain, */*",
      "User-Agent": USER_AGENT,
      "x-requested-by": "Woolworths Online",
      Cookie: cookieString(cookies),
      Referer: `${BASE_URL}/cat/Food/Fruit-Vegetables-Salads/_/N-lllnam`,
    },
  });

  if (!resp.ok) {
    const text = await resp.text();
    console.error(
      `[Woolworths] searchCategory ${resp.status}: ${text.substring(0, 200)}`,
    );
    return { records: [], totalResults: null, httpStatus: resp.status };
  }

  const data = await resp.json();

  // Response structure (from working scraper):
  //   data.contents[0].mainContent[0].contents[0].records[]
  let records: any[] = [];
  let totalResults: number | null = null;

  try {
    const contents = data.contents?.[0] || {};
    const mainContent = contents.mainContent?.[0] || {};
    const recordsContainer = mainContent.contents?.[0] || {};
    records = recordsContainer.records || [];

    // Total count from secondaryContent
    try {
      const secondary = contents.secondaryContent?.[0] || {};
      const categoryDims = secondary.categoryDimensions?.[0] || {};
      totalResults =
        categoryDims.count || recordsContainer.totalNumRecs || null;
    } catch {
      /* ignore */
    }
  } catch {
    // Fallback: try direct records on mainContent
    const mc = data.contents?.[0]?.mainContent?.[0] || {};
    records = mc.records || [];
    totalResults = mc.totalNumRecs || null;
  }

  return { records, totalResults, httpStatus: resp.status };
}

// ── Product Normalization ────────────────────────────────────────────────────

function normalizeProduct(item: any): NormalizedProduct {
  const attrs = item.attributes || {};

  const name = attrs.p_displayName || "Unknown Product";

  // Price: p_pl10 is the standard online price
  const priceVal = item.startingPrice?.p_pl10;
  const price = priceVal ? `R${priceVal}` : "Price not available";

  // Promotion
  const promotionPrice = attrs.PROMOTION || "No promo";

  // Image
  const imageUrl = attrs.p_externalImageReference || null;

  return {
    name,
    price,
    promotion_price: promotionPrice,
    retailer: "Woolworths",
    image_url: imageUrl,
    promotion_valid: "",
  };
}

// ── Main Handler ─────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  try {
    const body = await req.json();
    const {
      place_id,
      place_nickname,
      category,
      page = 0,
      page_size = DEFAULT_PAGE_SIZE,
      query,
    } = body;

    console.log(
      `[Woolworths] place=${place_nickname || "none"}, page=${page}, query=${query || category || "default"}`,
    );

    // Step 1: Create session via confirmPlace (only needed for browse, not search)
    let session: { cookies: Map<string, string>; error?: string } = {
      cookies: new Map(),
    };

    if (!query) {
      // Browse mode requires confirmPlace for location-specific pricing
      if (!place_id || !place_nickname) {
        return new Response(
          JSON.stringify({
            error: "place_id and place_nickname are required for browsing",
            hint: "For search, you can omit these. For browsing, get them from stores-nearby Edge Function.",
            example: {
              place_id: "ChIJt3cT6lVmlR4RQhVr-hreuuU",
              place_nickname: "2 Saltus Street",
            },
          }),
          {
            status: 400,
            headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
          },
        );
      }

      session = await createSession(place_id, place_nickname);
      if (session.error) {
        return new Response(
          JSON.stringify({
            error: "Failed to create Woolworths session",
            detail: session.error,
          }),
          {
            status: 502,
            headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
          },
        );
      }
    }

    // Step 2: Fetch products — search uses Constructor.io, browse uses searchCategory
    let records: any[];
    let totalResults: number | null;
    let source: string;

    if (query) {
      // Search via Constructor.io (public API, no cookies needed)
      const searchResult = await searchProducts(query, page, page_size);
      records = searchResult.records;
      totalResults = searchResult.totalResults;
      source = "constructor_search";
      console.log(
        `[Woolworths] Search got ${records.length} products (total: ${totalResults})`,
      );
    } else {
      // Browse via searchCategory (needs confirmPlace session)
      const browseResult = await fetchProducts(session.cookies, {
        category,
        page,
        pageSize: page_size,
      });
      records = browseResult.records;
      totalResults = browseResult.totalResults;
      source = "live_browse";
      console.log(
        `[Woolworths] Browse got ${records.length} products (total: ${totalResults}, HTTP: ${browseResult.httpStatus})`,
      );

      if (records.length === 0 && browseResult.httpStatus !== 200) {
        return new Response(
          JSON.stringify({
            error: "Woolworths API failed",
            http_status: browseResult.httpStatus,
          }),
          {
            status: 502,
            headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
          },
        );
      }
    }

    // Step 3: Normalize
    const products = records.map(normalizeProduct);
    const totalPages = totalResults
      ? Math.ceil(totalResults / page_size)
      : null;

    const response: ProductsResponse = {
      products,
      pagination: {
        current_page: page,
        total_pages: totalPages,
        total_results: totalResults,
        page_size: products.length,
      },
      retailer: "Woolworths",
      source,
      categories: Object.keys(CATEGORIES),
    };

    return new Response(JSON.stringify(response), {
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error(`[Woolworths] Error: ${(e as Error).message}`);
    return new Response(
      JSON.stringify({ error: "Internal error", detail: (e as Error).message }),
      {
        status: 500,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      },
    );
  }
});
