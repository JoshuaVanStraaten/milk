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

**3a. Enhance ProductNameParser**
- **File:** `lib/data/services/product_name_parser.dart`
- **Improvements:**
  - Better size normalization (handle "6x100g", "6 pack", "dozen", etc.)
  - Improve brand extraction for multi-word brands
  - Add variant detection (e.g., "low fat", "full cream", "lite")
  - Add confidence score output to matching

**3b. Improved algorithm with confidence scoring**
- Enhance `classify()` and `_findBestMatch()` to return a confidence score (0.0-1.0)
- Weight: brand match (0.3) + size match (0.25) + variant match (0.2) + name similarity (0.25)
- **Threshold:** If confidence < 0.6, escalate to Gemini

**3c. AI-assisted matching (hybrid fallback)**
- When algorithm confidence is below threshold:
  1. Fetch candidates from all retailers (existing `compareProduct()`)
  2. Send candidates + source product to Gemini with structured prompt
  3. Gemini returns ranked matches with confidence scores
  4. Use AI ranking to select best match per retailer
- **Files:** New `smart_matching_service.dart`, reuse `GeminiService`
- **Fallback:** If Gemini also fails, use best algorithm match regardless of confidence
- **Validation:** Log match results to measure algorithm vs AI accuracy over time

**3d. Improve ingredient matching for recipes**
- **File:** `lib/presentation/providers/recipe_provider.dart` — `_findBestMatch()`, `_cleanIngredientForSearch()`
- **Approach:** Use same hybrid matching from 3b/3c

---

### Sprint 4: Sort, Filter & Category Browsing
**Model:** Sonnet 4.6 (UI implementation) — Opus 4.6 if Edge Function changes needed
**Goal:** Let users browse by category and filter/sort results.

**4a. Category-based browsing**
- **Investigation needed:** Check if Edge Functions return category data. The `browseProducts()` method already accepts a `category` param.
- **If categories available:** Add category chip bar below retailer selector in `live_browse_screen.dart`
- **If not:** May need to update Edge Functions to include category in response, or add `category` field to `LiveProduct` model

**4b. Sort and filter controls**
- **File:** `lib/presentation/screens/products/live_browse_screen.dart`
- **Features:**
  - Filter: "Promos only" toggle
  - Sort: Price low→high, high→low, alphabetical
  - Category filter (if available from API)
- **UI:** Filter/sort icon in app bar → bottom sheet with options

**4c. Show healthy items first**
- **Approach:** When displaying search results, prioritize food items over confectionery/snacks
- **Implementation:** Client-side sorting heuristic based on product name keywords, or category if available

**4d. Deals per category on home screen**
- **File:** `lib/presentation/screens/home/home_screen.dart`
- **Approach:** Group deals by category with section headers (Dairy, Bakery, etc.)
- **Depends on:** Whether API returns category data

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
**Goal:** Improve store location coverage.

- **Approach:** Research additional store data sources, update Supabase `retailer_stores` table
- **Edge Function:** May need to increase search radius or add mall-specific entries
- **Not code-heavy:** Mostly data collection and DB updates

---

### Sprint 10: Final UI/UX Polish Pass
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
