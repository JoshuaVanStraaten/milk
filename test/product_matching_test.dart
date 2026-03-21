import 'package:flutter_test/flutter_test.dart';
import 'package:milk/data/models/live_product.dart';
import 'package:milk/data/services/gemini_service.dart';
import 'package:milk/data/services/ingredient_lookup.dart';
import 'package:milk/data/services/product_name_parser.dart';
import 'package:milk/data/services/smart_matching_service.dart';

/// Helper to create a LiveProduct for testing.
LiveProduct _product(String name, {double price = 29.99}) => LiveProduct(
      name: name,
      price: 'R${price.toStringAsFixed(2)}',
      priceNumeric: price,
      promotionPrice: 'No promo',
      retailer: 'Test',
    );

void main() {
  // ###########################################################################
  // SECTION 1: PRICE COMPARE MATCHING
  // ###########################################################################

  // =========================================================================
  // A. Search query generation
  // =========================================================================
  group('searchQuery', () {
    test('keeps brand, strips packaging filler', () {
      final parsed = ProductNameParser.parse('Coca-Cola Plastic 2L');
      expect(parsed.searchQuery, contains('coca-cola'));
      expect(parsed.searchQuery, isNot(contains('plastic')));
      expect(parsed.searchQuery, contains('2l'));
    });

    test('keeps brand + product words + size', () {
      final parsed =
          ProductNameParser.parse('Koo Baked Beans In Tomato Sauce 400g');
      expect(parsed.searchQuery, contains('koo'));
      expect(parsed.searchQuery, contains('baked'));
      expect(parsed.searchQuery, contains('beans'));
      expect(parsed.searchQuery, contains('400g'));
    });

    test('keeps multi-pack size intact', () {
      final parsed =
          ProductNameParser.parse('PnP UHT Full Cream Milk 6 x 1L');
      expect(parsed.searchQuery, contains('6'));
      expect(parsed.searchQuery, contains('1l'));
    });

    test('strips bottle/tin/loaf but keeps product words', () {
      final parsed =
          ProductNameParser.parse('Albany Superior Brown Bread Loaf 700g');
      expect(parsed.searchQuery, contains('albany'));
      expect(parsed.searchQuery, contains('brown'));
      expect(parsed.searchQuery, contains('bread'));
      expect(parsed.searchQuery, contains('700g'));
      expect(parsed.searchQuery, isNot(contains('loaf')));
    });

    test('strips slab but keeps chocolate info', () {
      final parsed =
          ProductNameParser.parse('Aero Milk Chocolate Slab 85g');
      expect(parsed.searchQuery, contains('aero'));
      expect(parsed.searchQuery, contains('chocolate'));
      expect(parsed.searchQuery, contains('85g'));
      expect(parsed.searchQuery, isNot(contains('slab')));
    });

    test('returns reasonable query for short product names', () {
      final parsed = ProductNameParser.parse('Milk 2L');
      expect(parsed.searchQuery.length, greaterThanOrEqualTo(3));
    });
  });

  // =========================================================================
  // B. Known cross-retailer EXACT matches (confidence >= 0.80)
  // =========================================================================
  group('exact matches (confidence >= 0.80)', () {
    final exactPairs = <(String, String)>[
      // Albany bread — identical names across retailers
      (
        'Albany Superior Brown Bread 700g',
        'Albany Superior Brown Bread 700g',
      ),
      // Albany bread — slight wording difference (Thick Sliced vs Thick Slice)
      (
        'Albany Superior Thick Sliced Brown Bread 700g',
        'Albany Superior Thick Slice Brown Bread 700g',
      ),
      // Bokomo Corn Flakes — identical across 3 retailers
      (
        'Bokomo Corn Flakes 1kg',
        'Bokomo Corn Flakes 1kg',
      ),
      // Aero chocolate — identical names Checkers vs Shoprite
      (
        'Aero Milk Chocolate Slab 85g',
        'Aero Milk Chocolate Slab 85g',
      ),
      // Baby Soft — "Pack" vs "pk"
      (
        'Baby Soft Fresh White Moist Toilet Tissue 42 Pack',
        'Baby Soft Fresh White Moist Toilet Tissue 42 pk',
      ),
      // Bakali chips — identical
      (
        'Bakali Salt & Vinegar Tortilla Chips 40g',
        'Bakali Salt & Vinegar Tortilla Chips 40g',
      ),
      // Albany bread — PnP naming vs Shoprite naming
      (
        'Albany Everyday Brown Bread 700g',
        'Albany Everyday Brown Bread Loaf 700g',
      ),
      // Bakers — PnP vs Checkers naming
      (
        'Bakers Good Morning Milk & Cereal 300g',
        'Bakers Good Morning Milk & Cereal Flavoured Breakfast Biscuits 300g',
      ),
      // ACE Rice — different filler words (Poly Bag vs Pack)
      (
        'Ace Maize Rice in Poly Bag 2.5kg',
        'ACE Maize Rice Pack 2.5kg',
      ),
      // Bull Brand — Checkers vs Shoprite identical
      (
        'Bull Brand Corned Meat 300g',
        'Bull Brand Corned Meat 300g',
      ),
      // All-Bran — identical across Checkers/Shoprite
      (
        'All-Bran Flakes Cereal 1kg',
        'All-Bran Flakes Cereal 1kg',
      ),
      // Albany wraps — PnP vs Checkers
      (
        'Albany Brown Wheat Wraps 6 Pack',
        'Albany Brown Wheat Wraps 6 x 45g',
      ),
      // Clover milk — PnP vs Checkers word order difference
      (
        'Clover Full Cream Milk Fresh 2L',
        'Clover Fresh Full Cream Milk 2L',
      ),
      // Doritos — PnP short vs Checkers verbose
      (
        'Doritos Supreme Cheese 145g',
        'Doritos Cheese Supreme Flavoured Corn Chips 145g',
      ),
      // KOO Baked Beans — case + spacing differences
      (
        'Koo Baked Beans In Tomato Sauce 400g',
        'KOO Baked Beans in Tomato Sauce 400g',
      ),
      // Koo Baked Beans — PnP vs Woolworths (space in size)
      (
        'Koo Baked Beans In Tomato Sauce 400g',
        'Koo Baked Beans in Tomato Sauce 400 g',
      ),
      // Frisco coffee — PnP vs Shoprite naming
      (
        'Frisco Instant Coffee 250g',
        'Frisco Original Instant Coffee & Chicory 250g',
      ),
      // Cape Point Pilchards — Checkers vs Shoprite identical
      (
        'Cape Point Pilchards In Tomato Sauce 400g',
        'Cape Point Pilchards In Tomato Sauce 400g',
      ),
      // Clover milk 6-pack — Checkers vs Shoprite identical
      (
        'Clover Full Cream Milk 6 x 1L',
        'Clover Full Cream Milk 6 x 1L',
      ),
    ];

    for (final (source, candidate) in exactPairs) {
      test('$source ↔ $candidate', () {
        final s = ProductNameParser.parse(source);
        final c = ProductNameParser.parse(candidate);
        final confidence = ProductNameParser.computeConfidence(s, c);
        expect(
          confidence,
          greaterThanOrEqualTo(0.80),
          reason:
              'Expected exact match (>=0.80) but got $confidence for "$source" vs "$candidate"',
        );
      });
    }
  });

  // =========================================================================
  // C. Known NON-matches (confidence < 0.55)
  // =========================================================================
  group('non-matches (confidence < 0.55)', () {
    final nonMatchPairs = <(String, String)>[
      ('Coca-Cola Plastic 2L', 'Millor Plastic Container 400ml'),
      (
        'Koo Baked Beans In Tomato Sauce 400g',
        'Glenryck Pilchards In Tomato Sauce 400g',
      ),
      (
        'Koo Baked Beans In Tomato Sauce 400g',
        'Lucky Star Pilchards In Tomato Sauce 400g',
      ),
      ('Albany Everyday Brown Bread 700g', 'Bokomo Corn Flakes 500g'),
      (
        'Cape Point Pilchards In Tomato Sauce 400g',
        'Cape Point Light Meat Tuna Chunks 170g',
      ),
    ];

    for (final (source, candidate) in nonMatchPairs) {
      test('$source ↔ $candidate', () {
        final s = ProductNameParser.parse(source);
        final c = ProductNameParser.parse(candidate);
        final confidence = ProductNameParser.computeConfidence(s, c);
        expect(
          confidence,
          lessThan(0.55),
          reason:
              'Expected non-match (<0.55) but got $confidence for "$source" vs "$candidate"',
        );
      });
    }
  });

  // =========================================================================
  // D. Variant conflict tests — similar but NOT exact
  // =========================================================================
  group('variant conflicts (similar, not exact)', () {
    final variantConflictPairs = <(String, String)>[
      ('Albany Everyday Brown Bread 700g', 'Albany Everyday White Bread 700g'),
      ('Aero Milk Chocolate Slab 85g', 'Aero Dark Chocolate Slab 85g'),
      ('Bull Brand Corned Meat 300g', 'Bull Brand Meatballs in Gravy 400g'),
      (
        'Koo Baked Beans in Tomato Sauce 420g',
        'Koo Butter Beans in Tomato Sauce 420g',
      ),
      (
        'Lucky Star Pilchards In Tomato Sauce 400g',
        'Lucky Star Sardines In Tomato Sauce 400g',
      ),
      (
        'Clover Fresh Full Cream Milk 2L',
        'Clover Fresh Low Fat Milk 2L',
      ),
      (
        'KOO Baked Beans In Tomato Sauce 215g',
        'KOO Baked Beans In Chilli Sauce Can 420g',
      ),
      (
        'Coca-Cola Original Soft Drink 2 L',
        'Coca-Cola Zero Sugar Soft Drink 2 L',
      ),
    ];

    for (final (source, candidate) in variantConflictPairs) {
      test('$source ↔ $candidate', () {
        final s = ProductNameParser.parse(source);
        final c = ProductNameParser.parse(candidate);
        final confidence = ProductNameParser.computeConfidence(s, c);
        expect(
          confidence,
          lessThan(0.80),
          reason:
              'Expected NOT exact (<0.80) for variant conflict but got $confidence',
        );
      });
    }
  });

  // =========================================================================
  // E. AI-territory: different naming but same product (at least similar)
  // =========================================================================
  group('AI-territory matches (at least similar, >= 0.55)', () {
    test('Coca-Cola Plastic 2L vs Original Soft Drink 2L', () {
      final s = ProductNameParser.parse('Coca-Cola Plastic 2L');
      final c = ProductNameParser.parse('Coca-Cola Original Soft Drink 2 L');
      final confidence = ProductNameParser.computeConfidence(s, c);
      expect(confidence, greaterThanOrEqualTo(0.55),
          reason: 'Same product, very different naming — at least similar');
    });

    test('Domestos Lemon PnP verbose vs Shoprite concise', () {
      final s = ProductNameParser.parse(
          'Domestos Lemon Multipurpose Stain Removal Thick Bleach Cleaner 750ml');
      final c = ProductNameParser.parse(
          'Domestos Lemon Fresh Multipurpose Thick Bleach 750ml');
      final confidence = ProductNameParser.computeConfidence(s, c);
      expect(confidence, greaterThanOrEqualTo(0.55),
          reason: 'Same product, different descriptors — at least similar');
    });
  });

  // =========================================================================
  // E2. Strawberry / single-word product matching
  // =========================================================================
  group('single-word product matching (strawberry bug)', () {
    test('Strawberries 400g should parse with empty normalizedName', () {
      final parsed = ProductNameParser.parse('Strawberries 400g');
      // brand fallback = "strawberries" (first word), no variant match
      // ("strawberries" does NOT contain "strawberry" as substring in Dart)
      // normalizedName = "" after brand removal
      expect(parsed.brand, equals('strawberries'));
      expect(parsed.normalizedName, isEmpty);
    });

    test('PnP Strawberries 250g should match Strawberries 400g as similar', () {
      final s = ProductNameParser.parse('Strawberries 400g');
      final c = ProductNameParser.parse('PnP Strawberries 250g');
      final confidence = ProductNameParser.computeConfidence(s, c);
      expect(
        confidence,
        greaterThanOrEqualTo(0.55),
        reason:
            'Same product (fresh strawberries) different sizes — should be at least similar. Got $confidence',
      );
    });

    test('Strawberries 400g should NOT match Replace Strawberry Drink 400g', () {
      final s = ProductNameParser.parse('Strawberries 400g');
      final c = ProductNameParser.parse('Replace Strawberry Drink 400g');
      // Category mismatch should reject this via _hasCategoryMismatch
      final match = ProductNameParser.classify(
        source: s,
        candidate: c,
        retailer: 'Test',
        name: 'Replace Strawberry Drink 400g',
        price: 'R49.99',
        priceNumeric: 49.99,
        sourcePrice: 39.99,
      );
      expect(match, isNull,
          reason: '"Replace Strawberry Drink" is a meal replacement, not fresh fruit');
    });

    test('Strawberries 400g should NOT match Strawberry Flavoured Yoghurt 175g', () {
      final s = ProductNameParser.parse('Strawberries 400g');
      final c = ProductNameParser.parse('Danone Strawberry Flavoured Yoghurt 175g');
      final match = ProductNameParser.classify(
        source: s,
        candidate: c,
        retailer: 'Test',
        name: 'Danone Strawberry Flavoured Yoghurt 175g',
        price: 'R12.99',
        priceNumeric: 12.99,
        sourcePrice: 39.99,
      );
      expect(match, isNull,
          reason: 'Flavoured yoghurt is not fresh strawberries');
    });

    test('Strawberries 400g should NOT match PnP Double Cream Strawberries & Cream', () {
      final s = ProductNameParser.parse('Strawberries 400 g');
      final c = ProductNameParser.parse('PnP Double Cream Strawberries & Cream');
      final match = ProductNameParser.classify(
        source: s,
        candidate: c,
        retailer: 'Pick n Pay',
        name: 'PnP Double Cream Strawberries & Cream',
        price: 'R12.99',
        priceNumeric: 12.99,
        sourcePrice: 89.99,
      );
      expect(match, isNull,
          reason: 'Double Cream dessert is not fresh strawberries');
    });

    test('Strawberries 400g should match Woolworths Strawberries 250g', () {
      final s = ProductNameParser.parse('Strawberries 400g');
      final c = ProductNameParser.parse('Woolworths Strawberries 250g');
      final confidence = ProductNameParser.computeConfidence(s, c);
      expect(
        confidence,
        greaterThanOrEqualTo(0.55),
        reason:
            'Same product different retailer brand — should be at least similar. Got $confidence',
      );
    });

    test('Bananas 1kg should match PnP Bananas 750g as similar', () {
      final s = ProductNameParser.parse('Bananas 1kg');
      final c = ProductNameParser.parse('PnP Bananas 750g');
      final confidence = ProductNameParser.computeConfidence(s, c);
      expect(
        confidence,
        greaterThanOrEqualTo(0.30),
        reason:
            'Same product (bananas) — should be at least fallback. Got $confidence',
      );
    });

    test('Bananas 650g vs Bananas 950g should be similar, NOT exact', () {
      final s = ProductNameParser.parse('Bananas 650g');
      final c = ProductNameParser.parse('Bananas 950g');
      final confidence = ProductNameParser.computeConfidence(s, c);
      expect(
        confidence,
        greaterThanOrEqualTo(0.55),
        reason: 'Same product different size — should be at least similar. Got $confidence',
      );
      expect(
        confidence,
        lessThan(0.80),
        reason: '650g vs 950g is a 46% size diff — should NOT be exact. Got $confidence',
      );
    });

    test('Bananas 650g vs Bananas 1.2kg should be similar or fallback, NOT exact', () {
      final s = ProductNameParser.parse('Bananas 650g');
      final c = ProductNameParser.parse('Bananas 1.2kg');
      final confidence = ProductNameParser.computeConfidence(s, c);
      expect(
        confidence,
        lessThan(0.80),
        reason: '650g vs 1.2kg is a huge size diff — should NOT be exact. Got $confidence',
      );
    });

    test('Tomatoes 1kg should match PnP Tomatoes 500g as similar', () {
      final s = ProductNameParser.parse('Tomatoes 1kg');
      final c = ProductNameParser.parse('PnP Tomatoes 500g');
      final confidence = ProductNameParser.computeConfidence(s, c);
      expect(
        confidence,
        greaterThanOrEqualTo(0.30),
        reason:
            'Same product (tomatoes) — should be at least fallback. Got $confidence',
      );
    });
  });

  // =========================================================================
  // F. Size mismatch tests
  // =========================================================================
  group('size mismatches', () {
    test('7-Up vs 7UP different naming — at least similar', () {
      final s = ProductNameParser.parse('7-Up Sugar Free 2L');
      final c = ProductNameParser.parse(
          '7UP Sugar Free Lemon and Lime Flavoured Soft Drink 2L');
      final confidence = ProductNameParser.computeConfidence(s, c);
      expect(confidence, greaterThanOrEqualTo(0.55),
          reason: 'Same product with different naming should be at least similar');
    });

    test('6x1L vs 1L should not be similar or exact', () {
      final sixPack = ProductNameParser.parse('PnP UHT Full Cream Milk 6 x 1L');
      final single = ProductNameParser.parse('Ritebrand Full Cream Milk 1L');
      final confidence =
          ProductNameParser.computeConfidence(sixPack, single);
      expect(confidence, lessThan(0.55),
          reason: '6-pack should not be similar to single — size gate');
    });

    test('400g vs 410g should still match (within 5%)', () {
      final a = ProductNameParser.parse('Koo Baked Beans 400g');
      final b = ProductNameParser.parse('Koo Baked Beans 410g');
      final confidence = ProductNameParser.computeConfidence(a, b);
      expect(confidence, greaterThanOrEqualTo(0.80),
          reason: '400g vs 410g is within 5% tolerance');
    });

    test('500g vs 1kg should not be similar or exact', () {
      final a = ProductNameParser.parse('Bokomo Corn Flakes 500g');
      final b = ProductNameParser.parse('Bokomo Corn Flakes 1kg');
      final confidence = ProductNameParser.computeConfidence(a, b);
      expect(confidence, lessThan(0.55),
          reason: '500g vs 1kg is a 100% size difference — size gate');
    });

    test('30 eggs vs 6 eggs should not be similar', () {
      final a = ProductNameParser.parse('Eggs 30 Pack');
      final b = ProductNameParser.parse('Eggs 6 Pack');
      final confidence = ProductNameParser.computeConfidence(a, b);
      expect(confidence, lessThan(0.55),
          reason: '30 vs 6 eggs — huge count difference, size gate');
    });
  });

  // ###########################################################################
  // SECTION 2: RECIPE INGREDIENT MATCHING
  // ###########################################################################

  group('recipe ingredient matching', () {
    late SmartMatchingService matcher;

    setUp(() {
      matcher = SmartMatchingService(
        gemini: GeminiService(apiKey: 'test-key'),
      );
    });

    // =========================================================================
    // G. Correct matches — should pick the right product
    // =========================================================================
    group('correct matches', () {
      test('lemon should match PnP Lemons, not Lemon Cake', () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'lemon',
          candidates: [
            _product('Lemon Condensed Cake', price: 49.99),
            _product('PnP Lemons 850g', price: 24.99),
            _product('Goldcrest Lemon Pesto 140g', price: 34.99),
          ],
        );
        expect(result, isNotNull);
        expect(result!.name, contains('Lemons'));
      });

      test('eggs should match Large Eggs, not chocolate eggs', () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'eggs',
          candidates: [
            _product('Eggs Galore Milk Chocolate Mallow Egg', price: 4.99),
            _product('Large Eggs 6 Pack', price: 26.99),
          ],
        );
        expect(result, isNotNull);
        expect(result!.name, contains('Large Eggs'));
      });

      test('brown onion should match Brown Onions, not gravy', () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'brown onion',
          candidates: [
            _product('Royco Brown Onion Instant Gravy Pack 32g', price: 19.99),
            _product('Brown Onions 1kg', price: 14.99),
          ],
        );
        expect(result, isNotNull);
        expect(result!.name, contains('Brown Onions'));
      });

      test('salt should match Table Salt, not Dishwasher Salt', () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'salt',
          candidates: [
            _product('Marina Dishwasher Salt 1kg', price: 19.99),
            _product('Cerebos Iodated Table Salt 500g', price: 12.99),
          ],
        );
        expect(result, isNotNull);
        expect(result!.name, contains('Table Salt'));
      });

      test('chocolate ingredient should match actual chocolate (not disqualified)',
          () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'dark chocolate',
          candidates: [
            _product('Dark Cooking Chocolate 100g', price: 29.99),
            _product('Chocolate Milk 1L', price: 24.99),
          ],
        );
        expect(result, isNotNull);
        expect(result!.name, contains('Cooking Chocolate'));
      });

      test('soy sauce should match actual soy sauce (sauce not disqualified)',
          () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'soy sauce',
          candidates: [
            _product('Kikkoman Soy Sauce 250ml', price: 44.99),
            _product('Soy Milk 1L', price: 29.99),
          ],
        );
        expect(result, isNotNull);
        expect(result!.name, contains('Soy Sauce'));
      });

      test('milk should match Full Cream Milk, not chocolate bar', () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'full cream milk',
          candidates: [
            _product('Lindt Milk Hazelnut Bar 35g', price: 34.99),
            _product('Douglasdale Full Cream Milk 2L', price: 36.99),
          ],
        );
        expect(result, isNotNull);
        expect(result!.name, contains('Full Cream Milk'));
      });

      test('vegetable oil should match oil, not mussels in oil', () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'vegetable oil',
          candidates: [
            _product('Goldcrest Smoked Mussels In Vegetable Oil 85g',
                price: 34.99),
            _product('PnP Vegetable Oil 750ml', price: 29.99),
          ],
        );
        expect(result, isNotNull);
        expect(result!.name, contains('Vegetable Oil'));
      });

      test('tomato paste ingredient should match tomato paste (paste not disqualified)',
          () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'tomato paste',
          candidates: [
            _product('All Gold Tomato Paste 100g', price: 9.99),
            _product('Fresh Tomatoes 1kg', price: 19.99),
          ],
        );
        expect(result, isNotNull);
        expect(result!.name, contains('Tomato Paste'));
      });
    });

    // =========================================================================
    // H. Should return null — no viable match exists
    // =========================================================================
    group('no viable match', () {
      test('lemon with only processed candidates should return null', () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'lemon',
          candidates: [
            _product('Lemon Condensed Cake', price: 49.99),
            _product('Goldcrest Lemon Pesto 140g', price: 34.99),
            _product('Lemon Cream Biscuits 200g', price: 19.99),
          ],
        );
        expect(result, isNull,
            reason: 'No fresh lemons in candidates — should return null');
      });

      test('red bell pepper with only sauce should return null', () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'red bell pepper',
          candidates: [
            _product('Imana Red Pepper Sauce 38g', price: 15.99),
          ],
        );
        expect(result, isNull,
            reason: 'Pepper sauce is not a bell pepper');
      });

      test('water with only gripe water should return null', () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'water',
          candidates: [
            _product('Medirite Gripe Water 100ml', price: 59.99),
          ],
        );
        expect(result, isNull,
            reason: 'Gripe water is medicine, not drinking water');
      });

      test('honey with only honey mustard should return null', () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'honey',
          candidates: [
            _product('Maille Honey Mustard 230g', price: 74.99),
          ],
        );
        expect(result, isNull,
            reason: 'Honey mustard is a condiment, not honey');
      });

      test('onion with only onion-flavoured products should return null',
          () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'onion',
          candidates: [
            _product('Royco Brown Onion Instant Gravy Pack 32g', price: 19.99),
            _product('Simba Creamy Onion Chips 120g', price: 14.99),
          ],
        );
        expect(result, isNull,
            reason: 'Gravy and chips are not onions');
      });
    });

    // =========================================================================
    // H2. Previously unmatched ingredients (Sprint 3e fixes)
    // =========================================================================
    group('previously unmatched ingredients', () {
      test('Hake Fillets should match PnP Hake Fillets, not fish cakes',
          () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'Hake Fillets',
          candidates: [
            _product('PnP Hake Fillets 800g', price: 89.99),
            _product('Hake Fish Cakes 400g', price: 39.99),
          ],
        );
        expect(result, isNotNull);
        expect(result!.name, contains('Hake Fillets'));
      });

      test('Stir Fry Vegetables should match stir fry veg, not soup',
          () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'Stir Fry Vegetables',
          candidates: [
            _product('PnP Stir Fry Vegetables 400g', price: 29.99),
            _product('Knorr Vegetable Soup 50g', price: 14.99),
          ],
        );
        expect(result, isNotNull);
        expect(result!.name, contains('Stir Fry'));
      });

      test('Hyphenated stir-fry matches non-hyphenated Stir Fry', () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'Mixed Stir-fry Vegetables',
          candidates: [
            _product('PnP Stir Fry Vegetables 400g', price: 29.99),
          ],
        );
        expect(result, isNotNull);
        expect(result!.name, contains('Stir Fry'));
      });

      test('Stir Fry Vegetables matches real API products without "vegetables"',
          () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'Stir Fry Vegetables',
          candidates: [
            _product('PnP Stir Fry Julienne 420g', price: 37.99),
            _product('PnP Sweet & Sour Stir Fry Sauce 100g', price: 23.99),
            _product('McCain Asian Stir Fry Vegetable Mix 700g', price: 44.99),
            _product('Chicken Stir Fry Per kg', price: 99.99),
          ],
        );
        expect(result, isNotNull);
        expect(result!.name, isNot(contains('Sauce')));
        expect(result.name, isNot(contains('Chicken')));
      });

      test('Sesame Seeds should not match rice cakes', () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'Sesame Seeds',
          candidates: [
            _product('Bakali Wild Sesame Seeds Rice Cakes 115g', price: 26.99),
          ],
        );
        expect(result, isNull,
            reason: 'Rice cakes are a snack, not sesame seeds');
      });

      test('Sesame Seeds should match sesame seeds, not sesame oil', () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'Sesame Seeds',
          candidates: [
            _product('Sesame Seeds 100g', price: 19.99),
            _product('Sesame Oil 250ml', price: 44.99),
          ],
        );
        expect(result, isNotNull);
        expect(result!.name, contains('Sesame Seeds'));
      });

      test('Sesame Seeds should not match crackers', () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'Sesame Seeds',
          candidates: [
            _product('Laurieri Grissotti Sesame Seeds Crackers 150g',
                price: 39.99),
          ],
        );
        expect(result, isNull,
            reason: 'Crackers are a snack, not sesame seeds');
      });

      test('Chilli Powder should match actual chilli powder, not bulk chilli',
          () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'Chilli Powder',
          candidates: [
            _product('Chilli Per kg', price: 69.90),
            _product('Robertsons Chilli Powder 100ml', price: 29.99),
          ],
        );
        expect(result, isNotNull);
        expect(result!.name, contains('Chilli Powder'));
      });

      test('Chilli Powder with only bulk chilli should return null', () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'Chilli Powder',
          candidates: [
            _product('Chilli Per kg', price: 69.90),
          ],
        );
        expect(result, isNull,
            reason: 'Bulk chilli is missing "powder" — not the same product');
      });

      test('Garam Masala should match actual garam masala', () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'Garam Masala',
          candidates: [
            _product('Robertsons Garam Masala 100ml', price: 34.99),
            _product('Masala Paste 400g', price: 49.99),
          ],
        );
        expect(result, isNotNull);
        expect(result!.name, contains('Garam Masala'));
      });
    });

    // =========================================================================
    // H3. Qualifier-aware matching (color/variety qualifiers may be absent)
    // =========================================================================
    group('qualifier-aware matching', () {
      test('Brown Onion matches Onions 1kg (color qualifier missing)', () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'Brown Onion',
          candidates: [
            _product('Onions 1kg', price: 19.99),
          ],
        );
        expect(result, isNotNull);
        expect(result!.name, contains('Onions'));
      });

      test('Red Bell Pepper matches Bell Peppers (color qualifier missing)',
          () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'Red Bell Pepper',
          candidates: [
            _product('PnP Bell Peppers 3 Pack', price: 19.99),
          ],
        );
        expect(result, isNotNull);
        expect(result!.name, contains('Bell Peppers'));
      });

      test('Green Beans matches Beans 500g (color qualifier missing)', () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'Green Beans',
          candidates: [
            _product('Beans 500g', price: 14.99),
          ],
        );
        expect(result, isNotNull);
        expect(result!.name, contains('Beans'));
      });

      test('Brown Onion prefers Brown Onions over plain Onions', () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'Brown Onion',
          candidates: [
            _product('Onions 1kg', price: 19.99),
            _product('Brown Onions 1kg', price: 14.99),
          ],
        );
        expect(result, isNotNull);
        expect(result!.name, contains('Brown Onions'));
      });
    });

    // =========================================================================
    // I. Plural/stemming tests
    // =========================================================================
    group('plural stemming', () {
      test('singular lemon matches plural Lemons', () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'lemon',
          candidates: [
            _product('PnP Lemons 850g', price: 24.99),
          ],
        );
        expect(result, isNotNull);
        expect(result!.name, contains('Lemons'));
      });

      test('singular pepper matches plural Peppers', () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'bell pepper',
          candidates: [
            _product('PnP Bell Peppers 3 Pack', price: 19.99),
          ],
        );
        expect(result, isNotNull);
        expect(result!.name, contains('Peppers'));
      });

      test('singular egg matches plural Eggs', () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'egg',
          candidates: [
            _product('Fairacres Eggs 6 Pack', price: 26.99),
          ],
        );
        expect(result, isNotNull);
        expect(result!.name, contains('Eggs'));
      });

      test('singular tomato matches plural Tomatoes', () async {
        final result = await matcher.matchIngredient(
          ingredientName: 'tomato',
          candidates: [
            _product('Roma Tomatoes 1kg', price: 29.99),
          ],
        );
        expect(result, isNotNull);
        expect(result!.name, contains('Tomatoes'));
      });
    });
  });

  // ###########################################################################
  // SECTION 3: INGREDIENT LOOKUP & HINT-ASSISTED MATCHING
  // ###########################################################################

  group('ingredient lookup resolution', () {
    test('exact match returns hint', () {
      final hint = IngredientLookup.resolve('butter');
      expect(hint, isNotNull);
      expect(hint!.searchQuery, contains('butter'));
      expect(hint.excludeWords, contains('chicken'));
    });

    test('exact match — multi-word', () {
      final hint = IngredientLookup.resolve('olive oil');
      expect(hint, isNotNull);
      expect(hint!.requiredWords, contains('olive'));
      expect(hint.requiredWords, contains('oil'));
    });

    test('partial match — ingredient contains key', () {
      final hint = IngredientLookup.resolve('unsalted butter');
      expect(hint, isNotNull);
      expect(hint!.searchQuery, contains('unsalted'));
    });

    test('case insensitive', () {
      final hint = IngredientLookup.resolve('Olive Oil');
      expect(hint, isNotNull);
    });

    test('unknown ingredient returns null', () {
      final hint = IngredientLookup.resolve('dragon fruit');
      expect(hint, isNull);
    });

    test('empty string returns null', () {
      final hint = IngredientLookup.resolve('');
      expect(hint, isNull);
    });
  });

  group('hint-assisted ingredient matching', () {
    late SmartMatchingService matcher;
    setUp(() {
      matcher = SmartMatchingService(gemini: GeminiService(apiKey: 'test-key'));
    });

    test('butter with hint excludes Butter Chicken', () async {
      final hint = IngredientLookup.resolve('butter');
      final result = await matcher.matchIngredient(
        ingredientName: 'butter',
        candidates: [
          _product('Butter Chicken Curry 400g', price: 49.99),
          _product('Act II Microwave Popcorn Butter Lovers 85g', price: 24.99),
          _product('Clover Salted Butter 500g', price: 54.99),
          _product('Peanut Butter Smooth 400g', price: 44.99),
        ],
        hint: hint,
      );
      expect(result, isNotNull);
      expect(result!.name, contains('Clover'));
    });

    test('milk with hint excludes Milk Chocolate', () async {
      final hint = IngredientLookup.resolve('milk');
      final result = await matcher.matchIngredient(
        ingredientName: 'milk',
        candidates: [
          _product('Lindt Milk Chocolate Slab 100g', price: 54.99),
          _product('Clover Full Cream Milk 2L', price: 36.99),
          _product('Aquafresh Milk Teeth Toothbrush', price: 29.99),
        ],
        hint: hint,
      );
      expect(result, isNotNull);
      expect(result!.name, contains('Full Cream Milk'));
    });

    test('eggs with hint excludes chocolate eggs', () async {
      final hint = IngredientLookup.resolve('eggs');
      final result = await matcher.matchIngredient(
        ingredientName: 'eggs',
        candidates: [
          _product('Eggs Galore Chocolate Mallow Egg 16g', price: 3.99),
          _product('Cadbury Mini Eggs 74g', price: 34.99),
          _product('Eggbert Large Eggs 6 Pack', price: 22.99),
        ],
        hint: hint,
      );
      expect(result, isNotNull);
      expect(result!.name, contains('Eggbert'));
    });

    test('salt with hint excludes Dishwasher Salt', () async {
      final hint = IngredientLookup.resolve('salt');
      final result = await matcher.matchIngredient(
        ingredientName: 'salt',
        candidates: [
          _product('Marina Dishwasher Salt 2kg', price: 49.99),
          _product('Salt and Vinegar Crisps 125g', price: 24.99),
          _product('Cerebos Iodated Table Salt 500g', price: 19.99),
        ],
        hint: hint,
      );
      expect(result, isNotNull);
      expect(result!.name, contains('Cerebos'));
    });

    test('sugar with hint excludes sugar-free drinks', () async {
      final hint = IngredientLookup.resolve('sugar');
      final result = await matcher.matchIngredient(
        ingredientName: 'sugar',
        candidates: [
          _product('7UP Sugar Free Soft Drink 500ml', price: 11.99),
          _product('Beacon Slab Milk Chocolate 80g', price: 19.99),
          _product('Selati White Sugar 2.5kg', price: 49.99),
        ],
        hint: hint,
      );
      expect(result, isNotNull);
      expect(result!.name, contains('Selati'));
    });

    test('rice with hint excludes Rice Cakes', () async {
      final hint = IngredientLookup.resolve('rice');
      final result = await matcher.matchIngredient(
        ingredientName: 'rice',
        candidates: [
          _product('Rice Cakes with Yoghurt Coating 175g', price: 72.99),
          _product('Tastic Long Grain Parboiled Rice 2kg', price: 49.99),
          _product('Rice Vermicelli 400g', price: 74.99),
        ],
        hint: hint,
      );
      expect(result, isNotNull);
      expect(result!.name, contains('Tastic'));
    });

    test('olive oil with hint excludes tuna in olive oil', () async {
      final hint = IngredientLookup.resolve('olive oil');
      final result = await matcher.matchIngredient(
        ingredientName: 'olive oil',
        candidates: [
          _product('Albacore Tuna Fillets in Olive Oil 180g', price: 84.99),
          _product('B-well Extra Virgin Olive Oil 1L', price: 89.99),
          _product('Olive Oil Breadsticks 100g', price: 49.99),
        ],
        hint: hint,
      );
      expect(result, isNotNull);
      expect(result!.name, contains('B-well'));
    });

    test('cream with hint excludes Ice Cream and Cream Cheese', () async {
      final hint = IngredientLookup.resolve('cream');
      final result = await matcher.matchIngredient(
        ingredientName: 'cream',
        candidates: [
          _product('Cream Cheese Spread 230g', price: 39.99),
          _product('Magnum Ice Cream Bar 100ml', price: 34.99),
          _product('Parmalat Fresh Cream 250ml', price: 24.99),
        ],
        hint: hint,
      );
      expect(result, isNotNull);
      expect(result!.name, contains('Fresh Cream'));
    });

    test('onion with hint excludes Onion Soup and Onion Rings', () async {
      final hint = IngredientLookup.resolve('onion');
      final result = await matcher.matchIngredient(
        ingredientName: 'onion',
        candidates: [
          _product('Knorr Brown Onion Soup 50g', price: 14.99),
          _product('Onion Rings Frozen 500g', price: 39.99),
          _product('Onions 1kg', price: 19.99),
        ],
        hint: hint,
      );
      expect(result, isNotNull);
      expect(result!.name, equals('Onions 1kg'));
    });

    test('garlic with hint excludes Garlic Bread and Garlic Sauce', () async {
      final hint = IngredientLookup.resolve('garlic');
      final result = await matcher.matchIngredient(
        ingredientName: 'garlic',
        candidates: [
          _product('Garlic Bread Baguette 300g', price: 29.99),
          _product('Garlic and Herb Sauce 250ml', price: 34.99),
          _product('Garlic 150g', price: 29.99),
        ],
        hint: hint,
      );
      expect(result, isNotNull);
      expect(result!.name, equals('Garlic 150g'));
    });

    test('hint graceful degradation — all filtered out falls back', () async {
      // If hint filtering removes everything, should fall back to unfiltered
      final hint = IngredientSearchHint(
        searchQuery: 'butter',
        requiredWords: {'impossible_word_xyz'},
      );
      final result = await matcher.matchIngredient(
        ingredientName: 'butter',
        candidates: [
          _product('Clover Butter 500g', price: 54.99),
        ],
        hint: hint,
      );
      // Should still match via fallback
      expect(result, isNotNull);
      expect(result!.name, contains('Butter'));
    });

    test('pepper with hint excludes Peppermint and Pepper Steak', () async {
      final hint = IngredientLookup.resolve('pepper');
      final result = await matcher.matchIngredient(
        ingredientName: 'pepper',
        candidates: [
          _product('Peppermint Caramel Dessert 420g', price: 129.99),
          _product('Pepper Crusted Beef Fillet 800g', price: 399.99),
          _product('Cape Herb Black Pepper Grinder 50g', price: 58.99),
        ],
        hint: hint,
      );
      expect(result, isNotNull);
      expect(result!.name, contains('Black Pepper'));
    });
  });
}
