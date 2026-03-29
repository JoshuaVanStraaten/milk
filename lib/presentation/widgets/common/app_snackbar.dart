import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Snackbar types for consistent styling
enum SnackbarType { success, error, warning, info }

/// Consistent snackbar helper for the entire app
class AppSnackbar {
  /// Show a success snackbar
  static void success(
    BuildContext context, {
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 3),
  }) {
    _show(
      context,
      message: message,
      type: SnackbarType.success,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
    );
  }

  /// Show an error snackbar
  static void error(
    BuildContext context, {
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 4),
  }) {
    _show(
      context,
      message: message,
      type: SnackbarType.error,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
    );
  }

  /// Show a warning snackbar
  static void warning(
    BuildContext context, {
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 3),
  }) {
    _show(
      context,
      message: message,
      type: SnackbarType.warning,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
    );
  }

  /// Show an info snackbar
  static void info(
    BuildContext context, {
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 3),
  }) {
    _show(
      context,
      message: message,
      type: SnackbarType.info,
      actionLabel: actionLabel,
      onAction: onAction,
      duration: duration,
    );
  }

  /// Show a snackbar with undo action (common pattern for deletions)
  static void showWithUndo(
    BuildContext context, {
    required String message,
    required VoidCallback onUndo,
    Duration duration = const Duration(seconds: 4),
  }) {
    _show(
      context,
      message: message,
      type: SnackbarType.info,
      actionLabel: 'Undo',
      onAction: onUndo,
      duration: duration,
    );
  }

  /// Internal method to show snackbar
  static void _show(
    BuildContext context, {
    required String message,
    required SnackbarType type,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 3),
  }) {
    // Clear any existing snackbars
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    final config = _getConfig(type);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final snackBar = SnackBar(
      content: Row(
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(config.icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          // Message
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: isDark ? config.darkColor : config.color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      duration: duration,
      action: actionLabel != null
          ? SnackBarAction(
              label: actionLabel,
              textColor: Colors.white,
              onPressed: () {
                onAction?.call();
              },
            )
          : null,
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  /// Get configuration for snackbar type
  static _SnackbarConfig _getConfig(SnackbarType type) {
    switch (type) {
      case SnackbarType.success:
        return _SnackbarConfig(
          icon: Icons.check_circle_outline,
          color: AppColors.success,
          darkColor: AppColors.snackbarSuccess,
        );
      case SnackbarType.error:
        return _SnackbarConfig(
          icon: Icons.error_outline,
          color: AppColors.error,
          darkColor: AppColors.snackbarError,
        );
      case SnackbarType.warning:
        return _SnackbarConfig(
          icon: Icons.warning_amber_outlined,
          color: AppColors.warning,
          darkColor: AppColors.snackbarWarning,
        );
      case SnackbarType.info:
        return _SnackbarConfig(
          icon: Icons.info_outline,
          color: AppColors.primary,
          darkColor: AppColors.primaryDark,
        );
    }
  }
}

/// Internal configuration class
class _SnackbarConfig {
  final IconData icon;
  final Color color;
  final Color darkColor;

  const _SnackbarConfig({
    required this.icon,
    required this.color,
    required this.darkColor,
  });
}
