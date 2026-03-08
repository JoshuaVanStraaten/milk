// lib/data/services/product_name_parser.dart
//
// Client-side product name parsing for live API products.
// Extracts brand, size (value + unit), and a normalized name
// for fuzzy matching — mirrors the SQL parse_product_name() function
// but works on LiveProduct data without DB access.

/// Parsed product name components for comparison matching.
class ParsedProductName {
  final String? brand;
  final double? sizeValue;
  final String? sizeUnit;
  final String normalizedName;
  final String originalName;

  const ParsedProductName({
    this.brand,
    this.sizeValue,
    this.sizeUnit,
    required this.normalizedName,
    required this.originalName,
  });

  /// Formatted size string (e.g. "500g", "1.5L")
  String? get formattedSize {
    if (sizeValue == null || sizeUnit == null) return null;
    final sizeStr = sizeValue == sizeValue!.roundToDouble()
        ? sizeValue!.toInt().toString()
        : sizeValue.toString();
    return '$sizeStr$sizeUnit';
  }

  @override
  String toString() =>
      'Parsed(brand: $brand, size: $formattedSize, normalized: "$normalizedName")';
}

/// Match classification for comparison results.
enum MatchType { exact, similar, fallback }

/// A comparison result with match classification.
class ComparisonMatch {
  final String retailer;
  final String name;
  final String price;
  final double priceNumeric;
  final String? promotionPrice;
  final bool hasPromo;
  final String? imageUrl;
  final MatchType matchType;
  final double similarityScore;
  final double? priceDifference;
  final ParsedProductName parsed;

  const ComparisonMatch({
    required this.retailer,
    required this.name,
    required this.price,
    required this.priceNumeric,
    this.promotionPrice,
    this.hasPromo = false,
    this.imageUrl,
    required this.matchType,
    required this.similarityScore,
    this.priceDifference,
    required this.parsed,
  });

  bool get isExactMatch => matchType == MatchType.exact;
  bool get isSimilarMatch => matchType == MatchType.similar;
  bool get isFallbackMatch => matchType == MatchType.fallback;

  bool get isCheaper => priceDifference != null && priceDifference! < 0;
  bool get isMoreExpensive => priceDifference != null && priceDifference! > 0;

  String? get formattedPriceDifference {
    if (priceDifference == null) return null;
    final sign = priceDifference! >= 0 ? '+' : '';
    return '${sign}R${priceDifference!.abs().toStringAsFixed(2)}';
  }

  String get matchQualityLabel {
    switch (matchType) {
      case MatchType.exact:
        return 'Same Product';
      case MatchType.similar:
        return 'Similar Product';
      case MatchType.fallback:
        return 'May Be Similar';
    }
  }
}

// =============================================================================
// PARSER
// =============================================================================

class ProductNameParser {
  ProductNameParser._();

  /// Known SA grocery brand patterns (mirrors SQL brand_patterns array).
  static const _brandPatterns = [
    // Dairy & Beverages
    'clover', 'parmalat', 'woodlands', 'fairfield', 'darling', 'lancewood',
    'danone', 'nutriday', 'ultra mel', 'super m', 'steri stumpie',
    // Hot drinks
    'nescafe', 'nescafé', 'ricoffy', 'frisco', 'jacobs', 'douwe egberts',
    'lipton', 'five roses', 'joko', 'glen', 'freshpak', 'laager',
    // Cereals
    'kellogg\'s', 'kelloggs', 'bokomo', 'weet-bix', 'weetbix', 'pronutro',
    'jungle', 'morvite',
    // Baking & spreads
    'rama', 'stork', 'flora', 'lurpak', 'black cat', 'yum yum',
    // Grains & staples
    'albany', 'sasko', 'blue ribbon', 'tastic', 'spekko', 'ace',
    'iwisa', 'white star', 'fatti\'s & moni\'s', 'fattis & monis',
    // Canned
    'all gold', 'koo', 'rhodes', 'bull brand', 'lucky star', 'john west',
    // Snacks
    'simba', 'lays', 'lay\'s', 'doritos', 'nik naks', 'niknaks',
    'willards', 'bakers', 'tennis', 'romany creams', 'oreo',
    // Confectionery
    'cadbury', 'beacon', 'lindt', 'ferrero', 'bar one', 'lunch bar',
    'kitkat', 'kit kat', 'aero', 'tex', 'jelly tots', 'astros', 'smarties',
    // Beverages
    'coca-cola', 'coca cola', 'pepsi', 'fanta', 'sprite', 'schweppes',
    'appletiser', 'grapetiser', 'liqui fruit', 'ceres', 'tropika',
    'oros', 'energade', 'powerade',
    // Personal care
    'dove', 'lux', 'lifebuoy', 'vaseline', 'nivea', 'garnier',
    'colgate', 'oral-b', 'oral b', 'gillette', 'pantene',
    'head & shoulders', 'always', 'pampers', 'huggies',
    // Cleaning
    'omo', 'sunlight', 'handy andy', 'domestos', 'harpic', 'mr muscle',
    'jik', 'sta-soft', 'sta soft', 'ariel', 'skip', 'surf', 'maq',
    'doom', 'raid', 'mortein',
    // Sauces & condiments
    'knorr', 'maggi', 'royco', 'imana', 'bisto', 'heinz',
    'mrs balls', 'mrs ball\'s', 'nando\'s', 'nandos', 'tabasco',
    'wellington\'s', 'crosse & blackwell', 'hellmann\'s', 'hellmanns',
    // Cooking oils
    'sunfoil', 'excella',
    // Meat & fish
    'enterprise', 'eskort', 'county fair', 'rainbow', 'goldi',
    'i&j', 'sea harvest', 'fry\'s', 'frys',
    // Store brands
    'pnp', 'pick n pay', 'checkers', 'shoprite', 'woolworths',
    'no name', 'housebrand', 'ritebrand',
    // Health
    'dettol', 'savlon', 'disprin', 'panado',
    // Cooking
    'royal', 'dr oetker', 'moir\'s', 'moirs', 'ina paarman',
    'mccain',
  ];

  /// Parse a product name into brand, size, and normalized form.
  static ParsedProductName parse(String name) {
    final lower = name.toLowerCase().trim();

    // -- Extract brand --
    String? brand;
    for (final pattern in _brandPatterns) {
      if (lower.startsWith('$pattern ') || lower.startsWith('$pattern\'')) {
        brand = pattern;
        break;
      }
    }
    // Fallback: first word
    brand ??= lower.split(' ').first.replaceAll("'", '');

    // -- Extract size --
    double? sizeValue;
    String? sizeUnit;

    // Multi-pack: "6 x 100g"
    final multiMatch = RegExp(
      r'(\d+)\s*x\s*(\d+\.?\d*)\s*(g|kg|ml|l|litre|liter)s?\b',
      caseSensitive: false,
    ).firstMatch(lower);

    if (multiMatch != null) {
      sizeValue = double.tryParse(multiMatch.group(2)!);
      sizeUnit = multiMatch.group(3)!.toLowerCase();
    } else {
      // Standard: "500g", "1.5L"
      final sizeMatch = RegExp(
        r'(\d+\.?\d*)\s*(g|kg|ml|l|litre|liter)s?\b',
        caseSensitive: false,
      ).firstMatch(lower);

      if (sizeMatch != null) {
        sizeValue = double.tryParse(sizeMatch.group(1)!);
        sizeUnit = sizeMatch.group(2)!.toLowerCase();
      }
    }

    // Normalize units
    if (sizeUnit == 'litre' || sizeUnit == 'liter') sizeUnit = 'l';

    // -- Normalize name --
    var normalized = lower;
    // Remove multi-pack patterns
    normalized = normalized.replaceAll(
      RegExp(
        r'\d+\s*x\s*\d+\.?\d*\s*(g|kg|ml|l|litre|liter)s?',
        caseSensitive: false,
      ),
      '',
    );
    normalized = normalized.replaceAll(
      RegExp(r'\d+\s*(pack|pk|ea)\b', caseSensitive: false),
      '',
    );
    // Remove size patterns
    normalized = normalized.replaceAll(
      RegExp(r'\d+\.?\d*\s*(g|kg|ml|l|litre|liter)s?\b', caseSensitive: false),
      '',
    );
    // Remove "per kg" patterns
    normalized = normalized.replaceAll(
      RegExp(r'per\s*(kg|g|100g|100ml)\b', caseSensitive: false),
      '',
    );
    // Clean whitespace
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();

    return ParsedProductName(
      brand: brand,
      sizeValue: sizeValue,
      sizeUnit: sizeUnit,
      normalizedName: normalized,
      originalName: name,
    );
  }

  /// Classify a candidate product against a source product.
  ///
  /// Returns null if similarity is below threshold.
  static ComparisonMatch? classify({
    required ParsedProductName source,
    required ParsedProductName candidate,
    required String retailer,
    required String name,
    required String price,
    required double priceNumeric,
    String? promotionPrice,
    bool hasPromo = false,
    String? imageUrl,
    required double sourcePrice,
    double similarityThreshold = 0.25,
  }) {
    final similarity = _wordSimilarity(
      source.normalizedName,
      candidate.normalizedName,
    );

    if (similarity < similarityThreshold) return null;

    // Determine match type
    MatchType matchType;

    final sameBrand =
        source.brand != null &&
        candidate.brand != null &&
        source.brand == candidate.brand;
    final sameSize =
        source.sizeValue != null &&
        candidate.sizeValue != null &&
        source.sizeUnit != null &&
        candidate.sizeUnit != null &&
        _compareSizes(
              source.sizeValue!,
              source.sizeUnit!,
              candidate.sizeValue!,
              candidate.sizeUnit!,
            ) ==
            0;

    if (sameBrand && sameSize && similarity > 0.5) {
      matchType = MatchType.exact;
    } else if (sameBrand && similarity > 0.4) {
      matchType = MatchType.similar;
    } else if (similarity > 0.5) {
      // High similarity even without brand match
      matchType = MatchType.similar;
    } else {
      matchType = MatchType.fallback;
    }

    final priceDiff = priceNumeric - sourcePrice;

    return ComparisonMatch(
      retailer: retailer,
      name: name,
      price: price,
      priceNumeric: priceNumeric,
      promotionPrice: promotionPrice,
      hasPromo: hasPromo,
      imageUrl: imageUrl,
      matchType: matchType,
      similarityScore: similarity,
      priceDifference: priceDiff.abs() < 0.01 ? null : priceDiff,
      parsed: candidate,
    );
  }

  /// Word-overlap Jaccard similarity (0.0 to 1.0).
  static double _wordSimilarity(String a, String b) {
    final wordsA = a.split(RegExp(r'\s+')).where((w) => w.length > 1).toSet();
    final wordsB = b.split(RegExp(r'\s+')).where((w) => w.length > 1).toSet();

    if (wordsA.isEmpty || wordsB.isEmpty) return 0;

    final overlap = wordsA.intersection(wordsB).length;
    return overlap / wordsA.union(wordsB).length;
  }

  /// Compare two sizes, returns 0 if equal, <0 if a < b, >0 if a > b.
  /// Normalizes kg→g and l→ml for comparison.
  static int _compareSizes(
    double valA,
    String unitA,
    double valB,
    String unitB,
  ) {
    final normA = _normalizeToBaseUnit(valA, unitA);
    final normB = _normalizeToBaseUnit(valB, unitB);

    // Different unit types (weight vs volume) — can't compare
    if (normA == null || normB == null) return -1;
    if (normA.unit != normB.unit) return -1;

    final diff = normA.value - normB.value;
    if (diff.abs() < 0.01) return 0;
    return diff > 0 ? 1 : -1;
  }

  static _NormalizedSize? _normalizeToBaseUnit(double value, String unit) {
    switch (unit.toLowerCase()) {
      case 'kg':
        return _NormalizedSize(value * 1000, 'g');
      case 'g':
        return _NormalizedSize(value, 'g');
      case 'l':
        return _NormalizedSize(value * 1000, 'ml');
      case 'ml':
        return _NormalizedSize(value, 'ml');
      default:
        return null;
    }
  }
}

class _NormalizedSize {
  final double value;
  final String unit;
  _NormalizedSize(this.value, this.unit);
}
