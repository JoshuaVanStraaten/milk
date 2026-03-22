// lib/presentation/providers/vehicle_config_provider.dart

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/vehicle_config.dart';

const _kVehicleConfigPrefix = 'vehicle_config_';

/// Manages the user's vehicle configuration for fuel cost calculations.
/// Persists to SharedPreferences, scoped per user ID.
class VehicleConfigNotifier extends StateNotifier<VehicleConfig?> {
  VehicleConfigNotifier() : super(null) {
    _load();
  }

  String get _storageKey {
    final uid = Supabase.instance.client.auth.currentUser?.id ?? 'anonymous';
    return '$_kVehicleConfigPrefix$uid';
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
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
      await prefs.remove(_storageKey);
    } else {
      await prefs.setString(
        _storageKey,
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

  /// Reload config for the current user (call after login/logout).
  Future<void> reload() async {
    state = null;
    await _load();
  }
}

/// The user's vehicle config. Null if not configured.
final vehicleConfigProvider =
    StateNotifierProvider<VehicleConfigNotifier, VehicleConfig?>(
  (_) => VehicleConfigNotifier(),
);
