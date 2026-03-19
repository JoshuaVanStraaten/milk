import 'package:shared_preferences/shared_preferences.dart';

/// Manages tutorial completion state via SharedPreferences.
class TutorialService {
  static const _homeTutorialKey = 'tutorial_home_completed';
  static const _browseTutorialKey = 'tutorial_browse_completed';
  static const _recipesTutorialKey = 'tutorial_recipes_completed';
  static const _recipeResultTutorialKey = 'tutorial_recipe_result_completed';
  static const _listsTutorialKey = 'tutorial_lists_completed';
  static const _allTutorialKey = 'tutorial_completed';

  final SharedPreferences _prefs;
  TutorialService(this._prefs);

  bool get isHomeTutorialCompleted =>
      _prefs.getBool(_allTutorialKey) ?? _prefs.getBool(_homeTutorialKey) ?? false;

  bool get isBrowseTutorialCompleted =>
      _prefs.getBool(_allTutorialKey) ?? _prefs.getBool(_browseTutorialKey) ?? false;

  bool get isRecipesTutorialCompleted =>
      _prefs.getBool(_allTutorialKey) ?? _prefs.getBool(_recipesTutorialKey) ?? false;

  bool get isRecipeResultTutorialCompleted =>
      _prefs.getBool(_allTutorialKey) ?? _prefs.getBool(_recipeResultTutorialKey) ?? false;

  bool get isListsTutorialCompleted =>
      _prefs.getBool(_allTutorialKey) ?? _prefs.getBool(_listsTutorialKey) ?? false;

  Future<void> completeHomeTutorial() => _prefs.setBool(_homeTutorialKey, true);

  Future<void> completeBrowseTutorial() => _prefs.setBool(_browseTutorialKey, true);

  Future<void> completeRecipesTutorial() => _prefs.setBool(_recipesTutorialKey, true);

  Future<void> completeRecipeResultTutorial() => _prefs.setBool(_recipeResultTutorialKey, true);

  Future<void> completeListsTutorial() => _prefs.setBool(_listsTutorialKey, true);

  Future<void> skipAll() => _prefs.setBool(_allTutorialKey, true);

  Future<void> resetAll() async {
    await _prefs.remove(_homeTutorialKey);
    await _prefs.remove(_browseTutorialKey);
    await _prefs.remove(_recipesTutorialKey);
    await _prefs.remove(_recipeResultTutorialKey);
    await _prefs.remove(_listsTutorialKey);
    await _prefs.remove(_allTutorialKey);
  }
}
