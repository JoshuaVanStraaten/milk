import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import '../../core/constants/app_constants.dart';
import '../models/product.dart';
import '../models/comparable_product.dart';

/// Repository for product operations
/// Handles fetching products from Supabase with pagination and filtering
/// All queries now require a province parameter for regional filtering
class ProductRepository {
  final SupabaseClient _supabase = SupabaseConfig.client;
  final Logger _logger = Logger();

  /// Fetch products for a specific retailer with pagination
  ///
  /// [retailer]: Store name (e.g., "Pick n Pay")
  /// [province]: Province to filter by (required)
  /// [page]: Page number (0-indexed)
  /// [limit]: Number of products per page
  Future<List<Product>> getProductsByRetailer({
    required String retailer,
    required String province,
    int page = 0,
    int limit = AppConstants.productsPerPage,
  }) async {
    try {
      _logger.d(
        'Fetching products for $retailer in $province (page: $page, limit: $limit)',
      );

      final startIndex = page * limit;
      final endIndex = startIndex + limit - 1;

      final response = await _supabase
          .from('Products')
          .select()
          .eq('retailer', retailer)
          .eq('province', province)
          .range(startIndex, endIndex);

      final products = (response as List)
          .map((json) => Product.fromJson(json))
          .toList();

      _logger.i(
        '✅ Fetched ${products.length} products for $retailer in $province',
      );

      return products;
    } catch (e, stackTrace) {
      _logger.e(
        'Error fetching products for $retailer in $province',
        error: e,
        stackTrace: stackTrace,
      );
      throw Exception('Failed to fetch products: $e');
    }
  }

  /// Search products by name across all retailers or specific retailer
  ///
  /// [query]: Search term
  /// [province]: Province to filter by (required)
  /// [retailer]: Optional - filter by retailer
  /// [limit]: Max results to return
  Future<List<Product>> searchProducts({
    required String query,
    required String province,
    String? retailer,
    int limit = 50,
  }) async {
    try {
      _logger.d(
        'Searching products: "$query" in $province ${retailer != null ? "at $retailer" : ""}',
      );

      var queryBuilder = _supabase
          .from('Products')
          .select()
          .eq('province', province)
          .ilike('name', '%$query%'); // Case-insensitive search

      // Filter by retailer if specified
      if (retailer != null) {
        queryBuilder = queryBuilder.eq('retailer', retailer);
      }

      final response = await queryBuilder.limit(limit);

      final products = (response as List)
          .map((json) => Product.fromJson(json))
          .toList();

      _logger.i(
        '✅ Found ${products.length} products matching "$query" in $province',
      );

      return products;
    } catch (e, stackTrace) {
      _logger.e('Error searching products', error: e, stackTrace: stackTrace);
      throw Exception('Failed to search products: $e');
    }
  }

  /// Get products on promotion for a specific retailer
  ///
  /// [retailer]: Store name
  /// [province]: Province to filter by (required)
  /// [page]: Page number (0-indexed)
  /// [limit]: Number of products per page
  Future<List<Product>> getPromotionProducts({
    required String retailer,
    required String province,
    int page = 0,
    int limit = 50,
  }) async {
    try {
      _logger.d(
        'Fetching promotion products for $retailer in $province (page: $page)',
      );

      final startIndex = page * limit;

      // Fetch more than we need since we'll filter out "No promo"
      final fetchLimit = limit * 3;
      final response = await _supabase
          .from('Products')
          .select()
          .eq('retailer', retailer)
          .eq('province', province)
          .not('promotion_price', 'is', null)
          .range(startIndex, startIndex + fetchLimit - 1);

      final allProducts = (response as List)
          .map((json) => Product.fromJson(json))
          .toList();

      // Filter out "No promo" products using the Product model's logic
      final promoProducts = allProducts
          .where((product) => product.hasPromotion)
          .take(limit)
          .toList();

      _logger.i(
        '✅ Fetched ${promoProducts.length} promotion products for $retailer in $province',
      );

      return promoProducts;
    } catch (e, stackTrace) {
      _logger.e(
        'Error fetching promotion products',
        error: e,
        stackTrace: stackTrace,
      );
      throw Exception('Failed to fetch promotion products: $e');
    }
  }

  /// Get a single product by index
  /// Note: Product index is unique across all provinces
  Future<Product> getProductByIndex(String index) async {
    try {
      _logger.d('Fetching product: $index');

      final response = await _supabase
          .from('Products')
          .select()
          .eq('index', index)
          .single();

      final product = Product.fromJson(response);

      _logger.i('✅ Fetched product: ${product.name}');

      return product;
    } catch (e, stackTrace) {
      _logger.e(
        'Error fetching product by index',
        error: e,
        stackTrace: stackTrace,
      );
      throw Exception('Failed to fetch product: $e');
    }
  }

  /// Get total count of products for a retailer (useful for pagination)
  ///
  /// [retailer]: Optional - filter by retailer
  /// [province]: Province to filter by (required)
  Future<int> getProductCount({
    String? retailer,
    required String province,
  }) async {
    try {
      // Build the query with filter first, then add count
      var query = _supabase
          .from('Products')
          .select('index')
          .eq('province', province);

      if (retailer != null) {
        query = query.eq('retailer', retailer);
      }

      // Add count to the query
      final response = await query.count();

      return response.count;
    } catch (e, stackTrace) {
      _logger.e(
        'Error getting product count',
        error: e,
        stackTrace: stackTrace,
      );
      return 0;
    }
  }

  /// Find comparable products at other retailers for price comparison
  ///
  /// [productIndex]: The index of the product to compare
  /// [province]: Province to filter by (required)
  /// [similarityThreshold]: Minimum similarity score (0.0 - 1.0), default 0.4
  ///
  /// Returns a list of comparable products ordered by:
  /// 1. Match type (EXACT > SIMILAR > FALLBACK)
  /// 2. Similarity score (highest first)
  /// 3. Price (cheapest first)
  Future<List<ComparableProduct>> findComparableProducts({
    required String productIndex,
    required String province,
    double similarityThreshold = 0.4,
  }) async {
    try {
      _logger.d(
        'Finding comparable products for index: $productIndex in $province',
      );

      final response = await _supabase.rpc(
        'find_comparable_products',
        params: {
          'source_product_index': productIndex,
          'target_province': province,
          'similarity_threshold': similarityThreshold,
        },
      );

      if (response == null) {
        _logger.w('No comparable products found (null response)');
        return [];
      }

      final comparisons = (response as List)
          .map((json) => ComparableProduct.fromJson(json))
          .toList();

      _logger.i('✅ Found ${comparisons.length} comparable products');

      // Log match breakdown for debugging
      final exact = comparisons.where((c) => c.isExactMatch).length;
      final similar = comparisons.where((c) => c.isSimilarMatch).length;
      final fallback = comparisons.where((c) => c.isFallbackMatch).length;
      _logger.d(
        'Match breakdown - EXACT: $exact, SIMILAR: $similar, FALLBACK: $fallback',
      );

      return comparisons;
    } catch (e, stackTrace) {
      _logger.e(
        'Error finding comparable products',
        error: e,
        stackTrace: stackTrace,
      );
      // Return empty list instead of throwing - comparison is non-critical
      return [];
    }
  }

  /// Get products by category
  ///
  /// [category]: Product category
  /// [province]: Province to filter by (required)
  /// [retailer]: Optional - filter by retailer
  /// [limit]: Max results to return
  Future<List<Product>> getProductsByCategory({
    required String category,
    required String province,
    String? retailer,
    int limit = 50,
  }) async {
    try {
      _logger.d('Fetching products in category: $category for $province');

      var queryBuilder = _supabase
          .from('Products')
          .select()
          .eq('province', province)
          .eq('category', category);

      if (retailer != null) {
        queryBuilder = queryBuilder.eq('retailer', retailer);
      }

      final response = await queryBuilder.order('name').limit(limit);

      final products = (response as List)
          .map((json) => Product.fromJson(json))
          .toList();

      _logger.i('✅ Fetched ${products.length} products in $category');

      return products;
    } catch (e, stackTrace) {
      _logger.e(
        'Error fetching products by category',
        error: e,
        stackTrace: stackTrace,
      );
      throw Exception('Failed to fetch products: $e');
    }
  }

  /// Get all unique categories for a province
  ///
  /// [province]: Province to get categories for
  /// [retailer]: Optional - filter by retailer
  Future<List<String>> getCategories({
    required String province,
    String? retailer,
  }) async {
    try {
      _logger.d('Fetching categories for $province');

      var queryBuilder = _supabase
          .from('Products')
          .select('category')
          .eq('province', province)
          .not('category', 'is', null);

      if (retailer != null) {
        queryBuilder = queryBuilder.eq('retailer', retailer);
      }

      final response = await queryBuilder;

      // Extract unique categories
      final categories =
          (response as List)
              .map((json) => json['category'] as String?)
              .where((c) => c != null && c.isNotEmpty)
              .cast<String>()
              .toSet()
              .toList()
            ..sort();

      _logger.i('✅ Found ${categories.length} categories');

      return categories;
    } catch (e, stackTrace) {
      _logger.e('Error fetching categories', error: e, stackTrace: stackTrace);
      return [];
    }
  }

  /// Group comparable products by retailer
  ///
  /// Useful for displaying "Best price at each store" view
  Map<String, List<ComparableProduct>> groupByRetailer(
    List<ComparableProduct> products,
  ) {
    final grouped = <String, List<ComparableProduct>>{};

    for (final product in products) {
      grouped.putIfAbsent(product.retailer, () => []);
      grouped[product.retailer]!.add(product);
    }

    return grouped;
  }

  /// Get the best price for each retailer
  ///
  /// Returns a map of retailer -> cheapest ComparableProduct
  Map<String, ComparableProduct> getBestPricePerRetailer(
    List<ComparableProduct> products,
  ) {
    final best = <String, ComparableProduct>{};

    for (final product in products) {
      final existing = best[product.retailer];

      if (existing == null) {
        best[product.retailer] = product;
      } else {
        // Prefer exact matches, then by price
        if (product.isExactMatch && !existing.isExactMatch) {
          best[product.retailer] = product;
        } else if (product.isExactMatch == existing.isExactMatch) {
          // Same match type - compare prices
          final productPrice = product.numericPrice;
          final existingPrice = existing.numericPrice;

          if (productPrice != null && existingPrice != null) {
            if (productPrice < existingPrice) {
              best[product.retailer] = product;
            }
          }
        }
      }
    }

    return best;
  }
}
