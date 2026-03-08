// lib/data/services/live_product_image_resolver.dart
//
// Patches LiveProduct image URLs for Checkers and Shoprite
// using the bundled image lookup cache.
//
// Usage: call resolveImages() on a LiveProductsResponse before
// displaying it in the UI.

import '../models/live_product.dart';
import 'image_lookup_service.dart';

/// Resolves images for a list of LiveProducts.
///
/// For Checkers and Shoprite, replaces the (broken) API image URL
/// with the Supabase Storage URL from the lookup cache.
/// PnP and Woolworths products are returned unchanged.
List<LiveProduct> resolveProductImages(
  List<LiveProduct> products,
  String retailer,
) {
  final lookup = ImageLookupService.instance;
  if (!lookup.isReady) return products;

  // Only Checkers and Shoprite need image resolution
  final lowerRetailer = retailer.toLowerCase();
  if (!lowerRetailer.contains('checkers') &&
      !lowerRetailer.contains('shoprite')) {
    return products;
  }

  return products.map((product) {
    final cachedUrl = lookup.lookupImage(
      retailer: retailer,
      productName: product.name,
    );

    if (cachedUrl != null) {
      return product.copyWith(imageUrl: cachedUrl);
    }

    return product;
  }).toList();
}
