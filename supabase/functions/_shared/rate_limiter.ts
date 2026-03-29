// supabase/functions/_shared/rate_limiter.ts
// Simple in-memory rate limiter per IP address.
//
// Usage in an Edge Function:
//   import { checkRateLimit } from "../_shared/rate_limiter.ts";
//
//   // Inside handler, after CORS preflight:
//   const rateLimitResponse = checkRateLimit(req, corsHeaders);
//   if (rateLimitResponse) return rateLimitResponse;

interface RateLimitEntry {
  count: number;
  resetAt: number; // Unix timestamp in ms
}

const ipMap = new Map<string, RateLimitEntry>();

// Clean up stale entries every 5 minutes to prevent memory growth
const CLEANUP_INTERVAL_MS = 5 * 60 * 1000;
let lastCleanup = Date.now();

function cleanup() {
  const now = Date.now();
  if (now - lastCleanup < CLEANUP_INTERVAL_MS) return;
  lastCleanup = now;

  for (const [ip, entry] of ipMap) {
    if (now > entry.resetAt) {
      ipMap.delete(ip);
    }
  }
}

/**
 * Check if a request should be rate limited.
 *
 * @param req - The incoming Request
 * @param corsHeaders - CORS headers to include in the 429 response
 * @param maxRequests - Max requests per window (default: 60)
 * @param windowMs - Time window in milliseconds (default: 60000 = 1 minute)
 * @returns A 429 Response if rate limited, or null if the request is allowed
 */
export function checkRateLimit(
  req: Request,
  corsHeaders: Record<string, string>,
  maxRequests = 60,
  windowMs = 60_000,
): Response | null {
  cleanup();

  // Extract client IP from headers (Supabase Edge Functions set these)
  const ip =
    req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
    req.headers.get("x-real-ip") ||
    "unknown";

  const now = Date.now();
  const entry = ipMap.get(ip);

  if (!entry || now > entry.resetAt) {
    // New window
    ipMap.set(ip, { count: 1, resetAt: now + windowMs });
    return null;
  }

  entry.count++;

  if (entry.count > maxRequests) {
    const retryAfterSeconds = Math.ceil((entry.resetAt - now) / 1000);
    return new Response(
      JSON.stringify({
        error: "Too many requests. Please try again shortly.",
      }),
      {
        status: 429,
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
          "Retry-After": String(retryAfterSeconds),
        },
      },
    );
  }

  return null;
}
