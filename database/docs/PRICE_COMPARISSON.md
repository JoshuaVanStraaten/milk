# Price Comparison Feature - Technical Documentation

## Overview

This feature enables users to compare prices of the same/similar products across all 4 retailers (Pick n Pay, Checkers, Woolworths, Shoprite).

## How It Works

### 1. Product Name Parsing

Since we don't have barcodes, we extract structured data from product names:

```
"Kellogg's Corn Flakes 500g"
    ↓ parse_product_name()

brand: "kellogg's"
size_value: 500
size_unit: "g"
normalized_name: "kellogg's corn flakes"
```

### 2. Matching Algorithm

When a user requests price comparison:

```
User views "Kellogg's Corn Flakes 500g" at Pick n Pay
    ↓ find_comparable_products()

1. Find products at OTHER retailers where:
   - Same brand ("kellogg's") OR similar normalized_name

2. Score each match:
   - EXACT: Same brand + same size + name similarity > 60%
   - SIMILAR: Same brand + name similarity > 50%
   - FALLBACK: Name similarity > 40%

3. Return sorted by: match_type → similarity → price
```

### 3. Daily Processing Flow

```
Your Python Scraper (runs daily)
    ↓
Upserts 30K+ products to Supabase
(new columns brand/size_value/size_unit will be NULL)
    ↓
pg_cron job runs at 5:00 AM UTC
    ↓
parse_unparsed_products() processes all rows where parsed_at IS NULL
    ↓
Comparison data ready! ✅
```

---

## Database Changes

### New Columns on `Products` Table

| Column            | Type        | Description                                      |
| ----------------- | ----------- | ------------------------------------------------ |
| `brand`           | TEXT        | Extracted brand name (lowercase)                 |
| `size_value`      | DECIMAL     | Numeric size (e.g., 500, 1.5, 2)                 |
| `size_unit`       | TEXT        | Unit: "g", "kg", "ml", "l"                       |
| `normalized_name` | TEXT        | Name without size, lowercase, for fuzzy matching |
| `parsed_at`       | TIMESTAMPTZ | When parsing occurred (NULL = not parsed)        |

### New Indexes

| Index                          | Purpose                        |
| ------------------------------ | ------------------------------ |
| `idx_products_brand`           | Fast brand lookups             |
| `idx_products_size`            | Fast size matching             |
| `idx_products_normalized_name` | Fuzzy text search (pg_trgm)    |
| `idx_products_parsed_at`       | Find unparsed products quickly |

### New Functions

| Function                          | Purpose                        | How to Call                                          |
| --------------------------------- | ------------------------------ | ---------------------------------------------------- |
| `parse_product_name(text)`        | Extract brand/size from a name | `SELECT * FROM parse_product_name('Clover Milk 2L')` |
| `parse_unparsed_products()`       | Batch parse all new products   | `SELECT * FROM parse_unparsed_products()`            |
| `find_comparable_products(index)` | Find matching products         | `SELECT * FROM find_comparable_products('123')`      |

---

## How to Use from Flutter

### Call the comparison function via Supabase RPC:

```dart
final response = await SupabaseConfig.client
    .rpc('find_comparable_products', params: {
      'source_product_index': product.index,
    })
    .execute();

if (response.data != null) {
  final comparisons = response.data as List;
  // Each item has:
  // - product_index, product_name, product_price
  // - product_promotion_price, product_image_url
  // - retailer, match_type, similarity_score
  // - price_difference, size_value, size_unit
}
```

### Understanding the Response:

```json
[
  {
    "product_index": "456",
    "product_name": "Kellogg's Corn Flakes 500 g",
    "product_price": "R54.99",
    "product_promotion_price": null,
    "product_image_url": "https://...",
    "retailer": "Woolworths",
    "match_type": "EXACT",
    "similarity_score": 0.857,
    "price_difference": -5.0, // R5 cheaper!
    "size_value": 500,
    "size_unit": "g"
  },
  {
    "product_index": "789",
    "product_name": "Kellogg's Corn Flakes 750g",
    "product_price": "R69.99",
    "retailer": "Checkers",
    "match_type": "SIMILAR", // Different size
    "similarity_score": 0.714,
    "price_difference": 10.0,
    "size_value": 750,
    "size_unit": "g"
  }
]
```

---

## Match Types Explained

| Type         | Criteria                                       | Confidence                                           |
| ------------ | ---------------------------------------------- | ---------------------------------------------------- |
| **EXACT**    | Same brand + same size + name similarity > 60% | High - likely the same product                       |
| **SIMILAR**  | Same brand + name similarity > 50%             | Medium - same brand, possibly different variant/size |
| **FALLBACK** | Name similarity > 40%                          | Low - might be relevant alternative                  |

---

## Adjusting the Schedule

The pg_cron job is set to run at 5:00 AM UTC daily. To change this:

```sql
-- View current schedule
SELECT * FROM cron.job WHERE jobname = 'parse-products-daily';

-- Unschedule existing job
SELECT cron.unschedule('parse-products-daily');

-- Reschedule to different time (e.g., 3:00 AM UTC)
SELECT cron.schedule(
    'parse-products-daily',
    '0 3 * * *',  -- 3:00 AM UTC
    $$SELECT parse_unparsed_products()$$
);
```

### Cron Expression Reference:

```
┌───────────── minute (0 - 59)
│ ┌───────────── hour (0 - 23)
│ │ ┌───────────── day of month (1 - 31)
│ │ │ ┌───────────── month (1 - 12)
│ │ │ │ ┌───────────── day of week (0 - 6) (Sunday to Saturday)
│ │ │ │ │
* * * * *

Examples:
'0 5 * * *'     = 5:00 AM UTC daily
'30 4 * * *'    = 4:30 AM UTC daily
'0 */6 * * *'   = Every 6 hours
'0 5 * * 1'     = 5:00 AM UTC every Monday
```

---

## Future: Calling from Python Scraper

When you update your scraper, add this at the end:

```python
from supabase import create_client

# After all upserts complete...
supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

# Call the parsing function
result = supabase.rpc('parse_unparsed_products').execute()
print(f"Parsed {result.data[0]['products_parsed']} products in {result.data[0]['duration_ms']}ms")
```

This will parse new products immediately after upload, rather than waiting for the scheduled job.

---

## Debugging

### Check if products are being parsed:

```sql
-- Count parsed vs unparsed
SELECT
    COUNT(*) FILTER (WHERE parsed_at IS NOT NULL) AS parsed,
    COUNT(*) FILTER (WHERE parsed_at IS NULL) AS unparsed
FROM "Products";
```

### Test the parsing function:

```sql
SELECT * FROM parse_product_name('Kellogg''s Corn Flakes 500g');
SELECT * FROM parse_product_name('Clover Full Cream Milk 2 L');
SELECT * FROM parse_product_name('Coca-Cola Zero 6 x 300ml');
SELECT * FROM parse_product_name('County Fair Frozen Chicken Nuggets 400g');
```

### View recently parsed products:

```sql
SELECT * FROM products_parsed_view LIMIT 20;
```

### Test comparison function:

```sql
-- Replace with an actual product index from your database
SELECT * FROM find_comparable_products('YOUR_PRODUCT_INDEX');
```

### Check cron job status:

```sql
-- View scheduled jobs
SELECT * FROM cron.job;

-- View recent job runs
SELECT * FROM cron.job_run_details
ORDER BY start_time DESC
LIMIT 10;
```

---

## Adding New Brands

If you notice products not being matched because the brand isn't recognized, add it to the `brand_patterns` array in the `parse_product_name` function:

```sql
-- Edit the function and add to brand_patterns array:
'new brand name', 'alternate spelling',
```

Then re-parse affected products:

```sql
-- Reset parsing for products with the new brand
UPDATE "Products"
SET parsed_at = NULL
WHERE LOWER(name) LIKE 'new brand%';

-- Re-run parsing
SELECT * FROM parse_unparsed_products();
```

---

## Performance Notes

- **Initial parse**: ~30,000 products takes 30-60 seconds
- **Daily incremental**: Only processes new/updated products (very fast)
- **Comparison query**: Uses indexes, typically < 100ms
- **pg_trgm index**: Enables fast fuzzy text matching
