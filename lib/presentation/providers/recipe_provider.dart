import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/recipe.dart';
import '../../data/repositories/recipe_repository.dart';
import '../../data/services/gemini_service.dart';

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
  final RecipeGenerationStep currentStep;

  const RecipeGenerationState({
    this.isLoading = false,
    this.generatedRecipe,
    this.error,
    this.currentStep = RecipeGenerationStep.input,
  });

  RecipeGenerationState copyWith({
    bool? isLoading,
    Recipe? generatedRecipe,
    String? error,
    RecipeGenerationStep? currentStep,
  }) {
    return RecipeGenerationState(
      isLoading: isLoading ?? this.isLoading,
      generatedRecipe: generatedRecipe ?? this.generatedRecipe,
      error: error,
      currentStep: currentStep ?? this.currentStep,
    );
  }
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

  RecipeGenerationNotifier(this._geminiService, this._repository)
    : super(const RecipeGenerationState());

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
      error: null,
      currentStep: RecipeGenerationStep.generating,
    );

    try {
      final recipe = await _geminiService.generateRecipe(
        recipeRequest: recipeRequest,
        servings: servings,
        dietaryRestrictions: dietaryRestrictions,
      );

      state = state.copyWith(generatedRecipe: recipe);

      // Auto-match ingredients to products
      if (autoMatch) {
        await _autoMatchIngredients(preferredRetailer: preferredRetailer);
      }

      state = state.copyWith(
        isLoading: false,
        currentStep: RecipeGenerationStep.review,
      );
    } catch (e) {
      debugPrint('Error generating recipe: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to generate recipe. Please try again.',
        currentStep: RecipeGenerationStep.input,
      );
    }
  }

  /// Automatically match all ingredients to best matching products
  Future<void> _autoMatchIngredients({String? preferredRetailer}) async {
    if (state.generatedRecipe == null) return;

    final ingredients = List<RecipeIngredient>.from(
      state.generatedRecipe!.ingredients,
    );

    for (int i = 0; i < ingredients.length; i++) {
      final ingredient = ingredients[i];

      try {
        // Search for matching products
        final matches = await _repository.findMatchingProducts(
          ingredientName: ingredient.ingredientName,
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

  /// Save recipe to database
  Future<Recipe?> saveRecipe() async {
    if (state.generatedRecipe == null) return null;

    state = state.copyWith(isLoading: true);

    try {
      final savedRecipe = await _repository.saveRecipe(state.generatedRecipe!);
      state = state.copyWith(isLoading: false, generatedRecipe: savedRecipe);
      return savedRecipe;
    } catch (e) {
      debugPrint('Error saving recipe: $e');
      state = state.copyWith(isLoading: false, error: 'Failed to save recipe.');
      return null;
    }
  }

  /// Export to shopping list
  /// Uses the current matched ingredients (no re-matching)
  Future<String?> exportToShoppingList({required String listName}) async {
    if (state.generatedRecipe == null) return null;

    state = state.copyWith(
      isLoading: true,
      currentStep: RecipeGenerationStep.export,
    );

    try {
      // Determine the primary store from matched ingredients
      final matchedRetailers = state.generatedRecipe!.ingredients
          .where((i) => i.matchedRetailer != null)
          .map((i) => i.matchedRetailer!)
          .toList();

      String storeName = 'Multiple Stores';
      if (matchedRetailers.isNotEmpty) {
        // Get most common retailer
        final retailerCounts = <String, int>{};
        for (final retailer in matchedRetailers) {
          retailerCounts[retailer] = (retailerCounts[retailer] ?? 0) + 1;
        }
        storeName = retailerCounts.entries
            .reduce((a, b) => a.value > b.value ? a : b)
            .key;
      }

      final listId = await _repository.exportToShoppingList(
        recipe: state.generatedRecipe!,
        listName: listName,
        storeName: storeName,
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
      return RecipeGenerationNotifier(geminiService, repository);
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

  IngredientMatchingNotifier(this._repository)
    : super(const IngredientMatchingState());

  /// Search for matching products
  Future<void> searchMatches({
    required String ingredientName,
    String? retailer,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final matches = await _repository.findMatchingProducts(
        ingredientName: ingredientName,
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
      return IngredientMatchingNotifier(repository);
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
class RecipeSuggestionsState {
  final bool isLoading;
  final List<RecipeSuggestion> suggestions;
  final String? error;
  final List<String> ingredients; // Preserve ingredients for back navigation
  final String? mealType; // Preserve meal type selection

  const RecipeSuggestionsState({
    this.isLoading = false,
    this.suggestions = const [],
    this.error,
    this.ingredients = const [],
    this.mealType,
  });

  RecipeSuggestionsState copyWith({
    bool? isLoading,
    List<RecipeSuggestion>? suggestions,
    String? error,
    List<String>? ingredients,
    String? mealType,
  }) {
    return RecipeSuggestionsState(
      isLoading: isLoading ?? this.isLoading,
      suggestions: suggestions ?? this.suggestions,
      error: error,
      ingredients: ingredients ?? this.ingredients,
      mealType: mealType ?? this.mealType,
    );
  }
}

/// Recipe suggestions notifier
class RecipeSuggestionsNotifier extends StateNotifier<RecipeSuggestionsState> {
  final GeminiService _geminiService;

  RecipeSuggestionsNotifier(this._geminiService)
    : super(const RecipeSuggestionsState());

  /// Get recipe suggestions from available ingredients
  Future<void> getSuggestions({
    required List<String> ingredients,
    String? mealType,
  }) async {
    if (ingredients.isEmpty) {
      state = state.copyWith(
        error: 'Please enter at least one ingredient.',
        suggestions: [],
      );
      return;
    }

    // Store ingredients and mealType for back navigation
    state = state.copyWith(
      isLoading: true,
      error: null,
      ingredients: ingredients,
      mealType: mealType,
    );

    try {
      final suggestions = await _geminiService.suggestRecipesFromIngredients(
        availableIngredients: ingredients,
        mealType: mealType,
      );

      state = state.copyWith(isLoading: false, suggestions: suggestions);
    } catch (e) {
      debugPrint('Error getting suggestions: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to get recipe suggestions.',
        suggestions: [],
      );
    }
  }

  /// Clear suggestions but keep ingredients (for back navigation)
  void clearSuggestions() {
    state = state.copyWith(suggestions: [], error: null);
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
