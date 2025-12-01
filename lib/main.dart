import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/config/supabase_config.dart';
import 'core/theme/app_theme.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/routes/app_router.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SharedPreferences for theme persistence
  final sharedPreferences = await SharedPreferences.getInstance();

  // Initialize Supabase
  await SupabaseConfig.initialize();

  // Run the app wrapped in ProviderScope (required for Riverpod)
  runApp(
    ProviderScope(
      overrides: [
        // Provide the SharedPreferences instance
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
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
      title: 'Savvy Grocery',
      debugShowCheckedModeBanner: false,

      // Theme configuration
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode, // Uses system/light/dark based on user preference
      // Router configuration
      routerConfig: router,
    );
  }
}
