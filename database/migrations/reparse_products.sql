-- ============================================================================
-- RE-PARSE ALL PRODUCTS
-- ============================================================================
-- Run this in Supabase SQL Editor to fix the mismatched parsing data
--
-- This script:
-- 1. Clears all parsed fields (sets parsed_at = NULL)
-- 2. Re-runs the parsing on all products
-- ============================================================================

-- STEP 1: Check how many products have mismatched data
-- (Where the brand in normalized_name doesn't match the brand field)
SELECT COUNT(*) as mismatched_count
FROM "Products"
WHERE parsed_at IS NOT NULL
  AND normalized_name IS NOT NULL
  AND brand IS NOT NULL
  AND normalized_name NOT LIKE '%' || brand || '%';

-- STEP 2: See some examples of mismatched products
SELECT
    index,
    name,
    brand,
    normalized_name,
    size_value,
    size_unit,
    retailer
FROM "Products"
WHERE parsed_at IS NOT NULL
  AND normalized_name IS NOT NULL
  AND brand IS NOT NULL
  AND LOWER(name) NOT LIKE '%' || brand || '%'
LIMIT 20;

-- ============================================================================
-- STEP 3: RESET ALL PARSED DATA
-- ============================================================================
-- This will set parsed_at to NULL, triggering re-parsing
-- UNCOMMENT THIS SECTION WHEN READY TO EXECUTE

/*
UPDATE "Products"
SET
    brand = NULL,
    size_value = NULL,
    size_unit = NULL,
    normalized_name = NULL,
    parsed_at = NULL;
*/

-- ============================================================================
-- STEP 4: RE-RUN THE PARSING
-- ============================================================================
-- After resetting, run the parsing function
-- This may take 1-2 minutes for 30,000+ products
-- UNCOMMENT THIS SECTION WHEN READY TO EXECUTE

/*
SELECT * FROM parse_unparsed_products();
*/

-- ============================================================================
-- STEP 5: VERIFY THE FIX
-- ============================================================================
-- After re-parsing, run this to verify the aQuelle product is fixed

/*
SELECT
    index,
    name,
    brand,
    normalized_name,
    size_value,
    size_unit,
    retailer
FROM "Products"
WHERE LOWER(name) LIKE '%aquelle%strawberry%'
LIMIT 5;
*/

-- ============================================================================
-- ALTERNATIVE: FIX ONLY MISMATCHED PRODUCTS (Faster)
-- ============================================================================
-- If you want to only re-parse products that appear mismatched
-- UNCOMMENT THIS SECTION WHEN READY TO EXECUTE

/*
-- Reset only mismatched products
UPDATE "Products"
SET
    brand = NULL,
    size_value = NULL,
    size_unit = NULL,
    normalized_name = NULL,
    parsed_at = NULL
WHERE
    parsed_at IS NOT NULL
    AND normalized_name IS NOT NULL
    AND brand IS NOT NULL
    AND LOWER(name) NOT LIKE '%' || brand || '%';

-- Then re-parse
SELECT * FROM parse_unparsed_products();
*/