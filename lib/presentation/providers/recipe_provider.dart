// lib/presentation/providers/recipe_provider.dart
//
// UPDATED: Ingredient matching now uses LiveApiService (live retailer APIs)
// instead of province-based DB RPC. All method signatures preserved for
// recipe_screen.dart compatibility.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/recipe.dart';
import '../../data/models/live_product.dart';
import '../../data/repositories/recipe_repository.dart';
import '../../data/services/gemini_service.dart';
import '../../data/services/image_lookup_service.dart';
import 'store_provider.dart'; // includes smartMatchingServiceProvider

// =============================================================================
// SERVICE PROVIDERS
// =============================================================================

/// Gemini service provider
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

class RecipeGenerationState {
  final bool isLoading;
  final Recipe? generatedRecipe;
  final String? error;
  final String? errorTitle;
  final RecipeGenerationStep currentStep;
  final String? matchedRetailer;
  final String?
  matchingProgressText; // e.g. "Searching Pick n Pay for Chicken Breast..."
  final int matchingTotal; // total ingredients to match
  final int matchingCurrent; // current ingredient being matched

  const RecipeGenerationState({
    this.isLoading = false,
    this.generatedRecipe,
    this.error,
    this.errorTitle,
    this.currentStep = RecipeGenerationStep.input,
    this.matchedRetailer,
    this.matchingProgressText,
    this.matchingTotal = 0,
    this.matchingCurrent = 0,
  });

  RecipeGenerationState copyWith({
    bool? isLoading,
    Recipe? generatedRecipe,
    String? error,
    String? errorTitle,
    RecipeGenerationStep? currentStep,
    String? matchedRetailer,
    String? matchingProgressText,
    int? matchingTotal,
    int? matchingCurrent,
    bool clearError = false,
    bool clearProgress = false,
  }) {
    return RecipeGenerationState(
      isLoading: isLoading ?? this.isLoading,
      generatedRecipe: generatedRecipe ?? this.generatedRecipe,
      error: clearError ? null : (error ?? this.error),
      errorTitle: clearError ? null : (errorTitle ?? this.errorTitle),
      currentStep: currentStep ?? this.currentStep,
      matchedRetailer: matchedRetailer ?? this.matchedRetailer,
      matchingProgressText: clearProgress
          ? null
          : (matchingProgressText ?? this.matchingProgressText),
      matchingTotal: matchingTotal ?? this.matchingTotal,
      matchingCurrent: matchingCurrent ?? this.matchingCurrent,
    );
  }

  bool get hasError => error != null;
  bool get isMatching => matchingTotal > 0 && matchingCurrent > 0;
  double get matchingPercent =>
      matchingTotal > 0 ? matchingCurrent / matchingTotal : 0;
}

enum RecipeGenerationStep {
  input,
  generating,
  review,
  matching,
  export,
  complete,
}

// =============================================================================
// RECIPE GENERATION NOTIFIER
// =============================================================================

class RecipeGenerationNotifier extends StateNotifier<RecipeGenerationState> {
  final GeminiService _geminiService;
  final RecipeRepository _repository;
  final Ref _ref;

  RecipeGenerationNotifier(this._geminiService, this._repository, this._ref)
    : super(const RecipeGenerationState());

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Generate a recipe from user request
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

      // Auto-match ingredients using live API
      if (autoMatch) {
        await _autoMatchIngredients(preferredRetailer: preferredRetailer);
      }

      state = state.copyWith(
        isLoading: false,
        currentStep: RecipeGenerationStep.review,
        matchedRetailer: preferredRetailer,
      );
    } on GeminiException catch (e) {
      debugPrint('Gemini error: $e');
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
        error: e.toString(),
        errorTitle: 'Something Went Wrong',
        currentStep: RecipeGenerationStep.input,
      );
    }
  }

  /// Auto-match ingredients to products using live API search
  /// with smart filtering via ProductNameParser to avoid bad matches.
  Future<void> _autoMatchIngredients({String? preferredRetailer}) async {
    if (state.generatedRecipe == null) return;

    final api = _ref.read(liveApiServiceProvider);
    final storeSelection = _ref.read(storeSelectionProvider).value;

    if (storeSelection == null) {
      debugPrint('No store selection available — skipping ingredient matching');
      return;
    }

    final ingredients = List<RecipeIngredient>.from(
      state.generatedRecipe!.ingredients,
    );

    final retailerName = preferredRetailer ?? storeSelection.stores.keys.first;

    // Set total for progress tracking
    state = state.copyWith(
      matchingTotal: ingredients.length,
      matchingCurrent: 0,
      matchingProgressText: 'Starting ingredient matching...',
    );

    for (int i = 0; i < ingredients.length; i++) {
      final ingredient = ingredients[i];

      // Clean the search query — strip quantities, units, prep instructions
      final searchQuery = _cleanIngredientForSearch(ingredient.ingredientName);

      // Update progress
      state = state.copyWith(
        matchingCurrent: i + 1,
        matchingProgressText: 'Searching $retailerName for "$searchQuery"',
      );

      try {
        List<LiveProduct> matches;

        if (preferredRetailer != null && preferredRetailer.isNotEmpty) {
          final store = storeSelection.stores[preferredRetailer];
          if (store == null) continue;

          final response = await api.searchProducts(
            query: searchQuery,
            store: store,
            retailer: preferredRetailer,
            pageSize: 10, // Fetch more to find better matches
          );
          matches = response.products;
        } else {
          final firstRetailer = storeSelection.stores.keys.first;
          final store = storeSelection.stores[firstRetailer]!;

          final response = await api.searchProducts(
            query: searchQuery,
            store: store,
            retailer: firstRetailer,
            pageSize: 10,
          );
          matches = response.products;
        }

        matches = _resolveImages(matches, retailerName);

        // Smart match — use enhanced scoring from SmartMatchingService
        final smartMatcher = _ref.read(smartMatchingServiceProvider);
        final best = await smartMatcher.matchIngredient(
          ingredientName: searchQuery,
          candidates: matches,
          ingredientQuantity: ingredient.quantity,
          ingredientUnit: ingredient.unit,
        );

        if (best != null) {
          ingredients[i] = ingredient.copyWith(
            matchedProductIndex: '${best.retailer}:${best.name}',
            matchedProductName: best.name,
            matchedProductPrice: best.priceNumeric,
            matchedRetailer: best.retailer,
          );
          state = state.copyWith(
            matchingProgressText: '✓ Found "${best.name}" for "$searchQuery"',
          );
        } else {
          if (preferredRetailer != null && preferredRetailer.isNotEmpty) {
            ingredients[i] = ingredient.copyWith(clearMatch: true);
          }
          state = state.copyWith(
            matchingProgressText: '✗ No match for "$searchQuery"',
          );
        }
      } catch (e) {
        debugPrint(
          'Failed to match ingredient "${ingredient.ingredientName}": $e',
        );
        if (preferredRetailer != null && preferredRetailer.isNotEmpty) {
          ingredients[i] = ingredient.copyWith(clearMatch: true);
        }
      }
    }

    state = state.copyWith(
      generatedRecipe: state.generatedRecipe!.copyWith(
        ingredients: ingredients,
      ),
      matchedRetailer: preferredRetailer,
      clearProgress: true,
    );
  }

  /// Re-run auto-matching with a specific retailer
  Future<void> reMatchWithRetailer(String retailer) async {
    if (state.generatedRecipe == null) return;

    state = state.copyWith(
      isLoading: true,
      currentStep: RecipeGenerationStep.generating,
    );

    // Clear existing matches when switching retailer
    final clearedIngredients = state.generatedRecipe!.ingredients
        .map((i) => i.copyWith(clearMatch: true))
        .toList();

    state = state.copyWith(
      generatedRecipe: state.generatedRecipe!.copyWith(
        ingredients: clearedIngredients,
      ),
    );

    final preferredRetailer = retailer.isEmpty ? null : retailer;
    await _autoMatchIngredients(preferredRetailer: preferredRetailer);

    state = state.copyWith(
      isLoading: false,
      currentStep: RecipeGenerationStep.review,
      clearProgress: true,
    );
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

    // Already persisted — skip to avoid duplicate insert conflict
    if (state.generatedRecipe?.recipeId != null) {
      return state.generatedRecipe;
    }

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
      if (saveRecipe && state.generatedRecipe?.recipeId == null) {
        await this.saveRecipe();
      }

      // Determine store name from matched ingredients
      if (storeName == null || storeName.isEmpty) {
        final matchedRetailers = state.generatedRecipe!.ingredients
            .where((i) => i.matchedRetailer != null)
            .map((i) => i.matchedRetailer!)
            .toList();

        if (matchedRetailers.isNotEmpty) {
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
        error: 'Failed to export to shopping list.',
        errorTitle: 'Export Failed',
        currentStep: RecipeGenerationStep.review,
      );
      return null;
    }
  }

  void reset() {
    state = const RecipeGenerationState();
  }

  List<LiveProduct> _resolveImages(
    List<LiveProduct> products,
    String retailer,
  ) {
    final lookup = ImageLookupService.instance;
    if (!lookup.isReady) return products;
    final lower = retailer.toLowerCase();
    if (!lower.contains('checkers') && !lower.contains('shoprite')) {
      return products;
    }
    return products.map((p) {
      final cached = lookup.lookupImage(
        retailer: retailer,
        productName: p.name,
      );
      if (cached != null) return p.copyWith(imageUrl: cached);
      return p;
    }).toList();
  }

  /// Clean an ingredient name for API search.
  /// Strips quantities, units, and prep instructions so the search
  /// focuses on the actual food item.
  ///
  /// "500g, lean Beef Mince 500g" → "Beef Mince"
  /// "2 cans (400g each), Chopped Tinned Tomatoes" → "Tinned Tomatoes"
  /// "3 units, minced Garlic Cloves" → "Garlic Cloves"
  static String _cleanIngredientForSearch(String ingredientName) {
    var cleaned = ingredientName;

    // Remove leading quantity + unit: "500g, " or "2 cans (400g each), "
    cleaned = cleaned.replaceAll(
      RegExp(
        r'^\d+\.?\d*\s*(g|kg|ml|l|cups?|tbsp|tsp|units?|cans?|pieces?|cloves?|stalks?|bunch|handful)\b[,\s]*',
        caseSensitive: false,
      ),
      '',
    );

    // Remove parenthetical info: "(400g each)"
    cleaned = cleaned.replaceAll(RegExp(r'\([^)]*\)'), '');

    // Remove trailing size: "500g", "2 x 400g"
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\d+\.?\d*\s*x?\s*\d*\.?\d*\s*(g|kg|ml|l)\b',
        caseSensitive: false,
      ),
      '',
    );

    // Remove prep instructions that add noise to search
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\b(finely|roughly|freshly|thinly)?\s*(chopped|diced|minced|sliced|grated|crushed|peeled|deseeded|trimmed|halved|beaten|sifted|melted|softened|whisked|mixed|skinned|deboned|boned|pre-cut|toasted|roasted)\b',
        caseSensitive: false,
      ),
      '',
    );

    // Remove common qualifiers and cooking measures that don't help search
    cleaned = cleaned.replaceAll(
      RegExp(
        r'\b(fresh|dried|frozen|tinned|canned|large|small|medium|to taste|pinch|dash|splash|handful|bunch|knob|drizzle|squeeze)\b',
        caseSensitive: false,
      ),
      '',
    );

    // Clean up whitespace, commas, leading/trailing junk
    cleaned = cleaned.replaceAll(RegExp(r'[,\s]+'), ' ').trim();

    // If cleaning removed everything, fall back to original minus leading numbers
    if (cleaned.isEmpty || cleaned.length < 3) {
      return ingredientName.replaceAll(RegExp(r'^\d+\S*\s*,?\s*'), '').trim();
    }

    return cleaned;
  }

}

/// Recipe generation provider
final recipeGenerationProvider =
    StateNotifierProvider<RecipeGenerationNotifier, RecipeGenerationState>((
      ref,
    ) {
      final gemini = ref.watch(geminiServiceProvider);
      final repository = ref.watch(recipeRepositoryProvider);
      return RecipeGenerationNotifier(gemini, repository, ref);
    });

// =============================================================================
// INGREDIENT MATCHING (manual search from matching sheet)
// =============================================================================

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

/// Ingredient matching notifier — uses live API search
class IngredientMatchingNotifier
    extends StateNotifier<IngredientMatchingState> {
  final Ref _ref;

  IngredientMatchingNotifier(this._ref)
    : super(const IngredientMatchingState());

  /// Search for matching products via live API
  Future<void> searchMatches({
    required String ingredientName,
    String? retailer,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final api = _ref.read(liveApiServiceProvider);
      final storeSelection = _ref.read(storeSelectionProvider).value;

      if (storeSelection == null) {
        state = state.copyWith(
          isLoading: false,
          error: 'No stores selected. Complete store setup first.',
          matches: [],
        );
        return;
      }

      List<LiveProduct> products;

      if (retailer != null && retailer.isNotEmpty) {
        final store = storeSelection.stores[retailer];
        if (store == null) {
          state = state.copyWith(isLoading: false, matches: []);
          return;
        }

        final response = await api.searchProducts(
          query: ingredientName,
          store: store,
          retailer: retailer,
          pageSize: 10,
        );
        products = response.products;
        products = _resolveImages(products, retailer);
      } else {
        // Search all retailers in parallel
        final results = await api.compareProduct(
          productName: ingredientName,
          stores: storeSelection.stores,
        );

        products = [];
        for (final entry in results.entries) {
          final resolved = _resolveImages(entry.value, entry.key);
          products.addAll(resolved);
        }
      }

      // Convert LiveProduct → IngredientProductMatch
      final matches = products
          .map(
            (p) => IngredientProductMatch(
              productIndex: '${p.retailer}:${p.name}',
              productName: p.name,
              productPrice: p.price,
              productImageUrl: p.imageUrl,
              retailer: p.retailer,
              similarityScore: 1.0,
            ),
          )
          .toList();

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

  void clearMatches() {
    state = const IngredientMatchingState();
  }

  List<LiveProduct> _resolveImages(
    List<LiveProduct> products,
    String retailer,
  ) {
    final lookup = ImageLookupService.instance;
    if (!lookup.isReady) return products;
    final lower = retailer.toLowerCase();
    if (!lower.contains('checkers') && !lower.contains('shoprite')) {
      return products;
    }
    return products.map((p) {
      final cached = lookup.lookupImage(
        retailer: retailer,
        productName: p.name,
      );
      if (cached != null) return p.copyWith(imageUrl: cached);
      return p;
    }).toList();
  }
}

/// Ingredient matching provider
final ingredientMatchingProvider =
    StateNotifierProvider<IngredientMatchingNotifier, IngredientMatchingState>((
      ref,
    ) {
      return IngredientMatchingNotifier(ref);
    });

// =============================================================================
// USER RECIPES
// =============================================================================

final userRecipesProvider = FutureProvider<List<Recipe>>((ref) async {
  final repository = ref.watch(recipeRepositoryProvider);
  return repository.getUserRecipes();
});

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

class RecipeSuggestionsState {
  final bool isLoading;
  final List<RecipeSuggestion> suggestions;
  final String? error;
  final String? errorTitle;
  final List<String> ingredients; // Preserve for back navigation
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

  bool get hasError => error != null;
}

class RecipeSuggestionsNotifier extends StateNotifier<RecipeSuggestionsState> {
  final GeminiService _geminiService;

  RecipeSuggestionsNotifier(this._geminiService)
    : super(const RecipeSuggestionsState());

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

final recipeSuggestionsProvider =
    StateNotifierProvider<RecipeSuggestionsNotifier, RecipeSuggestionsState>((
      ref,
    ) {
      final geminiService = ref.watch(geminiServiceProvider);
      return RecipeSuggestionsNotifier(geminiService);
    });
