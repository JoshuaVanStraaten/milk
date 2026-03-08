// lib/data/services/image_lookup_service.dart
//
// Resolves product images for Checkers and Shoprite by matching
// normalized product names against a bundled JSON lookup cache.
//
// The cache maps normalized_name → Supabase Storage URL for products
// whose API images don't display properly.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:logger/logger.dart';

class ImageLookupService {
  static ImageLookupService? _instance;
  static final Logger _logger = Logger();

  /// Keyed by retailer slug ("checkers", "shoprite"), then normalized name → URL.
  Map<String, Map<String, String>>? _cache;
  bool _isLoading = false;

  ImageLookupService._();

  /// Singleton accessor.
  static ImageLookupService get instance {
    _instance ??= ImageLookupService._();
    return _instance!;
  }

  /// Whether the cache has been loaded.
  bool get isReady => _cache != null;

  /// Load the JSON cache from bundled assets.
  /// Safe to call multiple times — subsequent calls are no-ops.
  Future<void> initialize() async {
    if (_cache != null || _isLoading) return;
    _isLoading = true;

    try {
      _logger.d('Loading image lookup cache...');
      final jsonString = await rootBundle.loadString(
        'assets/image_lookup_cache.json',
      );
      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;

      _cache = {};
      for (final entry in decoded.entries) {
        final retailer = entry.key;
        final products = entry.value as Map<String, dynamic>;
        _cache![retailer] = products.map((k, v) => MapEntry(k, v.toString()));
      }

      final total = _cache!.values.fold<int>(0, (sum, map) => sum + map.length);
      _logger.i('Image lookup cache loaded: $total products');
    } catch (e) {
      _logger.e('Failed to load image lookup cache: $e');
      _cache = {};
    } finally {
      _isLoading = false;
    }
  }

  /// Normalize a product name to match the cache keys.
  ///
  /// Mirrors the exact Python scraper logic that generated the keys:
  /// 1. Replace spaces with underscores
  /// 2. Strip non-ASCII characters (NFKD normalization)
  /// 3. Replace non-alphanumeric (except `_`, `.`, `-`) with underscore
  /// 4. Lowercase
  ///
  /// This naturally produces:
  /// - ` & ` → `___` (space→_, &→_, space→_)
  /// - `50%` → `50_` + next space was already `_` → `50__`
  /// - `(Small)` → `_small_`
  static String normalizeName(String name) {
    if (name.isEmpty) return '';

    // Step 1: spaces → underscores (BEFORE special char handling)
    var normalized = name.replaceAll(' ', '_');

    // Step 2: strip diacritics / non-ASCII
    // Dart doesn't have unicodedata.normalize, but we can strip
    // common accented chars. For SA grocery products this is sufficient.
    normalized = _stripDiacritics(normalized);

    // Step 3: non-alphanumeric (except _, ., -) → underscore
    normalized = normalized.replaceAll(RegExp(r'[^\w.\-]'), '_');

    // Step 4: lowercase
    normalized = normalized.toLowerCase();

    return normalized;
  }

  /// Strip diacritics from a string (approximate NFKD + ASCII encode).
  /// Handles common accented characters found in SA product names.
  static String _stripDiacritics(String text) {
    const diacritics =
        'àáâãäåæçèéêëìíîïðñòóôõöùúûüýÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖÙÚÛÜÝ';
    const replacements =
        'aaaaaaaceeeeiiiidnooooouuuuyAAAAAAACEEEEIIIIDNOOOOOUUUUY';

    var result = text;
    for (int i = 0; i < diacritics.length; i++) {
      result = result.replaceAll(diacritics[i], replacements[i]);
    }
    // Remove any remaining non-ASCII
    result = result.replaceAll(RegExp(r'[^\x00-\x7F]'), '');
    return result;
  }

  /// Look up an image URL for a Checkers or Shoprite product.
  ///
  /// Returns the Supabase Storage URL if found, otherwise `null`.
  /// For PnP and Woolworths, always returns `null` (their API images work).
  ///
  /// Tries exact match first, then prefix match for truncated names
  /// (some API responses cut off long product names with "...").
  String? lookupImage({required String retailer, required String productName}) {
    if (_cache == null) return null;

    final slug = _retailerSlug(retailer);
    if (slug == null) return null;

    final retailerCache = _cache![slug];
    if (retailerCache == null) return null;

    // Clean trailing ellipsis/dots from truncated API names
    var cleanName = productName
        .replaceAll(RegExp(r'\s*\.{2,}\s*$'), '') // "Powder ..." → "Powder"
        .replaceAll(RegExp(r'\s*…\s*$'), '') // "Powder…" → "Powder"
        .trim();

    final normalizedName = normalizeName(cleanName);

    // Try exact match first
    final exact = retailerCache[normalizedName];
    if (exact != null) return exact;

    // Prefix match fallback for truncated names (min 20 chars to avoid false matches)
    if (normalizedName.length >= 20) {
      for (final entry in retailerCache.entries) {
        if (entry.key.startsWith(normalizedName)) {
          return entry.value;
        }
      }
    }

    return null;
  }

  /// Map retailer display name to cache slug.
  /// Only Checkers and Shoprite need image lookup.
  String? _retailerSlug(String retailer) {
    final lower = retailer.toLowerCase();
    if (lower.contains('checkers')) return 'checkers';
    if (lower.contains('shoprite')) return 'shoprite';
    return null; // PnP and Woolworths don't need lookup
  }
}
