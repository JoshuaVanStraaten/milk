// lib/data/services/product_name_parser.dart
//
// Client-side product name parsing for live API products.
// Extracts brand, size (value + unit), pack count, variants, and a normalized
// name for fuzzy matching — mirrors the SQL parse_product_name() function
// but works on LiveProduct data without DB access.

/// Parsed product name components for comparison matching.
class ParsedProductName {
  final String? brand;
  final double? sizeValue;
  final String? sizeUnit;
  final int? packCount;
  final double? totalSize;
  final Set<String> variants;
  final Map<String, String> variantGroups;
  final String normalizedName;
  final String originalName;

  const ParsedProductName({
    this.brand,
    this.sizeValue,
    this.sizeUnit,
    this.packCount,
    this.totalSize,
    this.variants = const {},
    this.variantGroups = const {},
    required this.normalizedName,
    required this.originalName,
  });

  /// Build a search query optimized for retailer search APIs.
  /// Unlike normalizedName (which strips brand for Jaccard scoring),
  /// this KEEPS brand + core product words + full size (including multi-pack),
  /// strips only packaging filler words.
  String get searchQuery {
    var query = originalName.toLowerCase().trim();

    // Remove filler/packaging words that pollute search results
    const fillerWords = {
      'plastic', 'bottle', 'can', 'tin', 'box', 'bag', 'sachet',
      'pouch', 'tub', 'jar', 'container', 'carton', 'slab', 'bar',
      'loaf', 'roll', 'pack', 'tube', 'each', 'avg', 'approx',
    };
    final words = query
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && !fillerWords.contains(w))
        .toList();
    query = words.join(' ').trim();

    // Fallback: if we stripped too much, use original name
    if (query.length < 3) return originalName.trim();

    return query;
  }

  /// Formatted size string (e.g. "500g", "1.5L", "6x200ml")
  String? get formattedSize {
    if (sizeValue == null || sizeUnit == null) return null;
    final sizeStr = sizeValue == sizeValue!.roundToDouble()
        ? sizeValue!.toInt().toString()
        : sizeValue.toString();
    if (packCount != null && packCount! > 1) {
      return '${packCount}x$sizeStr$sizeUnit';
    }
    return '$sizeStr$sizeUnit';
  }

  @override
  String toString() =>
      'Parsed(brand: $brand, size: $formattedSize, variants: $variants, normalized: "$normalizedName")';
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
  final double confidenceScore;
  final bool aiVerified;
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
    this.confidenceScore = 0.0,
    this.aiVerified = false,
    this.priceDifference,
    required this.parsed,
  });

  /// Create a copy with updated fields (used by AI enhancement).
  ComparisonMatch copyWith({
    MatchType? matchType,
    double? confidenceScore,
    bool? aiVerified,
  }) {
    return ComparisonMatch(
      retailer: retailer,
      name: name,
      price: price,
      priceNumeric: priceNumeric,
      promotionPrice: promotionPrice,
      hasPromo: hasPromo,
      imageUrl: imageUrl,
      matchType: matchType ?? this.matchType,
      similarityScore: similarityScore,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      aiVerified: aiVerified ?? this.aiVerified,
      priceDifference: priceDifference,
      parsed: parsed,
    );
  }

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

  /// Known SA grocery brand patterns — sorted by length descending so
  /// multi-word brands match before their prefixes.
  static final List<String> _brandPatterns = () {
    const patterns = [
      // Dairy & Beverages
      'clover', 'parmalat', 'woodlands', 'fairfield', 'darling', 'lancewood',
      'danone', 'nutriday', 'ultra mel', 'super m', 'steri stumpie',
      'fair cape',
      // Hot drinks
      'nescafe', 'nescafé', 'ricoffy', 'frisco', 'jacobs', 'douwe egberts',
      'lipton', 'five roses', 'joko', 'glen', 'freshpak', 'laager',
      // Cereals
      "kellogg's", 'kelloggs', 'bokomo', 'weet-bix', 'weetbix', 'pronutro',
      'jungle', 'morvite',
      // Baking & spreads
      'rama', 'stork', 'flora', 'lurpak', 'black cat', 'yum yum',
      // Grains & staples
      'albany', 'sasko', 'blue ribbon', 'tastic', 'spekko', 'ace',
      'iwisa', 'white star', "fatti's & moni's", 'fattis & monis',
      // Canned
      'all gold', 'koo', 'rhodes', 'bull brand', 'lucky star', 'john west',
      // Snacks
      'simba', 'lays', "lay's", 'doritos', 'nik naks', 'niknaks',
      'willards', 'bakers', 'tennis', 'romany creams', 'oreo',
      // Confectionery
      'cadbury', 'beacon', 'lindt', 'ferrero', 'bar one', 'lunch bar',
      'kitkat', 'kit kat', 'aero', 'tex', 'jelly tots', 'astros', 'smarties',
      // Beverages
      'coca-cola', 'coca cola', 'pepsi', 'pepsi max', 'fanta', 'sprite',
      'schweppes', 'mountain dew',
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
      'mrs balls', "mrs ball's", "nando's", 'nandos', 'tabasco',
      "wellington's", 'crosse & blackwell', "hellmann's", 'hellmanns',
      // Cooking oils
      'sunfoil', 'excella',
      // Meat & fish
      'enterprise', 'eskort', 'county fair', 'rainbow', 'goldi',
      'i&j', 'sea harvest', "fry's", 'frys',
      // Store brands
      'pnp', 'pick n pay', 'checkers', 'shoprite', 'woolworths',
      'no name', 'housebrand', 'ritebrand', 'spar',
      // SPAR-specific brands
      'buttanutt', 'maggie scratcher', 'lancewood', 'alettes',
      "alette's", 'bakali',
      // Health
      'dettol', 'savlon', 'disprin', 'panado',
      // Cooking
      'royal', 'dr oetker', "moir's", 'moirs', 'ina paarman',
      'mccain',
    ];
    // Sort by length descending: "head & shoulders" before "head"
    final sorted = List<String>.from(patterns);
    sorted.sort((a, b) => b.length.compareTo(a.length));
    return sorted;
  }();

  /// Store brand patterns — used to detect store-own products.
  static const _storeBrands = {
    'pnp', 'pick n pay', 'checkers', 'shoprite', 'woolworths',
    'no name', 'housebrand', 'ritebrand', 'spar',
  };

  /// SPAR barcode suffix pattern (e.g. "SK6009518602649")
  static final _sparBarcodeRegex = RegExp(r'\s+SK\d{10,16}$', caseSensitive: false);

  /// Preprocess SPAR product names: strip barcode suffix, handle ALL CAPS.
  /// Called before standard parsing.
  static String _preprocessSpar(String name) {
    // Strip "SK" + barcode suffix (10-16 digits at end of name)
    var cleaned = name.replaceAll(_sparBarcodeRegex, '');

    // Detect trailing brand duplication:
    // e.g. "AERO MILK CHOCOLATE 85G NESTLE" → brand at end should not confuse parser
    // The Edge Function already converts to title case, but handle raw ALL CAPS too
    if (cleaned == cleaned.toUpperCase() && cleaned.length > 10) {
      // ALL CAPS input — no conversion here (Edge Function handles it),
      // but ensure size units stay consistent
      cleaned = cleaned.trim();
    }

    return cleaned.trim();
  }

  /// Generic/filler words that should not drive matching.
  /// These words appear across unrelated product categories and inflate
  /// name similarity when they're the only overlap.
  static const _stopWords = {
    // Generic filler
    'plastic', 'basic', 'original', 'new', 'classic', 'special',
    'premium', 'super', 'natural', 'real', 'pure', 'best',
    'good', 'great', 'value', 'home', 'family', 'mini',
    'long', 'short', 'thin', 'thick',
    'regular', 'standard', 'assorted', 'mixed', 'multi', 'each',
    'range', 'select', 'choice', 'style', 'type', 'brand',
    // Packaging words — appear across unrelated categories
    'bottle', 'can', 'tin', 'box', 'bag', 'sachet', 'pouch',
    'tub', 'jar', 'container', 'carton', 'slab', 'roll', 'tube',
    'loaf', 'pack', 'avg', 'approx',
    // Prepositions/connectors — shared across unrelated products
    'in', 'and', 'with', 'for', 'the', 'of', 'or', 'from',
    // Common descriptors shared across categories
    'flavoured', 'flavored', 'sauce', 'flavour', 'flavor',
  };

  /// Variant groups for product differentiation.
  /// Variants in the same group are mutually exclusive — a product with
  /// "low fat" is different from one with "full cream".
  static const _variantGroups = <String, List<String>>{
    'fat_type': [
      'full cream', 'low fat', 'fat free', 'skim', 'lite', '2% low fat',
      '1% low fat', 'semi skimmed',
    ],
    'flavor': [
      'vanilla', 'chocolate', 'strawberry', 'banana', 'caramel',
      'plain', 'unflavoured', 'unflavored', 'butterscotch', 'coffee',
      'chilli', 'tomato', 'bbq', 'cheese', 'honey', 'lemon', 'mint', 'mango',
    ],
    'sauce_type': [
      'in tomato sauce', 'in tomato', 'in chilli sauce', 'in chilli',
      'in brine', 'in oil', 'in water', 'in curry sauce', 'in curry',
      'in bbq sauce', 'in mushroom sauce',
    ],
    'drink_variant': [
      'original taste', 'zero sugar', 'no sugar', 'less sugar',
      'original', 'zero', 'light', 'diet',
    ],
    'dietary': [
      'free range', 'organic', 'gluten free', 'sugar free', 'lactose free',
      'vegan', 'kosher', 'halaal', 'halal',
    ],
    'grain': [
      'white', 'brown', 'wholegrain', 'whole wheat', 'multigrain',
      'seed loaf', 'rye',
    ],
    'bean_type': [
      'baked beans', 'butter beans', 'kidney beans', 'cannellini beans',
      'black beans', 'mixed beans', 'sugar beans', 'broad beans',
      'four bean', 'lentils', 'chickpeas',
    ],
    'protein_type': [
      'pilchards', 'sardines', 'tuna', 'salmon', 'hake',
      'corned meat', 'bully beef', 'meatballs', 'vienna',
      'chakalaka',
    ],
    'temperature': ['fresh', 'long life', 'uht'],
    'cut': ['lean', 'extra lean', 'prime', 'regular'],
  };

  /// Parse a product name into brand, size, pack count, variants, and
  /// normalized form.
  static ParsedProductName parse(String name) {
    // Preprocess SPAR names: strip barcode suffix before standard parsing
    final preprocessed = _preprocessSpar(name);
    final lower = preprocessed.toLowerCase().trim();

    // -- Extract brand (longest match first) --
    String? brand;
    for (final pattern in _brandPatterns) {
      if (lower.startsWith('$pattern ') || lower.startsWith("$pattern'")) {
        brand = pattern;
        break;
      }
    }
    // Fallback: first word
    brand ??= lower.split(' ').first.replaceAll("'", '');

    // -- Extract variants --
    final variants = <String>{};
    final variantGroups = <String, String>{};
    for (final entry in _variantGroups.entries) {
      for (final variant in entry.value) {
        if (lower.contains(variant)) {
          variants.add(variant);
          variantGroups[entry.key] = variant;
          break; // One match per group
        }
      }
    }

    // -- Extract pack count --
    int? packCount;

    // "dozen" = 12
    if (RegExp(r'\bdozen\b', caseSensitive: false).hasMatch(lower)) {
      packCount = 12;
    }
    // "6 pack", "6pk", "6s", "6 units", "6ea"
    final packMatch = RegExp(
      r'(\d+)\s*(?:pack|pk|s|units?|ea)\b',
      caseSensitive: false,
    ).firstMatch(lower);
    if (packMatch != null && packCount == null) {
      packCount = int.tryParse(packMatch.group(1)!);
    }

    // -- Extract size --
    double? sizeValue;
    String? sizeUnit;

    // Multi-pack with size: "6 x 100g", "6x200ml"
    final multiMatch = RegExp(
      r'(\d+)\s*x\s*(\d+\.?\d*)\s*(g|kg|ml|l|litre|liter)s?\b',
      caseSensitive: false,
    ).firstMatch(lower);

    if (multiMatch != null) {
      packCount = int.tryParse(multiMatch.group(1)!) ?? packCount;
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

    // Calculate total size for multi-packs
    double? totalSize;
    if (packCount != null && sizeValue != null) {
      totalSize = packCount * sizeValue;
    }

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
    // Remove "dozen"
    normalized = normalized.replaceAll(
      RegExp(r'\bdozen\b', caseSensitive: false),
      '',
    );
    // Remove size patterns
    normalized = normalized.replaceAll(
      RegExp(r'\d+\.?\d*\s*(g|kg|ml|l|litre|liter)s?\b', caseSensitive: false),
      '',
    );
    // Remove count-only patterns like "6s", "12 units"
    normalized = normalized.replaceAll(
      RegExp(r'\b\d+\s*(s|units?)\b', caseSensitive: false),
      '',
    );
    // Remove "per kg" patterns
    normalized = normalized.replaceAll(
      RegExp(r'per\s*(kg|g|100g|100ml)\b', caseSensitive: false),
      '',
    );
    // Remove brand from normalized name (so Jaccard focuses on product words)
    normalized = normalized.replaceFirst(brand, '');
    // Remove variants from normalized name
    for (final variant in variants) {
      normalized = normalized.replaceAll(variant, '');
    }
    // Clean whitespace
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();

    return ParsedProductName(
      brand: brand,
      sizeValue: sizeValue,
      sizeUnit: sizeUnit,
      packCount: packCount,
      totalSize: totalSize,
      variants: variants,
      variantGroups: variantGroups,
      normalizedName: normalized,
      originalName: preprocessed,
    );
  }

  // ===========================================================================
  // CONFIDENCE SCORING
  // ===========================================================================

  /// Compute a confidence score (0.0–1.0) that two parsed products are the
  /// same item. Weighted: brand 30%, size 25%, variant 20%, name 25%.
  static double computeConfidence(
    ParsedProductName source,
    ParsedProductName candidate,
  ) {
    final brand = _brandScore(source, candidate);
    final size = _sizeScore(source, candidate);
    final variant = _variantScore(source, candidate);

    // When normalizedName is empty, the product's identity was fully consumed
    // by brand/size/variant parsing. Fall back to comparing original names
    // (minus size patterns) so products like "Strawberries 400g" vs
    // "PnP Strawberries 250g" can still score well on name overlap.
    final String sourceNameForScore;
    final String candidateNameForScore;
    if (source.normalizedName.isEmpty || candidate.normalizedName.isEmpty) {
      final sizeRe = RegExp(
        r'\d+\.?\d*\s*(g|kg|ml|l|litre|liter)s?\b|\d+\s*x\s*\d+',
        caseSensitive: false,
      );
      sourceNameForScore = source.originalName.toLowerCase()
          .replaceAll(sizeRe, '').replaceAll(RegExp(r'\s+'), ' ').trim();
      candidateNameForScore = candidate.originalName.toLowerCase()
          .replaceAll(sizeRe, '').replaceAll(RegExp(r'\s+'), ' ').trim();
    } else {
      sourceNameForScore = source.normalizedName;
      candidateNameForScore = candidate.normalizedName;
    }

    final name = _nameScore(sourceNameForScore, candidateNameForScore);

    // Guard: if names share no meaningful words and brand isn't an exact
    // match, these are fundamentally different products — don't let
    // variant/size alone create a match (e.g. beans vs pilchards)
    if (name < 0.10 && brand < 0.9) return 0.0;

    final score =
        (brand * 0.30) + (size * 0.25) + (variant * 0.20) + (name * 0.25);

    // Size gate: if sizes differ drastically (e.g. 6x1L vs 1L), cap confidence
    // below "similar" threshold. Relax for cross-retailer produce comparisons
    // where brands differ (e.g. "Strawberries 400g" vs "PnP Strawberries 250g").
    if (size <= 0.1) {
      // Soft gate when: brands are different AND at least one fallback brand
      // appears in the other product's name (indicating a produce/generic product
      // sold under different retailer labels at different sizes).
      final srcBrand = source.brand?.toLowerCase().replaceAll('-', '') ?? '';
      final candBrand = candidate.brand?.toLowerCase().replaceAll('-', '') ?? '';
      final brandsAreDifferent = srcBrand != candBrand;
      final fallbackInOtherName = (!_brandPatterns.contains(srcBrand) &&
              candidate.originalName.toLowerCase().contains(srcBrand)) ||
          (!_brandPatterns.contains(candBrand) &&
              source.originalName.toLowerCase().contains(candBrand));

      if (brandsAreDifferent && fallbackInOtherName && size > 0.05) {
        // Cross-retailer produce — soft gate, allow similar matches
        return score.clamp(0.0, 0.64);
      }
      return score.clamp(0.0, 0.54);
    }

    // Moderate size gate: when both products have comparable size info and
    // differ by >20% (sizeScore < 0.5), cap below "exact" threshold.
    // 650g vs 950g is a meaningful difference — "similar" not "same product".
    // Skip this gate when one product is missing size info entirely (e.g.
    // "6 Pack" vs "6 x 45g") — that's incomplete data, not a real mismatch.
    final bothHaveSize = source.sizeValue != null && candidate.sizeValue != null;
    if (bothHaveSize && size < 0.5 && size > 0.1) {
      return score.clamp(0.0, 0.79);
    }

    // Variant conflict penalty: conflicting variants (e.g. brown vs white,
    // full cream vs low fat) are a strong signal these are different products.
    // Cap score below exact threshold when variants conflict.
    if (variant == 0.0 &&
        source.variantGroups.isNotEmpty &&
        candidate.variantGroups.isNotEmpty) {
      return score.clamp(0.0, 0.79);
    }

    return score;
  }

  /// Brand similarity (0.0–1.0).
  static double _brandScore(ParsedProductName a, ParsedProductName b) {
    if (a.brand == null || b.brand == null) return 0.3;

    final brandA = a.brand!.toLowerCase().replaceAll('-', '');
    final brandB = b.brand!.toLowerCase().replaceAll('-', '');

    if (brandA == brandB) return 1.0;

    final aIsStore = _storeBrands.contains(brandA);
    final bIsStore = _storeBrands.contains(brandB);

    // Both store brands — similar tier products
    if (aIsStore && bIsStore) return 0.7;

    final aKnown = _brandPatterns.contains(brandA);
    final bKnown = _brandPatterns.contains(brandB);

    // When one brand is a fallback (first word, not a known brand) and
    // it appears in the other product's original name, the "brand" is
    // actually the product name (e.g. "strawberries" from "Strawberries 400g"
    // appearing in "PnP Strawberries 250g"). Treat as compatible.
    if (!aKnown && b.originalName.toLowerCase().contains(brandA)) return 0.7;
    if (!bKnown && a.originalName.toLowerCase().contains(brandB)) return 0.7;

    if (!aKnown || !bKnown) return 0.3;

    // Different known brands
    return 0.0;
  }

  /// Size similarity (0.0–1.0).
  static double _sizeScore(ParsedProductName a, ParsedProductName b) {
    // Count-only products (eggs, rolls) — compare pack counts directly
    if (a.sizeValue == null &&
        b.sizeValue == null &&
        a.packCount != null &&
        b.packCount != null) {
      if (a.packCount == b.packCount) return 1.0;
      final ratio = a.packCount! / b.packCount!;
      final diff = (ratio - 1.0).abs();
      if (diff < 0.20) return 0.5; // Close counts (e.g. 6 vs 5)
      return 0.1; // Very different counts (e.g. 30 vs 6)
    }

    // Neither has size or pack count — can't compare
    if (a.sizeValue == null && b.sizeValue == null) return 0.5;
    // One has size, other doesn't
    if (a.sizeValue == null || b.sizeValue == null) return 0.3;

    final unitA = a.sizeUnit;
    final unitB = b.sizeUnit;
    if (unitA == null || unitB == null) return 0.3;

    final normA = _normalizeToBaseUnit(a.totalSize ?? a.sizeValue!, unitA);
    final normB = _normalizeToBaseUnit(b.totalSize ?? b.sizeValue!, unitB);

    // Can't compare different unit families (weight vs volume)
    if (normA == null || normB == null) return 0.0;
    if (normA.unit != normB.unit) return 0.0;

    final ratio = normA.value / normB.value;
    final diff = (ratio - 1.0).abs();

    // Exact match (within 1% tolerance)
    if (diff < 0.01) {
      // Same total but different pack structure (6x200ml vs 1200ml)?
      if (a.packCount != null &&
          b.packCount != null &&
          a.packCount != b.packCount) {
        return 0.7;
      }
      return 1.0;
    }

    // Within 5% — very likely same product (e.g. 400g vs 410g)
    if (diff < 0.05) return 0.8;

    // Within 20% — somewhat close
    if (diff < 0.20) return 0.5;

    // Scale down harshly for large size differences
    if (diff > 2.0) return 0.05; // >3x apart (e.g. 850g vs 200g)
    if (diff >= 0.50) return 0.1; // >=1.5x apart (e.g. 500g vs 1kg)
    return 0.25; // Modest difference (e.g. 500g vs 400g)
  }

  /// Variant similarity (0.0–1.0).
  static double _variantScore(ParsedProductName a, ParsedProductName b) {
    // Neither has variants — fully compatible
    if (a.variantGroups.isEmpty && b.variantGroups.isEmpty) return 1.0;

    final allGroups = {...a.variantGroups.keys, ...b.variantGroups.keys};
    if (allGroups.isEmpty) return 1.0;

    int conflicting = 0;
    int missingOneSide = 0;

    for (final group in allGroups) {
      final varA = a.variantGroups[group];
      final varB = b.variantGroups[group];

      if (varA == null || varB == null) {
        missingOneSide++;
      } else if (varA != varB) {
        conflicting++;
      }
    }

    // Any conflicting variant = strong signal these are different products
    if (conflicting > 0) return 0.0;

    // All matching
    if (missingOneSide == 0) return 1.0;

    // Some groups missing on one side — partial compatibility
    return 0.5;
  }

  // Words that signal a fundamentally different product category.
  // When the source product doesn't contain these words but the candidate does,
  // it's a category mismatch (e.g. "Strawberries" vs "Strawberry Drink").
  static const _categoryMismatchWords = {
    // Drinks
    'drink', 'juice', 'cooldrink', 'cordial', 'squash', 'soda', 'shake',
    'smoothie', 'water', 'tea', 'coffee',
    // Dairy / desserts (mismatch against fresh produce)
    'yoghurt', 'yogurt', 'custard', 'mousse', 'pudding',
    'gelato', 'sorbet',
    // Confectionery / snacks
    'chocolate', 'candy', 'sweet', 'gummy', 'mallow', 'marshmallow',
    'lollipop', 'toffee', 'fudge', 'cookie', 'biscuit', 'wafer',
    // Baked goods
    'cake', 'bread', 'muffin', 'scone', 'rusk', 'pie', 'tart',
    // Cleaning / non-food
    'detergent', 'cleaner', 'soap', 'shampoo', 'bleach', 'sanitizer',
    'nappy', 'diaper', 'wipe',
    // Meal replacements / supplements
    'replace', 'replacement', 'supplement', 'vitamin', 'protein', 'formula',
    'medicine', 'tablet', 'capsule', 'syrup',
    // Sauces / condiments
    'sauce', 'chutney', 'relish', 'marinade', 'dressing', 'ketchup',
    'paste', 'pesto', 'gravy', 'soup',
    // Jams / preserves
    'jam', 'jelly', 'preserve', 'marmalade', 'compote', 'conserve',
    // Processed
    'flavoured', 'flavored', 'instant', 'powder', 'concentrate',
  };

  /// Name similarity (0.0–1.0) using Jaccard + containment.
  /// Filters out generic stop words so they don't inflate scores.
  static double _nameScore(String a, String b) {
    final wordsA = a.split(RegExp(r'\s+')).where((w) => w.length > 1).toSet();
    final wordsB = b.split(RegExp(r'\s+')).where((w) => w.length > 1).toSet();

    // If either normalized name is empty (brand+size+variant consumed it all),
    // return neutral — let brand/size/variant scores carry the signal
    if (wordsA.isEmpty || wordsB.isEmpty) return 0.5;

    // Filter out stop words to get meaningful product words
    final meaningfulA = wordsA.difference(_stopWords);
    final meaningfulB = wordsB.difference(_stopWords);

    // If no meaningful words remain, fall back to full words with penalty
    if (meaningfulA.isEmpty || meaningfulB.isEmpty) {
      final overlap = wordsA.intersection(wordsB).length;
      if (overlap == 0) return 0;
      return (overlap / wordsA.union(wordsB).length) * 0.3;
    }

    // Category mismatch guard: if candidate has category-indicator words
    // that the source doesn't have, these are fundamentally different products.
    // "Strawberries" vs "Strawberry Drink" → "drink" not in source → reject.
    final candidateCategory = meaningfulB.intersection(_categoryMismatchWords);
    final sourceCategory = meaningfulA.intersection(_categoryMismatchWords);
    final mismatch = candidateCategory.difference(sourceCategory);
    if (mismatch.isNotEmpty) return 0;

    final overlap = meaningfulA.intersection(meaningfulB).length;
    if (overlap == 0) return 0;

    final jaccard = overlap / meaningfulA.union(meaningfulB).length;
    final containment = overlap / meaningfulA.length;

    // Penalize single-word overlap when both sides have many words
    if (overlap == 1 && meaningfulA.length > 2 && meaningfulB.length > 2) {
      return (jaccard * 0.4 + containment * 0.6) * 0.5;
    }

    return (jaccard * 0.4) + (containment * 0.6);
  }

  /// Multi-word phrases that indicate a different product category.
  /// Checked as substrings on the full original name (lowercased).
  /// "cream" alone is too common (Full Cream Milk), but "double cream"
  /// unambiguously signals a dairy dessert, not fresh produce.
  static const _categoryMismatchPhrases = [
    'double cream', 'ice cream', 'cream cheese', 'sour cream',
    'whipped cream', 'clotted cream',
  ];

  /// Check if two product names have a category mismatch based on original names.
  /// Uses the full original name (before brand/variant stripping) so that
  /// words like "drink", "replace", "sauce" are caught even when they'd be
  /// stripped from normalizedName.
  static bool _hasCategoryMismatch(String sourceOriginal, String candidateOriginal) {
    final sourceLower = sourceOriginal.toLowerCase();
    final candidateLower = candidateOriginal.toLowerCase();

    // Check multi-word phrases first
    for (final phrase in _categoryMismatchPhrases) {
      if (candidateLower.contains(phrase) && !sourceLower.contains(phrase)) {
        return true;
      }
    }

    // Single-word check
    final sizePattern = RegExp(r'^\d+\.?\d*(g|kg|ml|l|pack|pk)$');
    final sourceWords = sourceLower
        .split(RegExp(r'[\s\-]+'))
        .where((w) => w.length > 1 && !sizePattern.hasMatch(w))
        .toSet();
    final candidateWords = candidateLower
        .split(RegExp(r'[\s\-]+'))
        .where((w) => w.length > 1 && !sizePattern.hasMatch(w))
        .toSet();

    final candidateCategory = candidateWords.intersection(_categoryMismatchWords);
    final sourceCategory = sourceWords.intersection(_categoryMismatchWords);
    final mismatch = candidateCategory.difference(sourceCategory);
    return mismatch.isNotEmpty;
  }

  /// Map confidence score to MatchType for backward compatibility.
  static MatchType? matchTypeFromConfidence(double confidence) {
    if (confidence >= 0.80) return MatchType.exact;
    if (confidence >= 0.55) return MatchType.similar;
    if (confidence >= 0.30) return MatchType.fallback;
    return null; // Below threshold — reject
  }

  // ===========================================================================
  // CLASSIFY (updated to use confidence scoring)
  // ===========================================================================

  /// Classify a candidate product against a source product.
  ///
  /// Returns null if confidence is below threshold (0.30).
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
    // Category mismatch guard on ORIGINAL names (before variant/brand stripping).
    // Catches cases like "Strawberries 400g" vs "Replace Strawberry Drink 400g"
    // where normalizedName stripping hides the mismatch.
    if (_hasCategoryMismatch(source.originalName, candidate.originalName)) {
      return null;
    }

    final confidence = computeConfidence(source, candidate);
    final matchType = matchTypeFromConfidence(confidence);

    if (matchType == null) return null;

    // Legacy similarity for backward compat
    final similarity = _wordSimilarity(
      source.normalizedName,
      candidate.normalizedName,
    );

    // Additional rejection: very low word overlap even if confidence is OK.
    // Skip this check when either normalizedName is empty — that means the
    // product name was entirely consumed by brand/size/variant parsing
    // (e.g. "Strawberries 400g" → brand="strawberries", size=400g, normalized="").
    // In that case, similarity=0 is misleading, not a genuine mismatch.
    final bothNamesPresent = source.normalizedName.isNotEmpty &&
        candidate.normalizedName.isNotEmpty;
    if (bothNamesPresent &&
        similarity < similarityThreshold &&
        confidence < 0.55) {
      return null;
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
      confidenceScore: confidence,
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
