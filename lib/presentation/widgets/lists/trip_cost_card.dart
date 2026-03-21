// lib/presentation/widgets/lists/trip_cost_card.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/list_item.dart';
import '../../../data/models/vehicle_config.dart';
import '../../../data/services/fuel_cost_service.dart';
import '../../../data/services/fuel_price_service.dart';
import '../../providers/fuel_price_provider.dart';
import '../../providers/store_provider.dart';
import '../../providers/vehicle_config_provider.dart';
import '../common/vehicle_config_sheet.dart';

/// Collapsible card showing trip cost breakdown on a shopping list.
///
/// Shows product totals + fuel cost per retailer, delivery comparison,
/// and a grand total (products + fuel).
class TripCostCard extends ConsumerStatefulWidget {
  final List<ListItem> items;
  final bool isDark;

  const TripCostCard({super.key, required this.items, required this.isDark});

  @override
  ConsumerState<TripCostCard> createState() => _TripCostCardState();
}

class _TripCostCardState extends ConsumerState<TripCostCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final vehicle = ref.watch(vehicleConfigProvider);
    final isDark = widget.isDark;

    if (vehicle == null) {
      return _buildSetupPrompt(isDark);
    }

    final fuelPricesAsync = ref.watch(fuelPricesProvider);

    return fuelPricesAsync.when(
      data: (fuelData) => _buildCard(vehicle, fuelData, isDark),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildSetupPrompt(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.3),
        ),
      ),
      child: InkWell(
        onTap: () => showVehicleConfigSheet(context, isDark: isDark),
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: Lottie.asset(
                'assets/animations/car_question.json',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.local_gas_station_outlined,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Set up your vehicle to see trip costs',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(
      VehicleConfig vehicle, FuelPriceData fuelData, bool isDark) {
    final fuelPrice =
        fuelData.getPrice(vehicle.fuelType, vehicle.region) ?? 20.0;
    final storeAsync = ref.watch(storeSelectionProvider);
    final fuelService = FuelCostService();

    // Group items by retailer
    final retailerTotals = <String, double>{};
    for (final item in widget.items) {
      final retailer = item.itemRetailer;
      if (retailer != null && retailer.isNotEmpty) {
        retailerTotals[retailer] =
            (retailerTotals[retailer] ?? 0) + item.itemTotalPrice;
      }
    }

    if (retailerTotals.isEmpty) return const SizedBox.shrink();

    // Calculate fuel cost per retailer
    final retailerFuel = <String, FuelCostBreakdown>{};
    double totalFuelCost = 0;
    double totalProducts = 0;

    storeAsync.whenData((selection) {
      for (final entry in retailerTotals.entries) {
        totalProducts += entry.value;
        final store = selection.forRetailer(entry.key);
        if (store != null) {
          final breakdown = fuelService.calculateTripCost(
            distanceKm: store.distanceKm,
            consumptionPer100km: vehicle.consumptionPer100km,
            fuelPricePerLitre: fuelPrice,
          );
          retailerFuel[entry.key] = breakdown;
          totalFuelCost += breakdown.fuelCostRands;
        }
      }
    });

    if (totalProducts == 0) return const SizedBox.shrink();

    final grandTotal = totalProducts + totalFuelCost;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          // Collapsed header — always visible
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Lottie.asset(
                      'assets/animations/fuel_pump.json',
                      fit: BoxFit.contain,
                      repeat: false,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.local_gas_station,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Trip Cost',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'R${grandTotal.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more,
                      size: 20,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expanded breakdown
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: _buildExpandedContent(
              vehicle,
              fuelPrice,
              retailerTotals,
              retailerFuel,
              totalProducts,
              totalFuelCost,
              grandTotal,
              isDark,
            ),
            crossFadeState:
                _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedContent(
    VehicleConfig vehicle,
    double fuelPrice,
    Map<String, double> retailerTotals,
    Map<String, FuelCostBreakdown> retailerFuel,
    double totalProducts,
    double totalFuelCost,
    double grandTotal,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(
            color: isDark ? AppColors.dividerDark : AppColors.divider,
            height: 1,
          ),
          const SizedBox(height: 12),

          // Products subtotal
          _row('Products', 'R${totalProducts.toStringAsFixed(2)}', isDark,
              bold: true),
          const SizedBox(height: 6),

          // Per-retailer product + fuel breakdown
          ...retailerTotals.entries.map((entry) {
            final fuel = retailerFuel[entry.key];
            final distanceText = fuel != null
                ? ' (${fuel.distanceKm.toStringAsFixed(1)}km)'
                : '';
            final fuelText = fuel != null
                ? 'R${fuel.fuelCostRands.toStringAsFixed(2)}'
                : '—';

            return Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 4),
              child: Column(
                children: [
                  _row(
                    entry.key,
                    'R${entry.value.toStringAsFixed(2)}',
                    isDark,
                    fontSize: 12,
                    secondary: true,
                  ),
                  if (fuel != null)
                    _row(
                      '  Fuel$distanceText',
                      fuelText,
                      isDark,
                      fontSize: 12,
                      secondary: true,
                    ),
                ],
              ),
            );
          }),

          const SizedBox(height: 4),

          // Fuel subtotal
          _row(
            'Fuel (${retailerFuel.length} store${retailerFuel.length != 1 ? 's' : ''})',
            'R${totalFuelCost.toStringAsFixed(2)}',
            isDark,
            bold: true,
          ),

          const SizedBox(height: 8),
          Divider(
            color: isDark ? AppColors.dividerDark : AppColors.divider,
            height: 1,
          ),
          const SizedBox(height: 8),

          // Grand total
          _row('Total', 'R${grandTotal.toStringAsFixed(2)}', isDark,
              bold: true, highlight: true),

          const SizedBox(height: 10),

          // Delivery comparison
          _buildDeliveryComparison(
              retailerTotals, retailerFuel, isDark),

          const SizedBox(height: 8),

          // Vehicle info footer
          InkWell(
            onTap: () => showVehicleConfigSheet(context, isDark: isDark),
            child: Row(
              children: [
                Icon(Icons.directions_car, size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${vehicle.label} · ${vehicle.consumptionPer100km.toStringAsFixed(1)} L/100km · '
                    '${vehicle.fuelTypeLabel} ${vehicle.regionLabel} · '
                    'R${fuelPrice.toStringAsFixed(2)}/L',
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
                Text(
                  'Change',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryComparison(
    Map<String, double> retailerTotals,
    Map<String, FuelCostBreakdown> retailerFuel,
    bool isDark,
  ) {
    final deliveryRows = <Widget>[];

    for (final entry in retailerTotals.entries) {
      final deliveryConfig = DeliveryFeeConfig.fees[entry.key];
      if (deliveryConfig == null) continue;

      final fuelBreakdown = retailerFuel[entry.key];
      if (fuelBreakdown == null) continue;

      final cartTotal = entry.value;
      final deliveryFee = (deliveryConfig.freeAbove != null &&
              cartTotal >= deliveryConfig.freeAbove!)
          ? 0.0
          : deliveryConfig.fee;

      final fuelCost = fuelBreakdown.fuelCostRands;
      final savings = deliveryFee - fuelCost;
      final drivingCheaper = savings > 0;

      final feeText = deliveryFee == 0
          ? 'FREE'
          : 'R${deliveryFee.toStringAsFixed(0)}';

      final verdictText = deliveryFee == 0
          ? 'Free delivery beats driving by R${fuelCost.toStringAsFixed(0)}'
          : drivingCheaper
              ? 'Driving saves R${savings.toStringAsFixed(0)} vs ${deliveryConfig.appName}'
              : 'Save R${savings.abs().toStringAsFixed(0)} with ${deliveryConfig.appName}';

      final verdictColor = (deliveryFee == 0 || !drivingCheaper)
          ? AppColors.error
          : AppColors.success;

      deliveryRows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Icon(Icons.delivery_dining, size: 14, color: verdictColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${deliveryConfig.appName} ($feeText) · ',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondary,
                        ),
                      ),
                      TextSpan(
                        text: verdictText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: verdictColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (deliveryRows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'vs Delivery',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        ...deliveryRows,
      ],
    );
  }

  Widget _row(
    String label,
    String value,
    bool isDark, {
    bool bold = false,
    bool highlight = false,
    bool secondary = false,
    double fontSize = 13,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
            color: secondary
                ? (isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary)
                : (isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
            color: highlight
                ? AppColors.primary
                : secondary
                    ? (isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary)
                    : (isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary),
          ),
        ),
      ],
    );
  }
}
