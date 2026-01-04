import 'package:flutter/foundation.dart';

/// Represents a recipe with ingredients and instructions
class Recipe {
  final String? recipeId;
  final String? userId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
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
  final String? imageUrl;
  final List<RecipeIngredient> ingredients;

  Recipe({
    this.recipeId,
    this.userId,
    this.createdAt,
    this.updatedAt,
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
    this.aiGenerated = true,
    this.originalPrompt,
    this.imageUrl,
    this.ingredients = const [],
  });

  /// Create from Supabase JSON response
  factory Recipe.fromJson(Map<String, dynamic> json) {
    return Recipe(
      recipeId: json['recipe_id'] as String?,
      userId: json['user_id'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      recipeName: json['recipe_name'] as String? ?? 'Untitled Recipe',
      recipeDescription: json['recipe_description'] as String?,
      servings: json['servings'] as int? ?? 4,
      prepTimeMinutes: json['prep_time_minutes'] as int?,
      cookTimeMinutes: json['cook_time_minutes'] as int?,
      totalTimeMinutes: json['total_time_minutes'] as int?,
      difficulty: json['difficulty'] as String?,
      instructions: json['instructions'] != null
          ? List<String>.from(json['instructions'] as List)
          : [],
      cuisineType: json['cuisine_type'] as String?,
      mealType: json['meal_type'] as String?,
      dietaryTags: json['dietary_tags'] != null
          ? List<String>.from(json['dietary_tags'] as List)
          : [],
      aiGenerated: json['ai_generated'] as bool? ?? true,
      originalPrompt: json['original_prompt'] as String?,
      imageUrl: json['image_url'] as String?,
      ingredients: json['Recipe_Ingredients'] != null
          ? (json['Recipe_Ingredients'] as List)
                .map(
                  (e) => RecipeIngredient.fromJson(e as Map<String, dynamic>),
                )
                .toList()
          : [],
    );
  }

  /// Convert to JSON for Supabase insert/update
  Map<String, dynamic> toJson() {
    return {
      if (recipeId != null) 'recipe_id': recipeId,
      if (userId != null) 'user_id': userId,
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
      'image_url': imageUrl,
    };
  }

  /// Create a copy with updated fields
  Recipe copyWith({
    String? recipeId,
    String? userId,
    DateTime? createdAt,
    DateTime? updatedAt,
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
    String? imageUrl,
    List<RecipeIngredient>? ingredients,
  }) {
    return Recipe(
      recipeId: recipeId ?? this.recipeId,
      userId: userId ?? this.userId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
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
      imageUrl: imageUrl ?? this.imageUrl,
      ingredients: ingredients ?? this.ingredients,
    );
  }

  /// Formatted total time string
  String get formattedTotalTime {
    if (totalTimeMinutes == null) return '';
    if (totalTimeMinutes! < 60) return '${totalTimeMinutes}min';
    final hours = totalTimeMinutes! ~/ 60;
    final minutes = totalTimeMinutes! % 60;
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}min';
  }

  /// Formatted prep time string
  String get formattedPrepTime {
    if (prepTimeMinutes == null) return '';
    return '${prepTimeMinutes}min prep';
  }

  /// Formatted cook time string
  String get formattedCookTime {
    if (cookTimeMinutes == null) return '';
    return '${cookTimeMinutes}min cook';
  }

  /// Calculate estimated total price from matched ingredients
  double get estimatedTotalPrice {
    return ingredients
        .where((i) => i.matchedProductPrice != null)
        .fold(0.0, (sum, i) => sum + i.matchedProductPrice!);
  }

  /// Count of ingredients with product matches
  int get matchedIngredientsCount {
    return ingredients.where((i) => i.matchedProductIndex != null).length;
  }

  /// Count of ingredients without product matches
  int get unmatchedIngredientsCount {
    return ingredients.where((i) => i.matchedProductIndex == null).length;
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

/// Represents an ingredient in a recipe
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
  final int displayOrder;

  RecipeIngredient({
    this.ingredientId,
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
    this.displayOrder = 0,
  });

  /// Create from Supabase JSON response
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
      displayOrder: json['display_order'] as int? ?? 0,
    );
  }

  /// Convert to JSON for Supabase insert/update
  Map<String, dynamic> toJson() {
    return {
      if (ingredientId != null) 'ingredient_id': ingredientId,
      if (recipeId != null) 'recipe_id': recipeId,
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
  /// Use [clearMatch] = true to explicitly clear all match-related fields
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

    return '$qtyStr$unitStr$prepStr'.trim();
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

  factory IngredientProductMatch.fromJson(Map<String, dynamic> json) {
    return IngredientProductMatch(
      productIndex: json['product_index'] as String,
      productName: json['product_name'] as String,
      productPrice: json['product_price'] as String?,
      productPromotionPrice: json['product_promotion_price'] as String?,
      productImageUrl: json['product_image_url'] as String?,
      retailer: json['retailer'] as String,
      similarityScore: (json['similarity_score'] as num).toDouble(),
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
    return '${sizeValue!.toStringAsFixed(sizeValue! == sizeValue!.roundToDouble() ? 0 : 1)}${sizeUnit}';
  }

  /// Similarity as percentage
  String get similarityPercentage => '${(similarityScore * 100).toInt()}%';
}
