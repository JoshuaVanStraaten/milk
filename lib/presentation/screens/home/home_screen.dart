// lib/presentation/screens/home/home_screen.dart
//
// REDESIGNED: Live deals home screen with psychological engagement patterns.
// Shows real-time promotions from nearby stores, savings calculations,
// and urgency-driven deal cards to make users want to open the app daily.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lottie/lottie.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import '../../../core/constants/retailers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/live_product.dart';
import '../../providers/auth_provider.dart';
import '../../providers/store_provider.dart';
import '../../providers/tutorial_provider.dart';
import '../../widgets/common/shimmer_text.dart';
import '../../widgets/products/add_to_list_sheet.dart';
import '../../widgets/tutorial/tutorial_targets.dart';
import '../../widgets/products/product_detail_card.dart';
import '../compare/compare_sheet.dart';

// =============================================================================
// HOME DEALS PROVIDER — fetches promotions from all nearby stores
// =============================================================================

/// A single deal for display on the home screen.
class HomeDeal {
  final String name;
  final String retailer;
  final String price;
  final double priceNumeric;
  final String promotionPrice;
  final String? imageUrl;
  final String promotionValid;
  final double? savingsAmount;
  final int? savingsPercent;
  final Map<String, double>? multiBuyInfo;

  const HomeDeal({
    required this.name,
    required this.retailer,
    required this.price,
    required this.priceNumeric,
    required this.promotionPrice,
    this.imageUrl,
    this.promotionValid = '',
    this.savingsAmount,
    this.savingsPercent,
    this.multiBuyInfo,
  });

  /// Effective special price for add-to-list
  double? get specialPrice {
    if (multiBuyInfo != null) return multiBuyInfo!['pricePerItem'];
    final promoNum = double.tryParse(
      promotionPrice
          .replaceAll('R', '')
          .replaceAll(',', '')
          .replaceAll(' ', '')
          .trim(),
    );
    if (promoNum != null && promoNum > 0 && promoNum < priceNumeric)
      return promoNum;
    return null;
  }

  /// Convert to LiveProduct for detail screen navigation
  LiveProduct toLiveProduct() {
    return LiveProduct(
      name: name,
      price: price,
      priceNumeric: priceNumeric,
      promotionPrice: promotionPrice,
      retailer: retailer,
      imageUrl: imageUrl,
      promotionValid: promotionValid,
      hasPromo: true,
    );
  }
}

/// State for home deals
class HomeDealsState {
  final List<HomeDeal> hotDeals; // Top featured deals (carousel)
  final Map<String, List<HomeDeal>> dealsByRetailer; // Grouped by store
  final bool isLoading;
  final String? error;
  final int totalDealsCount;
  final double totalPotentialSavings;

  const HomeDealsState({
    this.hotDeals = const [],
    this.dealsByRetailer = const {},
    this.isLoading = false,
    this.error,
    this.totalDealsCount = 0,
    this.totalPotentialSavings = 0,
  });

  HomeDealsState copyWith({
    List<HomeDeal>? hotDeals,
    Map<String, List<HomeDeal>>? dealsByRetailer,
    bool? isLoading,
    String? error,
    int? totalDealsCount,
    double? totalPotentialSavings,
  }) {
    return HomeDealsState(
      hotDeals: hotDeals ?? this.hotDeals,
      dealsByRetailer: dealsByRetailer ?? this.dealsByRetailer,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      totalDealsCount: totalDealsCount ?? this.totalDealsCount,
      totalPotentialSavings:
          totalPotentialSavings ?? this.totalPotentialSavings,
    );
  }
}

/// Fetches promo products from all nearby retailers.
class HomeDealsNotifier extends StateNotifier<HomeDealsState> {
  final Ref _ref;

  HomeDealsNotifier(this._ref) : super(const HomeDealsState());

  Future<void> loadDeals() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final api = _ref.read(liveApiServiceProvider);
      final storeSelection = _ref.read(storeSelectionProvider).value;

      if (storeSelection == null || storeSelection.stores.isEmpty) {
        state = state.copyWith(isLoading: false, error: 'No stores found');
        return;
      }

      final allDeals = <HomeDeal>[];
      final byRetailer = <String, List<HomeDeal>>{};

      // Fetch from each retailer in parallel
      final futures = <Future<void>>[];

      for (final entry in storeSelection.stores.entries) {
        futures.add(() async {
          try {
            // Fetch multiple pages — more for retailers with sparse promos
            final allPageProducts = <LiveProduct>[];
            final maxPages = Retailers.isPharmacy(entry.key) ||
                    entry.key == 'Makro'
                ? 4  // Pharmacy/Makro have sparse promos, fetch more
                : 2;

            for (int page = 0; page < maxPages; page++) {
              final response = await api.browseProducts(
                retailer: entry.key,
                store: entry.value,
                page: page,
              );
              allPageProducts.addAll(response.products);
              // Stop early if page had few results (small catalog)
              if (response.products.length < 20) break;
            }

            final products = allPageProducts;

            final promos = products.where((p) => p.hasPromo).map((p) {
              // Calculate savings
              double? savings;
              int? savingsPercent;

              // Try to parse promo as a direct price
              final promoNum = double.tryParse(
                p.promotionPrice
                    .replaceAll('R', '')
                    .replaceAll(',', '')
                    .replaceAll(' ', '')
                    .trim(),
              );

              if (promoNum != null &&
                  promoNum > 0 &&
                  p.priceNumeric > promoNum) {
                savings = p.priceNumeric - promoNum;
                savingsPercent = ((savings / p.priceNumeric) * 100).round();
              }

              // Try multi-buy: "2 For R24"
              if (savings == null) {
                final multiBuy = p.multiBuyInfo;
                if (multiBuy != null && p.priceNumeric > 0) {
                  final perItem = multiBuy['pricePerItem']!;
                  if (perItem < p.priceNumeric) {
                    savings = p.priceNumeric - perItem;
                    savingsPercent = ((savings / p.priceNumeric) * 100).round();
                  }
                }
              }

              // Parse "X% off - Was RY.YY" or "Save RX.XX" formats
              if (savings == null) {
                final promoLower = p.promotionPrice.toLowerCase();

                // "22% off - Was R82.95" → extract percent
                final percentMatch = RegExp(r'(\d+)%\s*off').firstMatch(promoLower);
                if (percentMatch != null) {
                  savingsPercent = int.tryParse(percentMatch.group(1)!);
                  // Extract "Was" price to calculate savings amount
                  final wasMatch = RegExp(r'was\s*r\s*([\d,.]+)').firstMatch(promoLower);
                  if (wasMatch != null) {
                    final wasPrice = double.tryParse(
                      wasMatch.group(1)!.replaceAll(',', ''),
                    );
                    if (wasPrice != null && wasPrice > p.priceNumeric) {
                      savings = wasPrice - p.priceNumeric;
                    }
                  }
                  // Fallback: compute from percent if no "Was" price
                  if (savings == null && savingsPercent != null && p.priceNumeric > 0) {
                    final originalPrice = p.priceNumeric / (1 - savingsPercent / 100);
                    savings = originalPrice - p.priceNumeric;
                  }
                }

                // "Save R8.00"
                if (savings == null) {
                  final saveMatch = RegExp(r'save\s*r\s*([\d,.]+)').firstMatch(promoLower);
                  if (saveMatch != null) {
                    savings = double.tryParse(
                      saveMatch.group(1)!.replaceAll(',', ''),
                    );
                    if (savings != null && p.priceNumeric > 0) {
                      savingsPercent = ((savings / (p.priceNumeric + savings)) * 100).round();
                    }
                  }
                }
              }

              return HomeDeal(
                name: p.name,
                retailer: p.retailer,
                price: p.price,
                priceNumeric: p.priceNumeric,
                promotionPrice: p.promotionPrice,
                imageUrl: p.imageUrl,
                promotionValid: p.promotionValid,
                savingsAmount: savings,
                savingsPercent: savingsPercent,
                multiBuyInfo: p.multiBuyInfo,
              );
            }).toList();

            allDeals.addAll(promos);
            if (promos.isNotEmpty) {
              byRetailer[entry.key] = promos;
            }
          } catch (e) {
            debugPrint('Failed to load deals for ${entry.key}: $e');
          }
        }());
      }

      await Future.wait(futures);

      // Sort hot deals: grocery/bulk retailers first, pharmacies last.
      // Within each group, sort by biggest savings.
      allDeals.sort((a, b) {
        final aIsPharmacy = Retailers.isPharmacy(a.retailer) ? 1 : 0;
        final bIsPharmacy = Retailers.isPharmacy(b.retailer) ? 1 : 0;
        if (aIsPharmacy != bIsPharmacy) return aIsPharmacy.compareTo(bIsPharmacy);
        final aScore = (a.savingsAmount ?? 0) + (a.savingsPercent ?? 0) * 0.5;
        final bScore = (b.savingsAmount ?? 0) + (b.savingsPercent ?? 0) * 0.5;
        return bScore.compareTo(aScore);
      });

      // Calculate total potential savings
      final totalSavings = allDeals
          .where((d) => d.savingsAmount != null)
          .fold<double>(0, (sum, d) => sum + d.savingsAmount!);

      state = HomeDealsState(
        hotDeals: allDeals.take(20).toList(), // Top 20 for carousel
        dealsByRetailer: byRetailer,
        totalDealsCount: allDeals.length,
        totalPotentialSavings: totalSavings,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

final homeDealsProvider =
    StateNotifierProvider<HomeDealsNotifier, HomeDealsState>((ref) {
      return HomeDealsNotifier(ref);
    });

// =============================================================================
// HOME SCREEN
// =============================================================================

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  bool _dealsLoaded = false;
  TutorialCoachMark? _tutorialCoachMark;
  bool _tutorialTriggered = false;

  // Tutorial GlobalKeys
  final _savingsBannerKey = GlobalKey();
  final _hotDealsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    // If deals are already cached, skip the fade-in animation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(homeDealsProvider);
      if (state.hotDeals.isNotEmpty) {
        _fadeController.value = 1.0;
      }
    });
  }

  @override
  void dispose() {
    _tutorialCoachMark?.finish();
    _fadeController.dispose();
    super.dispose();
  }

  void _tryShowTutorial() {
    if (_tutorialTriggered) return;
    final tutorialService = ref.read(tutorialServiceProvider);
    if (tutorialService.isHomeTutorialCompleted) return;

    // Keys must be rendered before we can show the dialog
    if (_savingsBannerKey.currentContext == null ||
        _hotDealsKey.currentContext == null) return;

    _tutorialTriggered = true;

    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _WelcomeDialog(
          onStart: () {
            Navigator.of(context).pop();
            _startTutorialOverlay();
          },
          onSkip: () {
            Navigator.of(context).pop();
            ref.read(tutorialServiceProvider).skipAll();
          },
        ),
      );
    });
  }

  /// Waits until both target keys are rendered, then starts the overlay.
  /// Handles the case where "Start tour" is tapped before deals finish loading.
  void _startTutorialOverlay() {
    if (!mounted) return;

    if (_savingsBannerKey.currentContext == null ||
        _hotDealsKey.currentContext == null) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) { _startTutorialOverlay(); }
      });
      return;
    }

    final targets = buildHomeTutorialTargets(
      savingsBannerKey: _savingsBannerKey,
      hotDealsKey: _hotDealsKey,
    );
    targets.last = TargetFocus(
      identify: 'bottom_nav',
      targetPosition: bottomNavTargetPosition(context),
      shape: ShapeLightFocus.RRect,
      radius: 0,
      contents: targets.last.contents ?? [],
    );

    _tutorialCoachMark = TutorialCoachMark(
      targets: targets,
      colorShadow: Colors.black,
      opacityShadow: 0.8,
      hideSkip: true,
      paddingFocus: 10,
      focusAnimationDuration: const Duration(milliseconds: 300),
      unFocusAnimationDuration: const Duration(milliseconds: 300),
      onFinish: () {
        ref.read(tutorialServiceProvider).completeHomeTutorial();
      },
      onSkip: () {
        ref.read(tutorialServiceProvider).skipAll();
        return true;
      },
    )..show(context: context);
  }

  void _loadDealsOnce() {
    final state = ref.read(homeDealsProvider);
    // Skip if already loaded or currently loading
    if (state.hotDeals.isNotEmpty || state.isLoading) {
      _dealsLoaded = true;
      return;
    }
    if (!_dealsLoaded) {
      _dealsLoaded = true;
      Future.microtask(() {
        ref.read(homeDealsProvider.notifier).loadDeals();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProfileAsync = ref.watch(currentUserProfileProvider);
    final dealsState = ref.watch(homeDealsProvider);
    final storeSelection = ref.watch(storeSelectionProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Trigger load once stores are available
    storeSelection.whenData((_) => _loadDealsOnce());

    // Animate in once deals are loaded
    if (!dealsState.isLoading && dealsState.hotDeals.isNotEmpty) {
      _fadeController.forward();
      // Trigger tutorial after deals have rendered
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryShowTutorial());
    }

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.background,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => ref.read(homeDealsProvider.notifier).loadDeals(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            // ─── SLIVER APP BAR ───
            _buildSliverAppBar(context, userProfileAsync, isDark),

            // ─── SAVINGS BANNER ───
            if (!dealsState.isLoading && dealsState.totalDealsCount > 0)
              SliverToBoxAdapter(
                child: Container(
                  key: _savingsBannerKey,
                  child: _SavingsBanner(
                    totalDeals: dealsState.totalDealsCount,
                    totalSavings: dealsState.totalPotentialSavings,
                    isDark: isDark,
                  ),
                ),
              ),

            // ─── HOT DEALS CAROUSEL ───
            if (dealsState.isLoading)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: _DealsLoadingAnimation()),
              )
            else if (dealsState.hotDeals.isNotEmpty)
              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _fadeController,
                  child: Container(
                    key: _hotDealsKey,
                    child: _HotDealsSection(
                      deals: dealsState.hotDeals,
                      isDark: isDark,
                    ),
                  ),
                ),
              ),

            // ─── DEALS BY RETAILER (grocery first, then pharmacies) ───
            if (!dealsState.isLoading)
              ..._sortedRetailerEntries(dealsState.dealsByRetailer).map((entry) {
                final config = Retailers.fromName(entry.key);
                if (config == null)
                  return const SliverToBoxAdapter(child: SizedBox());
                return SliverToBoxAdapter(
                  child: FadeTransition(
                    opacity: _fadeController,
                    child: _RetailerDealsSection(
                      retailerName: entry.key,
                      config: config,
                      deals: entry.value,
                      isDark: isDark,
                      onViewAll: () {
                        ref.read(selectedRetailerProvider.notifier).state = entry.key;
                        context.go('/stores');
                      },
                    ),
                  ),
                );
              }),

            // ─── QUICK ACTIONS (fallback if no deals) ───
            if (!dealsState.isLoading && dealsState.hotDeals.isEmpty)
              SliverToBoxAdapter(child: _EmptyDealsState(isDark: isDark)),

            // Bottom padding
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  /// Orders retailer deal sections: grocery/bulk retailers first, pharmacies last.
  List<MapEntry<String, List<HomeDeal>>> _sortedRetailerEntries(
      Map<String, List<HomeDeal>> dealsByRetailer) {
    final entries = dealsByRetailer.entries.toList();
    entries.sort((a, b) {
      final aIsPharmacy = Retailers.isPharmacy(a.key) ? 1 : 0;
      final bIsPharmacy = Retailers.isPharmacy(b.key) ? 1 : 0;
      return aIsPharmacy.compareTo(bIsPharmacy);
    });
    return entries;
  }

  Widget _buildSliverAppBar(
    BuildContext context,
    AsyncValue userProfileAsync,
    bool isDark,
  ) {
    return SliverAppBar(
      expandedHeight: 120,
      floating: false,
      pinned: true,
      automaticallyImplyLeading: false,
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.background,
      surfaceTintColor: Colors.transparent,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
        title: userProfileAsync.when(
          data: (profile) {
            final greeting = _getGreeting();
            final name = profile?.displayName;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  name != null ? 'Hi, $name 👋' : 'Hi there 👋',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                  ),
                ),
              ],
            );
          },
          loading: () => const SizedBox(),
          error: (_, __) => const SizedBox(),
        ),
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

// =============================================================================
// SAVINGS BANNER — "You could save R134 this week" (Loss aversion + anchoring)
// =============================================================================

class _SavingsBanner extends StatefulWidget {
  final int totalDeals;
  final double totalSavings;
  final bool isDark;

  const _SavingsBanner({
    required this.totalDeals,
    required this.totalSavings,
    required this.isDark,
  });

  @override
  State<_SavingsBanner> createState() => _SavingsBannerState();
}

class _SavingsBannerState extends State<_SavingsBanner>
    with TickerProviderStateMixin {
  late final AnimationController _bounceController;
  late final AnimationController _countController;
  late Animation<double> _bounceAnimation;
  late Animation<double> _countAnimation;

  @override
  void initState() {
    super.initState();

    // Piggy spring-in — single bounce entrance with delay
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _bounceAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.elasticOut),
    );
    // Small delay so the banner is visible before the piggy pops in
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _bounceController.forward();
    });

    // Count-up animation for savings value
    _countController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    _countAnimation = Tween<double>(begin: 0, end: widget.totalSavings)
        .animate(CurvedAnimation(
      parent: _countController,
      curve: Curves.easeOutQuart,
    ));
    _countController.forward();
  }

  @override
  void didUpdateWidget(covariant _SavingsBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.totalSavings != widget.totalSavings) {
      _countAnimation = Tween<double>(
        begin: oldWidget.totalSavings,
        end: widget.totalSavings,
      ).animate(CurvedAnimation(
        parent: _countController,
        curve: Curves.easeOutQuart,
      ));
      _countController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bounceController.dispose();
    _countController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [
                  AppColors.primary.withValues(alpha: 0.25),
                  AppColors.primaryDark.withValues(alpha: 0.15),
                ]
              : [
                  AppColors.primary.withValues(alpha: 0.08),
                  AppColors.primaryLight.withValues(alpha: 0.05),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: isDark ? 0.3 : 0.15),
        ),
      ),
      child: Row(
        children: [
          // Scale-bouncing piggy icon
          AnimatedBuilder(
            animation: _bounceAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _bounceAnimation.value,
                child: child,
              );
            },
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color:
                    AppColors.primary.withValues(alpha: isDark ? 0.3 : 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.savings_outlined,
                color: AppColors.primary,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.totalSavings > 0) ...[
                  AnimatedBuilder(
                    animation: _countAnimation,
                    builder: (context, _) {
                      return Text(
                        'Save up to R${_countAnimation.value.toStringAsFixed(0)} this week',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimary,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  '${widget.totalDeals} specials near you right now',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.local_fire_department_rounded,
            color: AppColors.secondary,
            size: 28,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// HOT DEALS CAROUSEL — Horizontal scroll of best deals (Variable reward)
// =============================================================================

class _HotDealsSection extends StatelessWidget {
  final List<HomeDeal> deals;
  final bool isDark;

  const _HotDealsSection({required this.deals, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(
            children: [
              Text('🔥', style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                'Hot Deals',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                'Near you',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 210,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: deals.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _HotDealCard(deal: deals[index], isDark: isDark),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HotDealCard extends ConsumerWidget {
  final HomeDeal deal;
  final bool isDark;

  const _HotDealCard({required this.deal, required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = Retailers.fromName(deal.retailer);
    final retailerColor = config?.color ?? AppColors.primary;

    return GestureDetector(
      onTap: () => _openDetail(context, ref),
      child: Container(
        width: 160,
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDarkMode : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppColors.dividerDark : AppColors.divider,
            width: 1,
          ),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Image with badges
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: Stack(
                children: [
                  Container(
                    height: 100,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: deal.imageUrl != null && deal.imageUrl!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: deal.imageUrl!,
                              fit: BoxFit.contain,
                              errorWidget: (_, __, ___) => _buildPlaceholder(),
                            )
                          : _buildPlaceholder(),
                    ),
                  ),

                  // Savings badge (top-left)
                  if (deal.savingsPercent != null && deal.savingsPercent! > 0)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '-${deal.savingsPercent}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),

                  // Retailer pill (top-right)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: retailerColor.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _shortRetailerName(deal.retailer),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),

                  // Action buttons (bottom-right)
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _HomeCompareButton(
                          onTap: () => showCompareSheet(
                            context,
                            ref,
                            deal.toLiveProduct(),
                          ),
                          isDark: isDark,
                          size: 28,
                        ),
                        const SizedBox(width: 4),
                        _QuickAddButton(
                          onTap: () => _addToList(context, ref),
                          isDark: isDark,
                          size: 28,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Product info section
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product name — fixed 2 lines
                  SizedBox(
                    height: 30,
                    child: Text(
                      deal.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Prices — full width, no buttons competing
                  Text(
                    deal.promotionPrice,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    deal.price,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                      decoration: TextDecoration.lineThrough,
                      decorationColor: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, WidgetRef ref) {
    showProductDetailCard(
      context: context,
      ref: ref,
      product: deal.toLiveProduct(),
    );
  }

  void _addToList(BuildContext context, WidgetRef ref) {
    showAddToListSheet(
      context,
      ref,
      productName: deal.name,
      price: deal.priceNumeric,
      retailer: deal.retailer,
      specialPrice: deal.specialPrice,
      imageUrl: deal.imageUrl,
      priceDisplay: deal.price,
      multiBuyInfo: deal.multiBuyInfo,
    );
  }

  Widget _buildPlaceholder() {
    return const Center(
      child: Icon(
        Icons.image_outlined,
        size: 32,
        color: AppColors.textDisabled,
      ),
    );
  }

  String _shortRetailerName(String name) {
    if (name == 'Pick n Pay') return 'PnP';
    if (name.length > 10) return name.substring(0, 8);
    return name;
  }
}

// =============================================================================
// RETAILER DEALS SECTION — Grouped deals per store
// =============================================================================

class _RetailerDealsSection extends StatelessWidget {
  final String retailerName;
  final RetailerConfig config;
  final List<HomeDeal> deals;
  final bool isDark;
  final VoidCallback onViewAll;

  const _RetailerDealsSection({
    required this.retailerName,
    required this.config,
    required this.deals,
    required this.isDark,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    if (deals.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 16, 12),
          child: Row(
            children: [
              // Retailer color dot
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: config.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$retailerName Specials',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: onViewAll,
                child: Text(
                  'View all products',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Horizontal deal cards — same style as Hot Deals
        SizedBox(
          height: 210,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: deals.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _HotDealCard(deal: deals[index], isDark: isDark),
              );
            },
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// EMPTY STATE — When no deals found (still useful)
// =============================================================================

class _EmptyDealsState extends StatelessWidget {
  final bool isDark;

  const _EmptyDealsState({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 32),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.local_offer_outlined,
              size: 40,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Loading deals from your nearby stores...',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Pull down to refresh',
            style: TextStyle(
              fontSize: 14,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 32),

          // Quick actions as fallback
          _QuickActionChip(
            icon: Icons.store_rounded,
            label: 'Browse Products',
            onTap: () => context.go('/stores'),
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          _QuickActionChip(
            icon: Icons.auto_awesome,
            label: 'Generate a Recipe',
            onTap: () => context.go('/recipes'),
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          _QuickActionChip(
            icon: Icons.list_alt_rounded,
            label: 'My Shopping Lists',
            onTap: () => context.go('/lists'),
            isDark: isDark,
          ),
        ],
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDark;

  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 22, color: AppColors.primary),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// QUICK ADD BUTTON — small "+" to add product to shopping list
// =============================================================================

class _QuickAddButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isDark;
  final double size;

  const _QuickAddButton({
    required this.onTap,
    required this.isDark,
    this.size = 30,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(size / 3),
        ),
        child: Icon(Icons.add_rounded, size: size * 0.6, color: Colors.white),
      ),
    );
  }
}

// =============================================================================
// COMPARE BUTTON — small compare icon button for deal cards
// =============================================================================

class _HomeCompareButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isDark;
  final double size;

  const _HomeCompareButton({
    required this.onTap,
    required this.isDark,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDarkModeLight : AppColors.surface,
          borderRadius: BorderRadius.circular(size / 3),
        ),
        child: Icon(
          Icons.compare_arrows,
          size: size * 0.6,
          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
        ),
      ),
    );
  }
}

// =============================================================================
// LOADING ANIMATION — SA-themed trolley with rotating messages
// =============================================================================

class _DealsLoadingAnimation extends StatefulWidget {
  const _DealsLoadingAnimation();

  @override
  State<_DealsLoadingAnimation> createState() => _DealsLoadingAnimationState();
}

class _DealsLoadingAnimationState extends State<_DealsLoadingAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _dotsController;
  int _messageIndex = 0;
  Timer? _messageTimer;

  // SA-flavoured loading messages
  static const _messages = [
    'Checking the specials for you...',
    'Eish, so many deals today!',
    'Finding the lekker prices...',
    'Comparing across all the stores...',
    'Almost there, just a sec...',
    'Hunting for the best bargains...',
    'Loading fresh deals nearby...',
    'Saving you money, one item at a time',
  ];

  @override
  void initState() {
    super.initState();
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _messageTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (mounted) {
        setState(() {
          _messageIndex = (_messageIndex + 1) % _messages.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _dotsController.dispose();
    _messageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Lottie grocery bag animation
          Lottie.asset(
            'assets/animations/grocery_shopping_bag_pickup_and_delivery.json',
            width: 200,
            height: 200,
            fit: BoxFit.contain,
            repeat: true,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                Icons.shopping_cart_rounded,
                size: 64,
                color: AppColors.primary,
              );
            },
          ),

            const SizedBox(height: 20),

            // Shimmer text with animated message rotation
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.3),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: ShimmerText(
                key: ValueKey<int>(_messageIndex),
                text: _messages[_messageIndex],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Animated dots
            AnimatedBuilder(
              animation: _dotsController,
              builder: (context, _) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (i) {
                    final delay = i * 0.2;
                    final t =
                        (_dotsController.value - delay).clamp(0.0, 1.0);
                    final scale =
                        0.4 +
                        0.6 *
                            (t < 0.5 ? t * 2 : (1 - t) * 2)
                                .clamp(0.0, 1.0);
                    final opacity = 0.3 + 0.7 * scale;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color:
                            AppColors.primary.withValues(alpha: opacity),
                        shape: BoxShape.circle,
                      ),
                      transform:
                          Matrix4.diagonal3Values(scale, scale, 1.0),
                      transformAlignment: Alignment.center,
                    );
                  }),
                );
              },
            ),

            const SizedBox(height: 12),

            // Subtle hint
            Text(
              'Checking 4 retailers near you',
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
  }
}

// =============================================================================
// WELCOME DIALOG — shown before the tutorial overlay so timing is decoupled
// =============================================================================

class _WelcomeDialog extends StatelessWidget {
  final VoidCallback onStart;
  final VoidCallback onSkip;

  const _WelcomeDialog({required this.onStart, required this.onSkip});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.waving_hand_rounded,
                color: AppColors.primary,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Welcome to Milk!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Let's take a quick tour — we'll show you how to find the best grocery deals near you. Each tab has its own tip on first visit.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: onSkip,
                  child: Text(
                    'Skip',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onStart,
                  child: const Text(
                    'Start tour',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
