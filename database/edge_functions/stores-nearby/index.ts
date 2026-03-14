// supabase/functions/stores-nearby/index.ts
// Returns the nearest store for each retailer given GPS coordinates
//
// POST body: { "latitude": -25.8546, "longitude": 28.2492 }
// Response: { "stores": { "pnp": {...}, "checkers": {...}, ... } }

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { latitude, longitude } = await req.json();

    if (!latitude || !longitude) {
      return new Response(
        JSON.stringify({ error: "latitude and longitude are required" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Use the efficient single-query RPC that gets all retailers at once
    const { data, error } = await supabase.rpc("find_all_nearest_stores", {
      p_latitude: latitude,
      p_longitude: longitude,
    });

    if (error) {
      console.error("RPC error:", error);
      return new Response(
        JSON.stringify({
          error: "Failed to find nearest stores",
          details: error.message,
        }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // Transform array into keyed object
    const stores: Record<string, any> = {};
    for (const row of data || []) {
      stores[row.retailer] = {
        store_code: row.store_code,
        store_name: row.store_name,
        province: row.province,
        city: row.city,
        address: row.address,
        latitude: row.latitude,
        longitude: row.longitude,
        distance_km: row.distance_km,
      };
    }

    return new Response(
      JSON.stringify({
        stores,
        query: { latitude, longitude },
        timestamp: new Date().toISOString(),
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error("Unexpected error:", err);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
