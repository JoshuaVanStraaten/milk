-- ============================================================================
-- FUEL PRICES TABLE - DATABASE MIGRATION
-- ============================================================================
-- Run this in Supabase SQL Editor (Dashboard > SQL Editor > New Query)
-- on the PRODUCTION Supabase project (where auth/lists live)
--
-- This migration adds:
-- 1. fuel_prices table for storing SA fuel prices (updated monthly)
-- 2. RLS policy for public read access
-- 3. Seed data with March 2026 prices
--
-- Source: AA (aa.co.za) publishes prices on the first Wednesday of each month
-- ============================================================================


-- ============================================================================
-- SECTION 1: CREATE FUEL PRICES TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS fuel_prices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fuel_type text NOT NULL,           -- 'petrol_93', 'petrol_95', 'diesel_50ppm', 'diesel_500ppm'
  region text NOT NULL,              -- 'coastal', 'inland'
  price_per_litre numeric NOT NULL,  -- in Rands (e.g. 20.30)
  effective_date date NOT NULL,      -- first Wednesday of month when price took effect
  source text DEFAULT 'aa',          -- data source identifier
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(fuel_type, region)          -- one row per fuel_type+region combo (upsert target)
);

CREATE INDEX IF NOT EXISTS idx_fuel_prices_type_region ON fuel_prices(fuel_type, region);


-- ============================================================================
-- SECTION 2: ROW LEVEL SECURITY
-- ============================================================================
-- Public read access via anon key. No client writes (service role only from Edge Function).

ALTER TABLE fuel_prices ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public read fuel_prices"
  ON fuel_prices
  FOR SELECT
  USING (true);


-- ============================================================================
-- SECTION 3: SEED DATA (March 2026 prices from AA)
-- ============================================================================
-- Effective date: 2026-03-04 (first Wednesday of March 2026)

INSERT INTO fuel_prices (fuel_type, region, price_per_litre, effective_date, source)
VALUES
  ('petrol_93', 'coastal', 19.40, '2026-03-04', 'aa'),
  ('petrol_93', 'inland',  20.19, '2026-03-04', 'aa'),
  ('petrol_95', 'coastal', 19.47, '2026-03-04', 'aa'),
  ('petrol_95', 'inland',  20.30, '2026-03-04', 'aa'),
  ('diesel_50ppm',  'coastal', 17.84, '2026-03-04', 'aa'),
  ('diesel_50ppm',  'inland',  18.60, '2026-03-04', 'aa'),
  ('diesel_500ppm', 'coastal', 17.70, '2026-03-04', 'aa'),
  ('diesel_500ppm', 'inland',  18.53, '2026-03-04', 'aa')
ON CONFLICT (fuel_type, region) DO UPDATE SET
  price_per_litre = EXCLUDED.price_per_litre,
  effective_date = EXCLUDED.effective_date,
  source = EXCLUDED.source,
  updated_at = now();


-- ============================================================================
-- VERIFICATION
-- ============================================================================
-- Run after migration to verify:
-- SELECT fuel_type, region, price_per_litre, effective_date FROM fuel_prices ORDER BY fuel_type, region;
-- Expected: 8 rows (4 fuel types x 2 regions)
