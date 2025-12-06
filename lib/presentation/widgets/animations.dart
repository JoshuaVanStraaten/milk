import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Haptic feedback utility for consistent feedback across the app
class AppHaptics {
  /// Light tap feedback - for checkboxes, toggles, small buttons
  static void lightTap() {
    HapticFeedback.lightImpact();
  }

  /// Medium tap feedback - for button presses, card taps
  static void mediumTap() {
    HapticFeedback.mediumImpact();
  }

  /// Heavy tap feedback - for important actions like delete, confirm
  static void heavyTap() {
    HapticFeedback.heavyImpact();
  }

  /// Selection feedback - for selecting items in a list
  static void selection() {
    HapticFeedback.selectionClick();
  }

  /// Success feedback - for completed actions
  static void success() {
    HapticFeedback.mediumImpact();
  }

  /// Error/Warning feedback - for errors or destructive actions
  static void warning() {
    HapticFeedback.heavyImpact();
  }
}

/// Animated list item that fades and slides in with staggered delay
class AnimatedListItem extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration delay;
  final Duration duration;
  final Offset beginOffset;
  final bool animate;

  const AnimatedListItem({
    super.key,
    required this.child,
    this.index = 0,
    this.delay = const Duration(milliseconds: 50),
    this.duration = const Duration(milliseconds: 300),
    this.beginOffset = const Offset(0, 0.1),
    this.animate = true,
  });

  @override
  State<AnimatedListItem> createState() => _AnimatedListItemState();
}

class _AnimatedListItemState extends State<AnimatedListItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _slideAnimation = Tween<Offset>(
      begin: widget.beginOffset,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    if (widget.animate) {
      // Staggered delay based on index
      Future.delayed(widget.delay * widget.index, () {
        if (mounted) {
          _controller.forward();
        }
      });
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(position: _slideAnimation, child: widget.child),
    );
  }
}

/// Animated checkbox with scale bounce effect
class AnimatedCheckbox extends StatefulWidget {
  final bool value;
  final ValueChanged<bool?>? onChanged;
  final Color? activeColor;
  final bool enableHaptics;

  const AnimatedCheckbox({
    super.key,
    required this.value,
    this.onChanged,
    this.activeColor,
    this.enableHaptics = true,
  });

  @override
  State<AnimatedCheckbox> createState() => _AnimatedCheckboxState();
}

class _AnimatedCheckboxState extends State<AnimatedCheckbox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.8), weight: 50),
      TweenSequenceItem(tween: Tween<double>(begin: 0.8, end: 1.1), weight: 30),
      TweenSequenceItem(tween: Tween<double>(begin: 1.1, end: 1.0), weight: 20),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.enableHaptics) {
      AppHaptics.lightTap();
    }
    _controller.forward(from: 0);
    widget.onChanged?.call(!widget.value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Checkbox(
          value: widget.value,
          onChanged: (value) {
            if (widget.enableHaptics) {
              AppHaptics.lightTap();
            }
            _controller.forward(from: 0);
            widget.onChanged?.call(value);
          },
          activeColor: widget.activeColor,
        ),
      ),
    );
  }
}

/// Slide-to-dismiss with animation feedback
class AnimatedDismissible extends StatelessWidget {
  final Key itemKey;
  final Widget child;
  final Widget? background;
  final VoidCallback? onDismissed;
  final DismissDirection direction;
  final bool enableHaptics;

  const AnimatedDismissible({
    super.key,
    required this.itemKey,
    required this.child,
    this.background,
    this.onDismissed,
    this.direction = DismissDirection.endToStart,
    this.enableHaptics = true,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: itemKey,
      direction: direction,
      background: background,
      onDismissed: (dir) {
        if (enableHaptics) {
          AppHaptics.warning();
        }
        onDismissed?.call();
      },
      child: child,
    );
  }
}

/// Animated FAB with scale effect on press
class AnimatedFAB extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget icon;
  final Widget label;
  final bool enableHaptics;

  const AnimatedFAB({
    super.key,
    this.onPressed,
    required this.icon,
    required this.label,
    this.enableHaptics = true,
  });

  @override
  State<AnimatedFAB> createState() => _AnimatedFABState();
}

class _AnimatedFABState extends State<AnimatedFAB>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _controller.reverse();
    if (widget.enableHaptics) {
      AppHaptics.mediumTap();
    }
    widget.onPressed?.call();
  }

  void _handleTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: FloatingActionButton.extended(
          onPressed: null, // Handled by GestureDetector
          icon: widget.icon,
          label: widget.label,
        ),
      ),
    );
  }
}

/// Animated card with subtle press effect
class AnimatedPressCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enableHaptics;
  final double pressScale;
  final BorderRadius? borderRadius;

  const AnimatedPressCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.enableHaptics = true,
    this.pressScale = 0.98,
    this.borderRadius,
  });

  @override
  State<AnimatedPressCard> createState() => _AnimatedPressCardState();
}

class _AnimatedPressCardState extends State<AnimatedPressCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.pressScale,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _controller.reverse();
    if (widget.enableHaptics) {
      AppHaptics.lightTap();
    }
    widget.onTap?.call();
  }

  void _handleTapCancel() {
    _controller.reverse();
  }

  void _handleLongPress() {
    if (widget.enableHaptics) {
      AppHaptics.mediumTap();
    }
    widget.onLongPress?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onLongPress: widget.onLongPress != null ? _handleLongPress : null,
      child: ScaleTransition(scale: _scaleAnimation, child: widget.child),
    );
  }
}

/// Animated strikethrough text for completed items
class AnimatedStrikethrough extends StatefulWidget {
  final String text;
  final bool isComplete;
  final TextStyle? style;
  final TextStyle? completedStyle;
  final Duration duration;
  final int maxLines;
  final TextOverflow overflow;

  const AnimatedStrikethrough({
    super.key,
    required this.text,
    required this.isComplete,
    this.style,
    this.completedStyle,
    this.duration = const Duration(milliseconds: 300),
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  @override
  State<AnimatedStrikethrough> createState() => _AnimatedStrikethroughState();
}

class _AnimatedStrikethroughState extends State<AnimatedStrikethrough>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _strikeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: widget.isComplete ? 1.0 : 0.0,
    );

    _strikeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(AnimatedStrikethrough oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isComplete != oldWidget.isComplete) {
      if (widget.isComplete) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _strikeAnimation,
      builder: (context, child) {
        return CustomPaint(
          foregroundPainter: _StrikethroughPainter(
            progress: _strikeAnimation.value,
            textStyle: widget.style ?? const TextStyle(),
          ),
          child: AnimatedDefaultTextStyle(
            duration: widget.duration,
            style: widget.isComplete
                ? (widget.completedStyle ?? widget.style ?? const TextStyle())
                : (widget.style ?? const TextStyle()),
            child: Text(
              widget.text,
              maxLines: widget.maxLines,
              overflow: widget.overflow,
            ),
          ),
        );
      },
    );
  }
}

class _StrikethroughPainter extends CustomPainter {
  final double progress;
  final TextStyle textStyle;

  _StrikethroughPainter({required this.progress, required this.textStyle});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final paint = Paint()
      ..color = (textStyle.color ?? Colors.black).withOpacity(0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final startX = 0.0;
    final endX = size.width * progress;
    final y = size.height / 2;

    canvas.drawLine(Offset(startX, y), Offset(endX, y), paint);
  }

  @override
  bool shouldRepaint(_StrikethroughPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Success checkmark animation
class AnimatedSuccessCheck extends StatefulWidget {
  final bool show;
  final double size;
  final Color color;
  final Duration duration;

  const AnimatedSuccessCheck({
    super.key,
    required this.show,
    this.size = 24,
    this.color = Colors.green,
    this.duration = const Duration(milliseconds: 400),
  });

  @override
  State<AnimatedSuccessCheck> createState() => _AnimatedSuccessCheckState();
}

class _AnimatedSuccessCheckState extends State<AnimatedSuccessCheck>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _checkAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 1.2), weight: 60),
      TweenSequenceItem(tween: Tween<double>(begin: 1.2, end: 1.0), weight: 40),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _checkAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
      ),
    );

    if (widget.show) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(AnimatedSuccessCheck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.show && !oldWidget.show) {
      _controller.forward(from: 0);
    } else if (!widget.show && oldWidget.show) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _CheckPainter(
              progress: _checkAnimation.value,
              color: widget.color,
            ),
          ),
        );
      },
    );
  }
}

class _CheckPainter extends CustomPainter {
  final double progress;
  final Color color;

  _CheckPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.12
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Draw circle
    final circlePaint = Paint()
      ..color = color.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width / 2,
      circlePaint,
    );

    if (progress <= 0) return;

    // Check mark path
    final path = Path();
    final startX = size.width * 0.25;
    final startY = size.height * 0.5;
    final midX = size.width * 0.45;
    final midY = size.height * 0.7;
    final endX = size.width * 0.75;
    final endY = size.height * 0.35;

    path.moveTo(startX, startY);

    if (progress < 0.5) {
      // First part of check
      final t = progress * 2;
      path.lineTo(startX + (midX - startX) * t, startY + (midY - startY) * t);
    } else {
      // Complete first part and draw second
      path.lineTo(midX, midY);
      final t = (progress - 0.5) * 2;
      path.lineTo(midX + (endX - midX) * t, midY + (endY - midY) * t);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
