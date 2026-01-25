import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Card widget for recipe generation input
class RecipeInputCard extends StatefulWidget {
  final Function(String request, int servings, List<String>? dietary)
  onGenerate;

  const RecipeInputCard({super.key, required this.onGenerate});

  @override
  State<RecipeInputCard> createState() => _RecipeInputCardState();
}

class _RecipeInputCardState extends State<RecipeInputCard> {
  final _recipeController = TextEditingController();
  int _servings = 4;
  final Set<String> _selectedDietary = {};
  String? _selectedSuggestion; // Track which quick suggestion is selected

  final List<String> _dietaryOptions = [
    'Vegetarian',
    'Vegan',
    'Gluten-Free',
    'Dairy-Free',
    'Low-Carb',
    'Halal',
    'Kosher',
  ];

  final List<String> _quickSuggestions = [
    'Chicken Stir Fry',
    'Spaghetti Bolognese',
    'Butter Chicken',
    'Fish and Chips',
    'Caesar Salad',
    'Beef Tacos',
    'Vegetable Curry',
    'Grilled Salmon',
  ];

  @override
  void dispose() {
    _recipeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'What do you want to cook?',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Our AI will generate a recipe with ingredients',
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

          // Recipe input
          TextField(
            controller: _recipeController,
            decoration: InputDecoration(
              hintText: 'e.g., Chicken Stir Fry, Pasta Carbonara...',
              prefixIcon: const Icon(Icons.restaurant_menu),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: isDark ? AppColors.backgroundDark : Colors.white,
            ),
            textCapitalization: TextCapitalization.words,
            onChanged: (value) {
              setState(() {
                // Clear selection if user types something different
                if (_selectedSuggestion != null &&
                   value != _selectedSuggestion) {
                  _selectedSuggestion = null;
                }
                // Re-select if user types back to match a suggestion
                if (_quickSuggestions.contains(value)) {
                  _selectedSuggestion = value;
                }
              });
            },
            onSubmitted: (_) => _handleGenerate(),
          ),

          const SizedBox(height: 12),

          // Quick suggestions
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickSuggestions.map((suggestion) {
              final isSelected = _selectedSuggestion == suggestion;
              return ChoiceChip(
                label: Text(
                  suggestion,
                  style: TextStyle(
                    fontSize: 12,
                    color: isSelected ? Colors.white : null,
                  ),
                ),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedSuggestion = suggestion;
                      _recipeController.text = suggestion;
                    } else {
                      _selectedSuggestion = null;
                      _recipeController.clear();
                    }
                  });
                },
                selectedColor: AppColors.primary,
                backgroundColor: isDark
                    ? AppColors.backgroundDark
                    : Colors.white,
              );
            }).toList(),
          ),

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 16),

          // Servings selector
          Row(
            children: [
              Text(
                'Servings',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _servings > 1
                    ? () => setState(() => _servings--)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
                color: AppColors.primary,
              ),
              Container(
                width: 40,
                alignment: Alignment.center,
                child: Text(
                  '$_servings',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                onPressed: _servings < 12
                    ? () => setState(() => _servings++)
                    : null,
                icon: const Icon(Icons.add_circle_outline),
                color: AppColors.primary,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Dietary restrictions
          Text(
            'Dietary Requirements (optional)',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _dietaryOptions.map((option) {
              final isSelected = _selectedDietary.contains(option);
              return FilterChip(
                label: Text(
                  option,
                  style: TextStyle(
                    fontSize: 12,
                    color: isSelected ? Colors.white : null,
                  ),
                ),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedDietary.add(option);
                    } else {
                      _selectedDietary.remove(option);
                    }
                  });
                },
                selectedColor: AppColors.primary,
                checkmarkColor: Colors.white,
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          // Generate button
          FilledButton.icon(
            onPressed: _recipeController.text.trim().isNotEmpty
                ? _handleGenerate
                : null,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Generate Recipe'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleGenerate() {
    final request = _recipeController.text.trim();
    if (request.isEmpty) return;

    widget.onGenerate(
      request,
      _servings,
      _selectedDietary.isNotEmpty ? _selectedDietary.toList() : null,
    );
  }
}
