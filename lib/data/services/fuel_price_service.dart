// lib/data/services/fuel_price_service.dart

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/live_api_config.dart';

/// A single fuel price entry.
class FuelPrice {
  final String fuelType; // 'petrol_93', 'petrol_95', 'diesel_50ppm', 'diesel_500ppm'
  final String region; // 'coastal', 'inland'
  final double pricePerLitre;
  final String effectiveDate;

  const FuelPrice({
    required this.fuelType,
    required this.region,
    required this.pricePerLitre,
    required this.effectiveDate,
  });

  factory FuelPrice.fromJson(Map<String, dynamic> json) => FuelPrice(
        fuelType: json['fuel_type'] as String,
        region: json['region'] as String,
        pricePerLitre: (json['price_per_litre'] as num).toDouble(),
        effectiveDate: json['effective_date'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'fuel_type': fuelType,
        'region': region,
        'price_per_litre': pricePerLitre,
        'effective_date': effectiveDate,
      };
}

/// Aggregated fuel price data with a lookup helper.
class FuelPriceData {
  final List<FuelPrice> prices;
  final DateTime? updatedAt;

  const FuelPriceData({required this.prices, this.updatedAt});

  /// Look up the price for a specific fuel type and region.
  /// Returns null if not found.
  double? getPrice(String fuelType, String region) {
    for (final p in prices) {
      if (p.fuelType == fuelType && p.region == region) {
        return p.pricePerLitre;
      }
    }
    return null;
  }

  /// Effective date string for the most recent price entry, or null.
  String? get effectiveDate {
    if (prices.isEmpty) return null;
    return prices.first.effectiveDate;
  }

  Map<String, dynamic> toJson() => {
        'prices': prices.map((p) => p.toJson()).toList(),
        'updated_at': updatedAt?.toIso8601String(),
      };

  factory FuelPriceData.fromJson(Map<String, dynamic> json) {
    final pricesRaw = json['prices'] as List<dynamic>? ?? [];
    return FuelPriceData(
      prices: pricesRaw
          .map((p) => FuelPrice.fromJson(p as Map<String, dynamic>))
          .toList(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  static const FuelPriceData empty = FuelPriceData(prices: []);
}

/// Fetches SA fuel prices from the fuel-prices Edge Function.
/// Caches results in SharedPreferences for 7 days.
/// Falls back to cached data on network failure.
class FuelPriceService {
  static const _cacheKey = 'fuel_prices_cache';
  static const _lastFetchKey = 'fuel_prices_last_fetch';
  static const _cacheDuration = Duration(days: 7);
  static const _refreshThreshold = Duration(days: 30);

  /// Fetch fuel prices. Uses cache if fresh, otherwise fetches from network.
  /// Never throws — always returns data (possibly stale or empty).
  Future<FuelPriceData> fetchPrices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = _loadFromCache(prefs);
      final lastFetch = _lastFetchTime(prefs);
      final cacheAge = lastFetch != null
          ? DateTime.now().difference(lastFetch)
          : const Duration(days: 999);

      // Return cached if fresh enough
      if (cached != null && cacheAge < _cacheDuration) {
        return cached;
      }

      // Fetch from network
      final shouldRefreshSource = cacheAge > _refreshThreshold;
      final data = await _fetchFromNetwork(refresh: shouldRefreshSource);

      if (data != null && data.prices.isNotEmpty) {
        await _saveToCache(prefs, data);
        return data;
      }

      // Network returned empty — use cache fallback
      return cached ?? FuelPriceData.empty;
    } catch (_) {
      // Any error — try cache
      try {
        final prefs = await SharedPreferences.getInstance();
        return _loadFromCache(prefs) ?? FuelPriceData.empty;
      } catch (_) {
        return FuelPriceData.empty;
      }
    }
  }

  Future<FuelPriceData?> _fetchFromNetwork({bool refresh = false}) async {
    try {
      final url = LiveApiConfig.edgeFunctionUrl('fuel-prices');

      final http.Response response;
      if (refresh) {
        response = await http
            .post(
              Uri.parse(url),
              headers: LiveApiConfig.headers,
              body: jsonEncode({'action': 'refresh'}),
            )
            .timeout(LiveApiConfig.requestTimeout);
      } else {
        response = await http
            .get(
              Uri.parse(url),
              headers: LiveApiConfig.headers,
            )
            .timeout(LiveApiConfig.requestTimeout);
      }

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final pricesRaw = json['prices'] as List<dynamic>? ?? [];

      final prices = pricesRaw
          .map((p) => FuelPrice.fromJson(p as Map<String, dynamic>))
          .toList();

      final updatedAt = json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : DateTime.now();

      return FuelPriceData(prices: prices, updatedAt: updatedAt);
    } catch (_) {
      return null;
    }
  }

  FuelPriceData? _loadFromCache(SharedPreferences prefs) {
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return null;
    try {
      return FuelPriceData.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  DateTime? _lastFetchTime(SharedPreferences prefs) {
    final ms = prefs.getInt(_lastFetchKey);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> _saveToCache(SharedPreferences prefs, FuelPriceData data) async {
    await prefs.setString(_cacheKey, jsonEncode(data.toJson()));
    await prefs.setInt(_lastFetchKey, DateTime.now().millisecondsSinceEpoch);
  }
}
