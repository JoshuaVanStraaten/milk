import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/recipe.dart';
import '../../providers/recipe_provider.dart';

/// Card widget for displaying generated recipe results
class RecipeResultCard extends StatelessWidget {
  final Recipe recipe;
  final RecipeGenerationStep currentStep;
  final bool isLoading;
  final VoidCallback onStartMatching;
  final Function(int index) onMatchIngredient;
  final VoidCallback onExportToList;
  final VoidCallback onSaveRecipe;
  final VoidCallback onReset;
  final Function(String retailer)? onReMatchForStore;

  const RecipeResultCard({
    super.key,
    required this.recipe,
    required this.currentStep,
    required this.isLoading,
    required this.onStartMatching,
    required this.onMatchIngredient,
    required this.onExportToList,
    required this.onSaveRecipe,
    required this.onReset,
    this.onReMatchForStore,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Recipe header card
            _buildHeaderCard(context, isDark),

            const SizedBox(height: 16),

            // Ingredients section
            _buildIngredientsSection(context, isDark),

            const SizedBox(height: 16),

            // Instructions section
            _buildInstructionsSection(context, isDark),

            const SizedBox(height: 24),

            // Action buttons
            _buildActionButtons(context, isDark),
          ],
        ),
        // Loading overlay for re-matching
        if (isLoading)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Matching ingredients...',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHeaderCard(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  recipe.recipeName,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              IconButton(
                onPressed: onReset,
                icon: const Icon(Icons.close, color: Colors.white70),
                tooltip: 'Start over',
              ),
            ],
          ),
          if (recipe.recipeDescription != null) ...[
            const SizedBox(height: 8),
            Text(
              recipe.recipeDescription!,
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              if (recipe.formattedTotalTime.isNotEmpty)
                _buildInfoChip(Icons.timer, recipe.formattedTotalTime),
              _buildInfoChip(Icons.people, '${recipe.servings} servings'),
              if (recipe.difficulty != null)
                _buildInfoChip(Icons.signal_cellular_alt, recipe.difficulty!),
              if (recipe.cuisineType != null)
                _buildInfoChip(Icons.public, recipe.cuisineType!),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIngredientsSection(BuildContext context, bool isDark) {
    final isMatching = currentStep == RecipeGenerationStep.matching;
    final showMatchInfo =
        currentStep == RecipeGenerationStep.review || isMatching;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shopping_basket, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
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
              const Spacer(),
              if (showMatchInfo)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${recipe.matchedIngredientsCount}/${recipe.ingredients.length} matched',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
          // Re-match for store dropdown (only in review/matching step)
          if (showMatchInfo && onReMatchForStore != null) ...[
            const SizedBox(height: 12),
            _buildStoreSelector(context, isDark),
          ],
          const SizedBox(height: 12),
          ...recipe.ingredients.asMap().entries.map((entry) {
            final index = entry.key;
            final ingredient = entry.value;
            return _buildIngredientItem(
              context,
              ingredient,
              index,
              isMatching,
              isDark,
            );
          }),
          if (showMatchInfo && recipe.estimatedTotalPrice > 0) ...[
            const Divider(height: 24),
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
          ],
        ],
      ),
    );
  }

  Widget _buildStoreSelector(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.backgroundDark : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? AppColors.textDisabledDark : AppColors.textDisabled,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.store,
            size: 18,
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Text(
            'Re-match for:',
            style: TextStyle(
              fontSize: 13,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildStoreChip('All Stores', null, isDark),
                  const SizedBox(width: 6),
                  _buildStoreChip('Pick n Pay', AppConstants.pickNPay, isDark),
                  const SizedBox(width: 6),
                  _buildStoreChip(
                    'Woolworths',
                    AppConstants.woolworths,
                    isDark,
                  ),
                  const SizedBox(width: 6),
                  _buildStoreChip('Shoprite', AppConstants.shoprite, isDark),
                  const SizedBox(width: 6),
                  _buildStoreChip('Checkers', AppConstants.checkers, isDark),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreChip(String label, String? retailer, bool isDark) {
    return GestureDetector(
      onTap: () {
        if (onReMatchForStore != null) {
          onReMatchForStore!(retailer ?? '');
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildIngredientItem(
    BuildContext context,
    RecipeIngredient ingredient,
    int index,
    bool isMatching,
    bool isDark,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bullet or checkbox
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            child: ingredient.isMatched
                ? const Icon(
                    Icons.check_circle,
                    size: 18,
                    color: AppColors.success,
                  )
                : Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                      shape: BoxShape.circle,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          // Ingredient details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ingredient.displayString,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                  ),
                ),
                if (ingredient.isMatched &&
                    ingredient.matchedProductName != null)
                  Text(
                    '${ingredient.matchedProductName} • ${ingredient.formattedPrice}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.success,
                    ),
                  ),
                if (ingredient.isOptional)
                  Text(
                    'Optional',
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          // Match button (only in matching mode)
          if (isMatching)
            TextButton(
              onPressed: () => onMatchIngredient(index),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 32),
              ),
              child: Text(
                ingredient.isMatched ? 'Change' : 'Match',
                style: TextStyle(
                  fontSize: 12,
                  color: ingredient.isMatched
                      ? AppColors.textSecondary
                      : AppColors.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInstructionsSection(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.format_list_numbered,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
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
            ],
          ),
          const SizedBox(height: 12),
          ...recipe.instructions.asMap().entries.map((entry) {
            final index = entry.key;
            final instruction = entry.value;
            return _buildInstructionItem(index + 1, instruction, isDark);
          }),
        ],
      ),
    );
  }

  Widget _buildInstructionItem(
    int stepNumber,
    String instruction,
    bool isDark,
  ) {
    // Remove leading "Step X:" if present (since we're adding our own numbering)
    String cleanInstruction = instruction;
    final stepPattern = RegExp(r'^Step\s*\d+\s*[:\.]\s*', caseSensitive: false);
    cleanInstruction = instruction.replaceFirst(stepPattern, '');

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
              '$stepNumber',
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
              cleanInstruction,
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
  }

  Widget _buildActionButtons(BuildContext context, bool isDark) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    switch (currentStep) {
      case RecipeGenerationStep.review:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: onStartMatching,
              icon: const Icon(Icons.shopping_cart),
              label: const Text('Match Ingredients to Products'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onSaveRecipe,
                    icon: const Icon(Icons.bookmark_add),
                    label: const Text('Save Recipe'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextButton.icon(
                    onPressed: onReset,
                    icon: const Icon(Icons.refresh),
                    label: const Text('New Recipe'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );

      case RecipeGenerationStep.matching:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: onExportToList,
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('Export to Shopping List'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onSaveRecipe,
                    icon: const Icon(Icons.bookmark_add),
                    label: const Text('Save'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextButton.icon(
                    onPressed: onReset,
                    icon: const Icon(Icons.refresh),
                    label: const Text('New Recipe'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );

      default:
        return const SizedBox();
    }
  }
}
