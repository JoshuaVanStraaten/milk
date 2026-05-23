/// Example Supabase configuration
///
/// To use this app:
/// 1. Create a `.env` file in the project root directory
/// 2. Add your Supabase credentials to the `.env` file (see below)
/// 3. Never commit the `.env` file to version control
///
/// You can find your Supabase URL and Anon Key in:
/// Supabase Dashboard → Project Settings → API
///
/// ===========================================
/// .env file contents (create this file):
/// ===========================================
///
/// SUPABASE_URL=https://YOUR_PROJECT_ID.supabase.co
/// SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
///
/// ===========================================

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logger/logger.dart';

/// Supabase configuration and initialization
class SupabaseConfig {
  static final Logger _logger = Logger();

  /// Initialize Supabase
  /// This must be called before the app starts (in main.dart)
  static Future<void> initialize() async {
    try {
      // Load environment variables
      await dotenv.load(fileName: '.env');

      // Get credentials from .env
      final supabaseUrl = dotenv.env['SUPABASE_URL'];
      final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'];

      // Validate credentials
      if (supabaseUrl == null || supabaseUrl.isEmpty) {
        throw Exception('SUPABASE_URL not found in .env file');
      }
      if (supabaseAnonKey == null || supabaseAnonKey.isEmpty) {
        throw Exception('SUPABASE_ANON_KEY not found in .env file');
      }

      // Initialize Supabase
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce, // More secure auth flow
        ),
        realtimeClientOptions: const RealtimeClientOptions(
          logLevel: RealtimeLogLevel.info,
        ),
      );

      _logger.i('✅ Supabase initialized successfully');

      // Log current auth state (only in debug mode)
      if (kDebugMode) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) {
          _logger.d('User already logged in: ${session.user.email}');
        } else {
          _logger.d('No active session');
        }
      }
    } catch (e, stackTrace) {
      _logger.e(
        '❌ Failed to initialize Supabase',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow; // Re-throw so app knows initialization failed
    }
  }

  /// Get the Supabase client instance
  /// Use this throughout the app to access Supabase features
  static SupabaseClient get client => Supabase.instance.client;

  /// Get the current authenticated user (if any)
  static User? get currentUser => client.auth.currentUser;

  /// Check if user is authenticated
  static bool get isAuthenticated => currentUser != null;

  // Private constructor to prevent instantiation
  SupabaseConfig._();
}
