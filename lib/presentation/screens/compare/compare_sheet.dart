// lib/presentation/screens/compare/compare_sheet.dart
//
// Cross-retailer price comparison sheet.
// Opens when the user taps a product card in the Browse tab.
// Searches all 4 retailers in parallel for the same product name
// and displays matched results sorted by price.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants/retailers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/live_product.dart';
import '../../../data/models/nearby_store.dart';
import '../../../data/services/image_lookup_service.dart';
import '../../providers/store_provider.dart';

/// Show the comparison sheet as a modal bottom sheet.
///
/// Call this from the product card's onTap:
/// ```dart
/// onTap: () => showCompareSheet(context, ref, product);
/// ```
void showCompareSheet(
  BuildContext context,
  WidgetRef ref,
  LiveProduct product,
) {
  final storeSelection = ref.read(storeSelectionProvider);
  final stores = storeSelection.value;

  if (stores == null) return;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CompareSheet(product: product, stores: stores),
  );
}

class CompareSheet extends ConsumerStatefulWidget {
  final LiveProduct product;
  final StoreSelection stores;

  const CompareSheet({super.key, required this.product, required this.stores});

  @override
  ConsumerState<CompareSheet> createState() => _CompareSheetState();
}

class _CompareSheetState extends ConsumerState<CompareSheet> {
  Map<String, List<LiveProduct>>? _results;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchComparison();
  }

  Future<void> _fetchComparison() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final api = ref.read(liveApiServiceProvider);
      final results = await api.compareProduct(
        productName: _buildSearchQuery(),
        stores: widget.stores.stores,
      );

      // Resolve images for Checkers/Shoprite results
      final resolvedResults = <String, List<LiveProduct>>{};
      for (final entry in results.entries) {
        resolvedResults[entry.key] = _resolveImages(entry.value, entry.key);
      }

      if (mounted) {
        setState(() {
          _results = resolvedResults;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// Build a clean search query from the product name.
  /// Strips size/weight suffixes for better cross-retailer matching.
  String _buildSearchQuery() {
    var query = widget.product.name;
    // Remove common size patterns like "2L", "500ml", "1kg", "6 x 330ml"
    query = query.replaceAll(
      RegExp(r'\d+\s*x\s*\d+\s*(ml|l|g|kg)\b', caseSensitive: false),
      '',
    );
    query = query.replaceAll(
      RegExp(r'\d+\.?\d*\s*(ml|l|g|kg|pack)\b', caseSensitive: false),
      '',
    );
    query = query.trim();
    // If stripping left us with very little, use the original
    if (query.length < 3) query = widget.product.name;
    return query;
  }

  /// Resolve Checkers/Shoprite images from the lookup cache.
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.surfaceDarkMode : Colors.white;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHandle(),
          _buildHeader(isDark),
          const Divider(height: 1),
          Flexible(
            child: _loading
                ? _buildLoading()
                : _error != null
                ? _buildError()
                : _buildResults(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildHandle() {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 12, bottom: 8),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    final textColor = isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimary;
    final subtitleColor = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          // Product thumbnail
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
            ),
            clipBehavior: Clip.antiAlias,
            child: widget.product.imageUrl != null
                ? CachedNetworkImage(
                    imageUrl: widget.product.imageUrl!,
                    fit: BoxFit.contain,
                    errorWidget: (_, __, ___) =>
                        const Icon(Icons.image_not_supported, size: 24),
                  )
                : const Icon(Icons.image_not_supported, size: 24),
          ),
          const SizedBox(width: 12),
          // Product name + source retailer
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.product.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Comparing prices across all stores',
                  style: TextStyle(fontSize: 13, color: subtitleColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(strokeWidth: 2.5),
          const SizedBox(height: 16),
          Text(
            'Searching all retailers...',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: AppColors.error),
          const SizedBox(height: 12),
          const Text('Failed to compare prices'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _fetchComparison,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(bool isDark) {
    if (_results == null || _results!.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('No results found'),
      );
    }

    // Collect best match from each retailer and sort by price
    final comparisons = <_ComparisonItem>[];

    for (final entry in _results!.entries) {
      final retailer = entry.key;
      final products = entry.value;

      if (products.isEmpty) {
        comparisons.add(
          _ComparisonItem(retailer: retailer, product: null, matchQuality: 0),
        );
        continue;
      }

      // Find best match by name similarity
      final bestMatch = _findBestMatch(products, widget.product.name);
      comparisons.add(
        _ComparisonItem(
          retailer: retailer,
          product: bestMatch,
          matchQuality: _calculateSimilarity(
            bestMatch.name.toLowerCase(),
            widget.product.name.toLowerCase(),
          ),
        ),
      );
    }

    // Sort: available products first (by price), then unavailable
    comparisons.sort((a, b) {
      if (a.product == null && b.product == null) return 0;
      if (a.product == null) return 1;
      if (b.product == null) return -1;
      return a.product!.priceNumeric.compareTo(b.product!.priceNumeric);
    });

    // Find the cheapest for the savings badge
    final cheapest = comparisons.where((c) => c.product != null).toList();
    final cheapestPrice = cheapest.isNotEmpty
        ? cheapest.first.product!.priceNumeric
        : 0.0;

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: comparisons.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        return _buildComparisonCard(
          comparisons[index],
          isDark,
          isCheapest: index == 0 && comparisons[index].product != null,
          cheapestPrice: cheapestPrice,
        );
      },
    );
  }

  Widget _buildComparisonCard(
    _ComparisonItem item,
    bool isDark, {
    required bool isCheapest,
    required double cheapestPrice,
  }) {
    final config = Retailers.fromName(item.retailer);
    final retailerColor = config?.color ?? Colors.grey;
    final cardColor = isDark ? AppColors.surfaceDarkMode : Colors.grey.shade50;
    final textColor = isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimary;
    final subtitleColor = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;

    if (item.product == null) {
      // No results for this retailer
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            _buildRetailerIcon(retailerColor, isDark),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.retailer,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Product not found',
                    style: TextStyle(fontSize: 13, color: subtitleColor),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.remove_circle_outline,
              size: 20,
              color: Colors.grey.withValues(alpha: 0.4),
            ),
          ],
        ),
      );
    }

    final product = item.product!;
    final savings = product.priceNumeric - cheapestPrice;
    final showSavings = !isCheapest && savings > 0.50;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isCheapest
            ? AppColors.primary.withValues(alpha: isDark ? 0.15 : 0.06)
            : cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCheapest
              ? AppColors.primary.withValues(alpha: 0.4)
              : Colors.grey.withValues(alpha: 0.15),
          width: isCheapest ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // Product image
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: product.imageUrl != null
                ? CachedNetworkImage(
                    imageUrl: product.imageUrl!,
                    fit: BoxFit.contain,
                    errorWidget: (_, __, ___) =>
                        _buildRetailerIcon(retailerColor, isDark),
                  )
                : _buildRetailerIcon(retailerColor, isDark),
          ),
          const SizedBox(width: 12),

          // Product name + retailer + store
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: retailerColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        item.retailer,
                        style: TextStyle(
                          fontSize: 13,
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
                  product.name,
                  style: TextStyle(fontSize: 13, color: subtitleColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Price column
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (product.hasPromo) ...[
                Text(
                  product.price,
                  style: TextStyle(
                    fontSize: 12,
                    color: subtitleColor,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                Text(
                  product.promotionPrice,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isCheapest ? AppColors.primary : AppColors.error,
                  ),
                ),
              ] else
                Text(
                  product.price,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isCheapest ? AppColors.primary : textColor,
                  ),
                ),
              if (showSavings)
                Text(
                  '+R${savings.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.error.withValues(alpha: 0.8),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRetailerIcon(Color retailerColor, bool isDark) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: retailerColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(Icons.store, size: 18, color: retailerColor),
    );
  }

  /// Find the best matching product by name similarity.
  LiveProduct _findBestMatch(List<LiveProduct> products, String targetName) {
    if (products.length == 1) return products.first;

    final target = targetName.toLowerCase();
    LiveProduct best = products.first;
    double bestScore = 0;

    for (final p in products) {
      final score = _calculateSimilarity(p.name.toLowerCase(), target);
      if (score > bestScore) {
        bestScore = score;
        best = p;
      }
    }

    return best;
  }

  /// Word-overlap similarity score (0.0 to 1.0).
  double _calculateSimilarity(String a, String b) {
    final wordsA = a.split(RegExp(r'\s+')).toSet();
    final wordsB = b.split(RegExp(r'\s+')).toSet();

    if (wordsA.isEmpty || wordsB.isEmpty) return 0;

    final overlap = wordsA.intersection(wordsB).length;
    return overlap / wordsA.union(wordsB).length;
  }
}

/// Internal model for sorting comparison results.
class _ComparisonItem {
  final String retailer;
  final LiveProduct? product;
  final double matchQuality;

  _ComparisonItem({
    required this.retailer,
    this.product,
    this.matchQuality = 0,
  });
}
