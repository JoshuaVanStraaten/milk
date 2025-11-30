/// Model for comparable product results from price comparison
class ComparableProduct {
  final String productIndex;
  final String productName;
  final String? productPrice;
  final String? productPromotionPrice;
  final String? productImageUrl;
  final String retailer;
  final String matchType; // 'EXACT', 'SIMILAR', or 'FALLBACK'
  final double similarityScore;
  final double?
  priceDifference; // Positive = more expensive, Negative = cheaper
  final double? sizeValue;
  final String? sizeUnit;

  ComparableProduct({
    required this.productIndex,
    required this.productName,
    this.productPrice,
    this.productPromotionPrice,
    this.productImageUrl,
    required this.retailer,
    required this.matchType,
    required this.similarityScore,
    this.priceDifference,
    this.sizeValue,
    this.sizeUnit,
  });

  /// Create from Supabase RPC response
  factory ComparableProduct.fromJson(Map<String, dynamic> json) {
    return ComparableProduct(
      productIndex: json['product_index'] as String,
      productName: json['product_name'] as String,
      productPrice: json['product_price'] as String?,
      productPromotionPrice: json['product_promotion_price'] as String?,
      productImageUrl: json['product_image_url'] as String?,
      retailer: json['retailer'] as String,
      matchType: json['match_type'] as String,
      similarityScore: _parseDouble(json['similarity_score']) ?? 0.0,
      priceDifference: _parseDouble(json['price_difference']),
      sizeValue: _parseDouble(json['size_value']),
      sizeUnit: json['size_unit'] as String?,
    );
  }

  /// Helper to parse various numeric types from JSON
  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  /// Check if this product has a promotion
  bool get hasPromotion {
    if (productPromotionPrice == null || productPromotionPrice!.isEmpty) {
      return false;
    }
    final promoLower = productPromotionPrice!.toLowerCase().trim();
    return promoLower != 'no promo' &&
        promoLower != 'no promotion' &&
        promoLower != 'no special';
  }

  /// Get the best display price
  String get displayPrice {
    if (hasPromotion) {
      return productPromotionPrice!;
    }
    return productPrice ?? 'Price not available';
  }

  /// Get numeric price for display
  double? get numericPrice {
    final priceStr = hasPromotion ? productPromotionPrice : productPrice;

    if (priceStr == null) return null;

    final match = RegExp(r'R\s*(\d+\.?\d*)').firstMatch(priceStr);
    if (match != null) {
      return double.tryParse(match.group(1)!);
    }
    return null;
  }

  /// Get formatted size string
  String? get formattedSize {
    if (sizeValue == null || sizeUnit == null) return null;

    // Format nicely: "500g", "1.5L", "2kg"
    final value = sizeValue!;
    final unit = sizeUnit!.toLowerCase();

    if (value == value.toInt()) {
      return '${value.toInt()}$unit';
    }
    return '$value$unit';
  }

  /// Check if this is an exact match
  bool get isExactMatch => matchType == 'EXACT';

  /// Check if this is a similar match
  bool get isSimilarMatch => matchType == 'SIMILAR';

  /// Check if this is a fallback match
  bool get isFallbackMatch => matchType == 'FALLBACK';

  /// Get a human-readable match description
  String get matchDescription {
    switch (matchType) {
      case 'EXACT':
        return 'Same product';
      case 'SIMILAR':
        return 'Similar product';
      case 'FALLBACK':
        return 'Alternative';
      default:
        return 'Match';
    }
  }

  /// Is this product cheaper than the source?
  bool get isCheaper => priceDifference != null && priceDifference! < 0;

  /// Is this product more expensive than the source?
  bool get isMoreExpensive => priceDifference != null && priceDifference! > 0;

  /// Get formatted price difference string
  String? get formattedPriceDifference {
    if (priceDifference == null) return null;

    final diff = priceDifference!.abs();
    final formatted = 'R${diff.toStringAsFixed(2)}';

    if (priceDifference! < 0) {
      return '-$formatted'; // Cheaper
    } else if (priceDifference! > 0) {
      return '+$formatted'; // More expensive
    }
    return 'Same price';
  }

  @override
  String toString() {
    return 'ComparableProduct(name: $productName, retailer: $retailer, matchType: $matchType, priceDiff: $priceDifference)';
  }
}
