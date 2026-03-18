import 'dart:ui';

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Frosted-glass card container for loading states and overlays.
///
/// Uses [BackdropFilter] for blur + semi-transparent surface with subtle border.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final double blurSigma;

  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 16,
    this.padding,
    this.blurSigma = 10,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            color: isDark
                ? AppColors.surfaceDarkMode.withValues(alpha: 0.4)
                : AppColors.primary.withValues(alpha: 0.04),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : AppColors.primary.withValues(alpha: 0.12),
              width: 1,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      Colors.white.withValues(alpha: 0.06),
                      Colors.transparent,
                    ]
                  : [
                      AppColors.primary.withValues(alpha: 0.06),
                      Colors.transparent,
                    ],
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? AppColors.primary.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.04),
                blurRadius: isDark ? 24 : 12,
                spreadRadius: isDark ? 1 : 0,
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
