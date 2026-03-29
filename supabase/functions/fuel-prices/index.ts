// supabase/functions/fuel-prices/index.ts
// Manages SA fuel prices: reads from DB and refreshes from AA (aa.co.za)
//
// GET  → returns current fuel prices from production Supabase fuel_prices table
// POST { "action": "refresh" } → fetches latest prices from AA AJAX endpoint,
//       upserts to fuel_prices table, returns updated prices
//
// Deployed to POC Supabase. Reads/writes to PRODUCTION Supabase.
// Uses hardcoded prod URL + IMAGE_STORAGE_SERVICE_KEY (prod service role key).

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit } from "../_shared/rate_limiter.ts";

const PROD_PROJECT = "sfnavipqilqgzmtedfuh";
const PROD_URL = `https://${PROD_PROJECT}.supabase.co`;
const PROD_SERVICE_KEY = Deno.env.get("IMAGE_STORAGE_SERVICE_KEY") || "";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://sfnavipqilqgzmtedfuh.supabase.co",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// AA AJAX endpoint for fuel prices
const AA_FUEL_URL = "https://aa.co.za/wp-admin/admin-ajax.php";

// Map AA field names → our fuel_type keys
const FUEL_TYPE_MAP: Record<string, string> = {
  unleaded93: "petrol_93",
  unleaded95: "petrol_95",
  diesel50: "diesel_50ppm",
  diesel500: "diesel_500ppm",
};

function getSupabaseClient() {
  if (!PROD_SERVICE_KEY) {
    throw new Error("Missing IMAGE_STORAGE_SERVICE_KEY env var");
  }
  return createClient(PROD_URL, PROD_SERVICE_KEY);
}

/** Fetch current prices from the fuel_prices table */
async function readPricesFromDB() {
  const supabase = getSupabaseClient();
  const { data, error } = await supabase
    .from("fuel_prices")
    .select("fuel_type, region, price_per_litre, effective_date, source, updated_at")
    .order("fuel_type");

  if (error) {
    console.error("[FuelPrices] DB read error:", error.message);
    throw error;
  }

  return data;
}

/** Fetch latest prices from AA AJAX endpoint and upsert to DB */
async function refreshFromAA() {
  console.log("[FuelPrices] Fetching from AA...");

  const res = await fetch(AA_FUEL_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
      "Origin": "https://aa.co.za",
      "Referer": "https://aa.co.za/fuel-pricing/",
      "X-Requested-With": "XMLHttpRequest",
    },
    body: "action=getFuelPricesStart",
  });

  if (!res.ok) {
    throw new Error(`AA returned ${res.status}: ${await res.text().then(t => t.slice(0, 200))}`);
  }

  const json = await res.json();

  // Response shape: [{ prices: { ok, fuelPrices: [...] } }]
  const wrapper = Array.isArray(json) ? json[0] : json;
  const pricesData = wrapper?.prices;

  if (!pricesData?.ok || !pricesData?.fuelPrices?.length) {
    throw new Error(`AA response invalid: ok=${pricesData?.ok}, count=${pricesData?.fuelPrices?.length}`);
  }

  // Use the most recent entry (first in array)
  const latest = pricesData.fuelPrices[0];
  const effectiveDate = latest.updatedOn; // "2026-03-04"

  console.log(`[FuelPrices] AA latest: ${effectiveDate}`);

  // Build upsert rows
  const rows: Array<{
    fuel_type: string;
    region: string;
    price_per_litre: number;
    effective_date: string;
    source: string;
    updated_at: string;
  }> = [];

  for (const [aaPrefix, fuelType] of Object.entries(FUEL_TYPE_MAP)) {
    const coastKey = `${aaPrefix}Coast`;
    const inlandKey = `${aaPrefix}Inland`;

    const coastPrice = parseFloat(latest[coastKey]);
    const inlandPrice = parseFloat(latest[inlandKey]);

    if (!isNaN(coastPrice)) {
      rows.push({
        fuel_type: fuelType,
        region: "coastal",
        price_per_litre: coastPrice,
        effective_date: effectiveDate,
        source: "aa",
        updated_at: new Date().toISOString(),
      });
    }

    if (!isNaN(inlandPrice)) {
      rows.push({
        fuel_type: fuelType,
        region: "inland",
        price_per_litre: inlandPrice,
        effective_date: effectiveDate,
        source: "aa",
        updated_at: new Date().toISOString(),
      });
    }
  }

  console.log(`[FuelPrices] Upserting ${rows.length} rows`);

  const supabase = getSupabaseClient();
  const { error } = await supabase
    .from("fuel_prices")
    .upsert(rows, { onConflict: "fuel_type,region" });

  if (error) {
    console.error("[FuelPrices] Upsert error:", error.message);
    throw error;
  }

  console.log(`[FuelPrices] Refresh complete: ${rows.length} prices updated (effective ${effectiveDate})`);
  return rows;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const rateLimited = checkRateLimit(req, corsHeaders);
  if (rateLimited) return rateLimited;

  try {
    let action = "read";

    // POST with action: "refresh" triggers AA fetch + upsert
    if (req.method === "POST") {
      try {
        const body = await req.json();
        if (body?.action === "refresh") {
          action = "refresh";
        }
      } catch {
        // No body or invalid JSON — treat as read
      }
    }

    if (action === "refresh") {
      try {
        await refreshFromAA();
      } catch (err) {
        console.error("[FuelPrices] Refresh failed, falling back to DB:", err);
        // Fall through to return existing DB prices
      }
    }

    // Always return current DB prices
    const prices = await readPricesFromDB();

    const updatedAt = prices.length > 0
      ? prices.reduce((latest, p) => {
          const d = p.updated_at || p.effective_date;
          return d > latest ? d : latest;
        }, "")
      : null;

    return new Response(
      JSON.stringify({
        prices,
        updated_at: updatedAt,
        source: "aa",
        count: prices.length,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (err) {
    console.error("[FuelPrices] Unexpected error:", err);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
