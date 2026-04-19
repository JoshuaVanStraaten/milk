// supabase/functions/stores-search/index.ts
// Search for stores of a specific retailer by name/city/address,
// or return the nearest stores when no query is provided.
//
// POST body: {
//   "retailer": "pnp",             // required, lowercase retailer slug
//   "query": "irene",              // optional; omit/empty for nearby mode
//   "latitude": -25.85,            // optional but strongly recommended
//   "longitude": 28.24,            // optional but strongly recommended
//   "limit": 20                    // optional, default 20
// }
//
// Response: { "stores": [ { store_code, store_name, ... }, ... ] }
//
// Note: returns an ARRAY of stores (distinct from stores-nearby which
// returns one store per retailer, keyed by retailer slug).

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate_limiter.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // 60 requests / minute per IP — generous for interactive typing (debounced in client)
  const limited = checkRateLimit(req, corsHeaders, 60, 60_000);
  if (limited) return limited;

  try {
    const body = await req.json().catch(() => ({}));
    const retailer = typeof body.retailer === "string" ? body.retailer.trim().toLowerCase() : "";
    const query = typeof body.query === "string" ? body.query.trim() : "";
    const latitude = typeof body.latitude === "number" ? body.latitude : null;
    const longitude = typeof body.longitude === "number" ? body.longitude : null;
    const limit = typeof body.limit === "number" && body.limit > 0
      ? Math.min(Math.floor(body.limit), 50)
      : 20;

    if (!retailer) {
      return jsonError("retailer is required", 400);
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data, error } = await supabase.rpc("search_retailer_stores", {
      p_retailer: retailer,
      p_query: query || null,
      p_latitude: latitude,
      p_longitude: longitude,
      p_limit: limit,
    });

    if (error) {
      console.error("search_retailer_stores RPC error:", error);
      return jsonError("Failed to search stores", 500, error.message);
    }

    return new Response(
      JSON.stringify({
        stores: data ?? [],
        query: { retailer, query, latitude, longitude, limit },
        timestamp: new Date().toISOString(),
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error("Unexpected error:", err);
    return jsonError("Internal server error", 500);
  }
});

function jsonError(message: string, status: number, details?: string): Response {
  return new Response(
    JSON.stringify({ error: message, details }),
    {
      status,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    },
  );
}
