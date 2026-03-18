import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Text widget with an animated shimmer gradient sweep.
///
/// The shimmer highlights text with an emerald green sweep that repeats
/// continuously, giving a premium loading-indicator feel.
class ShimmerText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;

  const ShimmerText({
    super.key,
    required this.text,
    this.style,
    this.textAlign,
    this.maxLines,
  });

  @override
  State<ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<ShimmerText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                baseColor,
                AppColors.primaryLight,
                baseColor,
              ],
              stops: const [0.0, 0.5, 1.0],
              transform: _SlidingGradientTransform(_animation.value),
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcIn,
          child: child,
        );
      },
      child: Text(
        widget.text,
        style: widget.style,
        textAlign: widget.textAlign,
        maxLines: widget.maxLines,
        overflow:
            widget.maxLines != null ? TextOverflow.ellipsis : null,
      ),
    );
  }
}

/// Translates a [LinearGradient] horizontally by [slidePercent].
/// Duplicated from skeleton_loaders.dart (8 lines, private there).
class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;

  const _SlidingGradientTransform(this.slidePercent);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0, 0);
  }
}
