// lib/core/constants/product_categories.dart
//
// Cross-retailer category mapping for the browse screen chip bar.
//
// Each edge function accepts a `category` query param keyed by its own
// display name map. PnP / Checkers / Shoprite all share the same keys
// (e.g. "Fruit & Veg", "Bakery"). Woolworths uses different keys
// (e.g. "Fruit-Vegetables-Salads", "Bakery").
//
// The `valueForRetailer(slug)` method returns the correct key to pass
// to the edge function for each retailer.

import 'package:flutter/material.dart';

/// A single browseable product category with display info
/// and per-retailer edge-function keys.
class ProductCategory {
  final String displayName;
  final IconData icon;

  /// Retailer-specific edge function keys, keyed by retailer slug.
  /// The value is passed verbatim as the `category` query param.
  final Map<String, String> retailerKeys;

  const ProductCategory({
    required this.displayName,
    required this.icon,
    required this.retailerKeys,
  });

  /// Returns the edge function category key for [retailerSlug],
  /// or null if this category is not supported for that retailer.
  String? valueForRetailer(String retailerSlug) => retailerKeys[retailerSlug];
}

/// All supported browse categories.
///
/// Keys match what each edge function's CATEGORIES map expects:
///   - PnP:       PNP_CATEGORIES keys  (e.g. "Fruit & Veg")
///   - Checkers:  CHECKERS_CATEGORIES keys (e.g. "Fruit & Veg")
///   - Shoprite:  SHOPRITE_CATEGORIES keys (e.g. "Fruit & Veg")
///   - Woolworths: CATEGORIES keys     (e.g. "Fruit-Vegetables-Salads")
class ProductCategories {
  static const List<ProductCategory> all = [
    ProductCategory(
      displayName: 'Fruit & Veg',
      icon: Icons.eco_rounded,
      retailerKeys: {
        'pnp': 'Fruit & Veg',
        'woolworths': 'Fruit-Vegetables-Salads',
        'checkers': 'Fruit & Veg',
        'shoprite': 'Fruit & Veg',
      },
    ),
    ProductCategory(
      displayName: 'Dairy & Eggs',
      icon: Icons.egg_rounded,
      retailerKeys: {
        'pnp': 'Dairy & Eggs',
        'woolworths': 'Milk-Dairy-Eggs',
        'checkers': 'Dairy & Eggs',
        'shoprite': 'Dairy & Eggs',
      },
    ),
    ProductCategory(
      displayName: 'Meat & Poultry',
      icon: Icons.set_meal_rounded,
      retailerKeys: {
        'pnp': 'Meat & Poultry',
        'woolworths': 'Meat-Poultry-Fish',
        'checkers': 'Meat & Poultry',
        'shoprite': 'Meat & Poultry',
      },
    ),
    ProductCategory(
      displayName: 'Bakery',
      icon: Icons.bakery_dining_rounded,
      retailerKeys: {
        'pnp': 'Bakery',
        'woolworths': 'Bakery',
        'checkers': 'Bakery',
        'shoprite': 'Bakery',
      },
    ),
    ProductCategory(
      displayName: 'Frozen',
      icon: Icons.ac_unit_rounded,
      retailerKeys: {
        'pnp': 'Frozen',
        'woolworths': 'Frozen-Food',
        'checkers': 'Frozen',
        'shoprite': 'Frozen',
      },
    ),
    ProductCategory(
      displayName: 'Food Cupboard',
      icon: Icons.kitchen_rounded,
      retailerKeys: {
        'pnp': 'Food Cupboard',
        'woolworths': 'Pantry',
        'checkers': 'Food Cupboard',
        'shoprite': 'Food Cupboard',
      },
    ),
    ProductCategory(
      displayName: 'Snacks',
      icon: Icons.cookie_rounded,
      retailerKeys: {
        'pnp': 'Snacks',
        'woolworths': 'Chocolates-Sweets-Snacks',
        'checkers': 'Snacks',
        'shoprite': 'Snacks',
      },
    ),
    ProductCategory(
      displayName: 'Beverages',
      icon: Icons.local_drink_rounded,
      retailerKeys: {
        'pnp': 'Beverages',
        'woolworths': 'Beverages-Juices',
        'checkers': 'Beverages',
        'shoprite': 'Beverages',
      },
    ),
  ];

  // Private constructor
  ProductCategories._();
}
