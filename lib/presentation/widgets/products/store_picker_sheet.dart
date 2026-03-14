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
import '../common/address_search_field.dart';

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
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: keyboardHeight > 0 ? keyboardHeight + 12 : (bottomPad > 0 ? bottomPad : 12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Handle (tap to dismiss) ──
              GestureDetector(
                onTap: () => Navigator.pop(context),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
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

              // ── Header ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
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
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            'Tap a store to browse its products',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
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

              const SizedBox(height: 16),

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
                    ),
                  ),
                );
              }),

              const SizedBox(height: 12),

              // ── Refresh location ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Material(
                  color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: _isRefreshing ? null : _refreshLocation,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_isRefreshing)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            )
                          else
                            const Icon(
                              Icons.my_location_rounded,
                              size: 16,
                              color: AppColors.primary,
                            ),
                          const SizedBox(width: 8),
                          Text(
                            _isRefreshing
                                ? 'Updating location...'
                                : 'Update my location',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── Change location toggle ──
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Material(
                  color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () => setState(() {
                      _showAddressField = !_showAddressField;
                    }),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? AppColors.dividerDark : AppColors.divider,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Use a different address',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _showAddressField ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                            size: 16,
                            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
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
                  child: AddressSearchField(
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

class _StoreCard extends StatelessWidget {
  final RetailerConfig config;
  final NearbyStore? store;
  final bool isSelected;
  final bool isDark;
  final VoidCallback? onTap;

  const _StoreCard({
    required this.config,
    required this.store,
    required this.isSelected,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabledColor = isDark
        ? AppColors.textDisabledDark
        : AppColors.textDisabled;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Material(
        color: isSelected
            ? config.colorLight.withValues(alpha: isDark ? 0.15 : 1.0)
            : (isDark ? AppColors.surfaceDarkMode : AppColors.surface),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? config.color
                    : (isDark ? AppColors.dividerDark : AppColors.divider),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                // Retailer icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isSelected ? config.color : config.colorLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Icon(
                      config.icon,
                      color: isSelected ? Colors.white : config.color,
                      size: 20,
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // Store name + branch
                Expanded(
                  child: store != null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              config.name,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? config.color
                                    : (isDark
                                          ? AppColors.textPrimaryDark
                                          : AppColors.textPrimary),
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              store!.storeName,
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
                        )
                      : Text(
                          config.name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: disabledColor,
                          ),
                        ),
                ),

                // Distance + active badge
                if (store != null) ...[
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? config.color.withValues(alpha: 0.12)
                              : (isDark
                                    ? AppColors.backgroundDark
                                    : Colors.grey.shade100),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${store!.distanceKm.toStringAsFixed(1)} km',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? config.color
                                : (isDark
                                      ? AppColors.textSecondaryDark
                                      : AppColors.textSecondary),
                          ),
                        ),
                      ),
                      if (isSelected)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle_rounded,
                                size: 12,
                                color: config.color,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                'Active',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: config.color,
                                ),
                              ),
                            ],
                          ),
                        ),
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
