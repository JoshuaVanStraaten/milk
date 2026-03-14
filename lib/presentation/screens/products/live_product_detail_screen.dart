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
import '../../../data/services/smart_matching_service.dart';
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
  bool _verifyingWithAi = false;
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
      _verifyingWithAi = false;
    });

    try {
      final api = ref.read(liveApiServiceProvider);
      final smartMatcher = ref.read(smartMatchingServiceProvider);
      final storeSelection = ref.read(storeSelectionProvider).value;

      if (storeSelection == null) {
        setState(() {
          _compareError = 'No stores selected';
          _comparingPrices = false;
        });
        return;
      }

      // Parse the source product for search query
      final sourceParsed = ProductNameParser.parse(widget.product.name);
      final searchQuery = sourceParsed.searchQuery;

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

      // Remove self from source retailer results
      final filteredResults = <String, List<LiveProduct>>{};
      for (final entry in resolvedResults.entries) {
        if (entry.key == widget.product.retailer) {
          filteredResults[entry.key] = entry.value
              .where((p) => p.name != widget.product.name)
              .toList();
        } else {
          filteredResults[entry.key] = entry.value;
        }
      }

      // Algorithm-only scoring (instant)
      final algorithmResult = smartMatcher.findMatchesAlgorithm(
        sourceProduct: widget.product,
        candidatesByRetailer: filteredResults,
      );

      // Show algorithm results immediately
      final algorithmMatches = _flattenAndSort(algorithmResult);
      if (mounted) {
        setState(() {
          _comparisonResults = algorithmMatches;
          _comparingPrices = false;
        });
      }

      // If low-confidence matches exist, enhance with AI in background
      if (algorithmResult.hasLowConfidence) {
        if (mounted) setState(() => _verifyingWithAi = true);

        final enhanced = await smartMatcher.enhanceWithAi(
          sourceProduct: widget.product,
          algorithmResult: algorithmResult,
          candidatesByRetailer: filteredResults,
        );

        if (mounted) {
          setState(() {
            _comparisonResults = _flattenAndSort(enhanced);
            _verifyingWithAi = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _compareError = e.toString();
          _comparingPrices = false;
          _verifyingWithAi = false;
        });
      }
    }
  }

  /// Flatten a SmartMatchResult into a sorted list for display.
  List<ComparisonMatch> _flattenAndSort(SmartMatchResult result) {
    final matches = <ComparisonMatch>[];
    for (final list in result.allMatchesByRetailer.values) {
      matches.addAll(list);
    }
    // Sort: exact > similar > fallback, then by price
    matches.sort((a, b) {
      final typeOrder = a.matchType.index.compareTo(b.matchType.index);
      if (typeOrder != 0) return typeOrder;
      return a.priceNumeric.compareTo(b.priceNumeric);
    });
    return matches;
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

    // Find cheapest exact match for badge
    final cheapestExactPrice = exactMatches.isNotEmpty
        ? exactMatches
            .map((m) => m.priceNumeric)
            .reduce((a, b) => a < b ? a : b)
        : 0.0;

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
        if (_verifyingWithAi)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: subtitleColor,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Verifying matches with AI...',
                  style: TextStyle(fontSize: 12, color: subtitleColor),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),

        // Exact matches
        if (exactMatches.isNotEmpty) ...[
          _buildMatchSectionHeader(
            'Best Matches',
            Icons.check_circle,
            AppColors.success,
            exactMatches.length,
            isDark,
          ),
          const SizedBox(height: 8),
          ...exactMatches.asMap().entries.map((e) => _buildMatchCard(
                e.value,
                isDark,
                isCheapest: e.key == 0,
                cheapestPrice: cheapestExactPrice,
              )),
          const SizedBox(height: 16),
        ],

        // No exact matches — show info message
        if (exactMatches.isEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: subtitleColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No exact matches found at other stores',
                    style: TextStyle(fontSize: 13, color: subtitleColor),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Similar matches — collapsed when exact matches exist
        if (similarMatches.isNotEmpty) ...[
          if (exactMatches.isNotEmpty)
            _DetailCollapsibleSection(
              title: 'Similar Products (${similarMatches.length})',
              icon: Icons.content_copy,
              color: AppColors.secondary,
              isDark: isDark,
              children: similarMatches
                  .map((m) => _buildMatchCard(m, isDark))
                  .toList(),
            )
          else ...[
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
        ],

        // Alternatives — collapsed when better matches exist, expanded otherwise
        if (fallbackMatches.isNotEmpty) ...[
          if (exactMatches.isNotEmpty || similarMatches.isNotEmpty)
            _DetailCollapsibleSection(
              title: 'Alternatives (${fallbackMatches.length})',
              icon: Icons.category,
              color: subtitleColor,
              isDark: isDark,
              children: fallbackMatches
                  .map((m) => _buildMatchCard(m, isDark))
                  .toList(),
            )
          else ...[
            _buildMatchSectionHeader(
              'Alternatives',
              Icons.category,
              subtitleColor,
              fallbackMatches.length,
              isDark,
            ),
            const SizedBox(height: 8),
            ...fallbackMatches.map((m) => _buildMatchCard(m, isDark)),
          ],
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

  Widget _buildMatchCard(
    ComparisonMatch match,
    bool isDark, {
    bool isCheapest = false,
    double cheapestPrice = 0,
  }) {
    final config = Retailers.fromName(match.retailer);
    final retailerColor = config?.color ?? Colors.grey;
    final textColor = isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimary;
    final subtitleColor = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;

    final savings = cheapestPrice > 0
        ? match.priceNumeric - cheapestPrice
        : 0.0;
    final showSavings = !isCheapest && savings > 0.50;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          double? specialPrice;
          if (match.hasPromo && match.promotionPrice != null) {
            specialPrice = double.tryParse(
              match.promotionPrice!
                  .replaceAll('R', '')
                  .replaceAll(',', '')
                  .trim(),
            );
          }
          showAddToListSheet(
            context,
            ref,
            productName: match.name,
            price: match.priceNumeric,
            retailer: match.retailer,
            specialPrice: specialPrice,
            imageUrl: match.imageUrl,
            priceDisplay: match.price,
            multiBuyInfo: null,
          );
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isCheapest
                ? AppColors.primary.withValues(alpha: isDark ? 0.15 : 0.06)
                : (isDark ? AppColors.surfaceDarkMode : AppColors.surface),
            borderRadius: BorderRadius.circular(12),
            border: isCheapest
                ? Border.all(
                    color: AppColors.primary.withValues(alpha: 0.4),
                    width: 1.5,
                  )
                : null,
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
                  Row(
                    children: [
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
                      if (isCheapest) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'CHEAPEST',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
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
                    color: isCheapest ? AppColors.primary : textColor,
                  ),
                ),
                if (match.priceDifference != null) ...[
                  const SizedBox(height: 4),
                  _buildPriceDiffBadge(match),
                ],
                if (showSavings) ...[
                  const SizedBox(height: 4),
                  Text(
                    '+R${savings.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.error.withValues(alpha: 0.8),
                    ),
                  ),
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

/// Styled collapsible section for similar/alternative matches.
class _DetailCollapsibleSection extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color color;
  final bool isDark;
  final List<Widget> children;

  const _DetailCollapsibleSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.isDark,
    required this.children,
  });

  @override
  State<_DetailCollapsibleSection> createState() =>
      _DetailCollapsibleSectionState();
}

class _DetailCollapsibleSectionState extends State<_DetailCollapsibleSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.isDark
        ? Colors.grey.withValues(alpha: 0.2)
        : Colors.grey.withValues(alpha: 0.15);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: widget.isDark ? 0.08 : 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 16, color: widget.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: widget.isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 20,
                    color: widget.color,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(children: widget.children),
          ),
          crossFadeState:
              _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }
}
