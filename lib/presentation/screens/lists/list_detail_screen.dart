import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/list_item.dart';
import '../../providers/list_provider.dart';
import '../../widgets/skeleton_loaders.dart';
import '../../widgets/animations.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/empty_states.dart';

class ListDetailScreen extends ConsumerStatefulWidget {
  final String listId;

  const ListDetailScreen({super.key, required this.listId});

  @override
  ConsumerState<ListDetailScreen> createState() => _ListDetailScreenState();
}

class _ListDetailScreenState extends ConsumerState<ListDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(listByIdProvider(widget.listId));
    final itemsState = ref.watch(realtimeListItemsProvider(widget.listId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: listAsync.when(
          data: (list) => Text(list.listName),
          loading: () => const Text('Loading...'),
          error: (_, __) => const Text('Error'),
        ),
        actions: [
          // Real-time indicator
          if (itemsState.isRealtime)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Tooltip(
                message: 'Real-time sync active',
                child: Icon(Icons.sync, color: AppColors.success, size: 20),
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
              // List Header
              _ListHeader(list: list, isDark: isDark),

              const Divider(height: 1),

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
        child: _AnimatedItemList(items: sortedItems, listId: widget.listId),
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
    switch (retailer) {
      case 'Pick n Pay':
        return AppColors.pickNPay;
      case 'Woolworths':
        return AppColors.woolworths;
      case 'Shoprite':
        return AppColors.shoprite;
      case 'Checkers':
        return AppColors.checkers;
      case 'Custom Items':
        return AppColors.primary;
      default:
        return AppColors.textSecondary;
    }
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return EmptyState(
      type: EmptyStateType.emptyList,
      actionLabel: 'Browse Products',
      onAction: () => context.push('/stores'),
    );
  }

  void _showAddItemDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _AddItemSheet(listId: widget.listId),
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
                _showShareDialog(context, ref, list);
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

  void _showShareDialog(BuildContext context, WidgetRef ref, dynamic list) {
    final emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Share List'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Share "${list.listName}" with another user',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: 'Email address',
                hintText: 'friend@example.com',
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter an email')),
                );
                return;
              }

              Navigator.pop(context);

              final success = await ref
                  .read(listNotifierProvider.notifier)
                  .shareList(listId: widget.listId, shareWithEmail: email);

              if (context.mounted) {
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('List shared with $email'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Failed to share list'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            child: const Text('Share'),
          ),
        ],
      ),
    );
  }
}

class _ListHeader extends StatelessWidget {
  final dynamic list;
  final bool isDark;

  const _ListHeader({required this.list, required this.isDark});

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
        ],
      ),
    );
  }
}

class _ListItemTile extends ConsumerWidget {
  final ListItem item;
  final String listId;

  const _ListItemTile({required this.item, required this.listId});

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
        child: Card(
          key: ValueKey(item.itemId),
          margin: const EdgeInsets.only(bottom: 8),
          // Subtle opacity change for completed items
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: item.completedItem ? 0.7 : 1.0,
            child: InkWell(
              onTap: () {
                AppHaptics.lightTap();
                _showEditItemDialog(context, ref);
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: ListTile(
                  leading: AnimatedCheckbox(
                    value: item.completedItem,
                    onChanged: (value) {
                      // Use realtime provider for toggle with optimistic update
                      ref
                          .read(realtimeListItemsProvider(listId).notifier)
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

/// Bottom sheet for adding a new custom item
class _AddItemSheet extends ConsumerStatefulWidget {
  final String listId;

  const _AddItemSheet({required this.listId});

  @override
  ConsumerState<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends ConsumerState<_AddItemSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _noteController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _handleAddItem() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    // Use realtime provider for adding
    final item = await ref
        .read(realtimeListItemsProvider(widget.listId).notifier)
        .addItem(
          itemName: _nameController.text.trim(),
          itemPrice: double.parse(_priceController.text),
          itemQuantity: double.parse(_quantityController.text),
          itemNote: _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
        );

    setState(() => _isLoading = false);

    if (mounted && item != null) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ${item.itemName}'),
          backgroundColor: AppColors.success,
        ),
      );
      // Refresh the list to update total
      ref.invalidate(listByIdProvider(widget.listId));
      ref.invalidate(userListsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
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

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
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

              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  prefixIcon: Icon(Icons.note),
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),

              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _isLoading ? null : _handleAddItem,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Add to List', style: TextStyle(fontSize: 16)),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
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

  const _AnimatedItemList({required this.items, required this.listId});

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
        );
      },
    );
  }
}

/// Individual list item with slide animation when position changes
class _AnimatedListItem extends StatefulWidget {
  final ListItem item;
  final String listId;

  const _AnimatedListItem({
    super.key,
    required this.item,
    required this.listId,
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
        child: _ListItemTile(item: widget.item, listId: widget.listId),
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

  const _AnimatedGroupedList({
    required this.entries,
    required this.listId,
    required this.isDark,
    required this.buildHeader,
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
        );
      },
    );
  }
}
