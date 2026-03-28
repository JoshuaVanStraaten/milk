// lib/core/constants/retailers.dart

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Configuration for each South African retailer.
///
/// Centralises display names, brand colors, icons, and the Edge Function
/// name used by [LiveApiService]. Both the browse UI (retailer chips,
/// store cards) and the API layer reference this config.
class RetailerConfig {
  /// Display name shown in the UI (e.g. "Pick n Pay")
  final String name;

  /// Brand color used for chips, cards, and highlights
  final Color color;

  /// A lighter tint of [color] for backgrounds and unselected states.
  /// Typically `color.withOpacity(0.1)` or a hand-picked pastel.
  final Color colorLight;

  /// Icon displayed in store cards and retailer chips
  final IconData icon;

  /// Name of the Supabase Edge Function that proxies this retailer's API.
  /// Passed to [LiveApiConfig.edgeFunctionUrl] to build the request URL.
  final String edgeFunctionName;

  /// Short slug used as the key in the `stores-nearby` response
  /// (e.g. "pnp", "woolworths", "checkers", "shoprite").
  final String slug;

  const RetailerConfig({
    required this.name,
    required this.color,
    required this.colorLight,
    required this.icon,
    required this.edgeFunctionName,
    required this.slug,
  });
}

/// Central registry of all supported retailers.
///
/// Usage:
/// ```dart
/// // Iterate all retailers
/// for (final config in Retailers.all.values) { ... }
///
/// // Look up by display name
/// final pnp = Retailers.all['Pick n Pay'];
///
/// // Look up by API slug
/// final config = Retailers.fromSlug('pnp');
/// ```
class Retailers {
  /// All retailers keyed by their display name.
  static const Map<String, RetailerConfig> all = {
    'Pick n Pay': RetailerConfig(
      name: 'Pick n Pay',
      color: AppColors.pickNPay,
      colorLight: Color(0xFFFDE8EB), // Light red tint
      icon: Icons.shopping_cart,
      edgeFunctionName: 'products-pnp',
      slug: 'pnp',
    ),
    'Woolworths': RetailerConfig(
      name: 'Woolworths',
      color: AppColors.woolworths,
      colorLight: Color(0xFFE6F2EC), // Light green tint
      icon: Icons.eco,
      edgeFunctionName: 'products-woolworths',
      slug: 'woolworths',
    ),
    'Checkers': RetailerConfig(
      name: 'Checkers',
      color: AppColors.checkers,
      colorLight: Color(0xFFE6F0FA), // Light blue tint
      icon: Icons.local_grocery_store,
      edgeFunctionName: 'products-checkers',
      slug: 'checkers',
    ),
    'Shoprite': RetailerConfig(
      name: 'Shoprite',
      color: AppColors.shoprite,
      colorLight: Color(0xFFFFF0E6), // Light orange tint
      icon: Icons.storefront,
      edgeFunctionName: 'products-shoprite',
      slug: 'shoprite',
    ),
    'Makro': RetailerConfig(
      name: 'Makro',
      color: AppColors.makro,
      colorLight: Color(0xFFE6EDF8), // Light blue tint
      icon: Icons.warehouse,
      edgeFunctionName: 'products-makro',
      slug: 'makro',
    ),
    'Dis-Chem': RetailerConfig(
      name: 'Dis-Chem',
      color: AppColors.disChem,
      colorLight: Color(0xFFE6F7ED), // Light green tint
      icon: Icons.local_pharmacy,
      edgeFunctionName: 'products-dischem',
      slug: 'dischem',
    ),
    'Clicks': RetailerConfig(
      name: 'Clicks',
      color: AppColors.clicks,
      colorLight: Color(0xFFE6EFF8), // Light blue tint
      icon: Icons.medication,
      edgeFunctionName: 'products-clicks',
      slug: 'clicks',
    ),
    'SPAR': RetailerConfig(
      name: 'SPAR',
      color: AppColors.spar,
      colorLight: Color(0xFFFDE8EB), // Light red tint
      icon: Icons.store,
      edgeFunctionName: 'products-spar',
      slug: 'spar',
    ),
  };

  /// Look up a [RetailerConfig] by its API slug (e.g. "pnp", "checkers").
  ///
  /// Returns `null` if the slug is not recognised.
  static RetailerConfig? fromSlug(String slug) {
    for (final config in all.values) {
      if (config.slug == slug) return config;
    }
    return null;
  }

  /// Look up a [RetailerConfig] by its display name (e.g. "Pick n Pay").
  ///
  /// Returns `null` if the name is not recognised.
  static RetailerConfig? fromName(String name) => all[name];

  /// Ordered list of retailer display names.
  static List<String> get names => all.keys.toList();

  /// Grocery-focused retailers used for recipe auto-matching.
  /// Makro, Dis-Chem, and Clicks are excluded because they are not
  /// full grocery stores — their limited product ranges produce poor
  /// recipe ingredient matches.
  static const Set<String> groceryRetailers = {
    'Pick n Pay',
    'Woolworths',
    'Checkers',
    'Shoprite',
    'SPAR',
  };

  /// Whether [retailerName] is a grocery retailer (used for recipe matching).
  static bool isGrocery(String retailerName) =>
      groceryRetailers.contains(retailerName);

  /// Pharmacy retailers — compare against each other, not grocery stores.
  static const Set<String> pharmacyRetailers = {
    'Dis-Chem',
    'Clicks',
  };

  /// Whether [retailerName] is a pharmacy retailer.
  static bool isPharmacy(String retailerName) =>
      pharmacyRetailers.contains(retailerName);

  /// Returns the set of retailer names to compare against for a given source.
  /// - Grocery products compare against other grocery retailers.
  /// - Pharmacy products (Dis-Chem/Clicks) compare against each other.
  /// - Makro compares against grocery retailers (bulk vs standard).
  static Set<String> comparisonPeers(String sourceRetailer) {
    if (pharmacyRetailers.contains(sourceRetailer)) {
      return pharmacyRetailers;
    }
    return groceryRetailers;
  }

  // Private constructor to prevent instantiation
  Retailers._();
}
