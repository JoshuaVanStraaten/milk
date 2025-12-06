import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Custom page transitions for a polished app feel
class AppPageTransitions {
  /// Default transition duration
  static const Duration defaultDuration = Duration(milliseconds: 300);
  static const Duration fastDuration = Duration(milliseconds: 200);

  /// Slide up transition - good for modals, detail screens
  static CustomTransitionPage slideUp<T>({
    required Widget child,
    required GoRouterState state,
    Duration? duration,
  }) {
    return CustomTransitionPage<T>(
      key: state.pageKey,
      child: child,
      transitionDuration: duration ?? defaultDuration,
      reverseTransitionDuration: duration ?? defaultDuration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final tween = Tween(
          begin: const Offset(0, 0.1),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic));

        final fadeTween = Tween(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut));

        return SlideTransition(
          position: animation.drive(tween),
          child: FadeTransition(
            opacity: animation.drive(fadeTween),
            child: child,
          ),
        );
      },
    );
  }

  /// Slide from right transition - good for push navigation
  static CustomTransitionPage slideFromRight<T>({
    required Widget child,
    required GoRouterState state,
    Duration? duration,
  }) {
    return CustomTransitionPage<T>(
      key: state.pageKey,
      child: child,
      transitionDuration: duration ?? defaultDuration,
      reverseTransitionDuration: duration ?? defaultDuration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final tween = Tween(
          begin: const Offset(0.3, 0),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic));

        final fadeTween = Tween(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut));

        return SlideTransition(
          position: animation.drive(tween),
          child: FadeTransition(
            opacity: animation.drive(fadeTween),
            child: child,
          ),
        );
      },
    );
  }

  /// Fade transition - good for tab switches, auth screens
  static CustomTransitionPage fade<T>({
    required Widget child,
    required GoRouterState state,
    Duration? duration,
  }) {
    return CustomTransitionPage<T>(
      key: state.pageKey,
      child: child,
      transitionDuration: duration ?? fastDuration,
      reverseTransitionDuration: duration ?? fastDuration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurveTween(curve: Curves.easeInOut).animate(animation),
          child: child,
        );
      },
    );
  }

  /// Scale and fade transition - good for important screens
  static CustomTransitionPage scaleUp<T>({
    required Widget child,
    required GoRouterState state,
    Duration? duration,
  }) {
    return CustomTransitionPage<T>(
      key: state.pageKey,
      child: child,
      transitionDuration: duration ?? defaultDuration,
      reverseTransitionDuration: duration ?? defaultDuration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final scaleTween = Tween(
          begin: 0.95,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic));

        final fadeTween = Tween(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut));

        return ScaleTransition(
          scale: animation.drive(scaleTween),
          child: FadeTransition(
            opacity: animation.drive(fadeTween),
            child: child,
          ),
        );
      },
    );
  }

  /// Shared axis transition - good for related content (horizontal)
  static CustomTransitionPage sharedAxisHorizontal<T>({
    required Widget child,
    required GoRouterState state,
    Duration? duration,
  }) {
    return CustomTransitionPage<T>(
      key: state.pageKey,
      child: child,
      transitionDuration: duration ?? defaultDuration,
      reverseTransitionDuration: duration ?? defaultDuration,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        // Incoming page slides in from right and fades in
        final slideTween = Tween(
          begin: const Offset(0.2, 0),
          end: Offset.zero,
        ).chain(CurveTween(curve: Curves.easeOutCubic));

        final fadeTween = Tween(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut));

        // Outgoing page slides out to left and fades out
        final secondarySlideTween = Tween(
          begin: Offset.zero,
          end: const Offset(-0.2, 0),
        ).chain(CurveTween(curve: Curves.easeInCubic));

        final secondaryFadeTween = Tween(
          begin: 1.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeIn));

        return Stack(
          children: [
            SlideTransition(
              position: secondaryAnimation.drive(secondarySlideTween),
              child: FadeTransition(
                opacity: secondaryAnimation.drive(secondaryFadeTween),
                child: child,
              ),
            ),
            SlideTransition(
              position: animation.drive(slideTween),
              child: FadeTransition(
                opacity: animation.drive(fadeTween),
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }

  /// No transition - instant switch
  static CustomTransitionPage none<T>({
    required Widget child,
    required GoRouterState state,
  }) {
    return CustomTransitionPage<T>(
      key: state.pageKey,
      child: child,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return child;
      },
    );
  }
}
