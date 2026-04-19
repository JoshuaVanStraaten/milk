// database/all_stores/scripts/backfill_woolies_place_ids_retry.mjs
//
// Second-pass retry for Woolies stores that didn't match on the first run.
// Uses a simpler query shape: "Woolworths <store_name>, <city>" — shorter
// queries often match better on Google Places when the full address has
// noise (farm portions, multi-line, unusual formatting).

import { readFile, writeFile } from "node:fs/promises";
import { setTimeout as sleep } from "node:timers/promises";
import path from "node:path";

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

const OUTPUT_SQL_PATH = path.resolve(
  process.cwd(),
  "database/migrations/woolies_place_ids_backfill_retry.sql",
);

const DELAY_BETWEEN_CALLS_MS = 1100;

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
  url.searchParams.set("retailer", "eq.woolworths");
  url.searchParams.set("place_id", "is.null");
  url.searchParams.set("select", "id,store_code,store_name,address,city");
  url.searchParams.set("order", "id.asc");

  return fetchJson(url.toString(), {
    headers: { apikey: ANON_KEY, Authorization: `Bearer ${ANON_KEY}` },
  });
}

// Short, clean query — just name + city. Skips full address noise.
function buildSimpleQuery(store) {
  const name = store.store_name?.startsWith("Woolworths")
    ? store.store_name
    : `Woolworths ${store.store_name}`;
  const city = store.city?.replace(/Local Municipality|Ward \d+/gi, "").trim();
  return city ? `${name}, ${city}` : name;
}

async function resolvePlaceId(store, query) {
  const resp = await fetch(
    `${SUPABASE_URL}/functions/v1/places-autocomplete`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${ANON_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        query,
        sessionToken: `backfill-retry-${store.id}`,
      }),
    },
  );

  if (resp.status === 503) throw new Error("places_quota_exceeded");
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`${resp.status}: ${text.slice(0, 200)}`);
  }

  const data = await resp.json();
  const suggestions = data.suggestions ?? [];
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

// ── Main ───────────────────────────────────────────────────────────────────
const startedAt = Date.now();
console.log(`[retry] Starting second-pass Woolworths place_id backfill`);

const stores = await getUnprocessedStores();
console.log(`[retry] Found ${stores.length} store(s) still missing place_id`);

const updates = [];
let resolvedCount = 0;
let notFound = 0;

for (let i = 0; i < stores.length; i++) {
  const store = stores[i];
  const prefix = `[${String(i + 1).padStart(2, " ")}/${stores.length}]`;
  const query = buildSimpleQuery(store);

  try {
    const result = await resolvePlaceId(store, query);
    if (result) {
      updates.push({ store, result });
      resolvedCount++;
      console.log(
        `${prefix} ✓ ${store.store_name.padEnd(40).slice(0, 40)} via "${query.slice(0, 40)}" → ${result.placeId.slice(0, 24)}…`,
      );
    } else {
      notFound++;
      console.log(
        `${prefix} ∅ ${store.store_name.padEnd(40).slice(0, 40)} via "${query.slice(0, 40)}"`,
      );
    }
  } catch (e) {
    if (e.message === "places_quota_exceeded") {
      console.error(`${prefix} ✗ QUOTA EXCEEDED — stopping.`);
      break;
    }
    console.error(`${prefix} ✗ ${store.store_name} — ${e.message}`);
  }

  if (i < stores.length - 1) await sleep(DELAY_BETWEEN_CALLS_MS);
}

const sqlHeader = [
  "-- Auto-generated retry pass by backfill_woolies_place_ids_retry.mjs",
  `-- Generated: ${new Date().toISOString()}`,
  `-- Stores resolved this pass: ${resolvedCount} / ${stores.length}`,
  "",
  "BEGIN;",
  "",
].join("\n");

const sqlBody = updates
  .map((u) => buildUpdateStatement(u.store, u.result))
  .join("\n");

await writeFile(OUTPUT_SQL_PATH, `${sqlHeader}${sqlBody}\n\nCOMMIT;\n`, "utf8");

const elapsed = Math.round((Date.now() - startedAt) / 1000);
console.log(`\n[retry] Done in ${elapsed}s`);
console.log(`[retry]   resolved:  ${resolvedCount}`);
console.log(`[retry]   not found: ${notFound}`);
console.log(`\n[retry] Apply with:`);
console.log(`   npx supabase db query --linked --file database/migrations/woolies_place_ids_backfill_retry.sql`);
