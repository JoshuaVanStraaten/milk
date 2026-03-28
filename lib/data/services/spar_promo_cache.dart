// lib/data/services/spar_promo_cache.dart
//
// In-memory cache of SPAR catalogue specials from my-catalogue.co.za.
// Loaded lazily on the first SPAR product request, then cached for 6 hours.
//
// Used by the home deals page to show SPAR promotional specials.
// Cross-referencing with browse/search is disabled because the catalogue
// uses generic names ("Eggs", "Milk") that cause false positive matches
// against specific KwikSPAR names.

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/live_product.dart';
import '../models/nearby_store.dart';
import 'live_api_service.dart';

class SparPromoCache {
  List<LiveProduct>? _cachedSpecials;
  DateTime? _lastFetch;
  Completer<List<LiveProduct>>? _fetchCompleter;
  static const _ttl = Duration(hours: 6);

  /// Lazy-load specials from the SPAR edge function (specials mode).
  /// First call triggers the fetch; concurrent calls wait for the same result.
  Future<List<LiveProduct>> getSpecials(
    LiveApiService api,
    NearbyStore store,
  ) async {
    // Return cached if still fresh
    if (_cachedSpecials != null &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < _ttl) {
      return _cachedSpecials!;
    }

    // If a fetch is already in progress, wait for it
    if (_fetchCompleter != null) {
      return _fetchCompleter!.future;
    }

    _fetchCompleter = Completer<List<LiveProduct>>();

    try {
      final response = await api.fetchSpecials(
        retailer: 'SPAR',
        store: store,
      );
      _cachedSpecials = response.products;
      _lastFetch = DateTime.now();
      _fetchCompleter!.complete(_cachedSpecials!);
      debugPrint(
        '[SparPromoCache] Loaded ${_cachedSpecials!.length} catalogue specials',
      );
      return _cachedSpecials!;
    } catch (e) {
      debugPrint('[SparPromoCache] Failed to fetch specials: $e');
      final fallback = _cachedSpecials ?? [];
      _fetchCompleter!.complete(fallback);
      return fallback;
    } finally {
      _fetchCompleter = null;
    }
  }

  /// Cross-reference a list of SPAR products against cached specials.
  ///
  /// Currently disabled: catalogue names are too generic ("Eggs", "Milk")
  /// to safely match against specific KwikSPAR names. This caused wrong
  /// SALE badges on browse. Specials still show on home deals page.
  List<LiveProduct> enrichWithPromos(List<LiveProduct> products) {
    return products;
  }

  /// Whether the cache has been loaded (regardless of content).
  bool get isLoaded => _cachedSpecials != null;

  /// Number of cached specials (for diagnostics).
  int get specialsCount => _cachedSpecials?.length ?? 0;
}
