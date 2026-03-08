import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/user_profile.dart';
import '../../data/repositories/auth_repository.dart';

/// Provider for the AuthRepository instance
/// This creates a single shared instance of AuthRepository
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

/// Provider that listens to Supabase auth state changes
/// Automatically updates when user logs in/out
final authStateProvider = StreamProvider<AuthState>((ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  return authRepository.authStateChanges;
});

/// Provider for the currently authenticated user profile
/// Returns null if user is not authenticated
final currentUserProfileProvider = FutureProvider<UserProfile?>((ref) async {
  // Watch auth state - when it changes, this provider rebuilds
  final authState = ref.watch(authStateProvider);

  return authState.when(
    data: (state) async {
      final user = state.session?.user;
      if (user == null) return null;

      // Fetch user profile from database
      final authRepository = ref.watch(authRepositoryProvider);
      try {
        final profile = await authRepository.getUserProfile(user.id);

        // If display name is missing, try to fill it from Google OAuth metadata
        // Only use full_name/name from metadata (NOT email prefix - that's a poor fallback)
        if (profile.displayName == null) {
          final metaName =
              user.userMetadata?['full_name'] as String? ??
              user.userMetadata?['name'] as String?;

          if (metaName != null && metaName.isNotEmpty) {
            final updated = profile.copyWith(displayName: metaName);
            return await authRepository.updateUserProfile(updated);
          }
        }

        return profile;
      } catch (e) {
        // If profile doesn't exist or error, return null
        return null;
      }
    },
    loading: () => null,
    error: (_, __) => null,
  );
});

/// Notifier for authentication actions (sign up, sign in, sign out, Google OAuth)
/// This is the main controller for auth operations
class AuthNotifier extends StateNotifier<AsyncValue<UserProfile?>> {
  final AuthRepository _authRepository;
  final Ref _ref;

  AuthNotifier(this._authRepository, this._ref)
    : super(const AsyncValue.data(null));

  /// Sign up a new user
  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    // Set loading state
    state = const AsyncValue.loading();

    try {
      // Call repository to sign up
      final profile = await _authRepository.signUp(
        email: email,
        password: password,
        displayName: displayName,
      );

      // Set success state with user profile
      state = AsyncValue.data(profile);

      // Invalidate the profile provider so it refetches with the correct display name
      _ref.invalidate(currentUserProfileProvider);
    } catch (e, stackTrace) {
      // Set error state
      state = AsyncValue.error(e, stackTrace);
    }
  }

  /// Sign in existing user
  Future<void> signIn({required String email, required String password}) async {
    state = const AsyncValue.loading();

    try {
      final profile = await _authRepository.signIn(
        email: email,
        password: password,
      );

      state = AsyncValue.data(profile);
    } catch (e, stackTrace) {
      state = AsyncValue.error(e, stackTrace);
    }
  }

  /// Sign in with Google OAuth
  /// Note: This initiates the OAuth flow. The actual completion happens
  /// via deep link callback, which triggers handleOAuthCallback()
  Future<void> signInWithGoogle() async {
    state = const AsyncValue.loading();

    try {
      await _authRepository.signInWithGoogle();
      // Don't set state here - the OAuth redirect will handle it
      // The auth state stream will update when the user returns
    } catch (e, stackTrace) {
      state = AsyncValue.error(e, stackTrace);
    }
  }

  /// Handle OAuth callback after redirect
  /// Call this when the app receives the OAuth deep link callback
  Future<void> handleOAuthCallback() async {
    state = const AsyncValue.loading();

    try {
      final profile = await _authRepository.handleOAuthCallback();

      if (profile != null) {
        state = AsyncValue.data(profile);
      } else {
        state = const AsyncValue.data(null);
      }
    } catch (e, stackTrace) {
      state = AsyncValue.error(e, stackTrace);
    }
  }

  /// Sign out current user
  Future<void> signOut() async {
    state = const AsyncValue.loading();

    try {
      await _authRepository.signOut();
      state = const AsyncValue.data(null);
    } catch (e, stackTrace) {
      state = AsyncValue.error(e, stackTrace);
    }
  }

  /// Clear any error state
  void clearError() {
    if (state.hasError) {
      state = const AsyncValue.data(null);
    }
  }
}

/// Provider for AuthNotifier
/// Use this in your UI to call signUp, signIn, signInWithGoogle, signOut
final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<UserProfile?>>((ref) {
      final authRepository = ref.watch(authRepositoryProvider);
      return AuthNotifier(authRepository, ref);
    });
