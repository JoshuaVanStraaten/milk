// lib/presentation/widgets/common/address_search_field.dart
//
// Address search field with Nominatim (OpenStreetMap) autocomplete.
// Free, no API key, rate-limited to 1 req/s — fine for interactive typing.
// Results are restricted to South Africa (countrycodes=za).
//
// Suggestions are rendered INLINE (not as an Overlay) so they work
// correctly inside bottom sheets where the keyboard covers overlays.
//
// Fallback: when no Nominatim suggestions match (common for exact SA
// street addresses), pressing Enter uses the platform geocoder (Google
// on Android) via the `geocoding` package as a fallback.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../core/theme/app_colors.dart';
import '../../../data/services/location_service.dart';

/// A text field + inline suggestion list powered by Nominatim.
///
/// [onSubmit] fires when the user taps a suggestion or presses Enter
/// (with platform geocoder fallback), providing the display address
/// and resolved lat/lng.
class AddressSearchField extends StatefulWidget {
  final String hintText;
  final bool autofocus;
  final ValueChanged<({String address, double lat, double lng})> onSubmit;

  const AddressSearchField({
    super.key,
    this.hintText = 'e.g. 42 Main Road, Cape Town',
    this.autofocus = false,
    required this.onSubmit,
  });

  @override
  State<AddressSearchField> createState() => _AddressSearchFieldState();
}

class _AddressSearchFieldState extends State<AddressSearchField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  Timer? _debounce;
  List<_NominatimResult> _suggestions = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (_error != null) setState(() => _error = null);
    if (value.trim().length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(value));
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeQueryComponent(query)}'
        '&countrycodes=za'
        '&format=json'
        '&addressdetails=0'
        '&limit=3',
      );
      final response = await http.get(
        uri,
        headers: {'User-Agent': 'MilkApp/1.0 (grocery price comparison)'},
      ).timeout(const Duration(seconds: 5));

      if (!mounted) return;
      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List;
        setState(() {
          _suggestions = list
              .map((e) =>
                  _NominatimResult.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (_) {
      // Silently ignore — user can still submit manually
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _select(_NominatimResult result) {
    _controller.text = result.displayName;
    setState(() {
      _suggestions = [];
      _error = null;
    });
    _focusNode.unfocus();
    widget.onSubmit((
      address: result.displayName,
      lat: result.lat,
      lng: result.lng,
    ));
  }

  /// Called when the user presses Enter / search on the keyboard.
  /// If suggestions exist, picks the first one.
  /// Otherwise, falls back to the platform geocoder (Google on Android).
  Future<void> _onSubmitted(String value) async {
    if (_suggestions.isNotEmpty) {
      _select(_suggestions.first);
      return;
    }

    final address = value.trim();
    if (address.length < 5) return;

    // Fallback: platform geocoder via geocoding package
    setState(() {
      _loading = true;
      _error = null;
    });

    final coords = await LocationService().geocodeAddress(address);
    if (!mounted) return;

    if (coords == null) {
      setState(() {
        _loading = false;
        _error = 'Address not found. Try a more specific address.';
      });
      return;
    }

    setState(() {
      _loading = false;
      _suggestions = [];
    });
    _focusNode.unfocus();
    widget.onSubmit((address: address, lat: coords.lat, lng: coords.lng));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Search field ──
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: widget.autofocus,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: _onSubmitted,
          decoration: InputDecoration(
            hintText: widget.hintText,
            errorText: _error,
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                  )
                : _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _controller.clear();
                          setState(() {
                            _suggestions = [];
                            _error = null;
                          });
                        },
                      )
                    : null,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),

        // ── Helper text ──
        if (_controller.text.trim().length >= 3 &&
            _suggestions.isEmpty &&
            !_loading &&
            _error == null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Row(
              children: [
                Icon(Icons.keyboard_return,
                    size: 14,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "Don't see your address? Press search to use it anyway.",
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // ── Inline suggestions ──
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDarkMode : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? AppColors.dividerDark : AppColors.divider,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _suggestions.map((s) {
                  return InkWell(
                    onTap: () => _select(s),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              s.displayName,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? AppColors.textPrimaryDark
                                    : AppColors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _NominatimResult {
  final String displayName;
  final double lat;
  final double lng;

  const _NominatimResult({
    required this.displayName,
    required this.lat,
    required this.lng,
  });

  factory _NominatimResult.fromJson(Map<String, dynamic> json) =>
      _NominatimResult(
        displayName: json['display_name'] as String,
        lat: double.parse(json['lat'] as String),
        lng: double.parse(json['lon'] as String),
      );
}
