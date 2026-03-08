// lib/data/models/live_product.dart

/// A product returned by the live retailer API (via Edge Functions).
///
/// This is intentionally separate from [Product] (which represents
/// DB-backed scraped data) to avoid field conflicts and allow both
/// models to coexist during the migration period.
///
/// All Edge Functions return a unified response format with products
/// containing: name, price, promotion_price, retailer, image_url,
/// and promotion_valid.
class LiveProduct {
  /// Product display name
  final String name;

  /// Price as a string (e.g. "R36.99")
  final String price;

  /// Parsed numeric price for sorting/comparison
  final double priceNumeric;

  /// Promotion price string (e.g. "2 For R60", "R29.99", or "No promo")
  final String promotionPrice;

  /// Retailer display name (e.g. "Pick n Pay")
  final String retailer;

  /// Product image URL (may be null for some retailers)
  final String? imageUrl;

  /// Promotion validity text (e.g. "Valid until 2 Mar")
  final String promotionValid;

  /// Whether this product has an active promotion
  final bool hasPromo;

  const LiveProduct({
    required this.name,
    required this.price,
    required this.priceNumeric,
    required this.promotionPrice,
    required this.retailer,
    this.imageUrl,
    this.promotionValid = '',
    this.hasPromo = false,
  });

  /// Parse from the unified Edge Function response.
  ///
  /// Expected JSON shape:
  /// ```json
  /// {
  ///   "name": "Full Cream Milk 2L",
  ///   "price": "R36.99",
  ///   "promotion_price": "2 For R60",
  ///   "retailer": "Pick n Pay",
  ///   "image_url": "https://...",
  ///   "promotion_valid": "Valid until 2 Mar"
  /// }
  /// ```
  factory LiveProduct.fromJson(Map<String, dynamic> json) {
    final priceStr = json['price'] as String? ?? 'R0.00';
    final priceNum = _parsePrice(priceStr);
    final promo = json['promotion_price'] as String? ?? 'No promo';

    return LiveProduct(
      name: _decodeHtmlEntities(json['name'] as String? ?? 'Unknown'),
      price: priceStr,
      priceNumeric: priceNum,
      promotionPrice: _decodeHtmlEntities(promo),
      retailer: json['retailer'] as String? ?? '',
      imageUrl: json['image_url'] as String?,
      promotionValid: json['promotion_valid'] as String? ?? '',
      hasPromo: _hasValidPromo(promo),
    );
  }

  /// Decode HTML entities from Checkers/Shoprite API responses.
  /// e.g. "Fatti&#039;s &amp; Moni&#039;s" → "Fatti's & Moni's"
  static String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&#039;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#x27;', "'")
        .replaceAll('&#x2F;', '/');
  }

  /// Parse "R36.99" → 36.99, handling commas and whitespace.
  static double _parsePrice(String priceStr) {
    return double.tryParse(
          priceStr
              .replaceAll('R', '')
              .replaceAll(',', '')
              .replaceAll(' ', '')
              .trim(),
        ) ??
        0.0;
  }

  /// Check whether the promotion string indicates an active deal.
  static bool _hasValidPromo(String promo) {
    if (promo.isEmpty) return false;
    final lower = promo.toLowerCase().trim();
    return lower != 'no promo' &&
        lower != 'no promotion' &&
        lower != 'no special';
  }

  /// Parse multi-buy promos like "2 For R24" or "Buy 3 for R30".
  ///
  /// Returns `{ quantity, totalPrice, pricePerItem }` or `null`.
  Map<String, double>? get multiBuyInfo {
    if (!hasPromo) return null;

    final promoLower = promotionPrice.toLowerCase();

    // Pattern: "2 for R24" or "3 For R30.00"
    final match = RegExp(
      r'(?:buy\s*)?(\d+)\s*for\s*r\s*(\d+\.?\d*)',
    ).firstMatch(promoLower);

    if (match != null) {
      final qty = double.parse(match.group(1)!);
      final total = double.parse(match.group(2)!);
      return {
        'quantity': qty,
        'totalPrice': total,
        'pricePerItem': total / qty,
      };
    }
    return null;
  }

  /// Effective per-item price considering multi-buy deals.
  double get effectivePrice {
    final multiBuy = multiBuyInfo;
    if (multiBuy != null) return multiBuy['pricePerItem']!;

    if (hasPromo) {
      // Try to extract a numeric price from the promotion string
      final promoNumeric = _parsePrice(promotionPrice);
      if (promoNumeric > 0) return promoNumeric;
    }
    return priceNumeric;
  }

  /// Formatted display price for UI
  String get displayPrice {
    if (hasPromo) return promotionPrice;
    return price;
  }

  /// Create a copy with updated fields
  LiveProduct copyWith({
    String? name,
    String? price,
    double? priceNumeric,
    String? promotionPrice,
    String? retailer,
    String? imageUrl,
    String? promotionValid,
    bool? hasPromo,
  }) {
    return LiveProduct(
      name: name ?? this.name,
      price: price ?? this.price,
      priceNumeric: priceNumeric ?? this.priceNumeric,
      promotionPrice: promotionPrice ?? this.promotionPrice,
      retailer: retailer ?? this.retailer,
      imageUrl: imageUrl ?? this.imageUrl,
      promotionValid: promotionValid ?? this.promotionValid,
      hasPromo: hasPromo ?? this.hasPromo,
    );
  }

  @override
  String toString() => 'LiveProduct($name, $price, $retailer)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiveProduct && name == other.name && retailer == other.retailer;

  @override
  int get hashCode => Object.hash(name, retailer);
}

/// Wrapper for paginated product responses from Edge Functions.
///
/// All product endpoints return this structure:
/// ```json
/// {
///   "products": [...],
///   "pagination": { "current_page": 0, "total_pages": 10, ... },
///   "retailer": "Pick n Pay",
///   "source": "live_enriched"
/// }
/// ```
class LiveProductsResponse {
  final List<LiveProduct> products;
  final int currentPage;
  final int? totalPages;
  final int? totalResults;
  final int pageSize;
  final String retailer;

  /// Source indicator from the Edge Function
  /// (e.g. "live_enriched", "live_basic", "constructor_search")
  final String source;

  const LiveProductsResponse({
    required this.products,
    required this.currentPage,
    this.totalPages,
    this.totalResults,
    required this.pageSize,
    required this.retailer,
    this.source = '',
  });

  factory LiveProductsResponse.fromJson(Map<String, dynamic> json) {
    final pagination = json['pagination'] as Map<String, dynamic>? ?? {};
    final productsJson = json['products'] as List? ?? [];

    return LiveProductsResponse(
      products: productsJson
          .map((p) => LiveProduct.fromJson(p as Map<String, dynamic>))
          .toList(),
      currentPage: pagination['current_page'] as int? ?? 0,
      totalPages: pagination['total_pages'] as int?,
      totalResults: pagination['total_results'] as int?,
      pageSize: pagination['page_size'] as int? ?? 24,
      retailer: json['retailer'] as String? ?? '',
      source: json['source'] as String? ?? '',
    );
  }

  /// Whether there are more pages to load
  bool get hasMorePages {
    if (totalPages == null) return products.isNotEmpty;
    return currentPage < (totalPages! - 1);
  }

  /// Empty response (used as initial state)
  static const LiveProductsResponse empty = LiveProductsResponse(
    products: [],
    currentPage: 0,
    pageSize: 24,
    retailer: '',
  );

  @override
  String toString() =>
      'LiveProductsResponse($retailer: ${products.length} products, '
      'page ${currentPage + 1}/${totalPages ?? "?"})';
}
