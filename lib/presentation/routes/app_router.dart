// lib/presentation/routes/app_router.dart
//

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/config/supabase_config.dart';
import '../../data/models/product.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/signup_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/products/product_list_screen.dart';
import '../screens/products/product_detail_screen.dart';
import '../screens/lists/my_lists_screen.dart';
import '../screens/lists/create_list_screen.dart';
import '../screens/lists/list_detail_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/main/main_shell_screen.dart';
import '../screens/recipes/recipe_screen.dart';

import '../screens/onboarding/store_selection_screen.dart';
import '../screens/products/live_browse_screen.dart';
import '../providers/auth_provider.dart';

import '../providers/store_provider.dart';
import 'page_transitions.dart';

/// Route names for easy reference
class AppRoutes {
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String signup = '/signup';
  static const String home = '/home';
  static const String stores = '/stores';
  static const String products = '/products';
  static const String productDetail = '/product';
  static const String recipes = '/recipes';
  static const String lists = '/lists';
  static const String profile = '/profile';
}

/// Router notifier that listens to auth state changes
class RouterNotifier extends ChangeNotifier {
  final Ref _ref;
  StreamSubscription? _authSubscription;

  RouterNotifier(this._ref) {
    // Listen to auth state changes
    _authSubscription = _ref
        .read(authRepositoryProvider)
        .authStateChanges
        .listen((authState) {
          // Notify router to re-evaluate redirects when auth state changes
          notifyListeners();
        });

    // Listen to store setup changes
    _ref.listen(hasCompletedStoreSetupProvider, (previous, next) {
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

/// Provider for router notifier
final _routerNotifierProvider = Provider<RouterNotifier>((ref) {
  return RouterNotifier(ref);
});

/// Router configuration provider
final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(_routerNotifierProvider);

  return GoRouter(
    initialLocation: AppRoutes.login,
    debugLogDiagnostics: true,
    refreshListenable:
        notifier, // THIS IS KEY - router rebuilds when notifier changes
    // Redirect logic - protect routes that require authentication
    redirect: (context, state) {
      final isAuthenticated = SupabaseConfig.isAuthenticated;
      final isGoingToAuth =
          state.matchedLocation == AppRoutes.login ||
          state.matchedLocation == AppRoutes.signup;
      final isGoingToOnboarding = state.matchedLocation == AppRoutes.onboarding;

      // Check store setup status
      final hasCompletedStoreSetup = ref.read(hasCompletedStoreSetupProvider);
      final needsOnboarding = !hasCompletedStoreSetup;

      // If not authenticated and trying to access protected route, go to login
      if (!isAuthenticated && !isGoingToAuth) {
        return AppRoutes.login;
      }

      // If authenticated and trying to access auth screens
      if (isAuthenticated && isGoingToAuth) {
        // Check if user needs store setup onboarding
        if (needsOnboarding) {
          return AppRoutes.onboarding;
        }
        return AppRoutes.home;
      }

      // If authenticated but hasn't completed store setup
      if (isAuthenticated && needsOnboarding && !isGoingToOnboarding) {
        return AppRoutes.onboarding;
      }

      // If on onboarding but already completed it, go to home
      if (isAuthenticated && !needsOnboarding && isGoingToOnboarding) {
        return AppRoutes.home;
      }

      // No redirect needed
      return null;
    },

    routes: [
      // ===== ONBOARDING ROUTE =====
      // Store selection onboarding screen
      GoRoute(
        path: AppRoutes.onboarding,
        pageBuilder: (context, state) => AppPageTransitions.fade(
          state: state,
          child: const StoreSelectionScreen(),
        ),
      ),

      // ===== AUTH ROUTES (fade transitions) =====

      // Login route
      GoRoute(
        path: AppRoutes.login,
        pageBuilder: (context, state) =>
            AppPageTransitions.fade(state: state, child: const LoginScreen()),
      ),

      // Signup route
      GoRoute(
        path: AppRoutes.signup,
        pageBuilder: (context, state) => AppPageTransitions.slideFromRight(
          state: state,
          child: const SignupScreen(),
        ),
      ),

      // ===== MAIN TAB ROUTES (fade for tab switches) =====

      // Home route (protected) - with bottom nav - index 0
      GoRoute(
        path: AppRoutes.home,
        pageBuilder: (context, state) => AppPageTransitions.fade(
          state: state,
          child: const MainShellScreen(currentIndex: 0, child: HomeScreen()),
        ),
      ),

      // Store selector route (protected) - with bottom nav - index 1
      GoRoute(
        path: '/stores',
        pageBuilder: (context, state) => AppPageTransitions.fade(
          state: state,
          child: const MainShellScreen(
            currentIndex: 1,
            child: LiveBrowseScreen(),
          ),
        ),
      ),

      // Recipes route (protected) - with bottom nav - index 2
      GoRoute(
        path: AppRoutes.recipes,
        pageBuilder: (context, state) => AppPageTransitions.fade(
          state: state,
          child: const MainShellScreen(currentIndex: 2, child: RecipeScreen()),
        ),
      ),

      // Lists route (protected) - with bottom nav - index 3
      GoRoute(
        path: AppRoutes.lists,
        pageBuilder: (context, state) => AppPageTransitions.fade(
          state: state,
          child: const MainShellScreen(currentIndex: 3, child: MyListsScreen()),
        ),
      ),

      // Profile route (protected) - with bottom nav - index 4
      GoRoute(
        path: AppRoutes.profile,
        pageBuilder: (context, state) => AppPageTransitions.fade(
          state: state,
          child: const MainShellScreen(currentIndex: 4, child: ProfileScreen()),
        ),
      ),

      // ===== DETAIL ROUTES (slide transitions) =====

      // Product list route (protected) - NO bottom nav (fullscreen)
      GoRoute(
        path: '/products/:retailer',
        pageBuilder: (context, state) {
          final retailer = state.pathParameters['retailer']!;
          return AppPageTransitions.slideFromRight(
            state: state,
            child: ProductListScreen(retailer: retailer),
          );
        },
      ),

      // Product detail route (protected) - NO bottom nav (fullscreen)
      // Uses 'extra' to pass the Product object
      GoRoute(
        path: '/product/:retailer',
        pageBuilder: (context, state) {
          final retailer = state.pathParameters['retailer']!;
          final product = state.extra as Product;
          return AppPageTransitions.slideUp(
            state: state,
            child: ProductDetailScreen(product: product, retailer: retailer),
          );
        },
      ),

      // Create list route (protected) - NO bottom nav
      GoRoute(
        path: '/lists/create',
        pageBuilder: (context, state) => AppPageTransitions.slideUp(
          state: state,
          child: const CreateListScreen(),
        ),
      ),

      // List detail route (protected) - NO bottom nav
      GoRoute(
        path: '/lists/:listId',
        pageBuilder: (context, state) {
          final listId = state.pathParameters['listId']!;
          return AppPageTransitions.slideFromRight(
            state: state,
            child: ListDetailScreen(listId: listId),
          );
        },
      ),
    ],

    // Error page
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Route not found: ${state.matchedLocation}')),
    ),
  );
});
