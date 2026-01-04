import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/models/recipe.dart';
import '../../providers/recipe_provider.dart';

/// Bottom sheet for matching an ingredient to a product
class IngredientMatchingSheet extends ConsumerStatefulWidget {
  final RecipeIngredient ingredient;
  final Function(IngredientProductMatch) onSelectMatch;

  const IngredientMatchingSheet({
    super.key,
    required this.ingredient,
    required this.onSelectMatch,
  });

  @override
  ConsumerState<IngredientMatchingSheet> createState() =>
      _IngredientMatchingSheetState();
}

class _IngredientMatchingSheetState
    extends ConsumerState<IngredientMatchingSheet> {
  String? _selectedRetailer;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.ingredient.ingredientName;
    // Load initial matches
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchMatches();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _searchMatches() {
    ref
        .read(ingredientMatchingProvider.notifier)
        .searchMatches(
          ingredientName: _searchController.text,
          retailer: _selectedRetailer,
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ingredientMatchingProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.backgroundDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
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
                    const Icon(Icons.search, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Match Ingredient',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            widget.ingredient.displayString,
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

              const SizedBox(height: 12),

              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search for product...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: _searchMatches,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: isDark
                        ? AppColors.surfaceDarkMode
                        : AppColors.surface,
                  ),
                  onSubmitted: (_) => _searchMatches(),
                ),
              ),

              const SizedBox(height: 12),

              // Retailer filter
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildRetailerChip(null, 'All Stores', isDark),
                      const SizedBox(width: 8),
                      _buildRetailerChip(
                        AppConstants.pickNPay,
                        'Pick n Pay',
                        isDark,
                      ),
                      const SizedBox(width: 8),
                      _buildRetailerChip(
                        AppConstants.woolworths,
                        'Woolworths',
                        isDark,
                      ),
                      const SizedBox(width: 8),
                      _buildRetailerChip(
                        AppConstants.shoprite,
                        'Shoprite',
                        isDark,
                      ),
                      const SizedBox(width: 8),
                      _buildRetailerChip(
                        AppConstants.checkers,
                        'Checkers',
                        isDark,
                      ),
                    ],
                  ),
                ),
              ),

              const Divider(height: 24),

              // Results
              Expanded(child: _buildResults(state, scrollController, isDark)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRetailerChip(String? retailer, String label, bool isDark) {
    final isSelected = _selectedRetailer == retailer;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedRetailer = selected ? retailer : null;
        });
        _searchMatches();
      },
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(
        fontSize: 12,
        color: isSelected ? Colors.white : null,
      ),
    );
  }

  Widget _buildResults(
    IngredientMatchingState state,
    ScrollController scrollController,
    bool isDark,
  ) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text(state.error!),
            TextButton(onPressed: _searchMatches, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (state.matches.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color: isDark
                  ? AppColors.textDisabledDark
                  : AppColors.textDisabled,
            ),
            const SizedBox(height: 16),
            Text(
              'No matching products found',
              style: TextStyle(
                fontSize: 16,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different search term',
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: state.matches.length,
      itemBuilder: (context, index) {
        final match = state.matches[index];
        return _buildMatchCard(match, isDark);
      },
    );
  }

  Widget _buildMatchCard(IngredientProductMatch match, bool isDark) {
    final retailerColor = _getRetailerColor(match.retailer);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => widget.onSelectMatch(match),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Product image
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: match.productImageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: match.productImageUrl!,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _buildPlaceholder(isDark),
                      )
                    : _buildPlaceholder(isDark),
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
                        match.retailer,
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
                      match.productName,
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

                    // Size and similarity
                    Row(
                      children: [
                        if (match.formattedSize != null) ...[
                          Text(
                            match.formattedSize!,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: _getSimilarityColor(
                              match.similarityScore,
                            ).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            match.similarityPercentage,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: _getSimilarityColor(match.similarityScore),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Price
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    match.productPrice ?? 'N/A',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                    ),
                  ),
                  if (match.productPromotionPrice != null &&
                      match.productPromotionPrice != 'No promo')
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      constraints: const BoxConstraints(maxWidth: 80),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        match.productPromotionPrice!,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: AppColors.error,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),

              const SizedBox(width: 8),
              const Icon(Icons.add_circle, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(bool isDark) {
    return Container(
      width: 60,
      height: 60,
      color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
      child: Icon(
        Icons.image_not_supported,
        size: 24,
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

  Color _getSimilarityColor(double score) {
    if (score >= 0.7) return AppColors.success;
    if (score >= 0.5) return AppColors.secondary;
    return AppColors.textSecondary;
  }
}
