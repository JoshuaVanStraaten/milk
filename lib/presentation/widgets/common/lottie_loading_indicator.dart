import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../core/theme/app_colors.dart';

class LottieLoadingIndicator extends StatelessWidget {
  final double width;
  final double height;
  final String? message;
  final TextStyle? messageStyle;
  final Widget? subtitle;

  const LottieLoadingIndicator({
    super.key,
    this.width = 120,
    this.height = 120,
    this.message,
    this.messageStyle,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Lottie.asset(
          'assets/animations/loading_screen.json',
          width: width,
          height: height,
          fit: BoxFit.contain,
          repeat: true,
          errorBuilder: (context, error, stackTrace) {
            return SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                strokeCap: StrokeCap.round,
                color: AppColors.primary,
              ),
            );
          },
        ),
        if (message != null) ...[
          const SizedBox(height: 16),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: messageStyle ??
                TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                ),
          ),
        ],
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          subtitle!,
        ],
      ],
    );
  }
}
