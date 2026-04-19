// supabase/functions/places-details/index.ts
// Proxies Google Places Details (New) API. Keeps API key server-side.
//
// POST body: { "placeId": "ChIJ...", "sessionToken": "uuid-v4" }
// Response:  { "lat": -25.85, "lng": 28.24, "formattedAddress": "...", "placeId": "..." }
//
// Called AFTER the user picks an autocomplete suggestion.
// Session token should match the autocomplete session — batches them into
// one billed session (= 1 combined charge for autocomplete + details).
//
// On Google 429/OVER_QUERY_LIMIT → 503 { error: "places_quota_exceeded" }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
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

  // 30/min — one details call per user-picked suggestion
  const limited = checkRateLimit(req, corsHeaders, 30, 60_000);
  if (limited) return limited;

  try {
    const apiKey = Deno.env.get("GOOGLE_PLACES_API_KEY");
    if (!apiKey) {
      console.error("GOOGLE_PLACES_API_KEY not configured");
      return jsonError("Places details not configured", 500);
    }

    const body = await req.json().catch(() => ({}));
    const placeId = typeof body.placeId === "string" ? body.placeId.trim() : "";
    const sessionToken = typeof body.sessionToken === "string"
      ? body.sessionToken
      : "";

    if (!placeId) {
      return jsonError("placeId is required", 400);
    }

    // Places Details (New): GET /v1/places/{PLACE_ID}
    // Keep the field mask minimal to reduce cost (fewer fields = cheaper SKU)
    const url = new URL(`https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}`);
    if (sessionToken) url.searchParams.set("sessionToken", sessionToken);

    const googleResponse = await fetch(url.toString(), {
      method: "GET",
      headers: {
        "X-Goog-Api-Key": apiKey,
        "X-Goog-FieldMask": "id,location,formattedAddress,displayName",
      },
    });

    if (googleResponse.status === 429) {
      console.warn("Google Places details quota hit");
      return new Response(
        JSON.stringify({ error: "places_quota_exceeded" }),
        {
          status: 503,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    if (!googleResponse.ok) {
      const text = await googleResponse.text();
      console.error("Google Places details error:", googleResponse.status, text);
      if (text.includes("OVER_QUERY_LIMIT") || text.includes("RESOURCE_EXHAUSTED")) {
        return new Response(
          JSON.stringify({ error: "places_quota_exceeded" }),
          {
            status: 503,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
      return jsonError("Place details lookup failed", 502, text);
    }

    const payload = await googleResponse.json() as {
      id?: string;
      location?: { latitude?: number; longitude?: number };
      formattedAddress?: string;
      displayName?: { text?: string };
    };

    const lat = payload.location?.latitude;
    const lng = payload.location?.longitude;
    if (typeof lat !== "number" || typeof lng !== "number") {
      return jsonError("Place has no coordinates", 502);
    }

    return new Response(
      JSON.stringify({
        placeId: payload.id ?? placeId,
        lat,
        lng,
        formattedAddress: payload.formattedAddress ?? "",
        displayName: payload.displayName?.text ?? "",
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error("places-details unexpected error:", err);
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
