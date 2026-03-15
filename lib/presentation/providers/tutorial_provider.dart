import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/tutorial_service.dart';
import 'theme_provider.dart';

/// Provider for TutorialService instance.
final tutorialServiceProvider = Provider<TutorialService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return TutorialService(prefs);
});
