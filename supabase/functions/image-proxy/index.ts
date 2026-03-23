// supabase/functions/image-proxy/index.ts
//
// Image proxy for Checkers and Shoprite product images.
//
// These retailers' image CDN requires session cookies — Flutter can't
// send them. This function:
//   1. Checks if the image is already cached in Supabase Storage
//   2. If cached → 302 redirect to the public Storage URL
//   3. If not → fetches with session cookies, uploads to Storage, redirects
//
// Usage: GET /image-proxy?url=<encoded_retailer_image_url>

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const STORAGE_PROJECT = "sfnavipqilqgzmtedfuh";
const STORAGE_BUCKET = "product_images";
const STORAGE_BASE = `https://${STORAGE_PROJECT}.supabase.co/storage/v1`;
const STORAGE_PUBLIC_BASE = `${STORAGE_BASE}/object/public/${STORAGE_BUCKET}`;

// Service role key for the storage project — set as Edge Function secret
const STORAGE_SERVICE_KEY = Deno.env.get("IMAGE_STORAGE_SERVICE_KEY") || "";

const USER_AGENT =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "https://sfnavipqilqgzmtedfuh.supabase.co",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// In-memory session cache (persists across requests in same Deno isolate)
const sessionCache: Map<string, { cookies: string; expires: number }> = new Map();

// Allowed hostnames for image fetching (SSRF protection)
const ALLOWED_HOSTS = new Set([
  "www.checkers.co.za",
  "checkers.co.za",
  "products.checkers.co.za",
  "images.checkers.co.za",
  "www.shoprite.co.za",
  "shoprite.co.za",
  "products.shoprite.co.za",
  "images.shoprite.co.za",
]);

// Extract retailer and product code from the image URL
function parseImageUrl(url: string): { retailer: string; code: string; storagePath: string } | null {
  try {
    const parsed = new URL(url);
    const hostname = parsed.hostname.toLowerCase();

    // Strict domain whitelist to prevent SSRF
    if (!ALLOWED_HOSTS.has(hostname)) {
      return null;
    }

    let retailer: string;
    if (hostname.includes("checkers")) {
      retailer = "checkers";
    } else if (hostname.includes("shoprite")) {
      retailer = "shoprite";
    } else {
      return null;
    }

    // Extract product code (e.g., 10135941EA) from various URL patterns:
    //   /medias/10135941EA-checkers300Wx300H?...
    //   /medias/checkers300Wx300H-10136574EA.png?...
    //   /medias/checkers300Wx300H-medias-10151065EA-en-...?...
    //   /medias/10148833EAV2-checkers300Wx300H?...
    // Product codes are always 5+ digits followed by EA, KG, etc. (optionally with V2/v1 suffix)
    const codeMatch = parsed.pathname.match(/(\d{5,}[A-Z]{2}(?:[Vv]\d)?)/);
    if (!codeMatch) return null;

    const code = codeMatch[1];
    const storagePath = `${retailer}/${code}.png`;

    return { retailer, code, storagePath };
  } catch {
    return null;
  }
}

// Check if image exists in Storage (HEAD request to public URL)
async function checkStorageExists(storagePath: string): Promise<string | null> {
  const publicUrl = `${STORAGE_PUBLIC_BASE}/${storagePath}`;
  try {
    const resp = await fetch(publicUrl, { method: "HEAD" });
    if (resp.ok) return publicUrl;
  } catch { /* ignore */ }
  return null;
}

// Create a session to get cookies for the retailer
async function getSessionCookies(retailer: string): Promise<string | null> {
  const cached = sessionCache.get(retailer);
  if (cached && cached.expires > Date.now()) {
    return cached.cookies;
  }

  const baseUrl = retailer === "checkers"
    ? "https://products.checkers.co.za"
    : "https://www.shoprite.co.za";

  try {
    const resp = await fetch(baseUrl, {
      headers: {
        "User-Agent": USER_AGENT,
        Accept: "text/html",
      },
      redirect: "follow",
    });

    const setCookies: string[] = [];
    if (typeof (resp.headers as any).getSetCookie === "function") {
      setCookies.push(...(resp.headers as any).getSetCookie());
    } else {
      const raw = resp.headers.get("set-cookie") || "";
      if (raw) setCookies.push(...raw.split(/,(?=\s*[A-Za-z_][A-Za-z0-9_]*=)/));
    }
    await resp.text(); // consume body

    const cookies = setCookies
      .map((c) => c.split(";")[0].trim())
      .filter(Boolean)
      .join("; ");

    if (!cookies) return null;

    // Cache for 20 minutes
    sessionCache.set(retailer, {
      cookies,
      expires: Date.now() + 20 * 60 * 1000,
    });

    return cookies;
  } catch (e) {
    console.error(`Session creation failed for ${retailer}: ${(e as Error).message}`);
    return null;
  }
}

// Fetch image from retailer with session cookies
async function fetchRetailerImage(
  url: string,
  cookies: string,
): Promise<{ data: Uint8Array; contentType: string } | null> {
  try {
    const resp = await fetch(url, {
      headers: {
        "User-Agent": USER_AGENT,
        Cookie: cookies,
      },
      redirect: "follow",
    });

    if (!resp.ok) {
      // If 403, session may be stale — clear cache
      if (resp.status === 403) {
        const parsed = new URL(url);
        const retailer = parsed.hostname.includes("checkers") ? "checkers" : "shoprite";
        sessionCache.delete(retailer);
      }
      console.error(`Retailer returned ${resp.status} for ${url}`);
      return null;
    }

    const contentType = resp.headers.get("content-type") || "image/png";
    const data = new Uint8Array(await resp.arrayBuffer());
    return { data, contentType };
  } catch (e) {
    console.error(`Image fetch failed: ${(e as Error).message}`);
    return null;
  }
}

// Upload image to Supabase Storage
async function uploadToStorage(
  storagePath: string,
  data: Uint8Array,
  contentType: string,
): Promise<string | null> {
  const uploadUrl = `${STORAGE_BASE}/object/${STORAGE_BUCKET}/${storagePath}`;

  try {
    const resp = await fetch(uploadUrl, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${STORAGE_SERVICE_KEY}`,
        "Content-Type": contentType,
        "x-upsert": "true",
      },
      body: data,
    });

    if (!resp.ok) {
      const text = await resp.text();
      console.error(`Storage upload failed (${resp.status}): ${text}`);
      return null;
    }

    await resp.text(); // consume response
    return `${STORAGE_PUBLIC_BASE}/${storagePath}`;
  } catch (e) {
    console.error(`Storage upload error: ${(e as Error).message}`);
    return null;
  }
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  const reqUrl = new URL(req.url);
  const imageUrl = reqUrl.searchParams.get("url");

  if (!imageUrl) {
    return new Response(
      JSON.stringify({ error: "Missing 'url' query parameter" }),
      { status: 400, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  }

  const parsed = parseImageUrl(imageUrl);
  if (!parsed) {
    return new Response(
      JSON.stringify({ error: "Invalid image URL — must be a Checkers or Shoprite media URL" }),
      { status: 400, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  }

  // Step 1: Check if already cached in Storage
  const existingUrl = await checkStorageExists(parsed.storagePath);
  if (existingUrl) {
    return new Response(null, {
      status: 302,
      headers: { ...CORS_HEADERS, Location: existingUrl },
    });
  }

  // Step 2: Get session cookies
  let cookies = await getSessionCookies(parsed.retailer);
  if (!cookies) {
    return new Response(
      JSON.stringify({ error: "Failed to create retailer session" }),
      { status: 502, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  }

  // Step 3: Fetch image from retailer
  let image = await fetchRetailerImage(imageUrl, cookies);

  // Retry once with fresh session if failed (cookie may have been stale)
  if (!image) {
    sessionCache.delete(parsed.retailer);
    cookies = await getSessionCookies(parsed.retailer);
    if (cookies) {
      image = await fetchRetailerImage(imageUrl, cookies);
    }
  }

  if (!image) {
    return new Response(
      JSON.stringify({ error: "Failed to fetch image from retailer" }),
      { status: 502, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  }

  // Step 4: Upload to Storage (fire and don't block response)
  // We still return the image directly this time for speed
  const storagePromise = STORAGE_SERVICE_KEY
    ? uploadToStorage(parsed.storagePath, image.data, image.contentType)
    : Promise.resolve(null);

  // Step 5: Return image directly (don't wait for upload)
  // Use waitUntil-like pattern: start upload, return image immediately
  storagePromise.then((url) => {
    if (url) console.log(`[image-proxy] Cached: ${parsed.storagePath}`);
    else if (STORAGE_SERVICE_KEY) console.log(`[image-proxy] Cache upload failed: ${parsed.storagePath}`);
  }).catch(() => {});

  return new Response(image.data, {
    status: 200,
    headers: {
      ...CORS_HEADERS,
      "Content-Type": image.contentType,
      "Cache-Control": "public, max-age=86400, s-maxage=604800",
    },
  });
});
