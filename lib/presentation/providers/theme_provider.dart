import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Theme mode options
enum AppThemeMode {
  system, // Follow system setting
  light, // Always light
  dark, // Always dark
}

/// Key for storing theme preference
const String _themePreferenceKey = 'theme_mode';

/// Provider for SharedPreferences instance
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'SharedPreferences must be initialized in main.dart',
  );
});

/// Theme state
class ThemeState {
  final AppThemeMode themeMode;
  final ThemeMode flutterThemeMode;

  const ThemeState({required this.themeMode, required this.flutterThemeMode});

  /// Default state (system theme)
  factory ThemeState.initial() {
    return const ThemeState(
      themeMode: AppThemeMode.system,
      flutterThemeMode: ThemeMode.system,
    );
  }

  ThemeState copyWith({AppThemeMode? themeMode, ThemeMode? flutterThemeMode}) {
    return ThemeState(
      themeMode: themeMode ?? this.themeMode,
      flutterThemeMode: flutterThemeMode ?? this.flutterThemeMode,
    );
  }

  /// Check if dark mode is currently active
  bool isDarkMode(BuildContext context) {
    if (themeMode == AppThemeMode.dark) return true;
    if (themeMode == AppThemeMode.light) return false;
    // System mode - check platform brightness
    return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
  }
}

/// Theme notifier for managing theme state
class ThemeNotifier extends StateNotifier<ThemeState> {
  final SharedPreferences _prefs;

  ThemeNotifier(this._prefs) : super(ThemeState.initial()) {
    _loadThemePreference();
  }

  /// Load saved theme preference from storage
  void _loadThemePreference() {
    final savedTheme = _prefs.getString(_themePreferenceKey);

    if (savedTheme != null) {
      final themeMode = AppThemeMode.values.firstWhere(
        (e) => e.name == savedTheme,
        orElse: () => AppThemeMode.system,
      );
      _setThemeMode(themeMode);
    }
  }

  /// Set theme mode and persist preference
  Future<void> setThemeMode(AppThemeMode mode) async {
    _setThemeMode(mode);
    await _prefs.setString(_themePreferenceKey, mode.name);
  }

  /// Internal method to update state
  void _setThemeMode(AppThemeMode mode) {
    final flutterMode = switch (mode) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
    };

    state = state.copyWith(themeMode: mode, flutterThemeMode: flutterMode);
  }

  /// Toggle between light and dark (skips system)
  Future<void> toggleTheme() async {
    final newMode = state.themeMode == AppThemeMode.dark
        ? AppThemeMode.light
        : AppThemeMode.dark;
    await setThemeMode(newMode);
  }

  /// Cycle through all theme modes: system → light → dark → system
  Future<void> cycleThemeMode() async {
    final newMode = switch (state.themeMode) {
      AppThemeMode.system => AppThemeMode.light,
      AppThemeMode.light => AppThemeMode.dark,
      AppThemeMode.dark => AppThemeMode.system,
    };
    await setThemeMode(newMode);
  }
}

/// Provider for theme state
final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ThemeNotifier(prefs);
});

/// Convenience provider for current ThemeMode (for MaterialApp)
final themeModeProvider = Provider<ThemeMode>((ref) {
  return ref.watch(themeProvider).flutterThemeMode;
});

/// Convenience provider for checking if dark mode
final isDarkModeProvider = Provider.family<bool, BuildContext>((ref, context) {
  return ref.watch(themeProvider).isDarkMode(context);
});
