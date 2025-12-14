import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../providers/list_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/animations.dart';
import '../../widgets/common/app_snackbar.dart';

class CreateListScreen extends ConsumerStatefulWidget {
  const CreateListScreen({super.key});

  @override
  ConsumerState<CreateListScreen> createState() => _CreateListScreenState();
}

class _CreateListScreenState extends ConsumerState<CreateListScreen> {
  final _formKey = GlobalKey<FormState>();
  final _listNameController = TextEditingController();

  String _selectedStore = AppConstants.pickNPay;
  String _selectedColor = 'Green';

  @override
  void dispose() {
    _listNameController.dispose();
    super.dispose();
  }

  Future<void> _handleCreateList() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    AppHaptics.mediumTap();

    final listNotifier = ref.read(listNotifierProvider.notifier);

    final list = await listNotifier.createList(
      listName: _listNameController.text.trim(),
      storeName: _selectedStore,
      listColour: _selectedColor,
    );

    if (mounted && list != null) {
      AppHaptics.success();
      AppSnackbar.success(context, message: 'Created list: ${list.listName}');

      // Navigate to list detail
      context.pushReplacement('/lists/${list.shoppingListId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final listState = ref.watch(listNotifierProvider);
    final isLoading = listState.isLoading;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Create Shopping List')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // List Name
              AppTextField(
                label: 'List Name',
                hint: 'e.g., Weekly Groceries',
                controller: _listNameController,
                prefixIcon: Icons.list_alt,
                validator: (value) =>
                    Validators.required(value, fieldName: 'List name'),
              ),

              const SizedBox(height: 24),

              // Store Selector
              Text(
                'Primary Store',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'You can add items from any store to this list',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButton<String>(
                  value: _selectedStore,
                  isExpanded: true,
                  underline: const SizedBox(),
                  icon: const Icon(Icons.arrow_drop_down),
                  dropdownColor: isDark
                      ? AppColors.surfaceDarkMode
                      : AppColors.surface,
                  items: AppConstants.retailers.map((String store) {
                    return DropdownMenuItem<String>(
                      value: store,
                      child: Text(store),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      AppHaptics.selection();
                      setState(() {
                        _selectedStore = newValue;
                      });
                    }
                  },
                ),
              ),

              const SizedBox(height: 24),

              // Color Selector
              Text(
                'Choose Color',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),

              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: AppConstants.listColors.entries.map((entry) {
                  final colorName = entry.key;
                  final colorValue = entry.value;
                  final isSelected = _selectedColor == colorName;

                  return GestureDetector(
                    onTap: () {
                      AppHaptics.selection();
                      setState(() {
                        _selectedColor = colorName;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Color(colorValue),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? (isDark ? Colors.white : AppColors.textPrimary)
                              : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: Color(colorValue).withOpacity(0.4),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: isSelected
                            ? const Icon(Icons.check, color: Colors.white)
                            : const SizedBox(),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 40),

              // Create Button
              AppButton(
                text: 'Create List',
                onPressed: isLoading ? null : _handleCreateList,
                isLoading: isLoading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
