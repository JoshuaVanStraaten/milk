import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Card widget for entering ingredients to generate recipe suggestions
class IngredientsInputCard extends StatefulWidget {
  final Function(List<String> ingredients, String? mealType) onGetSuggestions;
  final Function(String recipeName, int servings, List<String>? dietary)
  onGenerateRecipe;
  final List<String> initialIngredients;
  final String? initialMealType;

  const IngredientsInputCard({
    super.key,
    required this.onGetSuggestions,
    required this.onGenerateRecipe,
    this.initialIngredients = const [],
    this.initialMealType,
  });

  @override
  State<IngredientsInputCard> createState() => _IngredientsInputCardState();
}

class _IngredientsInputCardState extends State<IngredientsInputCard> {
  final _ingredientController = TextEditingController();
  late List<String> _ingredients;
  late String? _selectedMealType;
  int _servings = 4;

  @override
  void initState() {
    super.initState();
    _ingredients = List.from(widget.initialIngredients);
    _selectedMealType = widget.initialMealType;
  }

  final List<String> _mealTypes = [
    'Breakfast',
    'Lunch',
    'Dinner',
    'Snack',
    'Dessert',
  ];

  final List<String> _commonIngredients = [
    'Chicken',
    'Beef',
    'Eggs',
    'Rice',
    'Pasta',
    'Potatoes',
    'Onions',
    'Garlic',
    'Tomatoes',
    'Cheese',
    'Milk',
    'Bread',
  ];

  @override
  void dispose() {
    _ingredientController.dispose();
    super.dispose();
  }

  void _addIngredient(String ingredient) {
    final trimmed = ingredient.trim();
    if (trimmed.isNotEmpty && !_ingredients.contains(trimmed.toLowerCase())) {
      setState(() {
        _ingredients.add(trimmed);
        _ingredientController.clear();
      });
    }
  }

  void _removeIngredient(int index) {
    setState(() {
      _ingredients.removeAt(index);
    });
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
                  Icons.kitchen,
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
                      'What ingredients do you have?',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Add ingredients and we\'ll suggest recipes',
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

          // Ingredient input
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ingredientController,
                  decoration: InputDecoration(
                    hintText: 'Add an ingredient...',
                    prefixIcon: const Icon(Icons.add_circle_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: isDark ? AppColors.backgroundDark : Colors.white,
                  ),
                  textCapitalization: TextCapitalization.words,
                  onSubmitted: _addIngredient,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: () => _addIngredient(_ingredientController.text),
                icon: const Icon(Icons.add),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.all(14),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Quick add common ingredients
          Text(
            'Quick add:',
            style: TextStyle(
              fontSize: 12,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _commonIngredients
                .where(
                  (i) => !_ingredients
                      .map((e) => e.toLowerCase())
                      .contains(i.toLowerCase()),
                )
                .take(8)
                .map((ingredient) {
                  return ActionChip(
                    label: Text(
                      ingredient,
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () => _addIngredient(ingredient),
                    backgroundColor: isDark
                        ? AppColors.backgroundDark
                        : Colors.white,
                  );
                })
                .toList(),
          ),

          const SizedBox(height: 16),

          // Added ingredients
          if (_ingredients.isNotEmpty) ...[
            Text(
              'Your ingredients (${_ingredients.length}):',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _ingredients.asMap().entries.map((entry) {
                return Chip(
                  label: Text(
                    entry.value,
                    style: const TextStyle(fontSize: 12),
                  ),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => _removeIngredient(entry.key),
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  deleteIconColor: AppColors.primary,
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],

          const Divider(),
          const SizedBox(height: 12),

          // Meal type selector
          Text(
            'What meal are you making? (optional)',
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
            children: _mealTypes.map((type) {
              final isSelected = _selectedMealType == type;
              return ChoiceChip(
                label: Text(
                  type,
                  style: TextStyle(
                    fontSize: 12,
                    color: isSelected ? Colors.white : null,
                  ),
                ),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    _selectedMealType = selected ? type : null;
                  });
                },
                selectedColor: AppColors.primary,
              );
            }).toList(),
          ),

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

          const SizedBox(height: 24),

          // Get suggestions button
          FilledButton.icon(
            onPressed: _ingredients.isNotEmpty
                ? () => widget.onGetSuggestions(_ingredients, _selectedMealType)
                : null,
            icon: const Icon(Icons.lightbulb_outline),
            label: const Text('Get Recipe Suggestions'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          if (_ingredients.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Add at least one ingredient to get started',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}
