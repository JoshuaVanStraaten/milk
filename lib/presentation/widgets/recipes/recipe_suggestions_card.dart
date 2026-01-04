import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/services/gemini_service.dart';

/// Card widget for displaying recipe suggestions based on ingredients
class RecipeSuggestionsCard extends StatelessWidget {
  final List<RecipeSuggestion> suggestions;
  final bool isLoading;
  final String? error;
  final Function(String recipeName) onSelectRecipe;
  final VoidCallback onBack;

  const RecipeSuggestionsCard({
    super.key,
    required this.suggestions,
    required this.isLoading,
    this.error,
    required this.onSelectRecipe,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isLoading) {
      return _buildLoadingState(isDark);
    }

    if (error != null) {
      return _buildErrorState(isDark);
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                style: IconButton.styleFrom(
                  backgroundColor: isDark
                      ? AppColors.backgroundDark
                      : Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recipe Suggestions',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Based on your ingredients',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Suggestions list
          if (suggestions.isEmpty)
            _buildEmptyState(isDark)
          else
            ...suggestions.map(
              (suggestion) => _buildSuggestionCard(context, suggestion, isDark),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            'Finding recipes...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Looking for dishes you can make',
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

  Widget _buildErrorState(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.error),
          const SizedBox(height: 16),
          Text(
            error ?? 'Something went wrong',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(
            Icons.search_off,
            size: 48,
            color: isDark ? AppColors.textDisabledDark : AppColors.textDisabled,
          ),
          const SizedBox(height: 16),
          Text(
            'No recipes found',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adding more ingredients',
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

  Widget _buildSuggestionCard(
    BuildContext context,
    RecipeSuggestion suggestion,
    bool isDark,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => onSelectRecipe(suggestion.recipeName),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Recipe name and difficulty
              Row(
                children: [
                  Expanded(
                    child: Text(
                      suggestion.recipeName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (suggestion.difficulty != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _getDifficultyColor(
                          suggestion.difficulty!,
                        ).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        suggestion.difficulty!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _getDifficultyColor(suggestion.difficulty!),
                        ),
                      ),
                    ),
                ],
              ),

              // Description
              if (suggestion.description != null) ...[
                const SizedBox(height: 8),
                Text(
                  suggestion.description!,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              const SizedBox(height: 12),

              // Time and ingredients info
              Row(
                children: [
                  if (suggestion.formattedTime.isNotEmpty) ...[
                    Icon(
                      Icons.timer,
                      size: 14,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      suggestion.formattedTime,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                  if (suggestion.usesIngredients.isNotEmpty) ...[
                    Icon(
                      Icons.check_circle,
                      size: 14,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Uses ${suggestion.usesIngredients.length} of your ingredients',
                      style: TextStyle(fontSize: 12, color: AppColors.success),
                    ),
                  ],
                ],
              ),

              // Missing ingredients
              if (suggestion.missingIngredients.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.shopping_cart_outlined,
                      size: 14,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Need: ${suggestion.missingIngredients.take(3).join(', ')}${suggestion.missingIngredients.length > 3 ? '...' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 12),

              // Generate button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => onSelectRecipe(suggestion.recipeName),
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('Generate Full Recipe'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
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
}
