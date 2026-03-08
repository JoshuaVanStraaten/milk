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

- Browse grid: `LiveProductCard` with `QuickAddButton` — 2-column, `childAspectRatio: 0.62`
- Home deals: `_HotDealCard` — 160px wide, retailer pill, savings badge, quick-add button
- Always white background for product images regardless of dark mode:

```dart
Container(color: Colors.white, child: CachedNetworkImage(...))
```

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
