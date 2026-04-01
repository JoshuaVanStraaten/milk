-- Schedule automatic fuel price refresh via pg_cron + pg_net
-- SA fuel prices change on the first Wednesday of each month (DoE announcement)
-- This job runs every Wednesday between the 1st-21st of each month at 10:00 SAST (08:00 UTC)
-- to cover the announcement day + buffer for late updates.

-- Enable required extensions (may already be enabled on Supabase)
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Schedule the fuel price refresh job
SELECT cron.schedule(
  'refresh-fuel-prices',
  '0 8 1-21 * 3',  -- Every Wednesday between 1st-21st of month, 08:00 UTC (10:00 SAST)
  $$
  SELECT net.http_post(
    url := 'https://pjqbvrluyvqvpegxumsd.supabase.co/functions/v1/fuel-prices',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := '{"action": "refresh"}'::jsonb
  );
  $$
);
