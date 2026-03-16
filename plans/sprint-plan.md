# Milk App — Incremental Bug Fix & Enhancement Plan

## Context

The app is in closed beta heading toward public launch. Focus is on fixing bugs, improving core matching, and polishing UI/UX. Work is split into incremental sprints — each sprint is tested manually on device/emulator, committed, then we move on.

## Model Selection Guide

Choose the best model for each task based on complexity:

- **Sonnet 4.6** — Bug fixes, unused import cleanup, padding fixes, simple UI tweaks, boilerplate code, repetitive changes
- **Opus 4.6** — Architecture decisions, AI matching algorithm design, complex state management, prompt engineering, deep refactors, UI/UX design strategy

---

## Sprint Order (priority-based, dependencies respected)

### Sprint 1: Quick Bug Fixes (low risk, high impact)

**Model:** Sonnet 4.6
**Goal:** Fix 4 isolated bugs that don't touch core logic.

**1a. Recipe save-then-export conflict** ⚠️ INCOMPLETE — needs second fix

- **Bug:** User saves recipe manually, then matches ingredients, then exports → "Save Failed" error
- **Root cause (deeper):** TWO code paths trigger the bug:
  1. `exportToShoppingList(saveRecipe: true)` — already guarded with `recipeId == null` check ✅
  2. **Export dialog UI** (`recipe_screen.dart:797-815`) — calls `saveRecipe()` then `exportToShoppingList()` as separate sequential calls. The dialog doesn't check if recipe already has a `recipeId`, so `saveRecipe()` calls `repository.saveRecipe()` which does a raw `.insert()` → duplicate key conflict on `Recipes_Overview` table
- **Fix approach (two-pronged):**
  - **Fix A** (provider-level, defensive): In `saveRecipe()` method (`recipe_provider.dart:358`), add early return if `state.generatedRecipe?.recipeId != null` — recipe already persisted, nothing to do
  - **Fix B** (repository-level, robust): In `recipe_repository.dart:saveRecipe()`, change `.insert()` to `.upsert()` so re-saving an existing recipe updates instead of failing
  - Fix A is the primary fix (prevents unnecessary DB call). Fix B is defense-in-depth.
- **Files:** `lib/presentation/providers/recipe_provider.dart` (line 358), `lib/data/repositories/recipe_repository.dart` (line 26)
- **Model:** Sonnet 4.6 (straightforward guard + upsert change)

**1b. Extra bottom padding on lists**

- **Bug:** Bottom of list screen cut off on some devices
- **Fix in:** `lib/presentation/screens/lists/list_detail_screen.dart`
- **Approach:** Add `padding: EdgeInsets.only(bottom: 80)` to the AnimatedList to account for FAB + safe area

**1c. API retry with backoff**

- **Bug:** Single API failure = no data shown
- **Fix in:** `lib/data/services/live_api_service.dart`
- **Approach:** Add `_retryWithBackoff()` helper — 3 attempts with exponential backoff (1s, 2s, 4s). Wrap all Edge Function calls.

**1d. Fix `withOpacity` deprecation warnings** (86 info items)

- **Fix in:** Multiple files (home_screen, skeleton_loaders, recipe widgets, etc.)
- **Approach:** Replace `.withOpacity(x)` with `.withValues(alpha: x)` globally

**1e. Cannot add compared products to list**

- **Bug:** When user compares prices on a product, match cards are display-only — no way to add a cheaper match to a shopping list. User can only add the original product.
- **Root cause:** `_buildMatchCard()` in `live_product_detail_screen.dart` (line ~685) returns a plain `Container` — no `InkWell`/`GestureDetector`, no `onTap` handler.
- **Fix:** Wrap match card in `InkWell`, on tap call existing `showAddToListSheet()` with the matched product's data (name, price, retailer, imageUrl, promo price). All required data is already available on the `ComparisonMatch` object.
- **File:** `lib/presentation/screens/products/live_product_detail_screen.dart` — `_buildMatchCard()` method
- **Reuses:** `showAddToListSheet()` from `lib/presentation/widgets/products/add_to_list_sheet.dart` (already imported/used in the file)
- **Model:** Sonnet 4.6 (straightforward UI wiring)

---

### Sprint 2: Product Card Redesign + Compare Button

**Model:** Opus 4.6 (UI/UX design decisions) → Sonnet 4.6 (implementation)
**Goal:** Smaller, more appealing product cards with inline compare button.

**2a. Redesign LiveProductCard**

- **Files:** `lib/presentation/widgets/products/live_product_card.dart`, `lib/presentation/screens/products/live_browse_screen.dart`
- **Changes:**
  - Reduce card size — smaller image (not edge-to-edge), add padding inside card
  - Center image with contained fit (like Checkers does ~60% width)
  - Add subtle card border/shadow for depth
  - Dark mode: grey card background instead of white (`AppColors.surfaceDarkMode` or slightly lighter)
  - Adjust grid `childAspectRatio` from 0.62 to something tighter
- **Reference:** Use `ui-ux-pro-max` skill for design guidance, look at Checkers/PnP apps for inspiration

**2b. Add compare button on product cards**

- **File:** `lib/presentation/widgets/products/live_product_card.dart`
- **Approach:** Add a small compare icon button (e.g. `Icons.compare_arrows`) next to the quick-add button
- **Action:** Calls `showCompareSheet(context, ref, product)` directly from card — already exists in `compare_sheet.dart`

**2c. Less symmetry in card layout**

- Break up the rigid 2-column grid feel — consider slightly varied spacing, rounded corners, card elevation differences between promo/non-promo items

---

### Sprint 3: Smart Product Matching (Core Feature)

**Model:** Opus 4.6 (algorithm design, prompt engineering, architecture)
**Goal:** Dramatically improve price comparison and recipe ingredient matching accuracy.
**Strategy:** Gemini + algorithm hybrid — improve algorithm first, measure reliability, fall back to AI when confidence is low.

#### Completed ✅

**3a. SmartMatchingService created** (`lib/data/services/smart_matching_service.dart`)

- Hybrid algorithm + AI matching with confidence scoring
- `computeConfidence()` scores: brand (0.3) + size (0.25) + variant (0.2) + name similarity (0.25)
- AI escalation via Gemini when confidence < 0.6
- `matchIngredient()` method for recipe ingredient → product matching

**3b. Recipe ingredient matching — plural stemming + disqualifiers**

- Added `_stem()` for singular/plural normalization ("lemons"→"lemon", "eggs"→"egg")
- Expanded `_disqualifyingWords` set (confectionery, baked goods, drinks, cleaning products, condiments, processed food)
- Extra-word rejection for short ingredients (≤2 words with >3 extra product words → reject)
- Disqualification override: nameScore=0 forces final score=0 (no rescue by algorithm confidence)
- Re-weighted blending: 40% algorithm + 60% name score, with `max(blended, nameScore)` floor

**3c. Gemini recipe prompt improvements** (`lib/data/services/gemini_service.dart`)

- Updated prompt to output ingredient names matching real grocery products
- "Table Salt" not "pinch Salt", "Large Eggs" not "beaten Large Eggs 2 units"

**3d. Comprehensive test suite** (`test/product_matching_test.dart` — 62 tests)

- Section 1: Price Compare Matching (45 tests) — search queries, cross-retailer matches, non-matches, variant conflicts, size mismatches
- Section 2: Recipe Ingredient Matching (17 tests) — correct matches, no-viable-match rejection, plural stemming

**3e. Unmatched ingredients from device testing** ✅

Fixed all three originally unmatched ingredients plus additional edge cases found during device testing:

- Hyphen normalization ("stir-fry" → "stir fry")
- Sibilant-aware stemming fix ("cakes" → "cake", not "cak")
- Qualifier-aware containment: color/packaging words (brown, red, tinned, canned) are optional; core food words (powder, seeds) are required
- Disqualifier additions: mustard, ketchup, cracker, pretzel, nacho
- Prep word stripping: skinned, deboned, tinned, canned
- Gemini prompt updated for shorter ingredient names
- "Tap to find a match" UI hint for unmatched ingredients
- 77 tests total (up from 62)

**Files modified:**

- `lib/data/services/gemini_service.dart` — prompt tweaks if ingredient names are the issue
- `test/product_matching_test.dart` — add test cases for hake, stir-fry veggies, sesame seeds

**3f. Quantity matching for price compare (similar products)** ✅

- Size gate in ProductNameParser blocks mismatched quantities (6x1L ≠ 1L, 30-pack ≠ 6-pack)
- Tolerant matching within 5% (400g ≈ 410g)

**3g. UI polish** ✅

- Renamed "Same Product" → "Best Matches" on detail screen
- Cheapest badge on detail screen
- Compare sheet redesigned

---

### Sprint 4: Sort, Filter & Category Browsing ✅ COMPLETE

**Model:** Opus 4.6 (Edge Function + architecture) → Sonnet 4.6 (UI implementation)
**Goal:** Let users browse by category and filter/sort results.

**4a-backend. Edge Function category support** ✅

All 4 edge functions updated and deployed with full subcategory chaining:

- **PnP** (`products-pnp/index.ts`): `PNP_CATEGORIES` map (8 categories), Hybris facet query
- **Checkers** (`products-checkers/index.ts`): `CHECKERS_CATEGORIES` with full subcategory arrays. Multi-facet chaining in `buildProductUrl()`. Beverages routed to `/c-2256/All-Departments` (not food path) with facets: `drinks`, `soft_drinks`, `juices_and_smoothies`, `coffee`, `tea`, `sports_and_energy_drinks`, `bottled_water`
- **Shoprite** (`products-shoprite/index.ts`): `SHOPRITE_CATEGORIES` with full subcategory arrays. Beverages routed to `/c-2256/All-Departments` with facets: `drinks`, `soft_drinks`, `juices_and_smoothies`, `coffee`, `tea`, `bottled_water`
- **Woolworths**: Already supported — 17 ATG nav codes in `CATEGORIES` map

Categories supported across all retailers:
```
Fruit & Veg | Dairy & Eggs | Meat & Poultry | Bakery
Frozen | Food Cupboard | Snacks | Beverages
```

**4a-frontend. Category chip bar + sort/filter** ✅

- `lib/core/constants/product_categories.dart` — cross-retailer category mapping
- `lib/presentation/screens/products/live_browse_screen.dart` — animated category chip bar, sort/filter bottom sheet, active filter bar, healthy-first sort
- `lib/presentation/providers/store_provider.dart` — `_currentCategory` tracking, `_requestId` stale-response discard pattern
- `test/browse_filter_sort_test.dart` — 26 unit tests (sort, filter, category mapping)

**4b-4c. Sort, filter, healthy-first** ✅

- Filter: "Promos only" toggle
- Sort: Relevance (default), Price low→high, high→low, A–Z
- Healthy-first: keyword-based deprioritisation when sort = Relevance

**4d. Deals per category on home screen**

- **File:** `lib/presentation/screens/home/home_screen.dart`
- **Approach:** Render `dealsByRetailer` map as retailer-grouped sections with colored headers via `Retailers.fromName()`
- **Status:** Deferred to Sprint 12 polish pass

**4e. Compact browse header** ✅

- Merged retailer chip bar + store info bar into a single AppBar button (`_StoreAppBarButton`)
- Button shows retailer icon (colored circle) + retailer name + store branch + chevron-down
- Tap opens existing `StorePickerSheet` (handles both retailer + store switching)
- Search moved to hero position (first element in body)
- AppBar gets subtle retailer brand color tint
- Header height reduced ~36% (~170px → ~108px)
- **File:** `lib/presentation/screens/products/live_browse_screen.dart`

---

### Sprint 5: List Management Enhancements ✅ COMPLETE

**Model:** Sonnet 4.6 (UI) → Opus 4.6 (browse+compare UX flow design)
**Goal:** Multi-select delete, browse+manual add toggle from inside lists.

**5a. Multi-select list deletion** ✅

- **File:** `lib/presentation/screens/lists/my_lists_screen.dart`
- Long-press enters selection mode, checkboxes appear, bulk delete in app bar

**5b. Add items from inside list — browse toggle** ✅

- **File:** `lib/presentation/screens/lists/list_detail_screen.dart`
- Tabbed sheet: "Manual" vs "Browse" tabs
  - Manual: form entry, optimistic close + snackbar
  - Browse: retailer chips, live search, "+" and compare buttons per row
  - Compare button opens compare sheet pre-wired to current list
  - Selecting a match adds directly to the list — both sheets close, snackbar shown
- **UX flow finalised:**
  - `+` tap → scale-bounce animation → sheet closes instantly (optimistic) → snackbar
  - Compare tap → compare sheet → select match → scale-bounce → both sheets close instantly → snackbar
  - All adds are fire-and-forget (no 1-2s wait for Supabase round-trip)
- **ScaffoldMessenger** captured before sheets open — snackbar always on main scaffold
- **Overflow fix** on promo price row (Flexible + ellipsis)

---

### Sprint 6: Location & Address Support ✅ COMPLETE

**Model:** Sonnet 4.6 → Opus 4.6 (autocomplete UX)
**Goal:** Let users enter addresses and save locations.

**6a. Address input with geocoding** ✅

- Added `geocoding: ^3.0.0` package (platform-native, free, no API key)
- `LocationService.geocodeAddress()` — converts address → lat/lng
- Nominatim (OpenStreetMap) autocomplete with platform geocoder fallback for exact addresses
- Reusable `AddressSearchField` widget with inline suggestions, debounced search, "press search to use anyway" hint
- **Onboarding** (`store_selection_screen.dart`): "Can't use GPS? Enter an address instead" toggle in error state
- **Browse** (`store_picker_sheet.dart`): "Use a different address" expandable section with saved locations + search
- Store picker sheet: `isScrollControlled: true`, keyboard-aware padding, drag handle tap-to-dismiss

**6b. Saved locations (Home/Work/Custom)** ✅

- `SavedLocation` model (`lib/data/models/saved_location.dart`)
- `SavedLocationsNotifier` + `savedLocationsProvider` backed by SharedPreferences
- Profile screen "My Locations" section with add/delete
- Add location sheet: Home / Work / Other (custom label with UUID) presets
- Store picker sheet: saved locations shown as compact rows inside the expandable address section, with "or search" divider

---

### Sprint 7: Walkthrough Tutorial ✅ COMPLETE

**Model:** Sonnet 4.6
**Goal:** Guide new users through the app on first launch.

**Package:** `tutorial_coach_mark: ^1.2.11`

**Completed:**

- `lib/data/services/tutorial_service.dart` — SharedPreferences wrapper (home/browse/recipes/skip-all/reset flags)
- `lib/presentation/providers/tutorial_provider.dart` — Riverpod provider
- `lib/presentation/widgets/tutorial/tutorial_targets.dart` — `TutorialTooltip` (themed card, step progress dots, tap-to-advance), `buildHomeTutorialTargets`, `buildBrowseTutorialTargets`, `buildRecipesTutorialTargets`
- **Home** (3 steps): welcome dialog → savings banner → hot deals → bottom nav
- **Browse** (4 steps): store selector → search bar → category chips → filter icon
- **Recipes** (1 step): mode selector tooltip on first visit
- **Profile**: "Replay Tutorial" row — resets all flags, navigates to home
- Welcome dialog always white background (consistent contrast in both light/dark mode)
- Race condition fix: `_startTutorialOverlay()` retries every 300ms until GlobalKeys are rendered — handles both fresh load and replay-tutorial flow

---

### Sprint 8: Share Feature Polish ✅ COMPLETE

**Model:** Opus 4.6
**Goal:** Better UX when sharing/collaborating on lists.

**Completed:**

- **Share bottom sheet** (`lib/presentation/widgets/lists/share_list_sheet.dart`) — Replaced plain AlertDialog with full bottom sheet: email input with validation, collaborator list, remove buttons, owner badge with "Owner" pill, inline status banners (success/error) that display within the sheet
- **Sharing metadata on model** (`lib/data/models/shopping_list.dart`) — Added `ownerEmail` (for shared-with-me lists) and `sharedCount` (for owned lists) transient fields
- **Repository enrichment** (`lib/data/repositories/list_repository.dart`) — `getUserLists()` batch-fetches share counts for owned lists and owner emails for shared-with-me lists
- **Provider additions** (`lib/presentation/providers/list_provider.dart`) — `sharedUsersProvider` (family by listId), `shareList()` now rethrows specific error messages
- **List card indicators** (`lib/presentation/screens/lists/my_lists_screen.dart`) — Cards show "Shared with N person/people" (owned) or "Shared by owner@email" (shared-with-me)
- **Specific error messages** — "No user found with email", "cannot share with yourself", "already shared" surfaced inline

---

### Sprint 9: Expand Store Database ✅ COMPLETE

**Goal:** Improve store location coverage across all 4 retailers.

**Completed:**

- **Store count: 394 → 1,394 (3.5x increase)**
  - PnP: 69 → **741** (10.7x) — normalized from existing `pnp_stores_v2.json` (2473 entries, filtered to SA grocery stores)
  - Checkers: 119 → **275** (2.3x) — scraped via Hybris `findStores` endpoint from 112 query points
  - Shoprite: 97 → **250** (2.6x) — scraped via Hybris `findStores` endpoint from 71 query points
  - Woolworths: 109 → **109** — `validatePlace` API returning 500 errors, existing data preserved
- **API discovery:** Checkers/Shoprite `findStores` endpoint works without auth (just `x-requested-with: XMLHttpRequest`). PnP OCC basesites endpoint provided full store list. Woolworths `getPrediction` + `validatePlace` two-step flow.
- **Data enrichment:** Nominatim reverse geocoding for province/city on stores missing that data
- **Data quality:** Filtered non-SA stores (Eswatini, Botswana, Lesotho), validated coordinate bounds, normalized province names
- **PostGIS fix:** Populated `location` geography column for all new stores (`ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)::geography`) — required for `find_all_nearest_stores` RPC distance calculations
- **Verified:** `stores-nearby` edge function returns correct nearest store per retailer from multiple test locations (Irene, Cape Town CBD, Durban CBD)

**Scripts created** (`database/all_stores/`):

| Script | Purpose |
|--------|---------|
| `scrape_checkers_stores.py` | Scrape Checkers via Hybris findStores (112 query points) |
| `scrape_shoprite_stores.py` | Scrape Shoprite via Hybris findStores (71 query points) |
| `scrape_woolworths_stores.py` | Scrape Woolworths via getPrediction + validatePlace |
| `normalize_pnp_stores.py` | Convert pnp_stores_v2.json to standard format |
| `merge_all_stores.py` | Merge all retailers + Nominatim enrichment |
| `import_to_supabase.mjs` | Upsert all_stores_combined.json to Supabase |

---

### Sprint 10: Recipe Export — Ingredient Selection & Retailer Comparison ✅ COMPLETE

**Model:** Opus 4.6 (UX flow design, comparison logic, state management) → Sonnet 4.6 (UI implementation)
**Goal:** Give users full control when exporting a recipe to a shopping list — deselect items they already have, compare total cost across retailers, and swap individual products before committing.

**Completed:**

- **Auto-match on generation** — removed manual "Match Ingredients to Products" button; `generateRecipe()` now lands directly on `matching` step so ingredients are ready immediately after generation
- **10a. Export preparation sheet** (`lib/presentation/widgets/recipes/export_preparation_sheet.dart`) — replaces old AlertDialog; ingredient checklist with checkboxes (matched ✓, unmatched greyed/disabled), list name field, save recipe toggle, "Compare Prices" and "Export" action buttons
- **10b. Retailer comparison sheet** (`lib/presentation/widgets/recipes/retailer_comparison_sheet.dart`) — 4-tab view (PnP, Woolworths, Checkers, Shoprite) with per-retailer basket totals, auto-jumps to cheapest tab on load, ★ badge on cheapest, "Shop at X" confirm button
- **10c. Product swap** — each ingredient row in comparison sheet is tappable; opens `IngredientMatchingSheet` pre-filtered to that retailer; selecting a product updates the basket total live
- **New data models** (`lib/data/models/recipe.dart`) — `RetailerBasket`, `RetailerComparisonState`
- **New provider** (`lib/presentation/providers/recipe_provider.dart`) — `RetailerComparisonNotifier` + `retailerComparisonProvider` (autoDispose); `exportToShoppingList` gains `selectedIngredientIds` param; new `exportRecipeDirectly` for comparison-path export
- **Bug fix: API flood** — comparison previously fired 4×N parallel requests (e.g. 68 for a 17-ingredient recipe), saturating Edge Functions and slowing home/browse/price compare; fixed by making per-retailer ingredient searches sequential (max 4 concurrent)
- **Bug fix: tab overflow + "Shop at" button** — tab bar `Column` overflow fixed with `Tab(height: 48)`; button label now updates correctly on auto-jump and manual tab switch via `_tabController` listener

---

### Sprint 10.5: Checkers/Shoprite Image Fix ✅ COMPLETE

**Model:** Opus 4.6
**Goal:** Fix broken product images for Checkers and Shoprite — replace static 5.2MB lookup cache with server-side image proxy + auto-cache.

**Root cause:** Checkers/Shoprite image URLs return 403 Forbidden without session cookies (CloudFront cookie-gating). Flutter's `Image.network()` can't send cookies.

**Completed:**

- **Image proxy Edge Function** (`supabase/functions/image-proxy/index.ts`) — accepts GET request with retailer image URL, checks Supabase Storage cache first (302 redirect if cached), otherwise creates session with cookies, fetches image, uploads to Storage for future requests, returns image bytes
- **Product code extraction** — regex `(\d{5,}[A-Z]{2}(?:[Vv]\d)?)` handles all 3 Checkers/Shoprite URL patterns (code-first, code-after-size, code-after-medias)
- **Session caching** — in-memory cookie cache (20min TTL) avoids repeated homepage fetches; stale session auto-retry
- **Checkers/Shoprite Edge Functions updated** — `rewriteImageUrl()` rewrites raw retailer image URLs to proxy URLs in `parseProductsFromHtml()`
- **Client-side cleanup** — deleted `image_lookup_cache.json` (-5.2MB APK), `ImageLookupService`, `live_product_image_resolver.dart`, removed all call sites (main.dart, store_provider, recipe_provider, home_screen, compare_sheet, live_product_detail_screen)
- **Deployed** with `--no-verify-jwt` (image widgets can't send auth headers), `IMAGE_STORAGE_SERVICE_KEY` secret set for Storage uploads

**User experience:**
- Cached images (most products over time): instant from Supabase Storage CDN
- First-time images: ~500ms (proxy fetch + auto-cache)
- APK size: ~5MB smaller

---

### Sprint 10.6: Recipe Ingredient Matching — Near-100% Accuracy ✅ COMPLETE

**Model:** Opus 4.6
**Goal:** Dramatically improve recipe ingredient → product matching accuracy from ~80% to near-100%.

**Root cause:** Short/generic ingredient names ("Butter", "Salt", "Milk", "Rice") returned too much noise from retailer search APIs. The scoring algorithm couldn't reliably distinguish actual ingredients from products that merely contain the word (e.g. "Butter Chicken", "Milk Chocolate", "Chocolate Eggs").

**Completed:**

- **Ingredient lookup map** (`lib/data/services/ingredient_lookup.dart`) — static map of ~120 common SA recipe ingredients → optimized search queries + required/exclude word filters. Built from analysis of 42K products across all 4 retailers. Covers dairy, eggs, meat, seafood, produce, pantry, oils, canned goods, baking, spices (including Indian spices), and condiments.
- **Hint-based pre-filtering** (`lib/data/services/smart_matching_service.dart`) — `matchIngredient()` gains optional `IngredientSearchHint` parameter. Pre-filters candidates using required/exclude words before scoring. Graceful degradation: if filtering removes all candidates, falls back to unfiltered. `hintApplied` flag relaxes extra-word rejection for hint-validated candidates.
- **Gemini prompt improvements** (`lib/data/services/gemini_service.dart`) — "NEVER output single-word ingredient names" rule (e.g. "Sunflower Oil" not "Oil", "Large Eggs" not "Eggs"). SA-specific terms section (Maize Meal, Beef Mince, Tinned Tomatoes, Vanilla Essence, Cornflour, Spring Onions, Crushed Garlic/Ginger instead of paste).
- **Pipeline integration** (`lib/presentation/providers/recipe_provider.dart`) — Both `_autoMatchIngredients()` and `RetailerComparisonNotifier.runComparison()` resolve lookup hints and use optimized search queries. pageSize increased 10→15 for better coverage.
- **Expanded disqualifiers** — added personal care (bath, lotion, teeth, toothbrush, deodorant), noodle, curry to `_disqualifyingWords`
- **95 tests** (up from 77) — 6 lookup resolution tests + 12 hint-assisted matching tests covering butter, milk, eggs, salt, sugar, rice, olive oil, cream, onion, garlic, pepper, graceful degradation

**Files:**
- `lib/data/services/ingredient_lookup.dart` (NEW)
- `lib/data/services/smart_matching_service.dart`
- `lib/data/services/gemini_service.dart`
- `lib/presentation/providers/recipe_provider.dart`
- `test/product_matching_test.dart`

---

### Sprint 11: Additional Retailers — SPAR, Dis-Chem, Clicks

**Model:** Opus 4.6 (API reverse-engineering, architecture) → Sonnet 4.6 (implementation)
**Goal:** Expand retailer coverage from 4 to 7 — add SPAR, Dis-Chem, and Clicks.

#### 11a. API Research & Edge Functions

Each retailer needs a Supabase Edge Function that proxies product search + category browse.

**SPAR** (`products-spar/index.ts`)
- Research SPAR online shopping API (myspar.co.za / spar.co.za)
- Identify product search endpoint, pagination, category structure
- Build Edge Function with same interface as existing retailers (query, category, page params → standardized product JSON)
- Map SPAR categories to shared category set (Fruit & Veg, Dairy & Eggs, Meat & Poultry, Bakery, Frozen, Food Cupboard, Snacks, Beverages)

**Dis-Chem** (`products-dischem/index.ts`)
- Research Dis-Chem online API (dischem.co.za)
- Dis-Chem is pharmacy-first but has a large grocery/health food/snacks section
- Focus on food & beverage categories initially, expand to health supplements later
- Build Edge Function with standardized interface

**Clicks** (`products-clicks/index.ts`)
- Research Clicks online API (clicks.co.za)
- Clicks is pharmacy-first with limited grocery — focus on health foods, beverages, snacks, baby food
- Build Edge Function with standardized interface
- Note: Clicks may have fewer grocery categories than other retailers — map what's available

**Common for all 3:**
- CORS headers matching existing pattern
- CSRF/cookie bypass if needed (document approach per retailer)
- HTML entity decoding in product names
- Image URL handling (direct URLs or proxy needed?)
- Deploy with `supabase functions deploy`

#### 11b. Retailer Config Registration

**File:** `lib/core/constants/retailers.dart`
- Add `SPAR`, `Dis-Chem`, `Clicks` to `Retailers.all` map
- Brand colors, icons, slugs, edge function names

**File:** `lib/core/theme/app_colors.dart`
- Add brand colors: SPAR (green #00833E), Dis-Chem (green #00A94F), Clicks (blue #005BAA)

#### 11c. Store Database

- Scrape/collect store locations for SPAR, Dis-Chem, Clicks (lat/lng, name, province, city)
- Scripts in `database/all_stores/` following existing pattern
- Import to Supabase `stores` table with PostGIS `location` column
- Update `stores-nearby` Edge Function to include new retailers in `find_all_nearest_stores` RPC

#### 11d. Category Mapping

**File:** `lib/core/constants/product_categories.dart`
- Add SPAR/Dis-Chem/Clicks category mappings to cross-retailer category map
- Dis-Chem/Clicks may not have all 8 categories — gracefully handle missing ones (hide category chip when browsing those retailers)

#### 11e. Price Comparison Integration

- `SmartMatchingService` / `ProductNameParser` should work out-of-the-box (retailer-agnostic)
- Retailer comparison sheet (`retailer_comparison_sheet.dart`) — add 3 new tabs (7 total)
- Consider tab scrolling or 2-row layout for 7 retailers
- Update `RetailerComparisonNotifier` to search all 7 retailers

#### 11f. Image Handling

- Test if SPAR/Dis-Chem/Clicks images load directly or need proxy
- If proxy needed, update `image-proxy/index.ts` to handle new retailer URL patterns
- If direct URLs work, no changes needed

#### 11g. Testing

- Update `test/product_matching_test.dart` with cross-retailer match cases for new retailers
- Manual test: browse, search, category filter, price compare, recipe export for each new retailer
- Verify store-nearby returns correct nearest store for all 7 retailers

**Estimated complexity:** High — each retailer is essentially a mini-project (API research + Edge Function + store data + testing). Consider splitting into 11-SPAR, 11-DisChem, 11-Clicks sub-sprints.

---

### Sprint 12: Final UI/UX Polish Pass

**Model:** Opus 4.6 (design review & strategy) → Sonnet 4.6 (implementation)
**Goal:** Professional, exciting look across the entire app — now across all 7 retailers.

- Use `ui-ux-pro-max` skill for comprehensive review
- Dark mode audit (all screens)
- Animation polish
- Typography consistency
- Loading state improvements
- Empty state designs
- Error state designs
- Verify retailer branding consistency for SPAR, Dis-Chem, Clicks

---

## Future (Add to CLAUDE.md)

- **FatSecret API** for nutritional information (fat, protein, carbs)
- Diet plan curation and calorie tracking
- Store price history trends
- **Barcode scanner** — scan products in-store, compare prices (needs barcode data in DB first)
- **More retailers** — Game, Makro, Food Lover's Market if demand warrants

## Decisions Made

- **AI matching:** Gemini + algorithm hybrid. Improve algorithm first, add confidence scoring, escalate to Gemini when confidence < 0.6
- **Barcode scanner:** Skipped for now — deprioritized, added to future backlog
- **Categories:** Need to investigate Edge Function responses before planning Sprint 4
- **Start point:** Sprint 1 (quick bug fixes)

---

## iOS Testing Suggestions

- **Simulator:** Use Xcode iOS Simulator on a Mac (free)
- **BrowserStack/Appetize.io:** Cloud-based iOS device testing
- **MacInCloud/MacStadium:** Rent a remote Mac for Xcode builds
- **TestFlight:** Once built on a Mac, distribute to any iPhone via TestFlight
- **Flutter web:** Quick visual check (not full test) via `flutter run -d chrome`

---

## Verification Per Sprint

1. `flutter analyze` — zero warnings
2. Manual test on emulator/physical Android
3. Test both light and dark mode
4. Test all 4 retailers where applicable
5. Commit with conventional commit message
6. Push to GitHub
