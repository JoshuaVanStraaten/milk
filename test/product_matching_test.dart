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

  // ###########################################################################
  // SECTION 4: SPAR INTEGRATION TESTS
  // ###########################################################################

  // =========================================================================
  // A. SPAR name preprocessing — barcode stripping
  // =========================================================================
  group('SPAR barcode stripping', () {
    test('strips SK barcode suffix from SPAR product names', () {
      final parsed = ProductNameParser.parse(
          'Albany Best Of Both Genius Speciality Bread 700g SK6009518602649');
      expect(parsed.originalName,
          equals('Albany Best Of Both Genius Speciality Bread 700g'));
      expect(parsed.brand, equals('albany'));
      expect(parsed.sizeValue, equals(700));
      expect(parsed.sizeUnit, equals('g'));
    });

    test('strips barcode from SPAR own-brand product', () {
      final parsed = ProductNameParser.parse(
          'Cultured Buttermilk Low Fat 500g Spar SK6001008731242');
      expect(parsed.originalName, isNot(contains('SK6001008731242')));
      expect(parsed.sizeValue, equals(500));
      expect(parsed.sizeUnit, equals('g'));
    });

    test('strips barcode from product with brand at end', () {
      final parsed = ProductNameParser.parse(
          'Aero Milk Chocolate 85g Nestle SK6009188000080');
      expect(parsed.originalName, isNot(contains('SK6009188000080')));
      expect(parsed.brand, equals('aero'));
      expect(parsed.sizeValue, equals(85));
    });

    test('handles product with no barcode (non-SPAR)', () {
      final parsed = ProductNameParser.parse('Clover Full Cream Milk 2L');
      expect(parsed.originalName, equals('Clover Full Cream Milk 2L'));
      expect(parsed.brand, equals('clover'));
    });

    test('strips barcode with 13-digit code', () {
      final parsed = ProductNameParser.parse(
          'Lucky Star Pilchards In Tomato Sauce 400g SK6009522300123');
      expect(parsed.originalName, isNot(contains('SK')));
      expect(parsed.brand, equals('lucky star'));
      expect(parsed.sizeValue, equals(400));
    });

    test('strips barcode with varying lengths (10-16 digits)', () {
      final p1 = ProductNameParser.parse('Test Product 100g SK0070650800138');
      expect(p1.originalName, equals('Test Product 100g'));

      final p2 = ProductNameParser.parse('Test Product 100g SK60095186016');
      // 11 digits — should still strip
      expect(p2.originalName, equals('Test Product 100g'));
    });
  });

  // =========================================================================
  // B. SPAR cross-retailer matching — exact matches
  // =========================================================================
  group('SPAR cross-retailer exact matching', () {
    test('Albany bread matches across SPAR and PnP', () {
      final spar = ProductNameParser.parse(
          'Albany Superior Brown Bread 700g SK6009518602649');
      final pnp = ProductNameParser.parse('Albany Superior Brown Bread 700g');
      final confidence =
          ProductNameParser.computeConfidence(spar, pnp);
      expect(confidence, greaterThanOrEqualTo(0.80),
          reason: 'Same brand + product + size should be exact match');
    });

    test('Clover milk matches across SPAR and Checkers', () {
      final spar = ProductNameParser.parse(
          'Clover Full Cream Milk 2l SK6001008000123');
      final checkers =
          ProductNameParser.parse('Clover Full Cream Milk 2L');
      final confidence =
          ProductNameParser.computeConfidence(spar, checkers);
      expect(confidence, greaterThanOrEqualTo(0.80));
    });

    test('Nescafe matches across SPAR and Shoprite', () {
      final spar =
          ProductNameParser.parse('Nescafe Classic 200g SK6001108000456');
      final shoprite =
          ProductNameParser.parse('Nescafe Classic Instant Coffee 200g');
      final confidence =
          ProductNameParser.computeConfidence(spar, shoprite);
      expect(confidence, greaterThanOrEqualTo(0.55),
          reason: 'Same brand + size, slight name diff → similar');
    });

    test('Lucky Star pilchards matches exactly', () {
      final spar = ProductNameParser.parse(
          'Lucky Star Pilchards In Tomato Sauce 400g SK6009522300789');
      final pnp = ProductNameParser.parse(
          'Lucky Star Pilchards In Tomato Sauce 400g');
      final confidence =
          ProductNameParser.computeConfidence(spar, pnp);
      expect(confidence, greaterThanOrEqualTo(0.80));
    });

    test('Koo Baked Beans matches exactly', () {
      final spar = ProductNameParser.parse(
          'Koo Baked Beans In Tomato Sauce 410g SK6001015200456');
      final checkers = ProductNameParser.parse(
          'KOO Baked Beans in Tomato Sauce 410g');
      final confidence =
          ProductNameParser.computeConfidence(spar, checkers);
      expect(confidence, greaterThanOrEqualTo(0.80));
    });

    test('Cadbury Dairy Milk matches across retailers', () {
      final spar = ProductNameParser.parse(
          'Cadbury Dairy Milk Chocolate 150g SK6001065000123');
      final pnp =
          ProductNameParser.parse('Cadbury Dairy Milk Chocolate 150g');
      final confidence =
          ProductNameParser.computeConfidence(spar, pnp);
      expect(confidence, greaterThanOrEqualTo(0.80));
    });

    test('Spekko Rice matches across retailers', () {
      final spar = ProductNameParser.parse(
          'Spekko Long Grain Parboiled Rice 2kg SK6001108200789');
      final shoprite = ProductNameParser.parse(
          'Spekko Long Grain Parboiled Rice 2Kg');
      final confidence =
          ProductNameParser.computeConfidence(spar, shoprite);
      expect(confidence, greaterThanOrEqualTo(0.80));
    });

    test('Sunfoil Sunflower Oil matches across retailers', () {
      final spar = ProductNameParser.parse(
          'Sunfoil Sunflower Oil 2l SK6001240000456');
      final pnp =
          ProductNameParser.parse('Sunfoil Sunflower Oil 2L');
      final confidence =
          ProductNameParser.computeConfidence(spar, pnp);
      expect(confidence, greaterThanOrEqualTo(0.80));
    });

    test('Tastic Rice matches across retailers', () {
      final spar =
          ProductNameParser.parse('Tastic Rice 2kg SK6001108100234');
      final checkers =
          ProductNameParser.parse('Tastic Long Grain Rice 2kg');
      final confidence =
          ProductNameParser.computeConfidence(spar, checkers);
      expect(confidence, greaterThanOrEqualTo(0.55));
    });

    test('Omo Washing Powder matches across retailers', () {
      final spar = ProductNameParser.parse(
          'Omo Auto Washing Powder 2kg SK6001085000789');
      final shoprite =
          ProductNameParser.parse('Omo Auto Washing Powder 2kg');
      final confidence =
          ProductNameParser.computeConfidence(spar, shoprite);
      expect(confidence, greaterThanOrEqualTo(0.80));
    });
  });

  // =========================================================================
  // C. SPAR own-brand vs branded — similar matches
  // =========================================================================
  group('SPAR own-brand vs branded', () {
    test('SPAR milk vs Clover milk — similar (different brand, same product)',
        () {
      final spar = ProductNameParser.parse(
          'Spar Full Cream Milk 2l SK6001008731000');
      final clover =
          ProductNameParser.parse('Clover Full Cream Milk 2L');
      final confidence =
          ProductNameParser.computeConfidence(spar, clover);
      expect(confidence, greaterThanOrEqualTo(0.55),
          reason: 'Different brand, same product type + size → similar');
      expect(confidence, lessThan(0.80),
          reason: 'Different brand should not be exact');
    });

    test('SPAR white sugar vs Selati white sugar — similar', () {
      final spar = ProductNameParser.parse(
          'Spar White Sugar 2.5kg SK6001008732000');
      final selati =
          ProductNameParser.parse('Selati White Sugar 2.5kg');
      final confidence =
          ProductNameParser.computeConfidence(spar, selati);
      expect(confidence, greaterThanOrEqualTo(0.55));
    });

    test('SPAR brown bread vs Albany brown bread — similar', () {
      final spar = ProductNameParser.parse(
          'Spar Brown Bread 700g SK6001008733000');
      final albany =
          ProductNameParser.parse('Albany Superior Brown Bread 700g');
      final confidence =
          ProductNameParser.computeConfidence(spar, albany);
      expect(confidence, greaterThanOrEqualTo(0.55));
    });
  });

  // =========================================================================
  // D. SPAR negative tests — should NOT match
  // =========================================================================
  group('SPAR negative matching', () {
    test('Milk Chocolate should NOT match Full Cream Milk at exact/similar level', () {
      final choc = ProductNameParser.parse(
          'Aero Milk Chocolate 85g SK6009188000080');
      final milk =
          ProductNameParser.parse('Clover Full Cream Milk 2L');
      final confidence =
          ProductNameParser.computeConfidence(choc, milk);
      expect(confidence, lessThan(0.55),
          reason: 'Chocolate vs milk — shared word "milk" inflates score but should stay below similar threshold');
    });

    test('Buttermilk Rusks should NOT match Cultured Buttermilk', () {
      final rusks = ProductNameParser.parse(
          'Alettes Buttermilk Rusks 500g SK6009673800140');
      final buttermilk = ProductNameParser.parse(
          'Cultured Buttermilk Low Fat 500ml SK6001008731242');
      final confidence =
          ProductNameParser.computeConfidence(rusks, buttermilk);
      expect(confidence, lessThan(0.55),
          reason: 'Rusks vs liquid buttermilk = different categories');
    });

    test('Rice Vinegar should NOT match Spekko Rice', () {
      final vinegar = ProductNameParser.parse(
          'Amoy White Rice Vinegar 150ml SK4892773231202');
      final rice = ProductNameParser.parse(
          'Spekko Long Grain Parboiled Rice 2kg SK6001108200789');
      final confidence =
          ProductNameParser.computeConfidence(vinegar, rice);
      expect(confidence, lessThan(0.30));
    });

    test('Coconut Milk should NOT match Full Cream Milk', () {
      final coconut = ProductNameParser.parse(
          'A Taste Of Thai Lite Coconut Milk 400ml SK0070650800138');
      final milk =
          ProductNameParser.parse('Clover Full Cream Milk 2L');
      final confidence =
          ProductNameParser.computeConfidence(coconut, milk);
      expect(confidence, lessThan(0.55),
          reason: 'Coconut milk vs dairy milk = different product');
    });

    test('Canned Milk should NOT match Fresh Milk', () {
      final canned = ProductNameParser.parse(
          'Nestle Condensed Milk 385g SK6001068300123');
      final fresh =
          ProductNameParser.parse('Clover Full Cream Milk 2L');
      final confidence =
          ProductNameParser.computeConfidence(canned, fresh);
      expect(confidence, lessThan(0.55));
    });
  });

  // =========================================================================
  // E. SPAR size normalization
  // =========================================================================
  group('SPAR size normalization', () {
    test('2l vs 2L — case insensitive match', () {
      final spar =
          ProductNameParser.parse('Clover Full Cream Milk 2l SK600100800');
      final pnp =
          ProductNameParser.parse('Clover Full Cream Milk 2L');
      expect(spar.sizeValue, equals(pnp.sizeValue));
      expect(spar.sizeUnit, equals(pnp.sizeUnit));
    });

    test('1kg vs 1000g — equivalent sizes', () {
      final kg = ProductNameParser.parse('Bokomo Corn Flakes 1kg');
      final g = ProductNameParser.parse('Bokomo Corn Flakes 1000g');
      // Both parse correctly
      expect(kg.sizeValue, equals(1));
      expect(kg.sizeUnit, equals('kg'));
      expect(g.sizeValue, equals(1000));
      expect(g.sizeUnit, equals('g'));
    });

    test('multi-pack parsing: 6 X 200ml', () {
      final parsed = ProductNameParser.parse(
          'Steri Stumpie Chocolate 6 X 200ml SK600100800');
      expect(parsed.packCount, equals(6));
      expect(parsed.sizeValue, equals(200));
      expect(parsed.sizeUnit, equals('ml'));
      expect(parsed.totalSize, equals(1200));
    });

    test('SPAR product with size in different position', () {
      final parsed = ProductNameParser.parse(
          '12 Free Range Grade 1 Extra Large Eggs 59g Maggie Scratcher SK6009662390829');
      // Should extract some size info
      expect(parsed.originalName, isNot(contains('SK6009662390829')));
    });
  });

  // =========================================================================
  // F. SPAR confidence score ranges
  // =========================================================================
  group('SPAR confidence score ranges', () {
    test('identical product across retailers → exact (≥0.80)', () {
      final spar = ProductNameParser.parse(
          'All Gold Tomato Sauce 700ml SK6009522300456');
      final pnp =
          ProductNameParser.parse('All Gold Tomato Sauce 700ml');
      final confidence =
          ProductNameParser.computeConfidence(spar, pnp);
      expect(confidence, greaterThanOrEqualTo(0.80));
    });

    test('different brand same product → similar (≥0.50)', () {
      final spar =
          ProductNameParser.parse('Spar Tomato Sauce 700ml SK6001008734000');
      final allGold =
          ProductNameParser.parse('All Gold Tomato Sauce 700ml');
      final confidence =
          ProductNameParser.computeConfidence(spar, allGold);
      expect(confidence, greaterThanOrEqualTo(0.50),
          reason: 'Different brand, same product+size → at least 0.50');
    });

    test('completely different products → rejected (<0.30)', () {
      final bread = ProductNameParser.parse(
          'Albany Brown Bread 700g SK6001253010352');
      final milk =
          ProductNameParser.parse('Clover Full Cream Milk 2L');
      final confidence =
          ProductNameParser.computeConfidence(bread, milk);
      expect(confidence, lessThan(0.30));
    });

    test('similar product different size → penalized but recognizable', () {
      final small = ProductNameParser.parse(
          'Nescafe Classic 100g SK6001108000111');
      final large = ProductNameParser.parse(
          'Nescafe Classic 200g SK6001108000222');
      final confidence =
          ProductNameParser.computeConfidence(small, large);
      // Same brand + product but different size → penalized but still recognizable
      expect(confidence, greaterThanOrEqualTo(0.50));
      expect(confidence, lessThan(0.80),
          reason: 'Different size should not be exact');
    });
  });

  // =========================================================================
  // G. SPAR brand detection
  // =========================================================================
  group('SPAR brand detection', () {
    test('detects SPAR as own brand', () {
      final parsed = ProductNameParser.parse(
          'Spar Full Cream Milk 2l SK6001008731242');
      expect(parsed.brand, equals('spar'));
    });

    test('detects Lancewood brand', () {
      final parsed = ProductNameParser.parse(
          'Lancewood Cultured Full Cream Buttermilk 500ml SK6009617225220');
      expect(parsed.brand, equals('lancewood'));
    });

    test('detects Buttanutt brand', () {
      final parsed = ProductNameParser.parse(
          'Buttanutt 100% Almond Nut Butter 250g SK6009900424392');
      expect(parsed.brand, equals('buttanutt'));
    });

    test('detects standard brand from SPAR product', () {
      final parsed = ProductNameParser.parse(
          'Coca-Cola Original Taste 2l SK5449000000996');
      expect(parsed.brand, equals('coca-cola'));
      expect(parsed.sizeValue, equals(2));
      expect(parsed.sizeUnit, equals('l'));
    });

    test('detects All Gold brand from SPAR product', () {
      final parsed = ProductNameParser.parse(
          'All Gold Peeled And Diced Tomatoes 410g SK6009522309999');
      expect(parsed.brand, equals('all gold'));
    });
  });

  // =========================================================================
  // H. SPAR variant detection
  // =========================================================================
  group('SPAR variant detection', () {
    test('detects fat type variant', () {
      final parsed = ProductNameParser.parse(
          'Clover Low Fat Milk 2l SK6001008000111');
      expect(parsed.variantGroups['fat_type'], equals('low fat'));
    });

    test('detects sauce type variant', () {
      final parsed = ProductNameParser.parse(
          'Lucky Star Pilchards In Tomato Sauce 400g SK6009522300789');
      expect(parsed.variantGroups['sauce_type'], equals('in tomato sauce'));
    });

    test('detects grain variant', () {
      final parsed = ProductNameParser.parse(
          'Albany Superior Brown Bread 700g SK6009518602649');
      expect(parsed.variantGroups['grain'], equals('brown'));
    });

    test('full cream vs low fat are different variants', () {
      final full = ProductNameParser.parse(
          'Clover Full Cream Milk 2l SK6001008000111');
      final low = ProductNameParser.parse(
          'Clover Low Fat Milk 2l SK6001008000222');
      expect(full.variantGroups['fat_type'], equals('full cream'));
      expect(low.variantGroups['fat_type'], equals('low fat'));
      // Different variants should reduce confidence
      final confidence =
          ProductNameParser.computeConfidence(full, low);
      expect(confidence, lessThan(0.80),
          reason: 'Different fat variants should not be exact match');
    });
  });

  // ###########################################################################
  // SECTION 5: CROSS-RETAILER PRICE COMPARISON ACCURACY
  // ###########################################################################
  //
  // Simulates the real flow: a product from one retailer → compared across
  // all 5 grocery retailers. Validates that matches are correct products,
  // correct sizes, and the comparison makes sense.

  group('Cross-retailer price comparison accuracy', () {
    late SmartMatchingService matcher;
    setUp(() {
      matcher = SmartMatchingService(gemini: GeminiService(apiKey: 'test-key'));
    });

    test('Clover Full Cream Milk 2L → matches correctly across 5 retailers',
        () {
      final source = _product('Clover Full Cream Milk 2L', price: 36.99);

      final candidatesByRetailer = <String, List<LiveProduct>>{
        'Pick n Pay': [
          _product('Clover Full Cream Milk 2L', price: 35.99),
          _product('Clover Low Fat Milk 2L', price: 34.99),
          _product('PnP Full Cream Milk 2L', price: 29.99),
          _product('Cadbury Dairy Milk Chocolate 150g', price: 39.99),
        ],
        'Checkers': [
          _product('Clover Full Cream Milk 2L', price: 37.49),
          _product('Parmalat Full Cream Milk 2L', price: 34.99),
          _product('Clover Chocolate Milk 1L', price: 25.99),
        ],
        'Shoprite': [
          _product('Clover Full Cream Milk 2L', price: 36.49),
          _product('Clover Full Cream Milk 1L', price: 19.99),
          _product('Danone Yoghurt 1L', price: 42.99),
        ],
        'Woolworths': [
          _product('Woolworths Full Cream Milk 2L', price: 38.99),
          _product('Clover Full Cream Milk 2L', price: 37.99),
        ],
        'SPAR': [
          _product('Clover Full Cream Milk 2l SK6001008000123', price: 36.79),
          _product('Spar Full Cream Milk 2l SK6001008731000', price: 31.99),
          _product('Aero Milk Chocolate 85g SK6009188000080', price: 28.99),
        ],
      };

      final result = matcher.findMatchesAlgorithm(
        sourceProduct: source,
        candidatesByRetailer: candidatesByRetailer,
      );

      // Each retailer should have a best match
      for (final retailer in candidatesByRetailer.keys) {
        final best = result.bestMatchPerRetailer[retailer];
        expect(best, isNotNull, reason: '$retailer should find a match');

        // Match should contain "milk" and "2l" — not chocolate or yoghurt
        final matchName = best!.name.toLowerCase();
        expect(matchName, contains('milk'),
            reason: '$retailer match "$matchName" should be a milk product');
        expect(matchName, isNot(contains('chocolate')),
            reason: '$retailer should not match chocolate');
        expect(matchName, isNot(contains('yoghurt')),
            reason: '$retailer should not match yoghurt');

        // Confidence should be at least similar-level
        expect(best.confidenceScore, greaterThanOrEqualTo(0.55),
            reason: '$retailer confidence ${best.confidenceScore} too low');
      }

      // PnP best match should be exact "Clover Full Cream Milk 2L"
      final pnpBest = result.bestMatchPerRetailer['Pick n Pay']!;
      expect(pnpBest.name, equals('Clover Full Cream Milk 2L'));
      expect(pnpBest.matchType, equals(MatchType.exact));
    });

    test('Albany Brown Bread 700g → matches bread not chocolate', () {
      final source =
          _product('Albany Superior Brown Bread 700g', price: 22.99);

      final candidatesByRetailer = <String, List<LiveProduct>>{
        'SPAR': [
          _product(
              'Albany Best Of Both Genius Speciality Bread 700g SK6009518602649',
              price: 20.99),
          _product('Albany Superior Brown Bread 700g SK6001253010352',
              price: 23.99),
          _product('Cadbury Whole Nut 150g SK6001065000456', price: 44.99),
        ],
        'Checkers': [
          _product('Albany Superior Brown Bread 700g', price: 21.99),
          _product('Sasko Premium Brown Bread 700g', price: 19.99),
        ],
      };

      final result = matcher.findMatchesAlgorithm(
        sourceProduct: source,
        candidatesByRetailer: candidatesByRetailer,
      );

      // SPAR should match the correct Albany bread
      final sparBest = result.bestMatchPerRetailer['SPAR']!;
      expect(sparBest.name.toLowerCase(), contains('albany'));
      expect(sparBest.name.toLowerCase(), contains('brown'));
      expect(sparBest.name.toLowerCase(), contains('bread'));
      expect(sparBest.matchType, equals(MatchType.exact));

      // Checkers should also match bread
      final checkersBest = result.bestMatchPerRetailer['Checkers']!;
      expect(checkersBest.name.toLowerCase(), contains('bread'));
      expect(checkersBest.name.toLowerCase(), contains('700g'));
    });

    test('Lucky Star Pilchards 400g → matches canned fish not random items',
        () {
      final source = _product('Lucky Star Pilchards In Tomato Sauce 400g',
          price: 24.99);

      final candidatesByRetailer = <String, List<LiveProduct>>{
        'SPAR': [
          _product(
              'Lucky Star Pilchards In Tomato Sauce 400g SK6009522300789',
              price: 25.49),
          _product('All Gold Tomato Sauce 700ml SK6009522309633',
              price: 42.99),
          _product('Lucky Star Pilchards In Chilli Sauce 400g SK6009522300456',
              price: 26.99),
        ],
        'Pick n Pay': [
          _product('Lucky Star Pilchards In Tomato Sauce 400g', price: 23.99),
          _product('John West Sardines In Tomato Sauce 120g', price: 31.99),
        ],
      };

      final result = matcher.findMatchesAlgorithm(
        sourceProduct: source,
        candidatesByRetailer: candidatesByRetailer,
      );

      // SPAR best should be same product (tomato sauce variant, not chilli)
      final sparBest = result.bestMatchPerRetailer['SPAR']!;
      expect(sparBest.name.toLowerCase(), contains('pilchards'));
      expect(sparBest.name.toLowerCase(), contains('tomato'));
      expect(sparBest.confidenceScore, greaterThanOrEqualTo(0.80));

      // Should NOT match tomato sauce (bottle) — different product entirely
      expect(sparBest.name.toLowerCase(), isNot(contains('700ml')));
    });

    test('Coca-Cola 2L → matches same drink not similar-named products', () {
      final source =
          _product('Coca-Cola Original Taste 2L', price: 22.99);

      final candidatesByRetailer = <String, List<LiveProduct>>{
        'SPAR': [
          _product('Coca-Cola Original Taste 2l SK5449000000996',
              price: 23.49),
          _product('Coca-Cola Zero Sugar 2l SK5449000131805', price: 23.49),
          _product('Fanta Orange 2l SK5449000011527', price: 21.49),
        ],
        'Shoprite': [
          _product('Coca-Cola Original Taste 2L', price: 21.99),
          _product('Pepsi Max 2L', price: 19.99),
        ],
      };

      final result = matcher.findMatchesAlgorithm(
        sourceProduct: source,
        candidatesByRetailer: candidatesByRetailer,
      );

      // SPAR should match "Original Taste", not "Zero Sugar"
      final sparBest = result.bestMatchPerRetailer['SPAR']!;
      expect(sparBest.name.toLowerCase(), contains('original'));
      expect(sparBest.name.toLowerCase(), isNot(contains('zero')));
      expect(sparBest.confidenceScore, greaterThanOrEqualTo(0.80));
    });

    test('price differences calculated correctly', () {
      final source = _product('Test Product 500g', price: 30.00);

      final candidatesByRetailer = <String, List<LiveProduct>>{
        'SPAR': [
          _product('Test Product 500g SK6001000000001', price: 25.00),
        ],
        'Pick n Pay': [
          _product('Test Product 500g', price: 35.00),
        ],
      };

      final result = matcher.findMatchesAlgorithm(
        sourceProduct: source,
        candidatesByRetailer: candidatesByRetailer,
      );

      final sparMatch = result.bestMatchPerRetailer['SPAR']!;
      expect(sparMatch.priceDifference, closeTo(-5.00, 0.01),
          reason: 'SPAR is R5 cheaper');
      expect(sparMatch.isCheaper, isTrue);

      final pnpMatch = result.bestMatchPerRetailer['Pick n Pay']!;
      expect(pnpMatch.priceDifference, closeTo(5.00, 0.01),
          reason: 'PnP is R5 more expensive');
      expect(pnpMatch.isCheaper, isFalse);
    });

    test('size mismatch penalizes confidence', () {
      final source = _product('Nescafe Classic 200g', price: 89.99);

      final candidatesByRetailer = <String, List<LiveProduct>>{
        'SPAR': [
          _product('Nescafe Classic 50g SK6001108000111', price: 32.99),
          _product('Nescafe Classic 200g SK6001108000222', price: 91.99),
        ],
      };

      final result = matcher.findMatchesAlgorithm(
        sourceProduct: source,
        candidatesByRetailer: candidatesByRetailer,
      );

      // Should prefer the 200g (same size) over the 50g
      final sparBest = result.bestMatchPerRetailer['SPAR']!;
      expect(sparBest.name, contains('200g'));
    });
  });

  // ###########################################################################
  // SECTION 6: RECIPE INGREDIENT MATCHING ACCURACY
  // ###########################################################################

  group('Recipe ingredient matching accuracy across retailers', () {
    late SmartMatchingService matcher;
    setUp(() {
      matcher = SmartMatchingService(gemini: GeminiService(apiKey: 'test-key'));
    });

    test('butter → matches butter products, not buttermilk/butterscotch',
        () async {
      final hint = IngredientLookup.resolve('butter');
      expect(hint, isNotNull, reason: 'butter should have a lookup hint');

      // Simulate candidates from SPAR
      final sparCandidates = [
        _product('Clover Butter 500g SK6001008000111', price: 54.99),
        _product('Cultured Buttermilk 500ml SK6001008731242', price: 16.99),
        _product('Butterscotch Pudding 100g SK6009000000111', price: 12.99),
        _product('Buttanutt Almond Butter 250g SK6009900424392', price: 82.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'butter',
        candidates: sparCandidates,
        hint: hint,
      );

      expect(result, isNotNull);
      expect(result!.name.toLowerCase(), contains('butter'));
      expect(result.name.toLowerCase(), isNot(contains('buttermilk')));
      expect(result.name.toLowerCase(), isNot(contains('butterscotch')));
    });

    test('large eggs → matches egg products, not chocolate Mini Eggs',
        () async {
      final hint = IngredientLookup.resolve('eggs');

      final candidates = [
        _product('Large Eggs 6 Pack SK6009662390001', price: 34.99),
        _product('Extra Large Free Range Eggs 6 SK6009662390002',
            price: 42.99),
        _product('Cadbury Mini Eggs 125g SK6001065000789', price: 32.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'large eggs',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull);
      final name = result!.name.toLowerCase();
      expect(name, contains('eggs'));
      expect(name, isNot(contains('cadbury')));
    });

    test('rice → matches rice grains, not rice vinegar or rice cakes',
        () async {
      final hint = IngredientLookup.resolve('rice');

      final candidates = [
        _product('Spekko Long Grain Parboiled Rice 2kg SK6001108200789',
            price: 39.99),
        _product('Amoy White Rice Vinegar 150ml SK4892773231202',
            price: 52.00),
        _product('Rice Cakes Plain 100g SK6001000000444', price: 28.99),
        _product('Tastic Rice 2kg SK6001108100234', price: 42.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'rice',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull);
      final name = result!.name.toLowerCase();
      expect(name, anyOf(contains('spekko'), contains('tastic')));
      expect(name, isNot(contains('vinegar')));
      expect(name, isNot(contains('cake')));
    });

    test('full cream milk → matches milk, not chocolate milk or coconut milk',
        () async {
      final hint = IngredientLookup.resolve('milk');

      final candidates = [
        _product('Clover Full Cream Milk 2l SK6001008000123', price: 36.79),
        _product('Aero Milk Chocolate 85g SK6009188000080', price: 28.99),
        _product('A Taste Of Thai Lite Coconut Milk 400ml SK0070650800138',
            price: 36.99),
        _product('Nestle Condensed Milk 385g SK6001068300123', price: 29.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'full cream milk',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull);
      final name = result!.name.toLowerCase();
      expect(name, contains('full cream milk'));
      expect(name, isNot(contains('chocolate')));
      expect(name, isNot(contains('coconut')));
    });

    test('onion → matches fresh onions, not onion rings or onion soup',
        () async {
      final hint = IngredientLookup.resolve('onion');

      final candidates = [
        _product('Onions 1kg SK6001000000555', price: 19.99),
        _product('Knorr Onion Soup 50g SK6001087300111', price: 14.99),
        _product('Frozen Onion Rings 500g SK6001000000666', price: 42.99),
        _product('Spring Onions Bunch SK6001000000777', price: 12.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'onion',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull);
      final name = result!.name.toLowerCase();
      expect(name, anyOf(contains('onions 1kg'), contains('spring onion')));
      expect(name, isNot(contains('soup')));
      expect(name, isNot(contains('rings')));
    });

    test('sugar → matches sugar product, not sugar-free sweets', () async {
      final hint = IngredientLookup.resolve('sugar');

      final candidates = [
        _product('Spar White Sugar 2.5kg SK6001008732000', price: 44.99),
        _product('Sugar Free Sweets 100g SK6001000000888', price: 29.99),
        _product('Selati White Sugar 1kg SK6001000001000', price: 19.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'sugar',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull);
      final name = result!.name.toLowerCase();
      expect(name, contains('sugar'));
      expect(name, isNot(contains('free')));
    });

    test('tinned tomatoes → matches canned tomato products', () async {
      final hint = IngredientLookup.resolve('tinned tomatoes');

      final candidates = [
        _product('All Gold Peeled And Diced Tomatoes 410g SK6009522309999',
            price: 18.99),
        _product('All Gold Tomato Sauce 700ml SK6009522309633', price: 42.99),
        _product('Koo Chopped Tomatoes 410g SK6001015000111', price: 16.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'tinned tomatoes',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull);
      final name = result!.name.toLowerCase();
      expect(name, contains('tomato'));
    });

    test('chicken breast → matches poultry, not chicken soup', () async {
      final hint = IngredientLookup.resolve('chicken');

      final candidates = [
        _product('Fresh Chicken Breast Fillets 500g SK6001000002222',
            price: 69.99),
        _product('Knorr Cream Of Chicken Soup 400g SK5012427143104',
            price: 48.99),
        _product('County Fair Frozen Chicken Portions 2kg SK6001000002333',
            price: 89.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'chicken breast',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull);
      final name = result!.name.toLowerCase();
      expect(name, contains('chicken'));
      expect(name, isNot(contains('soup')));
    });

    test('olive oil → matches olive oil, not sunflower oil or cooking spray',
        () async {
      final hint = IngredientLookup.resolve('olive oil');

      final candidates = [
        _product('Star Extra Virgin Olive Oil 500ml SK6001000003333',
            price: 79.99),
        _product('Sunfoil Sunflower Oil 2L SK6001240000456', price: 59.99),
        _product('Spray And Cook Original 300ml SK6001000003444',
            price: 49.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'olive oil',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull);
      expect(result!.name.toLowerCase(), contains('olive oil'));
    });

    test('garlic → matches fresh garlic, not garlic bread or garlic sauce',
        () async {
      final hint = IngredientLookup.resolve('garlic');

      final candidates = [
        _product('Crushed Garlic 200g SK6001000004444', price: 32.99),
        _product('Garlic Bread 350g SK6001000004555', price: 24.99),
        _product('Ina Paarman Garlic And Pepper Sauce 300ml SK6001000004666',
            price: 36.99),
        _product('Fresh Garlic 150g SK6001000004777', price: 14.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'garlic',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull);
      final name = result!.name.toLowerCase();
      expect(name, contains('garlic'));
      expect(name, isNot(contains('bread')));
      expect(name, isNot(contains('sauce')));
    });
  });

  // ###########################################################################
  // SECTION 7: INDIAN RECIPE INGREDIENT MATCHING
  // ###########################################################################

  group('Indian recipe ingredient matching', () {
    late SmartMatchingService matcher;
    setUp(() {
      matcher = SmartMatchingService(gemini: GeminiService(apiKey: 'test-key'));
    });

    test('basmati rice → matches Tastic Basmati, not white rice or rice vinegar',
        () async {
      final hint = IngredientLookup.resolve('basmati rice');

      final candidates = [
        _product('Tastic Basmati Rice 1kg SK6001108200789', price: 44.99),
        _product('Tastic Long Grain White Rice 2kg SK6001108200111', price: 39.99),
        _product('PnP Rice Vinegar 250ml', price: 29.99),
        _product('Woolworths Basmati Rice 500g', price: 32.99),
        _product('Spekko Basmati Rice 1kg', price: 42.99),
        _product('Spar Long Grain Parboiled Rice 2kg SK6001108200333',
            price: 34.99),
        _product('Checkers Housebrand White Rice 5kg', price: 74.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'basmati rice',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull, reason: 'Should find a basmati rice match');
      final name = result!.name.toLowerCase();
      expect(name, contains('basmati'),
          reason: 'Should match basmati rice specifically');
      expect(name, isNot(contains('vinegar')),
          reason: 'Rice vinegar is a condiment, not a grain');
    });

    test('turmeric → matches ground turmeric spice, not supplements', () async {
      final hint = IngredientLookup.resolve('turmeric');

      final candidates = [
        _product('Robertsons Ground Turmeric 100ml SK6001000005111',
            price: 24.99),
        _product('Woolworths Turmeric Supplement 60 Capsules', price: 149.99),
        _product('PnP Ground Turmeric 50g', price: 18.99),
        _product('Checkers Housebrand Turmeric 100ml', price: 16.99),
        _product('Spar Turmeric Spice 50g SK6001000005222', price: 19.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'turmeric',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull, reason: 'Should find a turmeric match');
      final name = result!.name.toLowerCase();
      expect(name, contains('turmeric'),
          reason: 'Should match turmeric spice product');
      expect(name, isNot(contains('supplement')),
          reason: 'Supplements are not cooking ingredients');
      expect(name, isNot(contains('capsule')),
          reason: 'Capsules are not cooking ingredients');
    });

    test('garam masala → matches spice blend', () async {
      final hint = IngredientLookup.resolve('garam masala');

      final candidates = [
        _product('Robertsons Garam Masala 100ml SK6001000005333', price: 32.99),
        _product('PnP Garam Masala Spice 50g', price: 24.99),
        _product('Woolworths Garam Masala 45g', price: 34.99),
        _product('Robertsons Chicken Spice 100ml SK6001000005444', price: 28.99),
        _product('Checkers Curry Powder 100g', price: 19.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'garam masala',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull, reason: 'Should find a garam masala match');
      final name = result!.name.toLowerCase();
      expect(name, contains('garam masala'),
          reason: 'Should specifically match garam masala blend');
      expect(name, isNot(contains('chicken spice')),
          reason: 'Chicken spice is a different blend');
      expect(name, isNot(contains('curry powder')),
          reason: 'Curry powder is a different spice');
    });

    test('coriander → matches fresh or ground coriander, not coriander chips',
        () async {
      final hint = IngredientLookup.resolve('coriander');

      final candidates = [
        _product('Fresh Coriander Bunch SK6001000005555', price: 9.99),
        _product('Robertsons Ground Coriander 100ml SK6001000005666',
            price: 26.99),
        _product('Simba Coriander And Lime Chips 125g', price: 19.99),
        _product('Woolworths Fresh Coriander 30g', price: 14.99),
        _product('PnP Ground Coriander 50g', price: 22.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'coriander',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull, reason: 'Should find a coriander match');
      final name = result!.name.toLowerCase();
      expect(name, contains('coriander'),
          reason: 'Should match coriander product');
      expect(name, isNot(contains('chips')),
          reason: 'Coriander-flavoured chips are not a cooking ingredient');
      expect(name, isNot(contains('lime')),
          reason: 'Flavoured chips are not a cooking ingredient');
    });

    test('chickpeas → matches canned chickpeas, not chickpea flour or hummus',
        () async {
      final hint = IngredientLookup.resolve('chickpeas');

      final candidates = [
        _product('Koo Chickpeas In Brine 410g SK6001015000222', price: 18.99),
        _product('PnP Chickpea Flour 500g', price: 34.99),
        _product('Woolworths Hummus Classic 200g', price: 39.99),
        _product('Checkers Canned Chickpeas 400g', price: 16.99),
        _product('Spar Chickpeas 410g SK6001015000333', price: 17.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'chickpeas',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull, reason: 'Should find a chickpeas match');
      final name = result!.name.toLowerCase();
      expect(name, contains('chickpea'),
          reason: 'Should match a chickpea product');
      expect(name, isNot(contains('flour')),
          reason: 'Chickpea flour is a different ingredient');
      expect(name, isNot(contains('hummus')),
          reason: 'Hummus is a prepared dip, not raw chickpeas');
    });

    test('yoghurt → matches plain/natural yoghurt, not drinks or frozen',
        () async {
      final hint = IngredientLookup.resolve('yoghurt');

      final candidates = [
        _product('Clover Plain Double Cream Yoghurt 500ml SK6001008000444',
            price: 29.99),
        _product('Danone Drinking Yoghurt Strawberry 1L', price: 34.99),
        _product('Woolworths Frozen Yoghurt Vanilla 1L', price: 59.99),
        _product('PnP Natural Yoghurt 500g', price: 24.99),
        _product('Spar Low Fat Natural Yoghurt 500g SK6001008000555',
            price: 22.99),
        _product('Checkers Plain Yoghurt 1kg', price: 44.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'yoghurt',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull, reason: 'Should find a yoghurt match');
      final name = result!.name.toLowerCase();
      expect(name, contains('yoghurt'),
          reason: 'Should match yoghurt product');
      expect(name, isNot(contains('drinking')),
          reason: 'Yoghurt drinks are not plain yoghurt');
      expect(name, isNot(contains('frozen')),
          reason: 'Frozen yoghurt is a dessert, not cooking yoghurt');
    });

    test('lentils → matches dried or canned lentils, not lentil soup',
        () async {
      final hint = IngredientLookup.resolve('lentils');

      final candidates = [
        _product('PnP Brown Lentils 500g', price: 24.99),
        _product('Woolworths Red Lentils 500g', price: 29.99),
        _product('Knorr Lentil Soup 400g SK6001087300222', price: 48.99),
        _product('Spar Green Lentils 500g SK6001000006111', price: 26.99),
        _product('Checkers Canned Lentils 400g', price: 18.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'lentils',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull, reason: 'Should find a lentils match');
      final name = result!.name.toLowerCase();
      expect(name, contains('lentil'),
          reason: 'Should match a lentil product');
      expect(name, isNot(contains('soup')),
          reason: 'Lentil soup is a prepared product, not raw lentils');
    });

    test('ginger → matches fresh or crushed ginger, not ginger beer', () async {
      final hint = IngredientLookup.resolve('ginger');

      final candidates = [
        _product('Fresh Ginger Root 200g SK6001000006222', price: 18.99),
        _product('Woolworths Crushed Ginger 200g', price: 34.99),
        _product('Stoney Ginger Beer 2L', price: 24.99),
        _product('PnP Ground Ginger 50g', price: 22.99),
        _product('Spar Fresh Ginger 250g SK6001000006333', price: 21.99),
        _product('Fitch And Leedes Ginger Ale 1L', price: 29.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'ginger',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull, reason: 'Should find a ginger match');
      final name = result!.name.toLowerCase();
      expect(name, contains('ginger'),
          reason: 'Should match a ginger product');
      expect(name, isNot(contains('beer')),
          reason: 'Ginger beer is a beverage, not a cooking ingredient');
      expect(name, isNot(contains('ale')),
          reason: 'Ginger ale is a beverage, not a cooking ingredient');
    });

    test('chilli → matches fresh chillies or chilli flakes, not chilli sauce',
        () async {
      final hint = IngredientLookup.resolve('chilli');

      final candidates = [
        _product('Fresh Red Chillies 100g SK6001000006444', price: 14.99),
        _product('Robertsons Chilli Flakes 12g SK6001000006555', price: 18.99),
        _product('Nandos Peri-Peri Chilli Sauce 250ml', price: 42.99),
        _product('Woolworths Dried Chilli Flakes 25g', price: 24.99),
        _product('PnP Fresh Chillies Per 100g', price: 12.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'chilli',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull, reason: 'Should find a chilli match');
      final name = result!.name.toLowerCase();
      expect(name, contains('chilli'),
          reason: 'Should match a chilli product');
      expect(name, isNot(contains('sauce')),
          reason: 'Chilli sauce is a condiment, not raw chillies');
      expect(name, isNot(contains('nando')),
          reason: 'Branded sauce is not a raw ingredient');
    });

    test('coconut milk → matches canned coconut milk, not coconut water or cow milk',
        () async {
      final hint = IngredientLookup.resolve('coconut milk');

      final candidates = [
        _product('Aroy-D Coconut Milk 400ml SK6016017000111', price: 34.99),
        _product('Liqui Fruit Coconut Water 330ml', price: 19.99),
        _product('Clover Full Cream Milk 2L', price: 36.99),
        _product('PnP Coconut Milk 400ml', price: 28.99),
        _product('Woolworths Coconut Milk 400ml', price: 36.99),
        _product('Spar Coconut Cream 400ml SK6016017000222', price: 32.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'coconut milk',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull, reason: 'Should find a coconut milk match');
      final name = result!.name.toLowerCase();
      expect(name, contains('coconut'),
          reason: 'Should match a coconut product');
      expect(name, isNot(contains('water')),
          reason: 'Coconut water is a different product');
      expect(name, isNot(contains('clover')),
          reason: 'Should not match cow milk');
    });
  });

  // ###########################################################################
  // SECTION 8: GREEK RECIPE INGREDIENT MATCHING
  // ###########################################################################

  group('Greek recipe ingredient matching', () {
    late SmartMatchingService matcher;
    setUp(() {
      matcher = SmartMatchingService(gemini: GeminiService(apiKey: 'test-key'));
    });

    test('feta cheese → matches feta, not cheddar or cream cheese', () async {
      final hint = IngredientLookup.resolve('feta cheese');

      final candidates = [
        _product('Clover Feta Cheese Plain 400g SK6001008000666', price: 64.99),
        _product('Lancewood Cheddar Cheese 900g', price: 99.99),
        _product('Philadelphia Cream Cheese 230g', price: 49.99),
        _product('Woolworths Danish Feta 200g', price: 44.99),
        _product('PnP Feta Cheese In Brine 400g', price: 59.99),
        _product('Spar Feta Crumbled 200g SK6001008000777', price: 39.99),
        _product('Checkers Feta 400g', price: 57.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'feta cheese',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull, reason: 'Should find a feta cheese match');
      final name = result!.name.toLowerCase();
      expect(name, contains('feta'),
          reason: 'Should match feta specifically');
      expect(name, isNot(contains('cheddar')),
          reason: 'Cheddar is a different cheese');
      expect(name, isNot(contains('cream cheese')),
          reason: 'Cream cheese is a different product');
    });

    test('olive oil → matches extra virgin olive oil, not sunflower oil',
        () async {
      final hint = IngredientLookup.resolve('olive oil');

      final candidates = [
        _product('Star Extra Virgin Olive Oil 500ml SK6001000007111',
            price: 79.99),
        _product('Sunfoil Sunflower Oil 2L', price: 59.99),
        _product('PnP Extra Virgin Olive Oil 500ml', price: 74.99),
        _product('Woolworths Extra Virgin Olive Oil 250ml', price: 49.99),
        _product('Spar Olive Oil Extra Virgin 500ml SK6001000007222',
            price: 72.99),
        _product('Checkers Olive Oil 1L', price: 129.99),
        _product('Spray And Cook Olive Oil 300ml', price: 49.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'olive oil',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull, reason: 'Should find an olive oil match');
      final name = result!.name.toLowerCase();
      expect(name, contains('olive oil'),
          reason: 'Should match olive oil product');
      expect(name, isNot(contains('sunflower')),
          reason: 'Sunflower oil is a different oil');
    });

    test('pita bread → matches pita/pitta bread, not regular bread', () async {
      final hint = IngredientLookup.resolve('pita bread');

      final candidates = [
        _product('Woolworths Pita Breads 6 Pack', price: 29.99),
        _product('Albany Superior White Bread 700g', price: 22.99),
        _product('PnP Pitta Bread 6s', price: 24.99),
        _product('Spar Pita Bread 6 Pack SK6001000007333', price: 26.99),
        _product('Checkers Pitta Pockets 6s', price: 27.99),
        _product('Sasko Premium Brown Bread 700g', price: 19.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'pita bread',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull, reason: 'Should find a pita bread match');
      final name = result!.name.toLowerCase();
      expect(name, anyOf(contains('pita'), contains('pitta')),
          reason: 'Should match pita/pitta bread');
      expect(name, isNot(contains('albany')),
          reason: 'Regular bread is not pita bread');
      expect(name, isNot(contains('sasko')),
          reason: 'Regular bread is not pita bread');
    });

    test('lemon → matches fresh lemons, not lemon juice or lemon drinks',
        () async {
      final hint = IngredientLookup.resolve('lemon');

      final candidates = [
        _product('Lemons Per Kg SK6001000007444', price: 29.99),
        _product('Woolworths Lemons 4 Pack', price: 19.99),
        _product('PnP 100% Lemon Juice 250ml', price: 24.99),
        _product('Schweppes Sparkling Lemon 2L', price: 22.99),
        _product('Spar Fresh Lemons 1kg SK6001000007555', price: 32.99),
        _product('Checkers Lemons Net 1kg', price: 27.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'lemon',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull, reason: 'Should find a lemon match');
      final name = result!.name.toLowerCase();
      expect(name, contains('lemon'),
          reason: 'Should match a lemon product');
      expect(name, isNot(contains('juice')),
          reason: 'Lemon juice is a processed product');
      expect(name, isNot(contains('schweppes')),
          reason: 'Lemon drinks are not fresh lemons');
      expect(name, isNot(contains('sparkling')),
          reason: 'Sparkling drinks are not fresh lemons');
    });

    test('cucumber → matches fresh cucumber, not pickled gherkins', () async {
      final hint = IngredientLookup.resolve('cucumber');

      final candidates = [
        _product('English Cucumber Each SK6001000007666', price: 14.99),
        _product('Koo Pickled Gherkins 375ml', price: 34.99),
        _product('Woolworths Fresh Cucumber Each', price: 12.99),
        _product('PnP Cucumber Each', price: 11.99),
        _product('Spar Cucumber SK6001000007777', price: 13.99),
        _product('Wellington Pickled Cucumbers 380g', price: 29.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'cucumber',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull, reason: 'Should find a cucumber match');
      final name = result!.name.toLowerCase();
      expect(name, contains('cucumber'),
          reason: 'Should match a cucumber product');
      expect(name, isNot(contains('pickled')),
          reason: 'Pickled cucumbers/gherkins are not fresh cucumber');
      expect(name, isNot(contains('gherkin')),
          reason: 'Gherkins are not fresh cucumber');
    });

    test('lamb → matches lamb cuts, not lamb-flavoured stock', () async {
      final hint = IngredientLookup.resolve('lamb');

      final candidates = [
        _product('Lamb Leg Per Kg SK6001000008111', price: 169.99),
        _product('Knorr Lamb Flavoured Stock Cubes 24s', price: 34.99),
        _product('Woolworths Lamb Loin Chops Per Kg', price: 189.99),
        _product('PnP Lamb Shoulder Per Kg', price: 149.99),
        _product('Spar Lamb Chops Per Kg SK6001000008222', price: 159.99),
        _product('Checkers Lamb Rib Chops Per Kg', price: 154.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'lamb',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull, reason: 'Should find a lamb match');
      final name = result!.name.toLowerCase();
      expect(name, contains('lamb'),
          reason: 'Should match a lamb product');
      expect(name, isNot(contains('stock')),
          reason: 'Lamb stock cubes are not lamb meat');
      expect(name, isNot(contains('flavour')),
          reason: 'Flavoured products are not actual lamb');
    });
  });

  // ###########################################################################
  // SECTION 9: SA CLASSIC RECIPE INGREDIENT MATCHING
  // ###########################################################################

  group('SA classic recipe ingredient matching', () {
    late SmartMatchingService matcher;
    setUp(() {
      matcher = SmartMatchingService(gemini: GeminiService(apiKey: 'test-key'));
    });

    test('maize meal → matches Iwisa/White Star, not corn flakes', () async {
      final hint = IngredientLookup.resolve('maize meal');

      final candidates = [
        _product('Iwisa Maize Meal 5kg SK6001011000111', price: 64.99),
        _product('White Star Super Maize Meal 2.5kg SK6001011000222',
            price: 39.99),
        _product('Kelloggs Corn Flakes 500g', price: 54.99),
        _product('PnP Super Maize Meal 5kg', price: 59.99),
        _product('Woolworths Organic Corn Kernels 410g', price: 29.99),
        _product('Spar Maize Meal 2.5kg SK6001011000333', price: 37.99),
        _product('Checkers Housebrand Maize Meal 5kg', price: 56.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'maize meal',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull, reason: 'Should find a maize meal match');
      final name = result!.name.toLowerCase();
      expect(name, contains('maize meal'),
          reason: 'Should match maize meal product');
      expect(name, isNot(contains('corn flakes')),
          reason: 'Corn flakes is a cereal, not maize meal');
      expect(name, isNot(contains('corn kernels')),
          reason: 'Corn kernels are not maize meal');
    });

    test('beef mince → matches minced beef, not beef stock or biltong',
        () async {
      final hint = IngredientLookup.resolve('beef mince');

      final candidates = [
        _product('Beef Mince Per Kg SK6001000009111', price: 99.99),
        _product('Knorr Beef Stock Cubes 24s', price: 34.99),
        _product('Safari Beef Biltong 80g', price: 49.99),
        _product('Woolworths Lean Beef Mince Per Kg', price: 119.99),
        _product('PnP Beef Mince 500g', price: 54.99),
        _product('Spar Premium Beef Mince Per Kg SK6001000009222',
            price: 109.99),
        _product('Checkers Beef Mince Per Kg', price: 94.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'beef mince',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull, reason: 'Should find a beef mince match');
      final name = result!.name.toLowerCase();
      expect(name, contains('mince'),
          reason: 'Should match a mince product');
      expect(name, isNot(contains('stock')),
          reason: 'Beef stock is not beef mince');
      expect(name, isNot(contains('biltong')),
          reason: 'Biltong is dried meat, not mince');
    });

    test('tomato and onion mix → matches Koo/All Gold tinned mix', () async {
      final hint = IngredientLookup.resolve('tomato and onion mix');

      final candidates = [
        _product('Koo Tomato And Onion Mix 410g SK6001015000444', price: 18.99),
        _product('All Gold Tomato And Onion Mix 410g SK6009522300111',
            price: 19.99),
        _product('Fresh Tomatoes Per Kg', price: 24.99),
        _product('PnP Tomato And Onion Smoor 410g', price: 16.99),
        _product('Woolworths Tomato And Onion Relish 250ml', price: 32.99),
        _product('Spar Tomato And Onion Mix 410g SK6001015000555', price: 17.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'tomato and onion mix',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull,
          reason: 'Should find a tomato and onion mix match');
      final name = result!.name.toLowerCase();
      expect(name, contains('tomato'),
          reason: 'Should contain tomato');
      expect(name, contains('onion'),
          reason: 'Should contain onion');
      expect(name, isNot(contains('fresh tomatoes')),
          reason: 'Fresh tomatoes are not a prepared mix');
    });

    test('chutney → matches Mrs Balls chutney, not tomato sauce', () async {
      final hint = IngredientLookup.resolve('chutney');

      final candidates = [
        _product('Mrs Balls Original Chutney 470g SK6001000010111',
            price: 36.99),
        _product('All Gold Tomato Sauce 700ml SK6009522309633', price: 42.99),
        _product('Woolworths Fruit Chutney 250ml', price: 34.99),
        _product('PnP Peach Chutney 470g', price: 32.99),
        _product('Spar Fruit Chutney 470g SK6001000010222', price: 29.99),
        _product('Checkers Mrs Balls Chutney 470g', price: 35.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'chutney',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull, reason: 'Should find a chutney match');
      final name = result!.name.toLowerCase();
      expect(name, contains('chutney'),
          reason: 'Should match a chutney product');
      expect(name, isNot(contains('tomato sauce')),
          reason: 'Tomato sauce is not chutney');
    });

    test('boerewors → matches fresh boerewors', () async {
      final hint = IngredientLookup.resolve('boerewors');

      final candidates = [
        _product('Traditional Boerewors Per Kg SK6001000010333', price: 109.99),
        _product('Woolworths Gourmet Boerewors Per Kg', price: 139.99),
        _product('PnP Boerewors 500g', price: 64.99),
        _product('Spar Premium Boerewors Per Kg SK6001000010444',
            price: 119.99),
        _product('Checkers Boerewors Per Kg', price: 104.99),
        _product('Boerewors Roll Spice 100g', price: 24.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'boerewors',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull, reason: 'Should find a boerewors match');
      final name = result!.name.toLowerCase();
      expect(name, contains('boerewors'),
          reason: 'Should match a boerewors product');
      expect(name, isNot(contains('spice')),
          reason: 'Boerewors spice is not boerewors meat');
    });

    test('braai spice → matches Robertsons/similar braai spice blend',
        () async {
      final hint = IngredientLookup.resolve('braai spice');

      final candidates = [
        _product('Robertsons Braai Spice 200ml SK6001000010555', price: 34.99),
        _product('Ina Paarman Braai And Grill Seasoning 200ml', price: 39.99),
        _product('Woolworths Braai Spice 100g', price: 29.99),
        _product('PnP Braai Spice 100g', price: 22.99),
        _product('Spar Braai Spice 200ml SK6001000010666', price: 27.99),
        _product('Checkers Braai Salt 500g', price: 19.99),
        _product('Weber Briquettes 4kg', price: 89.99),
      ];

      final result = await matcher.matchIngredient(
        ingredientName: 'braai spice',
        candidates: candidates,
        hint: hint,
      );

      expect(result, isNotNull, reason: 'Should find a braai spice match');
      final name = result!.name.toLowerCase();
      expect(name, contains('braai'),
          reason: 'Should match a braai spice product');
      expect(name, isNot(contains('briquettes')),
          reason: 'Charcoal briquettes are not braai spice');
    });
  });

  // ###########################################################################
  // SECTION 10: CROSS-RETAILER PRODUCT SEARCH ACCURACY — 5 RETAILERS
  // ###########################################################################
  //
  // Tests the full findMatchesAlgorithm flow with realistic product catalogs
  // from all 5 grocery retailers. Each test validates correct matching,
  // confidence scores, and SPAR SK barcode handling.

  group('Cross-retailer product search accuracy - 5 retailers', () {
    late SmartMatchingService matcher;
    setUp(() {
      matcher = SmartMatchingService(gemini: GeminiService(apiKey: 'test-key'));
    });

    test('Nescafe Gold Instant Coffee 200g → correct match across all 5 retailers',
        () {
      final source =
          _product('Nescafe Gold Instant Coffee 200g', price: 119.99);

      final candidatesByRetailer = <String, List<LiveProduct>>{
        'Pick n Pay': [
          _product('Nescafe Gold Instant Coffee 200g', price: 114.99),
          _product('Nescafe Classic Instant Coffee 200g', price: 89.99),
          _product('Jacobs Kronung Instant Coffee 200g', price: 109.99),
          _product('PnP Instant Coffee 200g', price: 49.99),
        ],
        'Woolworths': [
          _product('Nescafe Gold Instant Coffee 200g', price: 124.99),
          _product('Woolworths Single Origin Instant Coffee 200g',
              price: 89.99),
          _product('Nescafe Gold Decaf 200g', price: 129.99),
        ],
        'Checkers': [
          _product('Nescafe Gold Instant Coffee 200g', price: 117.99),
          _product('Nescafe Gold Cappuccino Sachets 10s', price: 64.99),
          _product('Ricoffy Instant Coffee 750g', price: 89.99),
          _product('Frisco Instant Coffee 250g', price: 79.99),
        ],
        'Shoprite': [
          _product('Nescafe Gold Instant Coffee 200g', price: 112.99),
          _product('Nescafe Gold Instant Coffee 100g', price: 69.99),
          _product('House Of Coffees Instant Coffee 200g', price: 64.99),
        ],
        'SPAR': [
          _product('Nescafe Gold Instant Coffee 200g SK7613036800012',
              price: 118.99),
          _product('Nescafe Classic 200g SK7613036000111', price: 87.99),
          _product('Spar Instant Coffee 200g SK6001008733000', price: 44.99),
          _product('Nescafe Gold Cappuccino 10s SK7613036800222', price: 62.99),
        ],
      };

      final result = matcher.findMatchesAlgorithm(
        sourceProduct: source,
        candidatesByRetailer: candidatesByRetailer,
      );

      // All retailers should have a match
      for (final retailer in candidatesByRetailer.keys) {
        final best = result.bestMatchPerRetailer[retailer];
        expect(best, isNotNull,
            reason: '$retailer should have a match for Nescafe Gold');

        final matchName = best!.name.toLowerCase();
        expect(matchName, contains('nescafe gold'),
            reason: '$retailer should match Nescafe Gold, not another coffee');
        expect(matchName, contains('200g'),
            reason:
                '$retailer should match 200g size, not different size or sachets');
        expect(matchName, isNot(contains('cappuccino')),
            reason: '$retailer should not match cappuccino sachets');
        expect(matchName, isNot(contains('classic')),
            reason: '$retailer should not match Nescafe Classic');
        expect(matchName, isNot(contains('decaf')),
            reason: '$retailer should not match decaf variant');

        // Confidence should be high for exact same product
        expect(best.confidenceScore, greaterThanOrEqualTo(0.80),
            reason:
                '$retailer confidence ${best.confidenceScore} too low for exact match');
      }

      // Verify SPAR product has SK barcode in name
      final sparBest = result.bestMatchPerRetailer['SPAR']!;
      expect(sparBest.name, contains('SK'),
          reason: 'SPAR product should retain SK barcode suffix');
    });

    test('Koo Baked Beans In Tomato Sauce 410g → correct match across all 5',
        () {
      final source =
          _product('Koo Baked Beans In Tomato Sauce 410g', price: 19.99);

      final candidatesByRetailer = <String, List<LiveProduct>>{
        'Pick n Pay': [
          _product('Koo Baked Beans In Tomato Sauce 410g', price: 18.99),
          _product('Koo Baked Beans In Curry Sauce 410g', price: 19.49),
          _product('All Gold Tomato Sauce 700ml', price: 42.99),
          _product('PnP Baked Beans 410g', price: 12.99),
        ],
        'Woolworths': [
          _product('Koo Baked Beans In Tomato Sauce 410g', price: 20.99),
          _product('Woolworths Baked Beans 410g', price: 16.99),
        ],
        'Checkers': [
          _product('Koo Baked Beans In Tomato Sauce 410g', price: 18.49),
          _product('Koo Four Bean Mix 410g', price: 22.99),
          _product('Bull Brand Corned Meat 300g', price: 34.99),
        ],
        'Shoprite': [
          _product('Koo Baked Beans In Tomato Sauce 410g', price: 17.99),
          _product('Koo Baked Beans In Tomato Sauce 225g', price: 11.99),
          _product('KOO Green Beans 410g', price: 18.99),
        ],
        'SPAR': [
          _product('Koo Baked Beans In Tomato Sauce 410g SK6001015000789',
              price: 18.79),
          _product('Koo Baked Beans In Curry Sauce 410g SK6001015000890',
              price: 19.29),
          _product('Spar Baked Beans 410g SK6001008734000', price: 11.99),
        ],
      };

      final result = matcher.findMatchesAlgorithm(
        sourceProduct: source,
        candidatesByRetailer: candidatesByRetailer,
      );

      for (final retailer in candidatesByRetailer.keys) {
        final best = result.bestMatchPerRetailer[retailer];
        expect(best, isNotNull,
            reason: '$retailer should have a match');

        final matchName = best!.name.toLowerCase();
        expect(matchName, contains('baked beans'),
            reason: '$retailer should match baked beans');
        expect(matchName, contains('tomato'),
            reason:
                '$retailer should match tomato sauce variant specifically');
        expect(matchName, isNot(contains('green beans')),
            reason: '$retailer should not match green beans');
        expect(matchName, isNot(contains('corned')),
            reason: '$retailer should not match corned meat');

        // 410g size preferred
        expect(matchName, contains('410g'),
            reason: '$retailer should match 410g, not smaller size');
      }

      // Verify correct Koo brand match for SPAR (not SPAR own brand)
      final sparBest = result.bestMatchPerRetailer['SPAR']!;
      expect(sparBest.name.toLowerCase(), contains('koo'),
          reason: 'SPAR should match Koo brand, not Spar own brand');
      expect(sparBest.confidenceScore, greaterThanOrEqualTo(0.80),
          reason: 'SPAR confidence should be high for exact product');
    });

    test('Simba Chips Salt & Vinegar 125g → correct match across all 5', () {
      final source =
          _product('Simba Chips Salt & Vinegar 125g', price: 19.99);

      final candidatesByRetailer = <String, List<LiveProduct>>{
        'Pick n Pay': [
          _product('Simba Chips Salt & Vinegar 125g', price: 18.99),
          _product('Simba Chips Creamy Cheddar 125g', price: 18.99),
          _product('Lays Salt & Vinegar 120g', price: 21.99),
          _product('Simba Chips Salt & Vinegar 36g', price: 7.99),
        ],
        'Woolworths': [
          _product('Simba Chips Salt & Vinegar 125g', price: 21.99),
          _product('Woolworths Sea Salt Crisps 150g', price: 24.99),
        ],
        'Checkers': [
          _product('Simba Chips Salt & Vinegar 125g', price: 17.99),
          _product('Simba Chips Mrs Balls Chutney 125g', price: 18.99),
          _product('NikNaks Original 135g', price: 18.99),
        ],
        'Shoprite': [
          _product('Simba Chips Salt & Vinegar 125g', price: 17.49),
          _product('Simba Chips Salt & Vinegar 200g', price: 29.99),
          _product('Willards Crinkle Cut 125g', price: 16.99),
        ],
        'SPAR': [
          _product('Simba Chips Salt And Vinegar 125g SK6009510800111',
              price: 18.49),
          _product('Simba Chips Creamy Cheddar 125g SK6009510800222',
              price: 18.49),
          _product('Spar Potato Chips Sea Salt 150g SK6001008735000',
              price: 14.99),
        ],
      };

      final result = matcher.findMatchesAlgorithm(
        sourceProduct: source,
        candidatesByRetailer: candidatesByRetailer,
      );

      for (final retailer in candidatesByRetailer.keys) {
        final best = result.bestMatchPerRetailer[retailer];
        expect(best, isNotNull,
            reason: '$retailer should have a match');

        final matchName = best!.name.toLowerCase();
        expect(matchName, contains('simba'),
            reason: '$retailer should match Simba brand');
        expect(matchName, anyOf(contains('salt & vinegar'), contains('salt and vinegar')),
            reason: '$retailer should match salt & vinegar flavour');
        expect(matchName, isNot(contains('cheddar')),
            reason: '$retailer should not match cheddar flavour');
        expect(matchName, isNot(contains('chutney')),
            reason: '$retailer should not match chutney flavour');

        // Should prefer 125g over 36g or 200g
        expect(matchName, contains('125g'),
            reason: '$retailer should match 125g size');

        expect(best.confidenceScore, greaterThanOrEqualTo(0.75),
            reason:
                '$retailer confidence ${best.confidenceScore} too low for Simba match');
      }
    });

    test('Sunlight Dishwashing Liquid 750ml → correct match across all 5', () {
      final source =
          _product('Sunlight Dishwashing Liquid 750ml', price: 39.99);

      final candidatesByRetailer = <String, List<LiveProduct>>{
        'Pick n Pay': [
          _product('Sunlight Dishwashing Liquid Regular 750ml', price: 37.99),
          _product('Sunlight Dishwashing Liquid Lemon 750ml', price: 37.99),
          _product('PnP Dishwashing Liquid 750ml', price: 19.99),
          _product('Sunlight Hand Washing Powder 2kg', price: 49.99),
        ],
        'Woolworths': [
          _product('Sunlight Dishwashing Liquid 750ml', price: 42.99),
          _product('Woolworths Eco Dishwashing Liquid 500ml', price: 34.99),
        ],
        'Checkers': [
          _product('Sunlight Dishwashing Liquid 750ml', price: 36.99),
          _product('Morning Fresh Dishwashing Liquid 450ml', price: 54.99),
          _product('Sunlight Laundry Bar 500g', price: 22.99),
        ],
        'Shoprite': [
          _product('Sunlight Dishwashing Liquid Regular 750ml', price: 35.99),
          _product('Sunlight Dishwashing Liquid Regular 400ml', price: 22.99),
          _product('Sunlight 2-In-1 Auto Washing Powder 2kg', price: 69.99),
        ],
        'SPAR': [
          _product('Sunlight Dishwashing Liquid 750ml SK6001085000111',
              price: 38.49),
          _product('Sunlight Laundry Bar 500g SK6001085000222', price: 21.99),
          _product('Spar Dishwashing Liquid 750ml SK6001008736000',
              price: 16.99),
        ],
      };

      final result = matcher.findMatchesAlgorithm(
        sourceProduct: source,
        candidatesByRetailer: candidatesByRetailer,
      );

      for (final retailer in candidatesByRetailer.keys) {
        final best = result.bestMatchPerRetailer[retailer];
        expect(best, isNotNull,
            reason: '$retailer should have a match');

        final matchName = best!.name.toLowerCase();
        expect(matchName, contains('sunlight'),
            reason: '$retailer should match Sunlight brand');
        expect(matchName, contains('dishwashing'),
            reason: '$retailer should match dishwashing liquid');
        expect(matchName, isNot(contains('laundry')),
            reason: '$retailer should not match laundry products');
        expect(matchName, isNot(contains('powder')),
            reason: '$retailer should not match washing powder');
        expect(matchName, isNot(contains('bar')),
            reason: '$retailer should not match soap bar');

        // Should match 750ml size
        expect(matchName, contains('750ml'),
            reason: '$retailer should match 750ml size');

        expect(best.confidenceScore, greaterThanOrEqualTo(0.75),
            reason:
                '$retailer confidence ${best.confidenceScore} too low for Sunlight');
      }
    });

    test('Pampers Baby Dry Size 4 Jumbo Pack → correct match across PnP, SPAR, Checkers',
        () {
      final source =
          _product('Pampers Baby Dry Size 4 Jumbo Pack', price: 249.99);

      final candidatesByRetailer = <String, List<LiveProduct>>{
        'Pick n Pay': [
          _product('Pampers Baby Dry Size 4 Jumbo Pack 64s', price: 239.99),
          _product('Pampers Baby Dry Size 3 Jumbo Pack 68s', price: 239.99),
          _product('Pampers Premium Care Size 4 44s', price: 279.99),
          _product('Huggies Gold Size 4 60s', price: 219.99),
          _product('Panadol Pain Tablets 24s', price: 49.99),
        ],
        'SPAR': [
          _product('Pampers Baby Dry Size 4 Jumbo Pack 64s SK6001000011111',
              price: 244.99),
          _product('Pampers Baby Dry Size 5 Jumbo Pack 56s SK6001000011222',
              price: 249.99),
          _product('Spar Baby Wipes 80s SK6001008737000', price: 29.99),
          _product('Pampers Active Baby Size 4 Maxi 76s SK6001000011333',
              price: 259.99),
        ],
        'Checkers': [
          _product('Pampers Baby Dry Size 4 Jumbo Pack 64s', price: 234.99),
          _product('Pampers Baby Dry Size 4 Value Pack 38s', price: 149.99),
          _product('Luvs Diapers Size 4 29s', price: 129.99),
          _product('Checkers Baby Nappies Size 4 50s', price: 119.99),
        ],
      };

      final result = matcher.findMatchesAlgorithm(
        sourceProduct: source,
        candidatesByRetailer: candidatesByRetailer,
      );

      for (final retailer in candidatesByRetailer.keys) {
        final best = result.bestMatchPerRetailer[retailer];
        expect(best, isNotNull,
            reason: '$retailer should have a match');

        final matchName = best!.name.toLowerCase();
        expect(matchName, contains('pampers'),
            reason: '$retailer should match Pampers brand');
        expect(matchName, contains('size 4'),
            reason: '$retailer should match Size 4');
        expect(matchName, isNot(contains('panadol')),
            reason: '$retailer should not match pharmacy items');
        expect(matchName, isNot(contains('wipes')),
            reason: '$retailer should not match baby wipes');

        // Should prefer jumbo pack over value pack or different size
        expect(matchName, contains('jumbo'),
            reason: '$retailer should match jumbo pack');
        expect(matchName, isNot(contains('size 3')),
            reason: '$retailer should not match Size 3');
        expect(matchName, isNot(contains('size 5')),
            reason: '$retailer should not match Size 5');
      }

      // Verify SPAR has SK barcode
      final sparBest = result.bestMatchPerRetailer['SPAR']!;
      expect(sparBest.name, contains('SK'),
          reason: 'SPAR product should retain SK barcode suffix');

      // Verify price comparison makes sense
      final pnpBest = result.bestMatchPerRetailer['Pick n Pay']!;
      expect(pnpBest.priceNumeric, closeTo(239.99, 0.01),
          reason: 'PnP price should be R239.99');

      final checkersBest = result.bestMatchPerRetailer['Checkers']!;
      expect(checkersBest.priceNumeric, closeTo(234.99, 0.01),
          reason: 'Checkers price should be R234.99 for jumbo pack');
      expect(checkersBest.priceDifference, closeTo(-15.00, 0.01),
          reason: 'Checkers should be R15 cheaper than source');
      expect(checkersBest.isCheaper, isTrue,
          reason: 'Checkers should be flagged as cheaper');
    });
  });
}
