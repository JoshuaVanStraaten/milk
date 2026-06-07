// lib/data/services/review_service.dart
import 'package:shared_preferences/shared_preferences.dart';

class ReviewService {
  static const _saveCountKey = 'recipe_save_count';
  static const _snoozedUntilKey = 'review_prompt_snoozed_until';
  static const _dismissedKey = 'review_prompt_dismissed';
  static const _triggerCount = 3;
  static const _snoozeDays = 7;

  final SharedPreferences _prefs;
  ReviewService(this._prefs);

  /// Increments the save counter.
  Future<void> recordSave() async {
    final count = (_prefs.getInt(_saveCountKey) ?? 0) + 1;
    await _prefs.setInt(_saveCountKey, count);
  }

  /// Returns true if the rating prompt should be shown right now.
  bool shouldPrompt() {
    final count = _prefs.getInt(_saveCountKey) ?? 0;
    if (count < _triggerCount) return false;

    final dismissed = _prefs.getBool(_dismissedKey) ?? false;
    if (dismissed) return false;

    final snoozedUntil = _prefs.getInt(_snoozedUntilKey) ?? 0;
    if (snoozedUntil == 0) return true;

    return DateTime.now().millisecondsSinceEpoch > snoozedUntil;
  }

  /// Called when the user taps "Later". Snoozes for [_snoozeDays] days.
  Future<void> onLater() async {
    final until = DateTime.now()
        .add(const Duration(days: _snoozeDays))
        .millisecondsSinceEpoch;
    await _prefs.setInt(_snoozedUntilKey, until);
  }

  /// Called when the user taps "No Thanks". Permanently suppresses.
  Future<void> onNoThanks() async {
    await _prefs.setBool(_dismissedKey, true);
  }

  /// Resets all review state — for manual testing only.
  Future<void> resetForTesting() async {
    await _prefs.remove(_saveCountKey);
    await _prefs.remove(_snoozedUntilKey);
    await _prefs.remove(_dismissedKey);
  }
}
