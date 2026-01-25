import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';
import 'theme_provider.dart'; // For sharedPreferencesProvider

/// Province state
class ProvinceState {
  final String selectedProvince;
  final bool isAvailable;
  final bool hasCompletedOnboarding;

  const ProvinceState({
    required this.selectedProvince,
    required this.isAvailable,
    required this.hasCompletedOnboarding,
  });

  /// Default state
  factory ProvinceState.initial() {
    return ProvinceState(
      selectedProvince: AppConstants.defaultProvince,
      isAvailable: AppConstants.isProvinceAvailable(
        AppConstants.defaultProvince,
      ),
      hasCompletedOnboarding: false,
    );
  }

  ProvinceState copyWith({
    String? selectedProvince,
    bool? isAvailable,
    bool? hasCompletedOnboarding,
  }) {
    return ProvinceState(
      selectedProvince: selectedProvince ?? this.selectedProvince,
      isAvailable: isAvailable ?? this.isAvailable,
      hasCompletedOnboarding:
          hasCompletedOnboarding ?? this.hasCompletedOnboarding,
    );
  }
}

/// Province notifier for managing province selection state
class ProvinceNotifier extends StateNotifier<ProvinceState> {
  final SharedPreferences _prefs;

  ProvinceNotifier(this._prefs) : super(ProvinceState.initial()) {
    _loadSavedProvince();
  }

  /// Load saved province preference from storage
  void _loadSavedProvince() {
    final savedProvince = _prefs.getString(AppConstants.keySelectedProvince);
    final hasCompletedOnboarding =
        _prefs.getBool(AppConstants.keyOnboardingComplete) ?? false;

    if (savedProvince != null &&
        AppConstants.allProvinces.contains(savedProvince)) {
      state = state.copyWith(
        selectedProvince: savedProvince,
        isAvailable: AppConstants.isProvinceAvailable(savedProvince),
        hasCompletedOnboarding: hasCompletedOnboarding,
      );
    } else {
      state = state.copyWith(hasCompletedOnboarding: hasCompletedOnboarding);
    }
  }

  /// Set selected province and persist preference
  /// Returns true if province is available, false if it's coming soon
  Future<bool> setProvince(String province) async {
    if (!AppConstants.allProvinces.contains(province)) {
      return false;
    }

    final isAvailable = AppConstants.isProvinceAvailable(province);

    // Only save if the province is available
    if (isAvailable) {
      await _prefs.setString(AppConstants.keySelectedProvince, province);
      state = state.copyWith(
        selectedProvince: province,
        isAvailable: isAvailable,
      );
    }

    return isAvailable;
  }

  /// Complete the onboarding flow
  Future<void> completeOnboarding() async {
    await _prefs.setBool(AppConstants.keyOnboardingComplete, true);
    state = state.copyWith(hasCompletedOnboarding: true);
  }

  /// Check if user needs to see onboarding
  bool get needsOnboarding => !state.hasCompletedOnboarding;

  /// Get all provinces with their availability info
  List<ProvinceInfo> get allProvincesInfo {
    return AppConstants.allProvinces
        .map((p) => AppConstants.getProvinceInfo(p))
        .toList();
  }

  /// Get only available provinces
  List<String> get availableProvinces => AppConstants.availableProvinces;

  /// Get coming soon provinces
  List<String> get comingSoonProvinces => AppConstants.comingSoonProvinces;
}

/// Provider for province state
final provinceProvider = StateNotifierProvider<ProvinceNotifier, ProvinceState>(
  (ref) {
    final prefs = ref.watch(sharedPreferencesProvider);
    return ProvinceNotifier(prefs);
  },
);

/// Convenience provider for selected province string
/// Use this when you just need the province name for queries
final selectedProvinceProvider = Provider<String>((ref) {
  return ref.watch(provinceProvider).selectedProvince;
});

/// Convenience provider for checking if selected province has data
final isProvinceAvailableProvider = Provider<bool>((ref) {
  return ref.watch(provinceProvider).isAvailable;
});

/// Convenience provider for checking if onboarding is needed
final needsOnboardingProvider = Provider<bool>((ref) {
  return !ref.watch(provinceProvider).hasCompletedOnboarding;
});

/// Provider for all provinces with info (for UI lists)
final allProvincesInfoProvider = Provider<List<ProvinceInfo>>((ref) {
  return AppConstants.allProvinces
      .map((p) => AppConstants.getProvinceInfo(p))
      .toList();
});
