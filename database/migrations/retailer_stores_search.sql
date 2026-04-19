-- database/migrations/retailer_stores_search.sql
--
-- Adds full-text search to the retailer_stores table so users can find a
-- specific store by name (e.g. "Irene Village") instead of only getting
-- the auto-closest store per retailer.
--
-- Additions:
--   1. Generated tsvector column (store_name + city + address)
--   2. GIN index on the tsvector
--   3. search_retailer_stores() RPC — FTS + optional proximity boost
--
-- Safe to re-run — everything is IF NOT EXISTS / OR REPLACE.

-- ─────────────────────────────────────────────────────────────
-- 1. Generated tsvector column
-- ─────────────────────────────────────────────────────────────
ALTER TABLE public.retailer_stores
  ADD COLUMN IF NOT EXISTS search_vector tsvector
  GENERATED ALWAYS AS (
    to_tsvector(
      'simple',
      coalesce(store_name, '') || ' ' ||
      coalesce(city, '')       || ' ' ||
      coalesce(address, '')
    )
  ) STORED;

-- ─────────────────────────────────────────────────────────────
-- 2. GIN index for fast FTS
-- ─────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS retailer_stores_search_vector_idx
  ON public.retailer_stores USING GIN (search_vector);

-- ─────────────────────────────────────────────────────────────
-- 3. search_retailer_stores RPC
--
-- Drop first (return-signature changes can't be done via CREATE OR REPLACE).
-- ─────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.search_retailer_stores(text, text, double precision, double precision, integer);
DROP FUNCTION IF EXISTS public.search_retailer_stores(text, text, numeric, numeric, integer);
--
-- Ranking:
--   • With query + coords: ts_rank × 0.7 + proximity_score × 0.3
--   • With query, no coords: pure ts_rank
--   • Empty query + coords: sort by distance (nearest first)
--   • Empty query, no coords: arbitrary order (fallback only)
--
-- proximity_score = 1 − least(distance_km, 100) / 100  (0 at 100km+, 1 right on top)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.search_retailer_stores(
  p_retailer  text,
  p_query     text     DEFAULT NULL,
  p_latitude  double precision DEFAULT NULL,
  p_longitude double precision DEFAULT NULL,
  p_limit     integer  DEFAULT 20
)
RETURNS TABLE (
  retailer    text,
  store_code  text,
  store_name  text,
  province    text,
  city        text,
  address     text,
  latitude    numeric,
  longitude   numeric,
  distance_km numeric
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
    -- plainto_tsquery handles multi-word queries gracefully ("cape town")
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
    END AS distance_km
  FROM public.retailer_stores rs
  WHERE rs.retailer = p_retailer
    AND (NOT v_has_query OR rs.search_vector @@ v_tsquery)
  ORDER BY
    CASE
      WHEN v_has_query AND v_has_coords THEN
        -- Weighted: text relevance dominates, proximity breaks ties
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

-- Grant execute to the anon role (same pattern as find_all_nearest_stores)
GRANT EXECUTE ON FUNCTION public.search_retailer_stores(text, text, double precision, double precision, integer) TO anon, authenticated;
