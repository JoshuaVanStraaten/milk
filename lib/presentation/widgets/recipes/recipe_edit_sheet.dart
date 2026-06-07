import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/recipe.dart';
import '../../providers/recipe_provider.dart';
import '../common/review_prompt.dart';

Future<void> showRecipeEditSheet({
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
    builder: (_) => UncontrolledProviderScope(
      container: ProviderScope.containerOf(context),
      child: RecipeEditSheet(recipe: recipe, isDark: isDark),
    ),
  );
}

class RecipeEditSheet extends ConsumerStatefulWidget {
  final Recipe recipe;
  final bool isDark;

  const RecipeEditSheet({
    super.key,
    required this.recipe,
    required this.isDark,
  });

  @override
  ConsumerState<RecipeEditSheet> createState() => _RecipeEditSheetState();
}

class _RecipeEditSheetState extends ConsumerState<RecipeEditSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _instructionsController;
  late int _servings;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.recipe.recipeName);
    _instructionsController = TextEditingController(
      text: widget.recipe.instructions.join('\n'),
    );
    _servings = widget.recipe.servings.clamp(1, 12);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final instructions = _instructionsController.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    setState(() => _isSaving = true);

    try {
      await ref
          .read(recipeRepositoryProvider)
          .saveRecipe(
            widget.recipe.copyWith(
              recipeName: _nameController.text.trim(),
              servings: _servings,
              instructions: instructions,
            ),
          );
      ref.invalidate(userRecipesProvider);
      if (widget.recipe.recipeId != null) {
        ref.invalidate(recipeByIdProvider(widget.recipe.recipeId!));
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recipe updated'),
          backgroundColor: AppColors.success,
        ),
      );
      await showReviewPromptIfNeeded(context, ref);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update recipe: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    final bgColor = widget.isDark ? AppColors.backgroundDark : Colors.white;
    final textColor = widget.isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimary;
    final subtitleColor = widget.isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;

    return Container(
      constraints: BoxConstraints(
        maxHeight:
            MediaQuery.of(context).size.height * (keyboardOpen ? 0.9 : 0.8),
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: widget.isDark
                    ? AppColors.textDisabledDark
                    : AppColors.textDisabled,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Edit recipe',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _isSaving
                      ? null
                      : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      maxLength: 100,
                      enabled: !_isSaving,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Recipe name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(
                          'Servings',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: !_isSaving && _servings > 1
                              ? () => setState(() => _servings--)
                              : null,
                          icon: const Icon(Icons.remove_circle_outline),
                          color: AppColors.primary,
                        ),
                        SizedBox(
                          width: 40,
                          child: Text(
                            '$_servings',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: !_isSaving && _servings < 12
                              ? () => setState(() => _servings++)
                              : null,
                          icon: const Icon(Icons.add_circle_outline),
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Instructions',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'One instruction per line',
                      style: TextStyle(fontSize: 12, color: subtitleColor),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _instructionsController,
                      enabled: !_isSaving,
                      minLines: 6,
                      maxLines: null,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(_isSaving ? 'Saving...' : 'Save changes'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
