import 'package:uuid/uuid.dart';

/// Recipe model for AI-generated and saved recipes
class Recipe {
  final String? recipeId;
  final String? userId;
  final DateTime? createdAt;
  final String recipeName;
  final String? recipeDescription;
  final int servings;
  final int? prepTimeMinutes;
  final int? cookTimeMinutes;
  final int? totalTimeMinutes;
  final String? difficulty;
  final List<String> instructions;
  final String? cuisineType;
  final String? mealType;
  final List<String> dietaryTags;
  final bool aiGenerated;
  final String? originalPrompt;
  final List<RecipeIngredient> ingredients;

  Recipe({
    this.recipeId,
    this.userId,
    this.createdAt,
    required this.recipeName,
    this.recipeDescription,
    this.servings = 4,
    this.prepTimeMinutes,
    this.cookTimeMinutes,
    this.totalTimeMinutes,
    this.difficulty,
    this.instructions = const [],
    this.cuisineType,
    this.mealType,
    this.dietaryTags = const [],
    this.aiGenerated = false,
    this.originalPrompt,
    this.ingredients = const [],
  });

  /// Create Recipe from Supabase JSON response
  factory Recipe.fromJson(Map<String, dynamic> json) {
    // Parse ingredients from nested Recipe_Ingredients
    List<RecipeIngredient> ingredientsList = [];
    if (json['Recipe_Ingredients'] != null) {
      ingredientsList = (json['Recipe_Ingredients'] as List)
          .map((i) => RecipeIngredient.fromJson(i as Map<String, dynamic>))
          .toList();
      // Sort by display_order
      ingredientsList.sort(
        (a, b) => (a.displayOrder ?? 0).compareTo(b.displayOrder ?? 0),
      );
    }

    // Parse instructions from JSON array or string
    List<String> instructions = [];
    if (json['instructions'] != null) {
      if (json['instructions'] is List) {
        instructions = (json['instructions'] as List)
            .map((e) => e.toString())
            .toList();
      } else if (json['instructions'] is String) {
        // Try to parse as JSON array string
        instructions = [json['instructions'] as String];
      }
    }

    // Parse dietary tags
    List<String> dietaryTags = [];
    if (json['dietary_tags'] != null) {
      if (json['dietary_tags'] is List) {
        dietaryTags = (json['dietary_tags'] as List)
            .map((e) => e.toString())
            .toList();
      }
    }

    return Recipe(
      recipeId: json['recipe_id'] as String?,
      userId: json['user_id'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      recipeName: json['recipe_name'] as String? ?? 'Untitled Recipe',
      recipeDescription: json['recipe_description'] as String?,
      servings: json['servings'] as int? ?? 4,
      prepTimeMinutes: json['prep_time_minutes'] as int?,
      cookTimeMinutes: json['cook_time_minutes'] as int?,
      totalTimeMinutes: json['total_time_minutes'] as int?,
      difficulty: json['difficulty'] as String?,
      instructions: instructions,
      cuisineType: json['cuisine_type'] as String?,
      mealType: json['meal_type'] as String?,
      dietaryTags: dietaryTags,
      aiGenerated: json['ai_generated'] as bool? ?? false,
      originalPrompt: json['original_prompt'] as String?,
      ingredients: ingredientsList,
    );
  }

  /// Convert Recipe to JSON for Supabase insert
  Map<String, dynamic> toJson() {
    return {
      if (recipeId != null) 'recipe_id': recipeId,
      'recipe_name': recipeName,
      'recipe_description': recipeDescription,
      'servings': servings,
      'prep_time_minutes': prepTimeMinutes,
      'cook_time_minutes': cookTimeMinutes,
      'total_time_minutes': totalTimeMinutes,
      'difficulty': difficulty,
      'instructions': instructions,
      'cuisine_type': cuisineType,
      'meal_type': mealType,
      'dietary_tags': dietaryTags,
      'ai_generated': aiGenerated,
      'original_prompt': originalPrompt,
      'created_at':
          createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
    };
  }

  /// Create a copy with updated fields
  Recipe copyWith({
    String? recipeId,
    String? userId,
    DateTime? createdAt,
    String? recipeName,
    String? recipeDescription,
    int? servings,
    int? prepTimeMinutes,
    int? cookTimeMinutes,
    int? totalTimeMinutes,
    String? difficulty,
    List<String>? instructions,
    String? cuisineType,
    String? mealType,
    List<String>? dietaryTags,
    bool? aiGenerated,
    String? originalPrompt,
    List<RecipeIngredient>? ingredients,
  }) {
    return Recipe(
      recipeId: recipeId ?? this.recipeId,
      userId: userId ?? this.userId,
      createdAt: createdAt ?? this.createdAt,
      recipeName: recipeName ?? this.recipeName,
      recipeDescription: recipeDescription ?? this.recipeDescription,
      servings: servings ?? this.servings,
      prepTimeMinutes: prepTimeMinutes ?? this.prepTimeMinutes,
      cookTimeMinutes: cookTimeMinutes ?? this.cookTimeMinutes,
      totalTimeMinutes: totalTimeMinutes ?? this.totalTimeMinutes,
      difficulty: difficulty ?? this.difficulty,
      instructions: instructions ?? this.instructions,
      cuisineType: cuisineType ?? this.cuisineType,
      mealType: mealType ?? this.mealType,
      dietaryTags: dietaryTags ?? this.dietaryTags,
      aiGenerated: aiGenerated ?? this.aiGenerated,
      originalPrompt: originalPrompt ?? this.originalPrompt,
      ingredients: ingredients ?? this.ingredients,
    );
  }

  /// Total time formatted as string (returns empty string if null)
  String get formattedTotalTime {
    if (totalTimeMinutes == null) return '';
    if (totalTimeMinutes! < 60) return '${totalTimeMinutes}min';
    final hours = totalTimeMinutes! ~/ 60;
    final minutes = totalTimeMinutes! % 60;
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}min';
  }

  /// Prep time formatted
  String get formattedPrepTime {
    if (prepTimeMinutes == null) return '';
    if (prepTimeMinutes! < 60) return '${prepTimeMinutes}min';
    final hours = prepTimeMinutes! ~/ 60;
    final minutes = prepTimeMinutes! % 60;
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}min';
  }

  /// Cook time formatted
  String get formattedCookTime {
    if (cookTimeMinutes == null) return '';
    if (cookTimeMinutes! < 60) return '${cookTimeMinutes}min';
    final hours = cookTimeMinutes! ~/ 60;
    final minutes = cookTimeMinutes! % 60;
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}min';
  }

  /// Calculate estimated total price from matched ingredients
  /// Returns 0.0 if no ingredients are matched (NON-NULLABLE for safe comparisons)
  double get estimatedTotalPrice {
    final matchedIngredients = ingredients.where((i) => i.isMatched).toList();
    if (matchedIngredients.isEmpty) return 0.0;

    return matchedIngredients.fold<double>(
      0.0,
      (sum, ingredient) => sum + (ingredient.matchedProductPrice ?? 0.0),
    );
  }

  /// Count of matched ingredients
  int get matchedIngredientsCount =>
      ingredients.where((i) => i.isMatched).length;

  /// Count of unmatched ingredients
  int get unmatchedIngredientsCount =>
      ingredients.where((i) => !i.isMatched).length;

  /// Percentage of ingredients matched
  int get matchedPercentage {
    if (ingredients.isEmpty) return 0;
    return ((matchedIngredientsCount / ingredients.length) * 100).round();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Recipe &&
          runtimeType == other.runtimeType &&
          recipeId == other.recipeId;

  @override
  int get hashCode => recipeId.hashCode;
}

/// Individual ingredient in a recipe
class RecipeIngredient {
  final String? ingredientId;
  final String? recipeId;
  final DateTime? createdAt;
  final String ingredientName;
  final double? quantity;
  final String? unit;
  final String? preparation;
  final bool isOptional;
  final String? matchedProductIndex;
  final String? matchedProductName;
  final double? matchedProductPrice;
  final String? matchedRetailer;
  final int? displayOrder;

  RecipeIngredient({
    String? ingredientId,
    this.recipeId,
    this.createdAt,
    required this.ingredientName,
    this.quantity,
    this.unit,
    this.preparation,
    this.isOptional = false,
    this.matchedProductIndex,
    this.matchedProductName,
    this.matchedProductPrice,
    this.matchedRetailer,
    this.displayOrder,
  }) : ingredientId = ingredientId ?? const Uuid().v4();

  /// Create RecipeIngredient from Supabase JSON
  factory RecipeIngredient.fromJson(Map<String, dynamic> json) {
    return RecipeIngredient(
      ingredientId: json['ingredient_id'] as String?,
      recipeId: json['recipe_id'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      ingredientName: json['ingredient_name'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toDouble(),
      unit: json['unit'] as String?,
      preparation: json['preparation'] as String?,
      isOptional: json['is_optional'] as bool? ?? false,
      matchedProductIndex: json['matched_product_index'] as String?,
      matchedProductName: json['matched_product_name'] as String?,
      matchedProductPrice: (json['matched_product_price'] as num?)?.toDouble(),
      matchedRetailer: json['matched_retailer'] as String?,
      displayOrder: json['display_order'] as int?,
    );
  }

  /// Convert to JSON for Supabase insert
  Map<String, dynamic> toJson() {
    return {
      'ingredient_id': ingredientId,
      'ingredient_name': ingredientName,
      'quantity': quantity,
      'unit': unit,
      'preparation': preparation,
      'is_optional': isOptional,
      'matched_product_index': matchedProductIndex,
      'matched_product_name': matchedProductName,
      'matched_product_price': matchedProductPrice,
      'matched_retailer': matchedRetailer,
      'display_order': displayOrder,
    };
  }

  /// Create a copy with updated fields
  /// Use [clearMatch: true] to explicitly clear the match fields
  RecipeIngredient copyWith({
    String? ingredientId,
    String? recipeId,
    DateTime? createdAt,
    String? ingredientName,
    double? quantity,
    String? unit,
    String? preparation,
    bool? isOptional,
    String? matchedProductIndex,
    String? matchedProductName,
    double? matchedProductPrice,
    String? matchedRetailer,
    int? displayOrder,
    bool clearMatch = false,
  }) {
    return RecipeIngredient(
      ingredientId: ingredientId ?? this.ingredientId,
      recipeId: recipeId ?? this.recipeId,
      createdAt: createdAt ?? this.createdAt,
      ingredientName: ingredientName ?? this.ingredientName,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      preparation: preparation ?? this.preparation,
      isOptional: isOptional ?? this.isOptional,
      matchedProductIndex: clearMatch
          ? null
          : (matchedProductIndex ?? this.matchedProductIndex),
      matchedProductName: clearMatch
          ? null
          : (matchedProductName ?? this.matchedProductName),
      matchedProductPrice: clearMatch
          ? null
          : (matchedProductPrice ?? this.matchedProductPrice),
      matchedRetailer: clearMatch
          ? null
          : (matchedRetailer ?? this.matchedRetailer),
      displayOrder: displayOrder ?? this.displayOrder,
    );
  }

  /// Formatted quantity string (e.g., "500g", "2 cups", "1 large")
  String get formattedQuantity {
    if (quantity == null && unit == null) return '';

    final qtyStr = quantity != null
        ? (quantity! == quantity!.roundToDouble()
              ? quantity!.toInt().toString()
              : quantity!.toString())
        : '';

    final unitStr = unit ?? '';
    final prepStr = preparation != null ? ', $preparation' : '';

    // Add space before count-based units (e.g. "2 units" not "2units")
    final sep = unitStr.isNotEmpty &&
            !RegExp(r'^(g|kg|ml|l)$', caseSensitive: false).hasMatch(unitStr)
        ? ' '
        : '';

    return '$qtyStr$sep$unitStr$prepStr'.trim();
  }

  /// Full display string (e.g., "500g Chicken Breast, diced")
  String get displayString {
    final qty = formattedQuantity;
    if (qty.isEmpty) return ingredientName;
    return '$qty $ingredientName';
  }

  /// Whether this ingredient has been matched to a product
  bool get isMatched => matchedProductIndex != null;

  /// Formatted price string
  String? get formattedPrice {
    if (matchedProductPrice == null) return null;
    return 'R${matchedProductPrice!.toStringAsFixed(2)}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecipeIngredient &&
          runtimeType == other.runtimeType &&
          ingredientId == other.ingredientId;

  @override
  int get hashCode => ingredientId.hashCode;
}

/// Represents a product match candidate for an ingredient
/// Used when searching for products to match to recipe ingredients
class IngredientProductMatch {
  final String productIndex;
  final String productName;
  final String? productPrice;
  final String? productPromotionPrice;
  final String? productImageUrl;
  final String retailer;
  final double similarityScore;
  final double? sizeValue;
  final String? sizeUnit;

  IngredientProductMatch({
    required this.productIndex,
    required this.productName,
    this.productPrice,
    this.productPromotionPrice,
    this.productImageUrl,
    required this.retailer,
    required this.similarityScore,
    this.sizeValue,
    this.sizeUnit,
  });

  /// Create from Supabase RPC response
  /// Note: Field names match the SQL function output:
  /// - index, name, price, promotion_price, image_url, retailer, similarity_score, size_value, size_unit
  factory IngredientProductMatch.fromJson(Map<String, dynamic> json) {
    return IngredientProductMatch(
      // SQL returns 'index', not 'product_index'
      productIndex: json['index'] as String? ?? '',
      // SQL returns 'name', not 'product_name'
      productName: json['name'] as String? ?? '',
      // SQL returns 'price', not 'product_price'
      productPrice: json['price'] as String?,
      // SQL returns 'promotion_price', not 'product_promotion_price'
      productPromotionPrice: json['promotion_price'] as String?,
      // SQL returns 'image_url', not 'product_image_url'
      productImageUrl: json['image_url'] as String?,
      // retailer matches
      retailer: json['retailer'] as String? ?? '',
      // SQL returns 'similarity_score', handle both names for safety
      similarityScore:
          (json['similarity_score'] as num?)?.toDouble() ??
          (json['sim_score'] as num?)?.toDouble() ??
          0.0,
      // size_value and size_unit match
      sizeValue: (json['size_value'] as num?)?.toDouble(),
      sizeUnit: json['size_unit'] as String?,
    );
  }

  /// Extract numeric price from price string (e.g., "R89.99" -> 89.99)
  double? get numericPrice {
    if (productPrice == null) return null;
    final match = RegExp(r'R?\s*(\d+\.?\d*)').firstMatch(productPrice!);
    if (match != null) {
      return double.tryParse(match.group(1)!);
    }
    return null;
  }

  /// Formatted size string
  String? get formattedSize {
    if (sizeValue == null || sizeUnit == null) return null;
    return '${sizeValue!.toStringAsFixed(sizeValue! == sizeValue!.roundToDouble() ? 0 : 1)}$sizeUnit';
  }

  /// Similarity as percentage
  String get similarityPercentage => '${(similarityScore * 100).toInt()}%';

  /// Check if product has a promotion
  bool get hasPromotion =>
      productPromotionPrice != null && productPromotionPrice!.isNotEmpty;
}

// NOTE: RecipeSuggestion is ONLY defined in gemini_service.dart
// Do NOT add it here to avoid duplicate class conflicts

/// One retailer's matched products for a set of selected ingredients.
/// Used by the retailer cost comparison feature (Sprint 10b).
class RetailerBasket {
  final String retailerName;

  /// ingredientId → best matched product (null = not found / not available)
  final Map<String, IngredientProductMatch?> matches;

  final bool isLoading;
  final String? error;

  const RetailerBasket({
    required this.retailerName,
    required this.matches,
    this.isLoading = false,
    this.error,
  });

  RetailerBasket copyWith({
    String? retailerName,
    Map<String, IngredientProductMatch?>? matches,
    bool? isLoading,
    String? error,
  }) {
    return RetailerBasket(
      retailerName: retailerName ?? this.retailerName,
      matches: matches ?? this.matches,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }

  double get total => matches.values
      .whereType<IngredientProductMatch>()
      .fold(0.0, (sum, m) => sum + (m.numericPrice ?? 0.0));

  int get matchedCount =>
      matches.values.whereType<IngredientProductMatch>().length;

  String get formattedTotal => 'R${total.toStringAsFixed(2)}';
}

/// Full multi-retailer comparison state for the recipe export flow.
class RetailerComparisonState {
  final bool isLoading;

  /// retailerName → RetailerBasket
  final Map<String, RetailerBasket> baskets;

  final String? selectedRetailer;
  final String? error;

  const RetailerComparisonState({
    this.isLoading = false,
    this.baskets = const {},
    this.selectedRetailer,
    this.error,
  });

  RetailerComparisonState copyWith({
    bool? isLoading,
    Map<String, RetailerBasket>? baskets,
    String? selectedRetailer,
    String? error,
  }) {
    return RetailerComparisonState(
      isLoading: isLoading ?? this.isLoading,
      baskets: baskets ?? this.baskets,
      selectedRetailer: selectedRetailer ?? this.selectedRetailer,
      error: error ?? this.error,
    );
  }

  /// Returns the retailer name with the lowest total cost (ignoring empty/unavailable baskets).
  String? get cheapestRetailer {
    if (baskets.isEmpty) return null;
    final loaded = baskets.entries.where(
      (e) => !e.value.isLoading && e.value.error == null && e.value.matchedCount > 0,
    );
    if (loaded.isEmpty) return null;
    return loaded.reduce((a, b) => a.value.total < b.value.total ? a : b).key;
  }

  bool get hasData => baskets.values.any((b) => !b.isLoading && b.matchedCount > 0);
}
