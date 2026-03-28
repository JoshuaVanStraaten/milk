import 'package:flutter/material.dart';

/// App-wide color palette
/// Following the emerald green theme for a fresh, grocery-focused aesthetic
/// Supports both light and dark modes
class AppColors {
  // ============================================
  // LIGHT MODE COLORS
  // ============================================

  // Primary Colors
  static const Color primary = Color(0xFF10B981); // Emerald green
  static const Color primaryDark = Color(0xFF059669);
  static const Color primaryLight = Color(0xFF34D399);

  // Secondary Colors
  static const Color secondary = Color(0xFFF59E0B); // Amber
  static const Color secondaryDark = Color(0xFFD97706);
  static const Color secondaryLight = Color(0xFFFBBF24);

  // Background Colors (Light)
  static const Color background = Color(0xFFFFFFFF); // Pure white
  static const Color surface = Color(0xFFF3F4F6); // Light gray
  static const Color surfaceDark = Color(0xFFE5E7EB);

  // Text Colors (Light)
  static const Color textPrimary = Color(0xFF1F2937); // Dark gray
  static const Color textSecondary = Color(0xFF6B7280); // Medium gray
  static const Color textDisabled = Color(0xFF9CA3AF); // Light gray

  // Status Colors
  static const Color success = Color(0xFF10B981); // Same as primary
  static const Color warning = Color(0xFFF59E0B); // Same as secondary
  static const Color error = Color(0xFFEF4444); // Red
  static const Color info = Color(0xFF3B82F6); // Blue

  // Retailer Brand Colors (for store-specific UI elements)
  static const Color pickNPay = Color(0xFFE31837); // Red
  static const Color woolworths = Color(0xFF006341); // Green
  static const Color shoprite = Color(0xFFFF6600); // Orange
  static const Color checkers = Color(0xFF005EB8); // Blue
  static const Color makro = Color(0xFF003DA5); // Makro blue
  static const Color disChem = Color(0xFF00A94F); // Dis-Chem green
  static const Color clicks = Color(0xFF005BAA); // Clicks blue
  static const Color spar = Color(0xFFDC1E35); // SPAR red

  // Utility Colors (Light)
  static const Color divider = Color(0xFFE5E7EB);
  static const Color shadow = Color(0x1A000000); // 10% black
  static const Color overlay = Color(0x80000000); // 50% black

  // ============================================
  // DARK MODE COLORS
  // ============================================

  // Background Colors (Dark)
  static const Color backgroundDark = Color(0xFF111827); // Very dark blue-gray
  static const Color surfaceDarkMode = Color(0xFF1F2937); // Dark gray
  static const Color surfaceDarkModeLight = Color(
    0xFF374151,
  ); // Medium dark gray

  // Text Colors (Dark)
  static const Color textPrimaryDark = Color(0xFFF9FAFB); // Almost white
  static const Color textSecondaryDark = Color(0xFF9CA3AF); // Light gray
  static const Color textDisabledDark = Color(0xFF6B7280); // Medium gray

  // Utility Colors (Dark)
  static const Color dividerDark = Color(0xFF374151);
  static const Color shadowDark = Color(0x40000000); // 25% black

  // Private constructor to prevent instantiation
  AppColors._();
}

/// Extension on BuildContext for easy access to theme-aware colors
/// Usage: context.textPrimary, context.textSecondary, context.surface
extension ThemeColors on BuildContext {
  /// Check if current theme is dark
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  /// Primary text color (adapts to theme)
  Color get textPrimary =>
      isDarkMode ? AppColors.textPrimaryDark : AppColors.textPrimary;

  /// Secondary text color (adapts to theme)
  Color get textSecondary =>
      isDarkMode ? AppColors.textSecondaryDark : AppColors.textSecondary;

  /// Disabled text color (adapts to theme)
  Color get textDisabled =>
      isDarkMode ? AppColors.textDisabledDark : AppColors.textDisabled;

  /// Surface color (adapts to theme)
  Color get surfaceColor =>
      isDarkMode ? AppColors.surfaceDarkMode : AppColors.surface;

  /// Background color (adapts to theme)
  Color get backgroundColor =>
      isDarkMode ? AppColors.backgroundDark : AppColors.background;

  /// Divider color (adapts to theme)
  Color get dividerColor =>
      isDarkMode ? AppColors.dividerDark : AppColors.divider;

  /// Card color (adapts to theme)
  Color get cardColor => isDarkMode ? AppColors.surfaceDarkMode : Colors.white;
}
