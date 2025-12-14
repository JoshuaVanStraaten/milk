import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/product.dart';
import '../../providers/product_provider.dart';
import '../../providers/list_provider.dart';
import '../../widgets/skeleton_loaders.dart';
import '../../widgets/animations.dart';
import '../../widgets/common/app_snackbar.dart';
import '../../../data/services/connectivity_service.dart';
import '../../widgets/common/empty_states.dart';

class ProductListScreen extends ConsumerStatefulWidget {
  final String retailer;

  const ProductListScreen({super.key, required this.retailer});

  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();

    // Listen for scroll to load more products
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent * 0.9) {
        // Near bottom, load more
        ref.read(productListProvider(widget.retailer).notifier).loadMore();
      }
    });

    // Prefetch user lists so they're ready when "Add to List" is tapped
    ref.read(userListsProvider);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productState = ref.watch(productListProvider(widget.retailer));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.retailer),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {
              _showFilterOptions(context);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          _buildSearchBar(),

          // Filter chips
          _buildFilterChips(productState),

          // Products
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await ref
                    .read(productListProvider(widget.retailer).notifier)
                    .refresh();
              },
              child: _buildBody(productState),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search products...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    ref
                        .read(productListProvider(widget.retailer).notifier)
                        .search('');
                  },
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onChanged: (value) {
          // Debounce search - wait 500ms after user stops typing
          Future.delayed(const Duration(milliseconds: 500), () {
            if (_searchController.text == value) {
              ref
                  .read(productListProvider(widget.retailer).notifier)
                  .search(value);
            }
          });
          setState(() {}); // Update to show/hide clear button
        },
      ),
    );
  }

  Widget _buildFilterChips(ProductListState state) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      height: 50,
      child: Row(
        children: [
          // Promotions filter chip
          FilterChip(
            label: const Text('Promotions'),
            selected: state.showPromotionsOnly,
            onSelected: (selected) {
              ref
                  .read(productListProvider(widget.retailer).notifier)
                  .togglePromotionsFilter();
            },
            avatar: state.showPromotionsOnly
                ? const Icon(Icons.check, size: 16)
                : const Icon(Icons.local_offer, size: 16),
          ),

          const SizedBox(width: 8),

          // Sort chip
          ActionChip(
            label: Text(_getSortLabel(state.sortBy)),
            avatar: const Icon(Icons.sort, size: 16),
            onPressed: () => _showSortOptions(context),
          ),

          // Show active filter count
          if (state.searchQuery.isNotEmpty ||
              state.showPromotionsOnly ||
              state.sortBy != 'none')
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '${_getActiveFilterCount(state)} active',
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
    );
  }

  String _getSortLabel(String sortBy) {
    switch (sortBy) {
      case 'price_asc':
        return 'Price: Low to High';
      case 'price_desc':
        return 'Price: High to Low';
      case 'name_asc':
        return 'Name: A-Z';
      default:
        return 'Sort';
    }
  }

  int _getActiveFilterCount(ProductListState state) {
    int count = 0;
    if (state.searchQuery.isNotEmpty) count++;
    if (state.showPromotionsOnly) count++;
    if (state.sortBy != 'none') count++;
    return count;
  }

  void _showSortOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.clear),
              title: const Text('No Sorting'),
              onTap: () {
                ref
                    .read(productListProvider(widget.retailer).notifier)
                    .setSortOrder('none');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.arrow_upward),
              title: const Text('Price: Low to High'),
              onTap: () {
                ref
                    .read(productListProvider(widget.retailer).notifier)
                    .setSortOrder('price_asc');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.arrow_downward),
              title: const Text('Price: High to Low'),
              onTap: () {
                ref
                    .read(productListProvider(widget.retailer).notifier)
                    .setSortOrder('price_desc');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.sort_by_alpha),
              title: const Text('Name: A-Z'),
              onTap: () {
                ref
                    .read(productListProvider(widget.retailer).notifier)
                    .setSortOrder('name_asc');
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showFilterOptions(BuildContext context) {
    final state = ref.read(productListProvider(widget.retailer));

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Filters',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              SwitchListTile(
                title: const Text('Show Promotions Only'),
                value: state.showPromotionsOnly,
                onChanged: (value) {
                  ref
                      .read(productListProvider(widget.retailer).notifier)
                      .togglePromotionsFilter();
                  Navigator.pop(context);
                },
              ),

              const SizedBox(height: 16),

              ElevatedButton(
                onPressed: () {
                  // Clear all filters
                  _searchController.clear();
                  ref
                      .read(productListProvider(widget.retailer).notifier)
                      .search('');
                  ref
                      .read(productListProvider(widget.retailer).notifier)
                      .setSortOrder('none');
                  if (state.showPromotionsOnly) {
                    ref
                        .read(productListProvider(widget.retailer).notifier)
                        .togglePromotionsFilter();
                  }
                  Navigator.pop(context);
                },
                child: const Text('Clear All Filters'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ProductListState state) {
    // final isDark = Theme.of(context).brightness == Brightness.dark;

    // Error state
    if (state.error != null && state.products.isEmpty) {
      final connectivity = ref.read(connectivityServiceProvider);
      final isOffline = connectivity.isOffline;

      // Check if error is network-related
      final isNetworkError =
          state.error!.contains('SocketException') ||
          state.error!.contains('ClientException') ||
          state.error!.contains('host lookup') ||
          state.error!.contains('Failed host lookup') ||
          state.error!.contains('Network is unreachable') ||
          state.error!.contains('Connection refused');

      if (isOffline || isNetworkError) {
        // Show offline-friendly empty state
        return EmptyState(
          type: EmptyStateType.offline,
          actionLabel: 'Retry',
          onAction: () {
            ref.read(productListProvider(widget.retailer).notifier).refresh();
          },
          customMessage:
              'Products will be available when you\'re back online. '
              'Try browsing your saved shopping lists instead.',
        );
      }

      // Generic error state for other errors
      return EmptyState(
        type: EmptyStateType.error,
        actionLabel: 'Retry',
        onAction: () {
          ref.read(productListProvider(widget.retailer).notifier).refresh();
        },
      );
    }

    // Loading initial products
    if (state.isLoading && state.products.isEmpty) {
      return const ProductGridSkeleton();
    }

    // Empty state - check if it's a search with no results
    if (state.products.isEmpty) {
      final isSearching =
          state.searchQuery.isNotEmpty || state.showPromotionsOnly;

      return EmptyState(
        type: isSearching
            ? EmptyStateType.noSearchResults
            : EmptyStateType.noProducts,
        actionLabel: isSearching ? 'Clear Filters' : null,
        onAction: isSearching
            ? () {
                final notifier = ref.read(
                  productListProvider(widget.retailer).notifier,
                );
                // Clear search
                if (state.searchQuery.isNotEmpty) {
                  notifier.search('');
                }
                // Turn off promotions filter if active
                if (state.showPromotionsOnly) {
                  notifier.togglePromotionsFilter();
                }
              }
            : null,
      );
    }

    // Product grid
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.62,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: state.products.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        // Loading indicator at the end - show skeleton card
        if (index >= state.products.length) {
          return const ShimmerEffect(child: ProductCardSkeleton());
        }

        final product = state.products[index];
        return AnimatedListItem(
          index: index % 10, // Reset stagger every 10 items for pagination
          child: _ProductCard(product: product, retailer: widget.retailer),
        );
      },
    );
  }
}

class _ProductCard extends ConsumerWidget {
  final Product product;
  final String retailer;

  const _ProductCard({required this.product, required this.retailer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          AppHaptics.lightTap();
          // Navigate to product detail screen
          context.push('/product/$retailer', extra: product);
        },
        onLongPress: () {
          AppHaptics.mediumTap();
          // Quick add to list on long press
          _showAddToListDialog(context, ref, product, retailer);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Image with Hero animation
            AspectRatio(
              aspectRatio: 1,
              child: Hero(
                tag: 'product-${product.index}',
                child: _buildProductImage(context, isDark),
              ),
            ),

            // Product Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(6.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Product Name
                    Flexible(
                      child: Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                          height: 1.2,
                        ),
                      ),
                    ),

                    const SizedBox(height: 4),

                    // Price
                    if (product.price != null && product.price!.isNotEmpty)
                      Text(
                        product.price!,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: product.hasPromotion
                              ? (isDark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondary)
                              : AppColors.primary,
                          decoration: product.hasPromotion
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),

                    // Promotion Price (if exists)
                    if (product.hasPromotion) ...[
                      const SizedBox(height: 2),
                      Flexible(
                        child: Text(
                          product.promotionPrice!,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.error,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductImage(BuildContext context, bool isDark) {
    final surfaceColor = isDark ? AppColors.surfaceDarkMode : AppColors.surface;
    final iconColor = isDark
        ? AppColors.textDisabledDark
        : AppColors.textDisabled;

    if (product.imageUrl == null || product.imageUrl!.isEmpty) {
      return Container(
        color: surfaceColor,
        child: Center(
          child: Icon(Icons.image_not_supported, size: 48, color: iconColor),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: product.imageUrl!,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        color: surfaceColor,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      errorWidget: (context, url, error) => Container(
        color: surfaceColor,
        child: Center(
          child: Icon(Icons.broken_image, size: 48, color: iconColor),
        ),
      ),
    );
  }
}

// Helper function to show add to list dialog
void _showAddToListDialog(
  BuildContext context,
  WidgetRef ref,
  Product product,
  String retailer,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => _AddToListSheet(product: product, retailer: retailer),
  );
}

class _AddToListSheet extends ConsumerStatefulWidget {
  final Product product;
  final String retailer;

  const _AddToListSheet({required this.product, required this.retailer});

  @override
  ConsumerState<_AddToListSheet> createState() => _AddToListSheetState();
}

class _AddToListSheetState extends ConsumerState<_AddToListSheet> {
  final _quantityController = TextEditingController(text: '1');
  final _noteController = TextEditingController();
  String? _selectedListId;

  @override
  void dispose() {
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _handleAddToList() async {
    if (_selectedListId == null) {
      AppSnackbar.warning(context, message: 'Please select a list');
      return;
    }

    final quantity = double.tryParse(_quantityController.text) ?? 1.0;

    // Get prices and multi-buy info
    double regularPrice = 0.0;
    double? specialPrice;
    Map<String, double>? multiBuyInfo;

    if (widget.product.hasPromotion) {
      regularPrice = widget.product.numericRegularPrice ?? 0.0;

      // Check if it's a multi-buy deal
      multiBuyInfo = widget.product.multiBuyInfo;

      if (multiBuyInfo != null) {
        // Multi-buy promo: store the deal info for smart calculation
        specialPrice = multiBuyInfo['pricePerItem']; // For display purposes
      } else {
        // Simple promo: use promo price as-is
        specialPrice = widget.product.numericPromotionPrice;
      }
    } else {
      // No promotion
      regularPrice = widget.product.numericPrice ?? 0.0;
      specialPrice = null;
    }

    final itemNotifier = ref.read(listItemNotifierProvider.notifier);

    final item = await itemNotifier.addItem(
      listId: _selectedListId!,
      itemName: widget.product.name,
      itemPrice: regularPrice,
      itemQuantity: quantity,
      itemNote: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
      itemRetailer: widget.retailer,
      itemSpecialPrice: specialPrice,
      multiBuyInfo: multiBuyInfo,
    );

    if (mounted && item != null) {
      // Refresh the realtime provider for this list
      ref.read(realtimeListItemsProvider(_selectedListId!).notifier).refresh();

      Navigator.pop(context);
      AppSnackbar.success(
        context,
        message: 'Added ${widget.product.name} to list',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppColors.surfaceDarkMode : AppColors.surface;
    final textSecondaryColor = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;

    // Watch the lists provider reactively - this fixes the first-load issue
    final listsAsync = ref.watch(userListsProvider);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.backgroundDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Add to Shopping List',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 20),

          // Product info
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: widget.product.imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: widget.product.imageUrl!,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          width: 60,
                          height: 60,
                          color: surfaceColor,
                          child: const Icon(Icons.image_not_supported),
                        ),
                      )
                    : Container(
                        width: 60,
                        height: 60,
                        color: surfaceColor,
                        child: const Icon(Icons.image_not_supported),
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
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.product.displayPrice,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: widget.product.hasPromotion
                            ? AppColors.error
                            : AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // List selector - now uses watched provider
          listsAsync.when(
            data: (lists) {
              if (lists.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'No lists yet. Create a list first!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: textSecondaryColor),
                  ),
                );
              }

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButton<String>(
                  value: _selectedListId,
                  hint: const Text('Select a list'),
                  isExpanded: true,
                  underline: const SizedBox(),
                  dropdownColor: isDark
                      ? AppColors.surfaceDarkMode
                      : Colors.white,
                  items: lists.map<DropdownMenuItem<String>>((list) {
                    return DropdownMenuItem<String>(
                      value: list.shoppingListId,
                      child: Text(list.listName),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedListId = value;
                    });
                  },
                ),
              );
            },
            loading: () => const CircularProgressIndicator(),
            error: (_, __) => const Text('Error loading lists'),
          ),

          const SizedBox(height: 16),

          // Quantity
          TextFormField(
            controller: _quantityController,
            decoration: const InputDecoration(
              labelText: 'Quantity',
              prefixIcon: Icon(Icons.shopping_cart),
            ),
            keyboardType: TextInputType.number,
          ),

          const SizedBox(height: 16),

          // Note
          TextFormField(
            controller: _noteController,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              prefixIcon: Icon(Icons.note),
            ),
            maxLines: 2,
          ),

          const SizedBox(height: 24),

          // Add button
          ElevatedButton(
            onPressed: _handleAddToList,
            child: const Text('Add to List'),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
