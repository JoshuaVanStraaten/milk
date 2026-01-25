import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Shows a user-friendly error dialog for AI-related errors
///
/// Usage in a ConsumerWidget:
/// ```dart
/// ref.listen<RecipeGenerationState>(recipeGenerationProvider, (prev, next) {
///   if (next.hasError) {
///     showAIErrorDialog(
///       context,
///       title: next.errorTitle ?? 'Error',
///       message: next.error!,
///       onDismiss: () => ref.read(recipeGenerationProvider.notifier).clearError(),
///     );
///   }
/// });
/// ```
void showAIErrorDialog(
  BuildContext context, {
  required String title,
  required String message,
  VoidCallback? onDismiss,
  VoidCallback? onRetry,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) => AlertDialog(
      backgroundColor: isDark ? AppColors.surfaceDarkMode : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.warning.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.cloud_off_rounded,
          color: AppColors.warning,
          size: 32,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
        ),
        textAlign: TextAlign.center,
      ),
      content: Text(
        message,
        style: TextStyle(
          fontSize: 14,
          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
          height: 1.4,
        ),
        textAlign: TextAlign.center,
      ),
      actionsAlignment: MainAxisAlignment.center,
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        if (onRetry != null)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onDismiss?.call();
              onRetry();
            },
            child: const Text('Try Again'),
          ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop();
            onDismiss?.call();
          },
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// A simpler snackbar alternative for less severe errors
void showAIErrorSnackbar(
  BuildContext context, {
  required String message,
  VoidCallback? onRetry,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      action: onRetry != null
          ? SnackBarAction(label: 'Retry', onPressed: onRetry)
          : null,
      duration: const Duration(seconds: 5),
    ),
  );
}
