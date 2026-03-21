import 'package:flutter_test/flutter_test.dart';
import 'package:milk/data/models/vehicle_config.dart';
import 'package:milk/data/services/fuel_cost_service.dart';

void main() {
  late FuelCostService service;

  setUp(() {
    service = FuelCostService();
  });

  group('FuelCostService.calculateTripCost', () {
    test('basic round trip calculation', () {
      final result = service.calculateTripCost(
        distanceKm: 5.0,
        consumptionPer100km: 7.5,
        fuelPricePerLitre: 20.30,
      );

      expect(result.distanceKm, 5.0);
      expect(result.roundTripKm, 10.0);
      // 10km * 7.5/100 = 0.75L
      expect(result.fuelUsedLitres, closeTo(0.75, 0.001));
      // 0.75L * R20.30 = R15.225
      expect(result.fuelCostRands, closeTo(15.225, 0.001));
      expect(result.totalTripCost, result.fuelCostRands);
    });

    test('zero distance returns zero cost', () {
      final result = service.calculateTripCost(
        distanceKm: 0,
        consumptionPer100km: 7.5,
        fuelPricePerLitre: 20.30,
      );

      expect(result.roundTripKm, 0);
      expect(result.fuelUsedLitres, 0);
      expect(result.fuelCostRands, 0);
    });

    test('small car preset (5.8 L/100km)', () {
      final result = service.calculateTripCost(
        distanceKm: 3.2,
        consumptionPer100km: VehicleConfig.defaultConsumption[VehicleType.small]!,
        fuelPricePerLitre: 19.47,
      );

      // Round trip: 6.4km
      expect(result.roundTripKm, closeTo(6.4, 0.001));
      // Fuel: 6.4 * 5.8/100 = 0.3712L
      expect(result.fuelUsedLitres, closeTo(0.3712, 0.001));
      // Cost: 0.3712 * 19.47 = R7.22
      expect(result.fuelCostRands, closeTo(7.225, 0.01));
    });

    test('large SUV preset (9.8 L/100km)', () {
      final result = service.calculateTripCost(
        distanceKm: 15.0,
        consumptionPer100km: VehicleConfig.defaultConsumption[VehicleType.large]!,
        fuelPricePerLitre: 20.30,
      );

      // Round trip: 30km
      expect(result.roundTripKm, 30.0);
      // Fuel: 30 * 9.8/100 = 2.94L
      expect(result.fuelUsedLitres, closeTo(2.94, 0.001));
      // Cost: 2.94 * 20.30 = R59.682
      expect(result.fuelCostRands, closeTo(59.682, 0.01));
    });

    test('diesel pricing (cheaper per litre)', () {
      final result = service.calculateTripCost(
        distanceKm: 10.0,
        consumptionPer100km: 7.5,
        fuelPricePerLitre: 17.84, // diesel 50ppm coastal
      );

      // Round trip: 20km, Fuel: 1.5L, Cost: 1.5 * 17.84 = R26.76
      expect(result.fuelUsedLitres, closeTo(1.5, 0.001));
      expect(result.fuelCostRands, closeTo(26.76, 0.01));
    });

    test('very short trip (0.5km)', () {
      final result = service.calculateTripCost(
        distanceKm: 0.5,
        consumptionPer100km: 7.5,
        fuelPricePerLitre: 20.30,
      );

      // Round trip: 1km, Fuel: 0.075L, Cost: R1.52
      expect(result.fuelCostRands, closeTo(1.5225, 0.01));
    });

    test('long trip (50km)', () {
      final result = service.calculateTripCost(
        distanceKm: 50.0,
        consumptionPer100km: 7.5,
        fuelPricePerLitre: 20.30,
      );

      // Round trip: 100km, Fuel: 7.5L, Cost: R152.25
      expect(result.fuelUsedLitres, closeTo(7.5, 0.001));
      expect(result.fuelCostRands, closeTo(152.25, 0.01));
    });
  });

  group('VehicleConfig', () {
    test('JSON serialization round-trip', () {
      const config = VehicleConfig(
        type: VehicleType.medium,
        consumptionPer100km: 7.5,
        label: 'Medium Car',
        fuelType: 'petrol_95',
        region: 'inland',
      );

      final json = config.toJson();
      final restored = VehicleConfig.fromJson(json);

      expect(restored.type, config.type);
      expect(restored.consumptionPer100km, config.consumptionPer100km);
      expect(restored.label, config.label);
      expect(restored.fuelType, config.fuelType);
      expect(restored.region, config.region);
    });

    test('fromJson handles missing fields gracefully', () {
      final config = VehicleConfig.fromJson({});

      expect(config.type, VehicleType.medium);
      expect(config.consumptionPer100km, 7.5);
      expect(config.fuelType, 'petrol_95');
      expect(config.region, 'inland');
    });

    test('copyWith preserves unchanged fields', () {
      const original = VehicleConfig(
        type: VehicleType.small,
        consumptionPer100km: 5.8,
        label: 'Small Car',
        fuelType: 'petrol_93',
        region: 'coastal',
      );

      final updated = original.copyWith(region: 'inland');

      expect(updated.type, VehicleType.small);
      expect(updated.consumptionPer100km, 5.8);
      expect(updated.fuelType, 'petrol_93');
      expect(updated.region, 'inland');
    });

    test('default consumption values', () {
      expect(VehicleConfig.defaultConsumption[VehicleType.small], 5.8);
      expect(VehicleConfig.defaultConsumption[VehicleType.medium], 7.5);
      expect(VehicleConfig.defaultConsumption[VehicleType.large], 9.8);
    });

    test('fuel type labels', () {
      expect(VehicleConfig.fuelTypeLabels['petrol_93'], 'Petrol 93');
      expect(VehicleConfig.fuelTypeLabels['diesel_50ppm'], 'Diesel 50ppm');
    });
  });

  group('DeliveryFeeConfig', () {
    test('Checkers Sixty60 has no free delivery threshold', () {
      final checkers = DeliveryFeeConfig.fees['Checkers']!;
      expect(checkers.appName, 'Sixty60');
      expect(checkers.fee, 36.0);
      expect(checkers.freeAbove, isNull);
    });

    test('PnP asap has free delivery above R400', () {
      final pnp = DeliveryFeeConfig.fees['Pick n Pay']!;
      expect(pnp.appName, 'asap!');
      expect(pnp.fee, 35.0);
      expect(pnp.freeAbove, 400.0);
    });

    test('Woolworths Dash has free delivery above R350', () {
      final woolies = DeliveryFeeConfig.fees['Woolworths']!;
      expect(woolies.appName, 'Dash');
      expect(woolies.fee, 45.0);
      expect(woolies.freeAbove, 350.0);
    });

    test('no delivery config for Shoprite', () {
      expect(DeliveryFeeConfig.fees['Shoprite'], isNull);
    });

    test('no delivery config for Makro', () {
      expect(DeliveryFeeConfig.fees['Makro'], isNull);
    });
  });
}
