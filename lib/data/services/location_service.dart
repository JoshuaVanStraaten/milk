// lib/data/services/location_service.dart

import 'dart:async';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:logger/logger.dart';

/// Handles GPS location permission requests and position retrieval.
///
/// Used during onboarding (store selection) and when the user wants
/// to refresh their nearby stores. Wraps the `geolocator` package
/// with proper error handling and timeout logic.
///
/// Usage:
/// ```dart
/// final locationService = LocationService();
/// final position = await locationService.getCurrentPosition();
/// if (position != null) {
///   // Use position.latitude, position.longitude
/// }
/// ```
class LocationService {
  final Logger _logger = Logger();

  /// Request timeout for fresh GPS fix.
  static const Duration _timeout = Duration(seconds: 30);

  // ── DEBUG OVERRIDE ──────────────────────────────────────────────
  // Set to true + your coords to skip GPS on emulator.
  // REMEMBER: set back to false before releasing!
  static const bool _useDebugLocation = false;
  static const double _debugLat = -26.2041; // Johannesburg
  static const double _debugLng = 28.0473;
  // ───────────────────────────────────────────────────────────s─────

  /// Get the user's current GPS position.
  ///
  /// Handles the full permission flow:
  /// 1. Check if location services are enabled
  /// 2. Check/request permission
  /// 3. Try last known position first (instant, usually available)
  /// 4. Fall back to fresh GPS fix with timeout
  ///
  /// Returns `null` if:
  /// - Location services are disabled on the device
  /// - User denies the permission prompt
  ///
  /// Throws [LocationPermissionDeniedException] if permission is
  /// permanently denied (user must go to Settings to re-enable).
  ///
  /// Throws [LocationTimeoutException] if the GPS fix takes too long
  /// and no last known position is available.
  Future<Position?> getCurrentPosition() async {
    // Debug override — skip GPS entirely
    if (_useDebugLocation) {
      _logger.w('⚠️ Using DEBUG location: ($_debugLat, $_debugLng)');
      return Position(
        latitude: _debugLat,
        longitude: _debugLng,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
    }

    // 1. Check if location services are enabled on the device
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _logger.w('Location services are disabled');
      return null;
    }

    // 2. Check current permission status
    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      // First time or previously denied (not permanently) — request it
      _logger.d('Requesting location permission...');
      permission = await Geolocator.requestPermission();

      if (permission == LocationPermission.denied) {
        _logger.w('Location permission denied by user');
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _logger.w('Location permission permanently denied');
      throw LocationPermissionDeniedException();
    }

    // 3. Try last known position first (instant — no GPS needed)
    try {
      _logger.d('Checking last known position...');
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        _logger.i(
          'Using last known position: (${lastKnown.latitude.toStringAsFixed(4)}, '
          '${lastKnown.longitude.toStringAsFixed(4)})',
        );
        return lastKnown;
      }
      _logger.d('No last known position, requesting fresh fix...');
    } catch (e) {
      _logger.w('getLastKnownPosition failed: $e');
    }

    // 4. Fresh GPS fix with low accuracy (faster) and generous timeout.
    //    Low accuracy is fine for store finding — we just need city-level.
    try {
      _logger.d('Getting current position (low accuracy)...');
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      ).timeout(_timeout, onTimeout: () => throw LocationTimeoutException());

      _logger.i(
        'Got position: (${position.latitude.toStringAsFixed(4)}, '
        '${position.longitude.toStringAsFixed(4)})',
      );
      return position;
    } on LocationTimeoutException {
      rethrow;
    } catch (e) {
      _logger.e('Failed to get position: $e');
      rethrow;
    }
  }

  /// Geocode a human-readable address string to lat/lng coordinates.
  ///
  /// Returns a record `({double lat, double lng})` on success, or `null`
  /// if the address could not be resolved (not found, network error, etc.).
  Future<({double lat, double lng})?> geocodeAddress(String address) async {
    try {
      final locations = await locationFromAddress(address);
      if (locations.isEmpty) return null;
      final first = locations.first;
      _logger.i(
        'Geocoded "$address" → (${first.latitude.toStringAsFixed(4)}, '
        '${first.longitude.toStringAsFixed(4)})',
      );
      return (lat: first.latitude, lng: first.longitude);
    } on NoResultFoundException {
      _logger.w('No geocoding result for: "$address"');
      return null;
    } catch (e) {
      _logger.e('Geocoding failed for "$address": $e');
      return null;
    }
  }

  /// Open the device's location settings page.
  /// Useful when location services are disabled.
  Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }

  /// Open the app's permission settings page.
  /// Useful when permission is permanently denied.
  Future<bool> openAppSettings() async {
    return await Geolocator.openAppSettings();
  }
}

/// Thrown when the user has permanently denied location permission.
/// The app should show a message directing them to Settings.
class LocationPermissionDeniedException implements Exception {
  @override
  String toString() =>
      'Location permission permanently denied. Please enable in Settings.';
}

/// Thrown when the GPS position request times out.
/// Common on emulators or in areas with poor GPS signal.
class LocationTimeoutException implements Exception {
  @override
  String toString() =>
      'Location request timed out. Please try again or check GPS signal.';
}
