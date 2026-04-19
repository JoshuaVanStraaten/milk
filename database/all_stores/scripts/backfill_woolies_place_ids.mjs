// database/all_stores/scripts/backfill_woolies_place_ids.mjs
//
// One-time backfill: for every Woolworths row in retailer_stores where
// place_id IS NULL, call our places-autocomplete Edge Function to resolve
// a real Google Place ID from the store name + address.
//
// Why: Woolies' confirmPlace product API requires a valid Google Place ID.
// Without one, browse fails silently and users see wrong/missing prices.
//
// Cost: ~109 stores × 1 autocomplete session × $2.83/1000 ≈ $0.31.
// Covered by the $200/mo Google Maps free tier. Quota usage: ~109/300 daily.
//
// Throttling: 1.1s between calls (~55 req/min) — well under the 12k/min
// per-minute quota, but safe for both our rate limiter (60 req/min) and
// Google's.
//
// Run:
//   node database/all_stores/scripts/backfill_woolies_place_ids.mjs
//
// Required env (loaded from .env):
//   POC_SUPABASE_URL, POC_SUPABASE_ANON_KEY
//
// Output: database/migrations/woolies_place_ids_backfill.sql
//   Apply with: npx supabase db query --linked --file database/migrations/woolies_place_ids_backfill.sql

import { readFile, writeFile } from "node:fs/promises";
import { setTimeout as sleep } from "node:timers/promises";
import path from "node:path";

// ── Load .env ──────────────────────────────────────────────────────────────
const envPath = path.resolve(process.cwd(), ".env");
const envText = await readFile(envPath, "utf8").catch(() => "");
const env = Object.fromEntries(
  envText
    .split("\n")
    .map((l) => l.trim())
    .filter((l) => l && !l.startsWith("#") && l.includes("="))
    .map((l) => {
      const idx = l.indexOf("=");
      return [l.slice(0, idx).trim(), l.slice(idx + 1).trim()];
    }),
);

const SUPABASE_URL = env.POC_SUPABASE_URL;
const ANON_KEY = env.POC_SUPABASE_ANON_KEY;

if (!SUPABASE_URL || !ANON_KEY) {
  console.error("Missing POC_SUPABASE_URL / POC_SUPABASE_ANON_KEY in .env");
  process.exit(1);
}

// We write the results to a SQL file. User applies it via
// `npx supabase db query` (which already uses linked project auth).
// No service role key needed on the local machine.
const OUTPUT_SQL_PATH = path.resolve(
  process.cwd(),
  "database/migrations/woolies_place_ids_backfill.sql",
);

// ── Config ─────────────────────────────────────────────────────────────────
const RETAILER = "woolworths";
const DELAY_BETWEEN_CALLS_MS = 1100; // ~55 req/min, safely under all limits
const MAX_STORES_PER_RUN = 280; // Stay under 300/day quota even if re-run

// ── Helpers ────────────────────────────────────────────────────────────────
async function fetchJson(url, init) {
  const resp = await fetch(url, init);
  const text = await resp.text();
  if (!resp.ok) {
    throw new Error(`${resp.status} ${resp.statusText}: ${text.slice(0, 300)}`);
  }
  return text ? JSON.parse(text) : null;
}

async function getUnprocessedStores() {
  const url = new URL(`${SUPABASE_URL}/rest/v1/retailer_stores`);
  url.searchParams.set("retailer", `eq.${RETAILER}`);
  url.searchParams.set("place_id", "is.null");
  url.searchParams.set(
    "select",
    "id,store_code,store_name,address,city,province",
  );
  url.searchParams.set("order", "id.asc");
  url.searchParams.set("limit", String(MAX_STORES_PER_RUN));

  return fetchJson(url.toString(), {
    headers: {
      apikey: ANON_KEY,
      Authorization: `Bearer ${ANON_KEY}`,
    },
  });
}

async function resolvePlaceId(store) {
  // Query shape: "Woolworths <store_name>, <address>, <city>" — maximises
  // the odds that Google's first result IS the store (not a neighbouring business)
  const parts = [
    store.store_name?.startsWith("Woolworths")
      ? store.store_name
      : `Woolworths ${store.store_name}`,
    store.address,
    store.city,
  ].filter((s) => s && s.trim());
  const query = parts.join(", ");

  const resp = await fetch(
    `${SUPABASE_URL}/functions/v1/places-autocomplete`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${ANON_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ query, sessionToken: `backfill-${store.id}` }),
    },
  );

  if (resp.status === 503) {
    throw new Error("places_quota_exceeded");
  }
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`${resp.status}: ${text.slice(0, 200)}`);
  }

  const data = await resp.json();
  const suggestions = data.suggestions ?? [];

  // Prefer a suggestion whose description actually mentions "Woolworths" —
  // guards against cases where Google's top hit is a nearby unrelated business
  const woolies = suggestions.find((s) =>
    /woolworths/i.test(s.description ?? ""),
  );
  const best = woolies ?? suggestions[0];

  return best
    ? {
        placeId: best.placeId,
        nickname: best.mainText || best.description || store.store_name,
      }
    : null;
}

// Postgres string escaping: replace single quotes with doubled single quotes.
// Inputs come from Google Places (trusted), but we're paranoid.
function sqlEscape(s) {
  if (s == null) return "NULL";
  return `'${String(s).replace(/'/g, "''")}'`;
}

function buildUpdateStatement(store, resolved) {
  return (
    `UPDATE public.retailer_stores SET ` +
    `place_id = ${sqlEscape(resolved.placeId)}, ` +
    `place_nickname = ${sqlEscape(resolved.nickname)} ` +
    `WHERE id = ${Number(store.id)};`
  );
}

// ── Main ───────────────────────────────────────────────────────────────────
const startedAt = Date.now();
console.log(`[backfill] Starting Woolworths place_id backfill`);

const stores = await getUnprocessedStores();
console.log(`[backfill] Found ${stores.length} store(s) needing place_id`);

const updates = [];
let resolvedCount = 0;
let notFound = 0;
let errors = 0;

for (let i = 0; i < stores.length; i++) {
  const store = stores[i];
  const prefix = `[${String(i + 1).padStart(3, " ")}/${stores.length}]`;

  try {
    const result = await resolvePlaceId(store);
    if (result) {
      updates.push({ store, result });
      resolvedCount++;
      console.log(
        `${prefix} ✓ ${store.store_name.padEnd(40).slice(0, 40)} → ${result.placeId.slice(0, 27)}…`,
      );
    } else {
      notFound++;
      console.log(
        `${prefix} ∅ ${store.store_name.padEnd(40).slice(0, 40)} (no suggestions)`,
      );
    }
  } catch (e) {
    errors++;
    if (e.message === "places_quota_exceeded") {
      console.error(`${prefix} ✗ QUOTA EXCEEDED — stopping. Re-run tomorrow.`);
      break;
    }
    console.error(
      `${prefix} ✗ ${store.store_name.padEnd(40).slice(0, 40)} — ${e.message}`,
    );
  }

  if (i < stores.length - 1) {
    await sleep(DELAY_BETWEEN_CALLS_MS);
  }
}

// ── Write SQL file ─────────────────────────────────────────────────────────
const sqlHeader = [
  "-- Auto-generated by backfill_woolies_place_ids.mjs",
  `-- Generated: ${new Date().toISOString()}`,
  `-- Stores resolved: ${resolvedCount} / ${stores.length}`,
  "--",
  "-- Apply with:",
  "--   npx supabase db query --linked --file database/migrations/woolies_place_ids_backfill.sql",
  "",
  "BEGIN;",
  "",
].join("\n");

const sqlBody = updates.map((u) => buildUpdateStatement(u.store, u.result)).join("\n");

await writeFile(OUTPUT_SQL_PATH, `${sqlHeader}${sqlBody}\n\nCOMMIT;\n`, "utf8");

const elapsedSec = Math.round((Date.now() - startedAt) / 1000);
console.log(`\n[backfill] Done in ${elapsedSec}s`);
console.log(`[backfill]   resolved:  ${resolvedCount}`);
console.log(`[backfill]   not found: ${notFound}`);
console.log(`[backfill]   errors:    ${errors}`);
console.log(`\n[backfill] Wrote SQL to: ${path.relative(process.cwd(), OUTPUT_SQL_PATH)}`);
console.log(`[backfill] Apply with:`);
console.log(`   npx supabase db query --linked --file database/migrations/woolies_place_ids_backfill.sql`);
