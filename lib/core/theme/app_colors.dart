import 'package:flutter/material.dart';

/// App-wide color palette
/// Following the emerald green theme for a fresh, grocery-focused aesthetic
class AppColors {
  // Primary Colors
  static const Color primary = Color(0xFF10B981); // Emerald green
  static const Color primaryDark = Color(0xFF059669);
  static const Color primaryLight = Color(0xFF34D399);

  // Secondary Colors
  static const Color secondary = Color(0xFFF59E0B); // Amber
  static const Color secondaryDark = Color(0xFFD97706);
  static const Color secondaryLight = Color(0xFFFBBF24);

  // Background Colors
  static const Color background = Color(0xFFFFFFFF); // Pure white
  static const Color surface = Color(0xFFF3F4F6); // Light gray
  static const Color surfaceDark = Color(0xFFE5E7EB);

  // Text Colors
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

  // Utility Colors
  static const Color divider = Color(0xFFE5E7EB);
  static const Color shadow = Color(0x1A000000); // 10% black
  static const Color overlay = Color(0x80000000); // 50% black

  // Disabled
  AppColors._(); // Private constructor to prevent instantiation
}
