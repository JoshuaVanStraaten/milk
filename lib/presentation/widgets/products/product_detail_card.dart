import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/constants/retailers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/live_product.dart';
import '../../screens/compare/compare_sheet.dart';
import 'add_to_list_sheet.dart';

/// Shows a product detail popup card centered on screen with a bouncy animation.
void showProductDetailCard({
  required BuildContext context,
  required WidgetRef ref,
  required LiveProduct product,
}) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Product Detail',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 350),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return ScaleTransition(
        scale: CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        ),
        child: FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          ),
          child: child,
        ),
      );
    },
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return Center(
        child: _ProductDetailCard(
          product: product,
          callerContext: context,
          callerRef: ref,
        ),
      );
    },
  );
}

class _ProductDetailCard extends ConsumerWidget {
  final LiveProduct product;
  final BuildContext callerContext;
  final WidgetRef callerRef;

  const _ProductDetailCard({
    required this.product,
    required this.callerContext,
    required this.callerRef,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final retailerConfig = Retailers.fromName(product.retailer);
    final retailerColor = retailerConfig?.color ?? AppColors.primary;
    final screenWidth = MediaQuery.of(context).size.width;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: screenWidth * 0.85,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDarkMode : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 32,
              spreadRadius: 4,
              offset: const Offset(0, 8),
            ),
            if (!isDark)
              BoxShadow(
                color: retailerColor.withValues(alpha: 0.15),
                blurRadius: 48,
                spreadRadius: -4,
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Product image
                _buildImageSection(isDark, retailerColor),

                // Product info + actions
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Retailer badge
                      _buildRetailerBadge(retailerColor),
                      const SizedBox(height: 10),

                      // Name (left) + Price (right)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Product name — left side
                          Expanded(
                            child: Text(
                              product.name,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? AppColors.textPrimaryDark
                                    : AppColors.textPrimary,
                                height: 1.3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          // Price column — right side
                          _buildPriceColumn(isDark),
                        ],
                      ),

                      // Unit price + validity below
                      _buildPriceFooter(isDark),

                      const SizedBox(height: 20),

                      // Action buttons
                      _buildActionButtons(context, ref, isDark),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageSection(bool isDark, Color retailerColor) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.grey.withValues(alpha: 0.12),
          ),
        ),
      ),
      child: Stack(
        children: [
          // Product image
          Center(
            child: product.imageUrl != null
                ? CachedNetworkImage(
                    imageUrl: product.imageUrl!,
                    fit: BoxFit.contain,
                    height: 180,
                    errorWidget: (_, __, ___) => _buildPlaceholder(),
                  )
                : _buildPlaceholder(),
          ),

          // Sale badge
          if (product.hasPromo)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'SALE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Icon(
      Icons.image_not_supported_outlined,
      size: 48,
      color: AppColors.textDisabled,
    );
  }

  Widget _buildRetailerBadge(Color retailerColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: retailerColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        product.retailer,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: retailerColor,
        ),
      ),
    );
  }

  /// Right-aligned price column (price, promo badge, promo price).
  Widget _buildPriceColumn(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Main price
        Text(
          product.price,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: product.hasPromo
                ? (isDark ? AppColors.textSecondaryDark : AppColors.textSecondary)
                : AppColors.primary,
            decoration: product.hasPromo ? TextDecoration.lineThrough : null,
          ),
        ),
        if (product.hasPromo) ...[
          const SizedBox(height: 4),
          Text(
            product.promotionPrice,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.error,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'PROMO',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.error,
              ),
            ),
          ),
        ],
        // Unit price — right under the price for quick scanning
        if (product.sizeDisplay != null) ...[
          const SizedBox(height: 4),
          Text(
            product.pricePerUnitDisplay != null
                ? '${product.sizeDisplay} · ${product.pricePerUnitDisplay}'
                : product.sizeDisplay!,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  /// Footer below the name+price row: promo validity.
  Widget _buildPriceFooter(bool isDark) {
    final hasValidity = product.promotionValid.isNotEmpty &&
        product.promotionValid != 'No promo';

    if (!hasValidity) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          product.promotionValid,
          style: TextStyle(
            fontSize: 11,
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
  ) {
    return Row(
      children: [
        // Compare Prices
        Expanded(
          child: FilledButton.icon(
            onPressed: () {
              showCompareSheet(context, ref, product);
            },
            icon: const Icon(Icons.compare_arrows, size: 18),
            label: const Text('Compare Prices'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Add to List
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).pop(); // close card
              showAddToListSheet(
                callerContext,
                callerRef,
                productName: product.name,
                price: product.priceNumeric,
                retailer: product.retailer,
                imageUrl: product.imageUrl,
              );
            },
            icon: const Icon(Icons.shopping_cart_outlined, size: 18),
            label: const Text('Add to List'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(
                color: AppColors.primary.withValues(alpha: 0.5),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
