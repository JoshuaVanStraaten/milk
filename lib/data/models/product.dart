/// Product model matching the Products table in Supabase
/// Updated to include province and new scraped fields
class Product {
  final String index; // Primary key (text-based unique identifier)
  final String name;
  final String? price; // Can be null or empty
  final String? promotionPrice;
  final String retailer;
  final String? imageUrl;
  final String? promotionValid;

  // New fields from updated schema
  final String province; // Required - province the product belongs to
  final String? brand; // Extracted brand name
  final double? sizeValue; // Extracted size number (e.g., 500)
  final String? sizeUnit; // Size unit (e.g., "g", "ml", "kg")
  final String? normalizedName; // Lowercase, cleaned name for search
  final DateTime? parsedAt; // When the product was last scraped
  final String? category; // Product category

  Product({
    required this.index,
    required this.name,
    this.price,
    this.promotionPrice,
    required this.retailer,
    this.imageUrl,
    this.promotionValid,
    required this.province,
    this.brand,
    this.sizeValue,
    this.sizeUnit,
    this.normalizedName,
    this.parsedAt,
    this.category,
  });

  /// Create Product from Supabase JSON response
  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      index: json['index'] as String,
      name: json['name'] as String? ?? '',
      price: json['price'] as String?,
      promotionPrice: json['promotion_price'] as String?,
      retailer: json['retailer'] as String? ?? '',
      imageUrl: json['image_url'] as String?,
      promotionValid: json['promotion_valid'] as String?,
      province: json['province'] as String? ?? '',
      brand: json['brand'] as String?,
      sizeValue: (json['size_value'] as num?)?.toDouble(),
      sizeUnit: json['size_unit'] as String?,
      normalizedName: json['normalized_name'] as String?,
      parsedAt: json['parsed_at'] != null
          ? DateTime.tryParse(json['parsed_at'] as String)
          : null,
      category: json['category'] as String?,
    );
  }

  /// Convert Product to JSON
  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'name': name,
      'price': price,
      'promotion_price': promotionPrice,
      'retailer': retailer,
      'image_url': imageUrl,
      'promotion_valid': promotionValid,
      'province': province,
      'brand': brand,
      'size_value': sizeValue,
      'size_unit': sizeUnit,
      'normalized_name': normalizedName,
      'parsed_at': parsedAt?.toIso8601String(),
      'category': category,
    };
  }

  /// Create a copy with updated fields
  Product copyWith({
    String? index,
    String? name,
    String? price,
    String? promotionPrice,
    String? retailer,
    String? imageUrl,
    String? promotionValid,
    String? province,
    String? brand,
    double? sizeValue,
    String? sizeUnit,
    String? normalizedName,
    DateTime? parsedAt,
    String? category,
  }) {
    return Product(
      index: index ?? this.index,
      name: name ?? this.name,
      price: price ?? this.price,
      promotionPrice: promotionPrice ?? this.promotionPrice,
      retailer: retailer ?? this.retailer,
      imageUrl: imageUrl ?? this.imageUrl,
      promotionValid: promotionValid ?? this.promotionValid,
      province: province ?? this.province,
      brand: brand ?? this.brand,
      sizeValue: sizeValue ?? this.sizeValue,
      sizeUnit: sizeUnit ?? this.sizeUnit,
      normalizedName: normalizedName ?? this.normalizedName,
      parsedAt: parsedAt ?? this.parsedAt,
      category: category ?? this.category,
    );
  }

  /// Check if product has a promotion
  bool get hasPromotion {
    if (promotionPrice == null || promotionPrice!.isEmpty) {
      return false;
    }

    // Check if promotion text indicates no promotion
    final promoLower = promotionPrice!.toLowerCase().trim();
    if (promoLower == 'no promo' ||
        promoLower == 'no promotion' ||
        promoLower == 'no special') {
      return false;
    }

    // Check if promo price is different from regular price
    return promotionPrice != price;
  }

  /// Parse multi-buy promos like "2 For R24" or "3 for R30"
  /// Returns a map with 'quantity', 'totalPrice', and 'pricePerItem' if it's a multi-buy
  Map<String, double>? get multiBuyInfo {
    if (!hasPromotion) return null;

    final promoLower = promotionPrice!.toLowerCase();

    // Pattern: "2 for R24" or "3 For R30.00"
    final multiBuyMatch = RegExp(
      r'(\d+)\s*for\s*r\s*(\d+\.?\d*)',
    ).firstMatch(promoLower);
    if (multiBuyMatch != null) {
      final quantity = double.parse(multiBuyMatch.group(1)!);
      final totalPrice = double.parse(multiBuyMatch.group(2)!);
      return {
        'quantity': quantity,
        'totalPrice': totalPrice,
        'pricePerItem': totalPrice / quantity,
      };
    }

    // Pattern: "Buy 2 For R89"
    final buyMultiMatch = RegExp(
      r'buy\s*(\d+)\s*for\s*r\s*(\d+\.?\d*)',
    ).firstMatch(promoLower);
    if (buyMultiMatch != null) {
      final quantity = double.parse(buyMultiMatch.group(1)!);
      final totalPrice = double.parse(buyMultiMatch.group(2)!);
      return {
        'quantity': quantity,
        'totalPrice': totalPrice,
        'pricePerItem': totalPrice / quantity,
      };
    }

    return null;
  }

  /// Get the effective price per item (for sorting and comparison)
  /// This considers multi-buy deals and returns per-item cost
  double? get effectivePerItemPrice {
    // Check if it's a multi-buy deal
    final multiBuy = multiBuyInfo;
    if (multiBuy != null) {
      // Multi-buy: return per-item price from the deal
      return multiBuy['pricePerItem'];
    }

    // Has a simple promo? Use promo price
    if (hasPromotion) {
      return numericPromotionPrice ?? numericRegularPrice;
    }

    // No promo: use regular price
    return numericRegularPrice ?? numericPrice;
  }

  /// Get display price (promotion price if available, otherwise regular price)
  String get displayPrice {
    if (hasPromotion) {
      return promotionPrice!;
    }
    return price ?? 'Price not available';
  }

  /// Get formatted size string (e.g., "500g", "1L")
  String? get formattedSize {
    if (sizeValue == null || sizeUnit == null) return null;

    // Format nicely - no decimals for whole numbers
    final valueStr = sizeValue! == sizeValue!.roundToDouble()
        ? sizeValue!.round().toString()
        : sizeValue!.toString();

    return '$valueStr${sizeUnit!}';
  }

  /// Get numeric price for calculations (removes "R" and converts to double)
  double? get numericPrice {
    try {
      final priceStr = displayPrice
          .replaceAll(',', '')
          .replaceAll(RegExp(r'\(.*?\)'), '') // Remove text in parentheses
          .trim();

      // Look for pattern "R" followed by numbers (e.g., "R24.99")
      final rPriceMatch = RegExp(r'R\s*(\d+\.?\d*)').firstMatch(priceStr);
      if (rPriceMatch != null) {
        return double.parse(rPriceMatch.group(1)!);
      }

      // Fallback: Extract last number with decimals (most likely the price)
      final decimalMatches = RegExp(r'(\d+\.\d+)').allMatches(priceStr);
      if (decimalMatches.isNotEmpty) {
        return double.parse(decimalMatches.last.group(1)!);
      }

      // Last resort: Extract last whole number (avoid quantities at start)
      final numberMatches = RegExp(r'(\d+)').allMatches(priceStr);
      if (numberMatches.isNotEmpty) {
        return double.parse(numberMatches.last.group(0)!);
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get numeric regular price
  double? get numericRegularPrice {
    try {
      if (price == null || price!.isEmpty) return null;

      final priceStr = price!
          .replaceAll(',', '')
          .replaceAll(RegExp(r'\(.*?\)'), '')
          .trim();

      // Look for pattern "R" followed by numbers
      final rPriceMatch = RegExp(r'R\s*(\d+\.?\d*)').firstMatch(priceStr);
      if (rPriceMatch != null) {
        return double.parse(rPriceMatch.group(1)!);
      }

      // Fallback: Extract last number with decimals
      final decimalMatches = RegExp(r'(\d+\.\d+)').allMatches(priceStr);
      if (decimalMatches.isNotEmpty) {
        return double.parse(decimalMatches.last.group(1)!);
      }

      // Last resort: Extract last whole number
      final numberMatches = RegExp(r'(\d+)').allMatches(priceStr);
      if (numberMatches.isNotEmpty) {
        return double.parse(numberMatches.last.group(0)!);
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get numeric promotion price
  double? get numericPromotionPrice {
    try {
      if (promotionPrice == null || promotionPrice!.isEmpty) return null;
      if (!hasPromotion) return null;

      final priceStr = promotionPrice!
          .replaceAll(',', '')
          .replaceAll(RegExp(r'\(.*?\)'), '')
          .trim();

      // Look for pattern "R" followed by numbers (most reliable)
      final rPriceMatch = RegExp(r'R\s*(\d+\.?\d*)').firstMatch(priceStr);
      if (rPriceMatch != null) {
        return double.parse(rPriceMatch.group(1)!);
      }

      // Fallback: Extract last number with decimals
      final decimalMatches = RegExp(r'(\d+\.\d+)').allMatches(priceStr);
      if (decimalMatches.isNotEmpty) {
        return double.parse(decimalMatches.last.group(1)!);
      }

      // Last resort: Extract last whole number (avoid quantities at start)
      final numberMatches = RegExp(r'(\d+)').allMatches(priceStr);
      if (numberMatches.isNotEmpty) {
        return double.parse(numberMatches.last.group(0)!);
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Calculate savings amount
  double? get savingsAmount {
    if (!hasPromotion) return null;
    final regular = numericRegularPrice;
    final promo = numericPrice;
    if (regular == null || promo == null) return null;
    return regular - promo;
  }

  /// Calculate savings percentage
  int? get savingsPercentage {
    if (!hasPromotion) return null;
    final regular = numericRegularPrice;
    final promo = numericPrice;
    if (regular == null || promo == null || regular == 0) return null;
    return (((regular - promo) / regular) * 100).round();
  }

  @override
  String toString() {
    return 'Product(name: $name, retailer: $retailer, price: $price, province: $province)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Product && other.index == index;
  }

  @override
  int get hashCode => index.hashCode;
}
