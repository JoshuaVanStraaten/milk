---
name: supabase-edge-functions
description: Use when creating or modifying Supabase Edge Functions, database queries, or backend logic. Covers retailer API proxying, CORS, CSRF bypass, and deployment.
---

# Supabase & Edge Functions for Milk

## Edge Function Deployment

```powershell
supabase functions deploy <function-name> --project-ref pjqbvrluyvqvpegxumsd
```

## Retailer API Patterns

| Retailer   | API Type        | Auth Needed     | Notes                                            |
| ---------- | --------------- | --------------- | ------------------------------------------------ |
| Pick n Pay | SAP Hybris REST | No              | Direct HTTP GET                                  |
| Woolworths | Constructor.io  | No (public key) | National pricing only                            |
| Checkers   | Custom API      | CSRF token      | Fetch homepage → extract token → use in requests |
| Shoprite   | Custom API      | CSRF token      | Same as Checkers                                 |

All four work via **pure HTTP** — no headless browser needed.

## Edge Function Template

```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: corsHeaders });
  try {
    const body = await req.json();
    // ... retailer-specific logic
    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
```

## Response Format (all retailers must return)

```json
{
  "products": [
    {
      "name": "Product Name",
      "price": "R29.99",
      "promotion_price": "2 For R50",
      "retailer": "Pick n Pay",
      "image_url": "https://...",
      "promotion_valid": "Valid until 15 Mar"
    }
  ]
}
```

Use `"No promo"` for `promotion_price` when no promotion exists.

## Supabase Flutter Client

```dart
final supabase = Supabase.instance.client;

// Query
final data = await supabase.from('Products').select().eq('retailer', 'Pick n Pay').range(0, 19);

// Edge Function call
final response = await supabase.functions.invoke('products-pnp', body: { ... });
```

## PostGIS (stores-nearby)

```sql
SELECT *, ST_Distance(location, ST_SetSRID(ST_MakePoint($lng, $lat), 4326)) as distance
FROM retailer_stores
WHERE ST_DWithin(location, ST_SetSRID(ST_MakePoint($lng, $lat), 4326), $radius)
ORDER BY distance;
```
