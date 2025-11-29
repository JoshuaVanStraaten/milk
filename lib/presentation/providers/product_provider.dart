import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/product.dart';
import '../../data/repositories/product_repository.dart';

/// Provider for ProductRepository instance
final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository();
});

/// State for product list with pagination
class ProductListState {
  final List<Product> products;
  final bool isLoading;
  final bool hasMore;
  final int currentPage;
  final String? error;
  final String searchQuery;
  final bool showPromotionsOnly;
  final String sortBy; // 'none', 'price_asc', 'price_desc', 'name_asc'

  ProductListState({
    this.products = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.currentPage = 0,
    this.error,
    this.searchQuery = '',
    this.showPromotionsOnly = false,
    this.sortBy = 'none',
  });

  ProductListState copyWith({
    List<Product>? products,
    bool? isLoading,
    bool? hasMore,
    int? currentPage,
    String? error,
    String? searchQuery,
    bool? showPromotionsOnly,
    String? sortBy,
  }) {
    return ProductListState(
      products: products ?? this.products,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      error: error ?? this.error,
      searchQuery: searchQuery ?? this.searchQuery,
      showPromotionsOnly: showPromotionsOnly ?? this.showPromotionsOnly,
      sortBy: sortBy ?? this.sortBy,
    );
  }
}

/// Notifier for managing product list with pagination
class ProductListNotifier extends StateNotifier<ProductListState> {
  final ProductRepository _productRepository;
  final String retailer;

  ProductListNotifier(this._productRepository, this.retailer)
    : super(ProductListState()) {
    // Load initial products when created
    loadProducts();
  }

  /// Load products (initial load or refresh)
  Future<void> loadProducts() async {
    // Get current state values BEFORE setting loading
    final currentSearchQuery = state.searchQuery;
    final currentShowPromotionsOnly = state.showPromotionsOnly;
    final currentSortBy = state.sortBy;

    state = state.copyWith(isLoading: true, error: null);

    try {
      List<Product> products;

      // Search or regular load
      if (currentSearchQuery.isNotEmpty) {
        products = await _productRepository.searchProducts(
          query: currentSearchQuery,
          retailer: retailer,
        );
      } else if (currentShowPromotionsOnly) {
        products = await _productRepository.getPromotionProducts(
          retailer: retailer,
          page: 0,
        );
      } else {
        products = await _productRepository.getProductsByRetailer(
          retailer: retailer,
          page: 0,
        );
      }

      // Apply sorting using the current sort order
      products = _sortProductsWithOrder(products, currentSortBy);

      // Create completely new state
      state = ProductListState(
        products: products,
        isLoading: false,
        hasMore: products.isNotEmpty && currentSearchQuery.isEmpty,
        currentPage: 0,
        searchQuery: currentSearchQuery,
        showPromotionsOnly: currentShowPromotionsOnly,
        sortBy: currentSortBy,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Load next page of products (pagination)
  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore || state.searchQuery.isNotEmpty)
      return;

    state = state.copyWith(isLoading: true);

    try {
      final nextPage = state.currentPage + 1;
      List<Product> newProducts;

      if (state.showPromotionsOnly) {
        newProducts = await _productRepository.getPromotionProducts(
          retailer: retailer,
          page: nextPage,
        );
      } else {
        newProducts = await _productRepository.getProductsByRetailer(
          retailer: retailer,
          page: nextPage,
        );
      }

      final hasMore = newProducts.isNotEmpty;

      // Combine old and new products
      final combinedProducts = [...state.products, ...newProducts];

      // Remove duplicates by product index (keep first occurrence)
      final seenIndices = <String>{};
      final uniqueProducts = combinedProducts.where((product) {
        if (seenIndices.contains(product.index)) {
          return false; // Skip duplicate
        }
        seenIndices.add(product.index);
        return true; // Keep first occurrence
      }).toList();

      // Sort the entire unique list
      final sortedProducts = _sortProductsWithOrder(
        uniqueProducts,
        state.sortBy,
      );

      state = state.copyWith(
        products: sortedProducts,
        isLoading: false,
        hasMore: hasMore,
        currentPage: nextPage,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Search products
  Future<void> search(String query) async {
    state = state.copyWith(searchQuery: query);
    await loadProducts();
  }

  /// Toggle promotions filter
  Future<void> togglePromotionsFilter() async {
    // Toggle the flag first
    final newShowPromotionsOnly = !state.showPromotionsOnly;

    // Update state with new filter value
    state = state.copyWith(
      showPromotionsOnly: newShowPromotionsOnly,
      currentPage: 0, // Reset to page 0
    );

    // Reload products with the new filter
    await loadProducts();
  }

  /// Set sort order
  Future<void> setSortOrder(String sortBy) async {
    // Update state with new sort order
    state = state.copyWith(
      sortBy: sortBy,
      currentPage: 0, // Reset to page 0
    );

    // Reload products with the new sort
    await loadProducts();
  }

  /// Refresh products (pull to refresh)
  Future<void> refresh() async {
    state = state.copyWith(currentPage: 0);
    await loadProducts();
  }

  /// Sort products based on given sort order
  List<Product> _sortProductsWithOrder(List<Product> products, String sortBy) {
    switch (sortBy) {
      case 'price_asc':
        products.sort((a, b) {
          final priceA = a.numericRegularPrice ?? double.infinity;
          final priceB = b.numericRegularPrice ?? double.infinity;
          return priceA.compareTo(priceB);
        });
        break;
      case 'price_desc':
        products.sort((a, b) {
          final priceA = a.numericRegularPrice ?? 0.0;
          final priceB = b.numericRegularPrice ?? 0.0;
          return priceB.compareTo(priceA);
        });
        break;
      case 'name_asc':
        products.sort((a, b) => a.name.compareTo(b.name));
        break;
      default:
        // No sorting
        break;
    }
    return products;
  }
}

/// Provider family for product list by retailer
/// Usage: ref.watch(productListProvider('Pick n Pay'))
final productListProvider =
    StateNotifierProvider.family<ProductListNotifier, ProductListState, String>(
      (ref, retailer) {
        final repository = ref.watch(productRepositoryProvider);
        return ProductListNotifier(repository, retailer);
      },
    );

/// Provider for searching products
final productSearchProvider = FutureProvider.family<List<Product>, String>((
  ref,
  query,
) async {
  if (query.isEmpty) return [];

  final repository = ref.watch(productRepositoryProvider);
  return repository.searchProducts(query: query);
});

/// Provider for promotion products by retailer
final promotionProductsProvider = FutureProvider.family<List<Product>, String>((
  ref,
  retailer,
) async {
  final repository = ref.watch(productRepositoryProvider);
  return repository.getPromotionProducts(retailer: retailer);
});
