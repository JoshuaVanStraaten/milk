-- ============================================================================
-- Milk Premium: Subscription & Recipe Usage Tables
-- ============================================================================

-- User subscriptions (tracks premium status)
CREATE TABLE IF NOT EXISTS user_subscriptions (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  tier text NOT NULL DEFAULT 'free' CHECK (tier IN ('free', 'premium')),
  started_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz,
  trial_started_at timestamptz,
  trial_ends_at timestamptz,
  platform text CHECK (platform IN ('android', 'ios', 'web')),
  store_transaction_id text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id)
);

-- Recipe usage tracking (for weekly free tier limits)
CREATE TABLE IF NOT EXISTS recipe_usage (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  generated_at timestamptz NOT NULL DEFAULT now(),
  recipe_name text NOT NULL
);

-- Index for fast weekly usage queries
CREATE INDEX IF NOT EXISTS idx_recipe_usage_user_date
  ON recipe_usage(user_id, generated_at DESC);

-- Index for subscription lookups
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_user
  ON user_subscriptions(user_id);

-- RLS policies
ALTER TABLE user_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE recipe_usage ENABLE ROW LEVEL SECURITY;

-- Users can only read/write their own subscription
CREATE POLICY "Users can view own subscription"
  ON user_subscriptions FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own subscription"
  ON user_subscriptions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own subscription"
  ON user_subscriptions FOR UPDATE
  USING (auth.uid() = user_id);

-- Users can only read/write their own usage
CREATE POLICY "Users can view own usage"
  ON recipe_usage FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own usage"
  ON recipe_usage FOR INSERT
  WITH CHECK (auth.uid() = user_id);
