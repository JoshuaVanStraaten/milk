// lib/presentation/widgets/common/google_places_search_field.dart
//
// Address search powered by Google Places (New) via two Supabase Edge Functions:
//   • places-autocomplete — POST on each keystroke (debounced)
//   • places-details      — POST once, when the user picks a suggestion
//
// Uses session tokens so autocomplete + details are billed as one session.
// On quota exhaustion the Edge Function returns 503 "places_quota_exceeded",
// and we silently fall back to the platform geocoder via [LocationService].
//
// The public API matches [AddressSearchField] so this is a drop-in replacement:
//   GooglePlacesSearchField(onSubmit: (r) { /* r.address, r.lat, r.lng */ })

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../core/constants/live_api_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/services/location_service.dart';

class GooglePlacesSearchField extends StatefulWidget {
  final String hintText;
  final bool autofocus;
  final ValueChanged<({String address, double lat, double lng})> onSubmit;

  const GooglePlacesSearchField({
    super.key,
    this.hintText = 'e.g. 42 Main Road, Cape Town',
    this.autofocus = false,
    required this.onSubmit,
  });

  @override
  State<GooglePlacesSearchField> createState() => _GooglePlacesSearchFieldState();
}

class _GooglePlacesSearchFieldState extends State<GooglePlacesSearchField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final _uuid = const Uuid();

  Timer? _debounce;
  List<_PlaceSuggestion> _suggestions = [];
  bool _loading = false;
  String? _error;
  String _sessionToken = '';

  @override
  void initState() {
    super.initState();
    _sessionToken = _uuid.v4();
  }

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
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _autocomplete(value),
    );
  }

  Future<void> _autocomplete(String query) async {
    setState(() => _loading = true);
    try {
      final response = await http
          .post(
            Uri.parse(LiveApiConfig.edgeFunctionUrl('places-autocomplete')),
            headers: LiveApiConfig.headers,
            body: jsonEncode({
              'query': query,
              'sessionToken': _sessionToken,
            }),
          )
          .timeout(const Duration(seconds: 6));

      if (!mounted) return;

      if (response.statusCode == 503) {
        // Quota exhausted — fall back silently. User presses Enter to submit
        // and we'll use the platform geocoder from _onSubmitted.
        setState(() => _suggestions = []);
        return;
      }

      if (response.statusCode != 200) {
        setState(() => _suggestions = []);
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rows = data['suggestions'] as List<dynamic>? ?? const [];
      setState(() {
        _suggestions = rows
            .map((e) => _PlaceSuggestion.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _suggestions = []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(_PlaceSuggestion suggestion) async {
    setState(() {
      _loading = true;
      _error = null;
      _suggestions = [];
    });
    _focusNode.unfocus();
    _controller.text = suggestion.description;

    try {
      final response = await http
          .post(
            Uri.parse(LiveApiConfig.edgeFunctionUrl('places-details')),
            headers: LiveApiConfig.headers,
            body: jsonEncode({
              'placeId': suggestion.placeId,
              'sessionToken': _sessionToken,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (!mounted) return;

      if (response.statusCode == 503) {
        // Quota — fall back to platform geocoder using the description string
        await _fallbackGeocode(suggestion.description);
        return;
      }

      if (response.statusCode != 200) {
        setState(() => _error = 'Could not resolve that address. Try another.');
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) {
        setState(() => _error = 'That address has no coordinates.');
        return;
      }

      widget.onSubmit((
        address: (data['formattedAddress'] as String?) ?? suggestion.description,
        lat: lat,
        lng: lng,
      ));

      // New session for the next search
      _sessionToken = _uuid.v4();
    } catch (_) {
      if (!mounted) return;
      await _fallbackGeocode(suggestion.description);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Called when the user presses Enter with no suggestion picked.
  /// Prefers the first suggestion; otherwise falls back to platform geocoder.
  Future<void> _onSubmitted(String value) async {
    if (_suggestions.isNotEmpty) {
      await _select(_suggestions.first);
      return;
    }

    final address = value.trim();
    if (address.length < 5) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    await _fallbackGeocode(address);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _fallbackGeocode(String address) async {
    final coords = await LocationService().geocodeAddress(address);
    if (!mounted) return;

    if (coords == null) {
      setState(() => _error = 'Address not found. Try a more specific address.');
      return;
    }

    _focusNode.unfocus();
    widget.onSubmit((address: address, lat: coords.lat, lng: coords.lng));
    _sessionToken = _uuid.v4();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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
                          _sessionToken = _uuid.v4();
                        },
                      )
                    : null,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.location_on_outlined,
                              size: 16,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.mainText.isNotEmpty
                                      ? s.mainText
                                      : s.description,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? AppColors.textPrimaryDark
                                        : AppColors.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (s.secondaryText.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    s.secondaryText,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? AppColors.textSecondaryDark
                                          : AppColors.textSecondary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
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

class _PlaceSuggestion {
  final String placeId;
  final String description;
  final String mainText;
  final String secondaryText;

  const _PlaceSuggestion({
    required this.placeId,
    required this.description,
    required this.mainText,
    required this.secondaryText,
  });

  factory _PlaceSuggestion.fromJson(Map<String, dynamic> json) =>
      _PlaceSuggestion(
        placeId: (json['placeId'] as String?) ?? '',
        description: (json['description'] as String?) ?? '',
        mainText: (json['mainText'] as String?) ?? '',
        secondaryText: (json['secondaryText'] as String?) ?? '',
      );
}
