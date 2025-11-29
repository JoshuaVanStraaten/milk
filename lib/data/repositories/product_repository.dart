import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import '../../core/constants/app_constants.dart';
import '../models/product.dart';

/// Repository for product operations
/// Handles fetching products from Supabase with pagination and filtering
class ProductRepository {
  final SupabaseClient _supabase = SupabaseConfig.client;
  final Logger _logger = Logger();

  /// Fetch products for a specific retailer with pagination
  ///
  /// [retailer]: Store name (e.g., "Pick n Pay")
  /// [page]: Page number (0-indexed)
  /// [limit]: Number of products per page
  Future<List<Product>> getProductsByRetailer({
    required String retailer,
    int page = 0,
    int limit = AppConstants.productsPerPage,
  }) async {
    try {
      _logger.d('Fetching products for $retailer (page: $page, limit: $limit)');

      final startIndex = page * limit;
      final endIndex = startIndex + limit - 1;

      final response = await _supabase
          .from('Products')
          .select()
          .eq('retailer', retailer)
          .range(startIndex, endIndex);

      final products = (response as List)
          .map((json) => Product.fromJson(json))
          .toList();

      _logger.i('✅ Fetched ${products.length} products for $retailer');

      return products;
    } catch (e, stackTrace) {
      _logger.e(
        'Error fetching products for $retailer',
        error: e,
        stackTrace: stackTrace,
      );
      throw Exception('Failed to fetch products: $e');
    }
  }

  /// Search products by name across all retailers or specific retailer
  ///
  /// [query]: Search term
  /// [retailer]: Optional - filter by retailer
  /// [limit]: Max results to return
  Future<List<Product>> searchProducts({
    required String query,
    String? retailer,
    int limit = 50,
  }) async {
    try {
      _logger.d(
        'Searching products: "$query" ${retailer != null ? "in $retailer" : ""}',
      );

      var queryBuilder = _supabase
          .from('Products')
          .select()
          .ilike('name', '%$query%'); // Case-insensitive search

      // Filter by retailer if specified
      if (retailer != null) {
        queryBuilder = queryBuilder.eq('retailer', retailer);
      }

      final response = await queryBuilder.limit(limit);

      final products = (response as List)
          .map((json) => Product.fromJson(json))
          .toList();

      _logger.i('✅ Found ${products.length} products matching "$query"');

      return products;
    } catch (e, stackTrace) {
      _logger.e('Error searching products', error: e, stackTrace: stackTrace);
      throw Exception('Failed to search products: $e');
    }
  }

  /// Get products on promotion for a specific retailer
  Future<List<Product>> getPromotionProducts({
    required String retailer,
    int page = 0,
    int limit = 50,
  }) async {
    try {
      _logger.d('Fetching promotion products for $retailer (page: $page)');

      final startIndex = page * limit;

      // Fetch more than we need since we'll filter out "No promo"
      final fetchLimit = limit * 3;
      final response = await _supabase
          .from('Products')
          .select()
          .eq('retailer', retailer)
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
        '✅ Fetched ${promoProducts.length} promotion products for $retailer',
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
  Future<int> getProductCount({String? retailer}) async {
    try {
      // Build the query with filter first, then add count
      var query = _supabase.from('Products').select('index');

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
}
