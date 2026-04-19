// supabase/functions/places-autocomplete/index.ts
// Proxies Google Places Autocomplete (New) API. Keeps API key server-side.
//
// POST body: { "query": "42 main rd", "sessionToken": "uuid-v4" }
// Response:  { "suggestions": [{ placeId, description, mainText, secondaryText }] }
//
// Restricted to South Africa via regionCode=za.
// On Google 429/OVER_QUERY_LIMIT → returns 503 { error: "places_quota_exceeded" }
// so the client can fall back to the platform geocoder gracefully.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { checkRateLimit } from "../_shared/rate_limiter.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const GOOGLE_ENDPOINT = "https://places.googleapis.com/v1/places:autocomplete";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // 30 requests / minute per IP — interactive typing with 300ms debounce
  // and 3-char minimum should land well below this
  const limited = checkRateLimit(req, corsHeaders, 30, 60_000);
  if (limited) return limited;

  try {
    const apiKey = Deno.env.get("GOOGLE_PLACES_API_KEY");
    if (!apiKey) {
      console.error("GOOGLE_PLACES_API_KEY not configured");
      return jsonError("Places search not configured", 500);
    }

    const body = await req.json().catch(() => ({}));
    const query = typeof body.query === "string" ? body.query.trim() : "";
    const sessionToken = typeof body.sessionToken === "string"
      ? body.sessionToken
      : "";

    if (query.length < 3) {
      return new Response(
        JSON.stringify({ suggestions: [] }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const googleResponse = await fetch(GOOGLE_ENDPOINT, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": apiKey,
      },
      body: JSON.stringify({
        input: query,
        includedRegionCodes: ["za"],
        sessionToken: sessionToken || undefined,
      }),
    });

    if (googleResponse.status === 429) {
      console.warn("Google Places autocomplete quota hit");
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
      console.error("Google Places error:", googleResponse.status, text);
      // Treat explicit quota strings in the body as quota exceeded too
      if (text.includes("OVER_QUERY_LIMIT") || text.includes("RESOURCE_EXHAUSTED")) {
        return new Response(
          JSON.stringify({ error: "places_quota_exceeded" }),
          {
            status: 503,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
      return jsonError("Places search failed", 502, text);
    }

    const payload = await googleResponse.json() as {
      suggestions?: Array<{
        placePrediction?: {
          placeId?: string;
          text?: { text?: string };
          structuredFormat?: {
            mainText?: { text?: string };
            secondaryText?: { text?: string };
          };
        };
      }>;
    };

    const suggestions = (payload.suggestions ?? [])
      .map((s) => s.placePrediction)
      .filter((p): p is NonNullable<typeof p> => !!p && !!p.placeId)
      .map((p) => ({
        placeId: p.placeId!,
        description: p.text?.text ?? "",
        mainText: p.structuredFormat?.mainText?.text ?? p.text?.text ?? "",
        secondaryText: p.structuredFormat?.secondaryText?.text ?? "",
      }));

    return new Response(
      JSON.stringify({ suggestions }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error("places-autocomplete unexpected error:", err);
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
