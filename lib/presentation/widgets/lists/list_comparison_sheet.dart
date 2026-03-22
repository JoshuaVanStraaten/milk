import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/retailers.dart';
import '../../../data/models/list_comparison.dart';
import '../../../data/models/list_item.dart';
import '../../../data/services/product_name_parser.dart';
import '../../providers/list_comparison_provider.dart';
import '../common/lottie_loading_indicator.dart';
import '../common/shimmer_text.dart';

/// Opens the list comparison sheet.
Future<void> showListComparisonSheet({
  required BuildContext context,
  required WidgetRef ref,
  required List<ListItem> items,
  required String listId,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ListComparisonSheet(
      items: items,
      listId: listId,
      isDark: isDark,
    ),
  );
}

class _ListComparisonSheet extends ConsumerStatefulWidget {
  final List<ListItem> items;
  final String listId;
  final bool isDark;

  const _ListComparisonSheet({
    required this.items,
    required this.listId,
    required this.isDark,
  });

  @override
  ConsumerState<_ListComparisonSheet> createState() =>
      _ListComparisonSheetState();
}

class _ListComparisonSheetState extends ConsumerState<_ListComparisonSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final List<String> _retailerNames =
      Retailers.all.keys.where(Retailers.isGrocery).toList();
  bool _hasJumpedToCheapest = false;
  bool _isApplying = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _retailerNames.length,
      vsync: this,
    );
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      ref
          .read(listComparisonProvider.notifier)
          .selectRetailer(_retailerNames[_tabController.index]);
      setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(listComparisonProvider.notifier).runComparison(
            items: widget.items,
          );
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _jumpToCheapest(String cheapestRetailer) {
    if (_hasJumpedToCheapest) return;
    final idx = _retailerNames.indexOf(cheapestRetailer);
    if (idx >= 0) {
      _tabController.animateTo(idx);
      _hasJumpedToCheapest = true;
      setState(() {});
    }
  }

  Future<void> _applyRetailer() async {
    final compState = ref.read(listComparisonProvider);
    final retailerName = _retailerNames[_tabController.index];
    final basket = compState.baskets[retailerName];
    if (basket == null || basket.matchedCount == 0) return;

    setState(() => _isApplying = true);

    await ref.read(listComparisonProvider.notifier).applyRetailer(
          retailerName: retailerName,
          listId: widget.listId,
          originalItems: widget.items,
        );

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'List updated to ${_shortName(retailerName)} prices',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final compState = ref.watch(listComparisonProvider);
    final isDark = widget.isDark;

    // Auto-jump to cheapest once all data loads
    if (!compState.isLoading && compState.hasData) {
      final cheapest =
          compState.cheapestWithFuelRetailer ?? compState.cheapestRetailer;
      if (cheapest != null) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _jumpToCheapest(cheapest));
      }
    }

    final currentRetailer = _retailerNames[_tabController.index];
    final currentBasket = compState.baskets[currentRetailer];
    final currentColor =
        Retailers.fromName(currentRetailer)?.color ?? AppColors.primary;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.backgroundDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),

              // Title row
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                child: Row(
                  children: [
                    const Icon(Icons.compare_arrows, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Compare Your List',
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                      iconSize: 20,
                    ),
                  ],
                ),
              ),

              // Winner summary card (after loading completes)
              if (!compState.isLoading && compState.hasData)
                _WinnerCard(
                  compState: compState,
                  isDark: isDark,
                ),

              // Progress indicator (while loading)
              if (compState.isLoading)
                _ProgressIndicator(
                  compState: compState,
                  itemCount: widget.items.length,
                  retailerNames: _retailerNames,
                  isDark: isDark,
                ),

              // Tab bar
              TabBar(
                controller: _tabController,
                isScrollable: _retailerNames.length > 4,
                tabAlignment: _retailerNames.length > 4
                    ? TabAlignment.start
                    : TabAlignment.fill,
                tabs: _retailerNames.map((name) {
                  final basket = compState.baskets[name];
                  final cheapest = compState.cheapestWithFuelRetailer ??
                      compState.cheapestRetailer;
                  final isCheapest = cheapest == name;
                  final config = Retailers.fromName(name);
                  return _RetailerTab(
                    name: _shortName(name),
                    basket: basket,
                    isCheapest: isCheapest,
                    color: config?.color ?? AppColors.primary,
                  );
                }).toList(),
                labelPadding: EdgeInsets.zero,
                indicatorColor: currentColor,
              ),

              Divider(
                height: 1,
                color: isDark ? AppColors.dividerDark : AppColors.divider,
              ),

              // Tab content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: _retailerNames.map((retailerName) {
                    return _RetailerTabContent(
                      retailerName: retailerName,
                      items: widget.items,
                      isDark: isDark,
                      scrollController: scrollController,
                    );
                  }).toList(),
                ),
              ),

              Divider(
                height: 1,
                color: isDark ? AppColors.dividerDark : AppColors.divider,
              ),

              // Bottom action row
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _isApplying ||
                              (currentBasket?.matchedCount ?? 0) == 0
                          ? null
                          : _applyRetailer,
                      style: FilledButton.styleFrom(
                        backgroundColor: currentColor,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isApplying
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Shop at ${_shortName(currentRetailer)} \u2014 ${currentBasket?.formattedGrandTotal ?? ''}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _shortName(String name) {
    const shorts = {
      'Pick n Pay': 'PnP',
      'Woolworths': 'Woolies',
      'Checkers': 'Checkers',
      'Shoprite': 'Shoprite',
    };
    return shorts[name] ?? name;
  }
}

// =============================================================================
// Winner summary card
// =============================================================================

class _WinnerCard extends StatelessWidget {
  final ListComparisonState compState;
  final bool isDark;

  const _WinnerCard({required this.compState, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final cheapest =
        compState.cheapestWithFuelRetailer ?? compState.cheapestRetailer;
    if (cheapest == null) return const SizedBox.shrink();

    final savings = compState.maxSavings;
    final config = Retailers.fromName(cheapest);
    final color = config?.color ?? AppColors.primary;

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: isDark ? 0.25 : 0.10),
              color.withValues(alpha: isDark ? 0.10 : 0.04),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Lottie.asset(
                  'assets/animations/trophy.json',
                  width: 36,
                  height: 36,
                  repeat: false,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_shortName(cheapest)} wins!',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            if (savings >= 5) ...[
              const SizedBox(height: 8),
              Text(
                'Save R${savings.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                SavingsTranslator.toRelatableMessage(savings),
                style: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'All stores are within R5 \u2014 shop wherever\'s closest!',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                ),
              ),
            ],
            // Show how many items the comparison is based on
            if (compState.commonItemCount > 0) ...[
              const SizedBox(height: 6),
              Text(
                'Based on ${compState.commonItemCount} item${compState.commonItemCount == 1 ? '' : 's'} found at all stores',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _shortName(String name) {
    const shorts = {
      'Pick n Pay': 'PnP',
      'Woolworths': 'Woolies',
      'Checkers': 'Checkers',
      'Shoprite': 'Shoprite',
    };
    return shorts[name] ?? name;
  }
}

// =============================================================================
// Progress indicator (while loading)
// =============================================================================

class _ProgressIndicator extends StatelessWidget {
  final ListComparisonState compState;
  final int itemCount;
  final List<String> retailerNames;
  final bool isDark;

  const _ProgressIndicator({
    required this.compState,
    required this.itemCount,
    required this.retailerNames,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        children: [
          Text(
            'Checking ${retailerNames.length} stores for $itemCount items...',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color:
                  isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          // Retailer status chips
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: retailerNames.map((name) {
              final basket = compState.baskets[name];
              final done = basket != null && !basket.isLoading;
              final color =
                  Retailers.fromName(name)?.color ?? AppColors.primary;

              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: done
                      ? color.withValues(alpha: 0.12)
                      : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: done
                        ? color.withValues(alpha: 0.3)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (done)
                      Icon(Icons.check_circle, size: 14, color: color)
                    else
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    const SizedBox(width: 6),
                    Text(
                      _shortName(name),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: done ? FontWeight.w600 : FontWeight.normal,
                        color: done
                            ? color
                            : (isDark ? Colors.white54 : Colors.black54),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  String _shortName(String name) {
    const shorts = {
      'Pick n Pay': 'PnP',
      'Woolworths': 'Woolies',
    };
    return shorts[name] ?? name;
  }
}

// =============================================================================
// Tab label widget
// =============================================================================

class _RetailerTab extends StatelessWidget {
  final String name;
  final ListRetailerBasket? basket;
  final bool isCheapest;
  final Color color;

  const _RetailerTab({
    required this.name,
    required this.basket,
    required this.isCheapest,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLoading = basket?.isLoading ?? true;
    final hasError = basket?.error != null;

    final priceWidget = isLoading
        ? SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          )
        : Text(
            hasError ? '\u2013' : (basket?.formattedGrandTotal ?? ''),
            style: TextStyle(
              fontSize: 10,
              color: hasError
                  ? (isDark ? Colors.white38 : Colors.black38)
                  : isCheapest
                      ? color
                      : (isDark ? Colors.white54 : Colors.black54),
              fontWeight: isCheapest ? FontWeight.w700 : FontWeight.normal,
            ),
          );

    return Tab(
      height: 48,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isCheapest) ...[
                const SizedBox(width: 3),
                Icon(Icons.star_rounded, size: 11, color: color),
              ],
            ],
          ),
          const SizedBox(height: 1),
          priceWidget,
        ],
      ),
    );
  }
}

// =============================================================================
// Per-retailer tab content
// =============================================================================

class _RetailerTabContent extends ConsumerWidget {
  final String retailerName;
  final List<ListItem> items;
  final bool isDark;
  final ScrollController scrollController;

  const _RetailerTabContent({
    required this.retailerName,
    required this.items,
    required this.isDark,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compState = ref.watch(listComparisonProvider);
    final basket = compState.baskets[retailerName];
    final config = Retailers.fromName(retailerName);
    final color = config?.color ?? AppColors.primary;

    if (basket == null || basket.isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LottieLoadingIndicator(
                width: 140,
                height: 140,
                message: 'Searching $retailerName...',
                messageStyle: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                ),
                subtitle: ShimmerText(
                  text:
                      'Finding the best prices for ${items.length} items',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (basket.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_off_outlined,
                  size: 40,
                  color: isDark ? Colors.white38 : Colors.black38),
              const SizedBox(height: 12),
              Text(
                basket.error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final cheapest =
        compState.cheapestWithFuelRetailer ?? compState.cheapestRetailer;
    final isCheapest = cheapest == retailerName;

    // Separate matched and unmatched items
    final matchedItems = <ListItem>[];
    final unmatchedItems = <ListItem>[];
    for (final item in items) {
      final match = basket.matches[item.itemId];
      if (match != null && match.isMatched) {
        matchedItems.add(item);
      } else {
        unmatchedItems.add(item);
      }
    }

    return Column(
      children: [
        // Summary header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Text(
                basket.formattedProductTotal,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              if (isCheapest)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_rounded, size: 12, color: color),
                      const SizedBox(width: 3),
                      Text(
                        'Cheapest',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              const Spacer(),
              Text(
                '${basket.matchedCount}/${basket.totalItems} found',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
            ],
          ),
        ),

        // Fuel cost subtitle
        if (basket.fuelCost != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Icon(Icons.local_gas_station,
                    size: 14,
                    color: isDark ? Colors.white54 : Colors.black54),
                const SizedBox(width: 4),
                Text(
                  '+ R${basket.fuelCost!.toStringAsFixed(2)} fuel (${basket.distanceKm?.toStringAsFixed(1)} km)',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                const Spacer(),
                Text(
                  'Total: ${basket.formattedGrandTotal}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),

        Divider(
          height: 1,
          indent: 16,
          endIndent: 16,
          color: isDark ? AppColors.dividerDark : AppColors.divider,
        ),

        // Item rows
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.only(bottom: 8),
            children: [
              // Matched items
              ...matchedItems.map((item) {
                final match = basket.matches[item.itemId]!;
                return _ItemRow(
                  item: item,
                  match: match,
                  retailerColor: color,
                  isDark: isDark,
                );
              }),

              // Unmatched section
              if (unmatchedItems.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'Not found (${unmatchedItems.length})',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ),
                ...unmatchedItems.map((item) {
                  return _ItemRow(
                    item: item,
                    match: basket.matches[item.itemId],
                    retailerColor: color,
                    isDark: isDark,
                  );
                }),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Individual item row
// =============================================================================

class _ItemRow extends StatelessWidget {
  final ListItem item;
  final ListItemMatch? match;
  final Color retailerColor;
  final bool isDark;

  const _ItemRow({
    required this.item,
    required this.match,
    required this.retailerColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final isMatched = match?.isMatched ?? false;
    final isCheapest = match?.isCheapestForItem ?? false;

    // Confidence icon
    Widget confidenceIcon;
    if (!isMatched) {
      confidenceIcon = Icon(Icons.cancel_outlined,
          size: 18, color: isDark ? Colors.white24 : Colors.black26);
    } else if (match!.matchType == MatchType.exact) {
      confidenceIcon =
          const Icon(Icons.check_circle, size: 18, color: AppColors.success);
    } else if (match!.matchType == MatchType.similar) {
      confidenceIcon =
          const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.warning);
    } else {
      confidenceIcon =
          Icon(Icons.help_outline, size: 18, color: Colors.orange.shade400);
    }

    // Price color
    Color priceColor;
    if (!isMatched) {
      priceColor = isDark ? Colors.white38 : Colors.black38;
    } else if (isCheapest) {
      priceColor = AppColors.success;
    } else {
      priceColor = retailerColor;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          confidenceIcon,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.itemName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isMatched
                        ? null
                        : (isDark ? Colors.white38 : Colors.black38),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (isMatched && match!.matchedProductName != null)
                  Text(
                    match!.matchedProductName!,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (item.itemQuantity > 1)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'x${item.itemQuantity.toStringAsFixed(item.itemQuantity == item.itemQuantity.roundToDouble() ? 0 : 1)}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
            ),
          if (isMatched)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: isCheapest
                  ? BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    )
                  : null,
              child: Text(
                'R${match!.totalPrice.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: priceColor,
                ),
              ),
            )
          else
            Text(
              'Not found',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
        ],
      ),
    );
  }
}
