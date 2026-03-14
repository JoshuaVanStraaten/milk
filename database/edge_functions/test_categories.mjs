/**
 * Category URL generation tests for Milk edge functions.
 *
 * Tests the URL-building and category-mapping logic extracted from each edge function.
 * Run with: node database/edge_functions/test_categories.mjs
 */

import assert from "node:assert/strict";

let passed = 0;
let failed = 0;

function test(name, fn) {
  try {
    fn();
    console.log(`  ✓ ${name}`);
    passed++;
  } catch (e) {
    console.error(`  ✗ ${name}`);
    console.error(`    ${e.message}`);
    failed++;
  }
}

// ── PnP ──────────────────────────────────────────────────────────────────────

const PNP_CATEGORIES = {
  "Fruit & Veg": "fresh-fruit-and-vegetables-423144840",
  "Meat & Poultry": "fresh-meat-poultry-and-seafood-423144840",
  "Dairy & Eggs": "milk-dairy-and-eggs-423144840",
  "Bakery": "bakery-423144840",
  "Frozen": "frozen-food-423144840",
  "Food Cupboard": "food-cupboard-423144840",
  "Snacks": "chocolates-chips-and-snacks-423144840",
  "Beverages": "beverages-423144840",
};

function pnpBuildQuery(query, category) {
  if (query) return query;
  const categorySlug = category ? PNP_CATEGORIES[category] : null;
  return categorySlug
    ? `:relevance:allCategories:pnpbase:category:${categorySlug}`
    : `:relevance:allCategories:${category || "pnpbase"}`;
}

console.log("\n--- PnP category query building ---");

test("default browse (no category) uses pnpbase", () => {
  assert.equal(pnpBuildQuery(undefined, undefined), ":relevance:allCategories:pnpbase");
});

test("known category 'Dairy & Eggs' appends correct slug", () => {
  assert.equal(
    pnpBuildQuery(undefined, "Dairy & Eggs"),
    ":relevance:allCategories:pnpbase:category:milk-dairy-and-eggs-423144840"
  );
});

test("known category 'Bakery' appends correct slug", () => {
  assert.equal(
    pnpBuildQuery(undefined, "Bakery"),
    ":relevance:allCategories:pnpbase:category:bakery-423144840"
  );
});

test("known category 'Fruit & Veg' appends correct slug", () => {
  assert.equal(
    pnpBuildQuery(undefined, "Fruit & Veg"),
    ":relevance:allCategories:pnpbase:category:fresh-fruit-and-vegetables-423144840"
  );
});

test("known category 'Frozen' appends correct slug", () => {
  assert.equal(
    pnpBuildQuery(undefined, "Frozen"),
    ":relevance:allCategories:pnpbase:category:frozen-food-423144840"
  );
});

test("unknown category falls back to raw value", () => {
  assert.equal(
    pnpBuildQuery(undefined, "pnpbase"),
    ":relevance:allCategories:pnpbase"
  );
});

test("search query bypasses category logic", () => {
  assert.equal(pnpBuildQuery("milk", "Bakery"), "milk");
});

test("all 8 categories are mapped", () => {
  const expected = ["Fruit & Veg", "Meat & Poultry", "Dairy & Eggs", "Bakery", "Frozen", "Food Cupboard", "Snacks", "Beverages"];
  for (const cat of expected) {
    assert.ok(PNP_CATEGORIES[cat], `Missing PnP mapping for: ${cat}`);
  }
});

// ── Checkers ─────────────────────────────────────────────────────────────────

const CHECKERS_BASE_URL = "https://products.checkers.co.za";
const CHECKERS_BROWSE_PATH = "/c-2413/All-Departments/Food";

const CHECKERS_CATEGORIES = {
  "Fruit & Veg": "fresh_food",
  "Meat & Poultry": "fresh_meat_and_poultry",
  "Dairy & Eggs": "milk_butter_and_eggs",
  "Bakery": "bakery",
  "Frozen": "frozen_food",
  "Food Cupboard": "food_cupboard",
  "Snacks": "chocolates_and_sweets",
  "Beverages": "drinks",
};

function checkersBuildUrl(page, query, category) {
  if (query) {
    const searchQuery = `${query}:relevance:browseAllStoresFacetOff:browseAllStoresFacetOff:allCategories:${category || "all_departments"}`;
    return `${CHECKERS_BASE_URL}/search?q=${encodeURIComponent(searchQuery)}&page=${page}`;
  }
  const facet = category ? CHECKERS_CATEGORIES[category] : null;
  if (facet) {
    const q = `:relevance:browseAllStoresFacetOff:browseAllStoresFacetOff:allCategories:${facet}`;
    return `${CHECKERS_BASE_URL}${CHECKERS_BROWSE_PATH}?q=${encodeURIComponent(q)}&page=${page}`;
  }
  return `${CHECKERS_BASE_URL}${CHECKERS_BROWSE_PATH}?q=:relevance&page=${page}`;
}

console.log("\n--- Checkers category URL building ---");

test("default browse (no category) uses Food path", () => {
  assert.equal(
    checkersBuildUrl(0, undefined, undefined),
    "https://products.checkers.co.za/c-2413/All-Departments/Food?q=:relevance&page=0"
  );
});

test("'Bakery' category uses facet query (confirmed from network tab)", () => {
  const url = checkersBuildUrl(0, undefined, "Bakery");
  assert.ok(url.includes("/c-2413/All-Departments/Food"), "Should use Food browse path");
  assert.ok(url.includes("allCategories%3Abakery") || url.includes("allCategories:bakery"), "Should include bakery facet");
  assert.ok(url.includes("browseAllStoresFacetOff"), "Should include browse facet flags");
});

test("'Frozen' category uses facet query (confirmed from network tab)", () => {
  const url = checkersBuildUrl(0, undefined, "Frozen");
  assert.ok(url.includes("frozen_food"), "Should include frozen_food facet");
});

test("'Dairy & Eggs' category maps to correct facet", () => {
  const url = checkersBuildUrl(0, undefined, "Dairy & Eggs");
  assert.ok(url.includes("milk_butter_and_eggs"), "Should include milk_butter_and_eggs facet");
});

test("page number is included in URL", () => {
  const url = checkersBuildUrl(2, undefined, "Bakery");
  assert.ok(url.endsWith("&page=2"), "Should end with page=2");
});

test("search query uses /search endpoint not browse path", () => {
  const url = checkersBuildUrl(0, "milk", undefined);
  assert.ok(url.includes("/search?q="), "Should use search endpoint");
  assert.ok(!url.includes("/c-2413"), "Should not use browse path");
});

test("unknown category falls back to plain browse", () => {
  const url = checkersBuildUrl(0, undefined, "NonExistent");
  assert.equal(
    url,
    "https://products.checkers.co.za/c-2413/All-Departments/Food?q=:relevance&page=0"
  );
});

test("all 8 categories are mapped", () => {
  const expected = ["Fruit & Veg", "Meat & Poultry", "Dairy & Eggs", "Bakery", "Frozen", "Food Cupboard", "Snacks", "Beverages"];
  for (const cat of expected) {
    assert.ok(CHECKERS_CATEGORIES[cat], `Missing Checkers mapping for: ${cat}`);
  }
});

// ── Shoprite ──────────────────────────────────────────────────────────────────

const SHOPRITE_BASE_URL = "https://www.shoprite.co.za";
const SHOPRITE_BROWSE_PATH = "/c-2256/All-Departments";
const SHOPRITE_FOOD_PATH = "/c-2413/All-Departments/Food";

const SHOPRITE_CATEGORIES = {
  "Fruit & Veg": "fresh_food",
  "Meat & Poultry": "fresh_meat_and_poultry",
  "Dairy & Eggs": "milk_butter_and_eggs",
  "Bakery": "bakery",
  "Frozen": "frozen_food",
  "Food Cupboard": "food_cupboard",
  "Snacks": "chocolates_and_sweets",
  "Beverages": "drinks",
};

function shopriteBuildUrl(page, query, category) {
  if (query) {
    const searchQuery = `${query}:relevance:browseAllStoresFacetOff:browseAllStoresFacetOff:allCategories:${category || "all_departments"}`;
    return `${SHOPRITE_BASE_URL}/search?q=${encodeURIComponent(searchQuery)}&page=${page}`;
  }
  const facet = category ? SHOPRITE_CATEGORIES[category] : null;
  if (facet) {
    const q = `:relevance:browseAllStoresFacetOff:browseAllStoresFacetOff:allCategories:${facet}`;
    return `${SHOPRITE_BASE_URL}${SHOPRITE_FOOD_PATH}?q=${encodeURIComponent(q)}&page=${page}`;
  }
  return `${SHOPRITE_BASE_URL}${SHOPRITE_BROWSE_PATH}?q=:relevance&page=${page}`;
}

console.log("\n--- Shoprite category URL building ---");

test("default browse (no category) uses All-Departments path", () => {
  assert.equal(
    shopriteBuildUrl(0, undefined, undefined),
    "https://www.shoprite.co.za/c-2256/All-Departments?q=:relevance&page=0"
  );
});

test("'Bakery' category uses Food path + facet (confirmed from network tab)", () => {
  const url = shopriteBuildUrl(0, undefined, "Bakery");
  assert.ok(url.includes("/c-2413/All-Departments/Food"), "Should use Food browse path");
  assert.ok(url.includes("allCategories%3Abakery") || url.includes("allCategories:bakery"), "Should include bakery facet");
});

test("'Frozen' category uses Food path + frozen_food facet (confirmed from network tab)", () => {
  const url = shopriteBuildUrl(0, undefined, "Frozen");
  assert.ok(url.includes("/c-2413/All-Departments/Food"), "Should use Food browse path");
  assert.ok(url.includes("frozen_food"), "Should include frozen_food facet");
});

test("category browse uses Food path, not All-Departments", () => {
  const url = shopriteBuildUrl(0, undefined, "Bakery");
  assert.ok(!url.includes("/c-2256/All-Departments"), "Should NOT use All-Departments path");
  assert.ok(url.includes("/c-2413/All-Departments/Food"), "Should use Food path");
});

test("page number is included in URL", () => {
  const url = shopriteBuildUrl(3, undefined, "Frozen");
  assert.ok(url.endsWith("&page=3"), "Should end with page=3");
});

test("search query uses /search endpoint", () => {
  const url = shopriteBuildUrl(0, "bread", undefined);
  assert.ok(url.includes("/search?q="), "Should use search endpoint");
});

test("unknown category falls back to All-Departments browse", () => {
  const url = shopriteBuildUrl(0, undefined, "NonExistent");
  assert.equal(
    url,
    "https://www.shoprite.co.za/c-2256/All-Departments?q=:relevance&page=0"
  );
});

test("all 8 categories are mapped", () => {
  const expected = ["Fruit & Veg", "Meat & Poultry", "Dairy & Eggs", "Bakery", "Frozen", "Food Cupboard", "Snacks", "Beverages"];
  for (const cat of expected) {
    assert.ok(SHOPRITE_CATEGORIES[cat], `Missing Shoprite mapping for: ${cat}`);
  }
});

// ── Cross-retailer consistency ────────────────────────────────────────────────

console.log("\n--- Cross-retailer consistency ---");

const ALL_DISPLAY_NAMES = ["Fruit & Veg", "Meat & Poultry", "Dairy & Eggs", "Bakery", "Frozen", "Food Cupboard", "Snacks", "Beverages"];

test("all retailers map the same 8 display names", () => {
  for (const name of ALL_DISPLAY_NAMES) {
    assert.ok(PNP_CATEGORIES[name], `PnP missing: ${name}`);
    assert.ok(CHECKERS_CATEGORIES[name], `Checkers missing: ${name}`);
    assert.ok(SHOPRITE_CATEGORIES[name], `Shoprite missing: ${name}`);
  }
});

test("Checkers and Shoprite use identical facet values (same platform)", () => {
  for (const name of ALL_DISPLAY_NAMES) {
    assert.equal(
      CHECKERS_CATEGORIES[name],
      SHOPRITE_CATEGORIES[name],
      `Mismatch for "${name}": Checkers=${CHECKERS_CATEGORIES[name]}, Shoprite=${SHOPRITE_CATEGORIES[name]}`
    );
  }
});

// ── Summary ───────────────────────────────────────────────────────────────────

console.log(`\n${passed + failed} tests: ${passed} passed, ${failed} failed\n`);
if (failed > 0) process.exit(1);
