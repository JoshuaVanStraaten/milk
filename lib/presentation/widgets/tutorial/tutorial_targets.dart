import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import '../../../core/theme/app_colors.dart';

// =============================================================================
// TUTORIAL TOOLTIP — reusable themed tooltip for all tutorial steps
// =============================================================================

class TutorialTooltip extends StatelessWidget {
  final String title;
  final String description;
  final int stepIndex;
  final int totalSteps;
  final VoidCallback? onTap;
  final VoidCallback? onSkip;

  const TutorialTooltip({
    super.key,
    required this.title,
    required this.description,
    required this.stepIndex,
    required this.totalSteps,
    this.onTap,
    this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step progress
          Row(
            children: [
              ...List.generate(totalSteps, (i) {
                return Container(
                  width: i == stepIndex ? 20 : 8,
                  height: 4,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: i == stepIndex
                        ? AppColors.primary
                        : AppColors.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
              const Spacer(),
              Text(
                '${stepIndex + 1}/$totalSteps',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Title
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          // Description
          Text(
            description,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          // Bottom row: tap hint + skip button
          Row(
            children: [
              Text(
                'Tap anywhere to continue',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.primary,
                ),
              ),
              const Spacer(),
              if (onSkip != null)
                GestureDetector(
                  onTap: onSkip,
                  child: Text(
                    'SKIP',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
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

// =============================================================================
// HOME TUTORIAL TARGETS
// =============================================================================

/// Keys: savingsBanner, hotDeals
/// Welcome step is shown as a Flutter Dialog before this runs — see _WelcomeDialog.
List<TargetFocus> buildHomeTutorialTargets({
  required GlobalKey savingsBannerKey,
  required GlobalKey hotDealsKey,
}) {
  const total = 3;

  return [
    // Step 1: Savings banner
    TargetFocus(
      identify: 'savings_banner',
      keyTarget: savingsBannerKey,
      shape: ShapeLightFocus.RRect,
      radius: 16,
      paddingFocus: 6,
      contents: [
        TargetContent(
          align: ContentAlign.bottom,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          builder: (context, controller) {
            return TutorialTooltip(
              title: 'Your Savings',
              description:
                  'See how much you could save across all nearby stores this week.',
              stepIndex: 0,
              totalSteps: total,
              onTap: controller.next,
              onSkip: controller.skip,
            );
          },
        ),
      ],
    ),

    // Step 2: Hot deals carousel
    TargetFocus(
      identify: 'hot_deals',
      keyTarget: hotDealsKey,
      shape: ShapeLightFocus.RRect,
      radius: 16,
      paddingFocus: 4,
      contents: [
        TargetContent(
          align: ContentAlign.bottom,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          builder: (context, controller) {
            return TutorialTooltip(
              title: 'Hot Deals',
              description:
                  'Swipe through the best deals near you. Tap the green + button on any card to add it to your shopping list.',
              stepIndex: 1,
              totalSteps: total,
              onTap: controller.next,
              onSkip: controller.skip,
            );
          },
        ),
      ],
    ),

    // Step 3: Bottom navigation
    TargetFocus(
      identify: 'bottom_nav',
      targetPosition: TargetPosition(
        const Size(400, 60),
        const Offset(0, 0), // Will be computed at runtime
      ),
      shape: ShapeLightFocus.RRect,
      radius: 0,
      contents: [
        TargetContent(
          align: ContentAlign.custom,
          customPosition: CustomTargetContentPosition(
            bottom: 80,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          builder: (context, controller) {
            return TutorialTooltip(
              title: 'Explore the App',
              description:
                  'Use these tabs to Browse products, find AI Recipes, manage your Shopping Lists, and view your Profile.',
              stepIndex: 2,
              totalSteps: total,
              onTap: controller.next,
              onSkip: controller.skip,
            );
          },
        ),
      ],
    ),
  ];
}

/// Compute bottom nav target position based on screen size.
/// Call this before showing the tutorial to set the correct position.
TargetPosition bottomNavTargetPosition(BuildContext context) {
  final screenSize = MediaQuery.of(context).size;
  return TargetPosition(
    Size(screenSize.width, 70),
    Offset(0, screenSize.height - 70),
  );
}

// =============================================================================
// BROWSE TUTORIAL TARGETS
// =============================================================================

List<TargetFocus> buildBrowseTutorialTargets({
  required GlobalKey storeButtonKey,
  required GlobalKey searchBarKey,
  required GlobalKey categoryChipKey,
  required GlobalKey filterIconKey,
}) {
  const total = 4;

  return [
    // Step 1: Store selector
    TargetFocus(
      identify: 'store_selector',
      keyTarget: storeButtonKey,
      shape: ShapeLightFocus.RRect,
      radius: 12,
      paddingFocus: 6,
      contents: [
        TargetContent(
          align: ContentAlign.bottom,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          builder: (context, controller) {
            return TutorialTooltip(
              title: 'Switch Stores',
              description:
                  'Tap here to switch between Pick n Pay, Woolworths, Checkers, and Shoprite.',
              stepIndex: 0,
              totalSteps: total,
              onTap: controller.next,
              onSkip: controller.skip,
            );
          },
        ),
      ],
    ),

    // Step 2: Search bar
    TargetFocus(
      identify: 'search_bar',
      keyTarget: searchBarKey,
      shape: ShapeLightFocus.RRect,
      radius: 12,
      paddingFocus: 4,
      contents: [
        TargetContent(
          align: ContentAlign.bottom,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          builder: (context, controller) {
            return TutorialTooltip(
              title: 'Search Products',
              description:
                  'Search for any product across thousands of items.',
              stepIndex: 1,
              totalSteps: total,
              onTap: controller.next,
              onSkip: controller.skip,
            );
          },
        ),
      ],
    ),

    // Step 3: Category chips
    TargetFocus(
      identify: 'category_chips',
      keyTarget: categoryChipKey,
      shape: ShapeLightFocus.RRect,
      radius: 12,
      paddingFocus: 4,
      contents: [
        TargetContent(
          align: ContentAlign.bottom,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          builder: (context, controller) {
            return TutorialTooltip(
              title: 'Browse by Category',
              description:
                  'Filter by category like Dairy, Beverages, or Bakery.',
              stepIndex: 2,
              totalSteps: total,
              onTap: controller.next,
              onSkip: controller.skip,
            );
          },
        ),
      ],
    ),

    // Step 4: Filter icon
    TargetFocus(
      identify: 'filter_icon',
      keyTarget: filterIconKey,
      shape: ShapeLightFocus.Circle,
      paddingFocus: 8,
      contents: [
        TargetContent(
          align: ContentAlign.bottom,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          builder: (context, controller) {
            return TutorialTooltip(
              title: 'Sort & Filter',
              description:
                  'Sort by price or show only products on promotion.',
              stepIndex: 3,
              totalSteps: total,
              onTap: controller.next,
              onSkip: controller.skip,
            );
          },
        ),
      ],
    ),
  ];
}

// =============================================================================
// RECIPES TUTORIAL TARGETS
// =============================================================================

List<TargetFocus> buildRecipesTutorialTargets({
  required GlobalKey modeSelectorKey,
}) {
  return [
    TargetFocus(
      identify: 'mode_selector',
      keyTarget: modeSelectorKey,
      shape: ShapeLightFocus.RRect,
      radius: 12,
      paddingFocus: 6,
      contents: [
        TargetContent(
          align: ContentAlign.bottom,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          builder: (context, controller) {
            return TutorialTooltip(
              title: 'Recipe Modes',
              description:
                  'Switch between finding a recipe by name or using ingredients you already have.',
              stepIndex: 0,
              totalSteps: 1,
              onTap: controller.next,
              onSkip: controller.skip,
            );
          },
        ),
      ],
    ),
  ];
}

// =============================================================================
// RECIPE RESULT TUTORIAL TARGETS (shown after first recipe generation)
// =============================================================================

List<TargetFocus> buildRecipeResultTutorialTargets({
  GlobalKey? storeSelectorKey,
  GlobalKey? exportButtonKey,
}) {
  final targets = <TargetFocus>[];
  final hasStoreSelector = storeSelectorKey != null;
  final hasExportButton = exportButtonKey != null;
  final total = (hasStoreSelector ? 1 : 0) + (hasExportButton ? 1 : 0);
  var step = 0;

  // Step 1: Re-match store chips (if visible)
  if (hasStoreSelector) {
    targets.add(TargetFocus(
      identify: 'store_selector',
      keyTarget: storeSelectorKey,
      shape: ShapeLightFocus.RRect,
      radius: 12,
      paddingFocus: 6,
      contents: [
        TargetContent(
          align: ContentAlign.bottom,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          builder: (context, controller) {
            return TutorialTooltip(
              title: 'Switch Retailers',
              description:
                  'Each ingredient is matched to a real product. Tap "Change" to swap it.\n\nUse these chips to re-match all ingredients to a specific store.',
              stepIndex: step,
              totalSteps: total,
              onTap: controller.next,
              onSkip: controller.skip,
            );
          },
        ),
      ],
    ));
    step++;
  }

  // Step 2: Export button (if visible)
  if (hasExportButton) {
    targets.add(TargetFocus(
      identify: 'export_button',
      keyTarget: exportButtonKey,
      shape: ShapeLightFocus.RRect,
      radius: 12,
      paddingFocus: 6,
      contents: [
        TargetContent(
          align: ContentAlign.top,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          builder: (context, controller) {
            return TutorialTooltip(
              title: 'Export to Shopping List',
              description:
                  'Add matched ingredients to a shopping list. You can deselect items you already have.',
              stepIndex: step,
              totalSteps: total,
              onTap: controller.next,
              onSkip: controller.skip,
            );
          },
        ),
      ],
    ));
  }

  return targets;
}

// =============================================================================
// LISTS TUTORIAL TARGETS
// =============================================================================

List<TargetFocus> buildListsTutorialTargets({
  required GlobalKey createListFabKey,
  GlobalKey? firstListCardKey,
}) {
  final hasListCard = firstListCardKey != null;
  final total = hasListCard ? 2 : 1;

  return [
    // Step 1: Create list FAB
    TargetFocus(
      identify: 'create_list_fab',
      keyTarget: createListFabKey,
      shape: ShapeLightFocus.RRect,
      radius: 16,
      paddingFocus: 8,
      contents: [
        TargetContent(
          align: ContentAlign.top,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          builder: (context, controller) {
            return TutorialTooltip(
              title: 'Create a List',
              description:
                  'Tap here to create a new shopping list. Pick a store, choose a colour, and start adding items.',
              stepIndex: 0,
              totalSteps: total,
              onTap: controller.next,
              onSkip: controller.skip,
            );
          },
        ),
      ],
    ),

    // Step 2: List card interactions (only if lists exist)
    if (hasListCard)
      TargetFocus(
        identify: 'first_list_card',
        keyTarget: firstListCardKey,
        shape: ShapeLightFocus.RRect,
        radius: 16,
        paddingFocus: 6,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            builder: (context, controller) {
              return TutorialTooltip(
                title: 'Manage Your Lists',
                description:
                    'Tap to open a list. Long-press to select multiple for bulk deletion. Swipe left to quickly delete one.',
                stepIndex: 1,
                totalSteps: total,
                onTap: controller.next,
                onSkip: controller.skip,
              );
            },
          ),
        ],
      ),
  ];
}

// =============================================================================
// LIST DETAIL TUTORIAL TARGETS (shown on first list detail visit)
// =============================================================================

List<TargetFocus> buildListDetailTutorialTargets({
  required GlobalKey addItemButtonKey,
}) {
  const total = 2;

  return [
    // Step 1: Add items
    TargetFocus(
      identify: 'add_item_button',
      keyTarget: addItemButtonKey,
      shape: ShapeLightFocus.RRect,
      radius: 16,
      paddingFocus: 8,
      contents: [
        TargetContent(
          align: ContentAlign.top,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          builder: (context, controller) {
            return TutorialTooltip(
              title: 'Add Items',
              description:
                  'Add items manually or browse products from any store. You can also compare prices before adding.',
              stepIndex: 0,
              totalSteps: total,
              onTap: controller.next,
              onSkip: controller.skip,
            );
          },
        ),
      ],
    ),

    // Step 2: Item management hint (positioned at center of screen)
    TargetFocus(
      identify: 'item_management',
      targetPosition: TargetPosition(
        const Size(300, 100),
        const Offset(50, 300),
      ),
      shape: ShapeLightFocus.RRect,
      radius: 16,
      contents: [
        TargetContent(
          align: ContentAlign.bottom,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          builder: (context, controller) {
            return TutorialTooltip(
              title: 'Managing Items',
              description:
                  'Tap an item to edit it. Swipe left to quickly delete. Long-press to select multiple items for bulk deletion.',
              stepIndex: 1,
              totalSteps: total,
              onTap: controller.next,
              onSkip: controller.skip,
            );
          },
        ),
      ],
    ),
  ];
}
