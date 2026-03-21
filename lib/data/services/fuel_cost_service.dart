// lib/data/services/fuel_cost_service.dart

import '../models/vehicle_config.dart';

/// Calculates fuel cost for round trips to stores.
class FuelCostService {
  /// Calculate the fuel cost for a round trip to a store.
  ///
  /// [distanceKm] is the one-way distance from the user to the store.
  /// [consumptionPer100km] is the vehicle's fuel consumption in L/100km.
  /// [fuelPricePerLitre] is the current fuel price in Rands.
  FuelCostBreakdown calculateTripCost({
    required double distanceKm,
    required double consumptionPer100km,
    required double fuelPricePerLitre,
  }) {
    final roundTripKm = distanceKm * 2;
    final fuelUsedLitres = roundTripKm * (consumptionPer100km / 100);
    final fuelCostRands = fuelUsedLitres * fuelPricePerLitre;

    return FuelCostBreakdown(
      distanceKm: distanceKm,
      roundTripKm: roundTripKm,
      fuelUsedLitres: fuelUsedLitres,
      fuelCostRands: fuelCostRands,
      totalTripCost: fuelCostRands,
    );
  }
}
