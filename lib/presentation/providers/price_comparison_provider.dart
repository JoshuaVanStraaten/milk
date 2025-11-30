import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/comparable_product.dart';
import '../../data/repositories/product_repository.dart';

/// Provider for the product repository
final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository();
});

/// State for price comparison
class PriceComparisonState {
  final List<ComparableProduct> comparisons;
  final bool isLoading;
  final String? error;
  final String? sourceProductIndex;

  const PriceComparisonState({
    this.comparisons = const [],
    this.isLoading = false,
    this.error,
    this.sourceProductIndex,
  });

  PriceComparisonState copyWith({
    List<ComparableProduct>? comparisons,
    bool? isLoading,
    String? error,
    String? sourceProductIndex,
  }) {
    return PriceComparisonState(
      comparisons: comparisons ?? this.comparisons,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      sourceProductIndex: sourceProductIndex ?? this.sourceProductIndex,
    );
  }

  /// Get only exact matches
  List<ComparableProduct> get exactMatches =>
      comparisons.where((c) => c.isExactMatch).toList();

  /// Get only similar matches
  List<ComparableProduct> get similarMatches =>
      comparisons.where((c) => c.isSimilarMatch).toList();

  /// Get only fallback matches
  List<ComparableProduct> get fallbackMatches =>
      comparisons.where((c) => c.isFallbackMatch).toList();

  /// Check if there are any results
  bool get hasResults => comparisons.isNotEmpty;

  /// Check if there are exact matches
  bool get hasExactMatches => exactMatches.isNotEmpty;

  /// Get the cheapest option (if any)
  ComparableProduct? get cheapestOption {
    if (comparisons.isEmpty) return null;

    // Prefer exact matches first
    final exact = exactMatches;
    if (exact.isNotEmpty) {
      return exact.reduce((a, b) {
        final aPrice = a.numericPrice ?? double.infinity;
        final bPrice = b.numericPrice ?? double.infinity;
        return aPrice < bPrice ? a : b;
      });
    }

    // Fall back to any match
    return comparisons.reduce((a, b) {
      final aPrice = a.numericPrice ?? double.infinity;
      final bPrice = b.numericPrice ?? double.infinity;
      return aPrice < bPrice ? a : b;
    });
  }

  /// Get unique retailers in results
  List<String> get retailers =>
      comparisons.map((c) => c.retailer).toSet().toList();

  /// Group comparisons by retailer
  Map<String, List<ComparableProduct>> get byRetailer {
    final grouped = <String, List<ComparableProduct>>{};
    for (final c in comparisons) {
      grouped.putIfAbsent(c.retailer, () => []);
      grouped[c.retailer]!.add(c);
    }
    return grouped;
  }
}

/// Notifier for price comparison state
class PriceComparisonNotifier extends StateNotifier<PriceComparisonState> {
  final ProductRepository _repository;

  PriceComparisonNotifier(this._repository)
    : super(const PriceComparisonState());

  /// Load comparable products for a given product index
  Future<void> loadComparisons(String productIndex) async {
    // Don't reload if already loaded for this product
    if (state.sourceProductIndex == productIndex && state.hasResults) {
      return;
    }

    state = state.copyWith(
      isLoading: true,
      error: null,
      sourceProductIndex: productIndex,
    );

    try {
      final comparisons = await _repository.findComparableProducts(
        productIndex: productIndex,
      );

      state = state.copyWith(comparisons: comparisons, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Refresh comparisons (force reload)
  Future<void> refresh() async {
    if (state.sourceProductIndex == null) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final comparisons = await _repository.findComparableProducts(
        productIndex: state.sourceProductIndex!,
      );

      state = state.copyWith(comparisons: comparisons, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Clear the comparison state
  void clear() {
    state = const PriceComparisonState();
  }
}

/// Provider for price comparison state
/// Use: ref.watch(priceComparisonProvider)
final priceComparisonProvider =
    StateNotifierProvider<PriceComparisonNotifier, PriceComparisonState>((ref) {
      final repository = ref.watch(productRepositoryProvider);
      return PriceComparisonNotifier(repository);
    });

/// Provider for loading comparisons - auto-disposes when not needed
/// Use: ref.watch(priceComparisonLoaderProvider(productIndex))
final priceComparisonLoaderProvider =
    FutureProvider.family<List<ComparableProduct>, String>((
      ref,
      productIndex,
    ) async {
      final repository = ref.watch(productRepositoryProvider);
      return repository.findComparableProducts(productIndex: productIndex);
    });
