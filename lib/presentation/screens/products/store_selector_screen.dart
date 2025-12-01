import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';

class StoreSelectorScreen extends StatelessWidget {
  const StoreSelectorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('Select Store')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),

            // Header
            Text(
              'Browse Products',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'Select a store to view products and specials',
              style: TextStyle(
                fontSize: 16,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),

            const SizedBox(height: 32),

            // Store Cards
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.0,
                children: [
                  _StoreCard(
                    storeName: AppConstants.pickNPay,
                    color: AppColors.pickNPay,
                    icon: Icons.shopping_cart,
                    isDark: isDark,
                    onTap: () {
                      context.push('/products/${AppConstants.pickNPay}');
                    },
                  ),
                  _StoreCard(
                    storeName: AppConstants.woolworths,
                    color: AppColors.woolworths,
                    icon: Icons.store,
                    isDark: isDark,
                    onTap: () {
                      context.push('/products/${AppConstants.woolworths}');
                    },
                  ),
                  _StoreCard(
                    storeName: AppConstants.shoprite,
                    color: AppColors.shoprite,
                    icon: Icons.shopping_basket,
                    isDark: isDark,
                    onTap: () {
                      context.push('/products/${AppConstants.shoprite}');
                    },
                  ),
                  _StoreCard(
                    storeName: AppConstants.checkers,
                    color: AppColors.checkers,
                    icon: Icons.local_grocery_store,
                    isDark: isDark,
                    onTap: () {
                      context.push('/products/${AppConstants.checkers}');
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreCard extends StatelessWidget {
  final String storeName;
  final Color color;
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;

  const _StoreCard({
    required this.storeName,
    required this.color,
    required this.icon,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withOpacity(isDark ? 0.3 : 0.1),
                color.withOpacity(isDark ? 0.15 : 0.05),
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Store Icon
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withOpacity(isDark ? 0.3 : 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 36, color: color),
              ),

              const SizedBox(height: 12),

              // Store Name
              Text(
                storeName,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
