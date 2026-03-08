// lib/core/constants/live_api_config.dart

/// Configuration for the Live API proxy (POC Supabase project).
///
/// This is a SEPARATE Supabase project from the production one.
/// It hosts only Edge Functions that proxy real-time retailer APIs.
/// The production Supabase (auth, user data, lists) is configured
/// in [SupabaseConfig] via .env file — that remains unchanged.
///
/// Eventually these Edge Functions will be migrated to the production
/// Supabase project, at which point this config can be consolidated.
class LiveApiConfig {
  /// POC Supabase project URL
  static const String supabaseUrl = 'https://pjqbvrluyvqvpegxumsd.supabase.co';

  /// POC Supabase anon key (safe to embed — RLS enforced server-side)
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
      '.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBqcWJ2cmx1eXZxdnBlZ3h1bXNkIiwi'
      'cm9sZSI6ImFub24iLCJpYXQiOjE3Mjg1NzE0MTUsImV4cCI6MjA0NDE0NzQxNX0'
      '.QXeQ-QEeUnOJF8l-tAJIELd08CokVqa1iKu0TLw5P_Q';

  /// Build the full URL for an Edge Function.
  ///
  /// Example: `edgeFunctionUrl('stores-nearby')`
  /// Returns: `https://pjqbvrluyvqvpegxumsd.supabase.co/functions/v1/stores-nearby`
  static String edgeFunctionUrl(String functionName) {
    return '$supabaseUrl/functions/v1/$functionName';
  }

  /// HTTP headers required for all Edge Function calls.
  static Map<String, String> get headers => {
    'Authorization': 'Bearer $supabaseAnonKey',
    'Content-Type': 'application/json',
  };

  /// Request timeout for Edge Function calls.
  /// Edge Functions can be slow on cold starts, so we allow 30s.
  static const Duration requestTimeout = Duration(seconds: 30);

  // Private constructor to prevent instantiation
  LiveApiConfig._();
}
