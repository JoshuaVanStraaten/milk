import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Base shimmer effect widget that provides the animated gradient
class ShimmerEffect extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const ShimmerEffect({super.key, required this.child, this.enabled = true});

  @override
  State<ShimmerEffect> createState() => _ShimmerEffectState();
}

class _ShimmerEffectState extends State<ShimmerEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      const Color(0xFF2D3748),
                      const Color(0xFF4A5568),
                      const Color(0xFF2D3748),
                    ]
                  : [
                      const Color(0xFFE5E7EB),
                      const Color(0xFFF3F4F6),
                      const Color(0xFFE5E7EB),
                    ],
              stops: const [0.0, 0.5, 1.0],
              transform: _SlidingGradientTransform(_animation.value),
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;

  const _SlidingGradientTransform(this.slidePercent);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0, 0);
  }
}

/// Basic skeleton box that can be customized
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Skeleton for a single product card in the grid
class ProductCardSkeleton extends StatelessWidget {
  const ProductCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Padded image placeholder — matches new LiveProductCard layout
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF374151) : AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),

          // Text placeholders
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Product name line 1
                  const SkeletonBox(height: 12, width: double.infinity),
                  const SizedBox(height: 4),
                  // Product name line 2
                  const SkeletonBox(height: 12, width: 80),
                  const SizedBox(height: 8),
                  // Price + two button placeholders
                  Row(
                    children: [
                      const SkeletonBox(height: 14, width: 60),
                      const Spacer(),
                      const SkeletonBox(height: 26, width: 26),
                      const SizedBox(width: 4),
                      const SkeletonBox(height: 26, width: 26),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Grid of product card skeletons
class ProductGridSkeleton extends StatelessWidget {
  final int itemCount;

  const ProductGridSkeleton({super.key, this.itemCount = 8});

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.72,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: itemCount,
        itemBuilder: (context, index) => const ProductCardSkeleton(),
      ),
    );
  }
}

/// Skeleton for a shopping list card
class ListCardSkeleton extends StatelessWidget {
  const ListCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            // Color indicator
            Container(
              width: 4,
              height: 60,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF374151)
                    : const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            const SizedBox(width: 16),

            // List info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // List name
                  const SkeletonBox(height: 18, width: 150),
                  const SizedBox(height: 8),
                  // Store name
                  const SkeletonBox(height: 14, width: 100),
                  const SizedBox(height: 10),
                  // Total price
                  const SkeletonBox(height: 16, width: 80),
                ],
              ),
            ),

            // Arrow placeholder
            SkeletonBox(height: 16, width: 16, borderRadius: 4),
          ],
        ),
      ),
    );
  }
}

/// List of shopping list card skeletons
class ListCardsSkeleton extends StatelessWidget {
  final int itemCount;

  const ListCardsSkeleton({super.key, this.itemCount = 5});

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        itemBuilder: (context, index) => const ListCardSkeleton(),
      ),
    );
  }
}

/// Skeleton for a list item in list detail screen
class ListItemSkeleton extends StatelessWidget {
  const ListItemSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: ListTile(
          leading: const SkeletonBox(height: 24, width: 24, borderRadius: 4),
          title: const SkeletonBox(height: 16, width: double.infinity),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Row(
                children: const [
                  SkeletonBox(height: 13, width: 50),
                  SizedBox(width: 8),
                  SkeletonBox(height: 13, width: 70),
                ],
              ),
              const SizedBox(height: 6),
              const SkeletonBox(height: 12, width: 80),
            ],
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: const [
              SkeletonBox(height: 16, width: 60),
              SizedBox(height: 6),
              SkeletonBox(height: 14, width: 14, borderRadius: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// List of list item skeletons
class ListItemsSkeleton extends StatelessWidget {
  final int itemCount;

  const ListItemsSkeleton({super.key, this.itemCount = 6});

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: itemCount,
        itemBuilder: (context, index) => const ListItemSkeleton(),
      ),
    );
  }
}

/// Skeleton for the list detail header
class ListDetailHeaderSkeleton extends StatelessWidget {
  const ListDetailHeaderSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ShimmerEffect(
      child: Container(
        padding: const EdgeInsets.all(20),
        color: isDark
            ? const Color(0xFF374151).withValues(alpha: 0.3)
            : const Color(0xFFE5E7EB).withValues(alpha: 0.5),
        child: Row(
          children: [
            // Icon container
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF374151)
                    : const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const SizedBox(width: 28, height: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonBox(height: 14, width: 100),
                  const SizedBox(height: 8),
                  const SkeletonBox(height: 24, width: 140),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full skeleton for list detail screen
class ListDetailSkeleton extends StatelessWidget {
  const ListDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        ListDetailHeaderSkeleton(),
        Divider(height: 1),
        Expanded(child: ListItemsSkeleton()),
      ],
    );
  }
}

/// Skeleton for product detail screen
class ProductDetailSkeleton extends StatelessWidget {
  const ProductDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ShimmerEffect(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product image
            Container(
              height: 300,
              width: double.infinity,
              color: isDark ? const Color(0xFF374151) : AppColors.surface,
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product name
                  const SkeletonBox(height: 24, width: double.infinity),
                  const SizedBox(height: 8),
                  const SkeletonBox(height: 24, width: 200),

                  const SizedBox(height: 16),

                  // Price section
                  const SkeletonBox(height: 14, width: 50),
                  const SizedBox(height: 8),
                  const SkeletonBox(height: 32, width: 100),

                  const SizedBox(height: 24),

                  // Info card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF374151).withValues(alpha: 0.5)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _buildInfoRowSkeleton(),
                        const SizedBox(height: 12),
                        _buildInfoRowSkeleton(),
                        const SizedBox(height: 12),
                        _buildInfoRowSkeleton(),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Button skeleton
                  const SkeletonBox(
                    height: 50,
                    width: double.infinity,
                    borderRadius: 12,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRowSkeleton() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: const [
        SkeletonBox(height: 14, width: 80),
        SkeletonBox(height: 14, width: 120),
      ],
    );
  }
}

/// Skeleton for store selector cards
class StoreSelectorSkeleton extends StatelessWidget {
  const StoreSelectorSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      child: GridView.count(
        padding: const EdgeInsets.all(16),
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        children: List.generate(4, (index) => const _StoreCardSkeleton()),
      ),
    );
  }
}

class _StoreCardSkeleton extends StatelessWidget {
  const _StoreCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF374151) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Logo placeholder
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF4A5568) : AppColors.surface,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: 12),
          // Store name placeholder
          const SkeletonBox(height: 16, width: 100),
        ],
      ),
    );
  }
}

/// Skeleton for home screen sections
class HomeSectionSkeleton extends StatelessWidget {
  const HomeSectionSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const SkeletonBox(height: 20, width: 150),
          ),
          // Horizontal list of cards
          SizedBox(
            height: 180,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 4,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: const _HomeCardSkeleton(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeCardSkeleton extends StatelessWidget {
  const _HomeCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: 140,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF374151) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image area
          Container(
            height: 100,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF4A5568) : AppColors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonBox(height: 14, width: 100),
                SizedBox(height: 6),
                SkeletonBox(height: 12, width: 60),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton for the home screen welcome section
class HomeScreenSkeleton extends StatelessWidget {
  const HomeScreenSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ShimmerEffect(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Welcome container
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF374151).withValues(alpha: 0.3)
                    : AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  // Icon placeholder
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF374151)
                          : const Color(0xFFE5E7EB),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Welcome text
                  const SkeletonBox(height: 24, width: 200),
                  const SizedBox(height: 12),
                  const SkeletonBox(height: 16, width: 280),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Quick action cards
            _QuickActionCardSkeleton(),
            const SizedBox(height: 16),
            _QuickActionCardSkeleton(),
          ],
        ),
      ),
    );
  }
}

class _QuickActionCardSkeleton extends StatelessWidget {
  const _QuickActionCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF374151) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icon placeholder
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF4A5568) : const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonBox(height: 16, width: 140),
                SizedBox(height: 8),
                SkeletonBox(height: 14, width: 200),
              ],
            ),
          ),
          const SkeletonBox(height: 16, width: 16, borderRadius: 4),
        ],
      ),
    );
  }
}
