// lib/presentation/widgets/products/add_to_list_sheet.dart
//
// Reusable bottom sheet for adding a product to an existing shopping list.
// Model-agnostic — accepts raw values so it works with both LiveProduct
// (live API) and Product (DB-backed) models.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../providers/list_provider.dart';

/// Show the "Add to List" sheet.
///
/// Works with any product source — just pass the relevant fields:
/// ```dart
/// // From LiveProduct:
/// showAddToListSheet(context, ref,
///   productName: product.name,
///   price: product.priceNumeric,
///   retailer: product.retailer,
///   specialPrice: product.hasPromo ? parsedPromoPrice : null,
///   imageUrl: product.imageUrl,
/// );
///
/// // From DB Product:
/// showAddToListSheet(context, ref,
///   productName: product.name,
///   price: product.numericPrice ?? 0,
///   retailer: retailer,
///   specialPrice: product.hasPromotion ? product.numericPromotionPrice : null,
///   imageUrl: product.imageUrl,
/// );
/// ```
void showAddToListSheet(
  BuildContext context,
  WidgetRef ref, {
  required String productName,
  required double price,
  required String retailer,
  double? specialPrice,
  String? imageUrl,
  String? priceDisplay,
  Map<String, double>? multiBuyInfo,
}) {
  // Pre-invalidate to ensure lists are fresh
  ref.invalidate(userListsProvider);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ProviderScope(
      parent: ProviderScope.containerOf(context),
      child: _AddToListSheet(
        productName: productName,
        price: price,
        retailer: retailer,
        specialPrice: specialPrice,
        imageUrl: imageUrl,
        priceDisplay: priceDisplay,
        multiBuyInfo: multiBuyInfo,
      ),
    ),
  );
}

class _AddToListSheet extends ConsumerStatefulWidget {
  final String productName;
  final double price;
  final String retailer;
  final double? specialPrice;
  final String? imageUrl;
  final String? priceDisplay;
  final Map<String, double>? multiBuyInfo;

  const _AddToListSheet({
    required this.productName,
    required this.price,
    required this.retailer,
    this.specialPrice,
    this.imageUrl,
    this.priceDisplay,
    this.multiBuyInfo,
  });

  @override
  ConsumerState<_AddToListSheet> createState() => _AddToListSheetState();
}

class _AddToListSheetState extends ConsumerState<_AddToListSheet> {
  int _quantity = 1;
  final _noteController = TextEditingController();
  final _scrollController = ScrollController();
  final _noteFocusNode = FocusNode();
  Timer? _longPressTimer;
  String? _selectedListId;
  bool _isAdding = false;

  @override
  void initState() {
    super.initState();
    _noteFocusNode.addListener(_onNoteFocus);
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _noteController.dispose();
    _scrollController.dispose();
    _noteFocusNode.dispose();
    super.dispose();
  }

  void _onNoteFocus() {
    if (_noteFocusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _startIncrement(int delta) {
    _longPressTimer?.cancel();
    _updateQuantity(delta);
    _longPressTimer = Timer(const Duration(milliseconds: 400), () {
      _longPressTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
        _updateQuantity(delta);
      });
    });
  }

  void _stopIncrement() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  void _updateQuantity(int delta) {
    FocusScope.of(context).unfocus();
    setState(() => _quantity = (_quantity + delta).clamp(1, 99));
  }

  Future<void> _handleAdd() async {
    if (_selectedListId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a list')));
      return;
    }

    setState(() => _isAdding = true);

    final quantity = _quantity.toDouble();

    final notifier = ref.read(listItemNotifierProvider.notifier);
    final item = await notifier.addItem(
      listId: _selectedListId!,
      itemName: widget.productName,
      itemPrice: widget.price,
      itemQuantity: quantity,
      itemNote: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
      itemRetailer: widget.retailer,
      itemSpecialPrice: widget.specialPrice,
      multiBuyInfo: widget.multiBuyInfo,
    );

    if (!mounted) return;

    if (item != null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${widget.productName} added to list'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      setState(() => _isAdding = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to add item. Please try again.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.surfaceDarkMode : Colors.white;
    final textColor = isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimary;
    final subtitleColor = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;

    final viewInsets = MediaQuery.of(context).viewInsets;
    final keyboardOpen = viewInsets.bottom > 0;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * (keyboardOpen ? 0.9 : 0.75),
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Product info header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.grey.withValues(alpha: 0.2),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: widget.imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: widget.imageUrl!,
                          fit: BoxFit.contain,
                          errorWidget: (_, __, ___) =>
                              const Icon(Icons.shopping_bag_outlined, size: 24),
                        )
                      : const Icon(Icons.shopping_bag_outlined, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.productName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.retailer} · ${widget.priceDisplay ?? 'R${widget.price.toStringAsFixed(2)}'}',
                        style: TextStyle(fontSize: 13, color: subtitleColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // List selection
          Flexible(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add to list',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // User's lists
                  _buildListSelector(isDark, textColor, subtitleColor),

                  const SizedBox(height: 20),

                  // Quantity stepper
                  Row(
                    children: [
                      Text(
                        'Quantity',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: textColor,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTapDown: (_) => _startIncrement(-1),
                        onTapUp: (_) => _stopIncrement(),
                        onTapCancel: _stopIncrement,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDark
                                ? AppColors.surfaceDarkModeLight
                                : AppColors.surface,
                          ),
                          child: Icon(
                            Icons.remove,
                            size: 18,
                            color: _quantity <= 1
                                ? (isDark ? AppColors.textDisabledDark : AppColors.textDisabled)
                                : textColor,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          '$_quantity',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTapDown: (_) => _startIncrement(1),
                        onTapUp: (_) => _stopIncrement(),
                        onTapCancel: _stopIncrement,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.1),
                          ),
                          child: const Icon(
                            Icons.add,
                            size: 18,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Note
                  Text(
                    'Note',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _noteController,
                    focusNode: _noteFocusNode,
                    decoration: InputDecoration(
                      hintText: 'e.g. Get the low-fat version',
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ),

          // Sticky add button
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + (keyboardOpen ? viewInsets.bottom : MediaQuery.of(context).padding.bottom)),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isAdding ? null : _handleAdd,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isAdding
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Add to List',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListSelector(bool isDark, Color textColor, Color subtitleColor) {
    final listsAsync = ref.watch(userListsProvider);

    return listsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'Failed to load lists',
          style: TextStyle(color: AppColors.error),
        ),
      ),
      data: (lists) {
        if (lists.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.surfaceDarkModeLight
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(Icons.list_alt, size: 32, color: subtitleColor),
                const SizedBox(height: 8),
                Text('No lists yet', style: TextStyle(color: subtitleColor)),
                const SizedBox(height: 4),
                Text(
                  'Create a list first from the Lists tab',
                  style: TextStyle(fontSize: 12, color: subtitleColor),
                ),
              ],
            ),
          );
        }

        return Column(
          children: lists.map((list) {
            final isSelected = _selectedListId == list.shoppingListId;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () {
                  setState(() => _selectedListId = list.shoppingListId);
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withValues(
                            alpha: isDark ? 0.15 : 0.06,
                          )
                        : isDark
                        ? AppColors.surfaceDarkModeLight
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.5)
                          : Colors.transparent,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.check_circle : Icons.circle_outlined,
                        color: isSelected ? AppColors.primary : subtitleColor,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              list.listName,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                            if (list.storeName.isNotEmpty)
                              Text(
                                list.storeName,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: subtitleColor,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        'R${list.totalPrice.toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 13, color: subtitleColor),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
