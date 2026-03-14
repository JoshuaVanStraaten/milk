import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/saved_location.dart';

const _kSavedLocationsKey = 'saved_locations_json';

class SavedLocationsNotifier extends StateNotifier<List<SavedLocation>> {
  SavedLocationsNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kSavedLocationsKey);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List)
          .map((e) => SavedLocation.fromJson(e as Map<String, dynamic>))
          .toList();
      state = list;
    } catch (_) {
      state = [];
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kSavedLocationsKey,
      jsonEncode(state.map((l) => l.toJson()).toList()),
    );
  }

  Future<void> addOrUpdate(SavedLocation location) async {
    final idx = state.indexWhere((l) => l.id == location.id);
    if (idx >= 0) {
      state = [
        for (var i = 0; i < state.length; i++)
          if (i == idx) location else state[i],
      ];
    } else {
      state = [...state, location];
    }
    await _persist();
  }

  Future<void> delete(String id) async {
    state = state.where((l) => l.id != id).toList();
    await _persist();
  }
}

final savedLocationsProvider =
    StateNotifierProvider<SavedLocationsNotifier, List<SavedLocation>>(
  (_) => SavedLocationsNotifier(),
);
