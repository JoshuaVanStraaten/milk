import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/recipe.dart';
import '../../data/repositories/recipe_repository.dart';
import '../../data/services/gemini_service.dart'; // RecipeSuggestion & GeminiException
import 'province_provider.dart';

// =============================================================================
// SERVICE PROVIDERS
// =============================================================================

/// Gemini service provider
/// Reads GEMINI_API_KEY from .env file
final geminiServiceProvider = Provider<GeminiService>((ref) {
  final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
  if (apiKey.isEmpty) {
    throw Exception(
      'GEMINI_API_KEY not configured. Add it to your .env file:\n'
      'GEMINI_API_KEY=your_api_key_here',
    );
  }
  return GeminiService(apiKey: apiKey);
});

/// Recipe repository provider
final recipeRepositoryProvider = Provider<RecipeRepository>((ref) {
  return RecipeRepository(Supabase.instance.client);
});

// =============================================================================
// RECIPE GENERATION STATE
// =============================================================================

/// State for recipe generation
class RecipeGenerationState {
  final bool isLoading;
  final Recipe? generatedRecipe;
  final String? error;
  final String? errorTitle; // For popup dialog title
  final RecipeGenerationStep currentStep;
  final String?
  matchedProvince; // Track which province ingredients were matched for

  const RecipeGenerationState({
    this.isLoading = false,
    this.generatedRecipe,
    this.error,
    this.errorTitle,
    this.currentStep = RecipeGenerationStep.input,
    this.matchedProvince,
  });

  RecipeGenerationState copyWith({
    bool? isLoading,
    Recipe? generatedRecipe,
    String? error,
    String? errorTitle,
    RecipeGenerationStep? currentStep,
    String? matchedProvince,
    bool clearError = false,
  }) {
    return RecipeGenerationState(
      isLoading: isLoading ?? this.isLoading,
      generatedRecipe: generatedRecipe ?? this.generatedRecipe,
      error: clearError ? null : (error ?? this.error),
      errorTitle: clearError ? null : (errorTitle ?? this.errorTitle),
      currentStep: currentStep ?? this.currentStep,
      matchedProvince: matchedProvince ?? this.matchedProvince,
    );
  }

  /// Whether there's an error to show in a popup
  bool get hasError => error != null;
}

enum RecipeGenerationStep {
  input, // User entering recipe request
  generating, // AI generating recipe
  review, // Showing generated recipe
  matching, // Matching ingredients to products
  export, // Exporting to shopping list
  complete, // Done
}

/// Recipe generation notifier
class RecipeGenerationNotifier extends StateNotifier<RecipeGenerationState> {
  final GeminiService _geminiService;
  final RecipeRepository _repository;
  final Ref _ref;

  RecipeGenerationNotifier(this._geminiService, this._repository, this._ref)
    : super(const RecipeGenerationState());

  /// Get current province from provider
  String get _currentProvince => _ref.read(selectedProvinceProvider);

  /// Clear the current error (call after showing popup)
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Generate a recipe from user request
  /// [autoMatch] - If true, automatically match ingredients to products after generation
  /// [preferredRetailer] - If set, prefer products from this retailer when auto-matching
  Future<void> generateRecipe({
    required String recipeRequest,
    int servings = 4,
    List<String>? dietaryRestrictions,
    bool autoMatch = true,
    String? preferredRetailer,
  }) async {
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      currentStep: RecipeGenerationStep.generating,
    );

    try {
      final recipe = await _geminiService.generateRecipe(
        recipeRequest: recipeRequest,
        servings: servings,
        dietaryRestrictions: dietaryRestrictions,
      );

      state = state.copyWith(generatedRecipe: recipe);

      // Auto-match ingredients to products in current province
      if (autoMatch) {
        await _autoMatchIngredients(preferredRetailer: preferredRetailer);
      }

      state = state.copyWith(
        isLoading: false,
        currentStep: RecipeGenerationStep.review,
        matchedProvince: _currentProvince,
      );
    } on GeminiException catch (e) {
      debugPrint('Gemini error generating recipe: $e');
      state = state.copyWith(
        isLoading: false,
        error: e.userFriendlyMessage,
        errorTitle: e.errorTitle,
        currentStep: RecipeGenerationStep.input,
      );
    } catch (e) {
      debugPrint('Error generating recipe: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to generate recipe. Please try again.',
        errorTitle: 'Request Failed',
        currentStep: RecipeGenerationStep.input,
      );
    }
  }

  /// Automatically match all ingredients to best matching products
  Future<void> _autoMatchIngredients({String? preferredRetailer}) async {
    if (state.generatedRecipe == null) return;

    final province = _currentProvince;
    final ingredients = List<RecipeIngredient>.from(
      state.generatedRecipe!.ingredients,
    );

    for (int i = 0; i < ingredients.length; i++) {
      final ingredient = ingredients[i];

      try {
        // Search for matching products in the current province
        final matches = await _repository.findMatchingProducts(
          ingredientName: ingredient.ingredientName,
          province: province,
          retailer: preferredRetailer,
          maxResults: 5,
        );

        if (matches.isNotEmpty) {
          // If a specific retailer is preferred, filter to only that retailer
          // (safety check in case SQL function doesn't filter properly)
          IngredientProductMatch? bestMatch;
          if (preferredRetailer != null && preferredRetailer.isNotEmpty) {
            final filteredMatches = matches
                .where(
                  (m) =>
                      m.retailer.toLowerCase() ==
                      preferredRetailer.toLowerCase(),
                )
                .toList();
            if (filteredMatches.isNotEmpty) {
              bestMatch = filteredMatches.first;
            }
          } else {
            bestMatch = matches.first;
          }

          if (bestMatch != null) {
            ingredients[i] = ingredient.copyWith(
              matchedProductIndex: bestMatch.productIndex,
              matchedProductName: bestMatch.productName,
              matchedProductPrice: bestMatch.numericPrice,
              matchedRetailer: bestMatch.retailer,
            );
          } else if (preferredRetailer != null &&
              preferredRetailer.isNotEmpty) {
            // When filtering by retailer and no match found, ensure cleared
            ingredients[i] = ingredient.copyWith(clearMatch: true);
          }
        }
      } catch (e) {
        // If matching fails for one ingredient, continue with others
        debugPrint(
          'Failed to match ingredient "${ingredient.ingredientName}": $e',
        );
        // When filtering by retailer, clear match on error to avoid wrong store
        if (preferredRetailer != null && preferredRetailer.isNotEmpty) {
          ingredients[i] = ingredient.copyWith(clearMatch: true);
        }
      }
    }

    state = state.copyWith(
      generatedRecipe: state.generatedRecipe!.copyWith(
        ingredients: ingredients,
      ),
      matchedProvince: province,
    );
  }

  /// Re-run auto-matching with a specific retailer
  /// Pass empty string or null for "All Stores"
  Future<void> reMatchWithRetailer(String retailer) async {
    if (state.generatedRecipe == null) return;

    state = state.copyWith(isLoading: true);

    // Clear existing matches first using clearMatch flag
    final ingredients = state.generatedRecipe!.ingredients
        .map((i) => i.copyWith(clearMatch: true))
        .toList();

    state = state.copyWith(
      generatedRecipe: state.generatedRecipe!.copyWith(
        ingredients: ingredients,
      ),
    );

    // Convert empty string to null for "All Stores"
    final preferredRetailer = retailer.isEmpty ? null : retailer;
    await _autoMatchIngredients(preferredRetailer: preferredRetailer);

    state = state.copyWith(isLoading: false);
  }

  /// Move to ingredient matching step
  void startIngredientMatching() {
    state = state.copyWith(currentStep: RecipeGenerationStep.matching);
  }

  /// Update recipe with matched ingredient
  void updateIngredientMatch(int index, IngredientProductMatch match) {
    if (state.generatedRecipe == null) return;

    final ingredients = List<RecipeIngredient>.from(
      state.generatedRecipe!.ingredients,
    );
    ingredients[index] = ingredients[index].copyWith(
      matchedProductIndex: match.productIndex,
      matchedProductName: match.productName,
      matchedProductPrice: match.numericPrice,
      matchedRetailer: match.retailer,
    );

    state = state.copyWith(
      generatedRecipe: state.generatedRecipe!.copyWith(
        ingredients: ingredients,
      ),
    );
  }

  /// Clear ingredient match
  void clearIngredientMatch(int index) {
    if (state.generatedRecipe == null) return;

    final ingredients = List<RecipeIngredient>.from(
      state.generatedRecipe!.ingredients,
    );
    ingredients[index] = ingredients[index].copyWith(clearMatch: true);

    state = state.copyWith(
      generatedRecipe: state.generatedRecipe!.copyWith(
        ingredients: ingredients,
      ),
    );
  }

  /// Save the generated recipe
  Future<Recipe?> saveRecipe() async {
    if (state.generatedRecipe == null) return null;

    state = state.copyWith(isLoading: true);

    try {
      final savedRecipe = await _repository.saveRecipe(state.generatedRecipe!);
      state = state.copyWith(isLoading: false, generatedRecipe: savedRecipe);
      return savedRecipe;
    } catch (e) {
      debugPrint('Error saving recipe: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to save recipe.',
        errorTitle: 'Save Failed',
      );
      return null;
    }
  }

  /// Export recipe to shopping list
  Future<String?> exportToShoppingList({
    required String listName,
    String? storeName,
    bool saveRecipe = false,
  }) async {
    if (state.generatedRecipe == null) return null;

    state = state.copyWith(
      isLoading: true,
      currentStep: RecipeGenerationStep.export,
    );

    try {
      // Save recipe first if requested
      if (saveRecipe) {
        await this.saveRecipe();
      }

      // Determine store name from matched ingredients
      if (storeName == null || storeName.isEmpty) {
        final matchedRetailers = state.generatedRecipe!.ingredients
            .where((i) => i.matchedRetailer != null)
            .map((i) => i.matchedRetailer!)
            .toList();

        if (matchedRetailers.isNotEmpty) {
          // Use most common retailer
          final retailerCounts = <String, int>{};
          for (final r in matchedRetailers) {
            retailerCounts[r] = (retailerCounts[r] ?? 0) + 1;
          }
          storeName = retailerCounts.entries
              .reduce((a, b) => a.value > b.value ? a : b)
              .key;
        }
      }

      final listId = await _repository.exportToShoppingList(
        recipe: state.generatedRecipe!,
        listName: listName,
        storeName: storeName ?? 'Mixed Stores',
      );

      state = state.copyWith(
        isLoading: false,
        currentStep: RecipeGenerationStep.complete,
      );

      return listId;
    } catch (e) {
      debugPrint('Error exporting to shopping list: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to create shopping list.',
        errorTitle: 'Export Failed',
      );
      return null;
    }
  }

  /// Reset to initial state
  void reset() {
    state = const RecipeGenerationState();
  }

  /// Go back to previous step
  void goBack() {
    switch (state.currentStep) {
      case RecipeGenerationStep.review:
        state = state.copyWith(currentStep: RecipeGenerationStep.input);
        break;
      case RecipeGenerationStep.matching:
        state = state.copyWith(currentStep: RecipeGenerationStep.review);
        break;
      case RecipeGenerationStep.export:
        state = state.copyWith(currentStep: RecipeGenerationStep.matching);
        break;
      default:
        break;
    }
  }
}

/// Recipe generation provider
final recipeGenerationProvider =
    StateNotifierProvider<RecipeGenerationNotifier, RecipeGenerationState>((
      ref,
    ) {
      final geminiService = ref.watch(geminiServiceProvider);
      final repository = ref.watch(recipeRepositoryProvider);
      return RecipeGenerationNotifier(geminiService, repository, ref);
    });

// =============================================================================
// INGREDIENT MATCHING STATE
// =============================================================================

/// State for ingredient product matching
class IngredientMatchingState {
  final bool isLoading;
  final List<IngredientProductMatch> matches;
  final String? error;

  const IngredientMatchingState({
    this.isLoading = false,
    this.matches = const [],
    this.error,
  });

  IngredientMatchingState copyWith({
    bool? isLoading,
    List<IngredientProductMatch>? matches,
    String? error,
  }) {
    return IngredientMatchingState(
      isLoading: isLoading ?? this.isLoading,
      matches: matches ?? this.matches,
      error: error,
    );
  }
}

/// Ingredient matching notifier
class IngredientMatchingNotifier
    extends StateNotifier<IngredientMatchingState> {
  final RecipeRepository _repository;
  final Ref _ref;

  IngredientMatchingNotifier(this._repository, this._ref)
    : super(const IngredientMatchingState());

  /// Get current province from provider
  String get _currentProvince => _ref.read(selectedProvinceProvider);

  /// Search for matching products in current province
  Future<void> searchMatches({
    required String ingredientName,
    String? retailer,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final matches = await _repository.findMatchingProducts(
        ingredientName: ingredientName,
        province: _currentProvince,
        retailer: retailer,
      );

      state = state.copyWith(isLoading: false, matches: matches);
    } catch (e) {
      debugPrint('Error searching matches: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to search products.',
        matches: [],
      );
    }
  }

  /// Clear matches
  void clearMatches() {
    state = const IngredientMatchingState();
  }
}

/// Ingredient matching provider
final ingredientMatchingProvider =
    StateNotifierProvider<IngredientMatchingNotifier, IngredientMatchingState>((
      ref,
    ) {
      final repository = ref.watch(recipeRepositoryProvider);
      return IngredientMatchingNotifier(repository, ref);
    });

// =============================================================================
// USER RECIPES
// =============================================================================

/// Provider for user's saved recipes
final userRecipesProvider = FutureProvider<List<Recipe>>((ref) async {
  final repository = ref.watch(recipeRepositoryProvider);
  return repository.getUserRecipes();
});

/// Provider for a single recipe by ID
final recipeByIdProvider = FutureProvider.family<Recipe, String>((
  ref,
  recipeId,
) async {
  final repository = ref.watch(recipeRepositoryProvider);
  return repository.getRecipeById(recipeId);
});

// =============================================================================
// RECIPE SUGGESTIONS (FROM INGREDIENTS)
// =============================================================================

/// State for ingredient-based recipe suggestions
/// Note: RecipeSuggestion is imported from gemini_service.dart
class RecipeSuggestionsState {
  final bool isLoading;
  final List<RecipeSuggestion> suggestions;
  final String? error;
  final String? errorTitle;
  final List<String> ingredients; // Preserve ingredients for back navigation
  final String? mealType; // Preserve meal type selection

  const RecipeSuggestionsState({
    this.isLoading = false,
    this.suggestions = const [],
    this.error,
    this.errorTitle,
    this.ingredients = const [],
    this.mealType,
  });

  RecipeSuggestionsState copyWith({
    bool? isLoading,
    List<RecipeSuggestion>? suggestions,
    String? error,
    String? errorTitle,
    List<String>? ingredients,
    String? mealType,
    bool clearError = false,
  }) {
    return RecipeSuggestionsState(
      isLoading: isLoading ?? this.isLoading,
      suggestions: suggestions ?? this.suggestions,
      error: clearError ? null : (error ?? this.error),
      errorTitle: clearError ? null : (errorTitle ?? this.errorTitle),
      ingredients: ingredients ?? this.ingredients,
      mealType: mealType ?? this.mealType,
    );
  }

  /// Whether there's an error to show in a popup
  bool get hasError => error != null;
}

/// Recipe suggestions notifier
class RecipeSuggestionsNotifier extends StateNotifier<RecipeSuggestionsState> {
  final GeminiService _geminiService;

  RecipeSuggestionsNotifier(this._geminiService)
    : super(const RecipeSuggestionsState());

  /// Clear the current error (call after showing popup)
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Get recipe suggestions from available ingredients
  Future<void> getSuggestions({
    required List<String> ingredients,
    String? mealType,
  }) async {
    if (ingredients.isEmpty) {
      state = state.copyWith(
        error: 'Please enter at least one ingredient.',
        errorTitle: 'Missing Ingredients',
        suggestions: [],
      );
      return;
    }

    // Store ingredients and mealType for back navigation
    state = state.copyWith(
      isLoading: true,
      clearError: true,
      ingredients: ingredients,
      mealType: mealType,
    );

    try {
      final suggestions = await _geminiService.suggestRecipesFromIngredients(
        availableIngredients: ingredients,
        mealType: mealType,
      );

      state = state.copyWith(isLoading: false, suggestions: suggestions);
    } on GeminiException catch (e) {
      debugPrint('Gemini error getting suggestions: $e');
      state = state.copyWith(
        isLoading: false,
        error: e.userFriendlyMessage,
        errorTitle: e.errorTitle,
        suggestions: [],
      );
    } catch (e) {
      debugPrint('Error getting suggestions: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to get recipe suggestions.',
        errorTitle: 'Request Failed',
        suggestions: [],
      );
    }
  }

  /// Clear suggestions but keep ingredients (for back navigation)
  void clearSuggestions() {
    state = state.copyWith(suggestions: [], clearError: true);
  }

  /// Clear everything including ingredients
  void clear() {
    state = const RecipeSuggestionsState();
  }
}

/// Recipe suggestions provider
final recipeSuggestionsProvider =
    StateNotifierProvider<RecipeSuggestionsNotifier, RecipeSuggestionsState>((
      ref,
    ) {
      final geminiService = ref.watch(geminiServiceProvider);
      return RecipeSuggestionsNotifier(geminiService);
    });
