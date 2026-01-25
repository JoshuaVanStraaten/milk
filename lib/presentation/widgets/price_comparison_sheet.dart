import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/product.dart';
import '../../../data/models/comparable_product.dart';
import '../providers/price_comparison_provider.dart';
import '../providers/province_provider.dart';

/// Bottom sheet for displaying price comparison results
class PriceComparisonSheet extends ConsumerStatefulWidget {
  final Product sourceProduct;

  const PriceComparisonSheet({super.key, required this.sourceProduct});

  @override
  ConsumerState<PriceComparisonSheet> createState() =>
      _PriceComparisonSheetState();
}

class _PriceComparisonSheetState extends ConsumerState<PriceComparisonSheet> {
  @override
  void initState() {
    super.initState();
    // Load comparisons when sheet opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(priceComparisonProvider.notifier)
          .loadComparisons(widget.sourceProduct.index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(priceComparisonProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.backgroundDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              // Handle bar
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.textDisabledDark
                        : AppColors.textDisabled,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(Icons.compare_arrows, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Price Comparison',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            widget.sourceProduct.name,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              const Divider(height: 24),

              // Content
              Expanded(child: _buildContent(state, scrollController, isDark)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildContent(
    PriceComparisonState state,
    ScrollController scrollController,
    bool isDark,
  ) {
    if (state.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Finding prices at other stores...',
              style: TextStyle(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    if (state.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 16),
              Text(
                'Unable to compare prices',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                state.error!,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  ref.read(priceComparisonProvider.notifier).refresh();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (!state.hasResults) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off, size: 48, color: AppColors.textDisabled),
              const SizedBox(height: 16),
              const Text(
                'No matching products found',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              const Text(
                'We couldn\'t find this product at other retailers',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Show results grouped by match type
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // Source product card (for reference)
        _buildSourceProductCard(),

        const SizedBox(height: 16),

        // Exact matches
        if (state.hasExactMatches) ...[
          _buildSectionHeader(
            'Same Product',
            Icons.check_circle,
            AppColors.success,
            state.exactMatches.length,
          ),
          const SizedBox(height: 8),
          ...state.exactMatches.map((c) => _buildComparisonCard(c, isDark)),
          const SizedBox(height: 16),
        ],

        // Similar matches
        if (state.similarMatches.isNotEmpty) ...[
          _buildSectionHeader(
            'Similar Products',
            Icons.content_copy,
            AppColors.secondary,
            state.similarMatches.length,
          ),
          const SizedBox(height: 8),
          ...state.similarMatches.map((c) => _buildComparisonCard(c, isDark)),
          const SizedBox(height: 16),
        ],

        // Fallback matches (only if no better matches)
        if (state.fallbackMatches.isNotEmpty &&
            !state.hasExactMatches &&
            state.similarMatches.isEmpty) ...[
          _buildSectionHeader(
            'Related Products',
            Icons.category,
            AppColors.textSecondary,
            state.fallbackMatches.length,
          ),
          const SizedBox(height: 8),
          ...state.fallbackMatches.map((c) => _buildComparisonCard(c, isDark)),
        ],

        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSourceProductCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final product = widget.sourceProduct;
    final retailerColor = _getRetailerColor(product.retailer);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.primary.withOpacity(0.1)
            : AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          // Product image
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: product.imageUrl!,
                    width: 50,
                    height: 50,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        _buildPlaceholderImage(50, isDark),
                  )
                : _buildPlaceholderImage(50, isDark),
          ),
          const SizedBox(width: 12),

          // Product details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: retailerColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        product.retailer,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: retailerColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Your Selection',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  product.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Price
          Text(
            product.price ?? 'N/A',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    IconData icon,
    Color color,
    int count,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            count.toString(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildComparisonCard(ComparableProduct comparison, bool isDark) {
    final retailerColor = _getRetailerColor(comparison.retailer);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _navigateToProduct(comparison),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Product image
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child:
                      comparison.productImageUrl != null &&
                          comparison.productImageUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: comparison.productImageUrl!,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              _buildPlaceholderImage(60, isDark),
                        )
                      : _buildPlaceholderImage(60, isDark),
                ),
                const SizedBox(width: 12),

                // Product details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Retailer badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: retailerColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          comparison.retailer,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: retailerColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Product name
                      Text(
                        comparison.productName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      // Size if available
                      if (comparison.formattedSize != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          comparison.formattedSize!,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Price and difference
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Base price (used for comparison)
                    Text(
                      comparison.productPrice ?? 'N/A',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                    ),

                    // Price difference badge (based on base price)
                    if (comparison.priceDifference != null) ...[
                      const SizedBox(height: 4),
                      _buildPriceDifferenceBadge(comparison),
                    ],

                    // Show promo as bonus info if available
                    if (comparison.hasPromotion) ...[
                      const SizedBox(height: 4),
                      Container(
                        constraints: const BoxConstraints(maxWidth: 100),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.error.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          comparison.productPromotionPrice!,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.error,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPriceDifferenceBadge(ComparableProduct comparison) {
    if (comparison.priceDifference == null) return const SizedBox();

    final isCheaper = comparison.isCheaper;
    final isMoreExpensive = comparison.isMoreExpensive;

    Color bgColor;
    Color textColor;
    IconData icon;

    if (isCheaper) {
      bgColor = AppColors.success.withOpacity(0.1);
      textColor = AppColors.success;
      icon = Icons.arrow_downward;
    } else if (isMoreExpensive) {
      bgColor = AppColors.error.withOpacity(0.1);
      textColor = AppColors.error;
      icon = Icons.arrow_upward;
    } else {
      bgColor = AppColors.textSecondary.withOpacity(0.1);
      textColor = AppColors.textSecondary;
      icon = Icons.remove;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 2),
          Text(
            comparison.formattedPriceDifference ?? '',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderImage(double size, [bool isDark = false]) {
    return Container(
      width: size,
      height: size,
      color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
      child: Icon(
        Icons.image_not_supported,
        size: size * 0.4,
        color: isDark ? AppColors.textDisabledDark : AppColors.textDisabled,
      ),
    );
  }

  Color _getRetailerColor(String retailer) {
    switch (retailer) {
      case AppConstants.pickNPay:
        return const Color(0xFFE31837);
      case AppConstants.woolworths:
        return const Color(0xFF006341);
      case AppConstants.shoprite:
        return const Color(0xFFFF6600);
      case AppConstants.checkers:
        return const Color(0xFF005EB8);
      default:
        return AppColors.primary;
    }
  }

  void _navigateToProduct(ComparableProduct comparison) {
    // Get current province from provider
    final province = ref.read(selectedProvinceProvider);

    // Create a Product from the comparison to navigate
    // Province is now required for the Product model
    final product = Product(
      index: comparison.productIndex,
      name: comparison.productName,
      price: comparison.productPrice,
      promotionPrice: comparison.productPromotionPrice,
      retailer: comparison.retailer,
      imageUrl: comparison.productImageUrl,
      province: province, // Use current province
      sizeValue: comparison.sizeValue,
      sizeUnit: comparison.sizeUnit,
    );

    // Close the bottom sheet first
    Navigator.pop(context);

    // Navigate to the product detail
    context.push('/product/${comparison.retailer}', extra: product);
  }
}

/// Helper function to show the price comparison sheet
void showPriceComparisonSheet(BuildContext context, Product product) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => PriceComparisonSheet(sourceProduct: product),
  );
}
