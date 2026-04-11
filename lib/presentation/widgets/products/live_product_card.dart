// lib/presentation/widgets/products/live_product_card.dart

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/live_product.dart';
import 'quick_add_button.dart';

/// Product card for live API products.
///
/// Displays product image (padded, floating on white container), name, price,
/// promotion badge, quick-add "+" button, and optional compare button.
/// Designed for use in a 2-column grid with `childAspectRatio: 0.72` or similar.
class LiveProductCard extends StatelessWidget {
  final LiveProduct product;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// If true, shows the quick-add "+" button. Defaults to true.
  final bool showAddButton;

  /// If true, shows the compare button. Defaults to true.
  final bool showCompareButton;

  /// Callback when compare button is tapped. If null, compare button is hidden.
  final VoidCallback? onCompare;

  /// Optional key for tutorial targeting on the compare button.
  final GlobalKey? compareButtonKey;

  const LiveProductCard({
    super.key,
    required this.product,
    this.onTap,
    this.onLongPress,
    this.showAddButton = true,
    this.showCompareButton = true,
    this.onCompare,
    this.compareButtonKey,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: product.hasPromo
            ? BorderSide(
                color: AppColors.error.withValues(alpha: 0.3),
                width: 1,
              )
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Padded product image area (badge + buttons inside)
            _buildImageArea(isDark),

            // Product info
            Expanded(
              child: _buildInfoSection(isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageArea(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          children: [
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: _buildImageContent(),
              ),
            ),
            // SALE badge (top-left)
            if (product.hasPromo)
              Positioned(
                top: 4,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'SALE',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            // Action buttons (top-right)
            Positioned(
              top: 4,
              right: 4,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showCompareButton && onCompare != null) ...[
                    _CompareButton(size: 26, isDark: isDark, onTap: onCompare!, tutorialKey: compareButtonKey),
                    const SizedBox(width: 4),
                  ],
                  if (showAddButton)
                    QuickAddButton(product: product, size: 26),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageContent() {
    if (product.imageUrl == null || product.imageUrl!.isEmpty) {
      return const Center(
        child: Icon(
          Icons.image_not_supported,
          size: 40,
          color: AppColors.textDisabled,
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: product.imageUrl!,
      fit: BoxFit.contain,
      placeholder: (context, url) =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      errorWidget: (context, url, error) => const Center(
        child: Icon(Icons.broken_image, size: 40, color: AppColors.textDisabled),
      ),
    );
  }

  Widget _buildInfoSection(bool isDark) {
    final unitPrice = product.pricePerUnitDisplay;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product name — 1 line if promo (need space), 2 lines otherwise
          Text(
            product.name,
            maxLines: product.hasPromo ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
              height: 1.2,
            ),
          ),

          // Size display — helps distinguish same-name products
          if (product.sizeDisplay != null) ...[
            const SizedBox(height: 1),
            Text(
              product.sizeDisplay!,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w400,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
          ],

          const Spacer(),

          // Promo text above price
          if (product.hasPromo)
            Text(
              product.promotionPrice,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

          // Price row: price left, unit price right
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                product.price,
                style: TextStyle(
                  fontSize: product.hasPromo ? 11 : 14,
                  fontWeight: product.hasPromo ? FontWeight.w500 : FontWeight.w700,
                  color: product.hasPromo
                      ? (isDark ? AppColors.textSecondaryDark : AppColors.textSecondary)
                      : AppColors.primary,
                  decoration: product.hasPromo ? TextDecoration.lineThrough : null,
                ),
              ),
              if (unitPrice != null) ...[
                const Spacer(),
                Text(
                  unitPrice,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

}

/// Small compare button with gray background.
class _CompareButton extends StatelessWidget {
  final double size;
  final bool isDark;
  final VoidCallback onTap;
  final GlobalKey? tutorialKey;

  const _CompareButton({
    required this.size,
    required this.isDark,
    required this.onTap,
    this.tutorialKey,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        key: tutorialKey,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDarkModeLight : AppColors.surface,
          borderRadius: BorderRadius.circular(size / 3),
        ),
        child: Icon(
          Icons.compare_arrows,
          size: size * 0.6,
          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
        ),
      ),
    );
  }
}
