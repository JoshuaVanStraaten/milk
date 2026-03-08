// lib/data/models/nearby_store.dart

import '../../core/constants/retailers.dart';

/// A physical store returned by the `stores-nearby` Edge Function.
///
/// Each retailer returns its nearest store to the user's GPS coordinates.
/// The response is an object keyed by retailer slug ("pnp", "woolworths", etc.),
/// so [fromJson] takes both the slug key and the store JSON.
class NearbyStore {
  /// Display name of the retailer (e.g. "Pick n Pay")
  final String retailer;

  /// Branch/store name (e.g. "Pick n Pay Sandton City")
  final String storeName;

  /// Internal store code used in product API requests
  final String storeCode;

  /// Distance from the user's location in kilometres
  final double distanceKm;

  /// Store GPS coordinates
  final double latitude;
  final double longitude;

  /// Google Place ID — required for Woolworths browse (confirmPlace API).
  /// May be `null` if the stores-nearby endpoint doesn't return it.
  final String? placeId;

  /// Address/nickname for Woolworths (used with place_id)
  final String? placeNickname;

  const NearbyStore({
    required this.retailer,
    required this.storeName,
    required this.storeCode,
    required this.distanceKm,
    required this.latitude,
    required this.longitude,
    this.placeId,
    this.placeNickname,
  });

  /// Parse from the `stores-nearby` response.
  ///
  /// The Edge Function returns:
  /// ```json
  /// {
  ///   "stores": {
  ///     "pnp": { "store_name": "...", "store_code": "40121", ... },
  ///     "woolworths": { ... }
  ///   }
  /// }
  /// ```
  /// [retailerSlug] is the key (e.g. "pnp"), [json] is the value object.
  factory NearbyStore.fromJson(String retailerSlug, Map<String, dynamic> json) {
    return NearbyStore(
      retailer: _retailerDisplayName(retailerSlug),
      storeName: json['store_name'] as String? ?? '',
      storeCode: json['store_code']?.toString() ?? '',
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0.0,
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      placeId: json['place_id'] as String?,
      placeNickname: json['place_nickname'] as String?,
    );
  }

  /// Map API slug to display name.
  static String _retailerDisplayName(String slug) {
    return Retailers.fromSlug(slug)?.name ?? slug;
  }

  /// Formatted distance string for UI (e.g. "2.1 km")
  String get formattedDistance => '${distanceKm.toStringAsFixed(1)} km';

  @override
  String toString() => 'NearbyStore($retailer: $storeName, $formattedDistance)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NearbyStore &&
          retailer == other.retailer &&
          storeCode == other.storeCode;

  @override
  int get hashCode => Object.hash(retailer, storeCode);
}

/// Holds the user's selected stores — one per retailer.
///
/// Populated after calling the `stores-nearby` Edge Function with
/// the user's GPS coordinates. The map is keyed by retailer display name.
class StoreSelection {
  final Map<String, NearbyStore> stores;

  const StoreSelection({required this.stores});

  NearbyStore? get pnp => stores['Pick n Pay'];
  NearbyStore? get woolworths => stores['Woolworths'];
  NearbyStore? get checkers => stores['Checkers'];
  NearbyStore? get shoprite => stores['Shoprite'];

  /// Whether all 4 retailers have a nearby store
  bool get isComplete => stores.length == 4;

  /// Look up the store for a given retailer display name
  NearbyStore? forRetailer(String name) => stores[name];

  /// Convert to a JSON-serializable map (for SharedPreferences persistence)
  Map<String, dynamic> toJson() {
    return stores.map(
      (key, store) => MapEntry(key, {
        'store_name': store.storeName,
        'store_code': store.storeCode,
        'distance_km': store.distanceKm,
        'latitude': store.latitude,
        'longitude': store.longitude,
        'place_id': store.placeId,
        'place_nickname': store.placeNickname,
      }),
    );
  }

  /// Restore from JSON (from SharedPreferences)
  factory StoreSelection.fromJson(Map<String, dynamic> json) {
    final stores = <String, NearbyStore>{};
    for (final entry in json.entries) {
      final storeJson = entry.value as Map<String, dynamic>;
      // Find the slug for this retailer name to use fromJson
      final config = Retailers.fromName(entry.key);
      if (config != null) {
        stores[entry.key] = NearbyStore.fromJson(config.slug, storeJson);
      }
    }
    return StoreSelection(stores: stores);
  }

  @override
  String toString() => 'StoreSelection(${stores.keys.join(', ')})';
}
