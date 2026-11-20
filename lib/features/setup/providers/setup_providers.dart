/// Riverpod providers for the setup / home feature.
///
/// Covers vehicle mode selection, language toggle, search state,
/// and recent destinations.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/navigation_models.dart';
import '../../../services/maps_service.dart';

// ── Maps Service ──────────────────────────────────────────────────────

/// Single instance of [MapsService] shared across the app.
final mapsServiceProvider = Provider<MapsService>((ref) {
  final service = MapsService();
  ref.onDispose(service.dispose);
  return service;
});

// ── Vehicle Mode ──────────────────────────────────────────────────────

/// Currently selected vehicle mode (bike or auto-cab).
final vehicleModeProvider = StateProvider<VehicleMode>((ref) {
  return VehicleMode.bike;
});

// ── Language ──────────────────────────────────────────────────────────

/// App UI language. `true` = English, `false` = Hindi.
final isEnglishProvider = StateProvider<bool>((ref) => true);

// ── Search ────────────────────────────────────────────────────────────

/// Raw text the user has typed into the search field.
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Debounced autocomplete results from Places API.
///
/// Re-queries whenever [searchQueryProvider] changes, with a 400 ms
/// debounce to avoid excessive API calls.
final searchResultsProvider =
    FutureProvider.autoDispose<List<PlaceSuggestion>>((ref) async {
  final query = ref.watch(searchQueryProvider);

  if (query.trim().length < 2) return [];

  // Debounce: wait 400 ms after the last keystroke.
  final completer = Completer<void>();
  final timer = Timer(const Duration(milliseconds: 400), completer.complete);
  ref.onDispose(timer.cancel);
  await completer.future;

  // If the query changed during debounce, Riverpod will cancel this future
  // automatically via autoDispose.
  final service = ref.read(mapsServiceProvider);
  return service.autocomplete(query);
});

// ── Recent Destinations ───────────────────────────────────────────────

/// A recent destination entry.
class RecentDestination {
  final String placeId;
  final String name;
  final String address;
  final DateTime visitedAt;

  const RecentDestination({
    required this.placeId,
    required this.name,
    required this.address,
    required this.visitedAt,
  });
}

/// Manages the list of recently searched / navigated-to destinations.
class RecentDestinationsNotifier extends StateNotifier<List<RecentDestination>> {
  RecentDestinationsNotifier() : super([]);

  static const _maxRecent = 10;

  void add(RecentDestination destination) {
    // Remove duplicate if exists, then prepend.
    final filtered =
        state.where((d) => d.placeId != destination.placeId).toList();
    state = [destination, ...filtered].take(_maxRecent).toList();
  }

  void clear() {
    state = [];
  }
}

final recentDestinationsProvider = StateNotifierProvider<
    RecentDestinationsNotifier, List<RecentDestination>>((ref) {
  return RecentDestinationsNotifier();
});

// ── Selected Destination for Real Navigation ─────────────────────────

class SelectedDestination {
  final String placeId;
  final String name;
  final String address;
  final double lat;
  final double lng;

  const SelectedDestination({
    required this.placeId,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
  });
}

final selectedDestinationProvider =
    StateProvider<SelectedDestination?>((ref) => null);
