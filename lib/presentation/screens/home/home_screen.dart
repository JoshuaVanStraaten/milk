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
import '../../../core/constants/retailers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/live_product.dart';
import '../../../data/services/image_lookup_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/store_provider.dart';
import '../../widgets/products/add_to_list_sheet.dart';
import '../products/live_product_detail_screen.dart';

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
            // Fetch 2 pages for more promo variety
            final allPageProducts = <LiveProduct>[];
            for (int page = 0; page < 2; page++) {
              final response = await api.browseProducts(
                retailer: entry.key,
                store: entry.value,
                page: page,
              );
              allPageProducts.addAll(response.products);
              // Stop if first page had few results
              if (response.products.length < 20) break;
            }

            // Resolve Checkers/Shoprite images from bundled cache
            var products = allPageProducts;
            final lookup = ImageLookupService.instance;
            if (lookup.isReady) {
              final lower = entry.key.toLowerCase();
              if (lower.contains('checkers') || lower.contains('shoprite')) {
                products = products.map((p) {
                  final cached = lookup.lookupImage(
                    retailer: entry.key,
                    productName: p.name,
                  );
                  if (cached != null) return p.copyWith(imageUrl: cached);
                  return p;
                }).toList();
              }
            }

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

      // Sort hot deals: biggest savings first, then by savings percent
      allDeals.sort((a, b) {
        final aScore = (a.savingsAmount ?? 0) + (a.savingsPercent ?? 0) * 0.5;
        final bScore = (b.savingsAmount ?? 0) + (b.savingsPercent ?? 0) * 0.5;
        return bScore.compareTo(aScore);
      });

      // Calculate total potential savings
      final totalSavings = allDeals
          .where((d) => d.savingsAmount != null)
          .fold<double>(0, (sum, d) => sum + d.savingsAmount!);

      state = HomeDealsState(
        hotDeals: allDeals.take(8).toList(), // Top 8 for carousel
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

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _loadDealsOnce() {
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
                child: _SavingsBanner(
                  totalDeals: dealsState.totalDealsCount,
                  totalSavings: dealsState.totalPotentialSavings,
                  isDark: isDark,
                ),
              ),

            // ─── HOT DEALS CAROUSEL ───
            if (dealsState.isLoading)
              SliverToBoxAdapter(child: _DealsLoadingAnimation())
            else if (dealsState.hotDeals.isNotEmpty)
              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _fadeController,
                  child: _HotDealsSection(
                    deals: dealsState.hotDeals,
                    isDark: isDark,
                  ),
                ),
              ),

            // ─── DEALS BY RETAILER ───
            if (!dealsState.isLoading)
              ...dealsState.dealsByRetailer.entries.map((entry) {
                final config = Retailers.fromName(entry.key);
                if (config == null)
                  return const SliverToBoxAdapter(child: SizedBox());
                return SliverToBoxAdapter(
                  child: FadeTransition(
                    opacity: _fadeController,
                    child: _RetailerDealsSection(
                      retailerName: entry.key,
                      config: config,
                      deals: entry.value.take(6).toList(),
                      isDark: isDark,
                      onViewAll: () => context.go('/stores'),
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
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  name != null ? 'Hi, $name 👋' : 'Hi there 👋',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
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

class _SavingsBanner extends StatelessWidget {
  final int totalDeals;
  final double totalSavings;
  final bool isDark;

  const _SavingsBanner({
    required this.totalDeals,
    required this.totalSavings,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
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
          // Savings icon with pulse effect
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: isDark ? 0.3 : 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.savings_outlined,
              color: AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (totalSavings > 0) ...[
                  Text(
                    'Save up to R${totalSavings.toStringAsFixed(0)} this week',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  '$totalDeals specials near you right now',
                  style: TextStyle(
                    fontSize: 13,
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
                  fontWeight: FontWeight.w800,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                'Near you',
                style: TextStyle(
                  fontSize: 13,
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
          height: 248,
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
      onTap: () => _openDetail(context),
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
          children: [
            // Image with badges
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  child: Container(
                    height: 110,
                    width: double.infinity,
                    color: Colors.white,
                    child: deal.imageUrl != null && deal.imageUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: deal.imageUrl!,
                            fit: BoxFit.contain,
                            errorWidget: (_, __, ___) => _buildPlaceholder(),
                          )
                        : _buildPlaceholder(),
                  ),
                ),

                // Savings badge (top-right)
                if (deal.savingsPercent != null && deal.savingsPercent! > 0)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '-${deal.savingsPercent}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),

                // Retailer pill (top-left)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
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
              ],
            ),

            // Product info section
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
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
                  const SizedBox(height: 8),
                  // Prices + add button row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Prices column
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              deal.promotionPrice,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
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
                      // Quick add button
                      _QuickAddButton(
                        onTap: () => _addToList(context, ref),
                        isDark: isDark,
                        size: 32,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDetail(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LiveProductDetailScreen(product: deal.toLiveProduct()),
      ),
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
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
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
                    fontSize: 13,
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
          height: 248,
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
// LOADING ANIMATION — SA-themed trolley with rotating messages
// =============================================================================

class _DealsLoadingAnimation extends StatefulWidget {
  const _DealsLoadingAnimation();

  @override
  State<_DealsLoadingAnimation> createState() => _DealsLoadingAnimationState();
}

class _DealsLoadingAnimationState extends State<_DealsLoadingAnimation>
    with TickerProviderStateMixin {
  late AnimationController _trolleyController;
  late AnimationController _bounceController;
  late AnimationController _dotsController;
  int _messageIndex = 0;
  Timer? _messageTimer;

  // SA-flavoured loading messages
  static const _messages = [
    'Checking the specials for you...',
    'Eish, so many deals today! 🔥',
    'Finding the lekker prices...',
    'Comparing across all the stores...',
    'Almost there, just a sec...',
    'Hunting for the best bargains...',
    'Loading fresh deals nearby...',
    'Saving you money, one item at a time 💰',
  ];

  @override
  void initState() {
    super.initState();
    // Trolley slides left-right
    _trolleyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    // Items bounce
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    // Dot animation
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    // Rotate messages every 2.5 seconds
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
    _trolleyController.dispose();
    _bounceController.dispose();
    _dotsController.dispose();
    _messageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Animated trolley scene
          SizedBox(
            height: 100,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Moving trolley
                AnimatedBuilder(
                  animation: _trolleyController,
                  builder: (context, child) {
                    final dx = (_trolleyController.value - 0.5) * 60;
                    return Transform.translate(
                      offset: Offset(dx, 0),
                      child: child,
                    );
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Bouncing items above trolley
                      AnimatedBuilder(
                        animation: _bounceController,
                        builder: (context, _) {
                          final dy = _bounceController.value * -8;
                          return Transform.translate(
                            offset: Offset(0, dy),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('🥦', style: TextStyle(fontSize: 18)),
                                const SizedBox(width: 4),
                                Text('🍞', style: TextStyle(fontSize: 16)),
                                const SizedBox(width: 4),
                                Text('🥛', style: TextStyle(fontSize: 18)),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 4),
                      // Trolley icon
                      Icon(
                        Icons.shopping_cart_rounded,
                        size: 44,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),

                // Track/line
                Positioned(
                  bottom: 8,
                  left: 40,
                  right: 40,
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          AppColors.primary.withValues(alpha: 0.3),
                          AppColors.primary.withValues(alpha: 0.3),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Animated loading message
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
            child: Text(
              _messages[_messageIndex],
              key: ValueKey<int>(_messageIndex),
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

          // Animated dots progress
          AnimatedBuilder(
            animation: _dotsController,
            builder: (context, _) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (i) {
                  final delay = i * 0.2;
                  final t = (_dotsController.value - delay).clamp(0.0, 1.0);
                  final scale =
                      0.4 +
                      0.6 * (t < 0.5 ? t * 2 : (1 - t) * 2).clamp(0.0, 1.0);
                  final opacity = 0.3 + 0.7 * scale;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: opacity),
                      shape: BoxShape.circle,
                    ),
                    transform: Matrix4.diagonal3Values(scale, scale, 1.0),
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
