// lib/core/constants/app_constants.dart
//
// CLEANED: Province code removed. Retailer constants kept for backward
// compatibility but new code should use Retailers.all from retailers.dart.

/// App-wide constants
class AppConstants {
  // App Info
  static const String appName = 'Milk';
  static const String appVersion = '1.0.0';

  // Pagination
  static const int productsPerPage = 20;
  static const int listsPerPage = 10;

  // Storage Keys (for SharedPreferences)
  static const String keyOnboardingComplete = 'onboarding_complete';
  static const String keyThemeMode = 'theme_mode';

  // Timeouts
  static const Duration apiTimeout = Duration(seconds: 30);
  static const Duration realtimeTimeout = Duration(seconds: 5);

  // Retailers (South African stores)
  // NOTE: Prefer Retailers.all from retailers.dart for new code.
  // These are kept for backward compatibility with existing screens.
  static const String pickNPay = 'Pick n Pay';
  static const String woolworths = 'Woolworths';
  static const String shoprite = 'Shoprite';
  static const String checkers = 'Checkers';

  static const List<String> retailers = [
    pickNPay,
    woolworths,
    shoprite,
    checkers,
  ];

  // ==========================================================================
  // ERROR MESSAGES
  // ==========================================================================

  static const String errorGeneric = 'Something went wrong. Please try again.';
  static const String errorNetwork =
      'No internet connection. Please check your network.';
  static const String errorAuth = 'Authentication failed. Please try again.';
  static const String errorNotFound = 'Item not found.';

  // ==========================================================================
  // LIST COLORS
  // ==========================================================================

  static const Map<String, int> listColors = {
    'Red': 0xFFEF4444,
    'Orange': 0xFFF97316,
    'Amber': 0xFFF59E0B,
    'Green': 0xFF10B981,
    'Teal': 0xFF14B8A6,
    'Blue': 0xFF3B82F6,
    'Indigo': 0xFF6366F1,
    'Purple': 0xFFA855F7,
    'Pink': 0xFFEC4899,
  };

  // Private constructor to prevent instantiation
  AppConstants._();
}
