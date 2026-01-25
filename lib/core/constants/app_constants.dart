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
  static const String keySelectedProvince = 'selected_province';

  // Timeouts
  static const Duration apiTimeout = Duration(seconds: 30);
  static const Duration realtimeTimeout = Duration(seconds: 5);

  // Retailers (South African stores)
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
  // PROVINCES
  // ==========================================================================

  /// Default province (used when none selected)
  static const String defaultProvince = 'Gauteng';

  /// All 9 South African provinces
  static const List<String> allProvinces = [
    'Gauteng',
    'Western Cape',
    'KwaZulu-Natal',
    'Eastern Cape',
    'Free State',
    'North West',
    'Mpumalanga',
    'Limpopo',
    'Northern Cape',
  ];

  /// Provinces with data currently available
  /// Update this list as more provinces are scraped
  static const List<String> availableProvinces = ['Gauteng'];

  /// Provinces coming soon (no data yet)
  static const List<String> comingSoonProvinces = [
    'Western Cape',
    'KwaZulu-Natal',
    'Eastern Cape',
    'Free State',
    'North West',
    'Mpumalanga',
    'Limpopo',
    'Northern Cape',
  ];

  /// Check if a province has data available
  static bool isProvinceAvailable(String province) {
    return availableProvinces.contains(province);
  }

  /// Get province display info (for UI)
  static ProvinceInfo getProvinceInfo(String province) {
    return ProvinceInfo(
      name: province,
      isAvailable: isProvinceAvailable(province),
      icon: _getProvinceIcon(province),
    );
  }

  /// Get an icon for each province (optional, for visual variety)
  static String _getProvinceIcon(String province) {
    // You can customize these or use a map marker for all
    return switch (province) {
      'Gauteng' => '🏙️',
      'Western Cape' => '🏔️',
      'KwaZulu-Natal' => '🌊',
      'Eastern Cape' => '🌿',
      'Free State' => '🌾',
      'North West' => '⛏️',
      'Mpumalanga' => '🌅',
      'Limpopo' => '🦁',
      'Northern Cape' => '🌵',
      _ => '📍',
    };
  }

  // ==========================================================================
  // ERROR MESSAGES
  // ==========================================================================

  static const String errorGeneric = 'Something went wrong. Please try again.';
  static const String errorNetwork =
      'No internet connection. Please check your network.';
  static const String errorAuth = 'Authentication failed. Please try again.';
  static const String errorNotFound = 'Item not found.';
  static const String errorProvinceUnavailable =
      'Data for this province is coming soon!';

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

/// Province information for UI display
class ProvinceInfo {
  final String name;
  final bool isAvailable;
  final String icon;

  const ProvinceInfo({
    required this.name,
    required this.isAvailable,
    required this.icon,
  });
}
