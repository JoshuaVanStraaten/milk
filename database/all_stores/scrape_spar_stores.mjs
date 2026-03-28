/**
 * Scrape all SPAR stores in South Africa from spar.co.za store locator API.
 *
 * Usage: node scrape_spar_stores.mjs
 *
 * Outputs: spar_stores_all.json in the same directory.
 * No npm install needed — uses native fetch() (Node 18+).
 */

import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const API_URL = "https://www.spar.co.za/api/stores/search";

// Only these grocery store types — excludes SPAR Express, Tops, Build It, etc.
const ALLOWED_TYPES = new Set(["SPAR", "SUPERSPAR", "KWIKSPAR"]);

// Province name normalization map (handle common variations)
const PROVINCE_ALIASES = {
  "kwazulu-natal": "KwaZulu-Natal",
  "kzn": "KwaZulu-Natal",
  "western-cape": "Western Cape",
  "westerncape": "Western Cape",
  "eastern-cape": "Eastern Cape",
  "easterncape": "Eastern Cape",
  "gauteng": "Gauteng",
  "limpopo": "Limpopo",
  "mpumalanga": "Mpumalanga",
  "north-west": "North West",
  "northwest": "North West",
  "northern-cape": "Northern Cape",
  "northerncape": "Northern Cape",
  "free-state": "Free State",
  "freestate": "Free State",
};

function normalizeProvince(raw) {
  if (!raw) return "Unknown";
  const key = raw.toLowerCase().replace(/\s+/g, "-");
  return PROVINCE_ALIASES[key] || raw.replace(/-/g, " ");
}

/**
 * Extract province from the Alias field.
 * Alias format: "KWIKSPAR-Hillcrest-KwaZulu-Natal"
 *   → last segment(s) after the city are the province.
 *
 * Strategy: SA has 9 known provinces. Walk backwards through the
 * hyphen-split segments and try to match a known province name.
 */
const SA_PROVINCES = [
  "KwaZulu-Natal",
  "Western Cape",
  "Eastern Cape",
  "Northern Cape",
  "North West",
  "Free State",
  "Gauteng",
  "Limpopo",
  "Mpumalanga",
];

function extractProvinceFromAlias(alias) {
  if (!alias) return "Unknown";

  // Try matching known province names from the end of the alias string
  const lower = alias.toLowerCase();
  for (const prov of SA_PROVINCES) {
    // Convert province to the hyphenated format used in aliases
    const hyphenated = prov.replace(/\s+/g, "-").toLowerCase();
    if (lower.endsWith(hyphenated)) {
      return prov;
    }
  }

  // Fallback: take the last hyphen-separated segment and normalize it
  const parts = alias.split("-");
  if (parts.length >= 3) {
    // Could be multi-word province like "KwaZulu-Natal" or "Free-State"
    // Try last two segments first
    const lastTwo = parts.slice(-2).join("-");
    const normalized = normalizeProvince(lastTwo);
    if (SA_PROVINCES.includes(normalized)) {
      return normalized;
    }
    // Try last segment only
    return normalizeProvince(parts[parts.length - 1]);
  }

  return "Unknown";
}

function buildAddress(store) {
  const physical = (store.PhysicalAddress || "").trim();
  const suburb = (store.Suburb || "").trim();
  if (physical && suburb) {
    return `${physical}, ${suburb}`;
  }
  return physical || suburb || "";
}

async function main() {
  console.log("Fetching SPAR stores from spar.co.za ...\n");

  const response = await fetch(API_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-requested-with": "XMLHttpRequest",
    },
    body: JSON.stringify({ lat: -25.7, lng: 28.2 }),
  });

  if (!response.ok) {
    throw new Error(`API returned ${response.status}: ${response.statusText}`);
  }

  const data = await response.json();
  const allStores = Array.isArray(data) ? data : data.stores || data.results || [];

  console.log(`Total stores fetched: ${allStores.length}`);

  // Step 1: Filter to allowed grocery types
  const groceryStores = allStores.filter((s) => {
    const type = (s.BusinessType || s.Type || "").toUpperCase().replace(/\s+/g, "");
    return ALLOWED_TYPES.has(type);
  });
  console.log(`After type filter (SPAR/SUPERSPAR/KWIKSPAR): ${groceryStores.length}`);

  // Step 2: Fix stores with swapped GPS coordinates
  let swappedCount = 0;
  for (const store of groceryStores) {
    if (store.GPSLat > 0 && store.GPSLong < 0) {
      const tmp = store.GPSLat;
      store.GPSLat = store.GPSLong;
      store.GPSLong = tmp;
      swappedCount++;
    }
  }
  console.log(`Fixed swapped GPS coordinates: ${swappedCount} stores`);

  // Step 3: Filter out stores with zero coordinates
  const withCoords = groceryStores.filter(
    (s) => s.GPSLat !== 0 && s.GPSLong !== 0
  );
  console.log(`After removing zero coordinates: ${withCoords.length}`);

  // Step 4: Filter to South Africa only (latitude between -35 and -22)
  const saOnly = withCoords.filter(
    (s) => s.GPSLat >= -35 && s.GPSLat <= -22
  );
  console.log(`After SA latitude filter (-35 to -22): ${saOnly.length}`);

  // Step 5: Map to output schema
  const mapped = saOnly.map((s) => ({
    retailer: "spar",
    store_code: String(s.SPARId),
    store_name: (s.FullName || "").trim(),
    latitude: s.GPSLat,
    longitude: s.GPSLong,
    province: extractProvinceFromAlias(s.Alias),
    city: (s.Town || "").trim(),
    address: buildAddress(s),
  }));

  // Step 6: Province breakdown
  const provinceCounts = {};
  for (const store of mapped) {
    provinceCounts[store.province] = (provinceCounts[store.province] || 0) + 1;
  }

  console.log(`\n--- Province Breakdown ---`);
  const sorted = Object.entries(provinceCounts).sort((a, b) => b[1] - a[1]);
  for (const [province, count] of sorted) {
    console.log(`  ${province}: ${count}`);
  }
  console.log(`  TOTAL: ${mapped.length}`);

  // Step 7: Write output
  const outPath = join(__dirname, "spar_stores_all.json");
  writeFileSync(outPath, JSON.stringify(mapped, null, 2) + "\n", "utf-8");
  console.log(`\nWrote ${mapped.length} stores to ${outPath}`);
}

main().catch((err) => {
  console.error("Error:", err.message);
  process.exit(1);
});
