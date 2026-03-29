import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/retailers.dart';
import '../../data/models/list_comparison.dart';
import '../../data/models/list_item.dart';
import '../../data/services/fuel_cost_service.dart';
import '../../data/services/fuel_price_service.dart';
import '../../data/services/product_name_parser.dart';
import 'fuel_price_provider.dart';
import 'store_provider.dart';
import 'vehicle_config_provider.dart';
import 'list_provider.dart';

class ListComparisonNotifier extends StateNotifier<ListComparisonState> {
  final Ref _ref;

  ListComparisonNotifier(this._ref) : super(const ListComparisonState());

  /// Compare all list items across the 4 grocery retailers in parallel.
  Future<void> runComparison({
    required List<ListItem> items,
  }) async {
    if (items.isEmpty) return;

    final storeSelection = _ref.read(storeSelectionProvider).value;
    if (storeSelection == null) {
      state = state.copyWith(error: 'No stores available');
      return;
    }

    final groceryNames =
        Retailers.all.keys.where(Retailers.isGrocery).toList();

    // Initialize all baskets as loading
    final initialBaskets = Map.fromEntries(
      groceryNames.map(
        (name) => MapEntry(
          name,
          ListRetailerBasket(retailerName: name, isLoading: true),
        ),
      ),
    );
    state = ListComparisonState(
      isLoading: true,
      baskets: initialBaskets,
      completedRetailers: 0,
    );

    final api = _ref.read(liveApiServiceProvider);

    // Fuel cost setup (optional — null if vehicle not configured)
    final vehicle = _ref.read(vehicleConfigProvider);
    FuelPriceData? fuelData;
    try {
      fuelData = await _ref.read(fuelPricesProvider.future);
    } catch (_) {
      // Fuel prices unavailable — proceed without fuel cost
    }

    Future<void> fetchRetailer(String retailerName) async {
      final store = storeSelection.stores[retailerName];
      if (store == null) {
        final basket = ListRetailerBasket(
          retailerName: retailerName,
          matches: {
            for (final item in items)
              item.itemId: ListItemMatch(
                itemId: item.itemId,
                itemName: item.itemName,
                quantity: item.itemQuantity,
              ),
          },
          error: 'Not available nearby',
        );
        _updateBasket(retailerName, basket);
        return;
      }

      // Search items sequentially within each retailer to avoid API flood
      final results = <String, ListItemMatch>{};
      for (final item in items) {
        // If this item already has a price from the same retailer (e.g. from
        // recipe matching), reuse it directly instead of re-searching.
        if (item.itemRetailer == retailerName && item.effectivePrice > 0) {
          results[item.itemId] = ListItemMatch(
            itemId: item.itemId,
            itemName: item.itemName,
            quantity: item.itemQuantity,
            matchedProductName: item.itemName,
            matchedPrice: item.effectivePrice,
            matchedRetailer: retailerName,
            confidenceScore: 1.0,
            matchType: MatchType.exact,
          );
          continue;
        }

        try {
          final parsed = ProductNameParser.parse(item.itemName);

          // Use searchQuery (keeps brand + size) for the API search so we
          // find the same product at other retailers — apples-to-apples.
          // This matches the normal price comparison (compare_sheet.dart).
          final query = parsed.searchQuery;

          final response = await api
              .searchProducts(
                query: query,
                store: store,
                retailer: retailerName,
                pageSize: 10,
              )
              .timeout(const Duration(seconds: 12));

          // Use the same classify() logic as the normal price comparison.
          // This ensures strict product-to-product matching: if no exact
          // match is found, the item is left as unmatched.
          final sourceParsed = parsed;
          ComparisonMatch? bestMatch;

          for (final candidate in response.products) {
            final candidateParsed = ProductNameParser.parse(candidate.name);
            final match = ProductNameParser.classify(
              source: sourceParsed,
              candidate: candidateParsed,
              retailer: retailerName,
              name: candidate.name,
              price: candidate.price,
              priceNumeric: candidate.effectivePrice,
              promotionPrice:
                  candidate.hasPromo ? candidate.promotionPrice : null,
              hasPromo: candidate.hasPromo,
              imageUrl: candidate.imageUrl,
              sourcePrice: item.effectivePrice,
            );
            if (match != null &&
                (bestMatch == null ||
                    match.confidenceScore > bestMatch.confidenceScore)) {
              bestMatch = match;
            }
          }

          if (bestMatch != null &&
              bestMatch.matchType != MatchType.fallback) {
            final priceNum = bestMatch.priceNumeric;
            results[item.itemId] = ListItemMatch(
              itemId: item.itemId,
              itemName: item.itemName,
              quantity: item.itemQuantity,
              matchedProductName: bestMatch.name,
              matchedPrice: priceNum,
              matchedImageUrl: bestMatch.imageUrl,
              matchedRetailer: retailerName,
              confidenceScore: bestMatch.confidenceScore,
              matchType: bestMatch.matchType,
            );
          } else {
            results[item.itemId] = ListItemMatch(
              itemId: item.itemId,
              itemName: item.itemName,
              quantity: item.itemQuantity,
            );
          }
        } catch (e) {
          debugPrint('List compare: $retailerName/${item.itemName} failed: $e');
          results[item.itemId] = ListItemMatch(
            itemId: item.itemId,
            itemName: item.itemName,
            quantity: item.itemQuantity,
          );
        }
      }

      // Calculate fuel cost if vehicle configured
      double? fuelCost;
      if (vehicle != null && fuelData != null) {
        final price = fuelData.getPrice(vehicle.fuelType, vehicle.region);
        if (price != null) {
          final breakdown = FuelCostService().calculateTripCost(
            distanceKm: store.distanceKm,
            consumptionPer100km: vehicle.consumptionPer100km,
            fuelPricePerLitre: price,
          );
          fuelCost = breakdown.fuelCostRands;
        }
      }

      final basket = ListRetailerBasket(
        retailerName: retailerName,
        matches: results,
        fuelCost: fuelCost,
        distanceKm: store.distanceKm,
      );
      _updateBasket(retailerName, basket);
    }

    await Future.wait(groceryNames.map(fetchRetailer));

    // Post-processing: mark cheapest per item
    _markCheapestPerItem();

    // Auto-select cheapest retailer
    final cheapest = state.cheapestWithFuelRetailer ?? state.cheapestRetailer;
    state = state.copyWith(
      isLoading: false,
      selectedRetailer: cheapest,
    );
  }

  void _updateBasket(String retailerName, ListRetailerBasket basket) {
    state = state.copyWith(
      baskets: {...state.baskets, retailerName: basket},
      completedRetailers: state.completedRetailers + 1,
    );
  }

  /// Cross-reference all baskets to mark the cheapest price per item.
  void _markCheapestPerItem() {
    final baskets = state.baskets;
    if (baskets.isEmpty) return;

    // Collect all item IDs
    final itemIds = <String>{};
    for (final basket in baskets.values) {
      itemIds.addAll(basket.matches.keys);
    }

    // For each item, find the cheapest price across retailers
    final updatedBaskets = Map<String, ListRetailerBasket>.from(baskets);

    for (final itemId in itemIds) {
      double? cheapestPrice;
      String? cheapestRetailer;

      for (final entry in baskets.entries) {
        final match = entry.value.matches[itemId];
        if (match != null && match.isMatched) {
          if (cheapestPrice == null || match.matchedPrice! < cheapestPrice) {
            cheapestPrice = match.matchedPrice!;
            cheapestRetailer = entry.key;
          }
        }
      }

      if (cheapestRetailer != null) {
        for (final retailerName in updatedBaskets.keys) {
          final basket = updatedBaskets[retailerName]!;
          final match = basket.matches[itemId];
          if (match != null && match.isMatched) {
            final updatedMatches =
                Map<String, ListItemMatch>.from(basket.matches);
            updatedMatches[itemId] = match.copyWith(
              isCheapestForItem: retailerName == cheapestRetailer,
            );
            updatedBaskets[retailerName] =
                basket.copyWith(matches: updatedMatches);
          }
        }
      }
    }

    state = state.copyWith(baskets: updatedBaskets);
  }

  /// Apply the selected retailer's matches to the shopping list.
  /// Updates each item's retailer, price, and special price in Supabase.
  Future<void> applyRetailer({
    required String retailerName,
    required String listId,
    required List<ListItem> originalItems,
  }) async {
    final basket = state.baskets[retailerName];
    if (basket == null) return;

    final notifier =
        _ref.read(realtimeListItemsProvider(listId).notifier);

    for (final item in originalItems) {
      final match = basket.matches[item.itemId];
      if (match != null && match.isMatched) {
        final updated = item.copyWith(
          itemRetailer: retailerName,
          itemPrice: match.matchedPrice,
          itemTotalPrice: match.totalPrice,
        );
        await notifier.updateItem(updated);
      }
    }
  }

  /// Replace one item's match in a retailer basket (product swap).
  void swapProduct({
    required String retailerName,
    required String itemId,
    required ListItemMatch newMatch,
  }) {
    final basket = state.baskets[retailerName];
    if (basket == null) return;
    final updatedMatches =
        Map<String, ListItemMatch>.from(basket.matches)
          ..[itemId] = newMatch;
    state = state.copyWith(
      baskets: {
        ...state.baskets,
        retailerName: basket.copyWith(matches: updatedMatches),
      },
    );
    _markCheapestPerItem();
  }

  void selectRetailer(String retailerName) {
    state = state.copyWith(selectedRetailer: retailerName);
  }

  void reset() => state = const ListComparisonState();
}

final listComparisonProvider = StateNotifierProvider.autoDispose<
    ListComparisonNotifier, ListComparisonState>((ref) {
  return ListComparisonNotifier(ref);
});
