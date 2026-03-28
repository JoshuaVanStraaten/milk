import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import 'package:go_router/go_router.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/saved_location.dart';
import '../../../data/models/vehicle_config.dart';
import '../../providers/auth_provider.dart';
import '../../routes/app_router.dart';
import '../../providers/vehicle_config_provider.dart';
import '../../widgets/common/address_search_field.dart';
import '../../widgets/common/vehicle_config_sheet.dart';
import '../../providers/saved_locations_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/tutorial_provider.dart';
import '../../widgets/tutorial/tutorial_targets.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  TutorialCoachMark? _tutorialCoachMark;
  bool _tutorialTriggered = false;
  final _vehicleCardKey = GlobalKey();

  @override
  void dispose() {
    _tutorialCoachMark?.finish();
    super.dispose();
  }

  void _tryShowProfileTutorial() {
    if (_tutorialTriggered) return;
    final tutorialService = ref.read(tutorialServiceProvider);
    if (tutorialService.isProfileTutorialCompleted) return;
    if (_vehicleCardKey.currentContext == null) return;
    _tutorialTriggered = true;

    // Scroll to vehicle card first, then show tutorial
    Future.delayed(const Duration(milliseconds: 400), () async {
      if (!mounted) return;

      if (!mounted) return;
      final vehicleContext = _vehicleCardKey.currentContext;
      if (vehicleContext != null) {
        await Scrollable.ensureVisible(
          vehicleContext,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          alignment: 0.5,
        );
      }

      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      final targets = buildProfileTutorialTargets(
        vehicleCardKey: _vehicleCardKey,
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
          ref.read(tutorialServiceProvider).completeProfileTutorial();
        },
        onSkip: () {
          ref.read(tutorialServiceProvider).skipAll();
          return true;
        },
      )..show(context: context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final userProfileAsync = ref.watch(currentUserProfileProvider);
    final themeState = ref.watch(themeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    WidgetsBinding.instance.addPostFrameCallback((_) => _tryShowProfileTutorial());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        automaticallyImplyLeading: false,
      ),
      body: userProfileAsync.when(
        data: (profile) {
          if (profile == null) {
            return const Center(child: Text('No profile found'));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                const SizedBox(height: 20),

                // Profile Avatar
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      profile.displayName?.isNotEmpty == true
                          ? profile.displayName![0].toUpperCase()
                          : profile.emailAddress[0].toUpperCase(),
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Display Name
                if (profile.displayName != null)
                  Text(
                    profile.displayName!,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                    ),
                  ),

                const SizedBox(height: 8),

                // Email
                Text(
                  profile.emailAddress,
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                  ),
                ),

                const SizedBox(height: 32),

                // Settings Section Header
                _SectionHeader(title: 'Settings', isDark: isDark),

                const SizedBox(height: 12),

                // Theme Selector
                _ThemeSelector(
                  currentMode: themeState.themeMode,
                  onModeChanged: (mode) {
                    ref.read(themeProvider.notifier).setThemeMode(mode);
                  },
                  isDark: isDark,
                ),

                const SizedBox(height: 12),

                // Replay Tutorial
                InkWell(
                  onTap: () async {
                    await ref.read(tutorialServiceProvider).resetAll();
                    if (context.mounted) context.go('/home');
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.school_outlined,
                            color: AppColors.primary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Replay Tutorial',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? AppColors.textPrimaryDark
                                      : AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'See the app walkthrough again',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? AppColors.textSecondaryDark
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // My Locations Section
                _SectionHeader(title: 'My Locations', isDark: isDark),
                const SizedBox(height: 12),
                _LocationsCard(isDark: isDark),

                const SizedBox(height: 24),

                // My Vehicle Section
                _SectionHeader(title: 'My Vehicle', isDark: isDark),
                const SizedBox(height: 12),
                _VehicleCard(key: _vehicleCardKey, isDark: isDark),

                const SizedBox(height: 24),

                // Premium Section
                _SectionHeader(title: 'Subscription', isDark: isDark),
                const SizedBox(height: 12),
                _PremiumCard(isDark: isDark),

                const SizedBox(height: 24),

                // Account Section Header
                _SectionHeader(title: 'Account', isDark: isDark),

                const SizedBox(height: 12),

                // Profile Info Cards
                _InfoCard(
                  icon: Icons.email_outlined,
                  title: 'Email',
                  subtitle: profile.emailAddress,
                  isDark: isDark,
                ),

                const SizedBox(height: 12),

                _InfoCard(
                  icon: Icons.calendar_today_outlined,
                  title: 'Member Since',
                  subtitle: _formatDate(profile.createdAt),
                  isDark: isDark,
                ),

                if (profile.birthday != null) ...[
                  const SizedBox(height: 12),
                  _InfoCard(
                    icon: Icons.cake_outlined,
                    title: 'Birthday',
                    subtitle: _formatDate(profile.birthday!),
                    isDark: isDark,
                  ),
                ],

                const SizedBox(height: 40),

                // Sign Out Button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final authNotifier = ref.read(
                        authNotifierProvider.notifier,
                      );
                      await authNotifier.signOut();
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign Out'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

/// Section header widget
class _PremiumCard extends StatelessWidget {
  final bool isDark;

  const _PremiumCard({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push(AppRoutes.premium),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.rocket_launch_rounded,
                color: AppColors.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Early Access',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'All features free for a limited time',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final bool isDark;

  const _SectionHeader({required this.title, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Theme selector widget
class _ThemeSelector extends StatelessWidget {
  final AppThemeMode currentMode;
  final Function(AppThemeMode) onModeChanged;
  final bool isDark;

  const _ThemeSelector({
    required this.currentMode,
    required this.onModeChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.palette_outlined,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Appearance',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getModeDescription(currentMode),
                      style: TextStyle(
                        fontSize: 12,
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
          const SizedBox(height: 16),
          // Theme mode buttons
          Row(
            children: [
              _ThemeModeButton(
                icon: Icons.phone_android,
                label: 'System',
                isSelected: currentMode == AppThemeMode.system,
                onTap: () => onModeChanged(AppThemeMode.system),
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _ThemeModeButton(
                icon: Icons.light_mode,
                label: 'Light',
                isSelected: currentMode == AppThemeMode.light,
                onTap: () => onModeChanged(AppThemeMode.light),
                isDark: isDark,
              ),
              const SizedBox(width: 8),
              _ThemeModeButton(
                icon: Icons.dark_mode,
                label: 'Dark',
                isSelected: currentMode == AppThemeMode.dark,
                onTap: () => onModeChanged(AppThemeMode.dark),
                isDark: isDark,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getModeDescription(AppThemeMode mode) {
    return switch (mode) {
      AppThemeMode.system => 'Follows your device settings',
      AppThemeMode.light => 'Always use light theme',
      AppThemeMode.dark => 'Always use dark theme',
    };
  }
}

/// Individual theme mode button
class _ThemeModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isDark;

  const _ThemeModeButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : (isDark ? AppColors.dividerDark : AppColors.divider),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? AppColors.primary
                    : (isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary),
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? AppColors.primary
                      : (isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// My Locations card
class _LocationsCard extends ConsumerWidget {
  final bool isDark;
  const _LocationsCard({required this.isDark});

  IconData _iconFor(String id) {
    if (id == 'home') return Icons.home_outlined;
    if (id == 'work') return Icons.work_outline;
    return Icons.location_on_outlined;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locations = ref.watch(savedLocationsProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          if (locations.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No saved locations yet.',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? AppColors.textSecondaryDark
                      : AppColors.textSecondary,
                ),
              ),
            )
          else
            ...locations.map((loc) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _iconFor(loc.id),
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
                              loc.label,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppColors.textPrimaryDark
                                    : AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              loc.address,
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
                        icon: Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondary,
                        ),
                        onPressed: () =>
                            ref.read(savedLocationsProvider.notifier).delete(loc.id),
                      ),
                    ],
                  ),
                )),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showAddLocationSheet(context, ref, isDark),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add location'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(
                  color: isDark ? AppColors.dividerDark : AppColors.divider,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddLocationSheet(BuildContext context, WidgetRef ref, bool isDark) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.backgroundDark : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AddLocationSheet(isDark: isDark, ref: ref),
    );
  }
}

/// Card showing the user's vehicle configuration for fuel cost estimates.
class _VehicleCard extends ConsumerWidget {
  final bool isDark;
  const _VehicleCard({super.key, required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vehicle = ref.watch(vehicleConfigProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: vehicle == null ? _buildEmptyState(context) : _buildConfigured(context, vehicle),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 80,
          height: 80,
          child: Lottie.asset(
            'assets/animations/car_question.json',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Icon(
              Icons.directions_car_outlined,
              size: 40,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Set up your vehicle to see trip fuel costs',
          style: TextStyle(
            fontSize: 14,
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => showVehicleConfigSheet(context, isDark: isDark),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Configure vehicle'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(
                color: isDark ? AppColors.dividerDark : AppColors.divider,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConfigured(BuildContext context, VehicleConfig vehicle) {
    return InkWell(
      onTap: () => showVehicleConfigSheet(context, isDark: isDark),
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.directions_car,
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
                  vehicle.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                  ),
                ),
                Text(
                  '${vehicle.consumptionPer100km.toStringAsFixed(1)} L/100km · '
                  '${vehicle.fuelTypeLabel} · ${vehicle.regionLabel}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

class _AddLocationSheet extends StatefulWidget {
  final bool isDark;
  final WidgetRef ref;
  const _AddLocationSheet({required this.isDark, required this.ref});

  @override
  State<_AddLocationSheet> createState() => _AddLocationSheetState();
}

class _AddLocationSheetState extends State<_AddLocationSheet> {
  String _selectedId = 'home';
  bool _isCustom = false;
  final TextEditingController _labelController = TextEditingController(text: 'Home');

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  void _onPreset(String id, String label) {
    setState(() {
      _selectedId = id;
      _isCustom = false;
      _labelController.text = label;
    });
  }

  void _onCustom() {
    setState(() {
      _selectedId = const Uuid().v4();
      _isCustom = true;
      _labelController.text = '';
    });
  }

  Future<void> _save({
    required String address,
    required double lat,
    required double lng,
  }) async {
    final label = _labelController.text.trim();
    if (_isCustom && label.isEmpty) return;

    final location = SavedLocation(
      id: _selectedId,
      label: label.isEmpty
          ? _selectedId[0].toUpperCase() + _selectedId.substring(1)
          : label,
      address: address,
      latitude: lat,
      longitude: lng,
    );
    await widget.ref.read(savedLocationsProvider.notifier).addOrUpdate(location);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppColors.textDisabledDark : AppColors.textDisabled,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Add Location',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _PresetButton(
                id: 'home',
                label: 'Home',
                icon: Icons.home_outlined,
                isSelected: _selectedId == 'home',
                isDark: isDark,
                onTap: () => _onPreset('home', 'Home'),
              ),
              const SizedBox(width: 10),
              _PresetButton(
                id: 'work',
                label: 'Work',
                icon: Icons.work_outline,
                isSelected: _selectedId == 'work',
                isDark: isDark,
                onTap: () => _onPreset('work', 'Work'),
              ),
              const SizedBox(width: 10),
              _PresetButton(
                id: 'custom',
                label: 'Other',
                icon: Icons.add_location_alt_outlined,
                isSelected: _isCustom,
                isDark: isDark,
                onTap: _onCustom,
              ),
            ],
          ),
          if (_isCustom) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _labelController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Label',
                hintText: 'e.g. Gym, Mom\'s house, Office',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              ),
            ),
          ],
          const SizedBox(height: 14),
          AddressSearchField(
            autofocus: !_isCustom,
            onSubmit: (result) => _save(
              address: result.address,
              lat: result.lat,
              lng: result.lng,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select a suggestion to save the location.',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PresetButton extends StatelessWidget {
  final String id;
  final String label;
  final IconData icon;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _PresetButton({
    required this.id,
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : (isDark ? AppColors.dividerDark : AppColors.divider),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? AppColors.primary
                    : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondary),
                size: 22,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? AppColors.primary
                      : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Info card widget
class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isDark;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMode : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark
                        ? AppColors.textPrimaryDark
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
