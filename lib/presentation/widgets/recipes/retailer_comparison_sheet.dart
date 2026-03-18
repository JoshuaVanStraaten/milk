// lib/presentation/widgets/recipes/retailer_comparison_sheet.dart
//
// Sprint 10b+10c — Retailer cost comparison before export.
// Shows total basket cost per retailer, highlights cheapest, and lets the
// user swap individual products (10c) before confirming a retailer.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/retailers.dart';
import '../../../data/models/recipe.dart';
import '../../providers/recipe_provider.dart';
import '../common/lottie_loading_indicator.dart';
import '../common/shimmer_text.dart';
import 'ingredient_matching_sheet.dart';

/// Opens the retailer comparison sheet. Returns the [RetailerBasket] the user
/// chose, or null if they cancelled.
Future<RetailerBasket?> showRetailerComparisonSheet({
  required BuildContext context,
  required WidgetRef ref,
  required List<RecipeIngredient> selectedIngredients,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet<RetailerBasket>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RetailerComparisonSheet(
      selectedIngredients: selectedIngredients,
      isDark: isDark,
    ),
  );
}

class _RetailerComparisonSheet extends ConsumerStatefulWidget {
  final List<RecipeIngredient> selectedIngredients;
  final bool isDark;

  const _RetailerComparisonSheet({
    required this.selectedIngredients,
    required this.isDark,
  });

  @override
  ConsumerState<_RetailerComparisonSheet> createState() =>
      _RetailerComparisonSheetState();
}

class _RetailerComparisonSheetState
    extends ConsumerState<_RetailerComparisonSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final List<String> _retailerNames = Retailers.all.keys.toList();
  bool _hasJumpedToCheapest = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _retailerNames.length,
      vsync: this,
    );
    // Rebuild when user manually changes tabs so "Shop at X" label updates
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(retailerComparisonProvider.notifier).runComparison(
            selectedIngredients: widget.selectedIngredients,
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
      // Force rebuild so the "Shop at" button label updates
      setState(() {});
    }
  }

  void _confirmRetailer() {
    final state = ref.read(retailerComparisonProvider);
    final retailerName = _retailerNames[_tabController.index];
    final basket = state.baskets[retailerName];
    if (basket == null) return;
    Navigator.of(context).pop(basket);
  }

  @override
  Widget build(BuildContext context) {
    final compState = ref.watch(retailerComparisonProvider);
    final isDark = widget.isDark;

    // Auto-jump to cheapest once data loads
    if (!compState.isLoading && compState.hasData) {
      final cheapest = compState.cheapestRetailer;
      if (cheapest != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _jumpToCheapest(cheapest),
        );
      }
    }

    final currentRetailer = _retailerNames[_tabController.index];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.backgroundDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.6,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              // Handle + title row
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
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                child: Row(
                  children: [
                    const Icon(Icons.compare_arrows, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Compare Prices',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
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

              // Tab bar
              TabBar(
                controller: _tabController,
                isScrollable: false,
                tabAlignment: TabAlignment.fill,
                tabs: _retailerNames.map((name) {
                  final basket = compState.baskets[name];
                  final isCheapest = compState.cheapestRetailer == name;
                  final config = Retailers.fromName(name);
                  return _RetailerTab(
                    name: _shortName(name),
                    basket: basket,
                    isCheapest: isCheapest,
                    color: config?.color ?? AppColors.primary,
                  );
                }).toList(),
                labelPadding: EdgeInsets.zero,
                indicatorColor: Retailers.fromName(currentRetailer)?.color ??
                    AppColors.primary,
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
                      selectedIngredients: widget.selectedIngredients,
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
                      onPressed: _confirmRetailer,
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            Retailers.fromName(currentRetailer)?.color ??
                                AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Shop at ${_shortName(currentRetailer)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
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
      'Woolworths': 'Woolworths',
      'Checkers': 'Checkers',
      'Shoprite': 'Shoprite',
    };
    return shorts[name] ?? name;
  }
}

// -----------------------------------------------------------------------------
// Tab label widget
// -----------------------------------------------------------------------------

class _RetailerTab extends StatelessWidget {
  final String name;
  final RetailerBasket? basket;
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
            hasError ? '–' : (basket?.formattedTotal ?? ''),
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

// -----------------------------------------------------------------------------
// Per-retailer tab content
// -----------------------------------------------------------------------------

class _RetailerTabContent extends ConsumerWidget {
  final String retailerName;
  final List<RecipeIngredient> selectedIngredients;
  final bool isDark;
  final ScrollController scrollController;

  const _RetailerTabContent({
    required this.retailerName,
    required this.selectedIngredients,
    required this.isDark,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compState = ref.watch(retailerComparisonProvider);
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
                      'Finding the best prices for ${selectedIngredients.length} ingredients',
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

    final isCheapest = compState.cheapestRetailer == retailerName;

    return Column(
      children: [
        // Retailer total header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Text(
                basket.formattedTotal,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              if (isCheapest)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
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
                '${basket.matchedCount}/${selectedIngredients.length} found',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.black54,
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

        // Ingredient rows
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            itemCount: selectedIngredients.length,
            padding: const EdgeInsets.only(bottom: 8),
            itemBuilder: (context, index) {
              final ing = selectedIngredients[index];
              final match = basket.matches[ing.ingredientId];

              return InkWell(
                onTap: () => _openSwapSheet(context, ref, ing, retailerName),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ing.ingredientName,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (match != null)
                              Text(
                                match.productName,
                                style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      isDark ? Colors.white54 : Colors.black54,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (match != null)
                        Text(
                          match.productPrice ?? '',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        )
                      else
                        Text(
                          'Not found',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.swap_horiz,
                        size: 16,
                        color: isDark ? Colors.white24 : Colors.black26,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openSwapSheet(
    BuildContext context,
    WidgetRef ref,
    RecipeIngredient ingredient,
    String retailerName,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => IngredientMatchingSheet(
        ingredient: ingredient,
        initialRetailer: retailerName,
        onSelectMatch: (match) {
          ref.read(retailerComparisonProvider.notifier).swapProduct(
                retailerName: retailerName,
                ingredientId: ingredient.ingredientId!,
                newMatch: match,
              );
          Navigator.of(context).pop();
        },
      ),
    );
  }
}
