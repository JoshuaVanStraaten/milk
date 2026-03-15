import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/config/supabase_config.dart';
import '../../providers/list_provider.dart';
import '../../widgets/skeleton_loaders.dart';
import '../../widgets/animations.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../widgets/common/empty_states.dart';

class MyListsScreen extends ConsumerStatefulWidget {
  const MyListsScreen({super.key});

  @override
  ConsumerState<MyListsScreen> createState() => _MyListsScreenState();
}

class _MyListsScreenState extends ConsumerState<MyListsScreen> {
  final Set<String> _selectedIds = {};
  bool get _isSelectionMode => _selectedIds.isNotEmpty;

  void _exitSelectionMode() {
    setState(() => _selectedIds.clear());
  }

  void _toggleSelection(String listId) {
    setState(() {
      if (_selectedIds.contains(listId)) {
        _selectedIds.remove(listId);
      } else {
        _selectedIds.add(listId);
      }
    });
    AppHaptics.lightTap();
  }

  void _enterSelectionMode(String listId) {
    setState(() => _selectedIds.add(listId));
    AppHaptics.lightTap();
  }

  Future<void> _confirmBulkDelete() async {
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $count list${count > 1 ? 's' : ''}?'),
        content: const Text('This cannot be undone.'),
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

    if (confirmed != true || !mounted) return;

    final idsToDelete = Set<String>.from(_selectedIds);
    _exitSelectionMode();

    for (final id in idsToDelete) {
      await ref.read(listNotifierProvider.notifier).deleteList(id);
    }

    ref.invalidate(userListsProvider);

    if (mounted) {
      AppSnackbar.success(
        context,
        message: 'Deleted $count list${count > 1 ? 's' : ''}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final listsAsync = ref.watch(userListsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: _isSelectionMode
            ? Text('${_selectedIds.length} selected')
            : const Text('My Shopping Lists'),
        automaticallyImplyLeading: false,
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelectionMode,
              )
            : null,
        backgroundColor: _isSelectionMode
            ? AppColors.primary.withValues(alpha: 0.1)
            : null,
        actions: _isSelectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _confirmBulkDelete,
                  color: AppColors.error,
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => context.push('/lists/create'),
                ),
              ],
      ),
      body: listsAsync.when(
        data: (lists) {
          if (lists.isEmpty) {
            return _buildEmptyState(context, isDark);
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(userListsProvider);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: lists.length,
              itemBuilder: (context, index) {
                final list = lists[index];
                return AnimatedListItem(
                  index: index,
                  child: _ListCard(
                    list: list,
                    isSelected: _selectedIds.contains(list.shoppingListId),
                    isSelectionMode: _isSelectionMode,
                    onLongPress: () => _enterSelectionMode(list.shoppingListId),
                    onToggleSelect: () =>
                        _toggleSelection(list.shoppingListId),
                  ),
                );
              },
            ),
          );
        },
        loading: () => const ListCardsSkeleton(),
        error: (error, stack) => _buildErrorState(context, ref, error, isDark),
      ),
      floatingActionButton: _isSelectionMode
          ? null
          : FloatingActionButton(
              onPressed: () => context.push('/lists/create'),
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return EmptyState(
      type: EmptyStateType.noLists,
      actionLabel: 'Create Shopping List',
      onAction: () => context.push('/lists/create'),
    );
  }

  Widget _buildErrorState(
    BuildContext context,
    WidgetRef ref,
    Object error,
    bool isDark,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              'Error loading lists',
              style: TextStyle(
                fontSize: 18,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ref.invalidate(userListsProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListCard extends ConsumerWidget {
  final dynamic list;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onLongPress;
  final VoidCallback onToggleSelect;

  const _ListCard({
    required this.list,
    required this.isSelected,
    required this.isSelectionMode,
    required this.onLongPress,
    required this.onToggleSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorValue =
        AppConstants.listColors[list.listColour] ??
        AppConstants.listColors['Green']!;
    final listColor = Color(colorValue);

    final currentUserId = SupabaseConfig.currentUser?.id;
    final isSharedWithMe =
        currentUserId != null && list.userId != currentUserId;
    final sharedCount = list.sharedCount ?? 0;

    String? sharingLabel;
    if (isSharedWithMe && list.ownerEmail != null) {
      sharingLabel = 'Shared by ${list.ownerEmail}';
    } else if (!isSharedWithMe && sharedCount > 0) {
      sharingLabel =
          'Shared with $sharedCount ${sharedCount == 1 ? 'person' : 'people'}';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isSelected
          ? AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.08)
          : null,
      child: InkWell(
        onTap: () {
          if (isSelectionMode) {
            onToggleSelect();
          } else {
            AppHaptics.lightTap();
            context.push('/lists/${list.shoppingListId}');
          }
        },
        onLongPress: isSelectionMode ? null : onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              // Color indicator
              Container(
                width: 4,
                height: 60,
                decoration: BoxDecoration(
                  color: listColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              const SizedBox(width: 16),

              // List info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      list.listName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      list.storeName,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                      ),
                    ),
                    // Sharing indicator
                    if (sharingLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(
                              isSharedWithMe
                                  ? Icons.person_outline
                                  : Icons.people_outline,
                              size: 14,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              sharingLabel,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Total: R${list.totalPrice.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: listColor,
                      ),
                    ),
                  ],
                ),
              ),

              // Selection indicator or arrow
              if (isSelectionMode)
                Icon(
                  isSelected ? Icons.check_circle : Icons.circle_outlined,
                  color: isSelected
                      ? AppColors.primary
                      : (isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary),
                )
              else
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
