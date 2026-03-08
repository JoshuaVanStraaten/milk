// lib/presentation/widgets/products/live_product_card.dart

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/live_product.dart';
import 'quick_add_button.dart';

/// Product card for live API products.
///
/// Displays product image, name, price, promotion badge, and a quick-add "+" button.
/// Designed for use in a 2-column grid with `childAspectRatio: 0.62`.
class LiveProductCard extends StatelessWidget {
  final LiveProduct product;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// If true, shows the quick-add "+" button. Defaults to true.
  final bool showAddButton;

  const LiveProductCard({
    super.key,
    required this.product,
    this.onTap,
    this.onLongPress,
    this.showAddButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Image
            AspectRatio(aspectRatio: 1, child: _buildImage(isDark)),

            // Product Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(6.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Product Name
                    Flexible(
                      child: Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                          height: 1.2,
                        ),
                      ),
                    ),

                    const SizedBox(height: 4),

                    // Price row with add button
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Prices
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Regular Price
                              Text(
                                product.price,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: product.hasPromo
                                      ? (isDark
                                            ? AppColors.textSecondaryDark
                                            : AppColors.textSecondary)
                                      : AppColors.primary,
                                  decoration: product.hasPromo
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),

                              // Promotion Price
                              if (product.hasPromo) ...[
                                const SizedBox(height: 2),
                                Text(
                                  product.promotionPrice,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.error,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),

                        // Quick add button
                        if (showAddButton)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: QuickAddButton(product: product, size: 28),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(bool isDark) {
    final iconColor = isDark
        ? AppColors.textDisabledDark
        : AppColors.textDisabled;

    if (product.imageUrl == null || product.imageUrl!.isEmpty) {
      return Container(
        color: Colors.white,
        child: Center(
          child: Icon(Icons.image_not_supported, size: 48, color: iconColor),
        ),
      );
    }

    return Container(
      color: Colors.white, // White background for all product images
      child: CachedNetworkImage(
        imageUrl: product.imageUrl!,
        fit: BoxFit.contain,
        placeholder: (context, url) =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        errorWidget: (context, url, error) =>
            Center(child: Icon(Icons.broken_image, size: 48, color: iconColor)),
      ),
    );
  }
}
