// lib/presentation/screens/products/live_browse_screen.dart
//
// REPLACES StoreSelectorScreen as the Browse tab (index 1).
// Shows: retailer chips → store info bar → product grid (live API)
// with search, infinite scroll, and DB fallback.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/nearby_store.dart';
import '../../../data/models/live_product.dart';
import '../../providers/store_provider.dart';
import '../../widgets/common/retailer_selector.dart';
import '../../widgets/products/store_info_bar.dart';
import '../../widgets/products/live_product_card.dart';
import '../../widgets/common/empty_states.dart';
import '../../widgets/skeleton_loaders.dart';
import '../../widgets/animations.dart';
import '../../widgets/products/add_to_list_sheet.dart';
import '../../widgets/products/store_picker_sheet.dart';
import 'live_product_detail_screen.dart';
import '../compare/compare_sheet.dart';

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

  @override
  void initState() {
    super.initState();

    // Infinite scroll listener
    _scrollController.addListener(_onScroll);

    // Load initial products after the widget is built
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
    if (_isSearching) return; // Don't paginate during search

    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.85) {
      ref.read(liveProductsProvider.notifier).loadNextPage();
    }
  }

  /// Load products for the currently selected retailer + store.
  void _loadProductsForCurrentRetailer({bool refresh = false}) {
    final retailer = ref.read(selectedRetailerProvider);
    final storeState = ref.read(storeSelectionProvider);

    storeState.whenData((selection) {
      final store = selection.forRetailer(retailer);
      if (store != null) {
        ref
            .read(liveProductsProvider.notifier)
            .loadProducts(retailer: retailer, store: store, refresh: refresh);
      }
    });
  }

  /// Handle retailer change from chip bar.
  void _onRetailerChanged(String retailer) {
    // Clear search when switching retailers
    _searchController.clear();
    _isSearching = false;
    ref.read(liveSearchProvider.notifier).clear();

    // Update selected retailer
    ref.read(selectedRetailerProvider.notifier).state = retailer;

    // Load products for new retailer
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

  /// Show the store picker bottom sheet
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

  /// Handle search input with debounce.
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedRetailer = ref.watch(selectedRetailerProvider);
    final storeState = ref.watch(storeSelectionProvider);

    // Get the current store for the info bar
    NearbyStore? currentStore;
    storeState.whenData((selection) {
      currentStore = selection.forRetailer(selectedRetailer);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Browse'),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          // Retailer chip bar
          RetailerSelector(
            selectedRetailer: selectedRetailer,
            onSelected: _onRetailerChanged,
          ),

          // Store info bar
          if (currentStore != null)
            StoreInfoBar(
              store: currentStore!,
              onTap: () => _showStorePickerSheet(context),
            ),

          const SizedBox(height: 4),

          // Search bar
          _buildSearchBar(isDark),

          // Products area
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                _loadProductsForCurrentRetailer(refresh: true);
                // Wait a bit for the refresh to complete
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

  /// Build the browse (non-search) product grid.
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

        return _buildProductGrid(
          products: response.products,
          hasMore: response.hasMorePages,
        );
      },
      loading: () => const ProductGridSkeleton(),
      error: (error, _) => _buildErrorState(error),
    );
  }

  /// Build the search results grid.
  Widget _buildSearchResults() {
    final searchState = ref.watch(liveSearchProvider);

    return searchState.when(
      data: (response) {
        if (response.products.isEmpty && _searchController.text.isNotEmpty) {
          return const EmptyState(type: EmptyStateType.noSearchResults);
        }

        if (response.products.isEmpty) {
          return const SizedBox.shrink();
        }

        return _buildProductGrid(
          products: response.products,
          hasMore: false, // Search doesn't paginate for now
        );
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
        // Loading indicator at the end
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
            onLongPress: () {
              // Match existing add-to-list logic from product_list_screen
              double regularPrice = product.priceNumeric;
              double? specialPrice;
              Map<String, double>? multiBuyInfo;

              if (product.hasPromo) {
                multiBuyInfo = product.multiBuyInfo;

                if (multiBuyInfo != null) {
                  // Multi-buy promo: store deal info for smart calculation
                  specialPrice = multiBuyInfo['pricePerItem'];
                } else {
                  // Try to parse promo price directly (e.g. "R29.99")
                  final parsed = double.tryParse(
                    product.promotionPrice
                        .replaceAll('R', '')
                        .replaceAll(',', '')
                        .trim(),
                  );
                  // If we can't parse it (e.g. "Buy any 2 save R10"),
                  // use the regular price as specialPrice so the PROMO
                  // badge still shows in the shopping list.
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
            },
          ),
        );
      },
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
