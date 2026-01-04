import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/recipe.dart';

/// Service for interacting with Google's Gemini AI API
class GeminiService {
  final String apiKey;
  final String _baseUrl = 'https://generativelanguage.googleapis.com/v1beta';
  final String _model = 'gemini-2.5-flash';

  GeminiService({required this.apiKey});

  /// Generate a recipe from a user's request
  ///
  /// [recipeRequest] - What the user wants to cook (e.g., "Chicken Stir Fry")
  /// [servings] - Number of servings desired
  /// [dietaryRestrictions] - Optional dietary requirements
  Future<Recipe> generateRecipe({
    required String recipeRequest,
    int servings = 4,
    List<String>? dietaryRestrictions,
  }) async {
    final prompt = _buildRecipePrompt(
      recipeRequest: recipeRequest,
      servings: servings,
      dietaryRestrictions: dietaryRestrictions,
    );

    final response = await _callGemini(prompt);
    return _parseRecipeResponse(response, recipeRequest);
  }

  /// Generate recipe suggestions based on available ingredients
  ///
  /// [availableIngredients] - List of ingredients the user has
  /// [mealType] - Optional meal type preference
  Future<List<RecipeSuggestion>> suggestRecipesFromIngredients({
    required List<String> availableIngredients,
    String? mealType,
  }) async {
    final prompt = _buildIngredientBasedPrompt(
      ingredients: availableIngredients,
      mealType: mealType,
    );

    final response = await _callGemini(prompt);
    return _parseRecipeSuggestions(response);
  }

  /// Build the prompt for recipe generation
  String _buildRecipePrompt({
    required String recipeRequest,
    required int servings,
    List<String>? dietaryRestrictions,
  }) {
    final dietaryNote =
        dietaryRestrictions != null && dietaryRestrictions.isNotEmpty
        ? '\nDietary requirements: ${dietaryRestrictions.join(', ')}'
        : '';

    return '''
You are a chef assistant helping South African home cooks. Generate a recipe based on the user's request.

Format ingredient names like grocery store products (e.g., "Chicken Breast 500g", "Soy Sauce 250ml").

User request: $recipeRequest
Servings: $servings$dietaryNote

Respond ONLY with valid JSON (no markdown, no backticks):
{
  "recipe_name": "Name",
  "recipe_description": "Brief description (1-2 sentences)",
  "servings": $servings,
  "prep_time_minutes": 15,
  "cook_time_minutes": 30,
  "total_time_minutes": 45,
  "difficulty": "Easy",
  "cuisine_type": "Cuisine",
  "meal_type": "Dinner",
  "dietary_tags": [],
  "ingredients": [
    {"name": "Product Name 500g", "quantity": 500, "unit": "g", "preparation": "diced", "is_optional": false}
  ],
  "instructions": [
    "Step 1 instruction (keep concise)",
    "Step 2 instruction"
  ]
}

IMPORTANT: Keep instructions concise (max 8 steps, 1-2 sentences each). Do not repeat ingredient names in full - just say "chicken" not "Chicken Breast 500g".
''';
  }

  /// Build prompt for ingredient-based recipe suggestions
  String _buildIngredientBasedPrompt({
    required List<String> ingredients,
    String? mealType,
  }) {
    final mealNote = mealType != null ? '\nPreferred meal type: $mealType' : '';

    return '''
You are a professional chef assistant. Based on the ingredients the user has available, suggest 3 recipes they could make.

Available ingredients: ${ingredients.join(', ')}$mealNote

Respond ONLY with a valid JSON array (no markdown, no explanation, just JSON):
[
  {
    "recipe_name": "Name of suggested dish",
    "description": "Brief description",
    "difficulty": "Easy|Medium|Hard",
    "time_minutes": 30,
    "missing_ingredients": ["ingredient1", "ingredient2"],
    "uses_ingredients": ["ingredient from user's list that this recipe uses"]
  }
]

Suggest recipes that:
1. Use as many of the available ingredients as possible
2. Require minimal additional ingredients
3. Are practical for home cooking
4. Vary in complexity and style
''';
  }

  /// Call the Gemini API
  Future<String> _callGemini(String prompt) async {
    final url = Uri.parse(
      '$_baseUrl/models/$_model:generateContent?key=$apiKey',
    );

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.7,
        'topK': 40,
        'topP': 0.95,
        'maxOutputTokens': 8192,
      },
    });

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (response.statusCode != 200) {
        debugPrint(
          'Gemini API error: ${response.statusCode} - ${response.body}',
        );
        throw GeminiException('API request failed: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      // Extract text from response
      final candidates = data['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        throw GeminiException('No response generated');
      }

      final content = candidates[0]['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List?;
      if (parts == null || parts.isEmpty) {
        throw GeminiException('Empty response from API');
      }

      final text = parts[0]['text'] as String?;
      if (text == null || text.isEmpty) {
        throw GeminiException('No text in response');
      }

      return text;
    } catch (e) {
      if (e is GeminiException) rethrow;
      debugPrint('Gemini API error: $e');
      throw GeminiException('Failed to connect to Gemini API: $e');
    }
  }

  /// Parse the recipe response from Gemini
  Recipe _parseRecipeResponse(String response, String originalPrompt) {
    try {
      // Clean up response - remove any markdown code blocks
      var cleanResponse = response.trim();
      if (cleanResponse.startsWith('```json')) {
        cleanResponse = cleanResponse.substring(7);
      } else if (cleanResponse.startsWith('```')) {
        cleanResponse = cleanResponse.substring(3);
      }
      if (cleanResponse.endsWith('```')) {
        cleanResponse = cleanResponse.substring(0, cleanResponse.length - 3);
      }
      cleanResponse = cleanResponse.trim();

      // Attempt to fix common JSON issues from malformed responses
      cleanResponse = _repairJson(cleanResponse);

      final json = jsonDecode(cleanResponse) as Map<String, dynamic>;

      // Parse ingredients
      final ingredientsList =
          (json['ingredients'] as List?)?.map((item) {
            final ing = item as Map<String, dynamic>;
            return RecipeIngredient(
              ingredientName: ing['name'] as String? ?? '',
              quantity: (ing['quantity'] as num?)?.toDouble(),
              unit: ing['unit'] as String?,
              preparation: ing['preparation'] as String?,
              isOptional: ing['is_optional'] as bool? ?? false,
            );
          }).toList() ??
          [];

      // Parse instructions
      final instructions =
          (json['instructions'] as List?)?.map((e) => e.toString()).toList() ??
          [];

      // Parse dietary tags
      final dietaryTags =
          (json['dietary_tags'] as List?)?.map((e) => e.toString()).toList() ??
          [];

      return Recipe(
        recipeName: json['recipe_name'] as String? ?? 'Generated Recipe',
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
        aiGenerated: true,
        originalPrompt: originalPrompt,
        ingredients: ingredientsList,
      );
    } catch (e) {
      debugPrint('Failed to parse recipe response: $e');
      debugPrint('Response was: $response');
      throw GeminiException('Failed to parse recipe: $e');
    }
  }

  /// Parse recipe suggestions response
  List<RecipeSuggestion> _parseRecipeSuggestions(String response) {
    try {
      // Clean up response
      var cleanResponse = response.trim();
      if (cleanResponse.startsWith('```json')) {
        cleanResponse = cleanResponse.substring(7);
      } else if (cleanResponse.startsWith('```')) {
        cleanResponse = cleanResponse.substring(3);
      }
      if (cleanResponse.endsWith('```')) {
        cleanResponse = cleanResponse.substring(0, cleanResponse.length - 3);
      }
      cleanResponse = cleanResponse.trim();

      final json = jsonDecode(cleanResponse) as List;

      return json.map((item) {
        final suggestion = item as Map<String, dynamic>;
        return RecipeSuggestion(
          recipeName: suggestion['recipe_name'] as String? ?? '',
          description: suggestion['description'] as String?,
          difficulty: suggestion['difficulty'] as String?,
          timeMinutes: suggestion['time_minutes'] as int?,
          missingIngredients:
              (suggestion['missing_ingredients'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [],
          usesIngredients:
              (suggestion['uses_ingredients'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [],
        );
      }).toList();
    } catch (e) {
      debugPrint('Failed to parse suggestions: $e');
      throw GeminiException('Failed to parse recipe suggestions: $e');
    }
  }

  /// Attempt to repair common JSON issues from Gemini responses
  String _repairJson(String json) {
    var repaired = json;

    // Fix: instructions array incorrectly closed with } instead of ]
    // The response has: "instructions": [ "step1", "step2" }
    // Should be:        "instructions": [ "step1", "step2" ]

    if (repaired.contains('"instructions"') &&
        repaired.trimRight().endsWith('}')) {
      // Count brackets after "instructions"
      int lastInstructionsIndex = repaired.lastIndexOf('"instructions"');
      String afterInstructions = repaired.substring(lastInstructionsIndex);

      int openBrackets = '['.allMatches(afterInstructions).length;
      int closeBrackets = ']'.allMatches(afterInstructions).length;

      if (openBrackets > closeBrackets) {
        // Find the last } and check if we need to change it to ]
        int lastBraceIndex = repaired.lastIndexOf('}');
        int secondLastBraceIndex = repaired.lastIndexOf(
          '}',
          lastBraceIndex - 1,
        );

        if (secondLastBraceIndex > 0) {
          // Replace the second-to-last } with ] (closing the instructions array)
          repaired =
              repaired.substring(0, secondLastBraceIndex) +
              ']' +
              repaired.substring(secondLastBraceIndex + 1);
        }
      }
    }

    // If JSON doesn't end with }, try to close it
    if (!repaired.trimRight().endsWith('}')) {
      int openBraces = '{'.allMatches(repaired).length;
      int closeBraces = '}'.allMatches(repaired).length;
      int openBrackets = '['.allMatches(repaired).length;
      int closeBrackets = ']'.allMatches(repaired).length;

      String suffix = '';
      for (int i = 0; i < openBrackets - closeBrackets; i++) {
        suffix += ']';
      }
      for (int i = 0; i < openBraces - closeBraces; i++) {
        suffix += '}';
      }

      repaired += suffix;
    }

    // Fix trailing comma before closing bracket/brace
    repaired = repaired.replaceAll(RegExp(r',(\s*[\]\}])'), r'$1');

    return repaired;
  }
}

/// Recipe suggestion from ingredient-based generation
class RecipeSuggestion {
  final String recipeName;
  final String? description;
  final String? difficulty;
  final int? timeMinutes;
  final List<String> missingIngredients;
  final List<String> usesIngredients;

  RecipeSuggestion({
    required this.recipeName,
    this.description,
    this.difficulty,
    this.timeMinutes,
    this.missingIngredients = const [],
    this.usesIngredients = const [],
  });

  String get formattedTime {
    if (timeMinutes == null) return '';
    if (timeMinutes! < 60) return '${timeMinutes}min';
    final hours = timeMinutes! ~/ 60;
    final minutes = timeMinutes! % 60;
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}min';
  }

  bool get hasAllIngredients => missingIngredients.isEmpty;
}

/// Custom exception for Gemini API errors
class GeminiException implements Exception {
  final String message;
  GeminiException(this.message);

  @override
  String toString() => 'GeminiException: $message';
}
