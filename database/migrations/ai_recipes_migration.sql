-- ============================================================================
-- AI RECIPES FEATURE - DATABASE MIGRATION
-- ============================================================================
-- Run this in Supabase SQL Editor (Dashboard → SQL Editor → New Query)
--
-- This migration adds/updates:
-- 1. Recipes_Overview table for storing saved recipes
-- 2. Recipe_Ingredients table for linking recipes to products
-- 3. RLS policies for private recipes
-- ============================================================================


-- ============================================================================
-- SECTION 1: RECIPES OVERVIEW TABLE
-- ============================================================================
-- Stores the main recipe information

CREATE TABLE IF NOT EXISTS "Recipes_Overview" (
    recipe_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    -- Recipe details
    recipe_name TEXT NOT NULL,
    recipe_description TEXT,
    servings INT DEFAULT 4,
    prep_time_minutes INT,
    cook_time_minutes INT,
    total_time_minutes INT,
    difficulty TEXT CHECK (difficulty IN ('Easy', 'Medium', 'Hard')),

    -- Instructions stored as JSON array of steps
    instructions JSONB NOT NULL DEFAULT '[]',

    -- Optional metadata
    cuisine_type TEXT,
    meal_type TEXT, -- 'Breakfast', 'Lunch', 'Dinner', 'Snack', 'Dessert'
    dietary_tags TEXT[], -- ['Vegetarian', 'Vegan', 'Gluten-Free', etc.]

    -- AI generation metadata
    ai_generated BOOLEAN DEFAULT TRUE,
    original_prompt TEXT, -- What the user asked for

    -- Image (future feature)
    image_url TEXT
);

-- Add indexes
CREATE INDEX IF NOT EXISTS idx_recipes_user_id ON "Recipes_Overview"(user_id);
CREATE INDEX IF NOT EXISTS idx_recipes_created_at ON "Recipes_Overview"(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_recipes_name ON "Recipes_Overview" USING GIN(to_tsvector('english', recipe_name));

-- Enable RLS
ALTER TABLE "Recipes_Overview" ENABLE ROW LEVEL SECURITY;

-- RLS Policies: Users can only see/edit their own recipes
CREATE POLICY "Users can view own recipes"
    ON "Recipes_Overview"
    FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own recipes"
    ON "Recipes_Overview"
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own recipes"
    ON "Recipes_Overview"
    FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own recipes"
    ON "Recipes_Overview"
    FOR DELETE
    USING (auth.uid() = user_id);


-- ============================================================================
-- SECTION 2: RECIPE INGREDIENTS TABLE
-- ============================================================================
-- Links recipe ingredients to products (optional product match)

CREATE TABLE IF NOT EXISTS "Recipe_Ingredients" (
    ingredient_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recipe_id UUID NOT NULL REFERENCES "Recipes_Overview"(recipe_id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),

    -- Ingredient details from AI
    ingredient_name TEXT NOT NULL, -- e.g., "Chicken Breast"
    quantity DECIMAL,              -- e.g., 500
    unit TEXT,                     -- e.g., "g", "ml", "cups", "pieces"
    preparation TEXT,              -- e.g., "diced", "sliced", "minced"
    is_optional BOOLEAN DEFAULT FALSE,

    -- Product matching (nullable - user may not match all ingredients)
    matched_product_index TEXT REFERENCES "Products"(index),
    matched_product_name TEXT,
    matched_product_price DECIMAL,
    matched_retailer TEXT,

    -- Order for display
    display_order INT DEFAULT 0
);

-- Add indexes
CREATE INDEX IF NOT EXISTS idx_recipe_ingredients_recipe_id ON "Recipe_Ingredients"(recipe_id);
CREATE INDEX IF NOT EXISTS idx_recipe_ingredients_product ON "Recipe_Ingredients"(matched_product_index);

-- Enable RLS
ALTER TABLE "Recipe_Ingredients" ENABLE ROW LEVEL SECURITY;

-- RLS Policies: Access through parent recipe ownership
CREATE POLICY "Users can view ingredients of own recipes"
    ON "Recipe_Ingredients"
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM "Recipes_Overview"
            WHERE recipe_id = "Recipe_Ingredients".recipe_id
            AND user_id = auth.uid()
        )
    );

CREATE POLICY "Users can insert ingredients to own recipes"
    ON "Recipe_Ingredients"
    FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM "Recipes_Overview"
            WHERE recipe_id = "Recipe_Ingredients".recipe_id
            AND user_id = auth.uid()
        )
    );

CREATE POLICY "Users can update ingredients of own recipes"
    ON "Recipe_Ingredients"
    FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM "Recipes_Overview"
            WHERE recipe_id = "Recipe_Ingredients".recipe_id
            AND user_id = auth.uid()
        )
    );

CREATE POLICY "Users can delete ingredients of own recipes"
    ON "Recipe_Ingredients"
    FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM "Recipes_Overview"
            WHERE recipe_id = "Recipe_Ingredients".recipe_id
            AND user_id = auth.uid()
        )
    );


-- ============================================================================
-- SECTION 3: FUNCTION TO FIND MATCHING PRODUCTS FOR INGREDIENTS
-- ============================================================================
-- Reuses the normalized_name and similarity matching from price comparison

CREATE OR REPLACE FUNCTION find_matching_products_for_ingredient(
    ingredient_search TEXT,
    target_retailer TEXT DEFAULT NULL,
    similarity_threshold DECIMAL DEFAULT 0.3,
    max_results INT DEFAULT 10
)
RETURNS TABLE(
    product_index TEXT,
    product_name TEXT,
    product_price TEXT,
    product_promotion_price TEXT,
    product_image_url TEXT,
    retailer TEXT,
    similarity_score DECIMAL,
    size_value DECIMAL,
    size_unit TEXT
) AS $$
DECLARE
    search_normalized TEXT;
BEGIN
    -- Normalize the search term
    search_normalized := LOWER(TRIM(ingredient_search));

    RETURN QUERY
    SELECT
        p.index,
        p.name,
        p.price,
        p.promotion_price,
        p.image_url,
        p.retailer,
        ROUND(similarity(p.normalized_name, search_normalized)::DECIMAL, 3) AS sim_score,
        p.size_value,
        p.size_unit
    FROM "Products" p
    WHERE
        -- Filter by retailer if specified
        (target_retailer IS NULL OR p.retailer = target_retailer)
        -- Must be parsed
        AND p.parsed_at IS NOT NULL
        -- Similarity filter using trigram index
        AND (
            p.normalized_name % search_normalized
            OR p.name ILIKE '%' || search_normalized || '%'
        )
    ORDER BY
        -- Exact match in name first
        CASE WHEN p.name ILIKE '%' || search_normalized || '%' THEN 0 ELSE 1 END,
        -- Then by similarity score
        similarity(p.normalized_name, search_normalized) DESC,
        -- Then by price (cheapest first) - extract numeric value
        (regexp_match(p.price, 'R\s*(\d+\.?\d*)'))[1]::DECIMAL ASC NULLS LAST
    LIMIT max_results;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION find_matching_products_for_ingredient(TEXT, TEXT, DECIMAL, INT) IS
'Finds matching products for a recipe ingredient.
Call from Flutter: supabase.rpc("find_matching_products_for_ingredient", {
  "ingredient_search": "chicken breast",
  "target_retailer": "Pick n Pay",
  "similarity_threshold": 0.3,
  "max_results": 10
})';


-- ============================================================================
-- SECTION 4: UPDATED_AT TRIGGER
-- ============================================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_recipes_updated_at ON "Recipes_Overview";
CREATE TRIGGER update_recipes_updated_at
    BEFORE UPDATE ON "Recipes_Overview"
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();


-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================
--
-- 1. Check tables exist:
--    SELECT table_name FROM information_schema.tables
--    WHERE table_name IN ('Recipes_Overview', 'Recipe_Ingredients');
--
-- 2. Test ingredient search:
--    SELECT * FROM find_matching_products_for_ingredient('chicken', 'Pick n Pay');
--
-- 3. Check RLS policies:
--    SELECT * FROM pg_policies WHERE tablename IN ('Recipes_Overview', 'Recipe_Ingredients');
--
-- ============================================================================
