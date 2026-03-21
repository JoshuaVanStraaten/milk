// lib/presentation/providers/vehicle_config_provider.dart

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/vehicle_config.dart';

const _kVehicleConfigKey = 'vehicle_config_json';

/// Manages the user's vehicle configuration for fuel cost calculations.
/// Persists to SharedPreferences. Null state = no vehicle configured.
class VehicleConfigNotifier extends StateNotifier<VehicleConfig?> {
  VehicleConfigNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kVehicleConfigKey);
      if (raw == null) return;
      state = VehicleConfig.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      state = null;
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (state == null) {
      await prefs.remove(_kVehicleConfigKey);
    } else {
      await prefs.setString(
        _kVehicleConfigKey,
        jsonEncode(state!.toJson()),
      );
    }
  }

  Future<void> setVehicle(VehicleConfig config) async {
    state = config;
    await _persist();
  }

  Future<void> clearVehicle() async {
    state = null;
    await _persist();
  }
}

/// The user's vehicle config. Null if not configured.
final vehicleConfigProvider =
    StateNotifierProvider<VehicleConfigNotifier, VehicleConfig?>(
  (_) => VehicleConfigNotifier(),
);
