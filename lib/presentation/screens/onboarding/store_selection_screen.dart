// lib/presentation/screens/onboarding/store_selection_screen.dart
//
// REPLACES the old province-based OnboardingScreen.
// GPS → stores-nearby Edge Function → user picks default retailer → done.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/retailers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/nearby_store.dart';
import '../../../data/services/location_service.dart';
import '../../providers/store_provider.dart';
import '../../widgets/common/google_places_search_field.dart';

class StoreSelectionScreen extends ConsumerStatefulWidget {
  const StoreSelectionScreen({super.key});

  @override
  ConsumerState<StoreSelectionScreen> createState() =>
      _StoreSelectionScreenState();
}

class _StoreSelectionScreenState extends ConsumerState<StoreSelectionScreen> {
  bool _locating = true;
  String? _locationError;
  String? _selectedRetailer;

  // Address input fallback (shown when GPS fails)
  bool _useAddressMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchLocation());
  }

  // TEMPORARY DEBUG VERSION — paste this over the _fetchLocation method
  // in store_selection_screen.dart to find the exact failure point.
  // Remove after diagnosing.

  Future<void> _fetchLocation() async {
    setState(() {
      _locating = true;
      _locationError = null;
    });

    try {
      debugPrint('🔍 [STORE_SETUP] Step 1: Getting location service...');
      final locationService = ref.read(locationServiceProvider);

      debugPrint('🔍 [STORE_SETUP] Step 2: Requesting position...');
      final position = await locationService.getCurrentPosition();

      if (position == null) {
        debugPrint(
          '❌ [STORE_SETUP] Position is null (location disabled or permission denied)',
        );
        setState(() {
          _locating = false;
          _locationError =
              'Could not get your location. Please enable location services and try again.';
        });
        return;
      }

      debugPrint(
        '✅ [STORE_SETUP] Step 3: Got position: ${position.latitude}, ${position.longitude}',
      );
      debugPrint(
        '🔍 [STORE_SETUP] Step 4: Fetching nearby stores from Edge Function...',
      );

      await ref
          .read(storeSelectionProvider.notifier)
          .fetchNearbyStores(position.latitude, position.longitude);

      debugPrint('✅ [STORE_SETUP] Step 5: Stores fetched successfully');
      if (mounted) setState(() => _locating = false);
    } on LocationPermissionDeniedException catch (e) {
      debugPrint('❌ [STORE_SETUP] Permission permanently denied: $e');
      if (mounted) {
        setState(() {
          _locating = false;
          _locationError =
              'Location permission was denied. Please enable it in your device settings to find nearby stores.';
        });
      }
    } on LocationTimeoutException catch (e) {
      debugPrint('❌ [STORE_SETUP] Location timed out: $e');
      if (mounted) {
        setState(() {
          _locating = false;
          _locationError =
              'Location request timed out. Please check your GPS signal and try again.';
        });
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [STORE_SETUP] Unexpected error: $e');
      debugPrint('❌ [STORE_SETUP] Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _locating = false;
          _locationError = 'Something went wrong: $e';
        });
      }
    }
  }

  Future<void> _fetchFromCoords(double lat, double lng) async {
    await ref
        .read(storeSelectionProvider.notifier)
        .fetchNearbyStores(lat, lng);

    if (mounted) {
      setState(() {
        _locating = false;
        _locationError = null;
        _useAddressMode = false;
      });
    }
  }

  void _selectRetailer(String retailer) {
    setState(() => _selectedRetailer = retailer);
  }

  Future<void> _confirmSelection() async {
    if (_selectedRetailer == null) return;

    // Set the selected retailer for the browse tab
    ref.read(selectedRetailerProvider.notifier).state = _selectedRetailer!;

    // Mark store setup as complete (persists to SharedPreferences)
    await ref.read(storeSelectionProvider.notifier).markSetupComplete();

    // Update the hasCompletedStoreSetup flag so the router redirects
    ref.read(hasCompletedStoreSetupProvider.notifier).state = true;

    // Navigate to home
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final storeState = ref.watch(storeSelectionProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),

              // App icon + welcome
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.shopping_basket,
                        color: AppColors.primary,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Welcome to Milk',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Compare grocery prices across South African stores.\nLet\'s find your nearest stores.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 36),

              // Content area — states
              if (_locating)
                _buildLocatingState(isDark)
              else if (_locationError != null)
                _buildErrorState(isDark)
              else
                Expanded(
                  child: storeState.when(
                    data: (selection) => _buildStoreList(selection, isDark),
                    loading: () => _buildLocatingState(isDark),
                    error: (e, _) {
                      // Show error state if store fetch failed
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && _locationError == null) {
                          setState(() {
                            _locationError =
                                'Failed to find nearby stores. Please try again.';
                          });
                        }
                      });
                      return _buildErrorState(isDark);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocatingState(bool isDark) {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Finding stores near you...',
              style: TextStyle(
                fontSize: 16,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(bool isDark) {
    return Expanded(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.location_off,
                size: 56,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondary,
              ),
              const SizedBox(height: 16),
              Text(
                _locationError ?? 'Unknown error',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _fetchLocation,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () async {
                  await Geolocator.openAppSettings();
                },
                child: const Text('Open App Settings'),
              ),

              // Address fallback
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => setState(() {
                  _useAddressMode = !_useAddressMode;
                }),
                icon: Icon(
                  _useAddressMode ? Icons.keyboard_arrow_up : Icons.edit_location_alt_outlined,
                  size: 18,
                ),
                label: Text(
                  _useAddressMode ? 'Hide address input' : "Can't use GPS? Enter an address instead",
                ),
              ),

              if (_useAddressMode) ...[
                const SizedBox(height: 12),
                GooglePlacesSearchField(
                  autofocus: true,
                  onSubmit: (result) => _fetchFromCoords(result.lat, result.lng),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStoreList(StoreSelection selection, bool isDark) {
    if (selection.stores.isEmpty) {
      return _buildErrorState(isDark);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose your store to start',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'We found ${selection.stores.length} stores nearby. Pick one to browse.',
          style: TextStyle(
            fontSize: 13,
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 16),

        // Store cards
        Expanded(
          child: ListView(
            children: Retailers.all.values.map((config) {
              final store = selection.forRetailer(config.name);
              final isSelected = _selectedRetailer == config.name;

              return _StoreSelectionCard(
                config: config,
                store: store,
                isSelected: isSelected,
                isDark: isDark,
                onTap: store != null
                    ? () => _selectRetailer(config.name)
                    : null,
              );
            }).toList(),
          ),
        ),

        // Confirm button
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _selectedRetailer != null ? _confirmSelection : null,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              disabledBackgroundColor: isDark
                  ? AppColors.surfaceDarkModeLight
                  : AppColors.divider,
            ),
            child: Text(
              _selectedRetailer != null
                  ? 'Start shopping at $_selectedRetailer'
                  : 'Select a store to continue',
              style: const TextStyle(fontSize: 15),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// =============================================================================
// STORE CARD WIDGET
// =============================================================================

class _StoreSelectionCard extends StatelessWidget {
  final RetailerConfig config;
  final NearbyStore? store;
  final bool isSelected;
  final bool isDark;
  final VoidCallback? onTap;

  const _StoreSelectionCard({
    required this.config,
    required this.store,
    required this.isSelected,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isAvailable = store != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: isSelected
            ? config.colorLight
            : isDark
            ? AppColors.surfaceDarkMode
            : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? config.color
                    : isDark
                    ? AppColors.dividerDark
                    : AppColors.divider,
                width: isSelected ? 2.5 : 1,
              ),
            ),
            child: Row(
              children: [
                // Retailer icon
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: isSelected ? config.color : config.colorLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Icon(
                      config.icon,
                      color: isSelected ? Colors.white : config.color,
                      size: 26,
                    ),
                  ),
                ),

                const SizedBox(width: 14),

                // Store info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        config.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isAvailable
                              ? (isSelected
                                    ? config.color
                                    : isDark
                                    ? AppColors.textPrimaryDark
                                    : AppColors.textPrimary)
                              : isDark
                              ? AppColors.textDisabledDark
                              : AppColors.textDisabled,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isAvailable
                            ? store!.storeName
                            : 'No store found nearby',
                        style: TextStyle(
                          fontSize: 13,
                          color: isAvailable
                              ? (isDark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondary)
                              : (isDark
                                    ? AppColors.textDisabledDark
                                    : AppColors.textDisabled),
                          fontStyle: isAvailable
                              ? FontStyle.normal
                              : FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),

                // Distance badge + checkmark
                if (isAvailable) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? config.color.withValues(alpha: 0.12)
                              : isDark
                              ? AppColors.surfaceDarkModeLight
                              : AppColors.surfaceDark,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          store!.formattedDistance,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? config.color
                                : isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                      if (isSelected)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Icon(
                            Icons.check_circle,
                            size: 22,
                            color: config.color,
                          ),
                        ),
                    ],
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
