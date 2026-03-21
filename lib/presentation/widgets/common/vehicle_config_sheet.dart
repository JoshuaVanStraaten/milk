// lib/presentation/widgets/common/vehicle_config_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/vehicle_config.dart';
import '../../providers/vehicle_config_provider.dart';

/// Bottom sheet for configuring the user's vehicle for fuel cost calculations.
///
/// Usage: call [showVehicleConfigSheet] to display.
void showVehicleConfigSheet(BuildContext context, {required bool isDark}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: isDark ? AppColors.backgroundDark : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _VehicleConfigSheet(isDark: isDark),
  );
}

class _VehicleConfigSheet extends ConsumerStatefulWidget {
  final bool isDark;
  const _VehicleConfigSheet({required this.isDark});

  @override
  ConsumerState<_VehicleConfigSheet> createState() =>
      _VehicleConfigSheetState();
}

class _VehicleConfigSheetState extends ConsumerState<_VehicleConfigSheet> {
  late VehicleType _selectedType;
  late double _consumption;
  late String _fuelType;
  late String _region;

  @override
  void initState() {
    super.initState();
    final existing = ref.read(vehicleConfigProvider);
    _selectedType = existing?.type ?? VehicleType.medium;
    _consumption = existing?.consumptionPer100km ??
        VehicleConfig.defaultConsumption[_selectedType] ??
        7.5;
    _fuelType = existing?.fuelType ?? 'petrol_95';
    _region = existing?.region ?? 'inland';
  }

  void _onTypeSelected(VehicleType type) {
    setState(() {
      _selectedType = type;
      if (type != VehicleType.custom) {
        _consumption = VehicleConfig.defaultConsumption[type] ?? 7.5;
      }
    });
  }

  void _save() {
    final config = VehicleConfig(
      type: _selectedType,
      consumptionPer100km: _consumption,
      label: VehicleConfig.defaultLabels[_selectedType] ?? 'Custom',
      fuelType: _fuelType,
      region: _region,
    );
    ref.read(vehicleConfigProvider.notifier).setVehicle(config);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.dividerDark : AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header with Lottie car animation
            Row(
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: Lottie.asset(
                    'assets/animations/car_driving.json',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.directions_car_outlined,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'My Vehicle',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Vehicle type selector
            _label('Vehicle Type', isDark),
            const SizedBox(height: 8),
            Row(
              children: [
                _vehicleTypeCard(VehicleType.small, Icons.directions_car,
                    'Small', '~5.8 L/100km', isDark),
                const SizedBox(width: 8),
                _vehicleTypeCard(VehicleType.medium, Icons.directions_car_filled,
                    'Medium', '~7.5 L/100km', isDark),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _vehicleTypeCard(VehicleType.large, Icons.local_shipping_outlined,
                    'Large / SUV', '~9.8 L/100km', isDark),
                const SizedBox(width: 8),
                _vehicleTypeCard(VehicleType.custom, Icons.tune,
                    'Custom', 'Set your own', isDark),
              ],
            ),

            // Custom consumption slider
            if (_selectedType == VehicleType.custom) ...[
              const SizedBox(height: 16),
              _label(
                  'Fuel Consumption: ${_consumption.toStringAsFixed(1)} L/100km',
                  isDark),
              Slider(
                value: _consumption,
                min: 3.0,
                max: 20.0,
                divisions: 170,
                activeColor: AppColors.primary,
                label: '${_consumption.toStringAsFixed(1)} L/100km',
                onChanged: (v) => setState(() => _consumption = v),
              ),
            ],

            const SizedBox(height: 16),

            // Fuel type dropdown
            _label('Fuel Type', isDark),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? AppColors.dividerDark : AppColors.divider,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _fuelType,
                  isExpanded: true,
                  dropdownColor:
                      isDark ? AppColors.surfaceDarkMode : Colors.white,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                  ),
                  items: VehicleConfig.fuelTypeLabels.entries
                      .map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _fuelType = v);
                  },
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Region selector
            _label('Region', isDark),
            const SizedBox(height: 8),
            Row(
              children: [
                _regionChip('coastal', 'Coastal', isDark),
                const SizedBox(width: 8),
                _regionChip('inland', 'Inland', isDark),
              ],
            ),

            const SizedBox(height: 8),
            Text(
              'Fuel prices differ between coastal and inland regions.',
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),

            const SizedBox(height: 8),
            Text(
              "Not sure about consumption? Check your car's dashboard display. "
              'City driving is usually 6\u201310 L/100km.',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),

            const SizedBox(height: 20),

            // Save button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Save Vehicle',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text, bool isDark) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
      ),
    );
  }

  Widget _vehicleTypeCard(
    VehicleType type,
    IconData icon,
    String label,
    String subtitle,
    bool isDark,
  ) {
    final isSelected = _selectedType == type;
    return Expanded(
      child: InkWell(
        onTap: () => _onTypeSelected(type),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.1)
                : (isDark ? AppColors.surfaceDarkMode : AppColors.surface),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : (isDark ? AppColors.dividerDark : AppColors.divider),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? AppColors.primary
                    : (isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary),
                size: 28,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? AppColors.primary
                      : (isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              if (isSelected) ...[
                const SizedBox(height: 4),
                const Icon(Icons.check_circle, color: AppColors.primary, size: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _regionChip(String value, String label, bool isDark) {
    final isSelected = _region == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _region = value),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : (isDark ? AppColors.dividerDark : AppColors.divider),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected
                  ? AppColors.primary
                  : (isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
