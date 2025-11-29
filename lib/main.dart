import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/config/supabase_config.dart';
import 'core/theme/app_theme.dart';
import 'presentation/routes/app_router.dart';

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await SupabaseConfig.initialize();

  // Run the app wrapped in ProviderScope (required for Riverpod)
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Get router from provider
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Milk',
      debugShowCheckedModeBanner: false, // Remove debug banner
      theme: AppTheme.lightTheme, // Use our custom theme
      routerConfig: router, // Use go_router
    );
  }
}
