import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/product.dart';
import '../../data/repositories/product_repository.dart';

// Province is no longer user-selectable — the live API uses GPS-based stores.
// This constant is kept for backward compatibility with DB queries (fallback).
const _defaultProvince = 'Gauteng';

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
  final String province; // Track which province products are loaded for

  ProductListState({
    this.products = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.currentPage = 0,
    this.error,
    this.searchQuery = '',
    this.showPromotionsOnly = false,
    this.sortBy = 'none',
    this.province = 'Gauteng',
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
    String? province,
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
      province: province ?? this.province,
    );
  }
}

/// Parameters for product list provider (retailer + province)
class ProductListParams {
  final String retailer;
  final String province;

  ProductListParams({required this.retailer, required this.province});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProductListParams &&
        other.retailer == retailer &&
        other.province == province;
  }

  @override
  int get hashCode => Object.hash(retailer, province);
}

/// Notifier for managing product list with pagination
class ProductListNotifier extends StateNotifier<ProductListState> {
  final ProductRepository _productRepository;
  final String retailer;
  final String province;

  ProductListNotifier(this._productRepository, this.retailer, this.province)
    : super(ProductListState(province: province)) {
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
          province: province,
          retailer: retailer,
        );
      } else if (currentShowPromotionsOnly) {
        products = await _productRepository.getPromotionProducts(
          retailer: retailer,
          province: province,
          page: 0,
        );
      } else {
        products = await _productRepository.getProductsByRetailer(
          retailer: retailer,
          province: province,
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
        province: province,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Load next page of products (pagination)
  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore || state.searchQuery.isNotEmpty) {
      return;
    }

    state = state.copyWith(isLoading: true);

    try {
      final nextPage = state.currentPage + 1;
      List<Product> newProducts;

      if (state.showPromotionsOnly) {
        newProducts = await _productRepository.getPromotionProducts(
          retailer: retailer,
          province: province,
          page: nextPage,
        );
      } else {
        newProducts = await _productRepository.getProductsByRetailer(
          retailer: retailer,
          province: province,
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

/// Provider family for product list by retailer AND province
/// Usage: ref.watch(productListProvider(ProductListParams(retailer: 'Pick n Pay', province: 'Gauteng')))
final productListProviderFamily =
    StateNotifierProvider.family<
      ProductListNotifier,
      ProductListState,
      ProductListParams
    >((ref, params) {
      final repository = ref.watch(productRepositoryProvider);
      return ProductListNotifier(repository, params.retailer, params.province);
    });

/// Convenience provider that auto-uses the selected province
/// Usage: ref.watch(productListProvider('Pick n Pay'))
final productListProvider =
    StateNotifierProvider.family<ProductListNotifier, ProductListState, String>(
      (ref, retailer) {
        final repository = ref.watch(productRepositoryProvider);
        final province = _defaultProvince;
        return ProductListNotifier(repository, retailer, province);
      },
    );

/// Provider for searching products (uses selected province)
final productSearchProvider = FutureProvider.family<List<Product>, String>((
  ref,
  query,
) async {
  if (query.isEmpty) return [];

  final repository = ref.watch(productRepositoryProvider);
  final province = _defaultProvince;
  return repository.searchProducts(query: query, province: province);
});

/// Provider for searching products in specific retailer (uses selected province)
final productSearchInRetailerProvider =
    FutureProvider.family<List<Product>, ({String query, String retailer})>((
      ref,
      params,
    ) async {
      if (params.query.isEmpty) return [];

      final repository = ref.watch(productRepositoryProvider);
      final province = _defaultProvince;
      return repository.searchProducts(
        query: params.query,
        province: province,
        retailer: params.retailer,
      );
    });

/// Provider for promotion products by retailer (uses selected province)
final promotionProductsProvider = FutureProvider.family<List<Product>, String>((
  ref,
  retailer,
) async {
  final repository = ref.watch(productRepositoryProvider);
  final province = _defaultProvince;
  return repository.getPromotionProducts(
    retailer: retailer,
    province: province,
  );
});

/// Provider for product count by retailer (uses selected province)
final productCountProvider = FutureProvider.family<int, String?>((
  ref,
  retailer,
) async {
  final repository = ref.watch(productRepositoryProvider);
  final province = _defaultProvince;
  return repository.getProductCount(retailer: retailer, province: province);
});

/// Provider for product categories (uses selected province)
final productCategoriesProvider = FutureProvider.family<List<String>, String?>((
  ref,
  retailer,
) async {
  final repository = ref.watch(productRepositoryProvider);
  final province = _defaultProvince;
  return repository.getCategories(province: province, retailer: retailer);
});
