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
- **Status:** Deferred to Sprint 11 polish pass

**4e. Compact browse header** ✅

- Merged retailer chip bar + store info bar into a single AppBar button (`_StoreAppBarButton`)
- Button shows retailer icon (colored circle) + retailer name + store branch + chevron-down
- Tap opens existing `StorePickerSheet` (handles both retailer + store switching)
- Search moved to hero position (first element in body)
- AppBar gets subtle retailer brand color tint
- Header height reduced ~36% (~170px → ~108px)
- **File:** `lib/presentation/screens/products/live_browse_screen.dart`

---

### Sprint 5: List Management Enhancements

**Model:** Sonnet 4.6 (UI) → Opus 4.6 (browse+compare UX flow design)
**Goal:** Multi-select delete, browse+manual add toggle from inside lists.

**5a. Multi-select list deletion**

- **File:** `lib/presentation/screens/lists/my_lists_screen.dart`
- **Approach:** Long-press enters selection mode, checkboxes appear, bulk delete action in app bar

**5b. Add items from inside list — browse toggle**

- **File:** `lib/presentation/screens/lists/list_detail_screen.dart`
- **Approach:** In the add-item FAB flow, add a toggle/tab: "Manual" vs "Browse"
  - Manual: Current `_AddItemSheet` behavior
  - Browse: Inline product search with retailer selector, results grid, tap-to-add
  - After adding, prompt: "Want to compare prices?" → opens compare sheet

---

### Sprint 6: Location & Address Support

**Model:** Sonnet 4.6
**Goal:** Let users enter addresses and save locations.

**6a. Address input with geocoding**

- **Files:** `lib/data/services/location_service.dart`, `lib/presentation/providers/store_provider.dart`
- **Approach:**
  - Add geocoding package (e.g., `geocoding` or Google Places API)
  - Address text field in store selection screen
  - Geocode address → lat/lng → fetch nearby stores
- **UI:** Add "Use address" option alongside "Use my location"

**6b. Saved locations (Home/Work)**

- **Storage:** `flutter_secure_storage` or SharedPreferences
- **Files:** New saved locations provider, profile screen addition
- **UI:** Profile screen → "My Locations" section with named locations

---

### Sprint 7: Walkthrough Tutorial

**Model:** Sonnet 4.6
**Goal:** Guide new users through the app on first launch.

- **Package:** `tutorial_coach_mark` or `showcaseview`
- **Files:** Main screens (home, browse, lists, recipes)
- **Approach:** Highlight key UI elements with tooltips on first launch
- **Storage:** `SharedPreferences` flag `'tutorial_completed'`

---

### Sprint 8: Share Feature Polish

**Model:** Sonnet 4.6
**Goal:** Better UX when sharing/collaborating on lists.

- **File:** `lib/presentation/screens/lists/list_detail_screen.dart`
- **Approach:** Show confirmation dialog/snackbar when list is shared
- **UI:** Use `ui-ux-pro-max` skill for share dialog design

---

### Sprint 9: Expand Store Database

**Goal:** Improve store location coverage. Look at the `database/edge_functions/stores-nearby` and also the `plans/checkers_near_stores.sh` such that we can expand our store db as we currently have much less checkers stores than others.

- **Approach:** Research additional store data sources, update Supabase `retailer_stores` table
- **Edge Function:** May need to increase search radius or add mall-specific entries
- **Not code-heavy:** Mostly data collection and DB updates

---

### Sprint 10: Recipe Export — Ingredient Selection & Retailer Comparison

**Model:** Opus 4.6 (UX flow design, comparison logic, state management) → Sonnet 4.6 (UI implementation)
**Goal:** Give users full control when exporting a recipe to a shopping list — deselect items they already have, compare total cost across retailers, and swap individual products before committing.

**10a. Ingredient deselection before export**

- **Flow:** After matching, before export, show ingredient list with checkboxes (all selected by default)
- **UX:** Clear messaging — "Deselect items you already have" or similar prompt
- **Approach:** Add selection state to export flow, only export checked ingredients
- **Files:** `lib/presentation/widgets/recipes/recipe_result_card.dart` (export dialog), `lib/presentation/providers/recipe_provider.dart` (export method)
- **Model:** Sonnet 4.6 (straightforward checkbox UI + state)

**10b. Retailer cost comparison before export**

- **Flow:** After ingredient selection users should be able to select if they want to compare or just continue with export, show a comparison view — each retailer as a dropdown/accordion with all matched products and prices, total per retailer, cheapest retailer highlighted
- **UX:** Use `ui-ux-pro-max` skill for optimal layout — likely a bottom sheet or full-screen modal with retailer tabs/cards
- **Approach:** Re-run ingredient matching against all retailers (or use cached results), calculate totals, rank by price
- **Data:** Needs `SmartMatchingService` to match ingredients across all 4 retailers simultaneously
- **Files:** New widget (e.g., `lib/presentation/widgets/recipes/retailer_comparison_sheet.dart`), `lib/presentation/providers/recipe_provider.dart`
- **Model:** Opus 4.6 (comparison UX design, data flow architecture)

**10c. Swap products per retailer in comparison view**

- **Flow:** In the retailer comparison view, each matched product is tappable — user can search for alternatives or pick from other matches
- **UX:** Tap a product → show search/alternatives sheet → select replacement → total updates live
- **Approach:** Reuse existing `onMatchIngredient` flow and `IngredientMatchingNotifier` for product search
- **Files:** Retailer comparison widget, recipe provider
- **Model:** Sonnet 4.6 (reuses existing search/match UI patterns)

---

### Sprint 11: Final UI/UX Polish Pass

**Model:** Opus 4.6 (design review & strategy) → Sonnet 4.6 (implementation)
**Goal:** Professional, exciting look across the entire app.

- Use `ui-ux-pro-max` skill for comprehensive review
- Dark mode audit (all screens)
- Animation polish
- Typography consistency
- Loading state improvements
- Empty state designs
- Error state designs

---

## Future (Add to CLAUDE.md)

- **FatSecret API** for nutritional information (fat, protein, carbs)
- Diet plan curation and calorie tracking
- Store price history trends
- **Barcode scanner** — scan products in-store, compare prices (needs barcode data in DB first)

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
