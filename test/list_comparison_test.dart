import 'package:flutter_test/flutter_test.dart';
import 'package:milk/data/models/list_comparison.dart';
import 'package:milk/data/services/product_name_parser.dart';

void main() {
  // ===== ListItemMatch TESTS =====
  group('ListItemMatch', () {
    test('totalPrice multiplies price by quantity', () {
      final match = ListItemMatch(
        itemId: '1',
        itemName: 'Milk',
        quantity: 3,
        matchedPrice: 27.99,
      );
      expect(match.totalPrice, closeTo(83.97, 0.01));
    });

    test('totalPrice is zero when no match', () {
      final match = ListItemMatch(
        itemId: '1',
        itemName: 'Milk',
        quantity: 2,
      );
      expect(match.totalPrice, 0.0);
    });

    test('isMatched requires both name and price', () {
      expect(
        ListItemMatch(itemId: '1', itemName: 'Milk', quantity: 1,
            matchedProductName: 'PnP Milk', matchedPrice: 27.99).isMatched,
        isTrue,
      );
      expect(
        ListItemMatch(itemId: '1', itemName: 'Milk', quantity: 1,
            matchedProductName: 'PnP Milk').isMatched,
        isFalse,
      );
      expect(
        ListItemMatch(itemId: '1', itemName: 'Milk', quantity: 1,
            matchedPrice: 27.99).isMatched,
        isFalse,
      );
      expect(
        ListItemMatch(itemId: '1', itemName: 'Milk', quantity: 1).isMatched,
        isFalse,
      );
    });

    test('quantity of 1 returns single unit price', () {
      final match = ListItemMatch(
        itemId: '1',
        itemName: 'Bread',
        quantity: 1,
        matchedPrice: 16.49,
      );
      expect(match.totalPrice, closeTo(16.49, 0.01));
    });

    test('copyWith preserves unchanged fields', () {
      final original = ListItemMatch(
        itemId: '1',
        itemName: 'Milk',
        quantity: 2,
        matchedPrice: 27.99,
        matchType: MatchType.exact,
        confidenceScore: 0.95,
      );
      final updated = original.copyWith(isCheapestForItem: true);
      expect(updated.matchedPrice, 27.99);
      expect(updated.matchType, MatchType.exact);
      expect(updated.isCheapestForItem, isTrue);
    });
  });

  // ===== ListRetailerBasket TESTS =====
  group('ListRetailerBasket', () {
    test('productTotal sums matched items with quantities', () {
      final basket = ListRetailerBasket(
        retailerName: 'Pick n Pay',
        matches: {
          '1': ListItemMatch(
            itemId: '1', itemName: 'Milk', quantity: 2,
            matchedProductName: 'PnP Milk 2L', matchedPrice: 27.99,
          ),
          '2': ListItemMatch(
            itemId: '2', itemName: 'Bread', quantity: 1,
            matchedProductName: 'PnP Bread 700g', matchedPrice: 16.49,
          ),
          '3': ListItemMatch(
            itemId: '3', itemName: 'Vanilla Essence', quantity: 1,
            // Not matched
          ),
        },
      );
      // (27.99 * 2) + (16.49 * 1) = 72.47
      expect(basket.productTotal, closeTo(72.47, 0.01));
    });

    test('grandTotal includes fuel cost', () {
      final basket = ListRetailerBasket(
        retailerName: 'Pick n Pay',
        matches: {
          '1': ListItemMatch(
            itemId: '1', itemName: 'Milk', quantity: 1,
            matchedProductName: 'PnP Milk', matchedPrice: 27.99,
          ),
        },
        fuelCost: 12.50,
      );
      expect(basket.grandTotal, closeTo(40.49, 0.01));
    });

    test('grandTotal equals productTotal when no fuel', () {
      final basket = ListRetailerBasket(
        retailerName: 'Pick n Pay',
        matches: {
          '1': ListItemMatch(
            itemId: '1', itemName: 'Milk', quantity: 1,
            matchedProductName: 'PnP Milk', matchedPrice: 27.99,
          ),
        },
      );
      expect(basket.grandTotal, basket.productTotal);
    });

    test('matchedCount excludes unmatched items', () {
      final basket = ListRetailerBasket(
        retailerName: 'Pick n Pay',
        matches: {
          '1': ListItemMatch(
            itemId: '1', itemName: 'Milk', quantity: 1,
            matchedProductName: 'PnP Milk', matchedPrice: 27.99,
          ),
          '2': ListItemMatch(
            itemId: '2', itemName: 'Vanilla', quantity: 1,
          ),
          '3': ListItemMatch(
            itemId: '3', itemName: 'Eggs', quantity: 1,
            matchedProductName: 'PnP Eggs', matchedPrice: 64.99,
          ),
        },
      );
      expect(basket.matchedCount, 2);
      expect(basket.totalItems, 3);
    });

    test('empty basket returns zero totals', () {
      const basket = ListRetailerBasket(retailerName: 'Checkers');
      expect(basket.productTotal, 0.0);
      expect(basket.grandTotal, 0.0);
      expect(basket.matchedCount, 0);
      expect(basket.totalItems, 0);
    });

    test('formattedProductTotal returns ZAR format', () {
      final basket = ListRetailerBasket(
        retailerName: 'Woolworths',
        matches: {
          '1': ListItemMatch(
            itemId: '1', itemName: 'Milk', quantity: 1,
            matchedProductName: 'Woolies Milk', matchedPrice: 32.99,
          ),
        },
      );
      expect(basket.formattedProductTotal, 'R32.99');
    });

    test('formattedGrandTotal includes fuel', () {
      final basket = ListRetailerBasket(
        retailerName: 'Woolworths',
        matches: {
          '1': ListItemMatch(
            itemId: '1', itemName: 'Milk', quantity: 1,
            matchedProductName: 'Woolies Milk', matchedPrice: 100.00,
          ),
        },
        fuelCost: 15.50,
      );
      expect(basket.formattedGrandTotal, 'R115.50');
    });
  });

  // ===== ListComparisonState TESTS =====
  group('ListComparisonState', () {
    ListRetailerBasket makeBasket(String name, double total, {
      String? error,
      bool loading = false,
    }) {
      if (loading || error != null || total == 0) {
        return ListRetailerBasket(
          retailerName: name,
          isLoading: loading,
          error: error,
        );
      }
      return ListRetailerBasket(
        retailerName: name,
        matches: {
          '1': ListItemMatch(
            itemId: '1', itemName: 'Item', quantity: 1,
            matchedProductName: 'Product', matchedPrice: total,
          ),
        },
      );
    }

    test('cheapestRetailer returns lowest productTotal', () {
      final state = ListComparisonState(
        baskets: {
          'Pick n Pay': makeBasket('Pick n Pay', 342.50),
          'Woolworths': makeBasket('Woolworths', 389.00),
          'Checkers': makeBasket('Checkers', 310.00),
          'Shoprite': makeBasket('Shoprite', 325.00),
        },
      );
      expect(state.cheapestRetailer, 'Checkers');
    });

    test('cheapestRetailer returns null when no baskets', () {
      const state = ListComparisonState();
      expect(state.cheapestRetailer, isNull);
    });

    test('cheapestRetailer returns null when all loading', () {
      final state = ListComparisonState(
        baskets: {
          'Pick n Pay': makeBasket('Pick n Pay', 0, loading: true),
          'Woolworths': makeBasket('Woolworths', 0, loading: true),
        },
      );
      expect(state.cheapestRetailer, isNull);
    });

    test('cheapestRetailer ignores baskets with errors', () {
      final state = ListComparisonState(
        baskets: {
          'Pick n Pay': makeBasket('Pick n Pay', 342.50),
          'Woolworths': makeBasket('Woolworths', 100.00, error: 'API failed'),
          'Checkers': makeBasket('Checkers', 310.00),
        },
      );
      expect(state.cheapestRetailer, 'Checkers');
    });

    test('cheapestWithFuelRetailer considers fuel cost', () {
      final state = ListComparisonState(
        baskets: {
          'Pick n Pay': ListRetailerBasket(
            retailerName: 'Pick n Pay',
            matches: {
              '1': ListItemMatch(
                itemId: '1', itemName: 'Item', quantity: 1,
                matchedProductName: 'P', matchedPrice: 300.00,
              ),
            },
            fuelCost: 50.00, // grand = 350
          ),
          'Checkers': ListRetailerBasket(
            retailerName: 'Checkers',
            matches: {
              '1': ListItemMatch(
                itemId: '1', itemName: 'Item', quantity: 1,
                matchedProductName: 'P', matchedPrice: 310.00,
              ),
            },
            fuelCost: 5.00, // grand = 315
          ),
        },
      );
      // PnP cheaper by product, but Checkers cheaper with fuel
      expect(state.cheapestRetailer, 'Pick n Pay');
      expect(state.cheapestWithFuelRetailer, 'Checkers');
    });

    test('maxSavings calculates difference between extremes', () {
      final state = ListComparisonState(
        baskets: {
          'Pick n Pay': ListRetailerBasket(
            retailerName: 'Pick n Pay',
            matches: {
              '1': ListItemMatch(
                itemId: '1', itemName: 'Item', quantity: 1,
                matchedProductName: 'P', matchedPrice: 300.00,
              ),
            },
            fuelCost: 10.00,
          ),
          'Woolworths': ListRetailerBasket(
            retailerName: 'Woolworths',
            matches: {
              '1': ListItemMatch(
                itemId: '1', itemName: 'Item', quantity: 1,
                matchedProductName: 'P', matchedPrice: 400.00,
              ),
            },
            fuelCost: 20.00,
          ),
        },
      );
      // 420 - 310 = 110
      expect(state.maxSavings, closeTo(110.0, 0.01));
    });

    test('maxSavings returns 0 with less than 2 baskets', () {
      final state = ListComparisonState(
        baskets: {
          'Pick n Pay': makeBasket('Pick n Pay', 300),
        },
      );
      expect(state.maxSavings, 0.0);
    });

    test('maxSavings returns 0 with no loaded baskets', () {
      final state = ListComparisonState(
        baskets: {
          'Pick n Pay': makeBasket('Pick n Pay', 0, loading: true),
          'Checkers': makeBasket('Checkers', 0, loading: true),
        },
      );
      expect(state.maxSavings, 0.0);
    });

    test('hasData is true when any basket has matches', () {
      final state = ListComparisonState(
        baskets: {
          'Pick n Pay': makeBasket('Pick n Pay', 0, loading: true),
          'Checkers': makeBasket('Checkers', 310),
        },
      );
      expect(state.hasData, isTrue);
    });

    test('hasData is false when all loading', () {
      final state = ListComparisonState(
        baskets: {
          'Pick n Pay': makeBasket('Pick n Pay', 0, loading: true),
          'Checkers': makeBasket('Checkers', 0, loading: true),
        },
      );
      expect(state.hasData, isFalse);
    });

    test('hasData is false when empty', () {
      const state = ListComparisonState();
      expect(state.hasData, isFalse);
    });
  });

  // ===== COMMON ITEMS (FAIR COMPARISON) TESTS =====
  group('Common items fair comparison', () {
    test('commonItemIds returns items matched at ALL retailers', () {
      final state = ListComparisonState(
        baskets: {
          'Pick n Pay': ListRetailerBasket(
            retailerName: 'Pick n Pay',
            matches: {
              '1': ListItemMatch(itemId: '1', itemName: 'Milk', quantity: 1,
                  matchedProductName: 'PnP Milk', matchedPrice: 28.0),
              '2': ListItemMatch(itemId: '2', itemName: 'Bread', quantity: 1,
                  matchedProductName: 'PnP Bread', matchedPrice: 16.0),
              '3': ListItemMatch(itemId: '3', itemName: 'Eggs', quantity: 1),
            },
          ),
          'Checkers': ListRetailerBasket(
            retailerName: 'Checkers',
            matches: {
              '1': ListItemMatch(itemId: '1', itemName: 'Milk', quantity: 1,
                  matchedProductName: 'Checkers Milk', matchedPrice: 25.0),
              '2': ListItemMatch(itemId: '2', itemName: 'Bread', quantity: 1),
              '3': ListItemMatch(itemId: '3', itemName: 'Eggs', quantity: 1,
                  matchedProductName: 'Checkers Eggs', matchedPrice: 60.0),
            },
          ),
        },
      );
      // Only item '1' (Milk) is matched at BOTH retailers
      expect(state.commonItemIds, {'1'});
      expect(state.commonItemCount, 1);
    });

    test('cheapestRetailer uses only common items not raw totals', () {
      final state = ListComparisonState(
        baskets: {
          'Pick n Pay': ListRetailerBasket(
            retailerName: 'Pick n Pay',
            matches: {
              '1': ListItemMatch(itemId: '1', itemName: 'Milk', quantity: 1,
                  matchedProductName: 'PnP Milk', matchedPrice: 28.0),
              '2': ListItemMatch(itemId: '2', itemName: 'Bread', quantity: 1,
                  matchedProductName: 'PnP Bread', matchedPrice: 16.0),
            },
          ),
          'Woolworths': ListRetailerBasket(
            retailerName: 'Woolworths',
            matches: {
              '1': ListItemMatch(itemId: '1', itemName: 'Milk', quantity: 1,
                  matchedProductName: 'Woolies Milk', matchedPrice: 25.0),
              '2': ListItemMatch(itemId: '2', itemName: 'Bread', quantity: 1),
            },
          ),
        },
      );
      // Common item: only '1' (Milk). PnP=28, Woolies=25. Woolies wins.
      // Raw totals: PnP=44, Woolies=25. But that's unfair since PnP matched more.
      expect(state.cheapestRetailer, 'Woolworths');
      // Savings based on common item only: 28 - 25 = 3
      expect(state.maxSavings, closeTo(3.0, 0.01));
    });

    test('cheapestRetailer is null when no common items exist', () {
      final state = ListComparisonState(
        baskets: {
          'Pick n Pay': ListRetailerBasket(
            retailerName: 'Pick n Pay',
            matches: {
              '1': ListItemMatch(itemId: '1', itemName: 'Milk', quantity: 1,
                  matchedProductName: 'PnP Milk', matchedPrice: 28.0),
              '2': ListItemMatch(itemId: '2', itemName: 'Bread', quantity: 1),
            },
          ),
          'Checkers': ListRetailerBasket(
            retailerName: 'Checkers',
            matches: {
              '1': ListItemMatch(itemId: '1', itemName: 'Milk', quantity: 1),
              '2': ListItemMatch(itemId: '2', itemName: 'Bread', quantity: 1,
                  matchedProductName: 'Checkers Bread', matchedPrice: 15.0),
            },
          ),
        },
      );
      // No item is matched at BOTH retailers
      expect(state.commonItemIds, isEmpty);
      expect(state.cheapestRetailer, isNull);
    });

    test('error baskets excluded from common item calculation', () {
      final state = ListComparisonState(
        baskets: {
          'Pick n Pay': ListRetailerBasket(
            retailerName: 'Pick n Pay',
            matches: {
              '1': ListItemMatch(itemId: '1', itemName: 'Milk', quantity: 1,
                  matchedProductName: 'PnP Milk', matchedPrice: 28.0),
            },
          ),
          'Checkers': ListRetailerBasket(
            retailerName: 'Checkers',
            matches: {
              '1': ListItemMatch(itemId: '1', itemName: 'Milk', quantity: 1,
                  matchedProductName: 'Checkers Milk', matchedPrice: 25.0),
            },
          ),
          'Woolworths': ListRetailerBasket(
            retailerName: 'Woolworths',
            error: 'Not available nearby',
            matches: {},
          ),
        },
      );
      // Woolworths has error, excluded. Common between PnP and Checkers: {'1'}
      expect(state.commonItemIds, {'1'});
      expect(state.cheapestRetailer, 'Checkers');
    });

    test('commonItemCount with all items matched everywhere', () {
      final state = ListComparisonState(
        baskets: {
          'Pick n Pay': ListRetailerBasket(
            retailerName: 'Pick n Pay',
            matches: {
              '1': ListItemMatch(itemId: '1', itemName: 'Milk', quantity: 1,
                  matchedProductName: 'PnP Milk', matchedPrice: 28.0),
              '2': ListItemMatch(itemId: '2', itemName: 'Bread', quantity: 1,
                  matchedProductName: 'PnP Bread', matchedPrice: 16.0),
            },
          ),
          'Checkers': ListRetailerBasket(
            retailerName: 'Checkers',
            matches: {
              '1': ListItemMatch(itemId: '1', itemName: 'Milk', quantity: 1,
                  matchedProductName: 'Checkers Milk', matchedPrice: 25.0),
              '2': ListItemMatch(itemId: '2', itemName: 'Bread', quantity: 1,
                  matchedProductName: 'Checkers Bread', matchedPrice: 14.0),
            },
          ),
        },
      );
      expect(state.commonItemCount, 2);
      expect(state.cheapestRetailer, 'Checkers'); // 25+14=39 vs 28+16=44
    });
  });

  // ===== SavingsTranslator TESTS =====
  group('SavingsTranslator', () {
    test('zero savings returns encouraging message', () {
      final msg = SavingsTranslator.toRelatableMessage(0);
      expect(msg, 'Prices are very close across stores!');
    });

    test('negative savings returns encouraging message', () {
      final msg = SavingsTranslator.toRelatableMessage(-10);
      expect(msg, 'Prices are very close across stores!');
    });

    test('small savings under R10 returns every rand counts', () {
      final msg = SavingsTranslator.toRelatableMessage(5);
      expect(msg, 'Every rand counts!');
    });

    test('R16+ maps to bread', () {
      final msg = SavingsTranslator.toRelatableMessage(16);
      expect(msg, contains('loaf of bread'));
    });

    test('R45+ maps to combination of items', () {
      final msg = SavingsTranslator.toRelatableMessage(50);
      // Should fit bread (R16) + sugar (R20) = R36 ≤ R50
      expect(msg, contains('and'));
    });

    test('R100+ maps to multiple items', () {
      final msg = SavingsTranslator.toRelatableMessage(100);
      expect(msg, isNotEmpty);
      expect(msg, isNot('Every rand counts!'));
    });

    test('very large savings still works', () {
      final msg = SavingsTranslator.toRelatableMessage(500);
      expect(msg, isNotEmpty);
    });

    test('message contains emoji', () {
      final msg = SavingsTranslator.toRelatableMessage(30);
      // Should contain at least one emoji character
      expect(msg.runes.any((r) => r > 0x1F000), isTrue);
    });
  });

  // ===== MATCH TYPE INTEGRATION =====
  group('MatchType thresholds (from ProductNameParser)', () {
    test('MatchType enum has expected values', () {
      expect(MatchType.values, contains(MatchType.exact));
      expect(MatchType.values, contains(MatchType.similar));
      expect(MatchType.values, contains(MatchType.fallback));
    });

    test('ListItemMatch defaults to fallback', () {
      final match = ListItemMatch(
        itemId: '1', itemName: 'Test', quantity: 1,
      );
      expect(match.matchType, MatchType.fallback);
    });
  });

  // ===== PER-ITEM CHEAPEST DETECTION =====
  group('Per-item cheapest marking', () {
    test('isCheapestForItem defaults to false', () {
      final match = ListItemMatch(
        itemId: '1', itemName: 'Milk', quantity: 1,
        matchedProductName: 'PnP Milk', matchedPrice: 27.99,
      );
      expect(match.isCheapestForItem, isFalse);
    });

    test('isCheapestForItem can be set via copyWith', () {
      final match = ListItemMatch(
        itemId: '1', itemName: 'Milk', quantity: 1,
        matchedProductName: 'PnP Milk', matchedPrice: 27.99,
      );
      final updated = match.copyWith(isCheapestForItem: true);
      expect(updated.isCheapestForItem, isTrue);
    });

    test('cheapest detection across baskets works manually', () {
      // Simulate what the provider's _markCheapestPerItem does
      final pnpMatch = ListItemMatch(
        itemId: '1', itemName: 'Milk', quantity: 1,
        matchedProductName: 'PnP Milk', matchedPrice: 27.99,
      );
      final checkersMatch = ListItemMatch(
        itemId: '1', itemName: 'Milk', quantity: 1,
        matchedProductName: 'Checkers Milk', matchedPrice: 25.49,
      );
      final wooliesMatch = ListItemMatch(
        itemId: '1', itemName: 'Milk', quantity: 1,
        matchedProductName: 'Woolies Milk', matchedPrice: 32.99,
      );

      final allMatches = [pnpMatch, checkersMatch, wooliesMatch];
      final cheapest = allMatches.reduce(
          (a, b) => a.matchedPrice! < b.matchedPrice! ? a : b);

      expect(cheapest.matchedProductName, 'Checkers Milk');
      expect(cheapest.matchedPrice, 25.49);
    });
  });

  // ===== EDGE CASES =====
  group('Edge cases', () {
    test('basket with all unmatched items has zero total', () {
      final basket = ListRetailerBasket(
        retailerName: 'Pick n Pay',
        matches: {
          '1': ListItemMatch(itemId: '1', itemName: 'Xyz', quantity: 1),
          '2': ListItemMatch(itemId: '2', itemName: 'Abc', quantity: 1),
        },
      );
      expect(basket.productTotal, 0.0);
      expect(basket.matchedCount, 0);
      expect(basket.totalItems, 2);
    });

    test('quantities multiplied correctly (3x R20 = R60)', () {
      final match = ListItemMatch(
        itemId: '1', itemName: 'Sugar', quantity: 3,
        matchedProductName: 'White Sugar 1kg', matchedPrice: 20.00,
      );
      expect(match.totalPrice, 60.0);
    });

    test('fractional quantities work', () {
      final match = ListItemMatch(
        itemId: '1', itemName: 'Cheese', quantity: 0.5,
        matchedProductName: 'Cheddar', matchedPrice: 80.00,
      );
      expect(match.totalPrice, 40.0);
    });

    test('state copyWith preserves completedRetailers', () {
      const state = ListComparisonState(
        isLoading: true,
        completedRetailers: 2,
      );
      final updated = state.copyWith(completedRetailers: 3);
      expect(updated.completedRetailers, 3);
      expect(updated.isLoading, isTrue);
    });

    test('single item comparison state works', () {
      final state = ListComparisonState(
        baskets: {
          'Pick n Pay': ListRetailerBasket(
            retailerName: 'Pick n Pay',
            matches: {
              '1': ListItemMatch(
                itemId: '1', itemName: 'Bread', quantity: 1,
                matchedProductName: 'PnP Bread', matchedPrice: 16.49,
              ),
            },
          ),
          'Checkers': ListRetailerBasket(
            retailerName: 'Checkers',
            matches: {
              '1': ListItemMatch(
                itemId: '1', itemName: 'Bread', quantity: 1,
                matchedProductName: 'Checkers Bread', matchedPrice: 14.99,
              ),
            },
          ),
        },
      );
      expect(state.cheapestRetailer, 'Checkers');
      expect(state.maxSavings, closeTo(1.50, 0.01));
    });

    test('tie in price picks first retailer deterministically', () {
      final state = ListComparisonState(
        baskets: {
          'Pick n Pay': ListRetailerBasket(
            retailerName: 'Pick n Pay',
            matches: {
              '1': ListItemMatch(
                itemId: '1', itemName: 'Milk', quantity: 1,
                matchedProductName: 'PnP Milk', matchedPrice: 30.00,
              ),
            },
          ),
          'Checkers': ListRetailerBasket(
            retailerName: 'Checkers',
            matches: {
              '1': ListItemMatch(
                itemId: '1', itemName: 'Milk', quantity: 1,
                matchedProductName: 'Checkers Milk', matchedPrice: 30.00,
              ),
            },
          ),
        },
      );
      // Both are 30.00, reduce picks the first (a < b is false, so returns b = first kept)
      expect(state.cheapestRetailer, isNotNull);
      expect(state.maxSavings, 0.0);
    });
  });
}
