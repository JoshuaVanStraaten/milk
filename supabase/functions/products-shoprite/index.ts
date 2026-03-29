// supabase/functions/products-shoprite/index.ts
//
// Shoprite Live Product API Proxy
// Uses the CSRF bypass method (pure HTTP, no Playwright needed)
//
// Flow:
//   1. Create session -> get cookies (JSESSIONID, AWSALB, etc.)
//   2. Set preferred store via store code
//   3. Fetch product listing page (HTML)
//   4. Parse products from data-product-ga JSON attributes
//   5. Extract CSRF token + productListJSON from HTML
//   6. Call heavy attributes API for promotion enrichment
//   7. Return normalized product JSON

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { checkRateLimit } from "../_shared/rate_limiter.ts";

const BASE_URL = "https://www.shoprite.co.za";
const IMAGE_PROXY_BASE = "https://pjqbvrluyvqvpegxumsd.supabase.co/functions/v1/image-proxy";
const BROWSE_PATH = "/c-2256/All-Departments";
const FOOD_BROWSE_PATH = "/c-2413/All-Departments/Food";

// Maps display category names → Shoprite Hybris allCategories facet values.
// Facets derived from shoprite_query.sh category list (display name → lowercase + underscores).
// Multiple facets per category are chained in the URL (see buildProductUrl).
const SHOPRITE_CATEGORIES: Record<string, string[]> = {
  "Fruit & Veg": ["fresh_fruit", "fresh_vegetables", "fresh_salad_herbs_and_dip"],
  "Meat & Poultry": ["fresh_meat_and_poultry", "frozen_meat_and_poultry"],
  "Dairy & Eggs": ["milk_butter_and_eggs", "yoghurt", "cheese", "long_life_milk_and_dairy_alternatives"],
  "Bakery": ["bakery", "bread_and_rolls", "from_our_bakery"],
  "Frozen": ["frozen_food", "frozen_vegetables", "frozen_fish_and_seafood", "frozen_pies_and_party_food"],
  "Food Cupboard": ["food_cupboard", "cooking_ingredients", "canned_food", "breakfast_cereals_porridge_and_pap", "rice_pasta_noodles_and_cous_cous", "spreads_honey_and_preserves", "baking"],
  "Snacks": ["chocolates_and_sweets", "chips_snacks_and_popcorn", "biscuits_cookies_and_cereal_bars", "crackers_and_crispbreads", "biltong_dried_fruit_nuts_and_seeds"],
  // Shoprite beverages live under all-departments (not food path) — uses BROWSE_PATH
  "Beverages": ["drinks", "soft_drinks", "juices_and_smoothies", "coffee", "tea", "bottled_water"],
};
const HEAVY_ATTRS_PATH = "/populateProductsWithHeavyAttributes";
const SET_STORE_PATH = "/store-finder/setPreferredStore";

const USER_AGENT =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "https://sfnavipqilqgzmtedfuh.supabase.co",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
"authorization, x-client-info, apikey, content-type",
};

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
}

// Cookie Management
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

// Session Management
async function createSession(
  storeCode: string,
): Promise<{ cookies: Map<string, string>; error?: string }> {
  const cookies = new Map<string, string>();

  // Step 1: Visit main page for cookies
  try {
    const initResp = await fetch(BASE_URL, {
      headers: {
"User-Agent": USER_AGENT,
Accept:
"text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
"Accept-Language": "en-US,en;q=0.9",
      },
      redirect: "follow",
    });
    extractCookies(initResp, cookies);
    await initResp.text();
    if (cookies.size === 0)
return { cookies, error: "No cookies received from initial page load" };
  } catch (e) {
    return {
cookies,
error: `Initial page load failed: ${(e as Error).message}`,
    };
  }

  // Step 2: Set preferred store
  try {
    const storeResp = await fetch(
      `${BASE_URL}${SET_STORE_PATH}?preferredStoreName=${storeCode}`,
{
        headers: {
"User-Agent": USER_AGENT,
Cookie: cookieString(cookies),
Accept:
"text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        },
        redirect: "follow",
      },
    );
    extractCookies(storeResp, cookies);
    await storeResp.text();
  } catch (e) {
    return {
cookies,
error: `Store selection failed: ${(e as Error).message}`,
    };
  }

  return { cookies };
}

// HTML Parsing

function extractCsrfToken(html: string): string | null {
  const m = html.match(/name=["']CSRFToken["']\s+value=["']([a-f0-9-]+)["']/i);
  if (m) return m[1];
  const m2 = html.match(/CSRFToken["'\s:=]+["']([a-f0-9-]+)["']/);
  return m2 ? m2[1] : null;
}

function extractProductListJson(html: string): string | null {
  const m = html.match(/productListJSON">\s*([\[{][\s\S]*?[\]}])\s*<\/div>/);
  return m ? m[1].trim() : null;
}

// Rewrite a retailer image URL to use the image proxy (which auto-caches to Storage).
function rewriteImageUrl(originalUrl: string): string {
  const codeMatch = originalUrl.match(/(\d{5,}[A-Z]{2}(?:[Vv]\d)?)/);
  if (codeMatch) {
    return `${IMAGE_PROXY_BASE}?url=${encodeURIComponent(originalUrl)}`;
  }
  return originalUrl;
}

function parseProductsFromHtml(
  html: string,
): Array<{
name: string;
price: string;
image_url: string | null;
productCode: string;
}> {
  const products: Array<{
name: string;
price: string;
image_url: string | null;
productCode: string;
  }> = [];
  const gaRegex = /data-product-ga='(\{[^']+\})'/g;
  let match;

  while ((match = gaRegex.exec(html)) !== null) {
    try {
      const ga = JSON.parse(match[1]);
      if (!ga.name) continue;
      const price =
ga.unit_sale_price || ga.price
? `R${ga.unit_sale_price || ga.price}`
: "Price not available";
      let imageUrl = ga.product_image_url || null;
      if (imageUrl && !imageUrl.startsWith("http"))
        imageUrl = `${BASE_URL}${imageUrl}`;

      // Rewrite to proxy URL — the proxy auto-caches to Supabase Storage
      if (imageUrl) {
        imageUrl = rewriteImageUrl(imageUrl);
      }

      products.push({
        name: ga.name
          .replace(/&amp;/g, "&")
          .replace(/&lt;/g, "<")
          .replace(/&gt;/g, ">")
          .replace(/&quot;/g, '"')
          .replace(/&#39;/g, "'")
          .replace(/&nbsp;/g, " "),
        price,
        image_url: imageUrl,
        productCode: ga.id || "",
      });
    } catch {
continue;
}
  }
  return products;
}

function extractTotalPages(html: string): number | null {
  const pm = html.match(
    /<ul[^>]*class="[^"]*pagination[^"]*"[^>]*>([\s\S]*?)<\/ul>/i,
  );
  if (!pm) return null;
  const nums: number[] = [];
  const liRe = /<li[^>]*>[\s\S]*?<\/li>/gi;
  let lm;
  while ((lm = liRe.exec(pm[1])) !== null) {
    const n = parseInt(lm[0].replace(/<[^>]+>/g, "").trim());
    if (!isNaN(n)) nums.push(n);
  }
  return nums.length > 0 ? Math.max(...nums) : null;
}

// Heavy Attributes
async function fetchHeavyAttributes(
  cookies: Map<string, string>,
csrfToken: string,
productListJson: string,
): Promise<any[] | null> {
  try {
    const resp = await fetch(`${BASE_URL}${HEAVY_ATTRS_PATH}`, {
      method: "POST",
      headers: {
        "User-Agent": USER_AGENT,
Cookie: cookieString(cookies),
csrftoken: csrfToken,
        "Content-Type": "application/json",
Accept: "text/plain, */*; q=0.01",
        "X-Requested-With": "XMLHttpRequest",
Origin: BASE_URL,
Referer: `${BASE_URL}${BROWSE_PATH}`,
      },
      body: productListJson,
    });
    if (!resp.ok) {
console.error(`Heavy attrs: ${resp.status}`);
return null;
}
    const data = await resp.json();
    return Array.isArray(data) ? data : null;
  } catch (e) {
console.error(`Heavy attrs error: ${(e as Error).message}`);
return null;
}
}

// Normalization
function normalizeProducts(
  htmlProducts: Array<{
name: string;
price: string;
image_url: string | null;
productCode: string;
  }>,
  heavyAttrs: any[] | null,
): NormalizedProduct[] {
  return htmlProducts.map((product, index) => {
    const heavy =
heavyAttrs && index < heavyAttrs.length ? heavyAttrs[index] : null;
    let promotionPrice = "No promo";
    let promotionValid = "";

    if (heavy) {
      const info = heavy.information?.[0] || {};
      const salePrice = info.salePrice;
      if (
        salePrice !== undefined &&
salePrice !== null &&
salePrice !== "" &&
!Number.isNaN(salePrice)
      ) {
        promotionPrice = `R${salePrice}`;
      }
      const bonusBuys = info.includedInBonusBuys || [];
      if (bonusBuys.length > 0 && promotionPrice === "No promo") {
        const bundleName = bonusBuys[0]?.name;
        if (bundleName) promotionPrice = String(bundleName);
      }
      const htmlBBs = info.htmlBBs || "";
      if (htmlBBs) {
        const vm = htmlBBs.match(/item-product__valid[^>]*>([^<]+)/i);
        if (vm)
promotionValid = vm[1]
            .replace(/&nbsp;/g, " ")
            .replace(/\s+/g, " ")
            .trim();
      }
    }

    return {
     name: product.name,
     price: product.price,
     promotion_price: promotionPrice,
     retailer: "Shoprite",
     image_url: product.image_url,
     promotion_valid: promotionValid,
    };
  });
}

// URL Building
function buildProductUrl(
  page: number,
  query?: string,
  category?: string,
): string {
  if (query) {
    // Search mode: use Shoprite faceted search
    const searchQuery = `${query}:relevance:browseAllStoresFacetOff:browseAllStoresFacetOff:allCategories:${category || "all_departments"}`;
    return `${BASE_URL}/search?q=${encodeURIComponent(searchQuery)}&page=${page}`;
  }
  // Browse mode: chain multiple allCategories facets for the category.
  // Single facet:  :relevance:browseAllStoresFacetOff:browseAllStoresFacetOff:allCategories:bakery
  // Multi-facet:   :relevance:allCategories:fresh_fruit:browseAllStoresFacetOff:browseAllStoresFacetOff:allCategories:fresh_vegetables
  const facets = category ? SHOPRITE_CATEGORIES[category] : null;
  if (facets && facets.length > 0) {
    let q: string;
    if (facets.length === 1) {
      q = `:relevance:browseAllStoresFacetOff:browseAllStoresFacetOff:allCategories:${facets[0]}`;
    } else {
      // Chain: :relevance:allCategories:<f1>:browseAllStoresFacetOff:browseAllStoresFacetOff:allCategories:<f2>...
      q = `:relevance:allCategories:${facets[0]}` +
        facets.slice(1).map(f => `:browseAllStoresFacetOff:browseAllStoresFacetOff:allCategories:${f}`).join("");
    }
    // Beverages live under the general all-departments path, not the food path
    const browsePath = category === "Beverages" ? BROWSE_PATH : FOOD_BROWSE_PATH;
    return `${BASE_URL}${browsePath}?q=${encodeURIComponent(q)}&page=${page}`;
  }
  return `${BASE_URL}${BROWSE_PATH}?q=:relevance&page=${page}`;
}

// Main Handler
serve(async (req: Request) => {
  if (req.method === "OPTIONS")
   return new Response(null, { status: 204, headers: CORS_HEADERS });

  const rateLimited = checkRateLimit(req, CORS_HEADERS);
  if (rateLimited) return rateLimited;

  try {
    const body = await req.json();
    const { store_code, page = 0, query, category } = body;

    if (!store_code) {
      return new Response(
        JSON.stringify({
         error: "store_code is required",
         hint: "Get store codes from stores-nearby Edge Function",
        }),
        {
         status: 400,
         headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    console.log(
      `[Shoprite] store=${store_code}, page=${page}, query=${query || "browse"}`,
    );

    const session = await createSession(store_code);
    if (session.error) {
      return new Response(
        JSON.stringify({
         error: "Failed to create Checkers session",
         detail: session.error,
        }),
        {
         status: 502,
         headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    const productUrl = buildProductUrl(page, query, category);
    console.log(`[Shoprite] Fetching: ${productUrl}`);

    const pageResp = await fetch(productUrl, {
      headers: {
       "User-Agent": USER_AGENT,
       Cookie: cookieString(session.cookies),
       Accept:
         "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
       "Accept-Language": "en-US,en;q=0.9",
      },
      redirect: "follow",
    });

    if (!pageResp.ok) {
      return new Response(
        JSON.stringify({
         error: `Checkers returned ${pageResp.status}`,
         url: productUrl,
        }),
        {
         status: 502,
         headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    extractCookies(pageResp, session.cookies);
    const html = await pageResp.text();

    const htmlProducts = parseProductsFromHtml(html);
    console.log(`[Shoprite] Parsed ${htmlProducts.length} products`);

    const csrfToken = extractCsrfToken(html);
    console.log(
      `[Shoprite] CSRF: ${csrfToken ? csrfToken.substring(0, 12) + "..." : "NOT FOUND"}`,
    );

    let heavyAttrs: any[] | null = null;
    if (csrfToken) {
      const productListJson = extractProductListJson(html);
      if (productListJson) {
        console.log(
          `[Shoprite] productListJSON: ${productListJson.length} chars`,
        );
        heavyAttrs = await fetchHeavyAttributes(
          session.cookies,
         csrfToken,
         productListJson,
        );
        console.log(
          `[Shoprite] Heavy attrs: ${heavyAttrs ? heavyAttrs.length + " items" : "FAILED"}`,
        );
      }
    }

    const products = normalizeProducts(htmlProducts, heavyAttrs);
    const totalPages = extractTotalPages(html);

    const response: ProductsResponse = {
      products,
      pagination: {
       current_page: page,
       total_pages: totalPages,
       total_results: null,
       page_size: products.length,
      },
      retailer: "Shoprite",
      source: heavyAttrs ? "live_enriched" : "live_basic",
    };

    return new Response(JSON.stringify(response), {
     headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error(`[Shoprite] Error: ${(e as Error).message}`);
    return new Response(
      JSON.stringify({ error: "Internal error", detail: (e as Error).message }),
      {
       status: 500,
       headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      },
    );
  }
});
