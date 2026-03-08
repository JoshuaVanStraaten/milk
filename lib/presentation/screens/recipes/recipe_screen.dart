import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../providers/recipe_provider.dart';
import '../../providers/list_provider.dart';
import '../../../data/models/recipe.dart';
import '../../widgets/recipes/recipe_input_card.dart';
import '../../widgets/recipes/recipe_result_card.dart';
import '../../widgets/recipes/ingredient_matching_sheet.dart';
import '../../widgets/recipes/ingredients_input_card.dart';
import '../../widgets/recipes/recipe_suggestions_card.dart';
import '../../widgets/common/ai_error_dialog.dart';

/// Main screen for AI recipe generation
class RecipeScreen extends ConsumerStatefulWidget {
  const RecipeScreen({super.key});

  @override
  ConsumerState<RecipeScreen> createState() => _RecipeScreenState();
}

class _RecipeScreenState extends ConsumerState<RecipeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Recipes'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.restaurant_menu), text: 'Generate Recipe'),
            Tab(icon: Icon(Icons.bookmark), text: 'Saved Recipes'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [_GenerateRecipeTab(), _SavedRecipesTab()],
      ),
    );
  }
}

/// Tab for generating new recipes
class _GenerateRecipeTab extends ConsumerStatefulWidget {
  const _GenerateRecipeTab();

  @override
  ConsumerState<_GenerateRecipeTab> createState() => _GenerateRecipeTabState();
}

class _GenerateRecipeTabState extends ConsumerState<_GenerateRecipeTab> {
  bool _useIngredientsMode = false;

  @override
  Widget build(BuildContext context) {
    // Listen for recipe generation errors
    ref.listen<RecipeGenerationState>(recipeGenerationProvider, (prev, next) {
      if (next.hasError && prev?.error != next.error) {
        showAIErrorDialog(
          context,
          title: next.errorTitle ?? 'Error',
          message: next.error!,
          onDismiss: () =>
              ref.read(recipeGenerationProvider.notifier).clearError(),
        );
      }
    });

    // Listen for recipe suggestions errors (from "Use Ingredients" mode)
    ref.listen<RecipeSuggestionsState>(recipeSuggestionsProvider, (prev, next) {
      if (next.hasError && prev?.error != next.error) {
        showAIErrorDialog(
          context,
          title: next.errorTitle ?? 'Error',
          message: next.error!,
          onDismiss: () =>
              ref.read(recipeSuggestionsProvider.notifier).clearError(),
        );
      }
    });

    final state = ref.watch(recipeGenerationProvider);
    final suggestionsState = ref.watch(recipeSuggestionsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mode selector (Recipe from name vs From ingredients)
          // Only show when in input step
          if (state.currentStep == RecipeGenerationStep.input &&
              !suggestionsState.isLoading &&
              suggestionsState.suggestions.isEmpty)
            _buildModeSelector(context, isDark),

          const SizedBox(height: 16),

          // Main content based on step and mode
          _buildContent(context, ref, state, suggestionsState, isDark),
        ],
      ),
    );
  }

  Widget _buildModeSelector(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ModeButton(
              icon: Icons.search,
              label: 'Find Recipe',
              isSelected: !_useIngredientsMode,
              onTap: () {
                setState(() => _useIngredientsMode = false);
              },
            ),
          ),
          Expanded(
            child: _ModeButton(
              icon: Icons.kitchen,
              label: 'Use Ingredients',
              isSelected: _useIngredientsMode,
              onTap: () {
                setState(() => _useIngredientsMode = true);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    RecipeGenerationState state,
    RecipeSuggestionsState suggestionsState,
    bool isDark,
  ) {
    // If we have suggestions, show them
    if (suggestionsState.isLoading ||
        suggestionsState.suggestions.isNotEmpty ||
        suggestionsState.error != null) {
      return RecipeSuggestionsCard(
        suggestions: suggestionsState.suggestions,
        isLoading: suggestionsState.isLoading,
        error: suggestionsState.error,
        onSelectRecipe: (recipeName) {
          // Clear everything and generate full recipe
          ref.read(recipeSuggestionsProvider.notifier).clear();
          ref
              .read(recipeGenerationProvider.notifier)
              .generateRecipe(recipeRequest: recipeName, servings: 4);
        },
        onBack: () {
          // Only clear suggestions, keep ingredients for editing
          ref.read(recipeSuggestionsProvider.notifier).clearSuggestions();
        },
      );
    }

    switch (state.currentStep) {
      case RecipeGenerationStep.input:
        if (_useIngredientsMode) {
          return IngredientsInputCard(
            initialIngredients: suggestionsState.ingredients,
            initialMealType: suggestionsState.mealType,
            onGetSuggestions: (ingredients, mealType) {
              ref
                  .read(recipeSuggestionsProvider.notifier)
                  .getSuggestions(ingredients: ingredients, mealType: mealType);
            },
            onGenerateRecipe: (request, servings, dietary) {
              ref
                  .read(recipeGenerationProvider.notifier)
                  .generateRecipe(
                    recipeRequest: request,
                    servings: servings,
                    dietaryRestrictions: dietary,
                  );
            },
          );
        }
        return RecipeInputCard(
          onGenerate: (request, servings, dietary) {
            ref
                .read(recipeGenerationProvider.notifier)
                .generateRecipe(
                  recipeRequest: request,
                  servings: servings,
                  dietaryRestrictions: dietary,
                );
          },
        );

      case RecipeGenerationStep.generating:
        return _buildLoadingState(state, isDark);

      case RecipeGenerationStep.review:
      case RecipeGenerationStep.matching:
      case RecipeGenerationStep.export:
        if (state.generatedRecipe != null) {
          return RecipeResultCard(
            recipe: state.generatedRecipe!,
            currentStep: state.currentStep,
            isLoading: state.isLoading,
            onStartMatching: () {
              ref
                  .read(recipeGenerationProvider.notifier)
                  .startIngredientMatching();
            },
            onMatchIngredient: (index) {
              _showIngredientMatchingSheet(
                context,
                ref,
                state.generatedRecipe!.ingredients[index],
                index,
              );
            },
            onExportToList: () {
              _showExportDialog(context, ref, state.generatedRecipe!);
            },
            onSaveRecipe: () async {
              final saved = await ref
                  .read(recipeGenerationProvider.notifier)
                  .saveRecipe();
              if (saved != null && context.mounted) {
                // Refresh the saved recipes list
                ref.invalidate(userRecipesProvider);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Recipe saved!'),
                    backgroundColor: AppColors.success,
                  ),
                );
              }
            },
            onReset: () {
              ref.read(recipeGenerationProvider.notifier).reset();
            },
            onReMatchForStore: (retailer) {
              ref
                  .read(recipeGenerationProvider.notifier)
                  .reMatchWithRetailer(retailer);
            },
          );
        }
        return const SizedBox();

      case RecipeGenerationStep.complete:
        return _buildCompleteState(context, ref, isDark);
    }
  }

  Widget _buildLoadingState(RecipeGenerationState state, bool isDark) {
    final isMatching = state.isMatching;
    final progressText = state.matchingProgressText;
    final percent = state.matchingPercent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon / animated indicator
          if (isMatching) ...[
            // Progress ring — large, clean
            SizedBox(
              width: 80,
              height: 80,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: percent),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
                builder: (context, value, _) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // Track
                      SizedBox(
                        width: 80,
                        height: 80,
                        child: CircularProgressIndicator(
                          value: 1.0,
                          strokeWidth: 5,
                          color:
                              (isDark
                                      ? AppColors.textDisabledDark
                                      : AppColors.textDisabled)
                                  .withValues(alpha: 0.3),
                        ),
                      ),
                      // Progress
                      SizedBox(
                        width: 80,
                        height: 80,
                        child: CircularProgressIndicator(
                          value: value,
                          strokeWidth: 5,
                          strokeCap: StrokeCap.round,
                          color: AppColors.primary,
                        ),
                      ),
                      // Percentage text
                      Text(
                        '${(value * 100).round()}%',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ] else ...[
            // Indeterminate spinner for recipe generation
            SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                strokeWidth: 4,
                strokeCap: StrokeCap.round,
                color: AppColors.primary,
              ),
            ),
          ],

          const SizedBox(height: 28),

          // Title
          Text(
            isMatching ? 'Matching ingredients' : 'Generating your recipe',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            ),
          ),

          const SizedBox(height: 8),

          // Counter chip
          if (isMatching) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${state.matchingCurrent} of ${state.matchingTotal} ingredients',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Progress text — ingredient being searched
          if (progressText != null) ...[
            Text(
              progressText,
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ] else ...[
            Text(
              'This may take a moment...',
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompleteState(BuildContext context, WidgetRef ref, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, size: 64, color: AppColors.success),
          const SizedBox(height: 16),
          Text(
            'Shopping List Created!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your ingredients have been added to your shopping list.',
            style: TextStyle(
              fontSize: 14,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: () {
                  // Refresh the lists before navigating
                  ref.invalidate(userListsProvider);
                  context.go('/lists');
                },
                icon: const Icon(Icons.list),
                label: const Text('View Shopping Lists'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  ref.read(recipeGenerationProvider.notifier).reset();
                },
                icon: const Icon(Icons.add),
                label: const Text('Generate New Recipe'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showIngredientMatchingSheet(
    BuildContext context,
    WidgetRef ref,
    RecipeIngredient ingredient,
    int index,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => IngredientMatchingSheet(
        ingredient: ingredient,
        onSelectMatch: (match) {
          ref
              .read(recipeGenerationProvider.notifier)
              .updateIngredientMatch(index, match);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showExportDialog(BuildContext context, WidgetRef ref, Recipe recipe) {
    final listNameController = TextEditingController(
      text: '${recipe.recipeName} Ingredients',
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unmatchedCount = recipe.unmatchedIngredientsCount;
    final matchedCount = recipe.matchedIngredientsCount;
    final totalIngredients = recipe.ingredients.length;
    bool saveRecipe = true; // Default to saving the recipe

    // Determine the current store from matched ingredients
    // Get the most common retailer among matched items
    String currentStore = 'Multiple Stores';
    final matchedRetailers = recipe.ingredients
        .where((i) => i.matchedRetailer != null)
        .map((i) => i.matchedRetailer!)
        .toList();

    if (matchedRetailers.isNotEmpty) {
      // Count occurrences of each retailer
      final retailerCounts = <String, int>{};
      for (final retailer in matchedRetailers) {
        retailerCounts[retailer] = (retailerCounts[retailer] ?? 0) + 1;
      }
      // Get the most common one
      final sortedRetailers = retailerCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      // If all matched items are from one store, show that store
      // Otherwise show "Multiple Stores"
      if (sortedRetailers.length == 1) {
        currentStore = sortedRetailers.first.key;
      } else {
        // Check if majority (>80%) are from one store
        final topCount = sortedRetailers.first.value;
        if (topCount / matchedRetailers.length > 0.8) {
          currentStore = '${sortedRetailers.first.key} (mostly)';
        }
      }
    } else {
      currentStore = 'No items matched';
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Export to Shopping List'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: listNameController,
                  decoration: const InputDecoration(
                    labelText: 'List Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // Show current store (read-only)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.surfaceDarkMode
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? AppColors.textDisabledDark
                          : AppColors.textDisabled,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.store,
                        size: 20,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Store: ',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondary,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          currentStore,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),
                Text(
                  'Use "Re-match for store" on the recipe screen to change store.',
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                  ),
                ),

                const SizedBox(height: 16),

                // Match status
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: unmatchedCount > 0
                        ? AppColors.warning.withValues(alpha: 0.1)
                        : AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: unmatchedCount > 0
                          ? AppColors.warning.withValues(alpha: 0.3)
                          : AppColors.success.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        unmatchedCount > 0
                            ? Icons.info_outline
                            : Icons.check_circle_outline,
                        color: unmatchedCount > 0
                            ? AppColors.warning
                            : AppColors.success,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          unmatchedCount > 0
                              ? '$matchedCount of $totalIngredients items matched. $unmatchedCount items will be added as custom items.'
                              : 'All $totalIngredients items matched!',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Price estimate with disclaimer
                if (recipe.estimatedTotalPrice > 0) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.surfaceDarkMode
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Estimated Total',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppColors.textPrimaryDark
                                    : AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              'R${recipe.estimatedTotalPrice.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '💡 This is based on full product prices. For example, if a recipe needs 50g pepper but the smallest pack is 250g, you\'ll pay for the full pack.',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondary,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // Save recipe checkbox
                CheckboxListTile(
                  value: saveRecipe,
                  onChanged: (value) {
                    setState(() {
                      saveRecipe = value ?? true;
                    });
                  },
                  title: Text(
                    'Save recipe to My Recipes',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    'AI-generated recipes may vary each time',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),

                // Option to go back and match more
                if (unmatchedCount > 0) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      // Go to matching step
                      ref
                          .read(recipeGenerationProvider.notifier)
                          .startIngredientMatching();
                    },
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Match items manually first'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);

                // Save recipe if checkbox is checked
                if (saveRecipe) {
                  await ref
                      .read(recipeGenerationProvider.notifier)
                      .saveRecipe();
                  ref.invalidate(userRecipesProvider);
                }

                // Create the shopping list
                final listId = await ref
                    .read(recipeGenerationProvider.notifier)
                    .exportToShoppingList(listName: listNameController.text);
                if (listId != null && context.mounted) {
                  // Navigation handled by state change to complete
                }
              },
              child: const Text('Create List'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mode selection button
class _ModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? Colors.white
                  : (isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? Colors.white
                    : (isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tab for saved recipes
class _SavedRecipesTab extends ConsumerWidget {
  const _SavedRecipesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipesAsync = ref.watch(userRecipesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return recipesAsync.when(
      data: (recipes) {
        if (recipes.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.restaurant_menu,
                  size: 64,
                  color: isDark
                      ? AppColors.textDisabledDark
                      : AppColors.textDisabled,
                ),
                const SizedBox(height: 16),
                Text(
                  'No saved recipes yet',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Generate a recipe and save it to see it here',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: recipes.length,
          itemBuilder: (context, index) {
            final recipe = recipes[index];
            return _SavedRecipeCard(
              recipe: recipe,
              onDelete: () => _confirmDelete(context, ref, recipe),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text('Failed to load recipes'),
            TextButton(
              onPressed: () => ref.invalidate(userRecipesProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, Recipe recipe) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Recipe'),
        content: Text(
          'Are you sure you want to delete "${recipe.recipeName}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ref
                    .read(recipeRepositoryProvider)
                    .deleteRecipe(recipe.recipeId!);
                ref.invalidate(userRecipesProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Recipe deleted'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to delete recipe: $e'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

/// Card for displaying a saved recipe
class _SavedRecipeCard extends StatelessWidget {
  final Recipe recipe;
  final VoidCallback onDelete;

  const _SavedRecipeCard({required this.recipe, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dismissible(
      key: Key(recipe.recipeId ?? recipe.recipeName),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        onDelete();
        return false; // We handle deletion in the callback
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: () {
            _showRecipeDetailSheet(context, recipe, isDark);
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Recipe icon/image
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.restaurant,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                // Recipe details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recipe.recipeName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (recipe.formattedTotalTime.isNotEmpty) ...[
                            Icon(
                              Icons.timer,
                              size: 14,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              recipe.formattedTotalTime,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Icon(
                            Icons.people,
                            size: 14,
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${recipe.servings} servings',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      if (recipe.difficulty != null) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _getDifficultyColor(
                              recipe.difficulty!,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            recipe.difficulty!,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: _getDifficultyColor(recipe.difficulty!),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getDifficultyColor(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'easy':
        return AppColors.success;
      case 'medium':
        return AppColors.secondary;
      case 'hard':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  void _showRecipeDetailSheet(
    BuildContext context,
    Recipe recipe,
    bool isDark,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: isDark ? AppColors.backgroundDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.textDisabledDark
                      : AppColors.textDisabled,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Text(
                      recipe.recipeName,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                    if (recipe.recipeDescription != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        recipe.recipeDescription!,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    // Info chips
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        if (recipe.formattedTotalTime.isNotEmpty)
                          _buildInfoChip(
                            Icons.timer,
                            recipe.formattedTotalTime,
                            isDark,
                          ),
                        _buildInfoChip(
                          Icons.people,
                          '${recipe.servings} servings',
                          isDark,
                        ),
                        if (recipe.difficulty != null)
                          _buildInfoChip(
                            Icons.signal_cellular_alt,
                            recipe.difficulty!,
                            isDark,
                          ),
                        if (recipe.cuisineType != null)
                          _buildInfoChip(
                            Icons.public,
                            recipe.cuisineType!,
                            isDark,
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Ingredients
                    Text(
                      'Ingredients',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...recipe.ingredients.map(
                      (ingredient) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.only(top: 6, right: 12),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                ingredient.displayString,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark
                                      ? AppColors.textPrimaryDark
                                      : AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Instructions
                    Text(
                      'Instructions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...recipe.instructions.asMap().entries.map((entry) {
                      final index = entry.key;
                      var instruction = entry.value;
                      // Remove leading "Step X:" if present
                      instruction = instruction.replaceFirst(
                        RegExp(r'^Step\s*\d+\s*[:\.]\s*', caseSensitive: false),
                        '',
                      );
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                instruction,
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.5,
                                  color: isDark
                                      ? AppColors.textPrimaryDark
                                      : AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
