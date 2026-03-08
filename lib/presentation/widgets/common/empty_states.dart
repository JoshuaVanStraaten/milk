import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Reusable empty state widget with consistent styling
class EmptyState extends StatelessWidget {
  final EmptyStateType type;
  final String? customTitle;
  final String? customMessage;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? customIcon;

  const EmptyState({
    super.key,
    required this.type,
    this.customTitle,
    this.customMessage,
    this.actionLabel,
    this.onAction,
    this.customIcon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final config = _getConfig(type);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Illustration
            customIcon ?? _buildIllustration(config, isDark),

            const SizedBox(height: 24),

            // Title
            Text(
              customTitle ?? config.title,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isDark
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 12),

            // Message
            Text(
              customMessage ?? config.message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),

            // Action button
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 32),
              _buildActionButton(actionLabel!, onAction!, config.color),
            ],

            // Tips section for some states
            if (config.tips != null) ...[
              const SizedBox(height: 32),
              _buildTips(config.tips!, isDark),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIllustration(_EmptyStateConfig config, bool isDark) {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            config.color.withValues(alpha: isDark ? 0.2 : 0.1),
            config.secondaryColor.withValues(alpha: isDark ? 0.15 : 0.05),
          ],
        ),
        shape: BoxShape.circle,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Main icon
          Icon(config.icon, size: 64, color: config.color),
          // Decorative accent
          if (config.accentIcon != null)
            Positioned(
              right: 20,
              bottom: 25,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: config.secondaryColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: config.secondaryColor.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(config.accentIcon, size: 20, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, VoidCallback onPressed, Color color) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.add),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
      ),
    );
  }

  Widget _buildTips(List<String> tips, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 18, color: AppColors.warning),
              const SizedBox(width: 8),
              Text(
                'Tips',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.textPrimaryDark
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...tips.map(
            (tip) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '•  ',
                    style: TextStyle(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      tip,
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
          ),
        ],
      ),
    );
  }

  _EmptyStateConfig _getConfig(EmptyStateType type) {
    switch (type) {
      case EmptyStateType.noLists:
        return _EmptyStateConfig(
          icon: Icons.format_list_bulleted_rounded,
          accentIcon: Icons.add,
          color: AppColors.primary,
          secondaryColor: AppColors.secondary,
          title: 'No Shopping Lists Yet',
          message:
              'Create your first list to start tracking prices and saving money on groceries.',
          tips: [
            'Add items from any store to a single list',
            'Items are automatically grouped by store',
            'Compare prices across retailers',
          ],
        );

      case EmptyStateType.emptyList:
        return _EmptyStateConfig(
          icon: Icons.shopping_basket_outlined,
          accentIcon: Icons.add_shopping_cart,
          color: AppColors.secondary,
          secondaryColor: AppColors.primary,
          title: 'Your List is Empty',
          message:
              'Start adding items from any store - they\'ll be grouped automatically.',
          tips: [
            'Add items from different stores to one list',
            'Long-press products to quickly add them',
            'Check off items as you shop',
          ],
        );

      case EmptyStateType.noProducts:
        return _EmptyStateConfig(
          icon: Icons.inventory_2_outlined,
          color: AppColors.textSecondary,
          secondaryColor: AppColors.primary,
          title: 'No Products Found',
          message:
              'We couldn\'t find any products matching your criteria. Try adjusting your search or filters.',
        );

      case EmptyStateType.noSearchResults:
        return _EmptyStateConfig(
          icon: Icons.search_off_rounded,
          color: AppColors.textSecondary,
          secondaryColor: AppColors.warning,
          title: 'No Results Found',
          message:
              'Try different keywords or check the spelling of your search term.',
          tips: [
            'Use simpler search terms',
            'Check for typos',
            'Try searching by brand name',
          ],
        );

      case EmptyStateType.noSharedLists:
        return _EmptyStateConfig(
          icon: Icons.people_outline_rounded,
          accentIcon: Icons.share,
          color: AppColors.primary,
          secondaryColor: AppColors.secondary,
          title: 'No Shared Lists',
          message:
              'Lists shared with you by family or friends will appear here.',
        );

      case EmptyStateType.offline:
        return _EmptyStateConfig(
          icon: Icons.wifi_off_rounded,
          color: AppColors.warning,
          secondaryColor: AppColors.error,
          title: 'You\'re Offline',
          message:
              'Check your internet connection and try again. Some features may be limited.',
        );

      case EmptyStateType.error:
        return _EmptyStateConfig(
          icon: Icons.error_outline_rounded,
          color: AppColors.error,
          secondaryColor: AppColors.warning,
          title: 'Something Went Wrong',
          message:
              'We encountered an error loading this content. Please try again.',
        );
    }
  }
}

/// Types of empty states
enum EmptyStateType {
  noLists,
  emptyList,
  noProducts,
  noSearchResults,
  noSharedLists,
  offline,
  error,
}

/// Configuration for empty state styling
class _EmptyStateConfig {
  final IconData icon;
  final IconData? accentIcon;
  final Color color;
  final Color secondaryColor;
  final String title;
  final String message;
  final List<String>? tips;

  const _EmptyStateConfig({
    required this.icon,
    this.accentIcon,
    required this.color,
    required this.secondaryColor,
    required this.title,
    required this.message,
    this.tips,
  });
}
