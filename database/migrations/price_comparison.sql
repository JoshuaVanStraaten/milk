-- ============================================================================
-- PRICE COMPARISON FEATURE - DATABASE MIGRATION
-- ============================================================================
-- Run this in Supabase SQL Editor (Dashboard → SQL Editor → New Query)
--
-- This migration adds:
-- 1. New columns for product matching (brand, size, normalized_name)
-- 2. Function to parse product names and extract structured data
-- 3. Function to find matching products across retailers
-- 4. pg_cron scheduled job to auto-parse new products daily
--
-- IMPORTANT: Run each section separately if you encounter issues
-- ============================================================================


-- ============================================================================
-- SECTION 1: ENABLE REQUIRED EXTENSIONS
-- ============================================================================
-- pg_trgm: For fuzzy text matching (similarity scores)
-- pg_cron: For scheduled jobs (auto-parsing)

CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS pg_cron;


-- ============================================================================
-- SECTION 2: ADD NEW COLUMNS TO PRODUCTS TABLE
-- ============================================================================
-- These columns store parsed/extracted data for efficient matching
--
-- brand: The product brand (e.g., "Kellogg's", "Clover", "Coca-Cola")
-- size_value: Numeric size (e.g., 500, 1.5, 2)
-- size_unit: Unit of measurement, normalized (e.g., "g", "kg", "ml", "l")
-- normalized_name: Lowercase name with size removed, for fuzzy matching
-- parsed_at: Timestamp when parsing occurred (NULL = not yet parsed)

ALTER TABLE "Products" ADD COLUMN IF NOT EXISTS brand TEXT;
ALTER TABLE "Products" ADD COLUMN IF NOT EXISTS size_value DECIMAL;
ALTER TABLE "Products" ADD COLUMN IF NOT EXISTS size_unit TEXT;
ALTER TABLE "Products" ADD COLUMN IF NOT EXISTS normalized_name TEXT;
ALTER TABLE "Products" ADD COLUMN IF NOT EXISTS parsed_at TIMESTAMPTZ;

-- Create indexes for efficient matching queries
CREATE INDEX IF NOT EXISTS idx_products_brand ON "Products"(brand);
CREATE INDEX IF NOT EXISTS idx_products_size ON "Products"(size_value, size_unit);
CREATE INDEX IF NOT EXISTS idx_products_normalized_name ON "Products" USING GIN(normalized_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_products_parsed_at ON "Products"(parsed_at) WHERE parsed_at IS NULL;


-- ============================================================================
-- SECTION 3: PRODUCT NAME PARSING FUNCTION
-- ============================================================================
-- This function extracts brand, size, and creates a normalized name from
-- product names. It handles various formats:
--   - "Kellogg's Corn Flakes 500g" → brand: "kellogg's", size: 500g
--   - "Clover Full Cream Milk 2 L" → brand: "clover", size: 2l (Woolworths format)
--   - "Coca-Cola Zero 6 x 300ml" → brand: "coca-cola", size: 300ml (multi-pack)

CREATE OR REPLACE FUNCTION parse_product_name(product_name TEXT)
RETURNS TABLE(
    extracted_brand TEXT,
    extracted_size_value DECIMAL,
    extracted_size_unit TEXT,
    extracted_normalized_name TEXT
) AS $$
DECLARE
    name_lower TEXT;
    brand_match TEXT;
    size_match TEXT[];
    size_val DECIMAL;
    size_u TEXT;
    normalized TEXT;

    -- Common brand patterns (add more as needed)
    brand_patterns TEXT[] := ARRAY[
        'kellogg''s', 'kelloggs', 'clover', 'coca-cola', 'coca cola', 'pepsi',
        'nestle', 'nestlé', 'cadbury', 'unilever', 'omo', 'sunlight', 'handy andy',
        'domestos', 'dove', 'lux', 'lifebuoy', 'vaseline', 'pond''s', 'ponds',
        'colgate', 'oral-b', 'oral b', 'gillette', 'pantene', 'head & shoulders',
        'always', 'pampers', 'huggies', 'johnson''s', 'johnsons', 'nivea',
        'garnier', 'l''oreal', 'loreal', 'maybelline', 'revlon', 'rimmel',
        'dettol', 'savlon', 'disprin', 'panado', 'bioplus', 'centrum',
        'nescafe', 'nescafé', 'ricoffy', 'frisco', 'jacobs', 'douwe egberts',
        'lipton', 'five roses', 'joko', 'glen', 'freshpak', 'laager',
        'fattis & monis', 'fatti''s & moni''s', 'albany', 'sasko', 'blue ribbon',
        'tastic', 'spekko', 'ace', 'iwisa', 'white star', 'jungle',
        'bokomo', 'weet-bix', 'weetbix', 'pronutro', 'morvite',
        'all gold', 'koo', 'rhodes', 'bull brand', 'lucky star', 'john west',
        'pilchards', 'black cat', 'yum yum', 'skippy',
        'rama', 'stork', 'flora', 'lurpak', 'kerrygold',
        'lancewood', 'parmalat', 'woodlands', 'fairfield', 'darling',
        'steri stumpie', 'steri-stumpie', 'milo', 'ovaltine', 'horlicks',
        'energade', 'powerade', 'gatorade', 'energise', 'rehidrat',
        'appletiser', 'grapetiser', 'liqui fruit', 'ceres', 'tropika',
        'oros', 'halls', 'brookes', 'bos', 'rooibos',
        'castle', 'castle lite', 'carling', 'hansa', 'windhoek', 'amstel',
        'heineken', 'corona', 'stella', 'budweiser', 'savanna', 'hunters',
        'smirnoff', 'gordons', 'gilbeys', 'captain morgan', 'bacardi',
        'johnnie walker', 'jameson', 'jack daniels', 'bells', 'j&b',
        'amarula', 'kwv', 'nederburg', 'drostdy-hof', 'robertson',
        'pnp', 'pick n pay', 'checkers', 'shoprite', 'woolworths', 'w.lab',
        'housebrand', 'no name', 'ritebrand', 'm budget',
        'simba', 'lays', 'lay''s', 'doritos', 'fritos', 'nik naks', 'niknaks',
        'willards', 'bakers', 'baumann''s', 'tennis', 'romany creams',
        'oreo', 'tuc', 'salticrax', 'provita', 'ryvita',
        'beacon', 'cadbury', 'lindt', 'ferrero', 'kinder', 'toblerone',
        'bar one', 'lunch bar', 'kitkat', 'kit kat', 'aero', 'tex',
        'jelly tots', 'astros', 'smarties', 'm&m', 'skittles', 'mentos',
        'chappies', 'big korn bites', 'ghost pops', 'flings',
        'royal', 'oetker', 'dr oetker', 'moir''s', 'moirs', 'ina paarman',
        'knorr', 'maggi', 'imana', 'royco', 'bisto',
        'mrs balls', 'mrs ball''s', 'all gold', 'wellington''s', 'crosse & blackwell',
        'tabasco', 'nando''s', 'nandos', 'steers', 'wimpy',
        'hellmann''s', 'hellmanns', 'cross & blackwell', 'heinz',
        'spur', 'mccain', 'i&j', 'sea harvest', 'oceanwise',
        'fry''s', 'frys', 'enterprise', 'eskort', 'renown', 'farmer''s choice',
        'county fair', 'rainbow', 'goldi', 'festive', 'mountain valley',
        'danone', 'yoplait', 'nutriday', 'ultra mel', 'super m',
        'bio live', 'activia', 'yakult', 'chamyto',
        'harpic', 'toilet duck', 'mr muscle', 'mr min', 'pledge',
        'windolene', 'handy andy', 'jik', 'domestos', 'toilet duck',
        'glade', 'airwick', 'air wick', 'doom', 'raid', 'mortein', 'peaceful sleep',
        'sta-soft', 'sta soft', 'stasoft', 'comfort', 'downy',
        'ariel', 'skip', 'surf', 'maq', 'sunfoil', 'excella'
    ];
BEGIN
    name_lower := LOWER(TRIM(product_name));

    -- ========================================
    -- STEP 1: Extract Brand
    -- ========================================
    -- Try to match known brands at the start of the product name
    brand_match := NULL;
    FOR i IN 1..array_length(brand_patterns, 1) LOOP
        IF name_lower LIKE brand_patterns[i] || ' %' OR name_lower LIKE brand_patterns[i] || '''%' THEN
            brand_match := brand_patterns[i];
            EXIT;
        END IF;
    END LOOP;

    -- If no known brand found, use first word (often the brand)
    IF brand_match IS NULL THEN
        brand_match := SPLIT_PART(name_lower, ' ', 1);
        -- Remove apostrophes for consistency
        brand_match := REPLACE(brand_match, '''', '');
    END IF;

    -- ========================================
    -- STEP 2: Extract Size
    -- ========================================
    -- Pattern matches: "500g", "500 g", "1.5L", "1.5 L", "2 kg", etc.
    -- Also handles multi-packs: "6 x 100g" → extracts "100g"

    -- First, try to find multi-pack pattern (e.g., "6 x 100g")
    size_match := regexp_match(name_lower, '(\d+)\s*x\s*(\d+\.?\d*)\s*(g|kg|ml|l|litre|liter)s?(?:\s|$)', 'i');

    IF size_match IS NOT NULL THEN
        -- Multi-pack: use individual item size
        size_val := size_match[2]::DECIMAL;
        size_u := LOWER(size_match[3]);
    ELSE
        -- Try standard size pattern
        size_match := regexp_match(name_lower, '(\d+\.?\d*)\s*(g|kg|ml|l|litre|liter)s?(?:\s|$)', 'i');

        IF size_match IS NOT NULL THEN
            size_val := size_match[1]::DECIMAL;
            size_u := LOWER(size_match[2]);
        ELSE
            -- Try "per kg" pattern
            IF name_lower LIKE '%per kg%' THEN
                size_val := 1;
                size_u := 'kg';
            END IF;
        END IF;
    END IF;

    -- Normalize size units
    IF size_u IN ('litre', 'liter') THEN
        size_u := 'l';
    END IF;

    -- Convert to base units for easier comparison
    -- Keep original for now, we'll handle conversion in comparison function

    -- ========================================
    -- STEP 3: Create Normalized Name
    -- ========================================
    -- Remove size information and extra whitespace for fuzzy matching
    normalized := name_lower;

    -- Remove multi-pack patterns (e.g., "6 x 100g", "5 Pack")
    normalized := regexp_replace(normalized, '\d+\s*x\s*\d+\.?\d*\s*(g|kg|ml|l|litre|liter)s?', '', 'gi');
    normalized := regexp_replace(normalized, '\d+\s*(pack|pk|ea)\b', '', 'gi');

    -- Remove size patterns
    normalized := regexp_replace(normalized, '\d+\.?\d*\s*(g|kg|ml|l|litre|liter)s?\b', '', 'gi');

    -- Remove "per kg" type patterns
    normalized := regexp_replace(normalized, 'per\s*(kg|g|100g|100ml)\b', '', 'gi');

    -- Clean up whitespace
    normalized := regexp_replace(normalized, '\s+', ' ', 'g');
    normalized := TRIM(normalized);

    RETURN QUERY SELECT brand_match, size_val, size_u, normalized;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Add a comment explaining the function
COMMENT ON FUNCTION parse_product_name(TEXT) IS
'Extracts brand, size (value + unit), and normalized name from a product name string.
Used for matching similar products across different retailers.';


-- ============================================================================
-- SECTION 4: BATCH PARSING FUNCTION
-- ============================================================================
-- This function parses all products that haven't been parsed yet.
-- It's designed to be called after your scraper upserts new products.
-- Processes in batches of 1000 to avoid memory issues.

CREATE OR REPLACE FUNCTION parse_unparsed_products(batch_size INT DEFAULT 1000)
RETURNS TABLE(products_parsed INT, duration_ms BIGINT) AS $$
DECLARE
    start_time TIMESTAMPTZ;
    total_parsed INT := 0;
    batch_count INT;
BEGIN
    start_time := clock_timestamp();

    -- Process in batches to avoid memory issues
    LOOP
        -- Update products in batches, parsing names inline
        WITH to_parse AS (
            SELECT index, name
            FROM "Products"
            WHERE parsed_at IS NULL
            LIMIT batch_size
            FOR UPDATE SKIP LOCKED
        ),
        parsed_data AS (
            SELECT
                t.index,
                (parse_product_name(t.name)).*
            FROM to_parse t
        ),
        updated AS (
            UPDATE "Products" p
            SET
                brand = pd.extracted_brand,
                size_value = pd.extracted_size_value,
                size_unit = pd.extracted_size_unit,
                normalized_name = pd.extracted_normalized_name,
                parsed_at = NOW()
            FROM parsed_data pd
            WHERE p.index = pd.index
            RETURNING 1
        )
        SELECT COUNT(*) INTO batch_count FROM updated;

        total_parsed := total_parsed + batch_count;

        -- Exit when no more rows to process
        EXIT WHEN batch_count = 0;

        -- Small pause to avoid overwhelming the database
        PERFORM pg_sleep(0.1);
    END LOOP;

    RETURN QUERY SELECT
        total_parsed,
        EXTRACT(MILLISECONDS FROM (clock_timestamp() - start_time))::BIGINT;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION parse_unparsed_products(INT) IS
'Parses all products where parsed_at IS NULL. Call this after your scraper runs.
Can also be called manually: SELECT * FROM parse_unparsed_products();
Or from Python: supabase.rpc("parse_unparsed_products").execute()';


-- ============================================================================
-- SECTION 5: PRICE COMPARISON FUNCTION
-- ============================================================================
-- This is the main function your Flutter app will call.
-- Given a product index, it finds matching products at other retailers.
--
-- Returns matches in order of confidence:
-- 1. EXACT: Same brand + same size + very similar name (>0.7 similarity)
-- 2. SIMILAR: Same brand + similar size OR similar name (>0.5 similarity)
-- 3. FALLBACK: Same normalized name pattern (>0.4 similarity)

CREATE OR REPLACE FUNCTION find_comparable_products(
    source_product_index TEXT,
    similarity_threshold DECIMAL DEFAULT 0.4
)
RETURNS TABLE(
    product_index TEXT,
    product_name TEXT,
    product_price TEXT,
    product_promotion_price TEXT,
    product_image_url TEXT,
    retailer TEXT,
    match_type TEXT,  -- 'EXACT', 'SIMILAR', or 'FALLBACK'
    similarity_score DECIMAL,
    price_difference DECIMAL,  -- Positive = more expensive, Negative = cheaper
    size_value DECIMAL,
    size_unit TEXT
) AS $$
DECLARE
    source_record RECORD;
    source_price DECIMAL;
BEGIN
    -- Get the source product details
    SELECT
        p."index",
        p.name,
        p.brand,
        p.size_value,
        p.size_unit,
        p.normalized_name,
        p."Retailer",
        -- Extract numeric price for comparison
        COALESCE(
            NULLIF(regexp_replace(p."promotionPrice", '[^0-9.]', '', 'g'), ''),
            NULLIF(regexp_replace(p.price, '[^0-9.]', '', 'g'), '')
        )::DECIMAL AS numeric_price
    INTO source_record
    FROM "Products" p
    WHERE p."index" = source_product_index;

    -- If product not found or not parsed, return empty
    IF source_record IS NULL OR source_record.normalized_name IS NULL THEN
        RETURN;
    END IF;

    source_price := source_record.numeric_price;

    RETURN QUERY
    WITH comparable AS (
        SELECT
            p."index" AS p_index,
            p.name AS p_name,
            p.price AS p_price,
            p."promotionPrice" AS p_promo_price,
            p."imageUrl" AS p_image_url,
            p."Retailer" AS p_retailer,
            p.brand AS p_brand,
            p.size_value AS p_size_value,
            p.size_unit AS p_size_unit,
            p.normalized_name AS p_normalized_name,
            -- Calculate similarity score
            similarity(p.normalized_name, source_record.normalized_name) AS name_similarity,
            -- Calculate best price
            COALESCE(
                NULLIF(regexp_replace(p."promotionPrice", '[^0-9.]', '', 'g'), ''),
                NULLIF(regexp_replace(p.price, '[^0-9.]', '', 'g'), '')
            )::DECIMAL AS p_numeric_price
        FROM "Products" p
        WHERE
            -- Different retailer
            p."Retailer" != source_record."Retailer"
            -- Must be parsed
            AND p.parsed_at IS NOT NULL
            -- Pre-filter: same brand OR similar name (using index)
            AND (
                p.brand = source_record.brand
                OR p.normalized_name % source_record.normalized_name  -- Uses pg_trgm index
            )
    )
    SELECT
        c.p_index,
        c.p_name,
        c.p_price,
        c.p_promo_price,
        c.p_image_url,
        c.p_retailer,
        -- Determine match type
        CASE
            WHEN c.p_brand = source_record.brand
                 AND c.p_size_value = source_record.size_value
                 AND c.p_size_unit = source_record.size_unit
                 AND c.name_similarity > 0.6
            THEN 'EXACT'
            WHEN c.p_brand = source_record.brand
                 AND c.name_similarity > 0.5
            THEN 'SIMILAR'
            ELSE 'FALLBACK'
        END AS match_type,
        ROUND(c.name_similarity::DECIMAL, 3) AS similarity_score,
        -- Price difference (positive = more expensive than source)
        CASE
            WHEN source_price IS NOT NULL AND c.p_numeric_price IS NOT NULL
            THEN ROUND(c.p_numeric_price - source_price, 2)
            ELSE NULL
        END AS price_diff,
        c.p_size_value,
        c.p_size_unit
    FROM comparable c
    WHERE c.name_similarity >= similarity_threshold
    ORDER BY
        -- Prioritize: EXACT > SIMILAR > FALLBACK
        CASE
            WHEN c.p_brand = source_record.brand
                 AND c.p_size_value = source_record.size_value
                 AND c.p_size_unit = source_record.size_unit
                 AND c.name_similarity > 0.6
            THEN 1
            WHEN c.p_brand = source_record.brand
                 AND c.name_similarity > 0.5
            THEN 2
            ELSE 3
        END,
        -- Then by similarity score
        c.name_similarity DESC,
        -- Then by price (cheapest first)
        c.p_numeric_price ASC NULLS LAST
    LIMIT 20;  -- Limit results to top 20
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION find_comparable_products(TEXT, DECIMAL) IS
'Finds matching products at other retailers for price comparison.
Call from Flutter: supabase.rpc("find_comparable_products", {"source_product_index": "123"})
Returns products ordered by match quality (EXACT > SIMILAR > FALLBACK) then by price.';


-- ============================================================================
-- SECTION 6: SCHEDULED JOB (pg_cron)
-- ============================================================================
-- This schedules the parsing function to run daily at 8:00 AM UTC.
-- Adjust the time based on when your scrapers finish.
--
-- IMPORTANT: pg_cron jobs can only be created by superuser or
-- users with the 'cron' role. In Supabase, you may need to run this
-- from the Dashboard SQL Editor.

-- First, remove any existing job with the same name
SELECT cron.unschedule('parse-products-daily')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'parse-products-daily');

-- Schedule the parsing job to run daily at 8:00 AM UTC
-- Adjust the time based on when your scrapers typically finish
SELECT cron.schedule(
    'parse-products-daily',           -- Job name
    '0 8 * * *',                      -- Cron expression: 8:00 AM UTC daily
    $$SELECT parse_unparsed_products()$$  -- SQL to execute
);

-- You can check scheduled jobs with:
-- SELECT * FROM cron.job;

-- You can check job run history with:
-- SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;


-- ============================================================================
-- SECTION 7: INITIAL PARSING (Run once after migration)
-- ============================================================================
-- This parses all existing products. Run this ONCE after creating the tables.
-- For 30,000+ products, this may take 1-2 minutes.
--
-- UNCOMMENT AND RUN THIS SEPARATELY AFTER THE MIGRATION:

-- SELECT * FROM parse_unparsed_products();


-- ============================================================================
-- SECTION 8: HELPER VIEW (Optional)
-- ============================================================================
-- A view to easily see parsed product data for debugging

CREATE OR REPLACE VIEW products_parsed_view AS
SELECT
    index,
    name,
    brand,
    size_value,
    size_unit,
    normalized_name,
    price,
    promotion_price,
    retailer,
    parsed_at
FROM "Products"
WHERE parsed_at IS NOT NULL
ORDER BY parsed_at DESC;

COMMENT ON VIEW products_parsed_view IS
'View of all parsed products with extracted brand, size, and normalized name.
Useful for debugging the parsing logic.';


-- ============================================================================
-- VERIFICATION QUERIES (Run these to verify the migration worked)
-- ============================================================================
--
-- 1. Check new columns exist:
--    SELECT column_name, data_type
--    FROM information_schema.columns
--    WHERE table_name = 'Products'
--    AND column_name IN ('brand', 'size_value', 'size_unit', 'normalized_name', 'parsed_at');
--
-- 2. Test parsing function:
--    SELECT * FROM parse_product_name('Kellogg''s Corn Flakes 500g');
--    SELECT * FROM parse_product_name('Clover Full Cream Milk 2 L');
--    SELECT * FROM parse_product_name('Coca-Cola Zero 6 x 300ml');
--
-- 3. Check scheduled job:
--    SELECT * FROM cron.job WHERE jobname = 'parse-products-daily';
--
-- 4. After running initial parse, test comparison:
--    SELECT * FROM find_comparable_products('YOUR_PRODUCT_INDEX_HERE');
--
-- ============================================================================