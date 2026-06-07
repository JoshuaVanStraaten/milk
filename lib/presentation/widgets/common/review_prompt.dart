// lib/presentation/widgets/common/review_prompt.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import '../../../presentation/providers/recipe_provider.dart';

/// Records a recipe save and — if conditions are met — shows the
/// "Rate Milk?" dialog. Safe to call after every save; the service
/// handles all gating logic internally.
Future<void> showReviewPromptIfNeeded(
  BuildContext context,
  WidgetRef ref,
) async {
  final service = ref.read(reviewServiceProvider);

  await service.recordSave();

  if (!service.shouldPrompt()) return;
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Enjoying Milk?'),
      content: const Text(
        'If you\'re finding it useful, a quick rating '
        'helps others discover the app.',
      ),
      actions: [
        TextButton(
          onPressed: () async {
            Navigator.of(ctx).pop();
            await service.onNoThanks();
          },
          child: const Text('No Thanks'),
        ),
        TextButton(
          onPressed: () async {
            Navigator.of(ctx).pop();
            await service.onLater();
          },
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.of(ctx).pop();
            final inAppReview = InAppReview.instance;
            if (await inAppReview.isAvailable()) {
              await inAppReview.requestReview();
            }
          },
          child: const Text('Rate Now'),
        ),
      ],
    ),
  );
}
