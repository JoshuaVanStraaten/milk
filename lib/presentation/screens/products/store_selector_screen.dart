import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';

class StoreSelectorScreen extends StatelessWidget {
  const StoreSelectorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Store')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),

            // Header
            const Text(
              'Browse Products',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Select a store to view products and specials',
              style: TextStyle(fontSize: 16, color: AppColors.textSecondary),
            ),

            const SizedBox(height: 32),

            // Store Cards
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio:
                    1.0, // Changed from 1.2 to 1.0 for more height
                children: [
                  _StoreCard(
                    storeName: AppConstants.pickNPay,
                    color: AppColors.pickNPay,
                    icon: Icons.shopping_cart,
                    onTap: () {
                      context.push('/products/${AppConstants.pickNPay}');
                    },
                  ),
                  _StoreCard(
                    storeName: AppConstants.woolworths,
                    color: AppColors.woolworths,
                    icon: Icons.store,
                    onTap: () {
                      context.push('/products/${AppConstants.woolworths}');
                    },
                  ),
                  _StoreCard(
                    storeName: AppConstants.shoprite,
                    color: AppColors.shoprite,
                    icon: Icons.shopping_basket,
                    onTap: () {
                      context.push('/products/${AppConstants.shoprite}');
                    },
                  ),
                  _StoreCard(
                    storeName: AppConstants.checkers,
                    color: AppColors.checkers,
                    icon: Icons.local_grocery_store,
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
  final VoidCallback onTap;

  const _StoreCard({
    required this.storeName,
    required this.color,
    required this.icon,
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
          padding: const EdgeInsets.all(16), // Reduced from 20
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Store Icon
              Container(
                padding: const EdgeInsets.all(14), // Reduced from 16
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 36, // Reduced from 40
                  color: color,
                ),
              ),

              const SizedBox(height: 12), // Reduced from 16
              // Store Name
              Text(
                storeName,
                textAlign: TextAlign.center,
                maxLines: 2, // Allow 2 lines for longer names
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15, // Reduced from 16
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
