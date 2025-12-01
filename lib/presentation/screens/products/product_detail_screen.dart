import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/product.dart';
import '../../providers/list_provider.dart';
import '../../widgets/price_comparison_sheet.dart';

/// Enum to categorize promotion types
enum PromoType {
  none, // No promotion
  simplePrice, // Just a price like "R35.99"
  buyXForY, // "Buy 2 for R22" - can calculate per-item
  buyXSavePercent, // "Buy any 3 save 20%" - partial calculation
  buyXSaveAmount, // "Buy 2 save R10" - partial calculation
  complex, // Complex promos we can't calculate
}

class ProductDetailScreen extends ConsumerWidget {
  final Product product;
  final String retailer;

  const ProductDetailScreen({
    super.key,
    required this.product,
    required this.retailer,
  });

  /// Determine the type of promotion
  PromoType _getPromoType() {
    if (!product.hasPromotion || product.promotionPrice == null) {
      return PromoType.none;
    }

    final promo = product.promotionPrice!.toLowerCase();

    // Check for "Buy X for RY" pattern
    if (RegExp(r'(\d+)\s*for\s*r\s*(\d+\.?\d*)').hasMatch(promo) ||
        RegExp(r'buy\s*(\d+)\s*for\s*r\s*(\d+\.?\d*)').hasMatch(promo)) {
      return PromoType.buyXForY;
    }

    // Check for "Buy X save Y%" pattern
    if (RegExp(r'buy\s*(any\s*)?\d+.*save\s*\d+\s*%').hasMatch(promo)) {
      return PromoType.buyXSavePercent;
    }

    // Check for "Buy X save RY" pattern (but not percentage)
    if (RegExp(r'buy\s*(any\s*)?\d+.*save\s*r\s*\d+').hasMatch(promo) &&
        !promo.contains('%')) {
      return PromoType.buyXSaveAmount;
    }

    // Check if it's a simple price (starts with R and is just a number)
    if (RegExp(r'^r\s*\d+\.?\d*$').hasMatch(promo.trim())) {
      return PromoType.simplePrice;
    }

    // Check if promo contains a clear price we can extract
    if (product.numericPromotionPrice != null &&
        !promo.contains('buy') &&
        !promo.contains('save') &&
        !promo.contains('any')) {
      return PromoType.simplePrice;
    }

    // Everything else is complex
    return PromoType.complex;
  }

  /// Check if we can show accurate savings
  bool _canShowSavings() {
    final promoType = _getPromoType();
    return promoType == PromoType.simplePrice ||
        promoType == PromoType.buyXForY;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final retailerColor = _getRetailerColor(retailer);
    final promoType = _getPromoType();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App Bar with product image
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: retailerColor,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: isDark ? AppColors.surfaceDarkMode : Colors.white,
                child: _buildProductImage(isDark),
              ),
            ),
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back, color: Colors.white),
              ),
              onPressed: () => context.pop(),
            ),
          ),

          // Product details
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Retailer badge
                  _buildRetailerBadge(retailerColor),

                  const SizedBox(height: 16),

                  // Product name
                  Text(
                    product.name,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Price section
                  _buildPriceSection(promoType, isDark),

                  const SizedBox(height: 24),

                  // Promotion card (for all promo types except none and simplePrice)
                  if (product.hasPromotion &&
                      promoType != PromoType.none &&
                      promoType != PromoType.simplePrice) ...[
                    _buildPromotionCard(isDark),
                    const SizedBox(height: 16),
                  ],

                  // Multi-buy info card (only for buyXForY where we can calculate)
                  if (promoType == PromoType.buyXForY &&
                      product.multiBuyInfo != null) ...[
                    _buildMultiBuyCard(isDark),
                    const SizedBox(height: 16),
                  ],

                  // Special offer validity card (for simple price promos)
                  if (promoType == PromoType.simplePrice &&
                      product.promotionValid != null &&
                      product.promotionValid!.isNotEmpty) ...[
                    _buildValidityCard(isDark),
                    const SizedBox(height: 16),
                  ],

                  const SizedBox(height: 8),

                  // Product info card
                  _buildProductInfoCard(promoType, isDark),

                  const SizedBox(height: 120), // Space for bottom buttons
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Compare Prices button
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => showPriceComparisonSheet(context, product),
                  icon: const Icon(Icons.compare_arrows),
                  label: const Text('Compare'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Add to List button
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: () => _showAddToListSheet(context, ref),
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('Add to List'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductImage(bool isDark) {
    final surfaceColor = isDark ? AppColors.surfaceDarkMode : Colors.white;
    final iconColor = isDark
        ? AppColors.textDisabledDark
        : AppColors.textDisabled;

    if (product.imageUrl == null || product.imageUrl!.isEmpty) {
      return Container(
        color: surfaceColor,
        child: Center(
          child: Icon(Icons.image_not_supported, size: 100, color: iconColor),
        ),
      );
    }

    return Hero(
      tag: 'product-${product.index}',
      child: Container(
        color: surfaceColor,
        child: CachedNetworkImage(
          imageUrl: product.imageUrl!,
          fit: BoxFit.contain,
          placeholder: (context, url) => Container(
            color: surfaceColor,
            child: const Center(child: CircularProgressIndicator()),
          ),
          errorWidget: (context, url, error) => Container(
            color: surfaceColor,
            child: Center(
              child: Icon(Icons.broken_image, size: 100, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRetailerBadge(Color retailerColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: retailerColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: retailerColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.store, size: 16, color: retailerColor),
          const SizedBox(width: 6),
          Text(
            retailer,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: retailerColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceSection(PromoType promoType, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Price',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),

          // Price display based on promo type
          _buildPriceDisplay(promoType, isDark),

          // Savings badge - only show when we can accurately calculate
          if (_canShowSavings() &&
              product.savingsAmount != null &&
              product.savingsAmount! > 0) ...[
            const SizedBox(height: 12),
            _buildSavingsBadge(),
          ],
        ],
      ),
    );
  }

  Widget _buildPriceDisplay(PromoType promoType, bool isDark) {
    switch (promoType) {
      case PromoType.simplePrice:
        // Show promo price prominent, original struck through
        return Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 12,
          runSpacing: 8,
          children: [
            Text(
              product.promotionPrice!,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: AppColors.error,
              ),
            ),
            if (product.price != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  product.price!,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ),
          ],
        );

      case PromoType.buyXForY:
      case PromoType.buyXSavePercent:
      case PromoType.buyXSaveAmount:
      case PromoType.complex:
        // Show original price, promo details in cards below
        return Text(
          product.price ?? 'Price unavailable',
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        );

      case PromoType.none:
      default:
        // No promo - show regular price
        return Text(
          product.price ?? 'Price unavailable',
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        );
    }
  }

  Widget _buildSavingsBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.savings, size: 16, color: AppColors.success),
          const SizedBox(width: 6),
          Text(
            'Save R${product.savingsAmount!.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.success,
            ),
          ),
          if (product.savingsPercentage != null) ...[
            const SizedBox(width: 8),
            Text(
              '(${product.savingsPercentage}% off)',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.success.withOpacity(0.8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPromotionCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.error.withOpacity(0.1),
            AppColors.secondary.withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.local_offer,
              color: AppColors.error,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Special Offer',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.error,
                  ),
                ),
                if (product.promotionPrice != null &&
                    product.promotionPrice!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    product.promotionPrice!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                    ),
                  ),
                ],
                if (product.promotionValid != null &&
                    product.promotionValid!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    product.promotionValid!,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValidityCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.error.withOpacity(0.1),
            AppColors.secondary.withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.local_offer,
              color: AppColors.error,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Special Offer',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  product.promotionValid!,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultiBuyCard(bool isDark) {
    final multiBuy = product.multiBuyInfo!;
    final quantity = multiBuy['quantity']!.toInt();
    final totalPrice = multiBuy['totalPrice']!;
    final pricePerItem = multiBuy['pricePerItem']!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.secondary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.secondary.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.secondary.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shopping_basket,
              color: AppColors.secondary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Buy $quantity for R${totalPrice.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.secondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'R${pricePerItem.toStringAsFixed(2)} each when you buy $quantity',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductInfoCard(PromoType promoType, bool isDark) {
    // Only show Valid field if there's a promotion AND the valid text is not empty
    final showValidField =
        product.hasPromotion &&
        product.promotionValid != null &&
        product.promotionValid!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Product Information',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),

          // Regular Price
          if (product.price != null && product.price!.isNotEmpty)
            _buildInfoRow('Regular Price', product.price!, isDark),

          // Promotion - only show for non-simple promos with actual promo text
          if (product.hasPromotion &&
              promoType != PromoType.simplePrice &&
              product.promotionPrice != null &&
              product.promotionPrice!.isNotEmpty)
            _buildInfoRow('Promotion', product.promotionPrice!, isDark),

          // Retailer
          _buildInfoRow('Retailer', retailer, isDark),

          // Validity - only show if there's a promotion AND valid text is not empty
          if (showValidField)
            _buildInfoRow('Valid', product.promotionValid!, isDark),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getRetailerColor(String retailer) {
    switch (retailer) {
      case AppConstants.pickNPay:
        return const Color(0xFFE31837); // Pick n Pay red
      case AppConstants.woolworths:
        return const Color(0xFF006341); // Woolworths green
      case AppConstants.shoprite:
        return const Color(0xFFFF6600); // Shoprite orange
      case AppConstants.checkers:
        return const Color(0xFF005EB8); // Checkers blue
      default:
        return AppColors.primary;
    }
  }

  void _showAddToListSheet(BuildContext context, WidgetRef ref) {
    final listsAsync = ref.read(userListsProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AddToListSheet(
        product: product,
        retailer: retailer,
        listsAsync: listsAsync,
      ),
    );
  }
}

/// Bottom sheet for adding product to a list
class _AddToListSheet extends ConsumerStatefulWidget {
  final Product product;
  final String retailer;
  final AsyncValue listsAsync;

  const _AddToListSheet({
    required this.product,
    required this.retailer,
    required this.listsAsync,
  });

  @override
  ConsumerState<_AddToListSheet> createState() => _AddToListSheetState();
}

class _AddToListSheetState extends ConsumerState<_AddToListSheet> {
  final _quantityController = TextEditingController(text: '1');
  final _noteController = TextEditingController();
  String? _selectedListId;
  bool _isLoading = false;

  @override
  void dispose() {
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _handleAddToList() async {
    if (_selectedListId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a list')));
      return;
    }

    setState(() => _isLoading = true);

    final quantity = double.tryParse(_quantityController.text) ?? 1.0;

    // Get prices and multi-buy info
    double regularPrice = 0.0;
    double? specialPrice;
    Map<String, double>? multiBuyInfo;

    if (widget.product.hasPromotion) {
      regularPrice = widget.product.numericRegularPrice ?? 0.0;
      multiBuyInfo = widget.product.multiBuyInfo;

      if (multiBuyInfo != null) {
        specialPrice = multiBuyInfo['pricePerItem'];
      } else {
        specialPrice = widget.product.numericPromotionPrice;
      }
    } else {
      regularPrice = widget.product.numericPrice ?? 0.0;
      specialPrice = null;
    }

    final itemNotifier = ref.read(listItemNotifierProvider.notifier);

    final item = await itemNotifier.addItem(
      listId: _selectedListId!,
      itemName: widget.product.name,
      itemPrice: regularPrice,
      itemQuantity: quantity,
      itemNote: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
      itemRetailer: widget.retailer,
      itemSpecialPrice: specialPrice,
      multiBuyInfo: multiBuyInfo,
    );

    setState(() => _isLoading = false);

    if (mounted && item != null) {
      // Capture values before popping
      final listId = _selectedListId;
      final productName = widget.product.name;

      // Get the router before we pop (use the navigator context, not bottom sheet)
      final router = GoRouter.of(context);

      // Pop the bottom sheet
      Navigator.pop(context);

      // Show snackbar using the ScaffoldMessenger (it finds the nearest Scaffold)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added $productName to list'),
          backgroundColor: AppColors.success,
          action: SnackBarAction(
            label: 'View List',
            textColor: Colors.white,
            onPressed: () {
              // Use the captured router instance
              router.push('/lists/$listId');
            },
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppColors.surfaceDarkMode : AppColors.surface;
    final backgroundColor = isDark ? AppColors.backgroundDark : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
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

            const SizedBox(height: 20),

            const Text(
              'Add to Shopping List',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 20),

            // Product info summary
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: surfaceColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: widget.product.imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: widget.product.imageUrl!,
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              width: 60,
                              height: 60,
                              color: surfaceColor,
                              child: const Icon(Icons.image_not_supported),
                            ),
                          )
                        : Container(
                            width: 60,
                            height: 60,
                            color: surfaceColor,
                            child: const Icon(Icons.image_not_supported),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.product.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.product.displayPrice,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: widget.product.hasPromotion
                                ? AppColors.error
                                : AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // List selector
            widget.listsAsync.when(
              data: (lists) {
                if (lists.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: surfaceColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'No lists yet',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            context.push('/lists/create');
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Create a List'),
                        ),
                      ],
                    ),
                  );
                }

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedListId,
                    hint: const Text('Select a list'),
                    isExpanded: true,
                    underline: const SizedBox(),
                    dropdownColor: isDark
                        ? AppColors.surfaceDarkMode
                        : Colors.white,
                    items: lists.map<DropdownMenuItem<String>>((list) {
                      return DropdownMenuItem<String>(
                        value: list.shoppingListId,
                        child: Text(list.listName),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedListId = value;
                      });
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Text('Error loading lists'),
            ),

            const SizedBox(height: 16),

            // Quantity
            TextFormField(
              controller: _quantityController,
              decoration: InputDecoration(
                labelText: 'Quantity',
                prefixIcon: const Icon(Icons.shopping_cart),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              keyboardType: TextInputType.number,
            ),

            const SizedBox(height: 16),

            // Note
            TextFormField(
              controller: _noteController,
              decoration: InputDecoration(
                labelText: 'Note (optional)',
                prefixIcon: const Icon(Icons.note),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              maxLines: 2,
            ),

            const SizedBox(height: 24),

            // Add button
            ElevatedButton(
              onPressed: _isLoading ? null : _handleAddToList,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Add to List', style: TextStyle(fontSize: 16)),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
