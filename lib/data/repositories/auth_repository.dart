import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import '../models/user_profile.dart';

/// Repository for authentication operations
/// Handles sign up, sign in, sign out, Google OAuth, and user profile management
class AuthRepository {
  final SupabaseClient _supabase = SupabaseConfig.client;
  final Logger _logger = Logger();

  /// Sign up a new user with email and password
  Future<UserProfile> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      _logger.i('Attempting to sign up user: $email');

      // Step 1: Create auth user in Supabase Auth
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
      );

      if (response.user == null) {
        throw Exception('Sign up failed: No user returned');
      }

      final user = response.user!;
      _logger.i('✅ Auth user created: ${user.id}');

      // Step 2: Wait a moment for any triggers to complete
      await Future.delayed(const Duration(milliseconds: 500));

      // Step 3: Try to fetch the profile (might be created by trigger)
      try {
        final profile = await getUserProfile(user.id);
        _logger.i(
          '✅ User profile found (created by trigger or previous attempt)',
        );

        // Update display name if provided
        if (displayName != null && displayName.isNotEmpty) {
          return await updateUserProfile(
            profile.copyWith(displayName: displayName),
          );
        }

        return profile;
      } catch (fetchError) {
        // Profile doesn't exist, create it manually
        _logger.d('Profile not found, creating manually');

        final newProfile = UserProfile(
          id: user.id,
          createdAt: DateTime.now(),
          emailAddress: email,
          displayName: displayName,
          mailingList: false,
        );

        // Try to insert
        try {
          await _supabase.from('user_profiles').insert(newProfile.toJson());
          _logger.i('✅ User profile created manually');
          return newProfile;
        } catch (insertError) {
          // Race condition - profile was just created, fetch it
          _logger.w('Insert failed (concurrent creation), fetching profile');
          return await getUserProfile(user.id);
        }
      }
    } on AuthException catch (e) {
      _logger.e('Auth error during sign up: ${e.message}');
      throw Exception('Sign up failed: ${e.message}');
    } catch (e, stackTrace) {
      _logger.e(
        'Unexpected error during sign up',
        error: e,
        stackTrace: stackTrace,
      );
      throw Exception('Sign up failed: $e');
    }
  }

  /// Sign in existing user with email and password
  Future<UserProfile> signIn({
    required String email,
    required String password,
  }) async {
    try {
      _logger.i('Attempting to sign in user: $email');

      // Step 1: Sign in with Supabase Auth
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        throw Exception('Sign in failed: No user returned');
      }

      final user = response.user!;
      _logger.i('✅ User signed in: ${user.id}');

      // Step 2: Fetch user profile from database
      final profile = await getUserProfile(user.id);

      return profile;
    } on AuthException catch (e) {
      _logger.e('Auth error during sign in: ${e.message}');
      throw Exception('Sign in failed: ${e.message}');
    } catch (e, stackTrace) {
      _logger.e(
        'Unexpected error during sign in',
        error: e,
        stackTrace: stackTrace,
      );
      throw Exception('Sign in failed: $e');
    }
  }

  /// Sign in with Google OAuth
  /// This initiates the OAuth flow - the actual sign-in completes via deep link callback
  Future<void> signInWithGoogle() async {
    try {
      _logger.i('Initiating Google OAuth sign in');

      await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'com.ubicorp.milkza://login-callback',
        authScreenLaunchMode: LaunchMode.externalApplication,
      );

      _logger.i('✅ Google OAuth flow initiated');
    } on AuthException catch (e) {
      _logger.e('Auth error during Google sign in: ${e.message}');
      throw Exception('Google sign in failed: ${e.message}');
    } catch (e, stackTrace) {
      _logger.e(
        'Unexpected error during Google sign in',
        error: e,
        stackTrace: stackTrace,
      );
      throw Exception('Google sign in failed: $e');
    }
  }

  /// Handle the OAuth callback and ensure user profile exists
  /// Call this after the OAuth redirect returns to the app
  Future<UserProfile?> handleOAuthCallback() async {
    try {
      final user = _supabase.auth.currentUser;

      if (user == null) {
        _logger.w('No user found after OAuth callback');
        return null;
      }

      _logger.i('✅ OAuth callback - user authenticated: ${user.id}');

      // Extract display name from Google OAuth metadata
      final oauthDisplayName =
          user.userMetadata?['full_name'] as String? ??
          user.userMetadata?['name'] as String? ??
          user.email?.split('@').first;

      // Try to fetch existing profile
      try {
        final profile = await getUserProfile(user.id);
        _logger.i('✅ Existing user profile found');

        // If profile exists but display name is missing, update it from OAuth data
        if (profile.displayName == null && oauthDisplayName != null) {
          _logger.i('Updating missing display name from OAuth data');
          final updated = profile.copyWith(displayName: oauthDisplayName);
          return await updateUserProfile(updated);
        }

        return profile;
      } catch (e) {
        // Profile doesn't exist, create one from OAuth data
        _logger.d('Profile not found, creating from OAuth data');

        final newProfile = UserProfile(
          id: user.id,
          createdAt: DateTime.now(),
          emailAddress: user.email ?? '',
          displayName: oauthDisplayName,
          mailingList: false,
        );

        try {
          await _supabase.from('user_profiles').insert(newProfile.toJson());
          _logger.i('✅ User profile created from OAuth data');
          return newProfile;
        } catch (insertError) {
          // Race condition - try fetching again
          _logger.w('Insert failed, fetching profile');
          return await getUserProfile(user.id);
        }
      }
    } catch (e, stackTrace) {
      _logger.e(
        'Error handling OAuth callback',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Sign out the current user
  Future<void> signOut() async {
    try {
      _logger.i('Signing out user');
      await _supabase.auth.signOut();
      _logger.i('✅ User signed out');
    } catch (e, stackTrace) {
      _logger.e('Error during sign out', error: e, stackTrace: stackTrace);
      throw Exception('Sign out failed: $e');
    }
  }

  /// Get user profile from database by user ID.
  /// Retries with exponential backoff on transient network errors.
  Future<UserProfile> getUserProfile(String userId) async {
    const maxAttempts = 3;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        _logger.d('Fetching user profile for: $userId (attempt $attempt)');

        final response = await _supabase
            .from('user_profiles')
            .select()
            .eq('id', userId)
            .single();

        final profile = UserProfile.fromJson(response);
        _logger.d('✅ User profile fetched');

        return profile;
      } catch (e, stackTrace) {
        final isTransient = e.toString().contains('SocketException') ||
            e.toString().contains('Failed host lookup') ||
            e.toString().contains('Connection refused') ||
            e.toString().contains('Connection reset') ||
            e.toString().contains('TimeoutException');

        if (isTransient && attempt < maxAttempts) {
          final delay = Duration(seconds: attempt * 2);
          _logger.w(
            'Transient error fetching profile (attempt $attempt/$maxAttempts), '
            'retrying in ${delay.inSeconds}s...',
          );
          await Future.delayed(delay);
          continue;
        }

        _logger.e(
          'Error fetching user profile',
          error: e,
          stackTrace: stackTrace,
        );
        throw Exception('Failed to fetch user profile: $e');
      }
    }

    // Unreachable, but satisfies the analyzer
    throw Exception('Failed to fetch user profile after $maxAttempts attempts');
  }

  /// Update user profile
  Future<UserProfile> updateUserProfile(UserProfile profile) async {
    try {
      _logger.i('Updating user profile: ${profile.id}');

      await _supabase
          .from('user_profiles')
          .update(profile.toJson())
          .eq('id', profile.id);

      _logger.i('✅ User profile updated');

      return profile;
    } catch (e, stackTrace) {
      _logger.e(
        'Error updating user profile',
        error: e,
        stackTrace: stackTrace,
      );
      throw Exception('Failed to update profile: $e');
    }
  }

  /// Get current authenticated user (if any)
  User? getCurrentUser() {
    return _supabase.auth.currentUser;
  }

  /// Check if user is authenticated
  bool isAuthenticated() {
    return getCurrentUser() != null;
  }

  /// Stream of auth state changes
  /// Useful for reacting to login/logout events
  Stream<AuthState> get authStateChanges {
    return _supabase.auth.onAuthStateChange;
  }
}
