// lib/data/services/live_api_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import '../../core/constants/live_api_config.dart';
import '../../core/constants/retailers.dart';
import '../models/live_product.dart';
import '../models/nearby_store.dart';

/// HTTP client for the live retailer API proxy (Supabase Edge Functions).
///
/// All methods call the POC Supabase Edge Functions defined in
/// [LiveApiConfig]. This is separate from the production Supabase client
/// used for auth, lists, and user data.
///
/// Usage via Riverpod:
/// ```dart
/// final api = ref.read(liveApiServiceProvider);
/// final stores = await api.fetchNearbyStores(lat: -26.2, lng: 28.0);
/// ```
class LiveApiService {
  final http.Client _client;
  final Logger _logger = Logger();

  LiveApiService({http.Client? client}) : _client = client ?? http.Client();

  /// Retry an async operation with exponential backoff.
  ///
  /// Attempts [maxRetries] times with delays of 1s, 2s, 4s between attempts.
  /// Only retries on timeout or HTTP errors, not on argument/parse errors.
  Future<T> _retryWithBackoff<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    String label = 'API call',
  }) async {
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        return await operation();
      } catch (e) {
        final isRetryable = e is TimeoutException ||
            e is http.ClientException ||
            e is LiveApiException;

        if (!isRetryable || attempt == maxRetries) {
          rethrow;
        }

        final delay = Duration(seconds: 1 << (attempt - 1)); // 1s, 2s, 4s
        _logger.w('$label attempt $attempt failed, retrying in ${delay.inSeconds}s: $e');
        await Future.delayed(delay);
      }
    }
    throw StateError('Unreachable'); // dart needs this for type safety
  }

  // ──────────────────────────────────────────────────────────────────────────
  // STORES NEARBY
  // ──────────────────────────────────────────────────────────────────────────

  /// Fetch the nearest store for each retailer based on GPS coordinates.
  ///
  /// Calls the `stores-nearby` Edge Function which queries PostGIS
  /// to find the closest store per retailer.
  ///
  /// Returns a list of [NearbyStore] — typically one per retailer (4 total).
  /// May return fewer if a retailer has no stores in the vicinity.
  Future<List<NearbyStore>> fetchNearbyStores({
    required double latitude,
    required double longitude,
  }) async {
    final url = LiveApiConfig.edgeFunctionUrl('stores-nearby');

    _logger.d('Fetching nearby stores for ($latitude, $longitude)');

    final response = await _retryWithBackoff(
      () => _client
          .post(
            Uri.parse(url),
            headers: LiveApiConfig.headers,
            body: jsonEncode({'latitude': latitude, 'longitude': longitude}),
          )
          .timeout(LiveApiConfig.requestTimeout)
          .then((r) {
            if (r.statusCode != 200) {
              throw LiveApiException(
                'Failed to fetch nearby stores',
                statusCode: r.statusCode,
                body: r.body,
              );
            }
            return r;
          }),
      label: 'stores-nearby',
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final storesMap = data['stores'] as Map<String, dynamic>? ?? {};

    final stores = <NearbyStore>[];
    for (final entry in storesMap.entries) {
      try {
        stores.add(
          NearbyStore.fromJson(entry.key, entry.value as Map<String, dynamic>),
        );
      } catch (e) {
        _logger.w('Failed to parse store for ${entry.key}: $e');
      }
    }

    _logger.i('Found ${stores.length} nearby stores');
    return stores;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // BROWSE PRODUCTS
  // ──────────────────────────────────────────────────────────────────────────

  /// Browse products for a retailer at a specific store.
  ///
  /// This fetches the retailer's product catalog for the given store,
  /// paginated. The Edge Function handles store-specific API calls
  /// (SAP Hybris for PnP, CSRF + HTML for Checkers/Shoprite, etc.).
  ///
  /// For Woolworths, a `place_id` is needed for browse (confirmPlace API).
  /// If unavailable, browse may fail — use [searchProducts] as fallback.
  Future<LiveProductsResponse> browseProducts({
    required String retailer,
    required NearbyStore store,
    String? category,
    int page = 0,
    int pageSize = 24,
  }) async {
    final config = Retailers.fromName(retailer);
    if (config == null) {
      throw LiveApiException('Unknown retailer: $retailer');
    }

    final url = LiveApiConfig.edgeFunctionUrl(config.edgeFunctionName);

    final body = <String, dynamic>{'page': page, 'page_size': pageSize};

    // Woolworths browse needs a Google Place ID for confirmPlace
    if (retailer == 'Woolworths') {
      body['place_id'] = store.placeId ?? store.storeCode;
      body['place_nickname'] = store.placeNickname ?? store.storeName;
      if (category != null) body['category'] = category;
    } else {
      body['store_code'] = store.storeCode;
      if (category != null) body['category'] = category;
    }

    _logger.d('Browsing $retailer (${store.storeName}), page $page');

    final response = await _retryWithBackoff(
      () => _client
          .post(
            Uri.parse(url),
            headers: LiveApiConfig.headers,
            body: jsonEncode(body),
          )
          .timeout(LiveApiConfig.requestTimeout)
          .then((r) {
            if (r.statusCode != 200) {
              throw LiveApiException(
                'Failed to browse $retailer products',
                statusCode: r.statusCode,
                body: r.body,
              );
            }
            return r;
          }),
      label: 'browse-$retailer',
    );

    return LiveProductsResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SEARCH PRODUCTS
  // ──────────────────────────────────────────────────────────────────────────

  /// Search products by query for a specific retailer and store.
  ///
  /// For Woolworths, search uses Constructor.io and doesn't need a place_id,
  /// so it works even when browse is unavailable.
  Future<LiveProductsResponse> searchProducts({
    required String retailer,
    required NearbyStore store,
    required String query,
    int page = 0,
    int pageSize = 24,
  }) async {
    final config = Retailers.fromName(retailer);
    if (config == null) {
      throw LiveApiException('Unknown retailer: $retailer');
    }

    final url = LiveApiConfig.edgeFunctionUrl(config.edgeFunctionName);

    final body = <String, dynamic>{
      'query': query,
      'page': page,
      'page_size': pageSize,
    };

    // Woolworths search uses Constructor.io (no store_code needed),
    // but we pass place info for consistency
    if (retailer == 'Woolworths') {
      if (store.placeId != null) body['place_id'] = store.placeId;
      if (store.placeNickname != null) {
        body['place_nickname'] = store.placeNickname;
      }
    } else {
      body['store_code'] = store.storeCode;
    }

    _logger.d('Searching $retailer for "$query", page $page');

    final response = await _retryWithBackoff(
      () => _client
          .post(
            Uri.parse(url),
            headers: LiveApiConfig.headers,
            body: jsonEncode(body),
          )
          .timeout(LiveApiConfig.requestTimeout)
          .then((r) {
            if (r.statusCode != 200) {
              throw LiveApiException(
                'Failed to search $retailer',
                statusCode: r.statusCode,
                body: r.body,
              );
            }
            return r;
          }),
      label: 'search-$retailer',
    );

    return LiveProductsResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // COMPARE PRODUCTS
  // ──────────────────────────────────────────────────────────────────────────

  /// Search all retailers in parallel for the same product name.
  ///
  /// Used for cross-retailer price comparison. Each retailer search
  /// runs independently; failures for individual retailers are caught
  /// and return an empty list (so partial results are still useful).
  Future<Map<String, List<LiveProduct>>> compareProduct({
    required String productName,
    required Map<String, NearbyStore> stores,
  }) async {
    final results = <String, List<LiveProduct>>{};
    final futures = <Future<void>>[];

    for (final entry in stores.entries) {
      final retailer = entry.key;
      final store = entry.value;

      futures.add(
        searchProducts(
              retailer: retailer,
              store: store,
              query: productName,
              pageSize: 10, // Only need top results for comparison
            )
            .then((response) {
              results[retailer] = response.products;
            })
            .catchError((Object e) {
              _logger.w('Comparison search failed for $retailer: $e');
              results[retailer] = [];
            }),
      );
    }

    await Future.wait(futures);
    _logger.i(
      'Comparison complete: ${results.entries.map((e) => '${e.key}=${e.value.length}').join(', ')}',
    );
    return results;
  }

  /// Clean up the HTTP client.
  void dispose() => _client.close();
}

/// Exception thrown by [LiveApiService] when an Edge Function call fails.
class LiveApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? body;

  LiveApiException(this.message, {this.statusCode, this.body});

  @override
  String toString() {
    if (statusCode != null) {
      return 'LiveApiException($statusCode): $message';
    }
    return 'LiveApiException: $message';
  }
}
