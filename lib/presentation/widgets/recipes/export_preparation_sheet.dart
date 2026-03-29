// lib/presentation/widgets/recipes/export_preparation_sheet.dart
//
// Sprint 10a — Ingredient deselection sheet before export.
// Lets users uncheck items they already have at home before exporting
// the recipe to a shopping list. Also entry point for retailer comparison (10b).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/recipe.dart';
import '../../providers/recipe_provider.dart';
import 'retailer_comparison_sheet.dart';

/// Opens the export preparation bottom sheet.
///
/// Call this instead of the old `_showExportDialog` in recipe_screen.dart.
Future<void> showExportPreparationSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Recipe recipe,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ExportPreparationSheet(recipe: recipe, isDark: isDark),
  );
}

class _ExportPreparationSheet extends ConsumerStatefulWidget {
  final Recipe recipe;
  final bool isDark;

  const _ExportPreparationSheet({
    required this.recipe,
    required this.isDark,
  });

  @override
  ConsumerState<_ExportPreparationSheet> createState() =>
      _ExportPreparationSheetState();
}

class _ExportPreparationSheetState
    extends ConsumerState<_ExportPreparationSheet> {
  late final TextEditingController _listNameController;

  /// ingredientId → whether it's selected for export
  late final Map<String, bool> _selected;

  bool _saveRecipe = true;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _listNameController = TextEditingController(
      text: '${widget.recipe.recipeName} Ingredients',
    );
    // Only matched ingredients can be exported; start all checked.
    // Unmatched ones start false and are disabled.
    _selected = {
      for (final i in widget.recipe.ingredients)
        if (i.ingredientId != null)
          i.ingredientId!: i.isMatched,
    };
  }

  @override
  void dispose() {
    _listNameController.dispose();
    super.dispose();
  }

  int get _selectedCount =>
      _selected.values.where((v) => v).length;

  List<RecipeIngredient> get _selectedIngredients =>
      widget.recipe.ingredients
          .where((i) => i.ingredientId != null && (_selected[i.ingredientId] ?? false))
          .toList();

  Future<void> _export({List<RecipeIngredient>? ingredientOverride}) async {
    if (_listNameController.text.trim().isEmpty) return;
    setState(() => _isExporting = true);

    final notifier = ref.read(recipeGenerationProvider.notifier);

    if (ingredientOverride != null) {
      // Export using overridden ingredient matches (from comparison sheet)
      final overriddenRecipe = widget.recipe.copyWith(
        ingredients: ingredientOverride,
      );
      await notifier.exportRecipeDirectly(
        recipe: overriddenRecipe,
        listName: _listNameController.text.trim(),
        saveRecipe: _saveRecipe,
      );
    } else {
      await notifier.exportToShoppingList(
        listName: _listNameController.text.trim(),
        saveRecipe: _saveRecipe,
        selectedIngredientIds:
            _selected.entries.where((e) => e.value).map((e) => e.key).toSet(),
      );
    }

    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _openComparison() async {
    final selected = _selectedIngredients;
    if (selected.isEmpty) return;

    final chosenBasket = await showRetailerComparisonSheet(
      context: context,
      ref: ref,
      selectedIngredients: selected,
    );

    if (chosenBasket == null) return;
    if (!mounted) return;

    // Build updated ingredients using the chosen basket's matches
    final updatedIngredients = selected.map((ing) {
      final match = chosenBasket.matches[ing.ingredientId];
      if (match == null) return ing;
      return ing.copyWith(
        matchedProductIndex: match.productIndex,
        matchedProductName: match.productName,
        matchedProductPrice: match.numericPrice,
        matchedRetailer: match.retailer,
      );
    }).toList();

    await _export(ingredientOverride: updatedIngredients);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final ingredients = widget.recipe.ingredients;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.backgroundDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              // Handle bar
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),

              // Title
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(
                  children: [
                    const Icon(Icons.shopping_cart_outlined, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Export to List',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),

              // List name field
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: _listNameController,
                  decoration: InputDecoration(
                    labelText: 'List name',
                    prefixIcon: const Icon(Icons.list_alt_outlined, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    isDense: true,
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),

              Divider(
                height: 1,
                color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.12),
              ),

              // Section header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Text(
                      'Select items to include',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: isDark ? Colors.white54 : Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const Spacer(),
                    Text(
                      '$_selectedCount of ${ingredients.where((i) => i.isMatched).length} matched',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: isDark ? Colors.white.withValues(alpha: 0.38) : Colors.black.withValues(alpha: 0.38),
                          ),
                    ),
                  ],
                ),
              ),

              // Ingredient list
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: ingredients.length,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemBuilder: (context, index) {
                    final ing = ingredients[index];
                    final id = ing.ingredientId;
                    final isMatched = ing.isMatched;
                    final isChecked = id != null && (_selected[id] ?? false);

                    return CheckboxListTile(
                      value: isChecked,
                      onChanged: isMatched && id != null
                          ? (val) => setState(() => _selected[id] = val ?? false)
                          : null,
                      dense: true,
                      title: Text(
                        ing.ingredientName,
                        style: TextStyle(
                          fontSize: 13,
                          color: isMatched
                              ? null
                              : (isDark ? Colors.white.withValues(alpha: 0.38) : Colors.black.withValues(alpha: 0.38)),
                          decoration: isMatched ? null : TextDecoration.none,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: isMatched
                          ? Text(
                              ing.matchedProductName ?? '',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                          : null,
                      secondary: isMatched
                          ? Text(
                              ing.formattedPrice ?? '',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            )
                          : Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Not found',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isDark ? Colors.white.withValues(alpha: 0.38) : Colors.black.withValues(alpha: 0.38),
                                ),
                              ),
                            ),
                    );
                  },
                ),
              ),

              Divider(
                height: 1,
                color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.12),
              ),

              // Save recipe toggle
              CheckboxListTile(
                value: _saveRecipe,
                onChanged: (val) => setState(() => _saveRecipe = val ?? true),
                dense: true,
                title: const Text(
                  'Save recipe to My Recipes',
                  style: TextStyle(fontSize: 13),
                ),
                controlAffinity: ListTileControlAffinity.leading,
              ),

              // Action buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: _selectedCount > 0 && !_isExporting
                          ? _openComparison
                          : null,
                      icon: const Icon(Icons.compare_arrows, size: 16),
                      label: const Text('Compare Prices'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _selectedCount > 0 && !_isExporting
                          ? () => _export()
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isExporting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Export'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
