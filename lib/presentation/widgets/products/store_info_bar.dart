// lib/presentation/widgets/products/store_info_bar.dart

import 'package:flutter/material.dart';
import '../../../core/constants/retailers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/nearby_store.dart';

/// Compact bar showing the current store's branch name and distance.
///
/// Tapping it opens the store picker sheet so the user can change
/// their selected store for the current retailer.
class StoreInfoBar extends StatelessWidget {
  final NearbyStore store;
  final VoidCallback? onTap;

  const StoreInfoBar({super.key, required this.store, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final config = Retailers.fromName(store.retailer);
    final color = config?.color ?? AppColors.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? AppColors.dividerDark : AppColors.divider,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.location_on, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                store.storeName,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                store.formattedDistance,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
