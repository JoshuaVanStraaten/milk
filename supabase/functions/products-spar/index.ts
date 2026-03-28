// supabase/functions/products-spar/index.ts
//
// KwikSPAR Live Product API Proxy
// Uses CSRF token + session cookies (similar to Checkers pattern)
//
// Flow:
//   1. GET store homepage -> extract CSRF token from <meta> tag + session cookies
//   2. POST /shop/searchproduct with CSRF token + cookies
//   3. Parse returnProduct array + extract images from html field
//   4. Normalize product names (strip barcodes, Title Case) and return
//
// POST body: {
//   "store_code": "hillcrest",    // Required: KwikSPAR store identifier
//   "query": "milk",              // Optional: search term (omit for browse)
//   "category": "Dairy & Eggs",   // Optional: display category name
//   "page": 0,                    // Optional: page number (0-indexed)
//   "page_size": 48               // Optional: items per page
// }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

// ── Store domains ──────────────────────────────────────────────────────────────
const STORES: Record<string, string> = {
  hillcrest: "https://hillcrestkwikspar.co.za",
  glenore: "https://www.glenorekwikspar.co.za",
};
const PRIMARY_STORE = "hillcrest";
const FALLBACK_STORE = "glenore";

// ── Category mapping: our display names -> KwikSPAR slugs ──────────────────────
const SPAR_CATEGORIES: Record<string, string[]> = {
  "Fruit & Veg": [
    "fruit", "produce", "hard-vegetables", "salad",
    "herbs-chillies-garlic-microherbs", "mushrooms", "cut-fruit", "ready-veg",
  ],
  "Meat & Poultry": [
    "beef", "chicken", "lamb", "pork", "butchery", "butchery-deals",
    "bacon", "polony", "viennas", "venison-ostrich", "biltong",
  ],
  "Dairy & Eggs": [
    "milk", "butter", "eggs", "cheese", "cream-and-cream-cheese",
    "feta", "yoghurt", "margarine",
  ],
  "Bakery": [
    "bakery", "baked-goods", "bread", "rollsbreads",
    "frozen-baked-goods", "rusks",
  ],
  "Frozen": [
    "frozen", "frozens", "frozen-chickenpork", "frozen-fish",
    "frozen-meals", "frozen-pizza-wraps", "frozen-veg", "frozen-fruit",
    "frozen-ice-cream-desserts-lollies", "frozen-burgers", "frozen-pastry",
  ],
  "Food Cupboard": [
    "pasta", "rice", "canned-food", "canned-fish", "canned-vegetables",
    "canned-fruit", "flour", "baking-aids", "cereals", "porridge", "oats",
    "muesli", "granola", "sauces", "pasta-sauces", "spices-and-seasonings",
    "oil", "olive-oil", "sugar", "jams", "spreads", "honey", "soup",
    "maize-meal-samp", "couscous",
  ],
  "Snacks": [
    "chips", "biscuits", "savoury-snacks", "nuts-snacks", "popcorn",
  ],
  "Beverages": [
    "coffee", "tea", "carbonated-drinks", "fruit-juices", "bottled-water",
    "energy-drinks", "cordials", "iced-coffee", "tonic-soda-water",
    "cold-drinks-aisle",
  ],
};

// ── CORS ────────────────────────────────────────────────────────────────────────
const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "https://sfnavipqilqgzmtedfuh.supabase.co",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const USER_AGENT =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36";

// ── Session cache (in-memory, 20-min TTL) ───────────────────────────────────────
interface CachedSession {
  csrfToken: string;
  cookies: string;
  createdAt: number;
}

const SESSION_TTL_MS = 20 * 60 * 1000; // 20 minutes
const sessionCache = new Map<string, CachedSession>();

function getCachedSession(baseUrl: string): CachedSession | null {
  const cached = sessionCache.get(baseUrl);
  if (!cached) return null;
  if (Date.now() - cached.createdAt > SESSION_TTL_MS) {
    sessionCache.delete(baseUrl);
    return null;
  }
  return cached;
}

// ── Cookie helpers ──────────────────────────────────────────────────────────────
function extractCookies(
  response: Response,
  existing: Map<string, string>,
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
      existing.set(
        parts.substring(0, eqIdx).trim(),
        parts.substring(eqIdx + 1).trim(),
      );
    }
  }
  return existing;
}

function cookieString(cookies: Map<string, string>): string {
  return Array.from(cookies.entries())
    .map(([k, v]) => `${k}=${v}`)
    .join("; ");
}

// ── Session creation ────────────────────────────────────────────────────────────
async function createSession(
  baseUrl: string,
): Promise<{ csrfToken: string; cookies: string } | null> {
  // Check cache first
  const cached = getCachedSession(baseUrl);
  if (cached) {
    console.log(`[SPAR] Using cached session for ${baseUrl}`);
    return { csrfToken: cached.csrfToken, cookies: cached.cookies };
  }

  console.log(`[SPAR] Creating new session for ${baseUrl}`);
  const cookieJar = new Map<string, string>();

  try {
    const resp = await fetch(`${baseUrl}/shop/`, {
      headers: {
        "User-Agent": USER_AGENT,
        Accept:
          "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.9",
      },
      redirect: "follow",
    });

    if (!resp.ok) {
      console.error(`[SPAR] Session page returned ${resp.status}`);
      return null;
    }

    extractCookies(resp, cookieJar);
    const html = await resp.text();

    // Extract CSRF token from <meta name="csrf-token" content="...">
    const csrfMatch = html.match(
      /<meta\s+name=["']csrf-token["']\s+content=["']([^"']+)["']/i,
    );
    if (!csrfMatch) {
      console.error("[SPAR] Could not extract CSRF token from homepage");
      return null;
    }

    const csrfToken = csrfMatch[1];
    const cookies = cookieString(cookieJar);

    if (cookieJar.size === 0) {
      console.error("[SPAR] No cookies received from session page");
      return null;
    }

    // Cache the session
    sessionCache.set(baseUrl, {
      csrfToken,
      cookies,
      createdAt: Date.now(),
    });

    console.log(
      `[SPAR] Session created: CSRF=${csrfToken.substring(0, 12)}..., cookies=${cookieJar.size} entries`,
    );
    return { csrfToken, cookies };
  } catch (e) {
    console.error(`[SPAR] Session creation failed: ${(e as Error).message}`);
    return null;
  }
}

// ── Product search ──────────────────────────────────────────────────────────────
interface SparRawProduct {
  item_id: string;
  item_name: string;
  price: number;
  currency?: string;
}

interface SparSearchResponse {
  count: number;
  totalProduct: number;
  isshowlaodmore: boolean;
  nextPage: number;
  returnProduct: SparRawProduct[];
  html: string;
}

async function searchProducts(
  baseUrl: string,
  csrfToken: string,
  cookies: string,
  query: string,
  categorySlug: string,
  pageno: number,
  globalSearch: boolean,
): Promise<SparSearchResponse | null> {
  const body = new URLSearchParams({
    productname: query,
    category_slug: categorySlug,
    orderBy: "",
    reference: "",
    pageno: String(pageno),
    globalsearch: String(globalSearch),
  });

  try {
    const resp = await fetch(`${baseUrl}/shop/searchproduct`, {
      method: "POST",
      headers: {
        "User-Agent": USER_AGENT,
        "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
        "X-CSRF-TOKEN": csrfToken,
        "X-Requested-With": "XMLHttpRequest",
        Cookie: cookies,
        Accept: "application/json, text/javascript, */*; q=0.01",
        Origin: baseUrl,
        Referer: `${baseUrl}/shop/`,
      },
      body: body.toString(),
    });

    if (!resp.ok) {
      const errText = await resp.text();
      console.error(
        `[SPAR] Search API returned ${resp.status}: ${errText.substring(0, 200)}`,
      );
      // Invalidate cached session on auth-related errors
      if (resp.status === 401 || resp.status === 419 || resp.status === 403) {
        sessionCache.delete(baseUrl);
      }
      return null;
    }

    return await resp.json();
  } catch (e) {
    console.error(`[SPAR] Search request failed: ${(e as Error).message}`);
    return null;
  }
}

// ── Name normalization ──────────────────────────────────────────────────────────

// Capitalize first letter of each word (for slug-derived names)
function capitalize(name: string): string {
  return name.replace(/\b\w/g, (char) => char.toUpperCase());
}

// Strip barcode suffix (SK followed by 10-16 digits)
function stripBarcode(name: string): string {
  return name.replace(/\s*SK\d{10,16}$/i, "").trim();
}

// Convert ALL CAPS to Title Case, keeping size units lowercase
// e.g. "ALBANY BEST OF BOTH 700G" -> "Albany Best Of Both 700g"
function toTitleCase(name: string): string {
  // Only convert if the name is predominantly uppercase
  const upperCount = (name.match(/[A-Z]/g) || []).length;
  const letterCount = (name.match(/[A-Za-z]/g) || []).length;
  if (letterCount === 0 || upperCount / letterCount < 0.7) return name;

  return name
    .toLowerCase()
    .replace(/\b\w/g, (char) => char.toUpperCase())
    // Keep size units lowercase: 500g, 2L, 1.5l, 750ml, 1kg, 6x500ml, etc.
    .replace(
      /\b(\d+(?:\.\d+)?)\s*(G|G|Kg|KG|Ml|ML|L|Ltr|Pk|Pack)\b/gi,
      (_match, num, unit) => `${num}${unit.toLowerCase()}`,
    )
    // Handle patterns like "6X500Ml" -> "6x500ml"
    .replace(
      /\b(\d+)[Xx](\d+(?:\.\d+)?)\s*(G|Kg|Ml|L)\b/gi,
      (_match, count, num, unit) => `${count}x${num}${unit.toLowerCase()}`,
    );
}

// Extract ALL product image URLs from the html field in order.
// Deduplicates consecutive/duplicate URLs since KwikSPAR HTML may
// include the same image twice per product (e.g. thumbnail + lazy-load).
function extractAllImageUrls(html: string): string[] {
  if (!html) return [];
  const urls: string[] = [];
  const seen = new Set<string>();
  const regex = /src="(https?:\/\/[^"]*\/images\/products\/thumb_[^"]*)"/gi;
  let m: RegExpExecArray | null;
  while ((m = regex.exec(html)) !== null) {
    const url = m[1];
    if (!seen.has(url)) {
      seen.add(url);
      urls.push(url);
    }
  }
  return urls;
}

// Extract a map of product name → image URL from the HTML.
// KwikSPAR HTML has product-box divs each containing:
//   <img src="...thumb_..."> and <h2>PRODUCT NAME</h2>
// The JSON returnProduct and HTML are in DIFFERENT orders and use
// DIFFERENT IDs, so we must match by product name.
function extractImageMapByName(html: string): Map<string, string> {
  const map = new Map<string, string>();
  if (!html) return map;

  // Split HTML into product blocks
  const blocks = html.split('<div class="product-box"');

  for (const block of blocks) {
    // Extract image URL
    const imgMatch = block.match(
      /src="(https?:\/\/[^"]*\/images\/products\/thumb_[^"]*)"/i,
    );
    if (!imgMatch) continue;

    // Extract product name from <h2>...</h2>
    const nameMatch = block.match(/<h2>([^<]+)<\/h2>/i);
    if (!nameMatch) continue;

    // Normalize name for matching: lowercase, trim
    const name = nameMatch[1].trim().toLowerCase();
    map.set(name, imgMatch[1]);
  }

  console.log(`[SPAR] Extracted ${map.size} name→image pairs from HTML`);
  return map;
}

// ── Product normalization ───────────────────────────────────────────────────────
interface NormalizedProduct {
  name: string;
  price: string;
  promotion_price: string;
  retailer: string;
  image_url: string | null;
  promotion_valid: string;
}

function normalizeProducts(
  rawProducts: SparRawProduct[],
  htmlPages: string[],
): NormalizedProduct[] {
  // Match images to products by name.
  // The HTML <h2> contains the full product name (same as returnProduct.item_name)
  // but HTML and JSON are in DIFFERENT orders, so positional matching is wrong.
  // We merge image maps from multiple HTML pages for better coverage.
  const nameImageMap = new Map<string, string>();
  for (const html of htmlPages) {
    const pageMap = extractImageMapByName(html);
    for (const [name, url] of pageMap) {
      nameImageMap.set(name, url);
    }
  }

  return rawProducts.map((item) => {
    // Clean up product name
    const rawName = item.item_name || "Unknown product";
    let name = stripBarcode(rawName);
    name = toTitleCase(name);

    // Format price
    const price =
      item.price !== undefined && item.price !== null
        ? `R${Number(item.price).toFixed(2)}`
        : "Price not available";

    // Match image by raw product name (lowercase, as stored in map)
    const image_url = nameImageMap.get(rawName.trim().toLowerCase()) || null;

    return {
      name,
      price,
      promotion_price: "No promo",
      promotion_valid: "",
      retailer: "SPAR",
      image_url,
    };
  });
}

// ── Catalogue specials scraping (my-catalogue.co.za) ────────────────────────

const SPECIALS_URL = "https://my-catalogue.co.za/spar-specials";
const CATALOGUE_URL =
  "https://my-catalogue.co.za/spar-specials/spar-catalogue";
const CATALOGUE_TTL_MS = 6 * 60 * 60 * 1000; // 6 hours

interface CachedCatalogue {
  products: NormalizedProduct[];
  createdAt: number;
}

let catalogueCache: CachedCatalogue | null = null;

/**
 * Extract product images from the catalogue page's window.__INITIAL_STATE.
 * Returns a map of product slug → image URL.
 */
function extractCatalogueImages(
  html: string,
): Map<string, string> {
  const imageMap = new Map<string, string>();

  const stateMatch = html.match(
    /window\.__INITIAL_STATE\s*=\s*(\{[\s\S]*?\});/,
  );
  if (!stateMatch) return imageMap;

  try {
    const state = JSON.parse(stateMatch[1]) as {
      productsByPages?: Record<string, unknown[]>;
    };
    const pages = state.productsByPages || {};
    for (const pageProducts of Object.values(pages)) {
      if (!Array.isArray(pageProducts)) continue;
      for (const product of pageProducts) {
        const p = product as { buttonLink?: string; image?: string };
        if (p.buttonLink && p.image) {
          // Extract slug from buttonLink like "https://my-catalogue.co.za/products/chicken"
          const slugMatch = p.buttonLink.match(/\/products\/([^?#]+)/);
          if (slugMatch) {
            const imageUrl = p.image.startsWith("http")
              ? p.image
              : `https://my-catalogue.co.za${p.image}`;
            imageMap.set(slugMatch[1], imageUrl);
          }
        }
      }
    }
  } catch (e) {
    console.error(
      `[SPAR] Failed to parse __INITIAL_STATE: ${(e as Error).message}`,
    );
  }

  return imageMap;
}

/**
 * Extract products from the specials listing page.
 * The listing page has product names, prices, and links in the HTML.
 *
 * Uses multiple extraction strategies since HTML structure varies:
 * 1. Links to /products/slug with title or alt text + nearby R price
 * 2. Anchor tags with product slugs + price text in parent container
 */
function extractSpecialsFromListing(
  html: string,
  catalogueImages: Map<string, string>,
): NormalizedProduct[] {
  const products: NormalizedProduct[] = [];
  const seen = new Set<string>();

  // Extract validity dates from the page (e.g., "23/03 - 07/04/2026")
  const dateMatch = html.match(
    /(\d{2}\/\d{2})\s*-\s*(\d{2}\/\d{2}\/\d{4})/,
  );
  let validUntil = "";
  if (dateMatch) {
    try {
      const [day, month] = dateMatch[2].split("/");
      const months = [
        "", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
      ];
      validUntil = `Valid until ${parseInt(day)} ${months[parseInt(month)]}`;
    } catch {
      validUntil = "";
    }
  }

  // Strategy 1: Find <a> tags linking to /products/slug with title attr
  // Pattern: <a href="/products/slug" title="Product Name">
  const linkTitleRegex =
    /<a[^>]+href="[^"]*\/products\/([\w-]+)[^"]*"[^>]*title="([^"]{2,})"[^>]*>/gi;

  let m: RegExpExecArray | null;
  while ((m = linkTitleRegex.exec(html)) !== null) {
    const slug = m[1];
    const name = m[2].trim();
    if (seen.has(slug)) continue;
    seen.add(slug);

    const imageUrl = catalogueImages.get(slug) || null;
    products.push({
      name: capitalize(name),
      price: "Price not available",
      promotion_price: "Price not available",
      promotion_valid: validUntil,
      retailer: "SPAR",
      image_url: imageUrl,
    });
  }

  // Strategy 2: Find all /products/slug links and nearby R XX.XX prices
  // Search for price patterns near product slug references
  // Split HTML into chunks around product links and extract prices
  const slugPriceRegex =
    /\/products\/([\w-]+)(?:[^"]*?)["'][^]*?R\s*(\d+[.,]\d{2})/gi;

  while ((m = slugPriceRegex.exec(html)) !== null) {
    const slug = m[1];
    const price = `R${m[2].replace(",", ".")}`;
    const key = `${slug}-${price}`.toLowerCase();

    if (seen.has(key)) continue;
    seen.add(key);
    seen.add(slug); // Also mark slug as seen

    // Find the existing product entry and update price, or create new
    const existing = products.find(
      (p) => p.name.toLowerCase().replace(/\s+/g, "-") === slug ||
        p.name.toLowerCase() === slug.replace(/-\d+$/, "").replace(/-/g, " "),
    );

    if (existing && existing.price === "Price not available") {
      existing.price = price;
      existing.promotion_price = price;
    } else if (!existing) {
      // Convert slug to display name: "baked-beans" → "Baked Beans"
      const name = capitalize(
        slug
          .replace(/-\d+$/, "") // Remove trailing numbers (e.g., "rice-3532")
          .replace(/-/g, " "),
      );

      const imageUrl = catalogueImages.get(slug) || null;

      products.push({
        name,
        price,
        promotion_price: price,
        promotion_valid: validUntil,
        retailer: "SPAR",
        image_url: imageUrl,
      });
    }
  }

  // Remove products still without prices
  const withPrices = products.filter((p) => p.price !== "Price not available");

  // If we got products with titles but no prices, still return them
  // (they'll show as deals without specific price)
  return withPrices.length > 0 ? withPrices : products.filter(
    (p) => p.name !== "Price not available",
  );
}

/**
 * Enrich specials with product images from the KwikSPAR API.
 * ONLY grabs images — does NOT replace product names or prices,
 * since KwikSPAR search results may be completely different products
 * from the catalogue specials.
 *
 * Batches 5 searches at a time to stay within timeout.
 */
async function enrichWithKwikSparImages(
  products: NormalizedProduct[],
): Promise<void> {
  const needImages = products.filter((p) => !p.image_url);
  if (needImages.length === 0) return;

  console.log(
    `[SPAR] Fetching images for ${needImages.length} products from KwikSPAR`,
  );

  // Get a session for KwikSPAR
  const session = await createSession(STORES[PRIMARY_STORE]);
  if (!session) {
    console.error("[SPAR] Could not create session for image fetch");
    return;
  }

  const baseUrl = STORES[PRIMARY_STORE];

  // Process in batches of 5
  for (let i = 0; i < needImages.length; i += 5) {
    const batch = needImages.slice(i, i + 5);
    await Promise.allSettled(
      batch.map(async (product) => {
        try {
          const data = await searchProducts(
            baseUrl,
            session.csrfToken,
            session.cookies,
            product.name,
            "",
            1,
            true,
          );

          if (!data) return;

          // Only grab the image — nothing else
          if (data.html) {
            const images = extractAllImageUrls(data.html);
            if (images.length > 0) {
              product.image_url = images[0];
            }
          }
        } catch (e) {
          // Silently skip — image fetch is best-effort
        }
      }),
    );
  }

  const enriched = products.filter((p) => p.image_url).length;
  console.log(
    `[SPAR] Image fetch complete: ${enriched}/${products.length} have images`,
  );
}

/**
 * Main catalogue specials fetch. Scrapes my-catalogue.co.za for
 * current SPAR promotional products with real prices.
 *
 * Fast approach: 2 HTTP requests total
 * 1. Fetch specials listing page → product names + prices
 * 2. Fetch catalogue page → product images from __INITIAL_STATE
 */
async function fetchCatalogueProducts(): Promise<NormalizedProduct[]> {
  // Check cache
  if (
    catalogueCache &&
    Date.now() - catalogueCache.createdAt < CATALOGUE_TTL_MS
  ) {
    console.log(
      `[SPAR] Using cached catalogue (${catalogueCache.products.length} products)`,
    );
    return catalogueCache.products;
  }

  console.log("[SPAR] Fetching specials from my-catalogue.co.za...");

  try {
    // Fetch both pages in parallel (only 2 requests!)
    const [specialsResp, catalogueResp] = await Promise.all([
      fetch(SPECIALS_URL, {
        headers: { "User-Agent": USER_AGENT, Accept: "text/html" },
      }),
      fetch(CATALOGUE_URL, {
        headers: { "User-Agent": USER_AGENT, Accept: "text/html" },
      }),
    ]);

    if (!specialsResp.ok) {
      console.error(
        `[SPAR] Specials page returned ${specialsResp.status}`,
      );
      return catalogueCache?.products ?? [];
    }

    const [specialsHtml, catalogueHtml] = await Promise.all([
      specialsResp.text(),
      catalogueResp.ok ? catalogueResp.text() : Promise.resolve(""),
    ]);

    // Extract images from catalogue page
    const catalogueImages = catalogueHtml
      ? extractCatalogueImages(catalogueHtml)
      : new Map<string, string>();

    console.log(
      `[SPAR] Found ${catalogueImages.size} product images in catalogue`,
    );

    // Extract products from specials listing
    const products = extractSpecialsFromListing(
      specialsHtml,
      catalogueImages,
    );

    console.log(
      `[SPAR] Extracted ${products.length} specials from listing page`,
    );

    // Enrich with images from KwikSPAR API (search for each product name)
    await enrichWithKwikSparImages(products);

    // Only keep products that have images
    const withImages = products.filter((p) => p.image_url);
    console.log(
      `[SPAR] Final: ${withImages.length} specials with images (dropped ${products.length - withImages.length} without)`,
    );

    // Cache results
    if (withImages.length > 0) {
      catalogueCache = {
        products: withImages,
        createdAt: Date.now(),
      };
    }

    return withImages;
  } catch (e) {
    console.error(
      `[SPAR] Catalogue fetch failed: ${(e as Error).message}`,
    );
    return catalogueCache?.products ?? [];
  }
}

// ── Attempt search against a specific store ─────────────────────────────────────
async function attemptStore(
  storeKey: string,
  query: string | undefined,
  category: string | undefined,
  page: number,
): Promise<{
  data: SparSearchResponse;
  baseUrl: string;
} | null> {
  const baseUrl = STORES[storeKey];
  if (!baseUrl) return null;

  const session = await createSession(baseUrl);
  if (!session) return null;

  // Determine search mode
  let searchQuery = "";
  let categorySlug = "";
  let globalSearch = true;

  if (query) {
    // Search mode: use query, ignore category slug
    searchQuery = query;
    globalSearch = true;
  } else if (category) {
    // Browse mode: use first slug from mapped category
    const slugs = SPAR_CATEGORIES[category];
    if (slugs && slugs.length > 0) {
      categorySlug = slugs[0];
      globalSearch = false;
    }
  }

  // Convert 0-indexed page to 1-indexed pageno
  const pageno = page + 1;

  const data = await searchProducts(
    baseUrl,
    session.csrfToken,
    session.cookies,
    searchQuery,
    categorySlug,
    pageno,
    globalSearch,
  );

  if (!data) return null;

  return { data, baseUrl };
}

// ── Main handler ────────────────────────────────────────────────────────────────
serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  try {
    const body = await req.json();
    const {
      store_code,
      query,
      category,
      page = 0,
      page_size = 48,
      specials = false,
    } = body;

    // ── Debug mode: return raw KwikSPAR HTML for analysis ──
    if (body.debug_html) {
      const session = await createSession(STORES[PRIMARY_STORE]);
      if (!session) {
        return new Response(JSON.stringify({ error: "No session" }), {
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        });
      }
      const data = await searchProducts(
        STORES[PRIMARY_STORE], session.csrfToken, session.cookies,
        "", "", 1, false,
      );
      return new Response(JSON.stringify({
        html_snippet: data?.html?.substring(0, 5000) || "no html",
        product_count: data?.returnProduct?.length || 0,
        first_3_products: data?.returnProduct?.slice(0, 3) || [],
      }), {
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    // ── Specials mode: scrape my-catalogue.co.za ──
    if (specials) {
      console.log("[SPAR] Fetching catalogue specials...");
      const products = await fetchCatalogueProducts();

      return new Response(
        JSON.stringify({
          products,
          pagination: {
            current_page: 0,
            total_pages: 1,
            total_results: products.length,
            page_size: products.length,
          },
          retailer: "SPAR",
          store_code: store_code || "national",
          source: "catalogue_specials",
          timestamp: new Date().toISOString(),
        }),
        {
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    if (!store_code) {
      return new Response(
        JSON.stringify({
          error: "store_code is required",
          hint: "Use a KwikSPAR store identifier (e.g. 'hillcrest', 'glenore')",
        }),
        {
          status: 400,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    console.log(
      `[SPAR] store=${store_code}, query="${query || "browse"}", category="${category || "all"}", page=${page}`,
    );

    // Try primary store first, then fallback
    let result = await attemptStore(PRIMARY_STORE, query, category, page);
    let usedStore = PRIMARY_STORE;

    if (!result) {
      console.log(
        `[SPAR] Primary store (${PRIMARY_STORE}) failed, trying fallback (${FALLBACK_STORE})`,
      );
      result = await attemptStore(FALLBACK_STORE, query, category, page);
      usedStore = FALLBACK_STORE;
    }

    if (!result) {
      return new Response(
        JSON.stringify({
          error: "Failed to fetch products from KwikSPAR",
          detail: "Both primary and fallback stores failed",
          retailer: "SPAR",
        }),
        {
          status: 502,
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        },
      );
    }

    const { data, baseUrl } = result;

    const products = normalizeProducts(data.returnProduct || [], [data.html || ""]);

    // Calculate pagination
    const totalResults = data.totalProduct || 0;
    const pageSize = data.count || products.length || page_size;
    const totalPages = pageSize > 0 ? Math.ceil(totalResults / pageSize) : 0;

    console.log(
      `[SPAR] Returned ${products.length} products (total: ${totalResults}, store: ${usedStore})`,
    );

    return new Response(
      JSON.stringify({
        products,
        pagination: {
          current_page: page,
          total_pages: totalPages,
          total_results: totalResults,
          page_size: pageSize,
        },
        retailer: "SPAR",
        store_code,
        source: "live",
        timestamp: new Date().toISOString(),
      }),
      {
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      },
    );
  } catch (e) {
    console.error(`[SPAR] Unexpected error: ${(e as Error).message}`);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        detail: (e as Error).message,
        retailer: "SPAR",
      }),
      {
        status: 500,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      },
    );
  }
});
