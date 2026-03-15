// lib/domain/providers/store_provider.dart

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/nearby_store.dart';
import '../../data/models/live_product.dart';
import '../../data/services/live_api_service.dart';
import '../../data/services/fallback_product_service.dart';
import '../../data/services/location_service.dart';
import '../../data/services/smart_matching_service.dart';
import 'recipe_provider.dart' show geminiServiceProvider;
import 'theme_provider.dart'; // for sharedPreferencesProvider

// =============================================================================
// SERVICE PROVIDERS
// =============================================================================

/// Singleton [LiveApiService] instance.
/// Disposed when the provider is no longer needed.
final liveApiServiceProvider = Provider<LiveApiService>((ref) {
  final service = LiveApiService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Wraps [LiveApiService] with automatic DB fallback.
/// Use this for browse/search/compare — transparent failover.
final fallbackProductServiceProvider = Provider<FallbackProductService>((ref) {
  final liveApi = ref.read(liveApiServiceProvider);
  return FallbackProductService(
    liveApi: liveApi,
    supabase: Supabase.instance.client,
  );
});

/// Singleton [LocationService] instance.
final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

/// Smart matching service — hybrid algorithm + AI product matching.
final smartMatchingServiceProvider = Provider<SmartMatchingService>((ref) {
  final gemini = ref.read(geminiServiceProvider);
  return SmartMatchingService(gemini: gemini);
});

// =============================================================================
// STORE SELECTION (PERSISTED)
// =============================================================================

/// SharedPreferences key for persisted store selection.
const _storeSelectionKey = 'selected_stores_json';

/// SharedPreferences key for the user's last known coordinates.
const _lastCoordsKey = 'last_location_coords';

/// SharedPreferences key for whether user has completed store setup.
const _storeSetupCompleteKey = 'store_setup_complete';

/// Whether the user has completed the initial store selection flow.
///
/// This replaces the old `hasCompletedOnboarding` from provinceProvider.
/// Checked by the router to redirect to store selection if needed.
final hasCompletedStoreSetupProvider = StateProvider<bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getBool(_storeSetupCompleteKey) ?? false;
});

/// Manages fetching nearby stores and persisting the user's selection.
///
/// State lifecycle:
/// 1. On app start: loads persisted [StoreSelection] from SharedPreferences
/// 2. During onboarding: fetches fresh stores via GPS + Edge Function
/// 3. After selection: persists to SharedPreferences
/// 4. On "change store": re-fetches with new/same coordinates
class StoreSelectionNotifier extends StateNotifier<AsyncValue<StoreSelection>> {
  final LiveApiService _api;
  final SharedPreferences _prefs;

  StoreSelectionNotifier(this._api, this._prefs)
    : super(const AsyncValue.loading()) {
    // Try to load persisted stores on creation
    _loadPersistedStores();
  }

  /// Load previously saved store selection from SharedPreferences.
  void _loadPersistedStores() {
    final json = _prefs.getString(_storeSelectionKey);
    if (json != null) {
      try {
        final decoded = jsonDecode(json) as Map<String, dynamic>;
        final selection = StoreSelection.fromJson(decoded);
        if (selection.stores.isNotEmpty) {
          state = AsyncValue.data(selection);
          return;
        }
      } catch (_) {
        // Corrupted data — will re-fetch
      }
    }
    // No persisted data — stay in loading state until fetchNearbyStores
    state = const AsyncValue.data(StoreSelection(stores: {}));
  }

  /// Fetch nearby stores from the Edge Function using GPS coordinates.
  ///
  /// This calls `stores-nearby` and populates the store map.
  /// Results are automatically persisted to SharedPreferences.
  Future<void> fetchNearbyStores(double lat, double lng) async {
    state = const AsyncValue.loading();

    try {
      final stores = await _api.fetchNearbyStores(
        latitude: lat,
        longitude: lng,
      );

      final storeMap = <String, NearbyStore>{};
      for (final store in stores) {
        storeMap[store.retailer] = store;
      }

      final selection = StoreSelection(stores: storeMap);

      // Persist to SharedPreferences
      await _prefs.setString(
        _storeSelectionKey,
        jsonEncode(selection.toJson()),
      );
      await _prefs.setString(
        _lastCoordsKey,
        jsonEncode({'lat': lat, 'lng': lng}),
      );

      state = AsyncValue.data(selection);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Mark store setup as complete (called after user picks their default retailer).
  Future<void> markSetupComplete() async {
    await _prefs.setBool(_storeSetupCompleteKey, true);
  }

  /// Clear persisted store data (e.g. for logout or re-onboarding).
  Future<void> clearStores() async {
    await _prefs.remove(_storeSelectionKey);
    await _prefs.remove(_lastCoordsKey);
    await _prefs.remove(_storeSetupCompleteKey);
    state = const AsyncValue.data(StoreSelection(stores: {}));
  }

  /// Get the last known coordinates (for refreshing stores without GPS).
  Map<String, double>? get lastCoordinates {
    final json = _prefs.getString(_lastCoordsKey);
    if (json == null) return null;
    try {
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      return {
        'lat': (decoded['lat'] as num).toDouble(),
        'lng': (decoded['lng'] as num).toDouble(),
      };
    } catch (_) {
      return null;
    }
  }
}

final storeSelectionProvider =
    StateNotifierProvider<StoreSelectionNotifier, AsyncValue<StoreSelection>>((
      ref,
    ) {
      final api = ref.read(liveApiServiceProvider);
      final prefs = ref.read(sharedPreferencesProvider);
      return StoreSelectionNotifier(api, prefs);
    });

// =============================================================================
// SELECTED RETAILER
// =============================================================================

/// The currently selected retailer on the Browse tab.
/// Defaults to "Pick n Pay" but updates when the user taps retailer chips.
final selectedRetailerProvider = StateProvider<String>((ref) => 'Pick n Pay');

// =============================================================================
// LIVE PRODUCTS (BROWSE)
// =============================================================================

/// Manages paginated product browsing for the selected retailer + store.
///
/// Supports:
/// - Initial load when retailer/store changes
/// - Infinite scroll pagination via [loadNextPage]
/// - Pull-to-refresh via [loadProducts] with `refresh: true`
class LiveProductsNotifier
    extends StateNotifier<AsyncValue<LiveProductsResponse>> {
  final FallbackProductService _fallback;
  String? _currentRetailer;
  NearbyStore? _currentStore;
  String? _currentCategory;
  int _currentPage = 0;
  final List<LiveProduct> _allProducts = [];
  int _requestId = 0; // Incremented on each new load; stale responses are discarded

  LiveProductsNotifier(LiveApiService _, this._fallback)
    : super(const AsyncValue.data(LiveProductsResponse.empty));

  /// Load products for a retailer + store combination.
  ///
  /// If [refresh] is true or [retailer] changed, resets pagination.
  Future<void> loadProducts({
    required String retailer,
    required NearbyStore store,
    String? category,
    bool refresh = false,
  }) async {
    if (refresh || retailer != _currentRetailer || category != _currentCategory) {
      _currentPage = 0;
      _allProducts.clear();
      _currentRetailer = retailer;
      _currentStore = store;
      _currentCategory = category;
    }

    // Capture request ID — any response with a different ID is stale and discarded
    final requestId = ++_requestId;

    // Show loading if no products yet, otherwise keep showing current data
    state = _allProducts.isEmpty
        ? const AsyncValue.loading()
        : AsyncValue.data(
            LiveProductsResponse(
              products: List.from(_allProducts),
              currentPage: _currentPage,
              pageSize: 24,
              retailer: retailer,
            ),
          );

    try {
      final response = await _fallback.browseProducts(
        retailer: retailer,
        store: store,
        category: category,
        page: _currentPage,
      );

      // Discard if a newer request has started (category/retailer changed mid-flight)
      if (requestId != _requestId) return;

      _allProducts.addAll(response.products);

      state = AsyncValue.data(
        LiveProductsResponse(
          products: List.from(_allProducts),
          currentPage: _currentPage,
          totalPages: response.totalPages,
          totalResults: response.totalResults,
          pageSize: response.pageSize,
          retailer: retailer,
          source: response.source,
        ),
      );
    } catch (e, st) {
      if (requestId != _requestId) return;
      if (_allProducts.isEmpty) {
        state = AsyncValue.error(e, st);
      }
      // If we already have products, keep showing them (silent fail for pagination)
    }
  }

  /// Load the next page of products (for infinite scroll).
  Future<void> loadNextPage() async {
    if (_currentRetailer == null || _currentStore == null) return;
    _currentPage++;
    await loadProducts(
      retailer: _currentRetailer!,
      store: _currentStore!,
      category: _currentCategory,
    );
  }

  /// Reset the notifier (e.g. when switching stores).
  void reset() {
    _currentPage = 0;
    _allProducts.clear();
    _currentRetailer = null;
    _currentStore = null;
    _currentCategory = null;
    _requestId++;
    state = const AsyncValue.data(LiveProductsResponse.empty);
  }
}

final liveProductsProvider =
    StateNotifierProvider<
      LiveProductsNotifier,
      AsyncValue<LiveProductsResponse>
    >(
      (ref) => LiveProductsNotifier(
        ref.read(liveApiServiceProvider),
        ref.read(fallbackProductServiceProvider),
      ),
    );

// =============================================================================
// LIVE SEARCH
// =============================================================================

/// Current search query text (debounced in the UI).
final liveSearchQueryProvider = StateProvider<String>((ref) => '');

/// Manages search results for the selected retailer.
class LiveSearchNotifier
    extends StateNotifier<AsyncValue<LiveProductsResponse>> {
  final FallbackProductService _fallback;

  LiveSearchNotifier(LiveApiService _, this._fallback)
    : super(const AsyncValue.data(LiveProductsResponse.empty));

  /// Execute a search query against a retailer's Edge Function.
  Future<void> search({
    required String retailer,
    required NearbyStore store,
    required String query,
  }) async {
    if (query.trim().isEmpty) {
      state = const AsyncValue.data(LiveProductsResponse.empty);
      return;
    }

    state = const AsyncValue.loading();

    try {
      final response = await _fallback.searchProducts(
        retailer: retailer,
        store: store,
        query: query,
      );
      state = AsyncValue.data(
        LiveProductsResponse(
          products: response.products,
          currentPage: response.currentPage,
          totalPages: response.totalPages,
          totalResults: response.totalResults,
          pageSize: response.pageSize,
          retailer: response.retailer,
          source: response.source,
        ),
      );
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Clear search results (e.g. when search bar is cleared).
  void clear() {
    state = const AsyncValue.data(LiveProductsResponse.empty);
  }
}

final liveSearchProvider =
    StateNotifierProvider<LiveSearchNotifier, AsyncValue<LiveProductsResponse>>(
      (ref) => LiveSearchNotifier(
        ref.read(liveApiServiceProvider),
        ref.read(fallbackProductServiceProvider),
      ),
    );

// =============================================================================
// COMPARISON
// =============================================================================

/// Holds the result of a cross-retailer price comparison.
/// Populated when the user taps "Compare" on a product.
final liveComparisonProvider =
    StateProvider<AsyncValue<Map<String, List<LiveProduct>>>>((ref) {
      return const AsyncValue.data({});
    });
