// lib/presentation/screens/products/live_browse_screen.dart
//
// REPLACES StoreSelectorScreen as the Browse tab (index 1).
// Shows: retailer chips → category chips → store info bar → product grid (live API)
// with search, infinite scroll, sort/filter controls, and DB fallback.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/retailers.dart';
import '../../../core/constants/product_categories.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/nearby_store.dart';
import '../../../data/models/live_product.dart';
import '../../providers/store_provider.dart';
import '../../widgets/products/live_product_card.dart';
import '../../widgets/common/empty_states.dart';
import '../../widgets/skeleton_loaders.dart';
import '../../widgets/animations.dart';
import '../../widgets/products/add_to_list_sheet.dart';
import '../../widgets/products/store_picker_sheet.dart';
import 'live_product_detail_screen.dart';
import '../compare/compare_sheet.dart';

// ─────────────────────────────────────────────
// Sort options
// ─────────────────────────────────────────────

enum SortOption {
  relevance('Relevance'),
  priceLow('Price: Low to High'),
  priceHigh('Price: High to Low'),
  alphabetical('A – Z');

  final String label;
  const SortOption(this.label);
}

// ─────────────────────────────────────────────
// Unhealthy keyword set (for healthy-first sort)
// ─────────────────────────────────────────────

/// Returns true if a product name contains confectionery/snack keywords.
/// Used to silently deprioritise unhealthy items on relevance sort (4c).
bool isUnhealthyProduct(String name) {
  final lower = name.toLowerCase();
  const unhealthyKeywords = {
    'chip', 'chips', 'crisp', 'crisps',
    'chocolate', 'candy', 'sweet', 'sweets', 'lolly', 'lollipop',
    'biscuit', 'cookie', 'wafer', 'snack bar', 'energy bar',
    'soda', 'fizzy', 'cooldrink', 'cold drink', 'energy drink',
    'gummy', 'gummies', 'jelly baby', 'jelly babies',
    'popcorn', 'nacho', 'pretzel', 'cracker',
    'ice cream', 'icecream', 'frozen dessert', 'sorbet',
    'cake', 'doughnut', 'donut', 'muffin', 'brownie',
    'pudding', 'toffee', 'fudge', 'nougat',
  };
  return unhealthyKeywords.any((kw) => lower.contains(kw));
}

/// Applies healthy-first deprioritisation: partitions products into
/// [healthy, unhealthy] and returns them concatenated.
List<LiveProduct> applyHealthyFirst(List<LiveProduct> products) {
  final healthy = <LiveProduct>[];
  final unhealthy = <LiveProduct>[];
  for (final p in products) {
    if (isUnhealthyProduct(p.name)) {
      unhealthy.add(p);
    } else {
      healthy.add(p);
    }
  }
  return [...healthy, ...unhealthy];
}

/// Applies the chosen [SortOption] to [products] (client-side).
List<LiveProduct> applySort(List<LiveProduct> products, SortOption sort) {
  final sorted = List<LiveProduct>.from(products);
  switch (sort) {
    case SortOption.relevance:
      return applyHealthyFirst(sorted);
    case SortOption.priceLow:
      sorted.sort((a, b) => a.priceNumeric.compareTo(b.priceNumeric));
    case SortOption.priceHigh:
      sorted.sort((a, b) => b.priceNumeric.compareTo(a.priceNumeric));
    case SortOption.alphabetical:
      sorted.sort((a, b) => a.name.compareTo(b.name));
  }
  return sorted;
}

// ─────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────

class LiveBrowseScreen extends ConsumerStatefulWidget {
  const LiveBrowseScreen({super.key});

  @override
  ConsumerState<LiveBrowseScreen> createState() => _LiveBrowseScreenState();
}

class _LiveBrowseScreenState extends ConsumerState<LiveBrowseScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;
  bool _isSearching = false;

  // Category state
  ProductCategory? _selectedCategory;

  // Sort & filter state
  SortOption _sortOption = SortOption.relevance;
  bool _promosOnly = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProductsForCurrentRetailer();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_isSearching) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.85) {
      ref.read(liveProductsProvider.notifier).loadNextPage();
    }
  }

  void _loadProductsForCurrentRetailer({bool refresh = false}) {
    final retailer = ref.read(selectedRetailerProvider);
    final storeState = ref.read(storeSelectionProvider);
    final retailerConfig = Retailers.fromName(retailer);
    final categoryValue = retailerConfig != null
        ? _selectedCategory?.valueForRetailer(retailerConfig.slug)
        : null;

    storeState.whenData((selection) {
      final store = selection.forRetailer(retailer);
      if (store != null) {
        ref
            .read(liveProductsProvider.notifier)
            .loadProducts(
              retailer: retailer,
              store: store,
              category: categoryValue,
              refresh: refresh,
            );
      }
    });
  }

  void _onRetailerChanged(String retailer) {
    _searchController.clear();
    setState(() {
      _isSearching = false;
      _selectedCategory = null; // Reset category on retailer change
    });
    ref.read(liveSearchProvider.notifier).clear();
    ref.read(selectedRetailerProvider.notifier).state = retailer;

    final storeState = ref.read(storeSelectionProvider);
    storeState.whenData((selection) {
      final store = selection.forRetailer(retailer);
      if (store != null) {
        ref
            .read(liveProductsProvider.notifier)
            .loadProducts(retailer: retailer, store: store, refresh: true);
      }
    });
  }

  void _onCategorySelected(ProductCategory? category) {
    setState(() => _selectedCategory = category);
    _loadProductsForCurrentRetailer(refresh: true);
  }

  void _showStorePickerSheet(BuildContext context) {
    final storeState = ref.read(storeSelectionProvider);
    final selectedRetailer = ref.read(selectedRetailerProvider);
    storeState.whenData((selection) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => StorePickerSheet(
          stores: selection,
          selectedRetailer: selectedRetailer,
          onRetailerChanged: _onRetailerChanged,
        ),
      );
    });
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();

    if (query.trim().isEmpty) {
      setState(() => _isSearching = false);
      ref.read(liveSearchProvider.notifier).clear();
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      setState(() => _isSearching = true);

      final retailer = ref.read(selectedRetailerProvider);
      final storeState = ref.read(storeSelectionProvider);
      storeState.whenData((selection) {
        final store = selection.forRetailer(retailer);
        if (store != null) {
          ref
              .read(liveSearchProvider.notifier)
              .search(retailer: retailer, store: store, query: query.trim());
        }
      });
    });
  }

  bool get _hasActiveFilters => _promosOnly || _sortOption != SortOption.relevance;

  void _showFilterSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FilterSortSheet(
        isDark: isDark,
        currentSort: _sortOption,
        promosOnly: _promosOnly,
        onApply: (sort, promos) {
          setState(() {
            _sortOption = sort;
            _promosOnly = promos;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedRetailer = ref.watch(selectedRetailerProvider);
    final storeState = ref.watch(storeSelectionProvider);
    final retailerConfig = Retailers.fromName(selectedRetailer);

    NearbyStore? currentStore;
    storeState.whenData((selection) {
      currentStore = selection.forRetailer(selectedRetailer);
    });

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        automaticallyImplyLeading: false,
        backgroundColor: isDark
            ? retailerConfig?.color.withValues(alpha: 0.08)
            : retailerConfig?.colorLight.withValues(alpha: 0.3),
        title: _StoreAppBarButton(
          retailerConfig: retailerConfig,
          currentStore: currentStore,
          onTap: () => _showStorePickerSheet(context),
        ),
        actions: [
          // Filter icon with badge dot when filters are active
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(Icons.tune_rounded),
                tooltip: 'Sort & Filter',
                onPressed: _showFilterSheet,
              ),
              if (_hasActiveFilters)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar (hero element — first in body)
          _buildSearchBar(isDark),

          // Category chip bar (hidden while searching)
          if (!_isSearching)
            _CategoryChipBar(
              selectedRetailer: selectedRetailer,
              selectedCategory: _selectedCategory,
              onSelected: _onCategorySelected,
            ),

          // Active filter chips summary (compact, dismissible)
          if (_hasActiveFilters && !_isSearching)
            _ActiveFilterBar(
              sortOption: _sortOption,
              promosOnly: _promosOnly,
              onClearSort: () => setState(() => _sortOption = SortOption.relevance),
              onClearPromos: () => setState(() => _promosOnly = false),
            ),

          // Products area
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                _loadProductsForCurrentRetailer(refresh: true);
                await Future.delayed(const Duration(milliseconds: 500));
              },
              child: _isSearching
                  ? _buildSearchResults()
                  : _buildBrowseResults(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                    setState(() => _isSearching = false);
                    ref.read(liveSearchProvider.notifier).clear();
                  },
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        onChanged: (value) {
          setState(() {}); // Update clear button visibility
          _onSearchChanged(value);
        },
      ),
    );
  }

  Widget _buildBrowseResults() {
    final productsState = ref.watch(liveProductsProvider);

    return productsState.when(
      data: (response) {
        if (response.products.isEmpty) {
          return const EmptyState(
            type: EmptyStateType.noProducts,
            customMessage:
                'No products available for this store right now. '
                'Try searching or switching to another retailer.',
          );
        }

        // Apply client-side sort & promo filter
        var products = applySort(response.products, _sortOption);
        if (_promosOnly) {
          products = products.where((p) => p.hasPromo).toList();
        }

        if (products.isEmpty) {
          return _buildNoPromoState();
        }

        return _buildProductGrid(
          products: products,
          hasMore: response.hasMorePages && !_promosOnly,
        );
      },
      loading: () => const ProductGridSkeleton(),
      error: (error, _) => _buildErrorState(error),
    );
  }

  Widget _buildSearchResults() {
    final searchState = ref.watch(liveSearchProvider);

    return searchState.when(
      data: (response) {
        if (response.products.isEmpty && _searchController.text.isNotEmpty) {
          return const EmptyState(type: EmptyStateType.noSearchResults);
        }
        if (response.products.isEmpty) return const SizedBox.shrink();

        final products = applySort(response.products, _sortOption);
        return _buildProductGrid(products: products, hasMore: false);
      },
      loading: () => const ProductGridSkeleton(),
      error: (error, _) => _buildErrorState(error),
    );
  }

  Widget _buildProductGrid({
    required List<LiveProduct> products,
    required bool hasMore,
  }) {
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.72,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: products.length + (hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= products.length) {
          return const ShimmerEffect(child: ProductCardSkeleton());
        }

        final product = products[index];
        return AnimatedListItem(
          index: index % 10,
          child: LiveProductCard(
            product: product,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LiveProductDetailScreen(product: product),
                ),
              );
            },
            onCompare: () => showCompareSheet(context, ref, product),
            onLongPress: () => _addToList(product),
          ),
        );
      },
    );
  }

  void _addToList(LiveProduct product) {
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

    showAddToListSheet(
      context,
      ref,
      productName: product.name,
      price: regularPrice,
      retailer: product.retailer,
      specialPrice: specialPrice,
      imageUrl: product.imageUrl,
      priceDisplay: product.price,
      multiBuyInfo: multiBuyInfo,
    );
  }

  Widget _buildNoPromoState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_offer_outlined,
              size: 56,
              color: AppColors.textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              'No promotions right now',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Check back later or browse all products.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => setState(() => _promosOnly = false),
              child: const Text('Show all products'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(Object error) {
    return EmptyState(
      type: EmptyStateType.error,
      customMessage: 'Failed to load products. Pull down to retry.',
      actionLabel: 'Retry',
      onAction: () => _loadProductsForCurrentRetailer(refresh: true),
    );
  }
}

// ─────────────────────────────────────────────
// Store / retailer button for AppBar
// ─────────────────────────────────────────────

class _StoreAppBarButton extends StatelessWidget {
  final RetailerConfig? retailerConfig;
  final NearbyStore? currentStore;
  final VoidCallback onTap;

  const _StoreAppBarButton({
    required this.retailerConfig,
    required this.currentStore,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = retailerConfig?.color ?? AppColors.primary;
    final name = retailerConfig?.name ?? 'Select Store';
    final branch = currentStore?.storeName ?? 'Tap to choose';

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Retailer icon in colored circle
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              retailerConfig?.icon ?? Icons.store,
              size: 18,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          // Retailer name + store branch
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  branch,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 20,
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Category chip bar widget
// ─────────────────────────────────────────────

class _CategoryChipBar extends StatelessWidget {
  final String selectedRetailer;
  final ProductCategory? selectedCategory;
  final ValueChanged<ProductCategory?> onSelected;

  const _CategoryChipBar({
    required this.selectedRetailer,
    required this.selectedCategory,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final retailerConfig = Retailers.fromName(selectedRetailer);
    final accentColor = retailerConfig?.color ?? AppColors.primary;

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: ProductCategories.all.length + 1, // +1 for "All"
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            // "All" chip
            final isSelected = selectedCategory == null;
            return _buildChip(
              context: context,
              label: 'All',
              icon: Icons.grid_view_rounded,
              isSelected: isSelected,
              accentColor: accentColor,
              isDark: isDark,
              onTap: () => onSelected(null),
            );
          }

          final category = ProductCategories.all[index - 1];
          final isSelected = selectedCategory == category;
          return _buildChip(
            context: context,
            label: category.displayName,
            icon: category.icon,
            isSelected: isSelected,
            accentColor: accentColor,
            isDark: isDark,
            onTap: () => onSelected(isSelected ? null : category),
          );
        },
      ),
    );
  }

  Widget _buildChip({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool isSelected,
    required Color accentColor,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor
              : (isDark ? AppColors.surfaceDarkModeLight : AppColors.surface),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? accentColor
                : (isDark ? AppColors.dividerDark : AppColors.divider),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected
                  ? Colors.white
                  : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondary),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Active filter summary bar
// ─────────────────────────────────────────────

class _ActiveFilterBar extends StatelessWidget {
  final SortOption sortOption;
  final bool promosOnly;
  final VoidCallback onClearSort;
  final VoidCallback onClearPromos;

  const _ActiveFilterBar({
    required this.sortOption,
    required this.promosOnly,
    required this.onClearSort,
    required this.onClearPromos,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          if (sortOption != SortOption.relevance)
            _FilterPill(
              label: sortOption.label,
              onRemove: onClearSort,
              isDark: isDark,
            ),
          if (promosOnly)
            _FilterPill(
              label: 'Promos only',
              onRemove: onClearPromos,
              isDark: isDark,
            ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  final bool isDark;

  const _FilterPill({
    required this.label,
    required this.onRemove,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(
              Icons.close_rounded,
              size: 14,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Filter / Sort bottom sheet
// ─────────────────────────────────────────────

class _FilterSortSheet extends StatefulWidget {
  final bool isDark;
  final SortOption currentSort;
  final bool promosOnly;
  final void Function(SortOption sort, bool promosOnly) onApply;

  const _FilterSortSheet({
    required this.isDark,
    required this.currentSort,
    required this.promosOnly,
    required this.onApply,
  });

  @override
  State<_FilterSortSheet> createState() => _FilterSortSheetState();
}

class _FilterSortSheetState extends State<_FilterSortSheet> {
  late SortOption _sort;
  late bool _promosOnly;

  @override
  void initState() {
    super.initState();
    _sort = widget.currentSort;
    _promosOnly = widget.promosOnly;
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isDark ? AppColors.surfaceDarkMode : Colors.white;
    final textPrimary =
        widget.isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final textSecondary =
        widget.isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final divider = widget.isDark ? AppColors.dividerDark : AppColors.divider;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              children: [
                Text(
                  'Sort & Filter',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _sort = SortOption.relevance;
                      _promosOnly = false;
                    });
                  },
                  child: Text(
                    'Reset',
                    style: TextStyle(color: textSecondary),
                  ),
                ),
              ],
            ),
          ),

          Divider(color: divider, height: 1),

          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Filter section
                  Text(
                    'Filter',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Promos only toggle
                  GestureDetector(
                    onTap: () => setState(() => _promosOnly = !_promosOnly),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: _promosOnly
                            ? AppColors.primary.withValues(alpha: 0.08)
                            : (widget.isDark
                                ? AppColors.surfaceDarkModeLight
                                : AppColors.surface),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _promosOnly
                              ? AppColors.primary.withValues(alpha: 0.4)
                              : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.local_offer_rounded,
                            size: 20,
                            color: _promosOnly
                                ? AppColors.primary
                                : textSecondary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Promotions only',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _promosOnly ? AppColors.primary : textPrimary,
                              ),
                            ),
                          ),
                          Switch.adaptive(
                            value: _promosOnly,
                            onChanged: (v) => setState(() => _promosOnly = v),
                            activeThumbColor: AppColors.primary,
                            activeTrackColor: AppColors.primary.withValues(alpha: 0.4),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Sort section
                  Text(
                    'Sort by',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),

                  ...SortOption.values.map((option) {
                    final isSelected = _sort == option;
                    return GestureDetector(
                      onTap: () => setState(() => _sort = option),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary.withValues(alpha: 0.08)
                              : (widget.isDark
                                  ? AppColors.surfaceDarkModeLight
                                  : AppColors.surface),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary.withValues(alpha: 0.4)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                option.label,
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? AppColors.primary
                                      : textPrimary,
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle_rounded,
                                color: AppColors.primary,
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),

          // Apply button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    widget.onApply(_sort, _promosOnly);
                    Navigator.of(context).pop();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Apply',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
