// lib/presentation/widgets/products/branch_picker_sheet.dart
//
// Per-retailer branch picker. Entered from the store app-bar pill on the
// Browse tab (or the "Change" button on a StorePickerSheet card).
//
// Magic single-input search:
//   • Empty query  → nearest stores for this retailer (via stores-search RPC)
//   • Typing       → full-text match across store_name + city + address,
//                    proximity-boosted against last known coords
//   • No matches   → "Search by address" option reveals the Places field
//
// Selecting a branch calls StoreSelectionNotifier.selectStoreForRetailer,
// which updates the global StoreSelection without re-calling stores-nearby.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/retailers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/nearby_store.dart';
import '../../providers/store_provider.dart';
import '../common/google_places_search_field.dart';

/// Helper to present the branch picker sheet with consistent styling.
Future<void> showBranchPickerSheet(
  BuildContext context, {
  required RetailerConfig retailer,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => BranchPickerSheet(retailer: retailer),
  );
}

class BranchPickerSheet extends ConsumerStatefulWidget {
  final RetailerConfig retailer;

  const BranchPickerSheet({super.key, required this.retailer});

  @override
  ConsumerState<BranchPickerSheet> createState() => _BranchPickerSheetState();
}

class _BranchPickerSheetState extends ConsumerState<BranchPickerSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  String _query = '';
  Timer? _debounce;
  bool _showAddressField = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _query = value.trim());
    });
  }

  Future<void> _selectStore(NearbyStore store) async {
    HapticFeedback.lightImpact();
    await ref.read(storeSelectionProvider.notifier).selectStoreForRetailer(store);
    if (!mounted) return;

    // If the user is currently browsing this retailer, force the product
    // grid to reload — prices/stock/promos differ per branch and stale
    // data would defeat the whole feature.
    final currentRetailer = ref.read(selectedRetailerProvider);
    if (currentRetailer == widget.retailer.name) {
      ref.read(liveProductsProvider.notifier).loadProducts(
            retailer: widget.retailer.name,
            store: store,
            refresh: true,
          );
    }

    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Now browsing ${store.storeName}'),
        backgroundColor: widget.retailer.color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleAddressResolved(
    ({String address, double lat, double lng}) result,
  ) async {
    // Re-run nearby stores around the chosen address (this updates ALL
    // retailers — consistent with existing "use a different address" flow)
    await ref
        .read(storeSelectionProvider.notifier)
        .fetchNearbyStores(result.lat, result.lng);
    if (!mounted) return;
    setState(() {
      _showAddressField = false;
      _query = '';
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    final lastCoords = ref.read(storeSelectionProvider.notifier).lastCoordinates;
    final currentSelection = ref
        .watch(storeSelectionProvider)
        .maybeWhen(data: (s) => s.forRetailer(widget.retailer.name), orElse: () => null);

    final searchParams = StoreSearchParams(
      retailerSlug: widget.retailer.slug,
      query: _query,
      latitude: lastCoords?['lat'],
      longitude: lastCoords?['lng'],
    );
    final results = ref.watch(storeSearchProvider(searchParams));

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: isDark ? AppColors.backgroundDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BrandedHeader(
              retailer: widget.retailer,
              isDark: isDark,
              onClose: () => Navigator.of(context).pop(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: _SearchInput(
                controller: _controller,
                focusNode: _focusNode,
                retailer: widget.retailer,
                isDark: isDark,
                onChanged: _onQueryChanged,
                onClear: () {
                  _controller.clear();
                  setState(() => _query = '');
                },
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ResultsSection(
                      results: results,
                      query: _query,
                      retailer: widget.retailer,
                      currentStoreCode: currentSelection?.storeCode,
                      isDark: isDark,
                      onTap: _selectStore,
                      onSearchByAddress: () =>
                          setState(() => _showAddressField = true),
                    ),
                    if (_showAddressField) ...[
                      const SizedBox(height: 18),
                      _AddressFieldCard(
                        isDark: isDark,
                        onSubmit: _handleAddressResolved,
                      ),
                    ] else ...[
                      const SizedBox(height: 14),
                      _UseDifferentLocationLink(
                        isDark: isDark,
                        onTap: () => setState(() => _showAddressField = true),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _BrandedHeader extends StatelessWidget {
  final RetailerConfig retailer;
  final bool isDark;
  final VoidCallback onClose;

  const _BrandedHeader({
    required this.retailer,
    required this.isDark,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Drag handle
        GestureDetector(
          onTap: onClose,
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
        // Header row (soft tint, no gradient)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: retailer.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(retailer.icon, color: retailer.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Choose your ${retailer.name}',
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
                      'Pick a specific branch or search by area',
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
                onPressed: onClose,
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
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Search input
// ─────────────────────────────────────────────────────────────────────────────

class _SearchInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final RetailerConfig retailer;
  final bool isDark;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchInput({
    required this.controller,
    required this.focusNode,
    required this.retailer,
    required this.isDark,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: "Search ${retailer.name} stores — try 'Irene Village' or 'Sandton'",
        hintStyle: TextStyle(
          fontSize: 13,
          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
        ),
        prefixIcon: Icon(Icons.search_rounded, color: retailer.color, size: 20),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: onClear,
              ),
        filled: true,
        fillColor: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? AppColors.dividerDark : AppColors.divider,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: retailer.color, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? AppColors.dividerDark : AppColors.divider,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Results section
// ─────────────────────────────────────────────────────────────────────────────

class _ResultsSection extends StatelessWidget {
  final AsyncValue<List<NearbyStore>> results;
  final String query;
  final RetailerConfig retailer;
  final String? currentStoreCode;
  final bool isDark;
  final ValueChanged<NearbyStore> onTap;
  final VoidCallback onSearchByAddress;

  const _ResultsSection({
    required this.results,
    required this.query,
    required this.retailer,
    required this.currentStoreCode,
    required this.isDark,
    required this.onTap,
    required this.onSearchByAddress,
  });

  @override
  Widget build(BuildContext context) {
    return results.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Column(
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 32,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
            ),
            const SizedBox(height: 8),
            Text(
              "Couldn't load stores. Check your connection.",
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      data: (stores) {
        if (stores.isEmpty) {
          return _EmptyResults(
            query: query,
            retailer: retailer,
            isDark: isDark,
            onSearchByAddress: onSearchByAddress,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 6, top: 4, bottom: 8),
              child: Text(
                query.isEmpty ? 'NEAR YOU' : '${stores.length} MATCHES',
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
            ...stores.map((store) => _BranchCard(
                  store: store,
                  retailer: retailer,
                  isCurrent: store.storeCode == currentStoreCode,
                  isDark: isDark,
                  onTap: () => onTap(store),
                )),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Branch card
// ─────────────────────────────────────────────────────────────────────────────

class _BranchCard extends StatefulWidget {
  final NearbyStore store;
  final RetailerConfig retailer;
  final bool isCurrent;
  final bool isDark;
  final VoidCallback onTap;

  const _BranchCard({
    required this.store,
    required this.retailer,
    required this.isCurrent,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_BranchCard> createState() => _BranchCardState();
}

class _BranchCardState extends State<_BranchCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final retailer = widget.retailer;
    final isDark = widget.isDark;
    final isCurrent = widget.isCurrent;

    final borderColor = isCurrent
        ? retailer.color
        : (isDark ? AppColors.dividerDark : AppColors.divider);
    final bgColor = isCurrent
        ? retailer.color.withValues(alpha: isDark ? 0.10 : 0.05)
        : (isDark ? AppColors.surfaceDarkMode : Colors.white);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.99 : 1.0,
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderColor,
              width: isCurrent ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: retailer.color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.storefront_rounded,
                    size: 18, color: retailer.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            store.storeName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isCurrent
                                  ? retailer.color
                                  : (isDark
                                      ? AppColors.textPrimaryDark
                                      : AppColors.textPrimary),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isCurrent) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.check_circle_rounded,
                              size: 13, color: retailer.color),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitleFor(store),
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
              const SizedBox(width: 10),
              _DistanceBadge(distanceKm: store.distanceKm, isDark: isDark),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitleFor(NearbyStore store) {
    // Seed `province` / `city` data is unreliable — many rows have wrong
    // or empty values. Distance is the one field we trust.
    return store.formattedDistance;
  }
}

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
// Empty results
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyResults extends StatelessWidget {
  final String query;
  final RetailerConfig retailer;
  final bool isDark;
  final VoidCallback onSearchByAddress;

  const _EmptyResults({
    required this.query,
    required this.retailer,
    required this.isDark,
    required this.onSearchByAddress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 36,
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
          ),
          const SizedBox(height: 8),
          Text(
            query.isEmpty
                ? "No ${retailer.name} stores found near you"
                : "No ${retailer.name} stores match \"$query\"",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onSearchByAddress,
            icon: Icon(Icons.location_on_outlined,
                size: 16, color: retailer.color),
            label: Text(
              'Search by address instead',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: retailer.color,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: retailer.color, width: 1.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Address field + "use a different location" link
// ─────────────────────────────────────────────────────────────────────────────

class _UseDifferentLocationLink extends StatelessWidget {
  final bool isDark;
  final VoidCallback onTap;

  const _UseDifferentLocationLink({required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.travel_explore_rounded,
              size: 16,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              'Use a different location',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_forward_rounded,
              size: 14,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressFieldCard extends StatelessWidget {
  final bool isDark;
  final ValueChanged<({String address, double lat, double lng})> onSubmit;

  const _AddressFieldCard({required this.isDark, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Search by address',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            "We'll find the nearest stores to that address.",
            style: TextStyle(
              fontSize: 11,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          GooglePlacesSearchField(
            autofocus: true,
            onSubmit: onSubmit,
          ),
        ],
      ),
    );
  }
}
