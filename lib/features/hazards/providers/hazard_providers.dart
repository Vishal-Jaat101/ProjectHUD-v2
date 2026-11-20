/// Riverpod providers for the hazard consensus system.
///
/// Consensus verification rule:
///   - 5 independent confirmations needed for broadcast.
///   - Alerts rider ~300m before hazard.
///   - "Still there?" prompts at ~100m.

import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/constants/app_constants.dart';
import '../../../app/providers/app_providers.dart';
import '../../../models/hazard_models.dart';
import '../../../services/firestore_service.dart';

final firestoreServiceProvider = Provider<FirestoreService>((ref) {
  return FirestoreService();
});

/// List of seeded hazards for demo / offline operation
final seededHazardsProvider = StateProvider<List<HazardReport>>((ref) {
  return [
    HazardReport(
      id: 'HAZ_001_POTHOLE',
      type: HazardType.pothole,
      latitude: 26.8610,
      longitude: 75.7890,
      reportedAt: DateTime.now().subtract(const Duration(hours: 2)),
      reportedBy: 'rider_anon_912',
      confirmations: 6, // Verified (>= 5)
      denials: 0,
      isVerified: true,
    ),
    HazardReport(
      id: 'HAZ_002_ACCIDENT',
      type: HazardType.accident,
      latitude: 26.8680,
      longitude: 75.7760,
      reportedAt: DateTime.now().subtract(const Duration(minutes: 40)),
      reportedBy: 'rider_anon_431',
      confirmations: 5, // Verified (>= 5)
      denials: 1,
      isVerified: true,
    ),
    HazardReport(
      id: 'HAZ_003_SPEED_BREAKER',
      type: HazardType.speedBreaker,
      latitude: 26.8550,
      longitude: 75.8020,
      reportedAt: DateTime.now().subtract(const Duration(hours: 5)),
      reportedBy: 'rider_anon_104',
      confirmations: 8, // Verified
      isVerified: true,
    ),
    HazardReport(
      id: 'HAZ_004_WATERLOGGING',
      type: HazardType.waterlogging,
      latitude: 26.8720,
      longitude: 75.7680,
      reportedAt: DateTime.now().subtract(const Duration(minutes: 15)),
      reportedBy: 'rider_anon_772',
      confirmations: 2, // UNVERIFIED (< 5) — will NOT be broadcast yet
      isVerified: false,
    ),
  ];
});

/// All verified hazards currently active
final verifiedHazardsProvider = Provider<List<HazardReport>>((ref) {
  final seeded = ref.watch(seededHazardsProvider);
  return seeded.where((h) => h.isVerified && h.isActive).toList();
});

/// Active hazard alert within ~300m of rider's current position
final activeHazardAlertProvider = Provider<HazardReport?>((ref) {
  final rideState = ref.watch(rideStateProvider);
  final hazards = ref.watch(verifiedHazardsProvider);

  if (rideState.currentLat == 0 && rideState.currentLng == 0) {
    return null;
  }

  for (final hazard in hazards) {
    final dist = _haversineDistance(
      rideState.currentLat,
      rideState.currentLng,
      hazard.latitude,
      hazard.longitude,
    );
    // Alert between 50m and 350m ahead
    if (dist <= AppConstants.hazardWarningDistanceMeters && dist >= 50) {
      return hazard;
    }
  }
  return null;
});

/// "Still there?" verification pending state (rider within 100m)
final hazardConfirmationPendingProvider =
    StateNotifierProvider<HazardConfirmationNotifier, HazardReport?>((ref) {
  return HazardConfirmationNotifier(ref);
});

class HazardConfirmationNotifier extends StateNotifier<HazardReport?> {
  HazardConfirmationNotifier(this._ref) : super(null);

  final Ref _ref;
  final Set<String> _promptedHazardIds = {};

  void checkProximity(double lat, double lng) {
    if (state != null) return; // Already prompting

    final hazards = _ref.read(verifiedHazardsProvider);
    for (final h in hazards) {
      if (_promptedHazardIds.contains(h.id)) continue;

      final dist = _haversineDistance(lat, lng, h.latitude, h.longitude);
      if (dist <= AppConstants.hazardConfirmationRadiusMeters) {
        _promptedHazardIds.add(h.id);
        state = h;
        break;
      }
    }
  }

  void resolve(bool stillThere) {
    if (state != null) {
      final current = state!;
      // Update Firestore when configured
      final firestore = _ref.read(firestoreServiceProvider);
      if (stillThere) {
        firestore.confirmHazard(current.id, 'rider_local');
      } else {
        firestore.denyHazard(current.id, 'rider_local');
      }

      final list = _ref.read(seededHazardsProvider);
      final idx = list.indexWhere((h) => h.id == current.id);
      if (idx != -1) {
        final updated = stillThere
            ? current.copyWith(confirmations: current.confirmations + 1)
            : current.copyWith(denials: current.denials + 1);
        final newList = List<HazardReport>.from(list);
        newList[idx] = updated;
        _ref.read(seededHazardsProvider.notifier).state = newList;
      }
      state = null;
    }
  }

  void setManualPrompt(HazardReport hazard) {
    state = hazard;
  }
}

double _haversineDistance(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * pi / 180.0;
  final dLon = (lon2 - lon1) * pi / 180.0;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180.0) *
          cos(lat2 * pi / 180.0) *
          sin(dLon / 2) *
          sin(dLon / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return r * c;
}
