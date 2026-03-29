# Milk App — Incremental Bug Fix & Enhancement Plan

## Context

The app is in closed beta heading toward public launch. Focus is on fixing bugs, improving core matching, and polishing UI/UX. Work is split into incremental sprints — each sprint is tested manually on device/emulator, committed, then we move on.

## Model Selection Guide

Choose the best model for each task based on complexity:

- **Sonnet 4.6** — Bug fixes, unused import cleanup, padding fixes, simple UI tweaks, boilerplate code, repetitive changes
- **Opus 4.6** — Architecture decisions, AI matching algorithm design, complex state management, prompt engineering, deep refactors, UI/UX design strategy

---

## Sprint Order (priority-based, dependencies respected)

### Sprint 1: Quick Bug Fixes (low risk, high impact) ✅

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

### Sprint 2: Product Card Redesign + Compare Button ✅

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

### Sprint 3: Smart Product Matching (Core Feature) ✅

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

| Script                        | Purpose                                                  |
| ----------------------------- | -------------------------------------------------------- |
| `scrape_checkers_stores.py`   | Scrape Checkers via Hybris findStores (112 query points) |
| `scrape_shoprite_stores.py`   | Scrape Shoprite via Hybris findStores (71 query points)  |
| `scrape_woolworths_stores.py` | Scrape Woolworths via getPrediction + validatePlace      |
| `normalize_pnp_stores.py`     | Convert pnp_stores_v2.json to standard format            |
| `merge_all_stores.py`         | Merge all retailers + Nominatim enrichment               |
| `import_to_supabase.mjs`      | Upsert all_stores_combined.json to Supabase              |

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

### Sprint 11: Additional Retailers — Makro, Dis-Chem, Clicks ✅

**Model:** Opus 4.6 (API reverse-engineering, architecture) → Sonnet 4.6 (implementation)
**Goal:** Expand retailer coverage from 4 to 7 — add Makro, Dis-Chem, and Clicks.

**Priority order:** Makro → Dis-Chem → Clicks (tackle individually as sub-sprints).

> **SPAR deferred:** SPAR is a franchise model — each store is independently owned with no centralized product/price API. Research (2026-03-21) found:
>
> - `spar.co.za/SPAR-Products` — own-brand catalog only, no prices, server-rendered HTML
> - `sparsame.com` / `easyquote-dcs.co.za` — working JSON API but only 1 store (SPAR Botswana)
> - `mobile.spar.co.za` — loyalty/rewards Rails app, no product catalog
> - `spar2u.myshopify.com` → redirects to SPAR2U Sri Lanka, not SA
> - SPAR2U SA app backend remains unknown (APK decompilation blocked by download site JS)
> - **Revisit if:** SPAR launches a centralized e-commerce platform, or someone captures SPAR2U network traffic via mitmproxy/HTTP Toolkit

#### Sprint 11.1: Makro ✅ COMPLETE

**Edge Function** (`supabase/functions/products-makro/index.ts`) — DEPLOYED

- Flipkart Commerce Cloud API (`POST https://www.makro.co.za/fccng/api/4/page/fetch`)
- No auth needed — browser-like headers only (user-agent, origin, referer)
- Search: `pageUri: "/search?q={query}&store=eat"` — 40 products/page
- Category browse: `pageUri: "/food-products/pr?sid=eat"` with search-based mapping
- Pagination via `pageContext.pageNumber` + `paginatedFetch: true` for page 2+
- Product data from `RESPONSE.slots[].widget.data.products[].productInfo.value`
- National pricing (no per-store prices — 22 warehouse stores)
- **Promo detection fix:** priceTag filtering only uses tags with actual discount keywords (off, save, %, for r, was r, half price) — prevents false positives from "New", "Best Seller", "Bundle Deal" labels
- **Home screen integration:** Multi-page fetch (4 pages) for Makro since promos are sparse; parses "X% off - Was RY.YY" and "Save RX.XX" promo formats
- **Browse promo filter fix:** Shows skeleton loading while auto-fetching more pages instead of flashing "No promos" between fetches
- Store database: 22 Makro warehouse locations imported to Supabase with PostGIS
- Image handling: direct FCC CDN URLs (`{@width}/{@height}/{@quality}` → 312/312/70) — no proxy needed

**Flutter Registration:**

- `retailers.dart` — Makro added with brand color, icon, slug, edge function name
- `app_colors.dart` — `makro = Color(0xFF003DA5)` (Makro blue)
- `product_categories.dart` — Makro category mappings (search-based, not facet-based)

#### Sprint 11.2: Dis-Chem ✅ COMPLETE

- Magento 2 REST API (`GET https://www.dischem.co.za/rest/V1/products?searchCriteria[...]`)
- No auth needed — fully open public API
- Search via `name` field with `like` condition, pagination via `pageSize` + `currentPage`
- Image: `https://www.dischem.co.za/media/catalog/product/{path}` from `media_gallery_entries[].file`
- Categories API: `GET /rest/V1/categories` — full tree, no auth
- Limited grocery range — primarily health food, supplements, baby, snacks
- 318 stores nationwide
- Edge Function deployed, Flutter registration complete, store database imported

#### Sprint 11.3: Clicks ✅ COMPLETE

- SAP Hybris + Algolia search — Algolia keys extracted and stored as Supabase secrets
- Limited grocery — food cupboard, snacks, chocolates only
- 600+ stores
- Edge Function deployed, Flutter registration complete, store database imported

#### Common tasks (11b-11h) ✅ ALL COMPLETE

- **11b. Retailer Config** — All 3 retailers registered (retailers.dart, app_colors.dart)
- **11c. Store Database** — All stores imported to Supabase with PostGIS
- **11d. Category Mapping** — All 3 retailers mapped in product_categories.dart
- **11e. Price Comparison** — Working across all 7 retailers with scrollable tabs
- **11f. Recipe Matching** — Retailer-agnostic, works as-is
- **11g. Image Handling** — Makro: direct CDN. Dis-Chem: Magento media URLs. Clicks: Hybris media URLs.
- **11h. Testing** — Cross-retailer matching verified

---

### Sprint 12: Final UI/UX Polish Pass ✅

**Model:** Opus 4.6 (design review & strategy) → Sonnet 4.6 (implementation)
**Goal:** Professional, exciting look across the entire app — now across all 7 retailers.

#### Completed ✅

- **Lottie loading animations** — replaced `CircularProgressIndicator` with `LottieLoadingIndicator` in compare sheet, browse-inside-list search, and other loading states
- **Error/empty state Lottie animations** — all 7 `EmptyState` types now have Lottie animations (error.json, lost_connection.json, empty.json, shopping_bag_empty.json, shopping_cart.json)
- **Typography consistency** — eliminated all off-theme font sizes (13/15/17/18/22px → snapped to theme scale: 11/12/14/16/20/24), standardized font weights (w800→w700, bold→w700), normalized notation across 7 files (~30 fixes)
- **New reusable widgets** — `LottieLoadingIndicator`, `ShimmerText`, `GlassContainer`, `ProductDetailCard`
- **Deals loading animation** — SA-themed Lottie grocery bag with rotating messages + animated dots

#### Remaining

- Dark mode audit (all screens)
- Use `ui-ux-pro-max` skill for comprehensive review
- Verify retailer branding consistency for Makro, Dis-Chem, Clicks

#### Sprint 12.8: Makro Promo & Home Screen Fixes (2026-03-21)

**Completed:**

- **Makro promo filter fix** — Edge function priceTag filtering was falsely marking non-promo products (tagged "New", "Best Seller") as on-sale. Fixed to only use tags with discount keywords (off, save, %, for r, was r, half price).
- **Browse promo skeleton loading** — Promo filter now shows skeleton while auto-fetching more pages for retailers with sparse promos (Makro), instead of flashing "No promos found" between page fetches.
- **Makro deals on home screen** — Multi-page fetch (4 pages) since Makro promos are sparse. Added parsing for "X% off - Was RY.YY" and "Save RX.XX" promo formats.
- **Hot deals expanded** — Increased from 8 to 20 deals shown. Retailer sections show all deals (removed `.take(6)` cap).
- **Retailer ordering** — Grocery-first, pharmacy-last in home screen sections.
- **Strawberry/cream mismatch fix** — "PnP Double Cream Strawberries & Cream" (dessert) no longer matches as "Similar" to fresh "Strawberries 400g". Added multi-word phrase detection (`_categoryMismatchPhrases`) for dairy/dessert products.
- **105 matching tests passing** (up from 95).

---

### Sprint 12.5: Post-Release Bug Fixes & UX Improvements ✅ COMPLETE

**Model:** Opus 4.6
**Goal:** Fix bugs reported after v1.1.0+3 Play Store release, improve discoverability.

**Completed:**

- **Recipe re-match bug fix** — `reMatchWithRetailer()` was setting `currentStep: review` instead of `matching`, which hid the "Change"/"Match" buttons and "Export to Shopping List" button after switching retailers. One-line fix in `recipe_provider.dart`. Added robustness guard: export button now also shows in `review` step when ingredients are matched.
- **List sync bug fix** — Items added from browse screen didn't appear in list detail until app restart. Root cause: `ListItemNotifier.addItem()` didn't invalidate `realtimeListItemsProvider(listId)`, which `list_detail_screen.dart` watches. Added the missing invalidation.
- **Default recipe matching uses browse retailer** — Initial auto-match now uses the currently selected retailer from the browse screen (via `selectedRetailerProvider`) instead of "All Stores". Active store chip is visually highlighted with filled background. `matchedRetailer` tracked in `RecipeGenerationState`.
- **Lottie loading for "Use Ingredients"** — Replaced `CircularProgressIndicator` in `recipe_suggestions_card.dart` with `LottieLoadingIndicator`.
- **Savings count-up animation slowed** — Duration increased from 1500ms to 2500ms, curve changed to `easeOutQuart` for more dramatic deceleration on fast devices.
- **Long-press multi-select for list items** — Added long-press selection mode to `list_detail_screen.dart` (reused pattern from `my_lists_screen.dart`). All 3 deletion methods available: swipe-left (quick), tap-edit-bin (deliberate), long-press multi-select (bulk). Selection mode shows count + delete button in AppBar, selection indicators replace checkboxes.
- **Expanded tutorials** — Recipe result tutorial (3 steps: matched ingredients, store chips, export button) triggers on first recipe generation. Lists tutorial (2 steps: create FAB, list card management) triggers on first Lists tab visit. List detail tutorial (2 steps: add items, item management hints). Added `recipeResult` and `lists` tutorial completion tracking to `TutorialService`.

**Deferred:**

- **Missing stores** (Woolworths Irene Village Mall, Woolworths Southdowns, Checkers/Woolworths Lorraine PE) — requires store code validation against retailer APIs, deferred to separate data task.

**Files modified:**

- `lib/presentation/providers/recipe_provider.dart` — re-match step fix, matchedRetailer tracking
- `lib/presentation/providers/list_provider.dart` — realtimeListItemsProvider invalidation
- `lib/presentation/widgets/recipes/recipe_result_card.dart` — export button robustness, matchedRetailer prop, store chip highlighting, tutorial GlobalKeys
- `lib/presentation/widgets/recipes/recipe_suggestions_card.dart` — Lottie loading
- `lib/presentation/screens/recipes/recipe_screen.dart` — browse retailer passthrough, recipe result tutorial trigger
- `lib/presentation/screens/home/home_screen.dart` — animation duration + curve
- `lib/presentation/screens/lists/list_detail_screen.dart` — long-press multi-select
- `lib/presentation/screens/lists/my_lists_screen.dart` — lists tutorial
- `lib/data/services/tutorial_service.dart` — new tutorial keys
- `lib/presentation/widgets/tutorial/tutorial_targets.dart` — recipe result, lists, list detail tutorial targets

---

### Sprint 12.6: Tutorial & Auth Hardening ✅ COMPLETE

**Model:** Opus 4.6
**Goal:** Fix tutorial overlay bugs, improve auth resilience, pass retailer context through recipe flow.

**Completed:**

- **Tutorial overlay black screen fix** — Recipe result tutorial replaced TutorialCoachMark (which caused stuck black overlays when tooltips rendered off-screen) with AlertDialog showing 3 tip rows. Root cause: library's `_buildContents` Stack fills entire overlay, blocking taps when tooltip is off-viewport.
- **SKIP button moved into tutorial cards** — All `TutorialTooltip` widgets now have inline SKIP button (bottom-right of card) instead of library's bottom-of-screen skip text. Removed `textSkip`/`textStyleSkip` from all TutorialCoachMark instances, replaced with `hideSkip: true`.
- **Auth profile retry with backoff** — `getUserProfile()` now retries up to 3 times with exponential backoff (2s, 4s) on transient network errors (SocketException, DNS lookup, connection refused/reset, timeout). Prevents sign-in failures on flaky networks.
- **Recipe matching respects selected retailer** — "Use Ingredients" suggestions now pass `preferredRetailer` from `selectedRetailerProvider`. Ingredient matching sheet opens pre-filtered to the active matched retailer (with empty-string-to-null normalization for "All Stores").
- **Tutorial GlobalKey cleanup** — Removed `ingredientsSectionKey`, `storeSelectorKey`, `exportButtonKey` from `recipe_result_card.dart` (no longer needed after dialog replacement).

**Files modified:**

- `lib/presentation/widgets/tutorial/tutorial_targets.dart` — SKIP in card, recipe result targets refactored
- `lib/presentation/screens/recipes/recipe_screen.dart` — AlertDialog tutorial, retailer passthrough, matching sheet initialRetailer
- `lib/presentation/widgets/recipes/recipe_result_card.dart` — removed tutorial GlobalKeys
- `lib/presentation/screens/home/home_screen.dart` — hideSkip: true
- `lib/presentation/screens/products/live_browse_screen.dart` — hideSkip: true
- `lib/presentation/screens/lists/my_lists_screen.dart` — hideSkip: true
- `lib/data/repositories/auth_repository.dart` — retry with exponential backoff

---

### Sprint 12.7: Add-to-List Bottom Sheet UX Fix ✅

**Model:** Opus 4.6 (UX design) → Sonnet 4.6 (implementation)
**Status:** COMPLETED
**Goal:** Fix keyboard-covering-fields UX issue in the add-to-list bottom sheet. Users report they can't see what they're typing because the keyboard covers the input fields.

**Completed:**

- 12.7a: Replaced quantity TextField with +/- stepper (long-press repeat, clamped 1-99) in add-to-list sheet, manual add tab, and browse add confirmation
- 12.7b: Fixed keyboard covering notes field — keyboard-aware maxHeight (75%→90%), ScrollController + FocusNode auto-scroll, viewInsets padding
- 12.7c: "Add to List" button moved outside scroll area (sticky), "Note" label above field, AppColors theming for dark mode
- Bonus: Browse tab's instant-add `+` button now opens a confirmation sheet with quantity stepper + note field instead of instant qty-1 add

**User complaint:** "When I try to type a note, the keyboard appears and covers the text field so I can't see what I'm typing."

**File:** `lib/presentation/widgets/products/add_to_list_sheet.dart`

#### 12.7a. Quantity: Replace text input with +/- stepper

**Problem:** Quantity field uses a `TextField` with number keyboard — opening the keyboard pushes content around and is overkill for incrementing a simple count.

**Fix:** Replace the 80px-wide `TextField` with a horizontal stepper widget:

- `[ - ]  2  [ + ]` layout
- Minus button: decrement (min 1), Plus button: increment (no max, reasonable default cap at 99)
- Display quantity as styled `Text` widget between buttons (no keyboard needed)
- Buttons: 36x36 circular `IconButton` with `Icons.remove` / `Icons.add`
- Long-press on +/- for fast increment/decrement (repeat every 150ms after 400ms hold)
- Remove `_quantityController` — use simple `int _quantity = 1` state variable

#### 12.7b. Notes: Fix keyboard covering the text field

**Problem:** The bottom sheet uses `isScrollControlled: true` and `maxHeight: 75%` with a `SingleChildScrollView`, but when the keyboard opens, the notes field gets pushed behind the keyboard.

**UX solution — sheet expands + auto-scrolls on focus:**

1. **Wrap sheet content in `Padding` with `MediaQuery.of(context).viewInsets.bottom`** — this is the standard Flutter pattern to make bottom sheets keyboard-aware. The sheet will automatically resize to sit above the keyboard.
2. **Use `Scrollable.ensureVisible()` on notes field focus** — when the notes `TextField` gains focus, auto-scroll the `SingleChildScrollView` so the field is fully visible above the keyboard.
3. **Add a `FocusNode` to the notes field** — listen for focus changes, trigger scroll-to-visible.
4. **Remove `maxHeight` constraint when keyboard is open** — let the sheet expand up to 90% of screen height when keyboard is active, then shrink back to 75% when dismissed.
5. **Add bottom padding equal to keyboard height** — inside the `SingleChildScrollView`, add `SizedBox(height: viewInsets.bottom)` at the end so there's room to scroll the notes field fully into view.

**Implementation pattern (Flutter-idiomatic):**

```dart
// In build():
final bottomInset = MediaQuery.of(context).viewInsets.bottom;
final keyboardOpen = bottomInset > 0;

// Sheet max height expands when keyboard is open
maxHeight: keyboardOpen ? 0.9 : 0.75,

// Padding at bottom of sheet body
padding: EdgeInsets.only(bottom: bottomInset),
```

```dart
// Auto-scroll when notes field gains focus
final _notesFocusNode = FocusNode();
final _scrollController = ScrollController();

@override
void initState() {
  super.initState();
  _notesFocusNode.addListener(() {
    if (_notesFocusNode.hasFocus) {
      Future.delayed(Duration(milliseconds: 300), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      });
    }
  });
}
```

#### 12.7c. Visual polish

- Stepper buttons use `AppColors` theme colors (work in both light/dark mode)
- Notes field gets a visible label above it (not just placeholder) per UX best practice
- "Add to List" button stays anchored at the bottom (outside the scroll area) so it's always reachable
- Smooth animation when sheet height changes (keyboard open/close)

**Testing:**

- Test on physical Android device with varying screen sizes
- Verify quantity stepper works: tap, long-press rapid increment, min boundary (1)
- Verify notes field: keyboard opens, field stays visible, can see text while typing
- Verify "Add to List" button remains accessible with keyboard open
- Test both light and dark mode

---

### Sprint 13: Fuel Cost Estimates & Trip Comparison ✅

**Status:** COMPLETED

**Model:** Opus 4.6 (UX design, cost model architecture) → Sonnet 4.6 (implementation)
**Goal:** Show users the true cost of shopping at each store — product prices + fuel cost for the round trip — and compare against delivery app fees so they can make the smartest choice.

**Completed:**
- [x] 13a. Vehicle config data model (`vehicle_config.dart`) — VehicleConfig, FuelPrice, FuelCostBreakdown, DeliveryFeeConfig
- [x] 13b. Fuel prices backend — `fuel_prices` Supabase table + `fuel-prices` Edge Function (scrapes AA AJAX endpoint)
- [x] 13c. Fuel price client — `FuelPriceService` with 7-day SharedPreferences cache + `fuelPriceProvider`
- [x] 13d. Fuel cost calculation engine — `FuelCostService` with round-trip fuel + delivery comparison
- [x] 13e. Profile UI — "My Vehicle" section with vehicle type cards, fuel type dropdown, region chips, Lottie header
- [x] 13f. Trip Cost card on list detail screen — collapsible per-retailer breakdown with delivery comparison
- [x] 13g. Browse screen fuel hint — distance + fuel cost subtitle on store picker
- [x] 13h. Lottie animations — car_driving, car_question, fuel_pump (static icon used for small Trip Cost header)
- [x] 13i. Vehicle config scoped per user (SharedPreferences keyed by user ID, reloads on login/logout)
- [x] Bug fix: Checkers Sixty60 delivery fee corrected (not free — R35 base fee)

#### Why this matters

A shopping list might be R12 cheaper at Store A, but if Store A is 15km away and Store B is 2km away, the fuel cost wipes out the savings. Users currently have no visibility into this. Delivery apps (Checkers Sixty60, Woolworths Dash, PnP asap) are an alternative — sometimes cheaper than driving, sometimes not. This feature makes the hidden cost visible.

#### 13a. Data Model — Vehicle & Fuel Configuration

**New model:** `lib/data/models/vehicle_config.dart`

```dart
enum VehicleType { small, medium, large, suv, custom }

class VehicleConfig {
  final VehicleType type;
  final double consumptionPer100km; // L/100km
  final String label; // "Small Car", "Medium Car", etc.
}
```

**Default consumption rates** (SA averages, L/100km):
| Type | City | Highway | Blended (used) |
|------|------|---------|-----------------|
| Small (e.g. VW Polo, Toyota Starlet) | 6.5 | 5.0 | 5.8 |
| Medium (e.g. Toyota Corolla, Mazda 3) | 8.5 | 6.5 | 7.5 |
| Large / SUV (e.g. Fortuner, Rav4) | 11.0 | 8.5 | 9.8 |
| Custom | user-entered | user-entered | user-entered |

**Fuel prices** (SA DoE publishes new prices on the first Wednesday of every month):
- 93 ULP (inland): R20.19/L (March 2026)
- 95 ULP (coast): R19.47/L, (inland): R20.30/L
- Diesel 50ppm (coast): R17.84/L, (inland): R19.17/L
- Diesel 500ppm (coast): R17.47/L, (inland): R18.78/L

**Storage:** `SharedPreferences` via `VehicleConfigNotifier` (Riverpod). Fields: `vehicleType`, `consumptionPer100km`, `fuelType` (petrol93/petrol95/diesel50/diesel500), `region` (coast/inland — auto-detected from GPS, overridable).

**Fuel price source — live from Supabase (NOT hardcoded):**

SA fuel prices change monthly. Hardcoding would require an app update every month. Instead:

1. **Supabase table `fuel_prices`:**
   ```sql
   CREATE TABLE fuel_prices (
     id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
     fuel_type text NOT NULL,        -- 'petrol_93', 'petrol_95', 'diesel_50ppm', 'diesel_500ppm'
     region text NOT NULL,           -- 'coast', 'inland'
     price_per_litre numeric NOT NULL,
     effective_date date NOT NULL,   -- first Wednesday of month
     created_at timestamptz DEFAULT now()
   );
   ```

2. **Edge Function `fuel-prices/index.ts`:**
   - Scrapes latest prices from AA (`aa.co.za/fuel-pricing`) or DoE website on demand
   - Parses the fuel price table (HTML table or PDF)
   - Upserts into `fuel_prices` table
   - Returns current prices as JSON
   - **Fallback:** If scraping fails, returns most recent prices from the table (always has data)

3. **Cron trigger (Supabase pg_cron or external):**
   - Runs on the 1st and 2nd Wednesday of each month (covers announcement day + buffer)
   - Calls the Edge Function to refresh prices
   - Alternatively: the app calls the Edge Function on launch if cached prices are >30 days old

4. **Flutter client flow:**
   - On app launch (or first fuel cost calculation), fetch `/fuel-prices`
   - Cache in SharedPreferences with `lastFetchedDate`
   - Re-fetch if cache is older than 7 days
   - Offline fallback: use cached prices (never block the user)

5. **Manual override:** If scraping breaks (website changes), we can manually INSERT new rows into `fuel_prices` via Supabase dashboard — no app update needed.

#### 13b. Cost Calculation Engine

**New service:** `lib/data/services/fuel_cost_service.dart`

```dart
class FuelCostService {
  /// Calculate fuel cost for a round trip to a store
  FuelCostBreakdown calculateTripCost({
    required double distanceKm,       // one-way, from StoreSelection
    required VehicleConfig vehicle,
    required FuelPrice fuelPrice,
  });
}

class FuelCostBreakdown {
  final double distanceKm;           // one-way
  final double roundTripKm;          // distance * 2
  final double fuelUsedLitres;       // roundTripKm * (consumption / 100)
  final double fuelCostRands;        // fuelUsedLitres * pricePerLitre
  final double wearAndTearRands;     // roundTripKm * aaRatePerKm (optional)
  final double totalTripCost;        // fuelCost + wearAndTear
}
```

**AA rates per km (2026)** — optional "full cost" mode:
| Vehicle value | Rate/km | Notes |
|---------------|---------|-------|
| R100k–R200k | R4.62/km | Includes depreciation, fuel, maintenance, insurance |
| R200k–R400k | R5.28/km | |
| R400k–R600k | R6.42/km | |

AA rates are the "true" cost of driving (not just fuel). Show as a toggle: "Include vehicle wear & tear (AA rates)" — defaults OFF, power users can enable.

**Delivery app fees** (hardcoded, updatable):
| App | Base fee | Free delivery threshold | Notes |
|-----|----------|------------------------|-------|
| Checkers Sixty60 | R36 | R500+ (free) | Most popular SA grocery delivery |
| Woolworths Dash | R45 | R350+ (free) | Premium groceries |
| PnP asap | R35 | R400+ (free) | Wide coverage |

#### 13c. Vehicle Configuration UI

**Arguments for Profile placement (winner):**
- Set once, applies everywhere — most users don't change cars often
- Keeps browse/list screens uncluttered
- Natural home next to "My Locations" section
- Matches mental model: "my car" is about me, not about a specific shopping trip

**Arguments for Browse placement:**
- Discoverability: users might not know the feature exists if buried in Profile
- Quick switching: rental car, borrowed car, passenger scenarios
- But: these are edge cases, and a "Change vehicle" link on the cost breakdown handles this

**Decision: Primary config in Profile, with quick-change link on cost breakdowns.**

**Profile screen addition:**

New section "My Vehicle" between "My Locations" and "Appearance":
- Vehicle type selector: 4 illustrated cards (Small / Medium / Large-SUV / Custom)
  - Each card shows a simple car silhouette icon + consumption range
  - Selected card gets emerald green border + checkmark
- Custom mode: expands a slider or text field for L/100km (range 3.0–20.0, step 0.1)
- Fuel type dropdown: Petrol 93 / Petrol 95 / Diesel 50ppm / Diesel 500ppm
- Region: Coast / Inland (auto-detected, with override toggle)
- "Not sure?" helper text: "Check your car's manual or dashboard for fuel consumption. City driving is usually 6-10 L/100km."

**Lottie animations for vehicle config:**
- Car driving animation for the vehicle type selector header
- Fuel pump animation for fuel type section
- Sources: LottieFiles / IconScout — search "car driving", "fuel pump", "gas station"
- Suggested: compact 100x100px Lottie in the section header, not full-screen

#### 13d. Shopping List Fuel Cost Breakdown

**Where it appears:** On the `list_detail_screen.dart`, as a collapsible section below the item list.

**Layout — "Trip Cost" card:**

```
┌─────────────────────────────────────────┐
│  Trip Cost Estimate                  ▼  │
│─────────────────────────────────────────│
│                                         │
│  Products           R 342.50           │
│  ┌─ Pick n Pay       R 198.00          │
│  ├─ Woolworths       R 144.50          │
│  └─ (no store)       R 0.00            │
│                                         │
│  Fuel (2 stores)     R 24.80           │
│  ┌─ PnP Centurion (3.2km) R 7.40      │
│  └─ Woolworths Mall (8.1km) R 17.40   │
│                                         │
│  ─────────────────────────────────────  │
│  Total               R 367.30           │
│                                         │
│  ┌─ vs Delivery ──────────────────────┐ │
│  │ Checkers Sixty60    R 36.00        │ │
│  │ PnP asap            R 35.00        │ │
│  │ Woolworths Dash     R 45.00        │ │
│  │                                    │ │
│  │ Driving saves R 10.20 vs Sixty60   │ │
│  │ (or costs R 14.80 more than Dash)  │ │
│  └────────────────────────────────────┘ │
│                                         │
│  [Car icon] Medium Car · 7.5 L/100km   │
│  Petrol 95 inland · R20.30/L  [Change] │
└─────────────────────────────────────────┘
```

**UX details:**
- Collapsed by default — shows just "Trip Cost: R367.30" with expand chevron
- Expandable to full breakdown
- "Change" link opens vehicle config (navigates to Profile or opens inline bottom sheet)
- Color coding: green text when driving is cheaper, red when delivery is cheaper
- If no vehicle configured: show "Set up your vehicle to see fuel costs" with a car Lottie + "Configure" button
- Items without a retailer (manually added) are excluded from fuel calculation
- If all items are from one store, show single-store fuel cost
- Round trip assumed (home → store → home, for each unique store)
- Multi-store route: currently sum of individual round trips (conservative). Future: optimize route (home → store A → store B → home)

**Delivery comparison logic:**
- Only show delivery apps for retailers that have delivery services (Checkers → Sixty60, PnP → asap, Woolworths → Dash)
- Compare: fuel cost for that retailer's store vs delivery fee
- If basket total exceeds free delivery threshold, show "FREE delivery" instead of fee
- Makro/Shoprite/Dis-Chem: no delivery comparison (no mainstream delivery app)

#### 13e. Browse Screen Integration (Lightweight)

**NOT a full vehicle config on browse** — just a subtle fuel cost hint per store.

On the store picker sheet or store info bar, show:
- "~R7.40 fuel round trip" next to the store distance
- Only shows if vehicle is configured
- Tapping opens the full Trip Cost breakdown (or prompts to configure vehicle if not set)

#### 13f. Lottie Animations

| Location | Animation | Size | Source suggestion |
|----------|-----------|------|-------------------|
| Vehicle config header (Profile) | Car driving on road | 120x80px | LottieFiles "car driving flat" |
| Trip Cost card header | Fuel gauge / pump | 48x48px | LottieFiles "fuel pump" |
| "No vehicle configured" empty state | Car with question mark | 150x150px | LottieFiles "car confused" |
| Delivery vs Driving verdict | Thumbs up (savings) or warning | 32x32px | Existing Lottie set |

Keep animations subtle — they accent the data, not distract from it. `prefers-reduced-motion` respected (static fallback icon).

#### 13g. Implementation Order

1. **Fuel prices backend** — `fuel_prices` Supabase table + `fuel-prices` Edge Function (scrape AA/DoE, upsert, return JSON)
2. **Fuel price client** — `FuelPriceService` (fetch + 7-day SharedPreferences cache) + `FuelPriceNotifier` provider
3. **Data model + service** — `VehicleConfig`, `FuelCostService`, `VehicleConfigNotifier`
4. **Profile UI** — "My Vehicle" section with vehicle type cards, fuel type, region
5. **List breakdown** — Trip Cost card on `list_detail_screen.dart`
6. **Delivery comparison** — within Trip Cost card
7. **Browse hint** — fuel cost hint on store picker
8. **Lottie animations** — source and integrate
9. **Testing** — unit tests for `FuelCostService`, Edge Function curl test, manual on-device testing

#### 13h. Files to Create/Modify

| File | Action |
|------|--------|
| `supabase/functions/fuel-prices/index.ts` | **Create** — scrape AA/DoE fuel prices, upsert to Supabase |
| `database/migrations/create_fuel_prices.sql` | **Create** — `fuel_prices` table schema |
| `lib/data/models/vehicle_config.dart` | **Create** — VehicleConfig, FuelPrice, FuelCostBreakdown models |
| `lib/data/services/fuel_cost_service.dart` | **Create** — calculation engine |
| `lib/data/services/fuel_price_service.dart` | **Create** — fetch + cache fuel prices from Supabase |
| `lib/presentation/providers/vehicle_provider.dart` | **Create** — VehicleConfigNotifier + SharedPreferences persistence |
| `lib/presentation/providers/fuel_price_provider.dart` | **Create** — FuelPriceNotifier with 7-day cache |
| `lib/presentation/screens/profile/profile_screen.dart` | Modify — add "My Vehicle" section |
| `lib/presentation/screens/lists/list_detail_screen.dart` | Modify — add Trip Cost breakdown card |
| `lib/presentation/widgets/lists/trip_cost_card.dart` | **Create** — the collapsible cost breakdown widget |
| `lib/presentation/screens/products/live_browse_screen.dart` | Modify — fuel hint on store info |
| `lib/core/constants/app_constants.dart` | Modify — delivery fee constants |
| `assets/lottie/car_driving.json` | **Create** — source from LottieFiles |
| `assets/lottie/fuel_pump.json` | **Create** — source from LottieFiles |
| `test/fuel_cost_test.dart` | **Create** — unit tests for FuelCostService |

---

### Sprint 14: List Price Comparison ✅

**Status:** COMPLETED

**Model:** Opus 4.6 (UX design, architecture) → Sonnet 4.6 (implementation)
**Goal:** Let users compare an entire shopping list's prices across retailers — find the cheapest store for the whole basket, not just individual items.

**Completed:**
- [x] 14a. Compare button — emerald pill in list header (next to total price, contextual placement)
- [x] 14b. ListComparisonNotifier — parallel search across 4 grocery retailers, progressive loading
- [x] 14c. ListComparisonSheet — full-screen bottom sheet with retailer tabs, winner card, trophy Lottie
- [x] 14d. Fair comparison — only items matched at ALL retailers count toward cheapest (common-items logic)
- [x] 14e. Match quality gate — only exact (>=0.80) and similar (>=0.55) matches accepted, fallback rejected
- [x] 14f. Fuel cost integration — per-retailer fuel cost from Sprint 13 (optional, if vehicle configured)
- [x] 14g. Human-centered savings — relatable SA grocery items with emoji ("That's a loaf of bread and 2L of milk!")
- [x] 14h. Apply retailer — "Shop at X" re-assigns all list items to selected retailer in Supabase
- [x] 14i. Per-item cheapest — green highlight on the cheapest price for each item across retailers
- [x] 14j. 47 unit tests — models, savings translator, common-items logic, edge cases

#### Key design decisions

- **Common-items comparison:** Winner is determined using ONLY items found at ALL retailers. Prevents a retailer "winning" by matching fewer items at lower total. Winner card shows "Based on X items found at all stores".
- **Match threshold:** Raised to >=0.55 (similar) minimum. Fallback matches (<0.55) treated as not found. Aligns with existing compare_sheet.dart behavior.
- **Compare button placement:** Moved from AppBar to list header (next to total price) after UX review — contextual proximity to the data it acts on. Keeps AppBar clean with 3 actions: sync, add, menu.
- **SavingsTranslator:** Uses March 2026 SA grocery prices (bread R16, milk R27, sugar R20, eggs R65, chicken R75).

#### Files created

| File | Purpose |
|------|---------|
| `lib/data/models/list_comparison.dart` | ListItemMatch, ListRetailerBasket, ListComparisonState, SavingsTranslator |
| `lib/presentation/providers/list_comparison_provider.dart` | ListComparisonNotifier with parallel search, fuel cost, apply retailer |
| `lib/presentation/widgets/lists/list_comparison_sheet.dart` | Full-screen comparison sheet with winner card, tabs, progress chips |
| `test/list_comparison_test.dart` | 47 unit tests |

#### Files modified

| File | Change |
|------|--------|
| `lib/presentation/screens/lists/list_detail_screen.dart` | Added compare button to _ListHeader, import |

---

### Sprint 15: Admin Dashboard

**Model:** Opus 4.6
**Goal:** Build an admin dashboard to monitor users, track app health, and identify backend issues.

**Scope:**

- User activity monitoring (signups, active users, retention)
- Error/issue tracking (failed API calls, auth errors, crash reports)
- Store data health checks (missing stores, stale data, broken images)
- Recipe generation metrics (success rate, matching accuracy, popular recipes)
- Shopping list usage stats (lists created, items added, sharing activity)
- Real-time alerts for backend issues (Edge Function failures, Supabase downtime)

**Tech options:** Supabase Dashboard views, custom web dashboard (Next.js + Supabase), or Flutter web admin panel.

---

### Sprint 16: Onboarding Flow Redesign

**Model:** Opus 4.6
**Goal:** Design and build a compelling onboarding flow that converts new users and explains the app's value proposition.

**Scope:**

- Multi-step onboarding screens (value props, feature highlights, social proof)
- Location permission request with clear benefit explanation
- Store preference selection (favorite retailers)
- Optional account creation (allow browsing without signup)
- Animated illustrations / Lottie animations per step
- Skip option with re-access from profile
- A/B test-ready structure for optimizing conversion

---

### Sprint 17: Security Audit ✅

**Model:** Opus 4.6
**Goal:** Full security audit of Flutter app → Supabase backend. Identify and fix vulnerabilities before wider public rollout.

**Completed:**

- **P0 Fix:** `.env` had production service_role key mislabeled as anon key — all RLS bypassed. Fixed to correct anon key.
- **RLS verified:** All 13 production tables have RLS enabled with correct policies. Fixed `Shopping_List_Overview` and `Shopping_List_Item_Level` policies to support email-based sharing fallback. Backfilled `Shared_With` column on existing share records.
- **Edge Functions hardened:** Removed hardcoded Algolia (Clicks) and Klevu (Dis-Chem) credentials → moved to `Deno.env.get()` + Supabase secrets. Fixed CORS wildcard `*` → restricted origin on all 8 functions. Fixed SSRF in image-proxy with strict domain whitelist.
- **Client hardened:** Removed hardcoded POC anon key from `live_api_config.dart` → loads from `.env`. Added ownership checks to `shareList()` and `deleteList()`. Removed debug user enumeration query. Strengthened password policy (8+ chars, letter + number for signup; lenient for login to not lock out existing users). Cleared local cache on sign-out to prevent cross-user data leakage.
- **UX fix:** "View all products" now navigates to Browse with the correct retailer pre-selected.

**Still remaining (pre-public launch):**

- [ ] Rotate Supabase service_role key (Dashboard → Settings → API) — manual, do in Supabase Dashboard
- [ ] Rotate Gemini API key (Google Cloud Console) — manual, do in Google Cloud Console then update `.env`
- [ ] Move Gemini API calls to Edge Function proxy (stop exposing key in APK) — code change: create `supabase/functions/gemini-proxy/index.ts`, update `gemini_service.dart` to call proxy instead of Gemini directly
- [ ] Add rate limiting to Edge Functions — add per-IP rate limiting middleware to all 8+ Edge Functions

---

### Sprint 17b: Recipe Comparison Fix ✅

**Model:** Opus 4.6
**Goal:** Fix recipe ingredient matching inconsistency in Compare Prices and oversized product matching.

**Completed:**

- **Price consistency:** Source retailer's prices are now reused directly in comparison (no re-searching), so recipe total matches comparison total.
- **Size-aware matching for comparison:** `RetailerComparisonNotifier.runComparison()` now passes `ingredient.quantity`/`unit` to `matchIngredient()` — was missing entirely, so `_pickBestSize()` never ran.
- **Cross-retailer size targeting:** Other retailers now target the matched product's size (e.g. if PnP matched 750ml, Shoprite targets ~750ml too) instead of the raw recipe qty (30ml).
- **Size ratio cap:** Added 3x cap with 2500g/ml ceiling in `_pickBestSize()` and pre-filtering in `matchIngredient()`. Prevents 10kg sugar, 5L oil, 12.5kg flour matches.
- **Brand-stripped search:** ~~List comparison now searches with `normalizedName` (strips brand) so cross-retailer search works properly.~~ **Reverted** — this caused terrible matches (e.g. Coca-Cola matching Pepsi). List comparison now uses `searchQuery` (keeps brand+size) and `classify()` (strict product-to-product matching), same as the normal price compare sheet.
- **Perfume/beauty blocking:** Added parfum, perfume, cologne, fragrance, cashmere, etc. to `_disqualifyingWords` and vanilla essence `excludeWords`.
- ~~**IngredientLookup hints in comparison:** Both recipe and list comparison now use the same hint filtering for consistent results.~~ **Reverted** — ingredient hints are for recipe matching, not product-to-product comparison.

**Files changed:** `smart_matching_service.dart`, `recipe_provider.dart`, `list_comparison_provider.dart`, `ingredient_lookup.dart`

---

### Sprint 17c: Product Matching Improvements ✅

**Model:** Opus 4.6
**Status:** COMPLETED — `84d1475`
**Goal:** Fix cross-retailer product matching failures for beverages, packaging word products, and count-based products (eggs).

**Completed:**

- **Brand normalization fix** — `_brandScore()` only stripped hyphens, not spaces, so "coca-cola" ≠ "coca cola" (brand score 0.3 instead of 1.0). Added `_normalizeBrand()` helper that strips both hyphens and spaces. Updated all brand comparison points.
- **Beverage category mismatch fix** — "drink" in `_categoryMismatchWords` caused valid cross-retailer drink matches to be rejected (e.g. "Coca-Cola Plastic 2L" vs "Coca Cola Soft Drink 2L"). Added `_beverageBrands` set (25 SA drink brands) and `_beverageCategoryWords` set. Fixed both `_hasCategoryMismatch()` and `_nameScore()` to skip beverage-word mismatches for known beverage brands. "Strawberries" vs "Strawberry Drink" still correctly rejected.
- **Store brand vs unknown brand scoring** — Previously scored 0.3 for unknown brands vs store brands. Now scores 0.5 when one is a store brand (PnP, Checkers, etc.) and the other is unknown — pushes identical commodity products like "PnP Large Eggs 30 Pack" vs "Eggbert Large Eggs 30 Pack" into "Best Matches" (exact, ≥0.80).
- **Pack count scoring tightened** — Large count differences (30 vs 18 = 67% diff) now score 0.05 instead of 0.1, capped as fallback/Alternatives. Added new tier: very close counts (30 vs 28 = <10% diff) score 0.8.
- **Price difference badges fix** — Used `effectivePrice` (promo-aware) instead of `priceNumeric` (original price) in both `SmartMatchingService` and `ListComparisonNotifier`. Fixes inaccurate +R20/+R40 badges when products are on promotion.
- **24 new tests** (105 → 129): packaging words (8), brand normalization (3), beverage mismatch (7), pack count matching (6)

**Files changed:**

- `lib/data/services/product_name_parser.dart` — `_normalizeBrand()`, `_beverageBrands`, `_beverageCategoryWords`, `_extractBrandFromName()`, `_brandScore()`, `_nameScore()`, `_hasCategoryMismatch()`, `_sizeScore()`
- `lib/data/services/smart_matching_service.dart` — `effectivePrice` for price diff
- `lib/presentation/providers/list_comparison_provider.dart` — `effectivePrice` for price diff
- `test/product_matching_test.dart` — 24 new tests in sections 3–6

---

### Sprint 18: List Price Refresh

**Model:** Sonnet 4.6
**Goal:** Add a refresh button to shopping lists that re-fetches current prices for products added from the browse screen, ensuring reused lists always show up-to-date prices.

**Problem:** When users reuse old shopping lists, the prices stored on list items are stale (from when the product was originally added). There's no way to update them without manually removing and re-adding each item.

**Implementation:**

- **Refresh button** — Add a refresh icon button to the list detail screen app bar (next to the compare button). Tapping it re-fetches live prices for all items that have a retailer assigned.
- **Per-item price update** — For each list item with `itemRetailer` set, search the retailer API using the item name, find the best match using `classify()`, and update `itemPrice`/`itemTotalPrice` in Supabase.
- **Visual feedback** — Show a progress indicator during refresh, then a snackbar with "Prices updated — X of Y items refreshed" or similar.
- **Skip unpriced items** — Items without a retailer (manually added, unmatched) are skipped.
- **Staleness indicator (optional)** — Show a subtle "prices from X days ago" hint on lists that haven't been refreshed recently, using `updated_at` from list items.

**Files:**
- `lib/presentation/screens/lists/list_detail_screen.dart` — Refresh button in app bar
- `lib/presentation/providers/list_provider.dart` — `refreshPrices()` method on list items notifier
- `lib/data/models/list_item.dart` — May need `updatedAt` field if not already present

---

### Sprint 19: Tutorial Update ✅

**Model:** Sonnet 4.6
**Goal:** Update the in-app tutorial/onboarding to cover new features added since the tutorial was last updated.
**Status:** COMPLETED — `eaa5be8`

**What was done:**
- Added compare button tutorial step to Browse screen (step 5)
- Activated list detail tutorial with 4 steps: add items, compare list, share & more, item management
- Added profile tutorial with scroll-to-target for vehicle config card
- Fixed closure capture bug in step counters (Dart closures capture by reference)
- Recipe export tutorial already covered in existing result dialog — verified, no changes needed

**Files updated:**
- `lib/data/services/tutorial_service.dart` — Added listDetail + profile keys/getters/completers
- `lib/presentation/widgets/tutorial/tutorial_targets.dart` — New steps + profile builder
- `lib/presentation/widgets/products/live_product_card.dart` — compareButtonKey param
- `lib/presentation/screens/products/live_browse_screen.dart` — Wired compare button key
- `lib/presentation/screens/lists/list_detail_screen.dart` — Wired list detail tutorial
- `lib/presentation/screens/profile/profile_screen.dart` — Converted to StatefulWidget, wired profile tutorial with scroll-to-target

---

### Sprint 20: Milk Premium — Subscription Infrastructure (Soft Launch) ✅

**Model:** Opus 4.6 (business model, architecture)
**Goal:** Build subscription tracking infrastructure. Show usage in UI but don't enforce limits. Collect usage data to inform future monetization.
**Branch:** `feat/milk-premium-subscription` → merged to `main`
**Status:** COMPLETED — `293ba59`

**Strategy (team decision 2026-03-28):** Soft launch — everything free. Simple usage counter ("X recipes generated this week") with no limit enforcement. Gemini upgraded to paid tier 1 with $3/mo spend cap. SQL migration deployed to production Supabase.

#### Phase 1: Infrastructure — DONE (code written, not deployed)

- [x] Supabase migration SQL (`database/migrations/create_subscription_tables.sql`) — `user_subscriptions` + `recipe_usage` tables with RLS
- [x] Subscription model (`lib/data/models/subscription.dart`)
- [x] Subscription repository (`lib/data/repositories/subscription_repository.dart`) — usage tracking, weekly limit check, trial activation
- [x] Subscription providers (`lib/presentation/providers/subscription_provider.dart`)

#### Phase 2: UI — DONE (code written, not deployed)

- [x] Premium paywall bottom sheet (`lib/presentation/widgets/recipes/premium_paywall_sheet.dart`)
- [x] Premium screen in Profile (`lib/presentation/screens/profile/premium_screen.dart`)
- [x] Recipe provider gate (`lib/presentation/providers/recipe_provider.dart`) — usage check + tracking
- [x] Recipe input card usage counter (`lib/presentation/widgets/recipes/recipe_input_card.dart`)
- [x] Profile screen Premium card (`lib/presentation/screens/profile/profile_screen.dart`)
- [x] `/premium` route (`lib/presentation/routes/app_router.dart`)
- [x] `flutter analyze` — zero warnings

#### Phase 2b: Soft Launch Adjustment — DONE

- [x] `recipe_provider.dart` — commented out hard block (line ~155). Usage still recorded via `_recordUsage()`, but generation is never blocked.
- [x] `recipe_screen.dart` — commented out `weekly_limit_reached` error interceptor that auto-showed paywall sheet (line ~208)
- [x] `recipe_input_card.dart` — commented out "Upgrade to Generate" locked button (line ~331). Always shows regular "Generate Recipe" button.
- [x] Counter simplified to "X recipes generated this week" — no premium/free distinction during soft launch
- [x] Premium screen redesigned as "Early Access" with Lottie animations (gift, confetti, premium)
- [x] Features split into "Free during early access" (AI recipes) and "Always free" (comparison, lists, deals)
- [x] Removed fake purchase buttons and trial flow from soft launch UI
- [x] `flutter analyze` — zero warnings

#### Phase 3: Manual Setup — DONE

- [x] **Upgraded Gemini to paid tier 1** — $3/mo spend cap, $300 free trial credit (90 days)
- [x] **SQL migration run** on production Supabase (`sfnavipqilqgzmtedfuh`)
- [x] **Budget alerts configured** in Google Cloud Console

#### When Ready to Monetize — TODOs to Undo (Future Sprint)

All soft-launch code is marked with `// TODO: Uncomment when ready to enforce recipe limits`. Search the codebase for this string to find all locations. Here's the full list:

1. **`lib/presentation/providers/recipe_provider.dart` (~line 155)**
   - Uncomment the `checkCanGenerate()` call and the `weekly_limit_reached` error block
   - This re-enables the hard gate that blocks generation past 3/week for free users

2. **`lib/presentation/screens/recipes/recipe_screen.dart` (~line 208)**
   - Uncomment the `weekly_limit_reached` error interceptor
   - Re-import `premium_paywall_sheet.dart` (line ~20)
   - This auto-shows the paywall bottom sheet when a free user hits the limit

3. **`lib/presentation/widgets/recipes/recipe_input_card.dart` (~line 331)**
   - Uncomment the `canGenerate` check and "Upgrade to Generate" locked button
   - Re-import `premium_paywall_sheet.dart` (line ~6)
   - This changes the generate button to a gold "Upgrade" button when limit is reached

4. **Payment integration (new work):**
   - [ ] Add `purchases_flutter` package (RevenueCat SDK)
   - [ ] Create `lib/data/services/purchase_service.dart`
   - [ ] RevenueCat dashboard + Google Play Console product setup (R29.99/mo, R249.99/yr)
   - [ ] Wire up purchase buttons in `premium_screen.dart` (currently `// TODO`)
   - [ ] Move Gemini API key server-side (`supabase/functions/gemini-proxy/index.ts`) — required before enforcing payment to prevent APK key extraction and paywall bypass

**Pricing (future):** R29.99/mo or R249.99/yr (30% discount). Free tier: 3 recipes/week.

---

## Future (Add to CLAUDE.md)

- **FatSecret API** for nutritional information (fat, protein, carbs)
- Diet plan curation and calorie tracking
- Store price history trends
- **Barcode scanner** — scan products in-store, compare prices (needs barcode data in DB first)
- **SPAR integration** — Extensively researched (2026-03-28). SPAR2U APK fully reverse-engineered. POC Edge Function (`products-spar`) deployed to Supabase using KwikSPAR API for live product search with ZAR prices. **Not integrated into app yet** — missing product images (KwikSPAR has none, `products.spar.net` needs signed URLs) and no promo data. Commerce API (`api.spar.co.za`) cracked for product master data (names, GTINs, brands, nutrition, allergens) but prices are behind store-session endpoints still locked. Contentful CMS publicly accessible (118 product lists, GTINs). Full research in `memory/project_spar_research.md`. To proceed: need to solve images (either crack signed URLs from Commerce API, or build a GTIN→image lookup), then wire into app.
- **More retailers** — Game, Food Lover's Market if demand warrants
- **Lottie animation for AI error messages** — animated error state when Gemini recipe generation fails or AI matching encounters errors (currently shows plain text/icon)
- **Mailing list** — Backend `mailing_list` column exists on `user_profiles` but no subscription flow or email service configured. Hidden from Profile UI until ready. Need to set up email service (Resend/SendGrid), opt-in toggle, and preference management.

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
4. Test all active retailers where applicable
5. Commit with conventional commit message
6. Push to GitHub
