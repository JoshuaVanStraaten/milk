---
name: milk-bug-patterns
description: Use when debugging issues in the Milk app. Documents recurring bug patterns, their root causes, and proven fixes. Read this BEFORE attempting to fix any bug.
---

# Milk Bug Patterns & Fixes

## 1. Checkers/Shoprite Images Not Showing

**Symptom:** Placeholder icon instead of product image for Checkers/Shoprite products.
**Root cause:** API returns broken image URLs. `ImageLookupService` must resolve from bundled cache.
**Fix:** Ensure `ImageLookupService.instance.initialize()` is called in `main.dart` AND images are resolved after fetching:

```dart
if (lookup.isReady && (retailer contains 'checkers' or 'shoprite')) {
  product = product.copyWith(imageUrl: lookup.lookupImage(retailer, productName));
}
```

**Also check:** `LiveProduct.copyWith()` method exists — it was missing once and silently failed.

## 2. HTML Entities in Product Names

**Symptom:** Names like `Pot O&#039;s` or `Fatti&#039;s &amp; Moni&#039;s`.
**Root cause:** Checkers/Shoprite API returns HTML-encoded text.
**Fix:** `_decodeHtmlEntities()` in `LiveProduct.fromJson()`. If entities appear, check the method is being called on both `name` and `promotionPrice`.

## 3. Double Navigator.pop Crash

**Symptom:** Black screen with "popped the last page off the stack" error.
**Root cause:** Both a callback AND the widget calling `Navigator.pop()`. Two pops = crash.
**Fix:** Only pop in ONE place. Usually the callback (parent) should handle the pop, not the child widget.

## 4. Auth Race Condition

**Symptom:** Profile shows email prefix instead of display name after signup.
**Root cause:** `currentUserProfileProvider` resolved before Supabase profile row was created.
**Fix:** Use `ref.invalidate(currentUserProfileProvider)` after signup completes. Never fall back to email prefix.

## 5. Overflow on Small Screens

**Symptom:** Bottom buttons cut off, text overflows cards, layout breaks on small phones.
**Fix patterns:**

- Wrap bottom sheets in `SingleChildScrollView` with `ClampingScrollPhysics`
- Set `maxHeight` constraint on bottom sheet containers (65% of screen)
- Use `Flexible`/`Expanded` for text, never raw `Text` in tight layouts
- Set explicit `height` on horizontal `ListView` containers
- Test on 360px wide viewport

## 6. Recipe Matching Returns Wrong Products

**Symptom:** "Mosquito killer" matched for "carrots", soy mince for beef mince.
**Root cause:** Raw ingredient name sent as search query (includes quantities, prep instructions).
**Fix:** `_cleanIngredientForSearch()` strips quantities/units/prep words. `_findBestMatch()` scores candidates with word overlap + containment, rejects below 0.2 threshold. Fetch 10+ candidates, not 5.

## 7. Woolworths Shows Limited Promos

**Symptom:** Only 1-2 deals show for Woolworths on home screen.
**Root cause:** Woolworths browse API returns mostly non-promo items per page.
**Fix:** Fetch 2+ pages. Currently `loadDeals()` fetches page 0 and page 1.

## 8. Provider Not Updating After State Change

**Symptom:** UI shows stale data after an action (add to list, signup, etc.).
**Fix:** `ref.invalidate(providerName)` after async state mutations. Don't assume auto-refresh.

## Debugging Checklist

Before fixing any bug:

1. Run `flutter analyze` — fix all warnings first
2. Check if the issue is dark mode specific (test both themes)
3. Check if the issue is retailer-specific (test all 4 stores)
4. Check the debug console for print statements — many services have `debugPrint` logging
5. Test on physical device, not just emulator
