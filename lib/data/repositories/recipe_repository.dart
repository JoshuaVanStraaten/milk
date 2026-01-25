import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/recipe.dart';

/// Repository for recipe-related database operations
/// Updated to support province-based filtering for ingredient matching
class RecipeRepository {
  final SupabaseClient _supabase;

  RecipeRepository(this._supabase);

  /// Save a recipe to the database
  Future<Recipe> saveRecipe(Recipe recipe) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Insert the recipe
      final recipeData = recipe.toJson();
      recipeData['user_id'] = userId;

      final recipeResponse = await _supabase
          .from('Recipes_Overview')
          .insert(recipeData)
          .select()
          .single();

      final savedRecipe = Recipe.fromJson(recipeResponse);
      final recipeId = savedRecipe.recipeId!;

      // Insert ingredients
      if (recipe.ingredients.isNotEmpty) {
        final ingredientsData = recipe.ingredients.asMap().entries.map((entry) {
          final ingredient = entry.value;
          final data = ingredient.toJson();
          data['recipe_id'] = recipeId;
          data['display_order'] = entry.key;
          return data;
        }).toList();

        await _supabase.from('Recipe_Ingredients').insert(ingredientsData);
      }

      // Fetch the complete recipe with ingredients
      return await getRecipeById(recipeId);
    } catch (e) {
      debugPrint('Error saving recipe: $e');
      throw Exception('Failed to save recipe: $e');
    }
  }

  /// Get a recipe by ID with its ingredients
  Future<Recipe> getRecipeById(String recipeId) async {
    try {
      final response = await _supabase
          .from('Recipes_Overview')
          .select('''
            *,
            Recipe_Ingredients (*)
          ''')
          .eq('recipe_id', recipeId)
          .single();

      return Recipe.fromJson(response);
    } catch (e) {
      debugPrint('Error fetching recipe: $e');
      throw Exception('Failed to fetch recipe: $e');
    }
  }

  /// Get all recipes for the current user
  Future<List<Recipe>> getUserRecipes() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final response = await _supabase
          .from('Recipes_Overview')
          .select('''
            *,
            Recipe_Ingredients (*)
          ''')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => Recipe.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error fetching user recipes: $e');
      throw Exception('Failed to fetch recipes: $e');
    }
  }

  /// Delete a recipe
  Future<void> deleteRecipe(String recipeId) async {
    try {
      // Ingredients will be cascade deleted due to FK constraint
      await _supabase
          .from('Recipes_Overview')
          .delete()
          .eq('recipe_id', recipeId);
    } catch (e) {
      debugPrint('Error deleting recipe: $e');
      throw Exception('Failed to delete recipe: $e');
    }
  }

  /// Update ingredient with matched product
  Future<void> updateIngredientMatch({
    required String ingredientId,
    required String productIndex,
    required String productName,
    required double productPrice,
    required String retailer,
  }) async {
    try {
      await _supabase
          .from('Recipe_Ingredients')
          .update({
            'matched_product_index': productIndex,
            'matched_product_name': productName,
            'matched_product_price': productPrice,
            'matched_retailer': retailer,
          })
          .eq('ingredient_id', ingredientId);
    } catch (e) {
      debugPrint('Error updating ingredient match: $e');
      throw Exception('Failed to update ingredient match: $e');
    }
  }

  /// Clear ingredient product match
  Future<void> clearIngredientMatch(String ingredientId) async {
    try {
      await _supabase
          .from('Recipe_Ingredients')
          .update({
            'matched_product_index': null,
            'matched_product_name': null,
            'matched_product_price': null,
            'matched_retailer': null,
          })
          .eq('ingredient_id', ingredientId);
    } catch (e) {
      debugPrint('Error clearing ingredient match: $e');
      throw Exception('Failed to clear ingredient match: $e');
    }
  }

  /// Find matching products for an ingredient
  ///
  /// [ingredientName]: The ingredient to search for
  /// [province]: Province to filter by (required)
  /// [retailer]: Optional - filter by specific retailer
  /// [maxResults]: Maximum number of results to return
  Future<List<IngredientProductMatch>> findMatchingProducts({
    required String ingredientName,
    required String province,
    String? retailer,
    int maxResults = 10,
  }) async {
    try {
      // Convert empty string to null for proper SQL handling
      final targetRetailer = (retailer == null || retailer.isEmpty)
          ? null
          : retailer;

      final response = await _supabase.rpc(
        'find_matching_products_for_ingredient',
        params: {
          'ingredient_search': ingredientName,
          'target_province': province,
          'target_retailer': targetRetailer,
          'similarity_threshold': 0.3,
          'max_results': maxResults,
        },
      );

      return (response as List)
          .map(
            (json) =>
                IngredientProductMatch.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } catch (e) {
      debugPrint('Error finding matching products: $e');
      // Return empty list instead of throwing - allows graceful handling
      return [];
    }
  }

  /// Export recipe ingredients to a shopping list
  ///
  /// [recipe]: The recipe to export
  /// [listName]: Name for the shopping list
  /// [storeName]: Store name for the list
  Future<String> exportToShoppingList({
    required Recipe recipe,
    required String listName,
    required String storeName,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Calculate total price from matched ingredients
      final totalPrice = recipe.ingredients
          .where((i) => i.matchedProductPrice != null)
          .fold(0.0, (sum, i) => sum + i.matchedProductPrice!);

      // Create the shopping list
      final listResponse = await _supabase
          .from('Shopping_List_Overview')
          .insert({
            'id': userId,
            'list_name': listName,
            'store_name': storeName,
            'total_price': totalPrice,
            'completed_list': false,
            'created_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      final listId = listResponse['ShoppingList_ID'] as String;

      // Add ingredients as list items
      final items = recipe.ingredients.map((ingredient) {
        // Extract price from matched product
        double? price;
        if (ingredient.matchedProductPrice != null) {
          price = ingredient.matchedProductPrice;
        }

        // Build a note that includes the recipe quantity and preparation
        String? note;
        final parts = <String>[];
        if (ingredient.quantity != null && ingredient.unit != null) {
          parts.add('Need: ${ingredient.quantity}${ingredient.unit}');
        }
        if (ingredient.preparation != null &&
            ingredient.preparation!.isNotEmpty) {
          parts.add(ingredient.preparation!);
        }
        if (parts.isNotEmpty) {
          note = parts.join(' - ');
        }

        // Determine retailer: matched retailer, or "Custom Items" for unmatched
        final itemRetailer = ingredient.matchedRetailer ?? 'Custom Items';

        return {
          'ShoppingList_ID': listId,
          'Item_Name':
              ingredient.matchedProductName ?? ingredient.ingredientName,
          'Completed_Item': false,
          'Item_Quantity':
              1, // Always 1 product, note contains recipe amount needed
          'Item_Price': price,
          'item_retailer': itemRetailer,
          'Item_Note': note,
          'item_total_price': price,
          'created_at': DateTime.now().toIso8601String(),
        };
      }).toList();

      if (items.isNotEmpty) {
        await _supabase.from('Shopping_List_Item_Level').insert(items);
      }

      return listId;
    } catch (e) {
      debugPrint('Error exporting to shopping list: $e');
      throw Exception('Failed to export to shopping list: $e');
    }
  }
}
