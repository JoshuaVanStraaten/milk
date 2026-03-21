// lib/presentation/screens/compare/compare_sheet.dart
//
// Cross-retailer price comparison sheet.
// Opens when the user taps a product card in the Browse tab.
// Searches all 4 retailers in parallel for the same product name
// and displays matched results categorized by match quality.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lottie/lottie.dart';
import '../../../core/constants/retailers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/live_product.dart';
import '../../../data/models/nearby_store.dart';
import '../../../data/services/product_name_parser.dart';
import '../../providers/list_provider.dart';
import '../../providers/store_provider.dart';
import '../../widgets/common/lottie_loading_indicator.dart';
import '../../widgets/products/add_to_list_sheet.dart';

/// Show the comparison sheet as a modal bottom sheet.
///
/// Call this from the product card's onTap:
/// ```dart
/// onTap: () => showCompareSheet(context, ref, product);
/// ```
void showCompareSheet(
  BuildContext context,
  WidgetRef ref,
  LiveProduct product, {
  String? listId,
  ScaffoldMessengerState? scaffoldMessenger,
}) {
  final storeSelection = ref.read(storeSelectionProvider);
  final stores = storeSelection.value;

  if (stores == null) return;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CompareSheet(
      product: product,
      stores: stores,
      listId: listId,
      scaffoldMessenger: scaffoldMessenger,
    ),
  );
}

class CompareSheet extends ConsumerStatefulWidget {
  final LiveProduct product;
  final StoreSelection stores;
  final String? listId;
  final ScaffoldMessengerState? scaffoldMessenger;

  const CompareSheet({
    super.key,
    required this.product,
    required this.stores,
    this.listId,
    this.scaffoldMessenger,
  });

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
      // Compare against peer retailers only:
      // Grocery → other grocery stores, Pharmacy → other pharmacy stores.
      final peers = Retailers.comparisonPeers(widget.product.retailer);
      final peerStores = Map.fromEntries(
        widget.stores.stores.entries.where((e) => peers.contains(e.key)),
      );
      final results = await api.compareProduct(
        productName: _buildSearchQuery(),
        stores: peerStores,
      );

      if (mounted) {
        setState(() {
          _results = results;
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

  /// Build a clean search query using ProductNameParser.
  /// Uses searchQuery (keeps brand + product words + size) instead of
  /// normalizedName (which strips brand/size and is meant for Jaccard scoring).
  String _buildSearchQuery() {
    final parsed = ProductNameParser.parse(widget.product.name);
    return parsed.searchQuery;
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
    final config = Retailers.fromName(widget.product.retailer);
    final retailerColor = config?.color ?? Colors.grey;

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
          // Product name + source retailer + price
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
                    const SizedBox(width: 4),
                    Text(
                      '${widget.product.retailer} · ${widget.product.price}',
                      style: TextStyle(fontSize: 13, color: subtitleColor),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    final isPharmacy = Retailers.isPharmacy(widget.product.retailer);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: LottieLoadingIndicator(
        width: 140,
        height: 140,
        message: isPharmacy
            ? 'Comparing pharmacies...'
            : 'Comparing grocery retailers...',
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

    final subtitleColor = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;

    // Filter out source retailer — user already knows their product's price
    final filteredResults = Map.of(_results!)
      ..removeWhere((retailer, _) =>
          retailer.toLowerCase() == widget.product.retailer.toLowerCase());

    if (filteredResults.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.store, size: 48, color: subtitleColor),
            const SizedBox(height: 12),
            Text(
              Retailers.isPharmacy(widget.product.retailer)
                  ? 'No other pharmacies available to compare'
                  : 'No other retailers available to compare',
              style: TextStyle(color: subtitleColor),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // Use SmartMatchingService for consistent matching across the app
    final smartMatcher = ref.read(smartMatchingServiceProvider);
    final result = smartMatcher.findMatchesAlgorithm(
      sourceProduct: widget.product,
      candidatesByRetailer: filteredResults,
    );

    // Flatten all matches across retailers, categorize by MatchType
    final exactMatches = <ComparisonMatch>[];
    final similarMatches = <ComparisonMatch>[];
    final fallbackMatches = <ComparisonMatch>[];

    for (final entry in result.allMatchesByRetailer.entries) {
      for (final match in entry.value) {
        switch (match.matchType) {
          case MatchType.exact:
            exactMatches.add(match);
          case MatchType.similar:
            similarMatches.add(match);
          case MatchType.fallback:
            fallbackMatches.add(match);
        }
      }
    }

    // Sort each category by price ascending
    exactMatches.sort((a, b) => a.priceNumeric.compareTo(b.priceNumeric));
    similarMatches.sort((a, b) => a.priceNumeric.compareTo(b.priceNumeric));
    fallbackMatches.sort((a, b) => a.priceNumeric.compareTo(b.priceNumeric));

    // Find cheapest exact match price for savings badge
    final cheapestExactPrice = exactMatches.isNotEmpty
        ? exactMatches.first.priceNumeric
        : 0.0;

    final hasExact = exactMatches.isNotEmpty;
    final hasSimilar = similarMatches.isNotEmpty;
    final hasFallback = fallbackMatches.isNotEmpty;

    if (!hasExact && !hasSimilar && !hasFallback) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Lottie.asset(
              'assets/animations/empty.json',
              width: 120,
              height: 120,
              repeat: false,
            ),
            const SizedBox(height: 8),
            Text(
              'No matching products found',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              Retailers.isPharmacy(widget.product.retailer)
                  ? 'This product wasn\'t found at other pharmacies'
                  : 'This product wasn\'t found at other grocery stores',
              style: TextStyle(fontSize: 13, color: subtitleColor),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // Exact matches section — always prominent
        if (hasExact) ...[
          _buildSectionHeader(
            'Best Matches',
            Icons.check_circle,
            AppColors.success,
            exactMatches.length,
            isDark,
          ),
          const SizedBox(height: 8),
          ...exactMatches.asMap().entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildMatchCard(
              e.value,
              isDark,
              isCheapest: e.key == 0,
              cheapestPrice: cheapestExactPrice,
            ),
          )),
        ],

        // Summary text when exact matches exist
        if (hasExact && (hasSimilar || hasFallback))
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Text(
              '${exactMatches.length} best match${exactMatches.length == 1 ? '' : 'es'} found',
              style: TextStyle(fontSize: 12, color: subtitleColor),
            ),
          ),

        // No exact matches — highlighted container so users notice
        if (!hasExact) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: isDark ? 0.12 : 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppColors.secondary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: AppColors.secondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No exact matches found — showing similar products',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Similar matches
        if (hasSimilar) ...[
          if (hasExact)
            // Collapsed when exact matches exist
            _buildCollapsibleSection(
              title: 'Similar Products (${similarMatches.length})',
              icon: Icons.content_copy,
              color: AppColors.secondary,
              matches: similarMatches,
              isDark: isDark,
              initiallyExpanded: false,
            )
          else ...[
            // Expanded when no exact matches
            _buildSectionHeader(
              'Similar Products',
              Icons.content_copy,
              AppColors.secondary,
              similarMatches.length,
              isDark,
            ),
            const SizedBox(height: 8),
            ...similarMatches.map((m) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildMatchCard(m, isDark,
                  isCheapest: false, cheapestPrice: 0),
            )),
          ],
        ],

        // Fallback/alternatives
        if (hasFallback)
          _buildCollapsibleSection(
            title: 'Alternatives (${fallbackMatches.length})',
            icon: Icons.category,
            color: subtitleColor,
            matches: fallbackMatches,
            isDark: isDark,
            initiallyExpanded: !hasExact && !hasSimilar,
          ),
      ],
    );
  }

  Widget _buildSectionHeader(
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

  Widget _buildCollapsibleSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<ComparisonMatch> matches,
    required bool isDark,
    required bool initiallyExpanded,
  }) {
    return _CollapsibleMatchSection(
      title: title,
      icon: icon,
      color: color,
      isDark: isDark,
      initiallyExpanded: initiallyExpanded,
      children: matches
          .map((m) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildMatchCard(m, isDark,
                    isCheapest: false, cheapestPrice: 0),
              ))
          .toList(),
    );
  }

  Widget _buildMatchCard(
    ComparisonMatch match,
    bool isDark, {
    required bool isCheapest,
    required double cheapestPrice,
  }) {
    final config = Retailers.fromName(match.retailer);
    final retailerColor = config?.color ?? Colors.grey;
    final cardColor = isDark ? AppColors.surfaceDarkMode : Colors.grey.shade50;
    final textColor = isDark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimary;
    final subtitleColor = isDark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondary;

    final savings = cheapestPrice > 0
        ? match.priceNumeric - cheapestPrice
        : 0.0;

    return _MatchCardTile(
      match: match,
      isDark: isDark,
      isCheapest: isCheapest,
      savings: savings,
      cardColor: cardColor,
      retailerColor: retailerColor,
      textColor: textColor,
      subtitleColor: subtitleColor,
      retailerIcon: _buildRetailerIcon(retailerColor, isDark),
      onTap: () async {
        double? specialPrice;
        if (match.hasPromo && match.promotionPrice != null) {
          specialPrice = double.tryParse(
            match.promotionPrice!
                .replaceAll('R', '')
                .replaceAll(',', '')
                .trim(),
          );
        }

        if (widget.listId != null) {
          // Optimistic — close both sheets and show snackbar immediately
          final nav = Navigator.of(context);
          nav.pop();
          nav.pop();
          widget.scaffoldMessenger?.showSnackBar(
            SnackBar(
              content: Text('${match.name} added'),
              backgroundColor: AppColors.primary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.all(16),
            ),
          );
          ref
              .read(realtimeListItemsProvider(widget.listId!).notifier)
              .addItem(
                itemName: match.name,
                itemPrice: match.priceNumeric,
                itemRetailer: match.retailer,
                itemSpecialPrice: specialPrice,
              );
        } else {
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
        }
      },
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
}

/// Animated match card — scales down on tap before calling onTap.
class _MatchCardTile extends StatefulWidget {
  final ComparisonMatch match;
  final bool isDark;
  final bool isCheapest;
  final double savings;
  final Color cardColor;
  final Color retailerColor;
  final Color textColor;
  final Color subtitleColor;
  final Widget retailerIcon;
  final Future<void> Function() onTap;

  const _MatchCardTile({
    required this.match,
    required this.isDark,
    required this.isCheapest,
    required this.savings,
    required this.cardColor,
    required this.retailerColor,
    required this.textColor,
    required this.subtitleColor,
    required this.retailerIcon,
    required this.onTap,
  });

  @override
  State<_MatchCardTile> createState() => _MatchCardTileState();
}

class _MatchCardTileState extends State<_MatchCardTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 110),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    await _controller.forward();
    await _controller.reverse();
    await widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    final isDark = widget.isDark;
    final isCheapest = widget.isCheapest;
    final showSavings = !isCheapest && widget.savings > 0.50;

    return GestureDetector(
      onTap: _handleTap,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isCheapest
                ? AppColors.primary.withValues(alpha: isDark ? 0.15 : 0.06)
                : widget.cardColor,
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
                child: match.imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: match.imageUrl!,
                        fit: BoxFit.contain,
                        errorWidget: (_, __, ___) => widget.retailerIcon,
                      )
                    : widget.retailerIcon,
              ),
              const SizedBox(width: 12),

              // Product name + retailer
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
                            color: widget.retailerColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            match.retailer,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: widget.retailerColor,
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
                        color: widget.subtitleColor,
                      ),
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
                  if (match.hasPromo && match.promotionPrice != null) ...[
                    Text(
                      match.price,
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.subtitleColor,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    Text(
                      match.promotionPrice!,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isCheapest
                            ? AppColors.primary
                            : AppColors.error,
                      ),
                    ),
                  ] else
                    Text(
                      match.price,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isCheapest
                            ? AppColors.primary
                            : widget.textColor,
                      ),
                    ),
                  if (showSavings)
                    Text(
                      '+R${widget.savings.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.error.withValues(alpha: 0.8),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Styled collapsible section that looks like a tappable button when collapsed.
class _CollapsibleMatchSection extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color color;
  final bool isDark;
  final bool initiallyExpanded;
  final List<Widget> children;

  const _CollapsibleMatchSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.isDark,
    required this.initiallyExpanded,
    required this.children,
  });

  @override
  State<_CollapsibleMatchSection> createState() =>
      _CollapsibleMatchSectionState();
}

class _CollapsibleMatchSectionState extends State<_CollapsibleMatchSection> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

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
