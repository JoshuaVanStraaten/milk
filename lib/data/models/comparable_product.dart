/// Represents a product from another retailer that is comparable to a source product
/// Used for price comparison functionality
class ComparableProduct {
  final String productIndex;
  final String productName;
  final String? productPrice;
  final String? productPromotionPrice;
  final String? productImageUrl;
  final String retailer;
  final String matchType; // 'EXACT', 'SIMILAR', or 'FALLBACK'
  final double similarityScore;
  final double? priceDifference;
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

  /// Create from Supabase RPC response (find_comparable_products function)
  /// Note: Field names in JSON match the SQL function output
  /// Property names match what the UI expects (productXxx naming)
  factory ComparableProduct.fromJson(Map<String, dynamic> json) {
    return ComparableProduct(
      // SQL returns 'index' -> maps to productIndex
      productIndex: json['index'] as String? ?? '',
      // SQL returns 'name' -> maps to productName
      productName: json['name'] as String? ?? '',
      // SQL returns 'price' -> maps to productPrice
      productPrice: json['price'] as String?,
      // SQL returns 'promotion_price' -> maps to productPromotionPrice
      productPromotionPrice: json['promotion_price'] as String?,
      // SQL returns 'image_url' -> maps to productImageUrl
      productImageUrl: json['image_url'] as String?,
      // SQL returns 'retailer' directly
      retailer: json['retailer'] as String? ?? '',
      // SQL returns 'match_type'
      matchType: json['match_type'] as String? ?? 'FALLBACK',
      // SQL returns 'similarity_score'
      similarityScore: (json['similarity_score'] as num?)?.toDouble() ?? 0.0,
      // SQL returns 'price_diff' -> maps to priceDifference
      priceDifference: (json['price_diff'] as num?)?.toDouble(),
      // SQL returns 'size_value'
      sizeValue: (json['size_value'] as num?)?.toDouble(),
      // SQL returns 'size_unit'
      sizeUnit: json['size_unit'] as String?,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'index': productIndex,
      'name': productName,
      'price': productPrice,
      'promotion_price': productPromotionPrice,
      'image_url': productImageUrl,
      'retailer': retailer,
      'match_type': matchType,
      'similarity_score': similarityScore,
      'price_diff': priceDifference,
      'size_value': sizeValue,
      'size_unit': sizeUnit,
    };
  }

  /// Whether this is an exact match (same brand, size, high similarity)
  bool get isExactMatch => matchType == 'EXACT';

  /// Whether this is a similar match (same brand, good similarity)
  bool get isSimilarMatch => matchType == 'SIMILAR';

  /// Whether this is a fallback match (name similarity only)
  bool get isFallbackMatch => matchType == 'FALLBACK';

  /// Extract numeric price from price string (e.g., "R89.99" -> 89.99)
  double? get numericPrice {
    if (productPrice == null) return null;
    final match = RegExp(r'R?\s*(\d+\.?\d*)').firstMatch(productPrice!);
    if (match != null) {
      return double.tryParse(match.group(1)!);
    }
    return null;
  }

  /// Extract numeric promotion price
  double? get numericPromotionPrice {
    if (productPromotionPrice == null || productPromotionPrice!.isEmpty)
      return null;
    // Handle "No promo" or similar text
    if (productPromotionPrice!.toLowerCase().contains('no promo')) return null;

    final match = RegExp(
      r'R?\s*(\d+\.?\d*)',
    ).firstMatch(productPromotionPrice!);
    if (match != null) {
      return double.tryParse(match.group(1)!);
    }
    return null;
  }

  /// Get the effective price (promotion price if available, otherwise regular price)
  double? get effectivePrice {
    return numericPromotionPrice ?? numericPrice;
  }

  /// Whether this product has a valid promotion
  bool get hasPromotion {
    if (productPromotionPrice == null || productPromotionPrice!.isEmpty)
      return false;
    if (productPromotionPrice!.toLowerCase().contains('no promo')) return false;
    return numericPromotionPrice != null;
  }

  /// Formatted price difference string
  String? get formattedPriceDifference {
    if (priceDifference == null) return null;
    final sign = priceDifference! >= 0 ? '+' : '';
    return '${sign}R${priceDifference!.abs().toStringAsFixed(2)}';
  }

  /// Whether this product is cheaper than the source
  bool get isCheaper => priceDifference != null && priceDifference! < 0;

  /// Whether this product is more expensive than the source
  bool get isMoreExpensive => priceDifference != null && priceDifference! > 0;

  /// Formatted size string (e.g., "500g", "1L")
  String? get formattedSize {
    if (sizeValue == null || sizeUnit == null) return null;
    // Format without decimals if whole number
    final sizeStr = sizeValue! == sizeValue!.roundToDouble()
        ? sizeValue!.toInt().toString()
        : sizeValue!.toString();
    return '$sizeStr$sizeUnit';
  }

  /// Similarity as percentage string (e.g., "85%")
  String get similarityPercentage => '${(similarityScore * 100).toInt()}%';

  /// Match quality indicator for UI
  String get matchQualityLabel {
    switch (matchType) {
      case 'EXACT':
        return 'Exact Match';
      case 'SIMILAR':
        return 'Similar Product';
      case 'FALLBACK':
        return 'May Be Similar';
      default:
        return 'Unknown';
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComparableProduct &&
          runtimeType == other.runtimeType &&
          productIndex == other.productIndex;

  @override
  int get hashCode => productIndex.hashCode;

  @override
  String toString() {
    return 'ComparableProduct(index: $productIndex, name: $productName, retailer: $retailer, '
        'matchType: $matchType, similarityScore: $similarityScore)';
  }
}
