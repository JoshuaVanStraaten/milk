import 'package:milk/data/services/product_name_parser.dart';

/// A single list item's match result at a specific retailer.
class ListItemMatch {
  final String itemId;
  final String itemName;
  final double quantity;
  final String? matchedProductName;
  final double? matchedPrice;
  final String? matchedImageUrl;
  final String? matchedRetailer;
  final double confidenceScore;
  final MatchType matchType;
  bool isCheapestForItem;

  ListItemMatch({
    required this.itemId,
    required this.itemName,
    required this.quantity,
    this.matchedProductName,
    this.matchedPrice,
    this.matchedImageUrl,
    this.matchedRetailer,
    this.confidenceScore = 0.0,
    this.matchType = MatchType.fallback,
    this.isCheapestForItem = false,
  });

  /// Total price accounting for quantity.
  double get totalPrice => (matchedPrice ?? 0.0) * quantity;

  /// Whether a product was found at this retailer.
  bool get isMatched => matchedProductName != null && matchedPrice != null;

  ListItemMatch copyWith({
    String? itemId,
    String? itemName,
    double? quantity,
    String? matchedProductName,
    double? matchedPrice,
    String? matchedImageUrl,
    String? matchedRetailer,
    double? confidenceScore,
    MatchType? matchType,
    bool? isCheapestForItem,
  }) {
    return ListItemMatch(
      itemId: itemId ?? this.itemId,
      itemName: itemName ?? this.itemName,
      quantity: quantity ?? this.quantity,
      matchedProductName: matchedProductName ?? this.matchedProductName,
      matchedPrice: matchedPrice ?? this.matchedPrice,
      matchedImageUrl: matchedImageUrl ?? this.matchedImageUrl,
      matchedRetailer: matchedRetailer ?? this.matchedRetailer,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      matchType: matchType ?? this.matchType,
      isCheapestForItem: isCheapestForItem ?? this.isCheapestForItem,
    );
  }
}

/// A retailer's full basket for the user's shopping list.
class ListRetailerBasket {
  final String retailerName;
  final Map<String, ListItemMatch> matches;
  final bool isLoading;
  final String? error;
  final double? fuelCost;
  final double? distanceKm;

  const ListRetailerBasket({
    required this.retailerName,
    this.matches = const {},
    this.isLoading = false,
    this.error,
    this.fuelCost,
    this.distanceKm,
  });

  double get productTotal => matches.values
      .where((m) => m.isMatched)
      .fold(0.0, (sum, m) => sum + m.totalPrice);

  double get grandTotal => productTotal + (fuelCost ?? 0.0);

  int get matchedCount => matches.values.where((m) => m.isMatched).length;

  int get totalItems => matches.length;

  String get formattedProductTotal => 'R${productTotal.toStringAsFixed(2)}';

  String get formattedGrandTotal => 'R${grandTotal.toStringAsFixed(2)}';

  ListRetailerBasket copyWith({
    String? retailerName,
    Map<String, ListItemMatch>? matches,
    bool? isLoading,
    String? error,
    double? fuelCost,
    double? distanceKm,
  }) {
    return ListRetailerBasket(
      retailerName: retailerName ?? this.retailerName,
      matches: matches ?? this.matches,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      fuelCost: fuelCost ?? this.fuelCost,
      distanceKm: distanceKm ?? this.distanceKm,
    );
  }
}

/// Full comparison state across all retailers.
class ListComparisonState {
  final bool isLoading;
  final Map<String, ListRetailerBasket> baskets;
  final String? selectedRetailer;
  final String? error;
  final int completedRetailers;

  const ListComparisonState({
    this.isLoading = false,
    this.baskets = const {},
    this.selectedRetailer,
    this.error,
    this.completedRetailers = 0,
  });

  /// Item IDs that are matched at ALL loaded retailers (apples-to-apples).
  Set<String> get commonItemIds {
    final loaded = baskets.values.where(
      (b) => !b.isLoading && b.error == null,
    ).toList();
    if (loaded.isEmpty) return {};
    // Start with all item IDs from the first basket, intersect with others
    var common = loaded.first.matches.entries
        .where((e) => e.value.isMatched)
        .map((e) => e.key)
        .toSet();
    for (final basket in loaded.skip(1)) {
      final matched = basket.matches.entries
          .where((e) => e.value.isMatched)
          .map((e) => e.key)
          .toSet();
      common = common.intersection(matched);
    }
    return common;
  }

  /// Number of items found at ALL retailers (fair comparison basis).
  int get commonItemCount => commonItemIds.length;

  /// Total for a basket using only commonly-matched items.
  double _commonTotal(ListRetailerBasket basket) {
    final common = commonItemIds;
    return basket.matches.entries
        .where((e) => common.contains(e.key) && e.value.isMatched)
        .fold(0.0, (sum, e) => sum + e.value.totalPrice);
  }

  /// Cheapest retailer using only commonly-matched items (fair comparison).
  String? get cheapestRetailer {
    if (baskets.isEmpty) return null;
    final loaded = baskets.entries.where(
      (e) => !e.value.isLoading && e.value.error == null && e.value.matchedCount > 0,
    );
    if (loaded.isEmpty) return null;
    if (commonItemIds.isEmpty) return null;
    return loaded.reduce((a, b) =>
        _commonTotal(a.value) < _commonTotal(b.value) ? a : b).key;
  }

  /// Cheapest retailer including fuel cost (common items + fuel).
  String? get cheapestWithFuelRetailer {
    if (baskets.isEmpty) return null;
    final loaded = baskets.entries.where(
      (e) => !e.value.isLoading && e.value.error == null && e.value.matchedCount > 0,
    );
    if (loaded.isEmpty) return null;
    if (commonItemIds.isEmpty) return null;
    return loaded.reduce((a, b) {
      final aTotal = _commonTotal(a.value) + (a.value.fuelCost ?? 0);
      final bTotal = _commonTotal(b.value) + (b.value.fuelCost ?? 0);
      return aTotal < bTotal ? a : b;
    }).key;
  }

  /// Savings between cheapest and most expensive using common items + fuel.
  double get maxSavings {
    final loaded = baskets.values.where(
      (b) => !b.isLoading && b.error == null && b.matchedCount > 0,
    ).toList();
    if (loaded.length < 2 || commonItemIds.isEmpty) return 0.0;
    final totals = loaded
        .map((b) => _commonTotal(b) + (b.fuelCost ?? 0))
        .toList()
      ..sort();
    return totals.last - totals.first;
  }

  bool get hasData =>
      baskets.values.any((b) => !b.isLoading && b.matchedCount > 0);

  ListComparisonState copyWith({
    bool? isLoading,
    Map<String, ListRetailerBasket>? baskets,
    String? selectedRetailer,
    String? error,
    int? completedRetailers,
  }) {
    return ListComparisonState(
      isLoading: isLoading ?? this.isLoading,
      baskets: baskets ?? this.baskets,
      selectedRetailer: selectedRetailer ?? this.selectedRetailer,
      error: error ?? this.error,
      completedRetailers: completedRetailers ?? this.completedRetailers,
    );
  }
}

/// Translates Rand savings into relatable SA grocery items.
class SavingsTranslator {
  static const _items = [
    _RelatableItem('a loaf of bread', '\u{1F35E}', 16.0),
    _RelatableItem('a kg of sugar', '\u{1F36C}', 20.0),
    _RelatableItem('2L of milk', '\u{1F95B}', 27.0),
    _RelatableItem('a bottle of cooking oil', '\u{1FAD8}', 40.0),
    _RelatableItem('a bag of rice', '\u{1F35A}', 40.0),
    _RelatableItem('a tray of eggs', '\u{1F95A}', 65.0),
    _RelatableItem('1kg of chicken', '\u{1F357}', 75.0),
  ];

  /// Returns a human-friendly message about what the savings could buy.
  static String toRelatableMessage(double savings) {
    if (savings <= 0) return 'Prices are very close across stores!';
    if (savings < 10) return 'Every rand counts!';

    // Find the best combination of items that fit within the savings
    final selected = <_RelatableItem>[];
    var remaining = savings;

    for (final item in _items) {
      if (item.price <= remaining) {
        selected.add(item);
        remaining -= item.price;
        if (selected.length >= 2) break;
      }
    }

    if (selected.isEmpty) {
      return 'Every rand counts!';
    }

    final names = selected.map((i) => i.name).join(' and ');
    final emojis = selected.map((i) => i.emoji).join('');
    return "That's $names! $emojis";
  }
}

class _RelatableItem {
  final String name;
  final String emoji;
  final double price;

  const _RelatableItem(this.name, this.emoji, this.price);
}
