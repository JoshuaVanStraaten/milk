class IngredientSearchHint {
  /// Optimized search term to send to the retailer API.
  final String searchQuery;

  /// Product name must contain at least one of these words (lowercased).
  /// Empty means no positive filter.
  final Set<String> requiredWords;

  /// Disqualify candidate if product name contains any of these (lowercased).
  final Set<String> excludeWords;

  const IngredientSearchHint({
    required this.searchQuery,
    this.requiredWords = const {},
    this.excludeWords = const {},
  });
}

class IngredientLookup {
  IngredientLookup._();

  /// Resolve an ingredient name to a search hint.
  ///
  /// Tries exact match first, then longest partial key match.
  /// Returns null if no match found (falls back to existing behavior).
  static IngredientSearchHint? resolve(String ingredientName) {
    final lower = ingredientName.toLowerCase().trim();
    if (lower.isEmpty) return null;

    // 1. Exact match
    if (_lookupMap.containsKey(lower)) return _lookupMap[lower];

    // 2. Longest key that is contained in the ingredient name
    IngredientSearchHint? bestHint;
    int bestLength = 0;
    for (final entry in _lookupMap.entries) {
      if (lower.contains(entry.key) && entry.key.length > bestLength) {
        bestHint = entry.value;
        bestLength = entry.key.length;
      }
    }
    if (bestHint != null) return bestHint;

    // 3. Longest key where the ingredient is contained in the key
    //    e.g. ingredient "cream" matches key "fresh cream"
    for (final entry in _lookupMap.entries) {
      if (entry.key.contains(lower) && entry.key.length > bestLength) {
        bestHint = entry.value;
        bestLength = entry.key.length;
      }
    }

    return bestHint;
  }

  // ---------------------------------------------------------------------------
  // LOOKUP MAP — ~100 common SA recipe ingredients
  // ---------------------------------------------------------------------------
  // Built from analysis of 42K products across PnP, Woolworths, Checkers,
  // Shoprite. Search queries are optimized for what the retailer APIs actually
  // return. Exclude words prevent noise from non-food or processed products.
  // ---------------------------------------------------------------------------

  static const Map<String, IngredientSearchHint> _lookupMap = {
    // =========================================================================
    // DAIRY
    // =========================================================================
    'butter': IngredientSearchHint(
      searchQuery: 'butter 500g',
      requiredWords: {'butter'},
      excludeWords: {
        'chicken', 'peanut', 'almond', 'cashew', 'biscuit', 'popcorn',
        'cookie', 'naan', 'shortbread', 'scone', 'croissant', 'palmier',
        'danish', 'straw', 'lettuce', 'baste', 'flavour',
      },
    ),
    'unsalted butter': IngredientSearchHint(
      searchQuery: 'unsalted butter',
      requiredWords: {'butter'},
      excludeWords: {
        'chicken', 'peanut', 'almond', 'biscuit', 'popcorn', 'cookie',
      },
    ),
    'salted butter': IngredientSearchHint(
      searchQuery: 'salted butter',
      requiredWords: {'butter'},
      excludeWords: {
        'chicken', 'peanut', 'almond', 'biscuit', 'popcorn', 'cookie',
      },
    ),
    'milk': IngredientSearchHint(
      searchQuery: 'full cream milk',
      requiredWords: {'milk'},
      excludeWords: {
        'chocolate', 'teeth', 'toothbrush', 'toothpaste', 'bath', 'lotion',
        'shampoo', 'conditioner', 'biscuit', 'cereal', 'beacon', 'slab',
        'bar', 'sweet', 'milkshake', 'powder', 'baby',
      },
    ),
    'full cream milk': IngredientSearchHint(
      searchQuery: 'full cream milk',
      requiredWords: {'milk'},
      excludeWords: {
        'chocolate', 'teeth', 'toothbrush', 'bath', 'lotion', 'biscuit',
        'beacon', 'slab', 'sweet', 'milkshake', 'powder',
      },
    ),
    'low fat milk': IngredientSearchHint(
      searchQuery: 'low fat milk',
      requiredWords: {'milk'},
      excludeWords: {
        'chocolate', 'teeth', 'bath', 'biscuit', 'sweet', 'milkshake',
      },
    ),
    'buttermilk': IngredientSearchHint(
      searchQuery: 'buttermilk',
      requiredWords: {'buttermilk'},
      excludeWords: {'rusk', 'biscuit'},
    ),
    'cream': IngredientSearchHint(
      searchQuery: 'fresh cream 250ml',
      requiredWords: {'cream'},
      excludeWords: {
        'ice', 'biscuit', 'cake', 'lotion', 'hand', 'body', 'face',
        'cheese', 'soda', 'cracker', 'rice', 'chip', 'liqueur', 'condensed',
        'honey', 'soup', 'pasta', 'moistur',
      },
    ),
    'fresh cream': IngredientSearchHint(
      searchQuery: 'fresh cream',
      requiredWords: {'cream'},
      excludeWords: {
        'ice', 'biscuit', 'cake', 'lotion', 'hand', 'cheese', 'soda',
        'cracker', 'liqueur', 'soup', 'moistur',
      },
    ),
    'sour cream': IngredientSearchHint(
      searchQuery: 'sour cream',
      requiredWords: {'sour', 'cream'},
      excludeWords: {'chip', 'crisp', 'dip'},
    ),
    'cream cheese': IngredientSearchHint(
      searchQuery: 'cream cheese',
      requiredWords: {'cream', 'cheese'},
      excludeWords: {'cake', 'rice', 'cracker'},
    ),
    'cheese': IngredientSearchHint(
      searchQuery: 'cheddar cheese',
      requiredWords: {'cheese'},
      excludeWords: {
        'cake', 'biscuit', 'cracker', 'straw', 'scone', 'pizza',
        'burger', 'toastie', 'sandwich', 'quiche',
      },
    ),
    'cheddar cheese': IngredientSearchHint(
      searchQuery: 'cheddar cheese',
      requiredWords: {'cheddar', 'cheese'},
      excludeWords: {'cake', 'biscuit', 'cracker'},
    ),
    'mozzarella': IngredientSearchHint(
      searchQuery: 'mozzarella cheese',
      requiredWords: {'mozzarella'},
      excludeWords: {'pizza', 'burger', 'sandwich'},
    ),
    'parmesan': IngredientSearchHint(
      searchQuery: 'parmesan cheese',
      requiredWords: {'parmesan'},
      excludeWords: {'crisp', 'cracker'},
    ),
    'feta': IngredientSearchHint(
      searchQuery: 'feta cheese',
      requiredWords: {'feta'},
      excludeWords: {'salad', 'pizza', 'quiche', 'pie'},
    ),
    'yoghurt': IngredientSearchHint(
      searchQuery: 'plain yoghurt',
      requiredWords: {'yoghurt', 'yogurt'},
      excludeWords: {'coating', 'rice', 'bar', 'muesli'},
    ),

    // =========================================================================
    // EGGS
    // =========================================================================
    'eggs': IngredientSearchHint(
      searchQuery: 'large eggs 6',
      requiredWords: {'egg'},
      excludeWords: {
        'chocolate', 'mallow', 'noodle', 'custard', 'candy', 'speckled',
        'foil', 'hollow', 'cadbury', 'mini egg', 'easter', 'galore',
      },
    ),
    'large eggs': IngredientSearchHint(
      searchQuery: 'large eggs 6',
      requiredWords: {'egg'},
      excludeWords: {
        'chocolate', 'mallow', 'noodle', 'candy', 'speckled', 'hollow',
        'cadbury', 'galore',
      },
    ),

    // =========================================================================
    // MEAT & POULTRY
    // =========================================================================
    'chicken breast': IngredientSearchHint(
      searchQuery: 'chicken breast fillet',
      requiredWords: {'chicken', 'breast'},
      excludeWords: {'mozzarella', 'topped', 'stuffed', 'crumbed', 'kiev'},
    ),
    'chicken thigh': IngredientSearchHint(
      searchQuery: 'chicken thigh',
      requiredWords: {'chicken', 'thigh'},
      excludeWords: {'kebab', 'marinated', 'bbq'},
    ),
    'chicken drumstick': IngredientSearchHint(
      searchQuery: 'chicken drumsticks',
      requiredWords: {'chicken', 'drumstick'},
      excludeWords: {'marinated', 'bbq'},
    ),
    'whole chicken': IngredientSearchHint(
      searchQuery: 'whole chicken',
      requiredWords: {'chicken', 'whole'},
      excludeWords: {'pie', 'soup', 'stock'},
    ),
    'chicken wings': IngredientSearchHint(
      searchQuery: 'chicken wings',
      requiredWords: {'chicken', 'wing'},
      excludeWords: {'sauce', 'buffalo', 'marinated'},
    ),
    'beef mince': IngredientSearchHint(
      searchQuery: 'beef mince',
      requiredWords: {'mince', 'beef'},
      excludeWords: {'curry', 'vetkoek', 'roti', 'pie', 'lasagne', 'sauce'},
    ),
    'lamb chops': IngredientSearchHint(
      searchQuery: 'lamb chops',
      requiredWords: {'lamb', 'chop'},
      excludeWords: {'sauce', 'curry', 'pie'},
    ),
    'lamb': IngredientSearchHint(
      searchQuery: 'lamb leg',
      requiredWords: {'lamb'},
      excludeWords: {
        'curry', 'pie', 'casserole', 'baby food', 'babes', 'sauce',
        'samosa', 'kebab',
      },
    ),
    'pork chops': IngredientSearchHint(
      searchQuery: 'pork chops',
      requiredWords: {'pork', 'chop'},
      excludeWords: {'sauce', 'bbq', 'marinated'},
    ),
    'bacon': IngredientSearchHint(
      searchQuery: 'back bacon',
      requiredWords: {'bacon'},
      excludeWords: {
        'pizza', 'burger', 'sandwich', 'toastie', 'quiche', 'pasta',
        'salad', 'biltong', 'flavour', 'chip', 'crisp',
      },
    ),
    'sausage': IngredientSearchHint(
      searchQuery: 'pork sausage',
      requiredWords: {'sausage'},
      excludeWords: {'roll', 'pizza', 'pasta', 'casserole'},
    ),
    'stewing beef': IngredientSearchHint(
      searchQuery: 'stewing beef',
      requiredWords: {'stew', 'beef'},
      excludeWords: {'sauce', 'pie', 'ready'},
    ),

    // =========================================================================
    // SEAFOOD
    // =========================================================================
    'hake fillets': IngredientSearchHint(
      searchQuery: 'hake fillets',
      requiredWords: {'hake'},
      excludeWords: {'battered', 'crumbed', 'finger'},
    ),
    'salmon': IngredientSearchHint(
      searchQuery: 'salmon fillet',
      requiredWords: {'salmon'},
      excludeWords: {'tinned', 'canned', 'brine', 'smoked'},
    ),
    'tinned salmon': IngredientSearchHint(
      searchQuery: 'salmon in brine',
      requiredWords: {'salmon'},
      excludeWords: {'fillet', 'fresh', 'frozen'},
    ),
    'prawns': IngredientSearchHint(
      searchQuery: 'prawns frozen',
      requiredWords: {'prawn'},
      excludeWords: {'cracker', 'chip', 'flavour'},
    ),
    'tinned tuna': IngredientSearchHint(
      searchQuery: 'tuna in brine',
      requiredWords: {'tuna'},
      excludeWords: {'steak', 'fresh', 'frozen'},
    ),

    // =========================================================================
    // PRODUCE — VEGETABLES
    // =========================================================================
    'onion': IngredientSearchHint(
      searchQuery: 'onions',
      requiredWords: {'onion'},
      excludeWords: {
        'soup', 'sauce', 'gravy', 'dip', 'ring', 'flavour', 'powder',
        'flake', 'quiche', 'couscous', 'kebab',
      },
    ),
    'onions': IngredientSearchHint(
      searchQuery: 'onions',
      requiredWords: {'onion'},
      excludeWords: {
        'soup', 'sauce', 'gravy', 'dip', 'ring', 'flavour', 'powder',
        'flake', 'quiche', 'couscous', 'kebab',
      },
    ),
    'red onion': IngredientSearchHint(
      searchQuery: 'red onions',
      requiredWords: {'onion'},
      excludeWords: {'soup', 'sauce', 'gravy', 'dip', 'ring', 'flavour'},
    ),
    'spring onions': IngredientSearchHint(
      searchQuery: 'spring onions',
      requiredWords: {'spring', 'onion'},
      excludeWords: {
        'cracker', 'flavour', 'chip', 'crisp', 'dip', 'pizza', 'cheese',
        'chicken', 'cream', 'sauce',
      },
    ),
    'spring onion': IngredientSearchHint(
      searchQuery: 'spring onions',
      requiredWords: {'spring', 'onion'},
      excludeWords: {
        'cracker', 'flavour', 'chip', 'crisp', 'dip', 'pizza', 'cheese',
        'chicken', 'cream', 'sauce',
      },
    ),
    'garlic paste': IngredientSearchHint(
      searchQuery: 'garlic paste',
      requiredWords: {'garlic'},
      excludeWords: {'olive', 'stuffed'},
    ),
    'ginger paste': IngredientSearchHint(
      searchQuery: 'ginger paste',
      requiredWords: {'ginger'},
      excludeWords: {'tea', 'biscuit', 'ale', 'beer', 'drink'},
    ),
    'crushed garlic': IngredientSearchHint(
      searchQuery: 'crushed garlic',
      requiredWords: {'garlic'},
      excludeWords: {'bread', 'butter', 'naan', 'pizza'},
    ),
    'crushed ginger': IngredientSearchHint(
      searchQuery: 'crushed ginger',
      requiredWords: {'ginger'},
      excludeWords: {'tea', 'biscuit', 'ale', 'beer'},
    ),
    'garlic': IngredientSearchHint(
      searchQuery: 'garlic',
      requiredWords: {'garlic'},
      excludeWords: {
        'sauce', 'bread', 'butter', 'flavour', 'bruschetta', 'naan',
        'mash', 'quinoa', 'couscous', 'herb', 'seasoning', 'grind',
        'paste', 'pizza', 'wrap',
      },
    ),
    'ginger': IngredientSearchHint(
      searchQuery: 'ginger',
      requiredWords: {'ginger'},
      excludeWords: {
        'ale', 'beer', 'drink', 'syrup', 'tea', 'biscuit', 'cookie',
        'shortbread', 'cake', 'juice', 'sparkling', 'infusion',
      },
    ),
    'potatoes': IngredientSearchHint(
      searchQuery: 'potatoes',
      requiredWords: {'potato'},
      excludeWords: {
        'chip', 'crisp', 'bake', 'soup', 'salad', 'mash', 'croquette',
        'wedge', 'fry', 'hash', 'gratin',
      },
    ),
    'carrots': IngredientSearchHint(
      searchQuery: 'carrots',
      requiredWords: {'carrot'},
      excludeWords: {
        'cake', 'rusk', 'soup', 'juice', 'batons', 'baby food',
      },
    ),
    'tomatoes': IngredientSearchHint(
      searchQuery: 'tomatoes',
      requiredWords: {'tomato'},
      excludeWords: {
        'sauce', 'paste', 'soup', 'puree', 'juice', 'ketchup', 'relish',
        'chutney', 'pizza', 'preserve', 'sundried', 'dried',
      },
    ),
    'spinach': IngredientSearchHint(
      searchQuery: 'baby spinach',
      requiredWords: {'spinach'},
      excludeWords: {
        'pie', 'quiche', 'juice', 'smoothie', 'babes', 'baby food',
        'sauce', 'pasta',
      },
    ),
    'broccoli': IngredientSearchHint(
      searchQuery: 'broccoli',
      requiredWords: {'broccoli'},
      excludeWords: {'sauce', 'baby food', 'babes', 'soup'},
    ),
    'mushrooms': IngredientSearchHint(
      searchQuery: 'mushrooms',
      requiredWords: {'mushroom'},
      excludeWords: {
        'sauce', 'soup', 'pizza', 'pasta', 'pie', 'quiche', 'burger',
      },
    ),
    'bell pepper': IngredientSearchHint(
      searchQuery: 'peppers mixed',
      requiredWords: {'pepper'},
      excludeWords: {
        'sauce', 'crusted', 'peppermint', 'seasoning', 'grinder',
        'corn', 'steak', 'biltong', 'salt',
      },
    ),
    'green pepper': IngredientSearchHint(
      searchQuery: 'green pepper',
      requiredWords: {'pepper', 'green'},
      excludeWords: {'sauce', 'seasoning', 'peppercorn'},
    ),
    'red pepper': IngredientSearchHint(
      searchQuery: 'red pepper',
      requiredWords: {'pepper', 'red'},
      excludeWords: {'sauce', 'seasoning', 'peppercorn', 'flake', 'crushed'},
    ),
    'butternut': IngredientSearchHint(
      searchQuery: 'butternut',
      requiredWords: {'butternut'},
      excludeWords: {'soup', 'sauce', 'baby food'},
    ),
    'sweet potato': IngredientSearchHint(
      searchQuery: 'sweet potatoes',
      requiredWords: {'sweet', 'potato'},
      excludeWords: {'chip', 'crisp', 'fry', 'baby food', 'soup'},
    ),
    'cabbage': IngredientSearchHint(
      searchQuery: 'cabbage',
      requiredWords: {'cabbage'},
      excludeWords: {'coleslaw', 'salad', 'soup'},
    ),
    'lettuce': IngredientSearchHint(
      searchQuery: 'lettuce',
      requiredWords: {'lettuce'},
      excludeWords: {'salad', 'wrap'},
    ),
    'cucumber': IngredientSearchHint(
      searchQuery: 'cucumber',
      requiredWords: {'cucumber'},
      excludeWords: {'salad', 'pickle', 'tzatziki', 'shake'},
    ),
    'avocado': IngredientSearchHint(
      searchQuery: 'avocado',
      requiredWords: {'avocado'},
      excludeWords: {'oil', 'dip', 'guacamole', 'sauce'},
    ),
    'celery': IngredientSearchHint(
      searchQuery: 'celery',
      requiredWords: {'celery'},
      excludeWords: {'soup', 'salt', 'seasoning'},
    ),
    'stir fry vegetables': IngredientSearchHint(
      searchQuery: 'stir fry vegetables',
      requiredWords: {'stir', 'fry'},
      excludeWords: {'sauce', 'noodle', 'rice'},
    ),
    'mixed vegetables': IngredientSearchHint(
      searchQuery: 'mixed vegetables frozen',
      requiredWords: {'mixed', 'vegetable'},
      excludeWords: {'soup', 'sauce', 'stock', 'juice'},
    ),

    // =========================================================================
    // PRODUCE — FRUIT
    // =========================================================================
    'lemons': IngredientSearchHint(
      searchQuery: 'lemons',
      requiredWords: {'lemon'},
      excludeWords: {
        'bleach', 'drink', 'juice', 'tea', 'biscuit', 'cake', 'tart',
        'curd', 'pepper', 'marinated', 'air', 'fresh', 'sparkling',
      },
    ),
    'lemon': IngredientSearchHint(
      searchQuery: 'lemons',
      requiredWords: {'lemon'},
      excludeWords: {
        'bleach', 'drink', 'juice', 'tea', 'biscuit', 'cake', 'tart',
        'curd', 'pepper', 'marinated', 'air', 'fresh', 'sparkling',
      },
    ),
    'lemon juice': IngredientSearchHint(
      searchQuery: 'lemon juice',
      requiredWords: {'lemon', 'juice'},
      excludeWords: {'bleach', 'sparkling', 'drink'},
    ),
    'lime': IngredientSearchHint(
      searchQuery: 'limes',
      requiredWords: {'lime'},
      excludeWords: {
        'drink', 'juice', 'soda', 'sparkling', 'gum', 'cordial', 'beer',
      },
    ),

    // =========================================================================
    // PANTRY — DRY GOODS
    // =========================================================================
    'flour': IngredientSearchHint(
      searchQuery: 'cake flour',
      requiredWords: {'flour'},
      excludeWords: {'tortilla', 'wrap', 'brownie', 'flapjack', 'mix'},
    ),
    'cake flour': IngredientSearchHint(
      searchQuery: 'cake flour',
      requiredWords: {'flour', 'cake'},
      excludeWords: {'mix', 'brownie'},
    ),
    'self raising flour': IngredientSearchHint(
      searchQuery: 'self raising flour',
      requiredWords: {'flour', 'self'},
    ),
    'bread flour': IngredientSearchHint(
      searchQuery: 'bread flour',
      requiredWords: {'flour', 'bread'},
    ),
    'sugar': IngredientSearchHint(
      searchQuery: 'white sugar',
      requiredWords: {'sugar'},
      excludeWords: {
        'free', 'gum', 'drink', 'juice', 'cereal', 'biscuit', 'bar',
        'chocolate', 'candy', 'sweet', 'jam', 'syrup', 'soda', 'gin',
        'liqueur', 'porridge',
      },
    ),
    'white sugar': IngredientSearchHint(
      searchQuery: 'white sugar',
      requiredWords: {'sugar', 'white'},
      excludeWords: {'free', 'drink', 'juice'},
    ),
    'brown sugar': IngredientSearchHint(
      searchQuery: 'brown sugar',
      requiredWords: {'sugar', 'brown'},
      excludeWords: {'free', 'drink'},
    ),
    'caster sugar': IngredientSearchHint(
      searchQuery: 'caster sugar',
      requiredWords: {'sugar', 'caster'},
    ),
    'icing sugar': IngredientSearchHint(
      searchQuery: 'icing sugar',
      requiredWords: {'sugar', 'icing'},
    ),
    'salt': IngredientSearchHint(
      searchQuery: 'table salt',
      requiredWords: {'salt'},
      excludeWords: {
        'dishwasher', 'bath', 'chip', 'crisp', 'pretzel', 'popcorn',
        'nut', 'cracker', 'vinegar', 'pepper', 'seasoning', 'biltong',
      },
    ),
    'table salt': IngredientSearchHint(
      searchQuery: 'table salt',
      requiredWords: {'salt', 'table'},
      excludeWords: {'dishwasher', 'bath'},
    ),
    'sea salt': IngredientSearchHint(
      searchQuery: 'sea salt',
      requiredWords: {'salt', 'sea'},
      excludeWords: {'chip', 'crisp', 'cracker', 'pretzel', 'popcorn'},
    ),
    'rice': IngredientSearchHint(
      searchQuery: 'long grain rice',
      requiredWords: {'rice'},
      excludeWords: {
        'cake', 'cracker', 'cereal', 'crispy', 'pudding', 'noodle',
        'paper', 'vermicelli', 'bar', 'treat', 'milk', 'baby',
      },
    ),
    'long grain rice': IngredientSearchHint(
      searchQuery: 'long grain rice',
      requiredWords: {'rice', 'long', 'grain'},
    ),
    'basmati rice': IngredientSearchHint(
      searchQuery: 'basmati rice',
      requiredWords: {'rice', 'basmati'},
    ),
    'pasta': IngredientSearchHint(
      searchQuery: 'spaghetti',
      requiredWords: {'spaghetti', 'pasta', 'penne', 'fusilli', 'macaroni', 'fettuccine', 'tagliatelle', 'linguine'},
      excludeWords: {'sauce', 'salad', 'ready', 'bake'},
    ),
    'spaghetti': IngredientSearchHint(
      searchQuery: 'spaghetti',
      requiredWords: {'spaghetti'},
      excludeWords: {'sauce', 'bolognese'},
    ),
    'penne': IngredientSearchHint(
      searchQuery: 'penne pasta',
      requiredWords: {'penne'},
      excludeWords: {'sauce', 'salad', 'ready'},
    ),
    'maize meal': IngredientSearchHint(
      searchQuery: 'maize meal',
      requiredWords: {'maize', 'meal'},
      excludeWords: {'dog', 'cat', 'pet'},
    ),
    'couscous': IngredientSearchHint(
      searchQuery: 'couscous',
      requiredWords: {'couscous'},
      excludeWords: {'flavour'},
    ),
    'bread': IngredientSearchHint(
      searchQuery: 'white bread',
      requiredWords: {'bread'},
      excludeWords: {
        'crumb', 'stick', 'flour', 'mix', 'pudding', 'sauce', 'butter',
      },
    ),
    'bread crumbs': IngredientSearchHint(
      searchQuery: 'bread crumbs',
      requiredWords: {'bread', 'crumb'},
    ),

    // =========================================================================
    // PANTRY — OILS & VINEGAR
    // =========================================================================
    'oil': IngredientSearchHint(
      searchQuery: 'sunflower oil',
      requiredWords: {'oil'},
      excludeWords: {
        'sardine', 'tuna', 'mussel', 'pilchard', 'anchovy', 'moistur',
        'hair', 'skin', 'body', 'baby', 'engine', 'essential', 'massage',
        'spray',
      },
    ),
    'sunflower oil': IngredientSearchHint(
      searchQuery: 'sunflower oil',
      requiredWords: {'sunflower', 'oil'},
    ),
    'olive oil': IngredientSearchHint(
      searchQuery: 'olive oil',
      requiredWords: {'olive', 'oil'},
      excludeWords: {
        'sardine', 'tuna', 'anchovy', 'breadstick', 'cracker', 'crisp',
        'spray',
      },
    ),
    'vegetable oil': IngredientSearchHint(
      searchQuery: 'vegetable oil',
      requiredWords: {'vegetable', 'oil'},
    ),
    'canola oil': IngredientSearchHint(
      searchQuery: 'canola oil',
      requiredWords: {'canola', 'oil'},
      excludeWords: {'spray'},
    ),
    'sesame oil': IngredientSearchHint(
      searchQuery: 'sesame oil',
      requiredWords: {'sesame', 'oil'},
    ),
    'vinegar': IngredientSearchHint(
      searchQuery: 'white vinegar',
      requiredWords: {'vinegar'},
      excludeWords: {'chip', 'crisp', 'cleaner', 'salt'},
    ),
    'balsamic vinegar': IngredientSearchHint(
      searchQuery: 'balsamic vinegar',
      requiredWords: {'balsamic'},
    ),

    // =========================================================================
    // PANTRY — CANNED & SAUCES
    // =========================================================================
    'tomato paste': IngredientSearchHint(
      searchQuery: 'tomato paste',
      requiredWords: {'tomato', 'paste'},
    ),
    'tinned tomatoes': IngredientSearchHint(
      searchQuery: 'chopped tomatoes 400g',
      requiredWords: {'tomato'},
      excludeWords: {'paste', 'sauce', 'soup', 'puree', 'ketchup', 'juice'},
    ),
    'chopped tomatoes': IngredientSearchHint(
      searchQuery: 'chopped tomatoes',
      requiredWords: {'tomato', 'chopped'},
    ),
    'diced tomatoes': IngredientSearchHint(
      searchQuery: 'diced tomatoes',
      requiredWords: {'tomato', 'diced'},
    ),
    'coconut milk': IngredientSearchHint(
      searchQuery: 'coconut milk',
      requiredWords: {'coconut'},
      excludeWords: {'chocolate', 'bar', 'biscuit', 'rusk', 'shampoo', 'conditioner', 'cream'},
    ),
    'coconut cream': IngredientSearchHint(
      searchQuery: 'coconut cream',
      requiredWords: {'coconut', 'cream'},
      excludeWords: {'chocolate', 'bar', 'biscuit'},
    ),
    'soy sauce': IngredientSearchHint(
      searchQuery: 'soy sauce',
      requiredWords: {'soy', 'sauce'},
    ),
    'worcestershire sauce': IngredientSearchHint(
      searchQuery: 'worcestershire sauce',
      requiredWords: {'worcestershire'},
    ),
    'tomato sauce': IngredientSearchHint(
      searchQuery: 'tomato sauce',
      requiredWords: {'tomato', 'sauce'},
      excludeWords: {'pasta', 'pizza', 'cooking'},
    ),
    'chicken stock': IngredientSearchHint(
      searchQuery: 'chicken stock',
      requiredWords: {'chicken', 'stock'},
      excludeWords: {'pie', 'bone'},
    ),
    'beef stock': IngredientSearchHint(
      searchQuery: 'beef stock',
      requiredWords: {'beef', 'stock'},
      excludeWords: {'bone'},
    ),
    'vegetable stock': IngredientSearchHint(
      searchQuery: 'vegetable stock',
      requiredWords: {'vegetable', 'stock'},
    ),

    // =========================================================================
    // PANTRY — BAKING
    // =========================================================================
    'baking powder': IngredientSearchHint(
      searchQuery: 'baking powder',
      requiredWords: {'baking', 'powder'},
    ),
    'baking soda': IngredientSearchHint(
      searchQuery: 'bicarbonate of soda',
      requiredWords: {'bicarbonate', 'soda', 'baking'},
    ),
    'bicarbonate of soda': IngredientSearchHint(
      searchQuery: 'bicarbonate of soda',
      requiredWords: {'bicarbonate'},
    ),
    'vanilla essence': IngredientSearchHint(
      searchQuery: 'vanilla essence',
      requiredWords: {'vanilla', 'essence'},
      excludeWords: {'porridge', 'yoghurt', 'ice'},
    ),
    'vanilla extract': IngredientSearchHint(
      searchQuery: 'vanilla essence',
      requiredWords: {'vanilla', 'essence'},
      excludeWords: {'porridge', 'yoghurt', 'ice'},
    ),
    'cornflour': IngredientSearchHint(
      searchQuery: 'maizena cornflour',
      requiredWords: {'cornflour', 'corn'},
      excludeWords: {'tortilla'},
    ),
    'corn flour': IngredientSearchHint(
      searchQuery: 'maizena cornflour',
      requiredWords: {'cornflour', 'corn'},
      excludeWords: {'tortilla'},
    ),
    'maizena': IngredientSearchHint(
      searchQuery: 'maizena cornflour',
      requiredWords: {'maizena', 'cornflour', 'corn'},
      excludeWords: {'tortilla'},
    ),
    'maizena corn flour': IngredientSearchHint(
      searchQuery: 'maizena cornflour',
      requiredWords: {'maizena', 'cornflour', 'corn'},
      excludeWords: {'tortilla'},
    ),
    'cocoa powder': IngredientSearchHint(
      searchQuery: 'cocoa powder',
      requiredWords: {'cocoa', 'powder'},
      excludeWords: {'drink', 'hot chocolate', 'bar'},
    ),
    'honey': IngredientSearchHint(
      searchQuery: 'pure honey',
      requiredWords: {'honey'},
      excludeWords: {
        'mustard', 'biscuit', 'cereal', 'granola', 'bbq', 'marinade',
        'pretzel', 'ham', 'sausage', 'glaze',
      },
    ),

    // =========================================================================
    // SPICES & HERBS
    // =========================================================================
    'black pepper': IngredientSearchHint(
      searchQuery: 'black pepper grinder',
      requiredWords: {'pepper', 'black'},
      excludeWords: {
        'steak', 'biltong', 'sauce', 'chip', 'crisp', 'sausage', 'fillet',
        'lemon', 'marinated',
      },
    ),
    'pepper': IngredientSearchHint(
      searchQuery: 'black pepper',
      requiredWords: {'pepper'},
      excludeWords: {
        'steak', 'biltong', 'sauce', 'chip', 'crisp', 'sausage',
        'peppermint', 'fillet', 'marinated', 'crusted', 'gateau',
        'dessert', 'smoked',
      },
    ),
    'paprika': IngredientSearchHint(
      searchQuery: 'paprika spice',
      requiredWords: {'paprika'},
      excludeWords: {
        'chicken', 'steak', 'marinated', 'grills', 'duck', 'kebab',
      },
    ),
    'ground cumin': IngredientSearchHint(
      searchQuery: 'ground cumin',
      requiredWords: {'cumin'},
      excludeWords: {'cheese', 'olive', 'curry'},
    ),
    'cumin': IngredientSearchHint(
      searchQuery: 'ground cumin',
      requiredWords: {'cumin'},
      excludeWords: {'cheese', 'olive', 'curry'},
    ),
    'turmeric': IngredientSearchHint(
      searchQuery: 'turmeric ground',
      requiredWords: {'turmeric'},
      excludeWords: {'tea', 'drink', 'juice', 'capsule'},
    ),
    'ground cinnamon': IngredientSearchHint(
      searchQuery: 'ground cinnamon',
      requiredWords: {'cinnamon'},
      excludeWords: {'tea', 'danish', 'apple', 'biscuit', 'porridge', 'cereal'},
    ),
    'cinnamon': IngredientSearchHint(
      searchQuery: 'ground cinnamon',
      requiredWords: {'cinnamon'},
      excludeWords: {'tea', 'danish', 'apple', 'biscuit', 'porridge', 'cereal'},
    ),
    'mixed herbs': IngredientSearchHint(
      searchQuery: 'mixed herbs',
      requiredWords: {'mixed', 'herb'},
    ),
    'dried oregano': IngredientSearchHint(
      searchQuery: 'oregano',
      requiredWords: {'oregano'},
    ),
    'dried thyme': IngredientSearchHint(
      searchQuery: 'thyme',
      requiredWords: {'thyme'},
    ),
    'dried rosemary': IngredientSearchHint(
      searchQuery: 'rosemary',
      requiredWords: {'rosemary'},
      excludeWords: {'chicken', 'lamb', 'steak', 'pork'},
    ),
    'chilli flakes': IngredientSearchHint(
      searchQuery: 'chilli flakes',
      requiredWords: {'chilli', 'flake'},
    ),
    'chilli powder': IngredientSearchHint(
      searchQuery: 'chilli powder',
      requiredWords: {'powder'},
      excludeWords: {
        'sauce', 'flake', 'per kg', 'fresh', 'paste', 'oil', 'crisp',
        'chip', 'biltong', 'sausage', 'steak',
      },
    ),
    'curry powder': IngredientSearchHint(
      searchQuery: 'curry powder',
      requiredWords: {'curry', 'powder'},
    ),
    'garam masala': IngredientSearchHint(
      searchQuery: 'garam masala',
      requiredWords: {'garam', 'masala'},
      excludeWords: {'sauce', 'cook-in', 'simmer'},
    ),
    'cardamom': IngredientSearchHint(
      searchQuery: 'cardamom',
      requiredWords: {'cardamom'},
      excludeWords: {'air', 'spritz', 'biscuit', 'tea', 'candle'},
    ),
    'cardamom pods': IngredientSearchHint(
      searchQuery: 'green cardamom',
      requiredWords: {'cardamom'},
      excludeWords: {'air', 'spritz', 'biscuit', 'tea', 'candle', 'ground'},
    ),
    'cinnamon stick': IngredientSearchHint(
      searchQuery: 'cinnamon stick',
      requiredWords: {'cinnamon', 'stick'},
    ),
    'cinnamon sticks': IngredientSearchHint(
      searchQuery: 'cinnamon stick',
      requiredWords: {'cinnamon', 'stick'},
    ),
    'star anise': IngredientSearchHint(
      searchQuery: 'star anise',
      requiredWords: {'anise', 'star'},
    ),
    'cloves': IngredientSearchHint(
      searchQuery: 'whole cloves',
      requiredWords: {'clove'},
      excludeWords: {'garlic'},
    ),
    'fennel seeds': IngredientSearchHint(
      searchQuery: 'fennel seeds',
      requiredWords: {'fennel'},
      excludeWords: {'tea', 'baby'},
    ),
    'coriander': IngredientSearchHint(
      searchQuery: 'ground coriander',
      requiredWords: {'coriander'},
      excludeWords: {'chicken', 'steak', 'marinated', 'sauce'},
    ),
    'ground coriander': IngredientSearchHint(
      searchQuery: 'ground coriander',
      requiredWords: {'coriander'},
      excludeWords: {'chicken', 'steak', 'marinated', 'sauce'},
    ),
    'fresh coriander': IngredientSearchHint(
      searchQuery: 'fresh coriander',
      requiredWords: {'coriander'},
      excludeWords: {'ground', 'powder', 'spice'},
    ),
    'bay leaves': IngredientSearchHint(
      searchQuery: 'bay leaves',
      requiredWords: {'bay', 'leaf', 'leaves'},
    ),
    'sesame seeds': IngredientSearchHint(
      searchQuery: 'sesame seeds',
      requiredWords: {'sesame', 'seed'},
      excludeWords: {'oil', 'pretzel', 'burger', 'bun'},
    ),
    'mustard': IngredientSearchHint(
      searchQuery: 'wholegrain mustard',
      requiredWords: {'mustard'},
      excludeWords: {'pretzel', 'chip', 'crisp', 'sausage', 'ham', 'powder'},
    ),
    'dijon mustard': IngredientSearchHint(
      searchQuery: 'dijon mustard',
      requiredWords: {'dijon', 'mustard'},
    ),

    // =========================================================================
    // CONDIMENTS & MISCELLANEOUS
    // =========================================================================
    'peanut butter': IngredientSearchHint(
      searchQuery: 'peanut butter',
      requiredWords: {'peanut', 'butter'},
      excludeWords: {'chocolate', 'bar', 'cup', 'cookie'},
    ),
    'mayonnaise': IngredientSearchHint(
      searchQuery: 'mayonnaise',
      requiredWords: {'mayonnaise', 'mayo'},
      excludeWords: {'salad', 'sandwich', 'wrap'},
    ),
    'tinned beans': IngredientSearchHint(
      searchQuery: 'baked beans',
      requiredWords: {'bean'},
      excludeWords: {'coffee', 'jelly', 'chocolate', 'vanilla'},
    ),
    'chickpeas': IngredientSearchHint(
      searchQuery: 'chickpeas',
      requiredWords: {'chickpea'},
      excludeWords: {'flour', 'crisp', 'snack'},
    ),
    'lentils': IngredientSearchHint(
      searchQuery: 'lentils',
      requiredWords: {'lentil'},
      excludeWords: {'soup', 'baby'},
    ),
    'condensed milk': IngredientSearchHint(
      searchQuery: 'condensed milk',
      requiredWords: {'condensed', 'milk'},
      excludeWords: {'liqueur', 'cream'},
    ),
    'evaporated milk': IngredientSearchHint(
      searchQuery: 'evaporated milk',
      requiredWords: {'evaporated', 'milk'},
    ),
  };
}
