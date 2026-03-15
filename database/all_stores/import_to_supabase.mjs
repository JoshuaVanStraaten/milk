#!/usr/bin/env node
/**
 * Import stores to Supabase
 *
 * Reads all_stores_combined.json and upserts into retailer_stores table.
 * Uses native fetch + Supabase REST API (no npm install needed).
 *
 * Usage:
 *   node import_to_supabase.mjs
 *
 * Environment variables (or edit below):
 *   SUPABASE_URL - Your Supabase project URL
 *   SUPABASE_SERVICE_ROLE_KEY - Service role key (NOT anon key)
 */

import { readFileSync } from "fs";

// ─── CONFIG ──────────────────────────────────────────────────
const SUPABASE_URL =
  process.env.SUPABASE_URL || "https://pjqbvrluyvqvpegxumsd.supabase.co";
const SUPABASE_KEY =
  process.env.SUPABASE_SERVICE_ROLE_KEY || "";
// ─────────────────────────────────────────────────────────────

if (!SUPABASE_KEY) {
  console.error("ERROR: Set SUPABASE_SERVICE_ROLE_KEY environment variable");
  console.error(
    "  export SUPABASE_SERVICE_ROLE_KEY=eyJ..."
  );
  process.exit(1);
}

const TABLE = "retailer_stores";
const BATCH_SIZE = 100;

async function upsertBatch(stores) {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/${TABLE}?on_conflict=retailer,store_code`,
    {
      method: "POST",
      headers: {
        apikey: SUPABASE_KEY,
        Authorization: `Bearer ${SUPABASE_KEY}`,
        "Content-Type": "application/json",
        Prefer: "resolution=merge-duplicates,return=minimal",
      },
      body: JSON.stringify(stores),
    }
  );

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Upsert failed (${res.status}): ${text}`);
  }
  return res.status;
}

async function main() {
  console.log("=" .repeat(60));
  console.log("  IMPORT STORES TO SUPABASE");
  console.log("=".repeat(60));

  // Load stores
  const stores = JSON.parse(readFileSync("all_stores_combined.json", "utf-8"));
  console.log(`\nLoaded ${stores.length} stores from all_stores_combined.json`);

  // Verify data
  const byRetailer = {};
  stores.forEach((s) => {
    byRetailer[s.retailer] = (byRetailer[s.retailer] || 0) + 1;
  });
  console.log("\nBy retailer:");
  Object.entries(byRetailer)
    .sort()
    .forEach(([r, c]) => console.log(`  ${r}: ${c}`));

  // Upsert in batches
  console.log(`\nUpserting in batches of ${BATCH_SIZE}...`);
  const totalBatches = Math.ceil(stores.length / BATCH_SIZE);
  let uploaded = 0;
  let errors = 0;

  for (let i = 0; i < stores.length; i += BATCH_SIZE) {
    const batch = stores.slice(i, i + BATCH_SIZE);
    const batchNum = Math.floor(i / BATCH_SIZE) + 1;

    try {
      const status = await upsertBatch(batch);
      uploaded += batch.length;
      if (batchNum % 5 === 0 || batchNum === totalBatches) {
        console.log(
          `  Batch ${batchNum}/${totalBatches}: ${uploaded} stores uploaded`
        );
      }
    } catch (err) {
      errors++;
      console.error(`  Batch ${batchNum} FAILED: ${err.message}`);
      // Log the first store in the failed batch for debugging
      console.error(`    First store: ${JSON.stringify(batch[0])}`);
    }
  }

  console.log(`\n${"=".repeat(60)}`);
  console.log("IMPORT COMPLETE");
  console.log("=".repeat(60));
  console.log(`  Uploaded: ${uploaded}`);
  console.log(`  Errors: ${errors}`);
  console.log(`  Table: ${TABLE}`);
}

main().catch(console.error);
