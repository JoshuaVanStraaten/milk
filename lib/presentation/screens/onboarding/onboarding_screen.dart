import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../providers/province_provider.dart';

/// Onboarding screen for first-launch province selection
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  String? _selectedProvince;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),

              // Header
              _buildHeader(isDark),

              const SizedBox(height: 40),

              // Province selection
              Expanded(child: _buildProvinceList(isDark)),

              const SizedBox(height: 24),

              // Continue button
              _buildContinueButton(isDark),

              const SizedBox(height: 16),

              // Skip option (defaults to Gauteng)
              _buildSkipButton(isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Column(
      children: [
        // App logo/icon
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(
            Icons.location_on,
            size: 40,
            color: AppColors.primary,
          ),
        ),

        const SizedBox(height: 24),

        Text(
          'Select Your Province',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 12),

        Text(
          'We\'ll show you prices and products available in your area',
          style: TextStyle(
            fontSize: 16,
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildProvinceList(bool isDark) {
    return ListView.builder(
      itemCount: AppConstants.allProvinces.length,
      itemBuilder: (context, index) {
        final province = AppConstants.allProvinces[index];
        final info = AppConstants.getProvinceInfo(province);
        final isSelected = _selectedProvince == province;

        return _ProvinceListTile(
          provinceInfo: info,
          isSelected: isSelected,
          isDark: isDark,
          onTap: info.isAvailable
              ? () {
                  setState(() {
                    _selectedProvince = province;
                  });
                }
              : null,
        );
      },
    );
  }

  Widget _buildContinueButton(bool isDark) {
    final canContinue =
        _selectedProvince != null &&
        AppConstants.isProvinceAvailable(_selectedProvince!);

    return ElevatedButton(
      onPressed: canContinue && !_isLoading ? _handleContinue : null,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: isDark ? Colors.grey[800] : Colors.grey[300],
      ),
      child: _isLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : const Text(
              'Continue',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
    );
  }

  Widget _buildSkipButton(bool isDark) {
    return TextButton(
      onPressed: _isLoading ? null : _handleSkip,
      child: Text(
        'Skip (Use Gauteng)',
        style: TextStyle(
          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
        ),
      ),
    );
  }

  Future<void> _handleContinue() async {
    if (_selectedProvince == null) return;

    setState(() => _isLoading = true);

    try {
      final provinceNotifier = ref.read(provinceProvider.notifier);
      await provinceNotifier.setProvince(_selectedProvince!);
      await provinceNotifier.completeOnboarding();

      if (mounted) {
        context.go('/home');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleSkip() async {
    setState(() => _isLoading = true);

    try {
      final provinceNotifier = ref.read(provinceProvider.notifier);
      await provinceNotifier.setProvince(AppConstants.defaultProvince);
      await provinceNotifier.completeOnboarding();

      if (mounted) {
        context.go('/home');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}

/// Individual province list tile widget
class _ProvinceListTile extends StatelessWidget {
  final ProvinceInfo provinceInfo;
  final bool isSelected;
  final bool isDark;
  final VoidCallback? onTap;

  const _ProvinceListTile({
    required this.provinceInfo,
    required this.isSelected,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isAvailable = provinceInfo.isAvailable;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withOpacity(0.1)
                  : (isDark ? AppColors.surfaceDarkMode : AppColors.surface),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? AppColors.primary
                    : (isDark ? AppColors.dividerDark : AppColors.divider),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                // Province icon
                Text(
                  provinceInfo.icon,
                  style: TextStyle(
                    fontSize: 24,
                    color: isAvailable ? null : Colors.grey,
                  ),
                ),

                const SizedBox(width: 16),

                // Province name
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        provinceInfo.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isAvailable
                              ? (isDark
                                    ? AppColors.textPrimaryDark
                                    : AppColors.textPrimary)
                              : (isDark ? Colors.grey[600] : Colors.grey[400]),
                        ),
                      ),
                      if (!isAvailable) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.secondary.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Coming Soon',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.secondary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Selection indicator
                if (isSelected)
                  const Icon(
                    Icons.check_circle,
                    color: AppColors.primary,
                    size: 24,
                  )
                else if (isAvailable)
                  Icon(
                    Icons.circle_outlined,
                    color: isDark ? Colors.grey[600] : Colors.grey[400],
                    size: 24,
                  )
                else
                  Icon(
                    Icons.lock_outline,
                    color: isDark ? Colors.grey[700] : Colors.grey[300],
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
