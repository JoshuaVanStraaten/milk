import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/retailers.dart';
import '../../data/models/list_comparison.dart';
import '../../data/models/list_item.dart';
import '../../data/services/fuel_cost_service.dart';
import '../../data/services/fuel_price_service.dart';
import '../../data/services/ingredient_lookup.dart';
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
    final smartMatcher = _ref.read(smartMatchingServiceProvider);

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

          // Use normalizedName (brand-stripped) for cross-retailer search so
          // "Snowflake Cake Flour 2.5kg" searches as "cake flour" — giving
          // each retailer's API a fair chance to return its own brands.
          // Fall back to searchQuery if normalizedName is empty.
          final query = parsed.normalizedName.isNotEmpty
              ? parsed.normalizedName
              : parsed.searchQuery;

          // Extract recipe quantity from item note ("Need: 250g") if available,
          // so size-aware matching uses the recipe amount, not the product size.
          double? ingredientQty = parsed.sizeValue;
          String? ingredientUnit = parsed.sizeUnit;
          if (item.itemNote != null) {
            final needMatch = RegExp(
              r'Need:\s*(\d+\.?\d*)\s*(g|kg|ml|l|units?|pieces?)',
              caseSensitive: false,
            ).firstMatch(item.itemNote!);
            if (needMatch != null) {
              ingredientQty = double.tryParse(needMatch.group(1)!);
              ingredientUnit = needMatch.group(2);
            }
          }

          // Resolve ingredient lookup hint for better filtering
          final hint = IngredientLookup.resolve(query);
          final apiQuery = hint?.searchQuery ?? query;

          final response = await api
              .searchProducts(
                query: apiQuery,
                store: store,
                retailer: retailerName,
                pageSize: 15,
              )
              .timeout(const Duration(seconds: 12));

          final best = await smartMatcher.matchIngredient(
            ingredientName: query,
            candidates: response.products,
            ingredientQuantity: ingredientQty,
            ingredientUnit: ingredientUnit,
            hint: hint,
          );

          if (best != null) {
            final promoPrice = double.tryParse(best.promotionPrice);
            final priceNum = (promoPrice != null && promoPrice > 0)
                ? promoPrice
                : best.priceNumeric;
            final bestParsed = ProductNameParser.parse(best.name);
            final confidence =
                ProductNameParser.computeConfidence(parsed, bestParsed);

            // Reject matches where sizes differ drastically.
            // E.g. "Milk 500ml" matching "Milk 6x1L" or "Flour 2.5kg"
            // matching "Flour 12.5kg" are not useful for price comparison.
            // computeConfidence already gates on size (caps at 0.54 when
            // sizeScore <= 0.1), but sizes that differ 2-3x can still slip
            // through. Use a stricter check for list comparison.
            bool sizeAcceptable = true;
            if (parsed.sizeValue != null && bestParsed.sizeValue != null &&
                parsed.sizeUnit != null && bestParsed.sizeUnit != null) {
              final srcTotal = parsed.totalSize ?? parsed.sizeValue!;
              final matchTotal = bestParsed.totalSize ?? bestParsed.sizeValue!;
              // Only compare when units are compatible (both weight or both volume)
              final srcU = parsed.sizeUnit!.toLowerCase();
              final matchU = bestParsed.sizeUnit!.toLowerCase();
              final bothWeight = {'g', 'kg'}.contains(srcU) && {'g', 'kg'}.contains(matchU);
              final bothVolume = {'ml', 'l'}.contains(srcU) && {'ml', 'l'}.contains(matchU);
              if (bothWeight || bothVolume) {
                final srcNorm = (srcU == 'kg' || srcU == 'l') ? srcTotal * 1000 : srcTotal;
                final matchNorm = (matchU == 'kg' || matchU == 'l') ? matchTotal * 1000 : matchTotal;
                if (srcNorm > 0) {
                  final ratio = matchNorm / srcNorm;
                  if (ratio > 3.0 || ratio < 0.33) {
                    sizeAcceptable = false;
                  }
                }
              }
            }

            // Only accept exact (>=0.80) or similar (>=0.55) matches
            // with acceptable size ratio.
            if (confidence >= 0.55 && sizeAcceptable) {
              results[item.itemId] = ListItemMatch(
                itemId: item.itemId,
                itemName: item.itemName,
                quantity: item.itemQuantity,
                matchedProductName: best.name,
                matchedPrice: priceNum,
                matchedImageUrl: best.imageUrl,
                matchedRetailer: retailerName,
                confidenceScore: confidence,
                matchType: confidence >= 0.80
                    ? MatchType.exact
                    : MatchType.similar,
              );
            } else {
              results[item.itemId] = ListItemMatch(
                itemId: item.itemId,
                itemName: item.itemName,
                quantity: item.itemQuantity,
              );
            }
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
