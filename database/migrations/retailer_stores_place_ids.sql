-- database/migrations/retailer_stores_place_ids.sql
--
-- Adds Google Place ID support to retailer_stores.
--
-- WHY: Woolworths' `confirmPlace` product API requires a real Google Place ID
-- (e.g. "ChIJvQaozVFCzB0ReI-UDsBSrW8"). Until now the Flutter app has been
-- sending the Woolies store_code as a fallback, which fails silently — browse
-- prices have been unreliable for every user.
--
-- Scope: Woolworths is the only retailer that needs this right now. Other
-- retailers may use it in future (e.g. to open Google Maps directions to a
-- store), so we add it as a generic nullable column rather than Woolies-only.
--
-- Safe to re-run — IF NOT EXISTS / OR REPLACE throughout.

-- ─────────────────────────────────────────────────────────────
-- 1. Columns
-- ─────────────────────────────────────────────────────────────
ALTER TABLE public.retailer_stores
  ADD COLUMN IF NOT EXISTS place_id text;

ALTER TABLE public.retailer_stores
  ADD COLUMN IF NOT EXISTS place_nickname text;

-- ─────────────────────────────────────────────────────────────
-- 2. Update find_all_nearest_stores to return the new fields
--    (RETURN signature changes → DROP first)
-- ─────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.find_all_nearest_stores(numeric, numeric);
DROP FUNCTION IF EXISTS public.find_all_nearest_stores(double precision, double precision);

CREATE OR REPLACE FUNCTION public.find_all_nearest_stores(
  p_latitude numeric,
  p_longitude numeric
)
RETURNS TABLE (
  retailer       text,
  store_code     text,
  store_name     text,
  province       text,
  city           text,
  address        text,
  latitude       numeric,
  longitude      numeric,
  distance_km    numeric,
  place_id       text,
  place_nickname text
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT DISTINCT ON (rs.retailer)
    rs.retailer,
    rs.store_code,
    rs.store_name,
    rs.province,
    rs.city,
    rs.address,
    rs.latitude,
    rs.longitude,
    ROUND(
      (ST_Distance(
        rs.location,
        ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326)::geography
      ) / 1000)::DECIMAL, 2
    ) AS distance_km,
    rs.place_id,
    rs.place_nickname
  FROM public.retailer_stores rs
  ORDER BY
    rs.retailer,
    rs.location <-> ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326)::geography;
END;
$$;

GRANT EXECUTE ON FUNCTION public.find_all_nearest_stores(numeric, numeric)
  TO anon, authenticated;

-- ─────────────────────────────────────────────────────────────
-- 3. Update search_retailer_stores to return the new fields
--    (RETURN signature changes → DROP first)
-- ─────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.search_retailer_stores(text, text, double precision, double precision, integer);
DROP FUNCTION IF EXISTS public.search_retailer_stores(text, text, numeric, numeric, integer);

CREATE OR REPLACE FUNCTION public.search_retailer_stores(
  p_retailer  text,
  p_query     text     DEFAULT NULL,
  p_latitude  double precision DEFAULT NULL,
  p_longitude double precision DEFAULT NULL,
  p_limit     integer  DEFAULT 20
)
RETURNS TABLE (
  retailer       text,
  store_code     text,
  store_name     text,
  province       text,
  city           text,
  address        text,
  latitude       numeric,
  longitude      numeric,
  distance_km    numeric,
  place_id       text,
  place_nickname text
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_has_query  boolean := p_query IS NOT NULL AND btrim(p_query) <> '';
  v_has_coords boolean := p_latitude IS NOT NULL AND p_longitude IS NOT NULL;
  v_tsquery    tsquery;
  v_user_point geography;
BEGIN
  IF v_has_query THEN
    v_tsquery := plainto_tsquery('simple', p_query);
  END IF;

  IF v_has_coords THEN
    v_user_point := ST_SetSRID(ST_MakePoint(p_longitude, p_latitude), 4326)::geography;
  END IF;

  RETURN QUERY
  SELECT
    rs.retailer,
    rs.store_code,
    rs.store_name,
    rs.province,
    rs.city,
    rs.address,
    rs.latitude,
    rs.longitude,
    CASE
      WHEN v_has_coords
        THEN ROUND((ST_Distance(rs.location, v_user_point) / 1000.0)::numeric, 2)
      ELSE NULL
    END AS distance_km,
    rs.place_id,
    rs.place_nickname
  FROM public.retailer_stores rs
  WHERE rs.retailer = p_retailer
    AND (NOT v_has_query OR rs.search_vector @@ v_tsquery)
  ORDER BY
    CASE
      WHEN v_has_query AND v_has_coords THEN
        -(
          ts_rank(rs.search_vector, v_tsquery) * 0.7
          + (1.0 - LEAST(ST_Distance(rs.location, v_user_point) / 1000.0, 100.0) / 100.0) * 0.3
        )
      WHEN v_has_query THEN
        -ts_rank(rs.search_vector, v_tsquery)
      WHEN v_has_coords THEN
        ST_Distance(rs.location, v_user_point)
      ELSE 0
    END
  LIMIT GREATEST(p_limit, 1);
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_retailer_stores(text, text, double precision, double precision, integer)
  TO anon, authenticated;
