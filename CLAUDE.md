# Milk — SA Grocery Price Comparison App

## What This Is

Flutter app for South African grocery shoppers. Compares live prices across Pick n Pay, Woolworths, Checkers, and Shoprite. GPS-based store selection, live product browsing, AI recipe generation, shopping lists with real-time collaboration, deals feed.

**Package:** `com.ubicorp.milkza` | **Version:** `1.1.0+2` | **Play Store:** Closed beta (live)

## Current Phase: Bug Fixes & Polish

Focus is stabilising the app for public launch. No new features — fix what's broken, polish what's rough.

## Tech Stack

- **Flutter** (Dart 3.9+), **Riverpod** for state, **GoRouter** for navigation, Material 3 (emerald green)
- **Supabase** (PostgreSQL, Auth, Realtime, Edge Functions)
- **Google Gemini API** for recipe generation
- **POC Supabase:** `https://pjqbvrluyvqvpegxumsd.supabase.co` (Edge Functions)

## Commands

```powershell
flutter run                          # Run on connected Android device
flutter build appbundle --release    # Build AAB for Play Store
flutter analyze                      # Lint — run before every commit
flutter test                         # Run tests
adb devices                          # Check connected device
```

## Project Structure

```
lib/
├── core/constants/    # app_constants.dart, retailers.dart, routes.dart
├── core/theme/        # app_colors.dart, app_theme.dart
├── data/models/       # live_product.dart, recipe.dart, shopping_list.dart, nearby_store.dart
├── data/repositories/ # auth_repository.dart, recipe_repository.dart, list_repository.dart
├── data/services/     # live_api_service.dart, gemini_service.dart, fallback_product_service.dart,
│                      # product_name_parser.dart, image_lookup_service.dart, location_service.dart
├── presentation/providers/  # auth_provider.dart, store_provider.dart, recipe_provider.dart
├── presentation/screens/    # home/, products/, lists/, auth/, profile/
└── presentation/widgets/    # products/, lists/, common/
```

## Key Architecture

- **Riverpod** for all state — `ref.watch()` in widgets, `ref.read()` in callbacks
- **FallbackProductService** wraps LiveApiService — auto-failover to Supabase Products table if API fails
- **ProductNameParser** extracts brand (150+ SA brands), size, normalized name — used in price compare and recipe matching
- **ImageLookupService** resolves Checkers/Shoprite images from `assets/image_lookup_cache.json`
- **HTML entities** decoded in `LiveProduct.fromJson()` for Checkers/Shoprite
- **showAddToListSheet()** is the standard add-to-list flow — used everywhere

## Skills

**Read before making UI changes:**

- `.claude/skills/milk-flutter-ui/SKILL.md` — Theme, dark mode, retailer branding, product cards, image patterns

**Read before touching Edge Functions or Supabase:**

- `.claude/skills/supabase-edge-functions/SKILL.md` — Retailer API patterns, CORS, CSRF, deployment

**Read when debugging:**

- `.claude/skills/milk-bug-patterns/SKILL.md` — Common bugs in this codebase and how to fix them

## Agents

- `/project:fix-bugs` — Runs `flutter analyze`, identifies issues, fixes them
- `/project:smoke-test` — Generates a checklist of manual test flows for the current changes

## Conventions

- Conventional commits: `feat:`, `fix:`, `refactor:`, `chore:`
- Always run `flutter analyze` before committing — zero warnings
- Dark mode: always use `AppColors` theme-aware colors, never hardcode
- Retailers: use `Retailers.fromName()`, never hardcode store names/colors
- Prices in ZAR: `R29.99`
- Test on physical Android device, not just emulator

## Don't

- Don't use BLoC — Riverpod only
- Don't fetch all products at once — paginate
- Don't hardcode province names — GPS-based now
- Don't use SharedPreferences for secrets — use flutter_secure_storage
- Don't import deleted files: `province_provider.dart`, `onboarding_screen.dart`, `store_selector_screen.dart`, `price_comparison_sheet.dart`, `price_comparison_provider.dart`
- Don't use `.withOpacity()` — use `.withValues(alpha: x)` instead (Flutter deprecation)

## Future Backlog

- **FatSecret API** — Nutritional info (fat, protein, carbs), diet plans, calorie tracking
- **Barcode scanner** — Scan products in-store, compare prices across retailers (needs barcode/EAN data in DB first)
- **Store price history** — Track price trends over time
