// supabase/functions/gemini-proxy/index.ts
// Proxies Gemini API calls server-side so the API key is never exposed in the APK.
//
// POST { contents, generationConfig } → forwards to Gemini API → returns response
//
// The GEMINI_API_KEY is stored as a Supabase Edge Function secret.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { checkRateLimit } from "../_shared/rate_limiter.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY") || "";
const GEMINI_MODEL = "gemini-2.5-flash";
const GEMINI_BASE_URL = "https://generativelanguage.googleapis.com/v1beta";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://sfnavipqilqgzmtedfuh.supabase.co",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Stricter rate limit for AI endpoint: 10 requests/minute per IP
  const rateLimited = checkRateLimit(req, corsHeaders, 10);
  if (rateLimited) return rateLimited;

  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "Method not allowed" }),
      {
        status: 405,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }

  if (!GEMINI_API_KEY) {
    console.error("[GeminiProxy] GEMINI_API_KEY not set");
    return new Response(
      JSON.stringify({ error: "AI service not configured" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }

  try {
    const body = await req.json();
    const { contents, generationConfig } = body;

    if (!contents || !Array.isArray(contents) || contents.length === 0) {
      return new Response(
        JSON.stringify({ error: "Missing or invalid 'contents' field" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Forward to Gemini API
    const geminiUrl = `${GEMINI_BASE_URL}/models/${GEMINI_MODEL}:generateContent?key=${GEMINI_API_KEY}`;

    const geminiBody: Record<string, unknown> = { contents };
    if (generationConfig) {
      geminiBody.generationConfig = generationConfig;
    }

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 60000); // 60s timeout

    try {
      const geminiRes = await fetch(geminiUrl, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(geminiBody),
        signal: controller.signal,
      });

      clearTimeout(timeout);

      // Pass through the Gemini response (status + body) to the client
      const geminiData = await geminiRes.text();

      return new Response(geminiData, {
        status: geminiRes.status,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    } catch (fetchErr) {
      clearTimeout(timeout);

      if (fetchErr instanceof DOMException && fetchErr.name === "AbortError") {
        return new Response(
          JSON.stringify({ error: "Gemini API request timed out" }),
          {
            status: 504,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      throw fetchErr;
    }
  } catch (err) {
    console.error("[GeminiProxy] Error:", err);
    return new Response(
      JSON.stringify({
        error: "Failed to proxy request to AI service",
      }),
      {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
