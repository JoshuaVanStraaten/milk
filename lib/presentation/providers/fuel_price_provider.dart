// lib/presentation/providers/fuel_price_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/fuel_price_service.dart';

/// Singleton FuelPriceService instance.
final fuelPriceServiceProvider = Provider<FuelPriceService>(
  (_) => FuelPriceService(),
);

/// Fuel prices fetched from the Edge Function (cached 7 days).
/// Widgets should watch this provider to get current SA fuel prices.
final fuelPricesProvider = FutureProvider<FuelPriceData>((ref) async {
  final service = ref.read(fuelPriceServiceProvider);
  return service.fetchPrices();
});
