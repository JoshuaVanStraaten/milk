import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/config/supabase_config.dart';
import 'core/theme/app_theme.dart';
import 'data/local/hive_database.dart';
import 'data/services/connectivity_service.dart';
import 'data/services/sync_service.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/routes/app_router.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SharedPreferences for theme and store persistence
  final sharedPreferences = await SharedPreferences.getInstance();

  // Initialize Hive for offline storage
  await HiveDatabase.initialize();

  // Initialize Supabase
  await SupabaseConfig.initialize();

  // Initialize connectivity service
  final connectivityService = ConnectivityService();
  await connectivityService.initialize();

  // Run the app wrapped in ProviderScope (required for Riverpod)
  runApp(
    ProviderScope(
      overrides: [
        // Provide the SharedPreferences instance
        // This is used by themeProvider and storeSelectionProvider
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        // Provide the initialized connectivity service
        connectivityServiceProvider.overrideWithValue(connectivityService),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Get router from provider
    final router = ref.watch(routerProvider);

    // Get theme mode from provider
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Milk',
      debugShowCheckedModeBanner: false,

      // Theme configuration
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode, // Uses system/light/dark based on user preference
      // Router configuration
      routerConfig: router,
      // Add global offline banner overlay
      builder: (context, child) {
        return _GlobalOfflineBanner(child: child ?? const SizedBox());
      },
    );
  }
}

/// Global offline/sync banner that appears on ALL screens
class _GlobalOfflineBanner extends ConsumerStatefulWidget {
  final Widget child;

  const _GlobalOfflineBanner({required this.child});

  @override
  ConsumerState<_GlobalOfflineBanner> createState() =>
      _GlobalOfflineBannerState();
}

class _GlobalOfflineBannerState extends ConsumerState<_GlobalOfflineBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  bool _showBanner = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1), // Start from bottom (off-screen)
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    // Listen for animation to complete to hide banner completely
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        if (mounted) setState(() => _showBanner = false);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateVisibility({
    required bool isOffline,
    required SyncStatus syncStatus,
  }) {
    final shouldShow = isOffline || syncStatus == SyncStatus.syncing;

    // Skip if not initialized yet
    if (!_initialized) {
      _initialized = true;
      if (shouldShow) {
        _showBanner = true;
        _controller.forward();
      }
      return;
    }

    if (shouldShow && !_showBanner) {
      setState(() => _showBanner = true);
      _controller.forward();
    } else if (!shouldShow && _showBanner) {
      _controller.reverse();
    } else if (_showBanner) {
      // Just update the content without animation
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final connectivityService = ref.watch(connectivityServiceProvider);
    final syncStatusAsync = ref.watch(syncStatusProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Initialize sync service (triggers listening for connectivity changes)
    ref.watch(syncServiceProvider);

    // Bottom nav height + safe area
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    const bottomNavHeight = 56.0; // Standard bottom nav height

    return StreamBuilder<ConnectivityStatus>(
      stream: connectivityService.statusStream,
      initialData: connectivityService.currentStatus,
      builder: (context, connectivitySnapshot) {
        final connectivityStatus =
            connectivitySnapshot.data ?? ConnectivityStatus.online;
        final isOffline = connectivityStatus == ConnectivityStatus.offline;
        final syncStatus = syncStatusAsync.valueOrNull ?? SyncStatus.idle;

        // Schedule the visibility update after build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _updateVisibility(isOffline: isOffline, syncStatus: syncStatus);
          }
        });

        // Determine banner content
        final isSyncing = syncStatus == SyncStatus.syncing;
        final bannerColor = isSyncing
            ? (isDark
                  ? const Color(0xFF1565C0)
                  : const Color(0xFF2196F3)) // Blue for syncing
            : (isDark
                  ? const Color(0xFFE65100)
                  : const Color(0xFFFF9800)); // Orange for offline

        return Stack(
          children: [
            // Main app content - takes full screen
            widget.child,

            // Banner overlay at bottom - only rendered when needed
            if (_showBanner)
              Positioned(
                // Position above the bottom nav bar
                bottom: bottomNavHeight + bottomPadding,
                left: 16,
                right: 16,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: bannerColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (isSyncing) ...[
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Syncing changes...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ] else ...[
                            const Icon(
                              Icons.cloud_off,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'You\'re offline',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Changes will sync',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
