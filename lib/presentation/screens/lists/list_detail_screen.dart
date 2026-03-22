import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/retailers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/list_item.dart';
import '../../../data/models/live_product.dart';
import '../../providers/list_provider.dart';
import '../../providers/store_provider.dart';
import '../../widgets/skeleton_loaders.dart';
import '../../widgets/animations.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/empty_states.dart';
import '../../widgets/common/lottie_loading_indicator.dart';
import '../compare/compare_sheet.dart';
import '../../widgets/lists/share_list_sheet.dart';
import '../../widgets/lists/list_comparison_sheet.dart';
import '../../widgets/lists/trip_cost_card.dart';

class ListDetailScreen extends ConsumerStatefulWidget {
  final String listId;

  const ListDetailScreen({super.key, required this.listId});

  @override
  ConsumerState<ListDetailScreen> createState() => _ListDetailScreenState();
}

class _ListDetailScreenState extends ConsumerState<ListDetailScreen> {
  final Set<String> _selectedIds = {};
  bool get _isSelectionMode => _selectedIds.isNotEmpty;

  void _exitSelectionMode() {
    setState(() => _selectedIds.clear());
  }

  void _toggleSelection(String itemId) {
    setState(() {
      if (_selectedIds.contains(itemId)) {
        _selectedIds.remove(itemId);
      } else {
        _selectedIds.add(itemId);
      }
    });
    AppHaptics.lightTap();
  }

  void _enterSelectionMode(String itemId) {
    setState(() => _selectedIds.add(itemId));
    AppHaptics.lightTap();
  }

  Future<void> _confirmBulkDelete() async {
    final count = _selectedIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $count item${count > 1 ? 's' : ''}?'),
        content: Text(
          'This will permanently remove $count item${count > 1 ? 's' : ''} from this list.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final notifier = ref.read(
        realtimeListItemsProvider(widget.listId).notifier,
      );
      for (final id in _selectedIds) {
        notifier.deleteItem(id);
      }
      AppSnackbar.success(
        context,
        message: '$count item${count > 1 ? 's' : ''} removed',
      );
      _exitSelectionMode();
    }
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(listByIdProvider(widget.listId));
    final itemsState = ref.watch(realtimeListItemsProvider(widget.listId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelectionMode,
              )
            : null,
        title: _isSelectionMode
            ? Text('${_selectedIds.length} selected')
            : listAsync.when(
                data: (list) => Text(list.listName),
                loading: () => const Text('Loading...'),
                error: (_, __) => const Text('Error'),
              ),
        backgroundColor: _isSelectionMode
            ? AppColors.primary.withValues(alpha: 0.1)
            : null,
        actions: _isSelectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.delete, color: AppColors.error),
                  onPressed: _confirmBulkDelete,
                ),
              ]
            : [
                // Real-time indicator
                if (itemsState.isRealtime)
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Tooltip(
                      message: 'Real-time sync active',
                      child:
                          Icon(Icons.sync, color: AppColors.success, size: 20),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    _showAddItemDialog(context);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () {
                    _showListOptions(context, ref, listAsync.value);
                  },
                ),
              ],
      ),
      body: listAsync.when(
        data: (list) {
          return Column(
            children: [
              // List Header with Compare button
              _ListHeader(
                list: list,
                isDark: isDark,
                onCompare: itemsState.items
                        .where((i) => !i.completedItem)
                        .isEmpty
                    ? null
                    : () => showListComparisonSheet(
                          context: context,
                          ref: ref,
                          items: itemsState.items
                              .where((i) => !i.completedItem)
                              .toList(),
                          listId: widget.listId,
                        ),
              ),

              const Divider(height: 1),

              // Trip Cost breakdown (collapsible)
              TripCostCard(items: itemsState.items, isDark: isDark),

              // Items List with real-time state
              Expanded(child: _buildItemsList(itemsState, isDark)),
            ],
          );
        },
        loading: () => const ListDetailSkeleton(),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: AppColors.error),
              const SizedBox(height: 16),
              Text(
                'Error loading list',
                style: TextStyle(
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$error',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.pop(),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          _showAddItemDialog(context);
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Item'),
      ),
    );
  }

  Widget _buildItemsList(RealtimeListItemsState itemsState, bool isDark) {
    // Error state
    if (itemsState.error != null && itemsState.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              'Error loading items',
              style: TextStyle(
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              itemsState.error!,
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                ref
                    .read(realtimeListItemsProvider(widget.listId).notifier)
                    .refresh();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // Loading state
    if (itemsState.isLoading && itemsState.items.isEmpty) {
      return const ListItemsSkeleton();
    }

    // Empty state
    if (itemsState.items.isEmpty) {
      return _buildEmptyState(context, isDark);
    }

    // Group items by retailer
    final groupedItems = _groupItemsByRetailer(itemsState.items);
    final retailers = groupedItems.keys.toList();

    // If only one retailer (or no retailer info), show flat list (but still sorted)
    if (retailers.length <= 1) {
      // Get the sorted items from the first (only) group
      final sortedItems = retailers.isNotEmpty
          ? groupedItems[retailers.first]!
          : <ListItem>[];

      return RefreshIndicator(
        onRefresh: () async {
          ref.read(realtimeListItemsProvider(widget.listId).notifier).refresh();
          ref.invalidate(listByIdProvider(widget.listId));
        },
        child: _AnimatedItemList(
          items: sortedItems,
          listId: widget.listId,
          selectedIds: _selectedIds,
          isSelectionMode: _isSelectionMode,
          onLongPress: _enterSelectionMode,
          onToggleSelect: _toggleSelection,
        ),
      );
    }

    // Multiple retailers - show grouped list
    // Build a flat list of entries (headers + items)
    final List<_GroupedListEntry> entries = [];
    for (final retailer in retailers) {
      final items = groupedItems[retailer]!;
      // Add header entry
      entries.add(
        _GroupedListEntry(
          id: 'header_$retailer',
          isHeader: true,
          retailer: retailer,
          itemCount: items.length,
        ),
      );
      // Add item entries
      for (final item in items) {
        entries.add(
          _GroupedListEntry(id: item.itemId, isHeader: false, item: item),
        );
      }
    }

    return RefreshIndicator(
      onRefresh: () async {
        ref.read(realtimeListItemsProvider(widget.listId).notifier).refresh();
        ref.invalidate(listByIdProvider(widget.listId));
      },
      child: _AnimatedGroupedList(
        entries: entries,
        listId: widget.listId,
        isDark: isDark,
        buildHeader: _buildRetailerHeader,
        selectedIds: _selectedIds,
        isSelectionMode: _isSelectionMode,
        onLongPress: _enterSelectionMode,
        onToggleSelect: _toggleSelection,
      ),
    );
  }

  /// Group items by retailer, with null/empty retailers grouped as "Custom Items"
  /// Within each group, unchecked items appear first, checked items at the bottom
  Map<String, List<ListItem>> _groupItemsByRetailer(List<ListItem> items) {
    final Map<String, List<ListItem>> grouped = {};

    for (final item in items) {
      final retailer = (item.itemRetailer?.isNotEmpty ?? false)
          ? item.itemRetailer!
          : 'Custom Items';

      if (!grouped.containsKey(retailer)) {
        grouped[retailer] = [];
      }
      grouped[retailer]!.add(item);
    }

    // Sort items within each group: unchecked first, then checked
    for (final retailer in grouped.keys) {
      grouped[retailer]!.sort((a, b) {
        // Unchecked items (false) come before checked items (true)
        if (a.completedItem != b.completedItem) {
          return a.completedItem ? 1 : -1;
        }
        // Keep original order for items with same completion status
        return 0;
      });
    }

    // Sort retailers: known stores first (alphabetically), then "Custom Items" last
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) {
        if (a == 'Custom Items') return 1;
        if (b == 'Custom Items') return -1;
        return a.compareTo(b);
      });

    return Map.fromEntries(
      sortedKeys.map((key) => MapEntry(key, grouped[key]!)),
    );
  }

  /// Build a retailer section header
  Widget _buildRetailerHeader(String retailer, int itemCount, bool isDark) {
    final Color retailerColor = _getRetailerColor(retailer);

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: retailerColor.withValues(alpha: isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: retailerColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.store, size: 16, color: retailerColor),
                const SizedBox(width: 6),
                Text(
                  retailer,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: retailerColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
          ),
          const Expanded(child: SizedBox()),
        ],
      ),
    );
  }

  /// Get color for retailer
  Color _getRetailerColor(String retailer) {
    if (retailer == 'Custom Items') return AppColors.primary;
    return Retailers.fromName(retailer)?.color ?? AppColors.textSecondary;
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return EmptyState(
      type: EmptyStateType.emptyList,
      actionLabel: 'Browse Products',
      onAction: () => context.push('/stores'),
    );
  }

  void _showAddItemDialog(BuildContext context) {
    final outerContext = context;
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddItemTabbedSheet(
        listId: widget.listId,
        outerContext: outerContext,
        scaffoldMessenger: messenger,
      ),
    );
  }

  void _showListOptions(BuildContext context, WidgetRef ref, dynamic list) {
    if (list == null) return;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share, color: AppColors.primary),
              title: const Text('Share List'),
              onTap: () {
                Navigator.pop(context);
                showShareListSheet(
                  context,
                  ref,
                  listId: widget.listId,
                  listName: list.listName,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: AppColors.error),
              title: const Text('Delete List'),
              onTap: () async {
                // Capture everything we need before closing the bottom sheet
                final notifier = ref.read(listNotifierProvider.notifier);
                final currentListId = widget.listId;
                final listName = list.listName;
                final navigator = Navigator.of(context);
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final router = GoRouter.of(context);

                // Close bottom sheet
                navigator.pop();

                // Wait a bit for bottom sheet animation
                await Future.delayed(const Duration(milliseconds: 100));

                if (!context.mounted) {
                  return;
                }

                // Show confirmation dialog
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Delete List?'),
                    content: Text(
                      'Are you sure you want to delete "$listName"?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.error,
                        ),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );

                if (confirm != true) return;

                // Show loading message
                scaffoldMessenger.showSnackBar(
                  const SnackBar(content: Text('Deleting list...')),
                );

                try {
                  final success = await notifier.deleteList(currentListId);

                  if (success) {
                    // Navigate back using the captured router
                    router.go('/lists');

                    // Show success message after a short delay
                    Future.delayed(const Duration(milliseconds: 300), () {
                      scaffoldMessenger.showSnackBar(
                        const SnackBar(
                          content: Text('List deleted successfully'),
                          backgroundColor: AppColors.success,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    });
                  } else {
                    // Show error if delete failed
                    scaffoldMessenger.showSnackBar(
                      const SnackBar(
                        content: Text('Failed to delete list'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                } catch (e) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

}

class _ListHeader extends StatelessWidget {
  final dynamic list;
  final bool isDark;
  final VoidCallback? onCompare;

  const _ListHeader({
    required this.list,
    required this.isDark,
    this.onCompare,
  });

  @override
  Widget build(BuildContext context) {
    final colorValue =
        AppConstants.listColors[list.listColour] ??
        AppConstants.listColors['Green']!;
    final listColor = Color(colorValue);

    return Container(
      padding: const EdgeInsets.all(20),
      color: listColor.withValues(alpha: isDark ? 0.2 : 0.1),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: listColor.withValues(alpha: isDark ? 0.3 : 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.shopping_cart, color: listColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  list.storeName,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Total: R${list.totalPrice.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: listColor,
                  ),
                ),
              ],
            ),
          ),
          if (onCompare != null)
            Material(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onCompare,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.compare_arrows,
                          size: 16, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Compare',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ListItemTile extends ConsumerWidget {
  final ListItem item;
  final String listId;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback? onLongPress;
  final VoidCallback? onToggleSelect;

  const _ListItemTile({
    required this.item,
    required this.listId,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.onLongPress,
    this.onToggleSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dismissible(
      key: Key(item.itemId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (direction) {
        // Haptic feedback on dismiss
        AppHaptics.warning();
        // Use realtime provider for deletion
        ref
            .read(realtimeListItemsProvider(listId).notifier)
            .deleteItem(item.itemId);
        AppSnackbar.success(context, message: '${item.itemName} removed');
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        decoration: isSelected
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary, width: 2),
              )
            : null,
        child: Card(
          key: ValueKey(item.itemId),
          margin: const EdgeInsets.only(bottom: 8),
          // Subtle opacity change for completed items
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: item.completedItem ? 0.7 : 1.0,
            child: InkWell(
              onTap: () {
                if (isSelectionMode) {
                  onToggleSelect?.call();
                } else {
                  AppHaptics.lightTap();
                  _showEditItemDialog(context, ref);
                }
              },
              onLongPress: isSelectionMode ? null : onLongPress,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: ListTile(
                  leading: isSelectionMode
                      ? Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: isSelected
                              ? AppColors.primary
                              : (isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondary),
                        )
                      : AnimatedCheckbox(
                          value: item.completedItem,
                          onChanged: (value) {
                            // Use realtime provider for toggle with optimistic update
                            ref
                                .read(
                                    realtimeListItemsProvider(listId).notifier)
                                .toggleItemCompletion(item);
                          },
                        ),
                  title: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      decoration: item.completedItem
                          ? TextDecoration.lineThrough
                          : null,
                      color: item.completedItem
                          ? (isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondary)
                          : (isDark
                                ? AppColors.textPrimaryDark
                                : AppColors.textPrimary),
                    ),
                    child: Text(item.itemName),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            'Qty: ${item.itemQuantity.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '× R${item.effectivePrice.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondary,
                            ),
                          ),
                          if (item.hasSpecialPrice) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'PROMO',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.error,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (item.itemRetailer != null &&
                          item.itemRetailer!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          item.itemRetailer!,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                      if (item.itemNote != null &&
                          item.itemNote!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.note,
                              size: 14,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                item.itemNote!,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  color: isDark
                                      ? AppColors.textSecondaryDark
                                      : AppColors.textSecondary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'R${item.itemTotalPrice.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Icon(
                        Icons.edit,
                        size: 16,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showEditItemDialog(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _EditItemSheet(item: item, listId: listId),
    );
  }
}

/// Bottom sheet for editing an existing item
class _EditItemSheet extends ConsumerStatefulWidget {
  final ListItem item;
  final String listId;

  const _EditItemSheet({required this.item, required this.listId});

  @override
  ConsumerState<_EditItemSheet> createState() => _EditItemSheetState();
}

class _EditItemSheetState extends ConsumerState<_EditItemSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _priceController;
  late TextEditingController _quantityController;
  late TextEditingController _noteController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.item.itemName);
    _priceController = TextEditingController(
      text: widget.item.itemPrice.toStringAsFixed(2),
    );
    _quantityController = TextEditingController(
      text: widget.item.itemQuantity.toStringAsFixed(0),
    );
    _noteController = TextEditingController(text: widget.item.itemNote ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _handleUpdateItem() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final newQuantity = double.parse(_quantityController.text);
    final newPrice = double.parse(_priceController.text);
    final newNote = _noteController.text.trim().isEmpty
        ? null
        : _noteController.text.trim();

    // Calculate new total price
    double newTotalPrice;
    if (widget.item.hasSpecialPrice) {
      newTotalPrice = widget.item.itemSpecialPrice! * newQuantity;
    } else {
      newTotalPrice = newPrice * newQuantity;
    }

    // Create updated item
    final updatedItem = widget.item.copyWith(
      itemName: _nameController.text.trim(),
      itemPrice: newPrice,
      itemQuantity: newQuantity,
      itemNote: newNote,
      itemTotalPrice: newTotalPrice,
    );

    // Use realtime provider for update
    final success = await ref
        .read(realtimeListItemsProvider(widget.listId).notifier)
        .updateItem(updatedItem);

    setState(() => _isLoading = false);

    if (mounted) {
      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Updated ${updatedItem.itemName}'),
            backgroundColor: AppColors.success,
          ),
        );
        // Refresh the list to update total
        ref.invalidate(listByIdProvider(widget.listId));
        ref.invalidate(userListsProvider);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update item'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleDeleteItem() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item?'),
        content: Text('Remove "${widget.item.itemName}" from this list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      Navigator.pop(context);
      ref
          .read(realtimeListItemsProvider(widget.listId).notifier)
          .deleteItem(widget.item.itemId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.item.itemName} removed')),
      );
      // Refresh the list to update total
      ref.invalidate(listByIdProvider(widget.listId));
      ref.invalidate(userListsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppColors.surfaceDarkMode : AppColors.surface;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with title and delete button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Edit Item',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    onPressed: _handleDeleteItem,
                    icon: const Icon(Icons.delete, color: AppColors.error),
                    tooltip: 'Delete item',
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Item name
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Item Name',
                  prefixIcon: Icon(Icons.shopping_basket),
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Name is required' : null,
              ),

              const SizedBox(height: 16),

              // Price and Quantity row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _priceController,
                      decoration: InputDecoration(
                        labelText: 'Price',
                        prefixText: 'R ',
                        border: const OutlineInputBorder(),
                        helperText: widget.item.hasSpecialPrice
                            ? 'Promo: R${widget.item.itemSpecialPrice!.toStringAsFixed(2)}'
                            : null,
                        helperStyle: const TextStyle(color: AppColors.error),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (value) {
                        if (value?.isEmpty ?? true) return 'Required';
                        if (double.tryParse(value!) == null) return 'Invalid';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _quantityController,
                      decoration: const InputDecoration(
                        labelText: 'Qty',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value?.isEmpty ?? true) return 'Required';
                        if (double.tryParse(value!) == null) return 'Invalid';
                        return null;
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Note field
              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  prefixIcon: Icon(Icons.note),
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),

              // Show retailer info if available (read-only)
              if (widget.item.itemRetailer != null &&
                  widget.item.itemRetailer!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(8),
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
                        widget.item.itemRetailer!,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Current total preview
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Current Total:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      'R${widget.item.itemTotalPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Update button
              ElevatedButton(
                onPressed: _isLoading ? null : _handleUpdateItem,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Update Item', style: TextStyle(fontSize: 16)),
              ),

              const SizedBox(height: 16),

              // Cancel button
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tabbed bottom sheet for adding items — Manual entry or Browse products
class _AddItemTabbedSheet extends ConsumerStatefulWidget {
  final String listId;
  final BuildContext outerContext;
  final ScaffoldMessengerState scaffoldMessenger;

  const _AddItemTabbedSheet({
    required this.listId,
    required this.outerContext,
    required this.scaffoldMessenger,
  });

  @override
  ConsumerState<_AddItemTabbedSheet> createState() =>
      _AddItemTabbedSheetState();
}

class _AddItemTabbedSheetState extends ConsumerState<_AddItemTabbedSheet>
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMode : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.3)
                    : Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Tab bar
          TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(icon: Icon(Icons.edit_note), text: 'Manual'),
              Tab(icon: Icon(Icons.search), text: 'Browse'),
            ],
          ),

          const Divider(height: 1),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _ManualAddTab(
                  listId: widget.listId,
                  outerContext: widget.outerContext,
                  scaffoldMessenger: widget.scaffoldMessenger,
                ),
                _BrowseAddTab(
                  listId: widget.listId,
                  outerContext: widget.outerContext,
                  scaffoldMessenger: widget.scaffoldMessenger,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Manual item entry tab (preserved from original _AddItemSheet)
class _ManualAddTab extends ConsumerStatefulWidget {
  final String listId;
  final BuildContext outerContext;
  final ScaffoldMessengerState scaffoldMessenger;

  const _ManualAddTab({
    required this.listId,
    required this.outerContext,
    required this.scaffoldMessenger,
  });

  @override
  ConsumerState<_ManualAddTab> createState() => _ManualAddTabState();
}

class _ManualAddTabState extends ConsumerState<_ManualAddTab> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _noteController = TextEditingController();
  final _scrollController = ScrollController();
  final _noteFocusNode = FocusNode();
  Timer? _longPressTimer;
  int _quantity = 1;

  @override
  void initState() {
    super.initState();
    _noteFocusNode.addListener(_onNoteFocus);
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _nameController.dispose();
    _priceController.dispose();
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

  Future<void> _handleAddItem() async {
    if (!_formKey.currentState!.validate()) return;

    // Optimistic — close and show snackbar immediately, add in background
    final itemName = _nameController.text.trim();
    final itemPrice = double.parse(_priceController.text);
    final itemQty = _quantity.toDouble();
    final itemNote = _noteController.text.trim().isEmpty
        ? null
        : _noteController.text.trim();

    Navigator.of(widget.outerContext).pop();
    widget.scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text('$itemName added'),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );

    ref
        .read(realtimeListItemsProvider(widget.listId).notifier)
        .addItem(
          itemName: itemName,
          itemPrice: itemPrice,
          itemQuantity: itemQty,
          itemNote: itemNote,
        )
        .then((_) {
      ref.invalidate(listByIdProvider(widget.listId));
      ref.invalidate(userListsProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Add Item',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),

              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Item Name',
                  prefixIcon: Icon(Icons.shopping_basket),
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Name is required' : null,
                textCapitalization: TextCapitalization.sentences,
              ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _priceController,
                decoration: const InputDecoration(
                  labelText: 'Price',
                  prefixText: 'R ',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Required';
                  if (double.tryParse(value!) == null) return 'Invalid';
                  return null;
                },
              ),

              const SizedBox(height: 20),

              // Quantity stepper
              Row(
                children: [
                  Text(
                    'Quantity',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
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
                            : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimary),
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
                        color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
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
                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
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

              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _handleAddItem,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Add to List', style: TextStyle(fontSize: 16)),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// Browse products tab — search live products and add to list
class _BrowseAddTab extends ConsumerStatefulWidget {
  final String listId;
  final BuildContext outerContext;
  final ScaffoldMessengerState scaffoldMessenger;

  const _BrowseAddTab({
    required this.listId,
    required this.outerContext,
    required this.scaffoldMessenger,
  });

  @override
  ConsumerState<_BrowseAddTab> createState() => _BrowseAddTabState();
}

class _BrowseAddTabState extends ConsumerState<_BrowseAddTab> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _selectedRetailer = '';
  List<LiveProduct>? _results;
  bool _searching = false;
  String? _error;
  final Set<String> _addedProductNames = {};

  @override
  void initState() {
    super.initState();
    // Default to the globally selected retailer
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _selectedRetailer = ref.read(selectedRetailerProvider);
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _results = null;
        _searching = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _performSearch(query.trim());
    });
  }

  Future<void> _performSearch(String query) async {
    final storeAsync = ref.read(storeSelectionProvider);
    final selection = storeAsync.value;
    if (selection == null) return;

    final store = selection.forRetailer(_selectedRetailer);
    if (store == null) {
      setState(() => _error = 'No store found for $_selectedRetailer');
      return;
    }

    setState(() {
      _searching = true;
      _error = null;
    });

    try {
      final service = ref.read(fallbackProductServiceProvider);
      final response = await service.searchProducts(
        retailer: _selectedRetailer,
        store: store,
        query: query,
      );

      final products = response.products;

      if (mounted) {
        setState(() {
          _results = products;
          _searching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Search failed. Please try again.';
          _searching = false;
        });
      }
    }
  }

  void _addProductToList(LiveProduct product) {
    double regularPrice = product.priceNumeric;
    double? specialPrice;
    Map<String, double>? multiBuyInfo;

    if (product.hasPromo) {
      multiBuyInfo = product.multiBuyInfo;
      if (multiBuyInfo != null) {
        specialPrice = multiBuyInfo['pricePerItem'];
      } else {
        final parsed = double.tryParse(
          product.promotionPrice
              .replaceAll('R', '')
              .replaceAll(',', '')
              .trim(),
        );
        specialPrice = parsed ?? regularPrice;
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BrowseAddConfirmSheet(
        product: product,
        regularPrice: regularPrice,
        specialPrice: specialPrice,
        multiBuyInfo: multiBuyInfo,
        listId: widget.listId,
        outerContext: widget.outerContext,
        scaffoldMessenger: widget.scaffoldMessenger,
        ref: ref,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // Retailer chips
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: Retailers.names.map((name) {
                final config = Retailers.fromName(name)!;
                final isSelected = name == _selectedRetailer;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(name),
                    selected: isSelected,
                    selectedColor: config.color.withValues(alpha: 0.2),
                    labelStyle: TextStyle(
                      color: isSelected
                          ? config.color
                          : (isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondary),
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 13,
                    ),
                    side: isSelected
                        ? BorderSide(color: config.color)
                        : null,
                    onSelected: (_) {
                      setState(() {
                        _selectedRetailer = name;
                        _results = null;
                        _error = null;
                        _addedProductNames.clear();
                      });
                      if (_searchController.text.trim().isNotEmpty) {
                        _performSearch(_searchController.text.trim());
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        // Search field
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search products...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _results = null;
                          _error = null;
                        });
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
            textInputAction: TextInputAction.search,
          ),
        ),

        const SizedBox(height: 12),

        // Results
        Expanded(child: _buildResults(isDark)),
      ],
    );
  }

  Widget _buildResults(bool isDark) {
    if (_searching) {
      return const Center(child: LottieLoadingIndicator(message: 'Searching products...'));
    }

    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: TextStyle(
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
          ),
        ),
      );
    }

    if (_results == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 48,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              'Search for products to add',
              style: TextStyle(
                fontSize: 16,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    if (_results!.isEmpty) {
      return Center(
        child: Text(
          'No products found',
          style: TextStyle(
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _results!.length,
      itemBuilder: (context, index) {
        final product = _results![index];
        final wasAdded = _addedProductNames.contains(product.name);
        return _BrowseProductRow(
          product: product,
          isDark: isDark,
          wasAdded: wasAdded,
          onAdd: () => _addProductToList(product),
          onCompare: () => showCompareSheet(
            widget.outerContext,
            ref,
            product,
            listId: widget.listId,
            scaffoldMessenger: widget.scaffoldMessenger,
          ),
        );
      },
    );
  }
}

/// Compact product row for browse-add results
class _BrowseProductRow extends StatefulWidget {
  final LiveProduct product;
  final bool isDark;
  final bool wasAdded;
  final VoidCallback onAdd;
  final VoidCallback onCompare;

  const _BrowseProductRow({
    required this.product,
    required this.isDark,
    required this.wasAdded,
    required this.onAdd,
    required this.onCompare,
  });

  @override
  State<_BrowseProductRow> createState() => _BrowseProductRowState();
}

class _BrowseProductRowState extends State<_BrowseProductRow>
    with SingleTickerProviderStateMixin {
  late AnimationController _addAnimController;
  late Animation<double> _addScale;
  bool _tapped = false;

  @override
  void initState() {
    super.initState();
    _addAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _addScale = Tween<double>(begin: 1.0, end: 0.72).animate(
      CurvedAnimation(parent: _addAnimController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _addAnimController.dispose();
    super.dispose();
  }

  Future<void> _handleAddTap() async {
    if (_tapped) return;
    setState(() => _tapped = true);
    await _addAnimController.forward();
    await _addAnimController.reverse();
    widget.onAdd();
  }

  @override
  Widget build(BuildContext context) {
    final hasPromo = widget.product.hasPromo;
    final isDark = widget.isDark;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            // Product image
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 48,
                height: 48,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.grey.withValues(alpha: 0.1),
                child: (widget.product.imageUrl?.isNotEmpty ?? false)
                    ? Image.network(
                        widget.product.imageUrl!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.image_not_supported_outlined,
                          size: 24,
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondary,
                        ),
                      )
                    : Icon(
                        Icons.shopping_basket_outlined,
                        size: 24,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                      ),
              ),
            ),

            const SizedBox(width: 12),

            // Product info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (hasPromo) ...[
                        Flexible(
                          child: Text(
                            widget.product.price,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondary,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            widget.product.promotionPrice,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.error,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'SALE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.error,
                            ),
                          ),
                        ),
                      ] else
                        Flexible(
                          child: Text(
                            widget.product.price,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Compare + Add buttons
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Compare button
                InkWell(
                  onTap: widget.onCompare,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.primary),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.compare_arrows,
                      color: AppColors.primary,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Add button
                widget.wasAdded
                    ? Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.check,
                          color: AppColors.success,
                          size: 20,
                        ),
                      )
                    : GestureDetector(
                        onTap: _handleAddTap,
                        child: ScaleTransition(
                          scale: _addScale,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirmation sheet shown when adding a browsed product to a list.
/// Lets user adjust quantity and add an optional note before confirming.
class _BrowseAddConfirmSheet extends StatefulWidget {
  final LiveProduct product;
  final double regularPrice;
  final double? specialPrice;
  final Map<String, double>? multiBuyInfo;
  final String listId;
  final BuildContext outerContext;
  final ScaffoldMessengerState scaffoldMessenger;
  final WidgetRef ref;

  const _BrowseAddConfirmSheet({
    required this.product,
    required this.regularPrice,
    required this.specialPrice,
    required this.multiBuyInfo,
    required this.listId,
    required this.outerContext,
    required this.scaffoldMessenger,
    required this.ref,
  });

  @override
  State<_BrowseAddConfirmSheet> createState() => _BrowseAddConfirmSheetState();
}

class _BrowseAddConfirmSheetState extends State<_BrowseAddConfirmSheet> {
  int _quantity = 1;
  final _noteController = TextEditingController();
  Timer? _longPressTimer;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _noteController.dispose();
    super.dispose();
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

  void _handleAdd() {
    final note = _noteController.text.trim().isEmpty
        ? null
        : _noteController.text.trim();

    // Pop this confirm sheet
    Navigator.of(context).pop();
    // Pop the parent tabbed sheet
    Navigator.of(widget.outerContext).pop();

    widget.scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text('${widget.product.name} added'),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );

    widget.ref
        .read(realtimeListItemsProvider(widget.listId).notifier)
        .addItem(
          itemName: widget.product.name,
          itemPrice: widget.regularPrice,
          itemQuantity: _quantity.toDouble(),
          itemNote: note,
          itemRetailer: widget.product.retailer,
          itemSpecialPrice: widget.specialPrice,
          multiBuyInfo: widget.multiBuyInfo,
        )
        .then((_) {
      widget.ref.invalidate(listByIdProvider(widget.listId));
      widget.ref.invalidate(userListsProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.surfaceDarkMode : Colors.white;
    final textColor = isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final subtitleColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Container(
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

          // Product info
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 48,
                    height: 48,
                    color: Colors.white,
                    child: (widget.product.imageUrl?.isNotEmpty ?? false)
                        ? Image.network(
                            widget.product.imageUrl!,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.shopping_bag_outlined, size: 24),
                          )
                        : const Icon(Icons.shopping_bag_outlined, size: 24),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.product.name,
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
                        '${widget.product.retailer} · ${widget.product.price}',
                        style: TextStyle(fontSize: 13, color: subtitleColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Quantity + Note
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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

          // Sticky add button
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + viewInsets.bottom),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _handleAdd,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Add to List',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper class for grouped list entries (headers and items)
class _GroupedListEntry {
  final String id;
  final bool isHeader;
  final String? retailer;
  final int? itemCount;
  final ListItem? item;

  _GroupedListEntry({
    required this.id,
    required this.isHeader,
    this.retailer,
    this.itemCount,
    this.item,
  });
}

/// Animated list that smoothly reorders items when their positions change
class _AnimatedItemList extends StatefulWidget {
  final List<ListItem> items;
  final String listId;
  final Set<String> selectedIds;
  final bool isSelectionMode;
  final void Function(String itemId)? onLongPress;
  final void Function(String itemId)? onToggleSelect;

  const _AnimatedItemList({
    required this.items,
    required this.listId,
    this.selectedIds = const {},
    this.isSelectionMode = false,
    this.onLongPress,
    this.onToggleSelect,
  });

  @override
  State<_AnimatedItemList> createState() => _AnimatedItemListState();
}

class _AnimatedItemListState extends State<_AnimatedItemList>
    with TickerProviderStateMixin {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  late List<ListItem> _items;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.items);
  }

  @override
  void didUpdateWidget(_AnimatedItemList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateList(widget.items);
  }

  void _updateList(List<ListItem> newItems) {
    // Find items that need to be removed and added
    final oldIds = _items.map((e) => e.itemId).toSet();
    final newIds = newItems.map((e) => e.itemId).toSet();

    // Items to remove (in old but not in new)
    final toRemove = oldIds.difference(newIds);

    // Remove items with animation
    for (final id in toRemove) {
      final index = _items.indexWhere((item) => item.itemId == id);
      if (index != -1) {
        final removedItem = _items.removeAt(index);
        _listKey.currentState?.removeItem(
          index,
          (context, animation) => _buildRemovedItem(removedItem, animation),
          duration: const Duration(milliseconds: 300),
        );
      }
    }

    // Update the items list to match new order
    _items = List.from(newItems);

    // For reordering, we rebuild the list
    // The AnimatedList handles this smoothly with the keys
    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildRemovedItem(ListItem item, Animation<double> animation) {
    return SizeTransition(
      sizeFactor: animation,
      child: FadeTransition(
        opacity: animation,
        child: _ListItemTile(item: item, listId: widget.listId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Use a regular ListView with AnimatedSwitcher for each item
    // This gives us smooth transitions when items reorder
    return ListView.builder(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 96),
      itemCount: widget.items.length,
      itemBuilder: (context, index) {
        final item = widget.items[index];
        return _AnimatedListItem(
          key: ValueKey(item.itemId),
          item: item,
          listId: widget.listId,
          isSelected: widget.selectedIds.contains(item.itemId),
          isSelectionMode: widget.isSelectionMode,
          onLongPress: () => widget.onLongPress?.call(item.itemId),
          onToggleSelect: () => widget.onToggleSelect?.call(item.itemId),
        );
      },
    );
  }
}

/// Individual list item with slide animation when position changes
class _AnimatedListItem extends StatefulWidget {
  final ListItem item;
  final String listId;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback? onLongPress;
  final VoidCallback? onToggleSelect;

  const _AnimatedListItem({
    super.key,
    required this.item,
    required this.listId,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.onLongPress,
    this.onToggleSelect,
  });

  @override
  State<_AnimatedListItem> createState() => _AnimatedListItemState();
}

class _AnimatedListItemState extends State<_AnimatedListItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  bool _isFirstBuild = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isFirstBuild) {
      _isFirstBuild = false;
      // Animate in on first build
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(_AnimatedListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If completion status changed, animate
    if (oldWidget.item.completedItem != widget.item.completedItem) {
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: _ListItemTile(
          item: widget.item,
          listId: widget.listId,
          isSelected: widget.isSelected,
          isSelectionMode: widget.isSelectionMode,
          onLongPress: widget.onLongPress,
          onToggleSelect: widget.onToggleSelect,
        ),
      ),
    );
  }
}

/// Animated list for multiple retailers (grouped list)
class _AnimatedGroupedList extends StatelessWidget {
  final List<_GroupedListEntry> entries;
  final String listId;
  final bool isDark;
  final Widget Function(String retailer, int itemCount, bool isDark)
  buildHeader;
  final Set<String> selectedIds;
  final bool isSelectionMode;
  final void Function(String itemId)? onLongPress;
  final void Function(String itemId)? onToggleSelect;

  const _AnimatedGroupedList({
    required this.entries,
    required this.listId,
    required this.isDark,
    required this.buildHeader,
    this.selectedIds = const {},
    this.isSelectionMode = false,
    this.onLongPress,
    this.onToggleSelect,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];

        // Headers don't need animation
        if (entry.isHeader) {
          return buildHeader(entry.retailer!, entry.itemCount!, isDark);
        }

        // Items get animated
        return _AnimatedListItem(
          key: ValueKey(entry.id),
          item: entry.item!,
          listId: listId,
          isSelected: selectedIds.contains(entry.id),
          isSelectionMode: isSelectionMode,
          onLongPress: () => onLongPress?.call(entry.id),
          onToggleSelect: () => onToggleSelect?.call(entry.id),
        );
      },
    );
  }
}
