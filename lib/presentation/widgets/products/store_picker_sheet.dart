// lib/presentation/widgets/products/store_picker_sheet.dart
//
// Store picker bottom sheet — shows nearby stores with staggered
// entrance animation. Tap to switch retailer, bottom button to
// refresh GPS location.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/retailers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/nearby_store.dart';
import '../../../data/services/location_service.dart';
import '../../providers/saved_locations_provider.dart';
import '../../providers/store_provider.dart';
import '../common/google_places_search_field.dart';
import 'branch_picker_sheet.dart';

class StorePickerSheet extends ConsumerStatefulWidget {
  final StoreSelection stores;
  final String selectedRetailer;
  final ValueChanged<String> onRetailerChanged;

  const StorePickerSheet({
    super.key,
    required this.stores,
    required this.selectedRetailer,
    required this.onRetailerChanged,
  });

  @override
  ConsumerState<StorePickerSheet> createState() => _StorePickerSheetState();
}

class _StorePickerSheetState extends ConsumerState<StorePickerSheet>
    with SingleTickerProviderStateMixin {
  bool _isRefreshing = false;
  late AnimationController _animController;

  bool _showAddressField = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _fetchFromCoords(double lat, double lng) async {
    await ref
        .read(storeSelectionProvider.notifier)
        .fetchNearbyStores(lat, lng);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stores updated to entered address'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _refreshLocation() async {
    setState(() => _isRefreshing = true);

    try {
      final position = await LocationService().getCurrentPosition();
      if (position != null && mounted) {
        await ref
            .read(storeSelectionProvider.notifier)
            .fetchNearbyStores(position.latitude, position.longitude);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Stores updated to your current location'),
              backgroundColor: AppColors.success,
              duration: Duration(seconds: 2),
            ),
          );
          Navigator.pop(context);
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not get your location'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final retailers = Retailers.all.values.toList();

    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.9;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: isDark ? AppColors.backgroundDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: keyboardHeight > 0 ? keyboardHeight + 12 : (bottomPad > 0 ? bottomPad + 12 : 20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Handle ──
              GestureDetector(
                onTap: () => Navigator.pop(context),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 10, 0, 6),
                  child: Center(
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
                ),
              ),

              // ── Header (soft tint band, no gradient) ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.storefront_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your Nearby Stores',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Tap to switch retailer, or change branch',
                            style: TextStyle(
                              fontSize: 12,
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
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.close_rounded,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                        size: 20,
                      ),
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 4),

              // ── Section label (subtle, neutral) ──
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'YOUR STORES',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),

              // ── Store cards — staggered entrance ──
              ...List.generate(retailers.length, (i) {
                final config = retailers[i];
                final store = widget.stores.forRetailer(config.name);
                final isSelected = config.name == widget.selectedRetailer;

                // Stagger: each card fades + slides in 80ms after previous
                final delay = i * 0.15;
                final interval = Interval(
                  delay.clamp(0.0, 0.6),
                  (delay + 0.4).clamp(0.0, 1.0),
                  curve: Curves.easeOutCubic,
                );
                final slideAnim =
                    Tween<Offset>(
                      begin: const Offset(0, 0.15),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(parent: _animController, curve: interval),
                    );
                final fadeAnim = CurvedAnimation(
                  parent: _animController,
                  curve: interval,
                );

                return SlideTransition(
                  position: slideAnim,
                  child: FadeTransition(
                    opacity: fadeAnim,
                    child: _StoreCard(
                      config: config,
                      store: store,
                      isSelected: isSelected,
                      isDark: isDark,
                      onTap: store != null
                          ? () {
                              widget.onRetailerChanged(config.name);
                              Navigator.pop(context);
                            }
                          : null,
                      onChangeBranch: () {
                        Navigator.pop(context);
                        showBranchPickerSheet(context, retailer: config);
                      },
                    ),
                  ),
                );
              }),

              const SizedBox(height: 16),

              // ── Section label ──
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'UPDATE YOUR LOCATION',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),

              // ── Actions row: primary (GPS) + secondary (address toggle) ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _ActionPill(
                        icon: Icons.my_location_rounded,
                        label: _isRefreshing
                            ? 'Updating…'
                            : 'Use my GPS',
                        isPrimary: true,
                        isLoading: _isRefreshing,
                        onTap: _isRefreshing ? null : _refreshLocation,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ActionPill(
                        icon: Icons.travel_explore_rounded,
                        label: _showAddressField
                            ? 'Hide address'
                            : 'Enter address',
                        isPrimary: false,
                        isExpanded: _showAddressField,
                        onTap: () => setState(() {
                          _showAddressField = !_showAddressField;
                        }),
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
              ),

              if (_showAddressField) ...[
                // ── Saved locations (compact rows) ──
                Builder(builder: (context) {
                  final savedLocations = ref.watch(savedLocationsProvider);
                  if (savedLocations.isEmpty) return const SizedBox.shrink();

                  IconData iconFor(String id) {
                    if (id == 'home') return Icons.home_outlined;
                    if (id == 'work') return Icons.work_outline;
                    return Icons.location_on_outlined;
                  }

                  return Padding(
                    padding: const EdgeInsets.only(left: 16, right: 16, top: 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: savedLocations.map((loc) {
                        return InkWell(
                          onTap: () => _fetchFromCoords(loc.latitude, loc.longitude),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                            child: Row(
                              children: [
                                Icon(
                                  iconFor(loc.id),
                                  size: 18,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    loc.label,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_forward_ios,
                                  size: 12,
                                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  );
                }),

                // ── Divider + search field ──
                Builder(builder: (context) {
                  final hasSaved = ref.watch(savedLocationsProvider).isNotEmpty;
                  if (!hasSaved) return const SizedBox(height: 10);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        Expanded(child: Divider(color: isDark ? AppColors.dividerDark : AppColors.divider)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            'or search',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: isDark ? AppColors.dividerDark : AppColors.divider)),
                      ],
                    ),
                  );
                }),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GooglePlacesSearchField(
                    autofocus: ref.watch(savedLocationsProvider).isEmpty,
                    onSubmit: (result) => _fetchFromCoords(result.lat, result.lng),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Store card
// ─────────────────────────────────────────────────────────────────────────────

class _StoreCard extends StatefulWidget {
  final RetailerConfig config;
  final NearbyStore? store;
  final bool isSelected;
  final bool isDark;
  final VoidCallback? onTap;
  final VoidCallback? onChangeBranch;

  const _StoreCard({
    required this.config,
    required this.store,
    required this.isSelected,
    required this.isDark,
    this.onTap,
    this.onChangeBranch,
  });

  @override
  State<_StoreCard> createState() => _StoreCardState();
}

class _StoreCardState extends State<_StoreCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final store = widget.store;
    final isDark = widget.isDark;
    final isSelected = widget.isSelected;
    final onTap = widget.onTap;
    final onChangeBranch = widget.onChangeBranch;

    final disabledColor = isDark
        ? AppColors.textDisabledDark
        : AppColors.textDisabled;

    final borderColor = isSelected
        ? config.color
        : (isDark ? AppColors.dividerDark : AppColors.divider);
    final bgColor = isSelected
        ? config.color.withValues(alpha: isDark ? 0.10 : 0.05)
        : (isDark ? AppColors.surfaceDarkMode : Colors.white);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: GestureDetector(
        onTapDown: onTap == null ? null : (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.99 : 1.0,
          duration: const Duration(milliseconds: 80),
          curve: Curves.easeOut,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: borderColor,
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                // Retailer icon — soft tinted tile
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: config.color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(config.icon, color: config.color, size: 18),
                ),

                const SizedBox(width: 12),

                // Store name + branch
                Expanded(
                  child: store == null
                      ? Text(
                          config.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: disabledColor,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    config.name,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: isSelected
                                          ? config.color
                                          : (isDark
                                              ? AppColors.textPrimaryDark
                                              : AppColors.textPrimary),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isSelected) ...[
                                  const SizedBox(width: 6),
                                  Icon(Icons.check_circle_rounded,
                                      size: 13, color: config.color),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              store.storeName,
                              style: TextStyle(
                                fontSize: 12,
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

                // Trailing column: distance + change
                if (store != null) ...[
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _DistanceBadge(
                        distanceKm: store.distanceKm,
                        isDark: isDark,
                      ),
                      if (onChangeBranch != null) ...[
                        const SizedBox(height: 5),
                        _ChangeBranchPill(
                          color: config.color,
                          onTap: onChangeBranch,
                        ),
                      ],
                    ],
                  ),
                ] else ...[
                  Text(
                    'Not found',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: disabledColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Action pill — footer CTA (primary = emerald-filled, secondary = outlined)
// ─────────────────────────────────────────────────────────────────────────────

class _ActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isPrimary;
  final bool isLoading;
  final bool isExpanded;
  final bool isDark;
  final VoidCallback? onTap;

  const _ActionPill({
    required this.icon,
    required this.label,
    required this.isPrimary,
    required this.isDark,
    required this.onTap,
    this.isLoading = false,
    this.isExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isPrimary
        ? AppColors.primary
        : (isDark ? AppColors.surfaceDarkMode : AppColors.surface);
    final fg = isPrimary
        ? Colors.white
        : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimary);
    final borderColor = isPrimary
        ? AppColors.primary
        : (isDark ? AppColors.dividerDark : AppColors.divider);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: fg,
                  ),
                )
              else
                Icon(icon, size: 15, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ),
              if (!isPrimary) ...[
                const SizedBox(width: 3),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 15,
                  color: fg.withValues(alpha: 0.7),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Distance badge (matches BranchPickerSheet's colour-banded chip)
// ─────────────────────────────────────────────────────────────────────────────

class _DistanceBadge extends StatelessWidget {
  final double distanceKm;
  final bool isDark;

  const _DistanceBadge({required this.distanceKm, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? AppColors.backgroundDark : Colors.grey.shade100;
    final fg =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        distanceKm <= 0 ? '—' : '${distanceKm.toStringAsFixed(1)} km',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Change-branch pill button
// ─────────────────────────────────────────────────────────────────────────────

class _ChangeBranchPill extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;

  const _ChangeBranchPill({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.swap_horiz_rounded, size: 12, color: color),
              const SizedBox(width: 3),
              Text(
                'Change',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
