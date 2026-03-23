// lib/data/services/smart_matching_service.dart
//
// Orchestration layer for hybrid algorithm + AI product matching.
// Uses ProductNameParser for fast client-side scoring, and escalates
// low-confidence matches to Gemini for AI verification.

import 'package:flutter/foundation.dart';

import '../models/live_product.dart';
import 'gemini_service.dart';
import 'ingredient_lookup.dart';
import 'product_name_parser.dart';

/// Result of smart matching across retailers.
class SmartMatchResult {
  final Map<String, ComparisonMatch?> bestMatchPerRetailer;
  final Map<String, List<ComparisonMatch>> allMatchesByRetailer;
  final bool usedAi;
  final Set<String> lowConfidenceRetailers;

  const SmartMatchResult({
    required this.bestMatchPerRetailer,
    required this.allMatchesByRetailer,
    this.usedAi = false,
    this.lowConfidenceRetailers = const {},
  });

  /// Whether any retailer has a match below the AI threshold.
  bool get hasLowConfidence => lowConfidenceRetailers.isNotEmpty;

  /// All best matches as a flat list (non-null only).
  List<ComparisonMatch> get bestMatches =>
      bestMatchPerRetailer.values.whereType<ComparisonMatch>().toList();

  /// Create updated result after AI enhancement.
  SmartMatchResult withAiEnhancement({
    required Map<String, ComparisonMatch?> updatedBestMatches,
    required Map<String, List<ComparisonMatch>> updatedAllMatches,
  }) {
    return SmartMatchResult(
      bestMatchPerRetailer: {
        ...bestMatchPerRetailer,
        ...updatedBestMatches,
      },
      allMatchesByRetailer: {
        ...allMatchesByRetailer,
        ...updatedAllMatches,
      },
      usedAi: true,
      lowConfidenceRetailers: const {},
    );
  }
}

/// Hybrid product matching service combining algorithm scoring with AI.
class SmartMatchingService {
  final GeminiService _gemini;

  /// Simple in-memory cache for AI match results.
  /// Key: "sourceName|candidateName", Value: confidence from Gemini.
  final Map<String, double> _aiCache = {};
  static const int _maxCacheSize = 100;

  SmartMatchingService({required GeminiService gemini}) : _gemini = gemini;

  // ===========================================================================
  // ALGORITHM-ONLY MATCHING (synchronous, instant)
  // ===========================================================================

  /// Score all candidates using the algorithm only. Returns immediately.
  SmartMatchResult findMatchesAlgorithm({
    required LiveProduct sourceProduct,
    required Map<String, List<LiveProduct>> candidatesByRetailer,
    double geminiThreshold = 0.6,
  }) {
    final sourceParsed = ProductNameParser.parse(sourceProduct.name);
    final bestPerRetailer = <String, ComparisonMatch?>{};
    final allByRetailer = <String, List<ComparisonMatch>>{};
    final lowConfidence = <String>{};

    for (final entry in candidatesByRetailer.entries) {
      final retailer = entry.key;
      final candidates = entry.value;

      if (candidates.isEmpty) {
        bestPerRetailer[retailer] = null;
        allByRetailer[retailer] = [];
        continue;
      }

      final matches = <ComparisonMatch>[];
      for (final candidate in candidates) {
        final candidateParsed = ProductNameParser.parse(candidate.name);
        final match = ProductNameParser.classify(
          source: sourceParsed,
          candidate: candidateParsed,
          retailer: retailer,
          name: candidate.name,
          price: candidate.price,
          priceNumeric: candidate.priceNumeric,
          promotionPrice:
              candidate.hasPromo ? candidate.promotionPrice : null,
          hasPromo: candidate.hasPromo,
          imageUrl: candidate.imageUrl,
          sourcePrice: sourceProduct.priceNumeric,
        );
        if (match != null) matches.add(match);
      }

      // Sort by confidence descending
      matches.sort((a, b) => b.confidenceScore.compareTo(a.confidenceScore));

      allByRetailer[retailer] = matches;
      bestPerRetailer[retailer] = matches.isNotEmpty ? matches.first : null;

      // Track low-confidence retailers for AI escalation
      if (matches.isNotEmpty &&
          matches.first.confidenceScore < geminiThreshold) {
        lowConfidence.add(retailer);
      } else if (matches.isEmpty) {
        lowConfidence.add(retailer);
      }
    }

    return SmartMatchResult(
      bestMatchPerRetailer: bestPerRetailer,
      allMatchesByRetailer: allByRetailer,
      lowConfidenceRetailers: lowConfidence,
    );
  }

  // ===========================================================================
  // AI ENHANCEMENT (async, 1-3 seconds)
  // ===========================================================================

  /// Enhance low-confidence matches from an algorithm result with Gemini AI.
  ///
  /// Only calls Gemini for retailers in [algorithmResult.lowConfidenceRetailers].
  /// Returns an updated SmartMatchResult with AI-verified matches.
  Future<SmartMatchResult> enhanceWithAi({
    required LiveProduct sourceProduct,
    required SmartMatchResult algorithmResult,
    required Map<String, List<LiveProduct>> candidatesByRetailer,
    double geminiThreshold = 0.6,
  }) async {
    if (!algorithmResult.hasLowConfidence) return algorithmResult;

    try {
      // Build candidates for Gemini — top 3 per low-confidence retailer
      final geminiCandidates =
          <String, List<({int index, String name, String price})>>{};
      final candidateMap = <String, Map<int, LiveProduct>>{};

      for (final retailer in algorithmResult.lowConfidenceRetailers) {
        final products = candidatesByRetailer[retailer] ?? [];
        if (products.isEmpty) continue;

        // Take top 3 candidates (or fewer)
        final top = products.take(3).toList();
        final indexed = <({int index, String name, String price})>[];
        final indexMap = <int, LiveProduct>{};

        for (var i = 0; i < top.length; i++) {
          // Check cache first
          final cacheKey = '${sourceProduct.name}|${top[i].name}';
          if (_aiCache.containsKey(cacheKey)) {
            continue; // Already have AI result for this pair
          }
          indexed.add((index: i + 1, name: top[i].name, price: top[i].price));
          indexMap[i + 1] = top[i];
        }

        if (indexed.isNotEmpty) {
          geminiCandidates[retailer] = indexed;
          candidateMap[retailer] = indexMap;
        }
      }

      if (geminiCandidates.isEmpty) return algorithmResult;

      // Single batched Gemini call
      final aiResults = await _gemini.evaluateProductMatches(
        sourceProductName: sourceProduct.name,
        sourceRetailer: sourceProduct.retailer,
        sourcePrice: sourceProduct.price,
        candidatesByRetailer: geminiCandidates,
      );

      // Apply AI results
      final updatedBest = <String, ComparisonMatch?>{};
      final updatedAll = <String, List<ComparisonMatch>>{};
      final sourceParsed = ProductNameParser.parse(sourceProduct.name);

      for (final aiResult in aiResults) {
        final retailer = aiResult.retailer;
        final product = candidateMap[retailer]?[aiResult.candidateIndex];
        if (product == null) continue;

        // Cache the result
        _cacheResult('${sourceProduct.name}|${product.name}',
            aiResult.confidence);

        // Re-classify with AI confidence
        final candidateParsed = ProductNameParser.parse(product.name);
        final matchType =
            ProductNameParser.matchTypeFromConfidence(aiResult.confidence);
        if (matchType == null) continue;

        final match = ComparisonMatch(
          retailer: retailer,
          name: product.name,
          price: product.price,
          priceNumeric: product.priceNumeric,
          promotionPrice:
              product.hasPromo ? product.promotionPrice : null,
          hasPromo: product.hasPromo,
          imageUrl: product.imageUrl,
          matchType: matchType,
          similarityScore: ProductNameParser.computeConfidence(
            sourceParsed,
            candidateParsed,
          ),
          confidenceScore: aiResult.confidence,
          aiVerified: true,
          priceDifference: _priceDiff(
            product.priceNumeric,
            sourceProduct.priceNumeric,
          ),
          parsed: candidateParsed,
        );

        // Keep best AI match per retailer
        final existing = updatedBest[retailer];
        if (existing == null ||
            match.confidenceScore > existing.confidenceScore) {
          updatedBest[retailer] = match;
        }

        // Add to all matches
        updatedAll.putIfAbsent(retailer, () => []).add(match);
      }

      // Sort updated all-matches by confidence
      for (final list in updatedAll.values) {
        list.sort((a, b) => b.confidenceScore.compareTo(a.confidenceScore));
      }

      return algorithmResult.withAiEnhancement(
        updatedBestMatches: updatedBest,
        updatedAllMatches: updatedAll,
      );
    } catch (e) {
      debugPrint('AI enhancement failed, using algorithm results: $e');
      return algorithmResult;
    }
  }

  // ===========================================================================
  // INGREDIENT MATCHING (for recipes)
  // ===========================================================================

  /// Match a recipe ingredient to the best product from candidates.
  ///
  /// Uses algorithm scoring with optional AI fallback for low confidence.
  /// If [hint] is provided, pre-filters candidates using required/exclude words
  /// before scoring, dramatically improving accuracy for generic ingredients.
  Future<LiveProduct?> matchIngredient({
    required String ingredientName,
    required List<LiveProduct> candidates,
    double geminiThreshold = 0.5,
    double? ingredientQuantity,
    String? ingredientUnit,
    IngredientSearchHint? hint,
  }) async {
    if (candidates.isEmpty) return null;

    // Pre-filter candidates using hint if available
    var filtered = candidates;
    if (hint != null) {
      filtered = _applyHintFilter(candidates, hint);
      // Graceful degradation: if filtering removed everything, use unfiltered
      if (filtered.isEmpty) filtered = candidates;
    }

    // Score candidates using the enhanced algorithm
    final sourceParsed = ProductNameParser.parse(ingredientName);
    final scored = <(LiveProduct, double)>[];

    for (final candidate in filtered) {
      final candidateParsed = ProductNameParser.parse(candidate.name);
      final confidence =
          ProductNameParser.computeConfidence(sourceParsed, candidateParsed);

      // For ingredients, also factor in containment (ingredient words in product).
      // When hint pre-filtering was applied, relax extra-word rejection since
      // the candidate already passed required/exclude word checks.
      final nameScore = _ingredientNameScore(
        ingredientName,
        candidate.name,
        hintApplied: hint != null,
      );
      // If ingredient name scoring disqualified this candidate, skip it entirely
      // (don't let computeConfidence rescue a disqualified product)
      if (nameScore == 0) {
        scored.add((candidate, 0.0));
        continue;
      }
      // For ingredient matching, nameScore is more important than algorithm
      // confidence (which expects brand/size/variant — ingredients often lack these).
      // Use max(blended, nameScore) so a strong name match isn't dragged down.
      final blended =
          ((confidence * 0.4) + (nameScore * 0.6)).clamp(0.0, 1.0);
      final score = blended > nameScore ? blended : nameScore;

      scored.add((candidate, score));
    }

    // Sort by score descending
    scored.sort((a, b) => b.$2.compareTo(a.$2));

    if (scored.isEmpty) return null;

    // Reject very low matches
    final viable = scored.where((e) => e.$2 >= 0.35).toList();
    if (viable.isEmpty) return null;

    // Size-aware preference: among viable candidates, prefer the smallest
    // product size that's >= the ingredient quantity needed.
    if (ingredientQuantity != null &&
        ingredientQuantity > 0 &&
        ingredientUnit != null) {
      final neededBase = _toBaseUnit(ingredientQuantity, ingredientUnit);
      if (neededBase != null) {
        // Pre-filter: remove candidates with unreasonable sizes.
        // Cap at 3x needed with a ceiling of 2500g/ml. When the target is
        // a matched product size (e.g. 750ml), this allows up to 2250ml.
        // When it's a small recipe qty (e.g. 50g), allows up to 150g.
        final maxSize = (neededBase * 3.0).clamp(0, 2500.0);
        final sizeFiltered = viable.where((entry) {
          final parsed = ProductNameParser.parse(entry.$1.name);
          final productBase = _productToBaseUnit(parsed);
          if (productBase == null) return true; // keep if size unknown
          return productBase <= maxSize;
        }).toList();
        final candidates = sizeFiltered.isNotEmpty ? sizeFiltered : viable;
        return _pickBestSize(candidates, neededBase);
      }
    }

    return viable.first.$1;
  }

  /// Pre-filter candidates using hint's required/exclude word lists.
  List<LiveProduct> _applyHintFilter(
    List<LiveProduct> candidates,
    IngredientSearchHint hint,
  ) {
    return candidates.where((product) {
      final lower = product.name.toLowerCase();

      // Exclude products containing any exclude word
      if (hint.excludeWords.isNotEmpty) {
        for (final word in hint.excludeWords) {
          if (lower.contains(word)) return false;
        }
      }

      // Require at least one required word (if specified)
      if (hint.requiredWords.isNotEmpty) {
        final hasRequired = hint.requiredWords.any(
          (word) => lower.contains(word),
        );
        if (!hasRequired) return false;
      }

      return true;
    }).toList();
  }

  /// Pick the best-sized product from viable candidates.
  /// Prefers the smallest product >= needed amount. Falls back to closest.
  LiveProduct _pickBestSize(
    List<(LiveProduct, double)> viable,
    double neededBase,
  ) {
    // Only consider top candidates (within 0.15 of best score)
    final topScore = viable.first.$2;
    final topCandidates =
        viable.where((e) => e.$2 >= topScore - 0.15).toList();

    (LiveProduct, double)? bestFit;
    double bestFitSize = double.infinity;

    for (final (product, _) in topCandidates) {
      final parsed = ProductNameParser.parse(product.name);
      final productBase = _productToBaseUnit(parsed);
      if (productBase == null) continue;

      // Prefer smallest product that's >= needed, capped at max reasonable size
      final maxSize = (neededBase * 3.0).clamp(0, 2500.0);
      if (productBase >= neededBase &&
          productBase < bestFitSize &&
          productBase <= maxSize) {
        bestFit = (product, productBase);
        bestFitSize = productBase;
      }
    }

    // If found a product >= needed, use it
    if (bestFit != null) return bestFit.$1;

    // Otherwise fall back to highest scoring candidate
    return topCandidates.first.$1;
  }

  /// Convert ingredient quantity + unit to a base unit (ml or g).
  double? _toBaseUnit(double quantity, String unit) {
    final u = unit.toLowerCase().trim();
    // Weight
    if (u == 'g' || u == 'grams' || u == 'gram') return quantity;
    if (u == 'kg' || u == 'kilograms') return quantity * 1000;
    // Volume
    if (u == 'ml' || u == 'millilitres') return quantity;
    if (u == 'l' || u == 'litres' || u == 'liters') return quantity * 1000;
    // Count-based (eggs, units) — return as-is for pack count matching
    if (u == 'units' || u == 'unit' || u == 'pieces' || u == 'piece') {
      return quantity;
    }
    return null;
  }

  /// Extract product size in base units from parsed name.
  double? _productToBaseUnit(ParsedProductName parsed) {
    if (parsed.totalSize != null && parsed.sizeUnit != null) {
      return _toBaseUnit(parsed.totalSize!, parsed.sizeUnit!);
    }
    if (parsed.sizeValue != null && parsed.sizeUnit != null) {
      return _toBaseUnit(parsed.sizeValue!, parsed.sizeUnit!);
    }
    // Pack count only (eggs)
    if (parsed.packCount != null) return parsed.packCount!.toDouble();
    return null;
  }

  // Words that disqualify a product when the ingredient is short (<=3 words).
  // E.g. "eggs" should NOT match "Eggs Galore Milk Chocolate Mallow Egg".
  // Only rejects if the word is NOT also in the ingredient itself.
  // Uses stemmed words, so "cake" also catches "cakes".
  static const _disqualifyingWords = {
    // Confectionery / snacks
    'chocolate', 'candy', 'sweet', 'gummy',
    'mallow', 'marshmallow', 'lollipop', 'toffee', 'fudge', 'caramel',
    'galore', 'lindt', 'cadbury', 'nestle', 'hazelnut', 'praline',
    'cookie', 'biscuit', 'wafer',
    // Baked goods
    'cake', 'bread', 'muffin', 'scone', 'rusk',
    'crouton', 'crumb', 'pie', 'tart',
    // Drinks
    'juice', 'drink', 'cooldrink', 'cordial', 'squash', 'soda',
    // Cleaning / non-food / personal care / beauty
    'dishwasher', 'detergent', 'cleaner', 'soap', 'shampoo', 'bleach',
    'laundry', 'fabric', 'softener', 'sanitizer', 'disinfectant',
    'bath', 'lotion', 'moistur', 'teeth', 'toothbrush', 'toothpaste',
    'deodorant', 'nappy', 'diaper', 'wipe',
    'parfum', 'perfume', 'cologne', 'cashmere', 'candle', 'fragrance',
    'cosmetic', 'lipstick', 'mascara', 'skincare',
    // Seafood (disqualifies when ingredient isn't seafood)
    'mussel', 'oyster', 'prawn', 'anchovy', 'sardine',
    // Condiments/sauces/processed (when matching fresh/basic ingredients)
    'chutney', 'relish', 'marinade', 'dressing', 'mustard', 'ketchup',
    'sauce', 'gravy', 'pesto', 'paste', 'stock', 'instant',
    'gripe', 'medicine', 'supplement',
    // Processed food indicators
    'flavoured', 'flavored', 'condensed', 'seasoning', 'soup',
    'noodle', 'curry',
    // Snacks
    'chip', 'crisp', 'popcorn', 'cracker', 'pretzel', 'nacho',
  };

  /// Simple plural stemming for ingredient word matching.
  /// "lemons" → "lemon", "berries" → "berry", "tomatoes" → "tomato".
  static String _stem(String word) {
    if (word.endsWith('ies') && word.length > 4) {
      return '${word.substring(0, word.length - 3)}y';
    }
    // Only strip 'es' after sibilants (sh, ch, x, z, s) where plural adds 'es'
    // e.g. "dishes"→"dish", "matches"→"match", "boxes"→"box", "tomatoes"→"tomato"
    // But NOT "cakes"→"cak" (should be "cake") or "flakes"→"flak"
    if (word.endsWith('shes') || word.endsWith('ches') ||
        word.endsWith('xes') || word.endsWith('zes') ||
        word.endsWith('sses')) {
      return word.substring(0, word.length - 2);
    }
    if (word.endsWith('oes') && word.length > 4) {
      return word.substring(0, word.length - 2);
    }
    if (word.endsWith('s') && !word.endsWith('ss') && word.length > 3) {
      return word.substring(0, word.length - 1);
    }
    return word;
  }

  // Qualifier words that describe variety/color/type but don't change the
  // fundamental food item. "Brown Onion" → "brown" is a qualifier, "onion" is
  // core. If only qualifiers are missing from the product, we still match.
  // Note: "fresh","dried","frozen","large","small","medium","ground" are already
  // stripped by _cleanIngredientForSearch before matching reaches here.
  static const _ingredientQualifiers = {
    // Colors
    'brown', 'white', 'red', 'green', 'yellow', 'black', 'purple', 'orange',
    // Heat / flavor intensity
    'sweet', 'hot', 'mild', 'spicy',
    // Packaging / state (product names often omit these)
    'tinned', 'canned',
    // Type / shape / style
    'flat', 'curly', 'round', 'plain', 'organic', 'mixed',
  };

  /// Ingredient-specific name scoring that emphasizes containment.
  /// "beef mince" should score high against "Lean Beef Mince 500g".
  /// Uses stemming so "lemon" matches "lemons".
  /// Penalizes products with many extra irrelevant words.
  double _ingredientNameScore(
    String ingredient,
    String productName, {
    bool hintApplied = false,
  }) {
    final sizePattern = RegExp(r'^\d+\.?\d*(g|kg|ml|l|pack|pk)$');
    // Normalize hyphens to spaces so "stir-fry" matches "stir fry"
    final normalizedIngredient = ingredient.toLowerCase().replaceAll('-', ' ');
    final normalizedProduct = productName.toLowerCase().replaceAll('-', ' ');
    final ingredientWords = normalizedIngredient
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 1 && !sizePattern.hasMatch(w))
        .map(_stem)
        .toSet();
    final productWords = normalizedProduct
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 1 && !sizePattern.hasMatch(w))
        .map(_stem)
        .toSet();

    if (ingredientWords.isEmpty || productWords.isEmpty) return 0;

    // Disqualify: if ingredient is short and product has words indicating
    // a completely different category (confectionery, cleaning, processed)
    if (ingredientWords.length <= 3) {
      final disqualified = productWords.intersection(_disqualifyingWords);
      final ingredientHas = ingredientWords.intersection(_disqualifyingWords);
      if (disqualified.difference(ingredientHas).isNotEmpty) {
        return 0;
      }
    }

    final overlap = ingredientWords.intersection(productWords).length;
    final jaccard = overlap / ingredientWords.union(productWords).length;
    final containment = overlap / ingredientWords.length;

    // Qualifier-aware containment: require all CORE words to be present.
    // Qualifier words (colors, variety descriptors) may be absent.
    // "Brown Onion" vs "Onions 1kg" → "brown" is qualifier, "onion" is core → OK
    // "Chilli Powder" vs "Chilli Per kg" → "powder" is core, missing → REJECT
    final missingWords = ingredientWords.difference(productWords);
    final missingCore = missingWords.difference(_ingredientQualifiers);
    final hasQualifierPenalty = missingWords.isNotEmpty && missingCore.isEmpty;

    // 2-word ingredients: all core words must be present (strict)
    if (ingredientWords.length == 2 && missingCore.isNotEmpty) {
      return 0;
    }
    // 3+ word ingredients: allow 1 missing core word (product names vary)
    // "Stir Fry Vegetables" matches "PnP Stir Fry Julienne" (missing "vegetable")
    if (ingredientWords.length >= 3 && missingCore.length > 1) {
      return 0;
    }

    // Extra words in product not in ingredient
    final extraWords = productWords.difference(ingredientWords).length;

    // For very short ingredients, reject if product has too many extra words.
    // Products always have brand + descriptors, so allow some extra words.
    // When hintApplied, the candidate already passed required/exclude word
    // checks, so we relax the threshold significantly.
    // 1-word: max 3 extra (or 6 with hint)
    // 2-word: max 4 extra (or 7 with hint)
    final extraWordLimit1 = hintApplied ? 6 : 3;
    final extraWordLimit2 = hintApplied ? 7 : 4;
    if (ingredientWords.length == 1 && extraWords > extraWordLimit1) {
      return 0;
    }
    if (ingredientWords.length == 2 && extraWords > extraWordLimit2) {
      return 0;
    }

    // Penalty for extra words
    final extraPenalty = extraWords > 0
        ? (1.0 - (extraWords * 0.1)).clamp(0.3, 1.0)
        : 1.0;

    // Small penalty if qualifier words were missing (prefer exact variety match)
    final qualifierPenalty = hasQualifierPenalty ? 0.85 : 1.0;

    return ((jaccard * 0.4) + (containment * 0.6)) * extraPenalty * qualifierPenalty;
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  double? _priceDiff(double candidatePrice, double sourcePrice) {
    final diff = candidatePrice - sourcePrice;
    return diff.abs() < 0.01 ? null : diff;
  }

  void _cacheResult(String key, double confidence) {
    if (_aiCache.length >= _maxCacheSize) {
      // Remove oldest entry (first key)
      _aiCache.remove(_aiCache.keys.first);
    }
    _aiCache[key] = confidence;
  }
}
