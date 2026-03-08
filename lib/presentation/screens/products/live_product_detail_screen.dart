// lib/presentation/screens/products/live_product_detail_screen.dart
//
// Full-screen product detail for LiveProduct items.
// Shows product image, price, promo info, retailer.
// Has "Compare Prices" button that triggers smart cross-retailer comparison
// with EXACT / SIMILAR / ALTERNATIVE match tiers.
// Also has "Add to List" button.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants/retailers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/live_product.dart';
import '../../../data/services/image_lookup_service.dart';
import '../../../data/services/product_name_parser.dart';
import '../../providers/store_provider.dart';
import '../../widgets/products/add_to_list_sheet.dart';

class LiveProductDetailScreen extends ConsumerStatefulWidget {
  final LiveProduct product;

  const LiveProductDetailScreen({super.key, required this.product});

  @override
  ConsumerState<LiveProductDetailScreen> createState() =>
      _LiveProductDetailScreenState();
}

class _LiveProductDetailScreenState
    extends ConsumerState<LiveProductDetailScreen> {
  // Comparison state
  List<ComparisonMatch>? _comparisonResults;
  bool _comparingPrices = false;
  String? _compareError;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimary;
    final subtitleColor = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;
    final config = Retailers.fromName(widget.product.retailer);
    final retailerColor = config?.color ?? AppColors.primary;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.background,
      body: CustomScrollView(
        slivers: [
          // App bar with product image
          _buildSliverAppBar(isDark, retailerColor),

          // Product info
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Retailer badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: retailerColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      widget.product.retailer,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: retailerColor,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Product name
                  Text(
                    widget.product.name,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                      height: 1.3,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Price section
                  _buildPriceSection(isDark, textColor, subtitleColor),

                  const SizedBox(height: 24),

                  // Action buttons
                  _buildActionButtons(isDark),

                  const SizedBox(height: 28),

                  // Comparison results (if loaded)
                  if (_comparingPrices || _comparisonResults != null)
                    _buildComparisonSection(isDark, textColor, subtitleColor),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // APP BAR WITH IMAGE
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildSliverAppBar(bool isDark, Color retailerColor) {
    return SliverAppBar(
      expandedHeight: 300,
      pinned: true,
      backgroundColor: isDark ? AppColors.surfaceDarkMode : Colors.white,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: (isDark ? Colors.black : Colors.white).withValues(
              alpha: 0.7,
            ),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.arrow_back,
            color: isDark ? Colors.white : Colors.black87,
            size: 20,
          ),
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          color: Colors.white,
          child: widget.product.imageUrl != null
              ? CachedNetworkImage(
                  imageUrl: widget.product.imageUrl!,
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) => _buildPlaceholder(isDark),
                )
              : _buildPlaceholder(isDark),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(bool isDark) {
    return Center(
      child: Icon(
        Icons.image_not_supported_outlined,
        size: 64,
        color: isDark ? AppColors.textDisabledDark : AppColors.textDisabled,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PRICE SECTION
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildPriceSection(bool isDark, Color textColor, Color subtitleColor) {
    final product = widget.product;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                product.price,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ),
              if (product.hasPromo) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'PROMO',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (product.hasPromo) ...[
            const SizedBox(height: 8),
            Text(
              product.promotionPrice,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.error,
              ),
            ),
          ],
          if (product.promotionValid.isNotEmpty &&
              product.promotionValid != 'No promo') ...[
            const SizedBox(height: 4),
            Text(
              product.promotionValid,
              style: TextStyle(fontSize: 13, color: subtitleColor),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTION BUTTONS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildActionButtons(bool isDark) {
    return Row(
      children: [
        // Compare Prices
        Expanded(
          child: FilledButton.icon(
            onPressed: _comparingPrices ? null : _comparePrices,
            icon: _comparingPrices
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.compare_arrows, size: 18),
            label: Text(
              _comparisonResults != null ? 'Refresh Compare' : 'Compare Prices',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Add to list
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _addToList(),
            icon: const Icon(Icons.add_shopping_cart, size: 18),
            label: const Text('Add to List'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMPARE LOGIC
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _comparePrices() async {
    setState(() {
      _comparingPrices = true;
      _compareError = null;
    });

    try {
      final api = ref.read(liveApiServiceProvider);
      final storeSelection = ref.read(storeSelectionProvider).value;

      if (storeSelection == null) {
        setState(() {
          _compareError = 'No stores selected';
          _comparingPrices = false;
        });
        return;
      }

      // Parse the source product
      final sourceParsed = ProductNameParser.parse(widget.product.name);

      // Build a clean search query
      final searchQuery = sourceParsed.normalizedName.length >= 3
          ? sourceParsed.normalizedName
          : widget.product.name;

      // Search all retailers in parallel
      final rawResults = await api.compareProduct(
        productName: searchQuery,
        stores: storeSelection.stores,
      );

      // Resolve images for Checkers/Shoprite
      final resolvedResults = <String, List<LiveProduct>>{};
      for (final entry in rawResults.entries) {
        resolvedResults[entry.key] = _resolveImages(entry.value, entry.key);
      }

      // Classify all results
      final matches = <ComparisonMatch>[];

      for (final entry in resolvedResults.entries) {
        final retailer = entry.key;
        // Skip the source retailer
        if (retailer == widget.product.retailer) continue;

        for (final candidate in entry.value) {
          final candidateParsed = ProductNameParser.parse(candidate.name);
          final match = ProductNameParser.classify(
            source: sourceParsed,
            candidate: candidateParsed,
            retailer: retailer,
            name: candidate.name,
            price: candidate.price,
            priceNumeric: candidate.priceNumeric,
            promotionPrice: candidate.hasPromo
                ? candidate.promotionPrice
                : null,
            hasPromo: candidate.hasPromo,
            imageUrl: candidate.imageUrl,
            sourcePrice: widget.product.priceNumeric,
          );
          if (match != null) {
            matches.add(match);
          }
        }
      }

      // Also include the source retailer's results (other products from same search)
      final sourceRetailerResults =
          resolvedResults[widget.product.retailer] ?? [];
      for (final candidate in sourceRetailerResults) {
        if (candidate.name == widget.product.name) continue; // Skip self
        final candidateParsed = ProductNameParser.parse(candidate.name);
        final match = ProductNameParser.classify(
          source: sourceParsed,
          candidate: candidateParsed,
          retailer: widget.product.retailer,
          name: candidate.name,
          price: candidate.price,
          priceNumeric: candidate.priceNumeric,
          promotionPrice: candidate.hasPromo ? candidate.promotionPrice : null,
          hasPromo: candidate.hasPromo,
          imageUrl: candidate.imageUrl,
          sourcePrice: widget.product.priceNumeric,
        );
        if (match != null) {
          matches.add(match);
        }
      }

      // Sort: exact > similar > fallback, then by price
      matches.sort((a, b) {
        final typeOrder = a.matchType.index.compareTo(b.matchType.index);
        if (typeOrder != 0) return typeOrder;
        return a.priceNumeric.compareTo(b.priceNumeric);
      });

      if (mounted) {
        setState(() {
          _comparisonResults = matches;
          _comparingPrices = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _compareError = e.toString();
          _comparingPrices = false;
        });
      }
    }
  }

  List<LiveProduct> _resolveImages(
    List<LiveProduct> products,
    String retailer,
  ) {
    final lookup = ImageLookupService.instance;
    if (!lookup.isReady) return products;
    final lower = retailer.toLowerCase();
    if (!lower.contains('checkers') && !lower.contains('shoprite')) {
      return products;
    }
    return products.map((p) {
      final cached = lookup.lookupImage(
        retailer: retailer,
        productName: p.name,
      );
      if (cached != null) return p.copyWith(imageUrl: cached);
      return p;
    }).toList();
  }

  void _addToList() {
    final product = widget.product;
    double regularPrice = product.priceNumeric;
    double? specialPrice;
    Map<String, double>? multiBuyInfo;

    if (product.hasPromo) {
      multiBuyInfo = product.multiBuyInfo;
      if (multiBuyInfo != null) {
        specialPrice = multiBuyInfo['pricePerItem'];
      } else {
        final parsed = double.tryParse(
          product.promotionPrice.replaceAll('R', '').replaceAll(',', '').trim(),
        );
        specialPrice = parsed ?? regularPrice;
      }
    }

    showAddToListSheet(
      context,
      ref,
      productName: product.name,
      price: regularPrice,
      retailer: product.retailer,
      specialPrice: specialPrice,
      imageUrl: product.imageUrl,
      priceDisplay: product.price,
      multiBuyInfo: multiBuyInfo,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMPARISON RESULTS UI
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildComparisonSection(
    bool isDark,
    Color textColor,
    Color subtitleColor,
  ) {
    if (_comparingPrices) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            const CircularProgressIndicator(strokeWidth: 2.5),
            const SizedBox(height: 16),
            Text(
              'Comparing prices across all retailers...',
              style: TextStyle(fontSize: 14, color: subtitleColor),
            ),
          ],
        ),
      );
    }

    if (_compareError != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(Icons.error_outline, color: AppColors.error, size: 32),
            const SizedBox(height: 8),
            const Text('Failed to compare prices'),
            const SizedBox(height: 8),
            TextButton(onPressed: _comparePrices, child: const Text('Retry')),
          ],
        ),
      );
    }

    final results = _comparisonResults!;

    if (results.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(Icons.search_off, size: 40, color: subtitleColor),
            const SizedBox(height: 8),
            Text(
              'No matching products found at other retailers',
              style: TextStyle(color: subtitleColor),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final exactMatches = results
        .where((m) => m.matchType == MatchType.exact)
        .toList();
    final similarMatches = results
        .where((m) => m.matchType == MatchType.similar)
        .toList();
    final fallbackMatches = results
        .where((m) => m.matchType == MatchType.fallback)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section title
        Row(
          children: [
            const Icon(
              Icons.compare_arrows,
              size: 20,
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
            Text(
              'Price Comparison',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${results.length} result${results.length == 1 ? '' : 's'} found',
          style: TextStyle(fontSize: 13, color: subtitleColor),
        ),
        const SizedBox(height: 16),

        // Exact matches
        if (exactMatches.isNotEmpty) ...[
          _buildMatchSectionHeader(
            'Same Product',
            Icons.check_circle,
            AppColors.success,
            exactMatches.length,
            isDark,
          ),
          const SizedBox(height: 8),
          ...exactMatches.map((m) => _buildMatchCard(m, isDark)),
          const SizedBox(height: 16),
        ],

        // Similar matches
        if (similarMatches.isNotEmpty) ...[
          _buildMatchSectionHeader(
            'Similar Products',
            Icons.content_copy,
            AppColors.secondary,
            similarMatches.length,
            isDark,
          ),
          const SizedBox(height: 8),
          ...similarMatches.map((m) => _buildMatchCard(m, isDark)),
          const SizedBox(height: 16),
        ],

        // Fallback (only if no better matches)
        if (fallbackMatches.isNotEmpty &&
            exactMatches.isEmpty &&
            similarMatches.isEmpty) ...[
          _buildMatchSectionHeader(
            'Related Products',
            Icons.category,
            subtitleColor,
            fallbackMatches.length,
            isDark,
          ),
          const SizedBox(height: 8),
          ...fallbackMatches.map((m) => _buildMatchCard(m, isDark)),
        ],

        // Show fallback as expandable if we have better matches too
        if (fallbackMatches.isNotEmpty &&
            (exactMatches.isNotEmpty || similarMatches.isNotEmpty)) ...[
          ExpansionTile(
            title: Row(
              children: [
                Icon(Icons.category, size: 16, color: subtitleColor),
                const SizedBox(width: 8),
                Text(
                  'Related Products (${fallbackMatches.length})',
                  style: TextStyle(fontSize: 14, color: subtitleColor),
                ),
              ],
            ),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            children: fallbackMatches
                .map((m) => _buildMatchCard(m, isDark))
                .toList(),
          ),
        ],

        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildMatchSectionHeader(
    String title,
    IconData icon,
    Color color,
    int count,
    bool isDark,
  ) {
    final textColor = isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimary;
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
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

  Widget _buildMatchCard(ComparisonMatch match, bool isDark) {
    final config = Retailers.fromName(match.retailer);
    final retailerColor = config?.color ?? Colors.grey;
    final textColor = isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimary;
    final subtitleColor = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Product image
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: match.imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: match.imageUrl!,
                      fit: BoxFit.contain,
                      errorWidget: (_, __, ___) =>
                          Icon(Icons.store, size: 24, color: retailerColor),
                    )
                  : Icon(Icons.store, size: 24, color: retailerColor),
            ),
            const SizedBox(width: 12),

            // Product info
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
                      color: retailerColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      match.retailer,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: retailerColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    match.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (match.parsed.formattedSize != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      match.parsed.formattedSize!,
                      style: TextStyle(fontSize: 11, color: subtitleColor),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Price column
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  match.price,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                if (match.priceDifference != null) ...[
                  const SizedBox(height: 4),
                  _buildPriceDiffBadge(match),
                ],
                if (match.hasPromo && match.promotionPrice != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 100),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      match.promotionPrice!,
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
    );
  }

  Widget _buildPriceDiffBadge(ComparisonMatch match) {
    Color bgColor;
    Color textColor;
    IconData icon;

    if (match.isCheaper) {
      bgColor = AppColors.success.withValues(alpha: 0.1);
      textColor = AppColors.success;
      icon = Icons.arrow_downward;
    } else if (match.isMoreExpensive) {
      bgColor = AppColors.error.withValues(alpha: 0.1);
      textColor = AppColors.error;
      icon = Icons.arrow_upward;
    } else {
      bgColor = AppColors.textSecondary.withValues(alpha: 0.1);
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
            match.formattedPriceDifference ?? '',
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
}
