// lib/data/services/fallback_product_service.dart
//
// Wraps LiveApiService with automatic DB fallback. When a live API
// call fails (timeout, server error, rate limit), this service
// queries the Supabase Products table as a backup data source.
//
// The fallback returns products in the same LiveProduct /
// LiveProductsResponse format so the UI doesn't need to know
// which source provided the data. The `source` field is set to
// "database_fallback" so the UI can optionally show a banner.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/live_product.dart';
import '../models/nearby_store.dart';
import 'live_api_service.dart';
import 'spar_promo_cache.dart';

class FallbackProductService {
  final LiveApiService _liveApi;
  final SupabaseClient _supabase;
  final SparPromoCache _sparPromoCache;

  FallbackProductService({
    required LiveApiService liveApi,
    required SupabaseClient supabase,
    required SparPromoCache sparPromoCache,
  }) : _liveApi = liveApi,
       _supabase = supabase,
       _sparPromoCache = sparPromoCache;

  // ──────────────────────────────────────────────────────────────────────────
  // BROWSE
  // ──────────────────────────────────────────────────────────────────────────

  /// Browse products — tries live API first, falls back to DB.
  /// For SPAR, enriches results with catalogue promo data.
  Future<LiveProductsResponse> browseProducts({
    required String retailer,
    required NearbyStore store,
    String? category,
    int page = 0,
    int pageSize = 24,
  }) async {
    LiveProductsResponse response;
    try {
      response = await _liveApi.browseProducts(
        retailer: retailer,
        store: store,
        category: category,
        page: page,
      );
    } catch (e) {
      debugPrint(
        'Live API browse failed for $retailer: $e — using DB fallback',
      );
      response = await _dbBrowse(retailer: retailer, page: page, pageSize: pageSize);
    }

    return _enrichSparPromos(response, retailer, store);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SEARCH
  // ──────────────────────────────────────────────────────────────────────────

  /// Search products — tries live API first, falls back to DB.
  /// For SPAR, enriches results with catalogue promo data.
  Future<LiveProductsResponse> searchProducts({
    required String retailer,
    required NearbyStore store,
    required String query,
    int pageSize = 24,
  }) async {
    LiveProductsResponse response;
    try {
      response = await _liveApi.searchProducts(
        retailer: retailer,
        store: store,
        query: query,
        pageSize: pageSize,
      );
    } catch (e) {
      debugPrint(
        'Live API search failed for $retailer: $e — using DB fallback',
      );
      response = await _dbSearch(retailer: retailer, query: query, pageSize: pageSize);
    }

    return _enrichSparPromos(response, retailer, store);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // COMPARE (multi-retailer)
  // ──────────────────────────────────────────────────────────────────────────

  /// Compare product across retailers — each retailer falls back independently.
  /// For SPAR, enriches results with catalogue promo data.
  Future<Map<String, List<LiveProduct>>> compareProduct({
    required String productName,
    required Map<String, NearbyStore> stores,
  }) async {
    final results = <String, List<LiveProduct>>{};
    final futures = <Future<void>>[];

    for (final entry in stores.entries) {
      futures.add(() async {
        List<LiveProduct> products;
        try {
          final response = await _liveApi.searchProducts(
            retailer: entry.key,
            store: entry.value,
            query: productName,
            pageSize: 5,
          );
          products = response.products;
        } catch (e) {
          debugPrint('Compare failed for ${entry.key}: $e — using DB fallback');
          try {
            final fallback = await _dbSearch(
              retailer: entry.key,
              query: productName,
              pageSize: 5,
            );
            products = fallback.products;
          } catch (_) {
            products = [];
          }
        }

        // Enrich SPAR results with promo data
        if (entry.key == 'SPAR' && products.isNotEmpty) {
          await _sparPromoCache.getSpecials(_liveApi, entry.value);
          products = _sparPromoCache.enrichWithPromos(products);
        }

        results[entry.key] = products;
      }());
    }

    await Future.wait(futures);
    return results;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SPAR PROMO ENRICHMENT
  // ──────────────────────────────────────────────────────────────────────────

  /// Enrich SPAR product responses with catalogue promo data.
  /// No-op for non-SPAR retailers.
  Future<LiveProductsResponse> _enrichSparPromos(
    LiveProductsResponse response,
    String retailer,
    NearbyStore store,
  ) async {
    if (retailer != 'SPAR') return response;

    try {
      await _sparPromoCache.getSpecials(_liveApi, store);
      return response.copyWith(
        products: _sparPromoCache.enrichWithPromos(response.products),
      );
    } catch (e) {
      debugPrint('SPAR promo enrichment failed: $e');
      return response;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // PASSTHROUGH (no fallback needed)
  // ──────────────────────────────────────────────────────────────────────────

  /// Nearby stores — no DB fallback (this data IS the DB).
  Future<List<NearbyStore>> fetchNearbyStores({
    required double latitude,
    required double longitude,
  }) {
    return _liveApi.fetchNearbyStores(latitude: latitude, longitude: longitude);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // DB FALLBACK — PRIVATE
  // ──────────────────────────────────────────────────────────────────────────

  /// Browse products from the Products table.
  Future<LiveProductsResponse> _dbBrowse({
    required String retailer,
    int page = 0,
    int pageSize = 24,
  }) async {
    final start = page * pageSize;
    final end = start + pageSize - 1;

    final response = await _supabase
        .from('Products')
        .select()
        .eq('retailer', retailer)
        .range(start, end)
        .order('name', ascending: true);

    final products = (response as List)
        .map((row) => _dbRowToLiveProduct(row as Map<String, dynamic>))
        .toList();

    return LiveProductsResponse(
      products: products,
      currentPage: page,
      pageSize: pageSize,
      retailer: retailer,
      source: 'database_fallback',
    );
  }

  /// Search products from the Products table using ilike.
  Future<LiveProductsResponse> _dbSearch({
    required String retailer,
    required String query,
    int pageSize = 24,
  }) async {
    // Split query into words for better matching
    final words = query
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 2)
        .toList();

    if (words.isEmpty) {
      return LiveProductsResponse(
        products: [],
        currentPage: 0,
        pageSize: pageSize,
        retailer: retailer,
        source: 'database_fallback',
      );
    }

    // Build a filter: each word must appear in the name
    // Use the first word as primary filter, then filter client-side for others
    var queryBuilder = _supabase
        .from('Products')
        .select()
        .eq('retailer', retailer)
        .ilike('name', '%${words.first}%')
        .limit(pageSize * 2); // Fetch extra for client-side filtering

    final response = await queryBuilder;

    var products = (response as List)
        .map((row) => _dbRowToLiveProduct(row as Map<String, dynamic>))
        .toList();

    // Client-side filter for additional words
    if (words.length > 1) {
      products = products.where((p) {
        final nameLower = p.name.toLowerCase();
        return words.every((w) => nameLower.contains(w.toLowerCase()));
      }).toList();
    }

    // Limit to pageSize
    if (products.length > pageSize) {
      products = products.sublist(0, pageSize);
    }

    return LiveProductsResponse(
      products: products,
      currentPage: 0,
      pageSize: pageSize,
      retailer: retailer,
      source: 'database_fallback',
    );
  }

  /// Convert a Products table row → LiveProduct.
  ///
  /// Products table schema:
  ///   index (text PK), name, price, promotion_price,
  ///   retailer, image_url, promotion_valid
  LiveProduct _dbRowToLiveProduct(Map<String, dynamic> row) {
    final priceStr = row['price'] as String? ?? 'R0.00';
    final promo = row['promotion_price'] as String? ?? 'No promo';
    final promoLower = promo.toLowerCase().trim();
    final hasPromo =
        promoLower != 'no promo' &&
        promoLower != 'no promotion' &&
        promoLower != 'no special' &&
        promoLower.isNotEmpty;

    return LiveProduct(
      name: row['name'] as String? ?? 'Unknown',
      price: priceStr.startsWith('R') ? priceStr : 'R$priceStr',
      priceNumeric: _parsePrice(priceStr),
      promotionPrice: promo,
      retailer: row['retailer'] as String? ?? '',
      imageUrl: row['image_url'] as String?,
      promotionValid: row['promotion_valid'] as String? ?? '',
      hasPromo: hasPromo,
    );
  }

  /// Parse "R36.99" or "36.99" → 36.99
  static double _parsePrice(String priceStr) {
    return double.tryParse(
          priceStr
              .replaceAll('R', '')
              .replaceAll(',', '')
              .replaceAll(' ', '')
              .trim(),
        ) ??
        0.0;
  }
}
