import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/live_api_config.dart';
import '../models/recipe.dart';

/// Service for interacting with Google's Gemini AI via Edge Function proxy.
///
/// The Gemini API key is stored server-side as a Supabase Edge Function secret.
/// This service sends prompts to the `gemini-proxy` Edge Function, which
/// forwards them to the Gemini API.
class GeminiService {
  GeminiService();

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

Format ingredient names EXACTLY as they appear on South African grocery store shelves.
Use common SA product names, not cooking terms. Examples:
- "Large Eggs" not "beaten eggs" (unit: "units", not "each")
- "Full Cream Milk" not "whole milk"
- "Sunflower Oil" or "Vegetable Oil" not "cooking oil"
- "Table Salt" not "pinch of salt"
- "Cake Flour" or "Self Raising Flour" not just "flour"
- "Unsalted Butter" not "melted butter"
- "Baking Powder" (unit: "g", not "ml" — it's a powder)
- "Caster Sugar" or "White Sugar" (unit: "g")
- "Ground Cinnamon" (unit: "g", not "ml")

CRITICAL: NEVER output single-word ingredient names. Always qualify:
- "Sunflower Oil" or "Olive Oil" not "Oil"
- "Large Eggs" not "Eggs"
- "White Sugar" or "Caster Sugar" not "Sugar"
- "Table Salt" not "Salt"
- "Long Grain Rice" or "Basmati Rice" not "Rice"
- "Unsalted Butter" or "Salted Butter" not "Butter"
- "Full Cream Milk" not "Milk"
- "Black Pepper" not "Pepper"
- "Fresh Cream" not "Cream"
- "Cake Flour" not "Flour"

SA-specific terms (use these, not international equivalents):
- "Maize Meal" not "Cornmeal" or "Polenta"
- "Beef Mince" not "Ground Beef"
- "Chicken Stock" not "Chicken Broth"
- "Tinned Tomatoes" or "Chopped Tomatoes" not "Canned Tomatoes"
- "Tomato Paste" not "Tomato Puree"
- "Mixed Herbs" not "Italian Seasoning"
- "Spaghetti" or "Penne" not just "Pasta" (specify the shape)
- "Vanilla Essence" not "Vanilla Extract"
- "Cornflour" or "Maizena Cornflour" not "Corn Starch"
- "Spring Onions" not "Scallions" or "Green Onions"
- "Crushed Garlic" or "Garlic" not "Garlic Paste" (SA stores sell crushed, not paste)
- "Crushed Ginger" or "Ginger" not "Ginger Paste" (SA stores sell crushed, not paste)
- "Cardamom" or "Green Cardamom" not "Cardamom Pods"

Valid units: "g", "kg", "ml", "l", "units" (for countable items like eggs).
Do NOT include quantities or sizes in the name field — put quantity in "quantity" and unit in "unit".
Do NOT include preparation (diced, melted, beaten, sifted, skinned, deboned) in the name — put it in "preparation".
Keep ingredient names SHORT — just the core product name as you'd search for it in a store.
Good: "Hake Fillets", "Stir Fry Vegetables", "Sesame Seeds"
Bad: "skinned and deboned Hake Fillets", "pre-cut Mixed Stir-fry Vegetables"

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
    {"name": "Chicken Breast", "quantity": 500, "unit": "g", "preparation": "diced", "is_optional": false}
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

  /// Call Gemini via the gemini-proxy Edge Function
  Future<String> _callGemini(
    String prompt, {
    double temperature = 0.7,
    int maxOutputTokens = 8192,
  }) async {
    final url = Uri.parse(
      LiveApiConfig.edgeFunctionUrl('gemini-proxy'),
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
        'temperature': temperature,
        'topK': 40,
        'topP': 0.95,
        'maxOutputTokens': maxOutputTokens,
      },
    });

    try {
      final response = await http
          .post(url, headers: LiveApiConfig.headers, body: body)
          .timeout(
            const Duration(seconds: 90), // 60s Gemini + 30s Edge Function buffer
            onTimeout: () {
              throw GeminiException(
                'Request timed out',
                statusCode: 408,
                isRetryable: true,
              );
            },
          );

      if (response.statusCode != 200) {
        debugPrint(
          'Gemini proxy error: ${response.statusCode} - ${response.body}',
        );

        // Parse the error response to get details
        try {
          final errorBody = jsonDecode(response.body) as Map<String, dynamic>;
          final error = errorBody['error'];

          // Edge Function proxy returns { error: "message" } as a string
          // Gemini API returns { error: { message, status } } as an object
          if (error is String) {
            throw GeminiException(
              error,
              statusCode: response.statusCode,
              isRetryable: response.statusCode >= 500 ||
                  response.statusCode == 429 ||
                  response.statusCode == 504,
            );
          }

          final errorMap = error as Map<String, dynamic>?;
          final status = errorMap?['status'] as String?;

          throw GeminiException(
            errorMap?['message'] as String? ?? 'API request failed',
            statusCode: response.statusCode,
            status: status,
            isRetryable:
                response.statusCode >= 500 ||
                response.statusCode == 429 ||
                status == 'UNAVAILABLE' ||
                status == 'RESOURCE_EXHAUSTED',
          );
        } catch (e) {
          if (e is GeminiException) rethrow;
          throw GeminiException(
            'API request failed: ${response.statusCode}',
            statusCode: response.statusCode,
            isRetryable: response.statusCode >= 500,
          );
        }
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      // Extract text from response
      final candidates = data['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        // Check for blocked content
        final blockReason = data['promptFeedback']?['blockReason'];
        if (blockReason != null) {
          throw GeminiException(
            'Content was blocked: $blockReason',
            status: 'BLOCKED',
            isRetryable: false,
          );
        }
        throw GeminiException('No response generated', isRetryable: true);
      }

      final content = candidates[0]['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List?;
      if (parts == null || parts.isEmpty) {
        throw GeminiException('Empty response from API', isRetryable: true);
      }

      final text = parts[0]['text'] as String?;
      if (text == null || text.isEmpty) {
        throw GeminiException('No text in response', isRetryable: true);
      }

      return text;
    } on GeminiException {
      rethrow;
    } on http.ClientException catch (e) {
      debugPrint('Network error: $e');
      throw GeminiException('Network error: ${e.message}', isRetryable: true);
    } catch (e) {
      if (e is GeminiException) rethrow;
      debugPrint('Gemini proxy error: $e');
      throw GeminiException('Failed to connect to AI service: $e');
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
      if (e is GeminiException) rethrow;
      debugPrint('Failed to parse recipe response: $e');
      debugPrint('Response was: $response');
      throw GeminiException('Failed to parse recipe', isRetryable: true);
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
      if (e is GeminiException) rethrow;
      debugPrint('Failed to parse suggestions: $e');
      throw GeminiException('Failed to parse suggestions', isRetryable: true);
    }
  }

  // ===========================================================================
  // PRODUCT MATCHING
  // ===========================================================================

  /// Evaluate product matches using AI when algorithm confidence is low.
  ///
  /// Sends source product + candidates from multiple retailers to Gemini
  /// and returns confidence scores for each candidate.
  Future<List<GeminiMatchResult>> evaluateProductMatches({
    required String sourceProductName,
    required String sourceRetailer,
    required String sourcePrice,
    required Map<String, List<({int index, String name, String price})>>
        candidatesByRetailer,
  }) async {
    final prompt = _buildMatchingPrompt(
      sourceProductName: sourceProductName,
      sourceRetailer: sourceRetailer,
      sourcePrice: sourcePrice,
      candidatesByRetailer: candidatesByRetailer,
    );

    final response = await _callGemini(
      prompt,
      temperature: 0.3,
      maxOutputTokens: 2048,
    );

    return _parseMatchingResponse(response);
  }

  /// Build the product matching prompt for Gemini.
  String _buildMatchingPrompt({
    required String sourceProductName,
    required String sourceRetailer,
    required String sourcePrice,
    required Map<String, List<({int index, String name, String price})>>
        candidatesByRetailer,
  }) {
    final candidatesBlock = StringBuffer();
    for (final entry in candidatesByRetailer.entries) {
      candidatesBlock.writeln('--- ${entry.key} ---');
      for (final c in entry.value) {
        candidatesBlock.writeln('${c.index}. "${c.name}" - ${c.price}');
      }
    }

    return '''
You are a South African grocery product matching assistant. Given a source product and candidates from other retailers, determine which candidates are the SAME product.

Key SA grocery rules:
- "2L" = "2 Litre" = "2000ml" (same size, different naming)
- "Full Cream" and "Low Fat" are DIFFERENT products
- Store brands (PnP, Woolworths, Checkers Housebrand, No Name, Ritebrand) are NEVER the same as named brands (Clover, Parmalat, Albany, etc.)
- Different sizes are DIFFERENT products (500ml is not 1L)
- Ignore minor naming differences: "Koo Baked Beans in Tomato Sauce 410g" = "KOO Baked Beans In Tomato 410g"
- Multi-packs: "6x200ml" = "6 x 200ml" (same thing)

SOURCE PRODUCT:
"$sourceProductName" from $sourceRetailer at $sourcePrice

CANDIDATES:
$candidatesBlock

For each candidate, respond ONLY with a JSON array (no markdown, no explanation):
[
  {"index": 1, "retailer": "Retailer Name", "confidence": 0.85, "reason": "Same brand, size, variant"}
]

Confidence guide:
- 0.8-1.0: Same product, just different naming/formatting
- 0.5-0.79: Similar product but different variant or size
- 0.0-0.49: Different product entirely
''';
  }

  /// Parse the matching response from Gemini.
  List<GeminiMatchResult> _parseMatchingResponse(String response) {
    try {
      var clean = response.trim();
      if (clean.startsWith('```json')) clean = clean.substring(7);
      if (clean.startsWith('```')) clean = clean.substring(3);
      if (clean.endsWith('```')) {
        clean = clean.substring(0, clean.length - 3);
      }
      clean = clean.trim();

      // Fix trailing commas
      clean = clean.replaceAll(RegExp(r',(\s*[\]\}])'), r'$1');

      final list = jsonDecode(clean) as List;
      return list.map((item) {
        final m = item as Map<String, dynamic>;
        return GeminiMatchResult(
          candidateIndex: m['index'] as int? ?? 0,
          retailer: m['retailer'] as String? ?? '',
          confidence: (m['confidence'] as num?)?.toDouble() ?? 0.0,
          reason: m['reason'] as String? ?? '',
        );
      }).toList();
    } catch (e) {
      debugPrint('Failed to parse matching response: $e');
      debugPrint('Response was: $response');
      return [];
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

/// Result from Gemini product match evaluation.
class GeminiMatchResult {
  final int candidateIndex;
  final String retailer;
  final double confidence;
  final String reason;

  const GeminiMatchResult({
    required this.candidateIndex,
    required this.retailer,
    required this.confidence,
    required this.reason,
  });

  @override
  String toString() =>
      'GeminiMatch(#$candidateIndex $retailer: $confidence - $reason)';
}

/// Custom exception for Gemini API errors
class GeminiException implements Exception {
  final String message;
  final int? statusCode;
  final String? status;
  final bool isRetryable;

  GeminiException(
    this.message, {
    this.statusCode,
    this.status,
    this.isRetryable = false,
  });

  /// Get a user-friendly error message for display in UI
  String get userFriendlyMessage {
    // Service unavailable / overloaded (503)
    if (statusCode == 503 || status == 'UNAVAILABLE') {
      return 'Our AI service is currently experiencing high demand. Please try again in a few moments.';
    }

    // Rate limited (429)
    if (statusCode == 429 || status == 'RESOURCE_EXHAUSTED') {
      return 'You\'ve made too many requests. Please wait a moment before trying again.';
    }

    // Server error (5xx)
    if (statusCode != null && statusCode! >= 500) {
      return 'Our AI service is temporarily unavailable. Please try again later.';
    }

    // API key / Authentication error (check message content for API key issues)
    if (statusCode == 401 ||
        statusCode == 403 ||
        message.toLowerCase().contains('api key')) {
      return 'There was an authentication error with the AI service. Please contact support if this persists.';
    }

    // Invalid request (400) - but not API key related
    if (statusCode == 400 || status == 'INVALID_ARGUMENT') {
      return 'There was a problem with your request. Please try a different recipe description.';
    }

    // Content blocked
    if (status == 'BLOCKED') {
      return 'This request couldn\'t be processed. Please try a different recipe description.';
    }

    // Network/timeout
    if (message.toLowerCase().contains('timeout') ||
        message.toLowerCase().contains('network')) {
      return 'Connection failed. Please check your internet and try again.';
    }

    // Parse error
    if (message.toLowerCase().contains('parse')) {
      return 'We had trouble understanding the AI response. Please try again.';
    }

    // Default fallback
    return 'Something went wrong. Please try again.';
  }

  /// Short title for error dialogs
  String get errorTitle {
    if (statusCode == 503 || status == 'UNAVAILABLE') {
      return 'AI Service Busy';
    }
    if (statusCode == 429 || status == 'RESOURCE_EXHAUSTED') {
      return 'Too Many Requests';
    }
    if (statusCode != null && statusCode! >= 500) {
      return 'Service Unavailable';
    }
    if (statusCode == 401 ||
        statusCode == 403 ||
        message.toLowerCase().contains('api key')) {
      return 'Authentication Error';
    }
    if (status == 'BLOCKED') {
      return 'Request Blocked';
    }
    return 'Request Failed';
  }

  @override
  String toString() =>
      'GeminiException: $message (status: $statusCode, $status)';
}
