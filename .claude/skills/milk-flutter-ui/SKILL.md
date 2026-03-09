---
name: milk-flutter-ui
description: Use when building or modifying any UI in the Milk app. Covers theme system, dark mode, retailer branding, product cards, image handling, and bottom sheets. Read FIRST before touching any screen or widget.
---

# Milk Flutter UI Patterns

## Theme System

All colors via `AppColors` in `core/theme/app_colors.dart`. Use the `ThemeColors` extension:

```dart
final isDark = Theme.of(context).brightness == Brightness.dark;
// Or use extension:
color: context.textPrimary,
color: context.surfaceColor,
```

Never hardcode `Colors.white` for text or backgrounds — always use theme-aware values.

## Retailer Branding

```dart
final config = Retailers.fromName(retailerName);
// config.color, config.colorLight, config.icon, config.edgeFunctionName
```

Defined in `core/constants/retailers.dart`. Never hardcode "Pick n Pay" or `Color(0xFFE31837)`.

## Product Cards

### Browse Grid (`LiveProductCard`)
- 2-column grid, `childAspectRatio: 0.72`, spacing 10px
- Image floats inside a **padded rounded white container** (never edge-to-edge):
  ```dart
  Padding(padding: EdgeInsets.fromLTRB(12, 10, 12, 4),
    child: AspectRatio(aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: EdgeInsets.all(8), child: CachedNetworkImage(...)),
      ),
    ),
  )
  ```
- Info padding: `EdgeInsets.fromLTRB(10, 4, 10, 8)`
- Two action buttons on the right of the price row (compare + quick-add, 26px each, 4px gap):
  - Compare: gray bg (`AppColors.surface` / `AppColors.surfaceDarkModeLight`), `Icons.compare_arrows`
  - Quick-add: emerald green (`AppColors.primary`), `Icons.add_rounded`
  - Both use `GestureDetector(behavior: HitTestBehavior.opaque)` for adequate tap targets
- Promo items: "SALE" badge (`Positioned(top:6, left:6)`, red bg) + 1px red border at alpha 0.3
- `showCompareButton: false` / `onCompare: null` hides the compare button (e.g. in search results)

### Home Deals (`_HotDealCard`, `home_screen.dart`)
- 160px wide, horizontal scroll carousel
- Image section: padded (`fromLTRB(10, 8, 10, 4)`), 100px height, 8px radius white container, 6px inner padding
- Badges inside the padded Stack: savings % (top-right, 4px), retailer pill (top-left, 4px)
- Price row: prices + compare button (28px) + quick-add (28px), 4px gap
- Compare button wired via `showCompareSheet(context, ref, deal.toLiveProduct())`
- Both cards share the same visual language: padded floating image, gray compare + green add

### Always white background for product images regardless of dark mode
The white image container is always `Colors.white` — product photos look correct on white.

## Checkers/Shoprite Images

These retailers return broken/missing image URLs. Always resolve through:

```dart
final lookup = ImageLookupService.instance;
if (lookup.isReady) {
  final cached = lookup.lookupImage(retailer: retailer, productName: p.name);
  if (cached != null) product = product.copyWith(imageUrl: cached);
}
```

## Add to List

Standard flow for ANY product → list action:

```dart
showAddToListSheet(context, ref,
  productName: product.name,
  price: product.priceNumeric,
  retailer: product.retailer,
  specialPrice: specialPrice,
  imageUrl: product.imageUrl,
  priceDisplay: product.price,
  multiBuyInfo: product.multiBuyInfo,
);
```

## Bottom Sheets

```dart
showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => Container(
    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
    decoration: BoxDecoration(
      color: isDark ? AppColors.surfaceDarkMode : Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    child: ...
  ),
);
```

## Common Overflow Fixes

- Wrap horizontal scroll content in `SingleChildScrollView` with `ClampingScrollPhysics`
- Use `Flexible` or `Expanded` for text that might overflow
- Always set `maxLines` + `overflow: TextOverflow.ellipsis` on product names
- Set explicit `height` on horizontal `ListView` containers
