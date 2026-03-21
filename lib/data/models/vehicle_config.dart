// lib/data/models/vehicle_config.dart

/// Vehicle type presets with SA-typical fuel consumption rates.
enum VehicleType { small, medium, large, custom }

/// User's vehicle configuration for fuel cost calculations.
class VehicleConfig {
  final VehicleType type;
  final double consumptionPer100km; // L/100km
  final String label;
  final String fuelType; // 'petrol_93', 'petrol_95', 'diesel_50ppm', 'diesel_500ppm'
  final String region; // 'coastal', 'inland'

  const VehicleConfig({
    required this.type,
    required this.consumptionPer100km,
    required this.label,
    required this.fuelType,
    required this.region,
  });

  /// SA average blended consumption rates (city + highway mix).
  static const Map<VehicleType, double> defaultConsumption = {
    VehicleType.small: 5.8, // VW Polo, Toyota Starlet
    VehicleType.medium: 7.5, // Toyota Corolla, Mazda 3
    VehicleType.large: 9.8, // Toyota Fortuner, Rav4
  };

  static const Map<VehicleType, String> defaultLabels = {
    VehicleType.small: 'Small Car',
    VehicleType.medium: 'Medium Car',
    VehicleType.large: 'Large / SUV',
    VehicleType.custom: 'Custom',
  };

  /// Human-readable fuel type labels for UI.
  static const Map<String, String> fuelTypeLabels = {
    'petrol_93': 'Petrol 93',
    'petrol_95': 'Petrol 95',
    'diesel_50ppm': 'Diesel 50ppm',
    'diesel_500ppm': 'Diesel 500ppm',
  };

  /// Human-readable region labels.
  static const Map<String, String> regionLabels = {
    'coastal': 'Coastal',
    'inland': 'Inland',
  };

  /// Coastal cities in SA (for auto-detection).
  static const List<String> coastalCities = [
    'cape town',
    'durban',
    'port elizabeth',
    'gqeberha',
    'east london',
    'richards bay',
    'george',
    'mossel bay',
    'knysna',
    'plettenberg bay',
    'hermanus',
    'jeffreys bay',
    'ballito',
    'umhlanga',
  ];

  String get fuelTypeLabel => fuelTypeLabels[fuelType] ?? fuelType;
  String get regionLabel => regionLabels[region] ?? region;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'consumptionPer100km': consumptionPer100km,
        'label': label,
        'fuelType': fuelType,
        'region': region,
      };

  factory VehicleConfig.fromJson(Map<String, dynamic> json) => VehicleConfig(
        type: VehicleType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => VehicleType.medium,
        ),
        consumptionPer100km:
            (json['consumptionPer100km'] as num?)?.toDouble() ?? 7.5,
        label: json['label'] as String? ?? 'Medium Car',
        fuelType: json['fuelType'] as String? ?? 'petrol_95',
        region: json['region'] as String? ?? 'inland',
      );

  VehicleConfig copyWith({
    VehicleType? type,
    double? consumptionPer100km,
    String? label,
    String? fuelType,
    String? region,
  }) =>
      VehicleConfig(
        type: type ?? this.type,
        consumptionPer100km: consumptionPer100km ?? this.consumptionPer100km,
        label: label ?? this.label,
        fuelType: fuelType ?? this.fuelType,
        region: region ?? this.region,
      );
}

/// Result of a fuel cost calculation for a round trip to a store.
class FuelCostBreakdown {
  final double distanceKm; // one-way
  final double roundTripKm;
  final double fuelUsedLitres;
  final double fuelCostRands;
  final double totalTripCost;

  const FuelCostBreakdown({
    required this.distanceKm,
    required this.roundTripKm,
    required this.fuelUsedLitres,
    required this.fuelCostRands,
    required this.totalTripCost,
  });
}

/// Delivery app fee configuration for cost comparison.
class DeliveryFeeConfig {
  final String appName;
  final double fee;
  final double? freeAbove; // cart total above which delivery is free

  const DeliveryFeeConfig({
    required this.appName,
    required this.fee,
    this.freeAbove,
  });

  /// SA delivery app fees (hardcoded, update as needed).
  static const Map<String, DeliveryFeeConfig> fees = {
    'Checkers': DeliveryFeeConfig(
        appName: 'Sixty60', fee: 36.0),
    'Woolworths':
        DeliveryFeeConfig(appName: 'Dash', fee: 45.0, freeAbove: 350.0),
    'Pick n Pay':
        DeliveryFeeConfig(appName: 'asap!', fee: 35.0, freeAbove: 400.0),
  };
}
