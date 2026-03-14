// test/browse_filter_sort_test.dart
//
// Unit tests for Sprint 4 browse screen logic:
//   - isUnhealthyProduct() keyword detection (4c)
//   - applyHealthyFirst() partitioning (4c)
//   - applySort() all sort options (4b)
//   - ProductCategory.valueForRetailer() (4a)

import 'package:flutter_test/flutter_test.dart';
import 'package:milk/core/constants/product_categories.dart';
import 'package:milk/data/models/live_product.dart';
import 'package:milk/presentation/screens/products/live_browse_screen.dart';

// ─────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────

LiveProduct _product(
  String name, {
  double price = 10.0,
  bool hasPromo = false,
}) =>
    LiveProduct(
      name: name,
      price: 'R${price.toStringAsFixed(2)}',
      priceNumeric: price,
      promotionPrice: hasPromo ? 'R8.00' : 'No promo',
      retailer: 'Test',
    );

// ─────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────

void main() {
  // ─────────────────────────────────────────────
  // isUnhealthyProduct
  // ─────────────────────────────────────────────
  group('isUnhealthyProduct()', () {
    test('detects chips', () {
      expect(isUnhealthyProduct('Simba Chips Original'), isTrue);
      expect(isUnhealthyProduct('Lays Crisp'), isTrue);
    });

    test('detects chocolate', () {
      expect(isUnhealthyProduct('Cadbury Dairy Milk Chocolate'), isTrue);
    });

    test('detects cooldrink / soda', () {
      expect(isUnhealthyProduct('Coca-Cola Soda 2L'), isTrue);
      expect(isUnhealthyProduct('Fanta Cooldrink'), isTrue);
    });

    test('detects biscuits and cookies', () {
      expect(isUnhealthyProduct('Oreo Cookie'), isTrue);
      expect(isUnhealthyProduct('Tennis Biscuit'), isTrue);
    });

    test('detects sweets and candy', () {
      expect(isUnhealthyProduct('Jelly Tots Sweets'), isTrue);
      expect(isUnhealthyProduct('Gummy Bears'), isTrue);
    });

    test('detects ice cream', () {
      expect(isUnhealthyProduct('Ola Ice Cream Vanilla'), isTrue);
    });

    test('does NOT flag healthy products', () {
      expect(isUnhealthyProduct('Full Cream Milk 2L'), isFalse);
      expect(isUnhealthyProduct('Free Range Chicken Breast'), isFalse);
      expect(isUnhealthyProduct('Brown Bread Sliced'), isFalse);
      expect(isUnhealthyProduct('Baby Spinach 200g'), isFalse);
      expect(isUnhealthyProduct('Olive Oil 500ml'), isFalse);
      expect(isUnhealthyProduct('Large Eggs 6 Pack'), isFalse);
    });

    test('case-insensitive', () {
      expect(isUnhealthyProduct('SIMBA CHIPS'), isTrue);
      expect(isUnhealthyProduct('Chocolate Fudge Cake'), isTrue);
    });
  });

  // ─────────────────────────────────────────────
  // applyHealthyFirst
  // ─────────────────────────────────────────────
  group('applyHealthyFirst()', () {
    test('places healthy products before unhealthy ones', () {
      final products = [
        _product('Simba Chips'),
        _product('Full Cream Milk'),
        _product('Oreo Cookie'),
        _product('Baby Spinach'),
      ];

      final result = applyHealthyFirst(products);

      expect(result[0].name, 'Full Cream Milk');
      expect(result[1].name, 'Baby Spinach');
      expect(result[2].name, 'Simba Chips');
      expect(result[3].name, 'Oreo Cookie');
    });

    test('returns all products unchanged if all healthy', () {
      final products = [
        _product('Milk 2L'),
        _product('Chicken Breast'),
        _product('Brown Bread'),
      ];

      final result = applyHealthyFirst(products);
      expect(result.map((p) => p.name).toList(), [
        'Milk 2L',
        'Chicken Breast',
        'Brown Bread',
      ]);
    });

    test('returns all products unchanged if all unhealthy', () {
      final products = [
        _product('Chips Pack'),
        _product('Chocolate Bar'),
      ];

      final result = applyHealthyFirst(products);
      // Order within group preserved, just all unhealthy at end — but since
      // all are unhealthy, result is the same set
      expect(result.length, 2);
      expect(result.map((p) => p.name).toSet(), {'Chips Pack', 'Chocolate Bar'});
    });

    test('handles empty list', () {
      expect(applyHealthyFirst([]), isEmpty);
    });

    test('preserves relative order within healthy group', () {
      final products = [
        _product('Apples'),
        _product('Bananas'),
        _product('Chips'),
        _product('Carrots'),
      ];
      final result = applyHealthyFirst(products);
      expect(result[0].name, 'Apples');
      expect(result[1].name, 'Bananas');
      expect(result[2].name, 'Carrots');
      expect(result[3].name, 'Chips');
    });
  });

  // ─────────────────────────────────────────────
  // applySort
  // ─────────────────────────────────────────────
  group('applySort()', () {
    final products = [
      _product('Banana', price: 15.0),
      _product('Apple', price: 5.0),
      _product('Chips', price: 25.0),
      _product('Milk', price: 10.0),
    ];

    test('SortOption.priceLow sorts ascending by price', () {
      final result = applySort(products, SortOption.priceLow);
      final prices = result.map((p) => p.priceNumeric).toList();
      expect(prices, [5.0, 10.0, 15.0, 25.0]);
    });

    test('SortOption.priceHigh sorts descending by price', () {
      final result = applySort(products, SortOption.priceHigh);
      final prices = result.map((p) => p.priceNumeric).toList();
      expect(prices, [25.0, 15.0, 10.0, 5.0]);
    });

    test('SortOption.alphabetical sorts A-Z by name', () {
      final result = applySort(products, SortOption.alphabetical);
      final names = result.map((p) => p.name).toList();
      expect(names, ['Apple', 'Banana', 'Chips', 'Milk']);
    });

    test('SortOption.relevance applies healthy-first', () {
      final result = applySort(products, SortOption.relevance);
      // Chips is unhealthy — should be last
      expect(result.last.name, 'Chips');
    });

    test('does not mutate original list', () {
      final original = List<LiveProduct>.from(products);
      applySort(products, SortOption.priceLow);
      final names = products.map((p) => p.name).toList();
      final originalNames = original.map((p) => p.name).toList();
      expect(names, originalNames);
    });

    test('handles single product', () {
      final single = [_product('Milk', price: 10.0)];
      expect(applySort(single, SortOption.priceLow).length, 1);
    });

    test('handles empty list', () {
      expect(applySort([], SortOption.priceLow), isEmpty);
    });
  });

  // ─────────────────────────────────────────────
  // ProductCategory.valueForRetailer
  // ─────────────────────────────────────────────
  group('ProductCategory.valueForRetailer()', () {
    test('returns correct value for each retailer slug', () {
      final fruitVeg = ProductCategories.all.firstWhere(
        (c) => c.displayName == 'Fruit & Veg',
      );

      expect(fruitVeg.valueForRetailer('pnp'), 'Fruit & Veg');
      expect(fruitVeg.valueForRetailer('woolworths'), 'Fruit-Vegetables-Salads');
      expect(fruitVeg.valueForRetailer('checkers'), 'Fruit & Veg');
      expect(fruitVeg.valueForRetailer('shoprite'), 'Fruit & Veg');
    });

    test('returns null for unknown retailer slug', () {
      final bakery = ProductCategories.all.firstWhere(
        (c) => c.displayName == 'Bakery',
      );
      expect(bakery.valueForRetailer('unknown_retailer'), isNull);
    });

    test('all categories have values for all 4 retailers', () {
      const slugs = ['pnp', 'woolworths', 'checkers', 'shoprite'];
      for (final category in ProductCategories.all) {
        for (final slug in slugs) {
          expect(
            category.valueForRetailer(slug),
            isNotNull,
            reason:
                '${category.displayName} missing value for retailer "$slug"',
          );
        }
      }
    });

    test('all 8 expected categories are present', () {
      final names = ProductCategories.all.map((c) => c.displayName).toSet();
      expect(names, containsAll([
        'Fruit & Veg',
        'Dairy & Eggs',
        'Meat & Poultry',
        'Bakery',
        'Frozen',
        'Food Cupboard',
        'Snacks',
        'Beverages',
      ]));
    });
  });

  // ─────────────────────────────────────────────
  // SortOption enum
  // ─────────────────────────────────────────────
  group('SortOption labels', () {
    test('all options have non-empty labels', () {
      for (final option in SortOption.values) {
        expect(option.label, isNotEmpty);
      }
    });

    test('relevance is the default label', () {
      expect(SortOption.relevance.label, 'Relevance');
    });
  });
}
