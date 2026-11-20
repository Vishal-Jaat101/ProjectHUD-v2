/// Cloud Firestore service for ProjectHUD.
///
/// Handles:
///   1. Hazard reporting and consensus verification (threshold of 5).
///   2. Real-time stream of nearby verified hazards.
///   3. Telemetry batch uploading for Phase 3 risk analysis.
///   4. Pre-calculated accident risk zones for the map layer.

import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../app/constants/app_constants.dart';
import '../models/hazard_models.dart';
import '../models/telemetry_models.dart';

class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore})
      : _customDb = firestore;

  final FirebaseFirestore? _customDb;

  /// Whether Firebase is initialized and live Firestore is ready.
  bool get isConfigured => _db != null;

  FirebaseFirestore? get _db {
    if (_customDb != null) return _customDb;
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseFirestore.instance;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  CollectionReference<Map<String, dynamic>>? get _hazardsCol =>
      _db?.collection('hazards');

  CollectionReference<Map<String, dynamic>>? get _telemetryCol =>
      _db?.collection('telemetry_events');

  CollectionReference<Map<String, dynamic>>? get _riskZonesCol =>
      _db?.collection('risk_zones');

  // ── Hazard Consensus System ─────────────────────────────────────────

  /// Report a new hazard at rider's current position.
  Future<String> reportHazard({
    required HazardType type,
    required double lat,
    required double lng,
    required String anonymisedUserId,
  }) async {
    final col = _hazardsCol;
    if (col == null) {
      // Offline/Demo mode fallback ID
      return 'HAZ_LOCAL_${DateTime.now().millisecondsSinceEpoch}';
    }

    try {
      // Check if an existing hazard of the same type is within 50m
      final nearby = await _findExistingNearbyHazard(type, lat, lng);
      if (nearby != null) {
        await confirmHazard(nearby.id, anonymisedUserId);
        return nearby.id;
      }

      final docRef = col.doc();
      final hazard = HazardReport(
        id: docRef.id,
        type: type,
        latitude: lat,
        longitude: lng,
        reportedAt: DateTime.now(),
        reportedBy: anonymisedUserId,
        confirmations: 1,
        denials: 0,
        isVerified: false,
      );

      await docRef.set(hazard.toFirestore());
      return docRef.id;
    } catch (_) {
      return 'HAZ_LOCAL_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  /// Add a confirmation vote to a hazard report.
  Future<void> confirmHazard(String hazardId, String userId) async {
    final col = _hazardsCol;
    final db = _db;
    if (col == null || db == null) return;

    try {
      final docRef = col.doc(hazardId);
      await db.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) return;

        final current = HazardReport.fromFirestore(snapshot.id, snapshot.data()!);
        final updatedConfirmations = current.confirmations + 1;
        final isNowVerified =
            updatedConfirmations >= AppConstants.hazardConsensusThreshold;

        transaction.update(docRef, {
          'confirmations': updatedConfirmations,
          'isVerified': isNowVerified,
          'lastConfirmedAt': DateTime.now().toIso8601String(),
        });
      });
    } catch (_) {}
  }

  /// Rider voted "NO" on "Still there?" flow.
  Future<void> denyHazard(String hazardId, String userId) async {
    final col = _hazardsCol;
    final db = _db;
    if (col == null || db == null) return;

    try {
      final docRef = col.doc(hazardId);
      await db.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) return;

        final current = HazardReport.fromFirestore(snapshot.id, snapshot.data()!);
        final updatedDenials = current.denials + 1;

        transaction.update(docRef, {
          'denials': updatedDenials,
        });
      });
    } catch (_) {}
  }

  /// Find existing hazard within 50 meters
  Future<HazardReport?> _findExistingNearbyHazard(
    HazardType type,
    double lat,
    double lng,
  ) async {
    final col = _hazardsCol;
    if (col == null) return null;

    try {
      const delta = 0.0005;
      final query = await col
          .where('type', isEqualTo: type.name)
          .where('latitude', isGreaterThanOrEqualTo: lat - delta)
          .where('latitude', isLessThanOrEqualTo: lat + delta)
          .limit(5)
          .get();

      for (final doc in query.docs) {
        final hazard = HazardReport.fromFirestore(doc.id, doc.data());
        final distMeters = _haversineDistance(
          lat,
          lng,
          hazard.latitude,
          hazard.longitude,
        );
        if (distMeters <= 50) {
          return hazard;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Stream of verified hazards around a location (radius in km)
  Stream<List<HazardReport>> streamNearbyVerifiedHazards({
    required double lat,
    required double lng,
    double radiusKm = 5.0,
  }) {
    final col = _hazardsCol;
    if (col == null) {
      return Stream.value([]);
    }

    try {
      final latDelta = radiusKm / 111.0;
      final lngDelta = radiusKm / (111.0 * cos(lat * pi / 180.0));

      return col
          .where('latitude', isGreaterThanOrEqualTo: lat - latDelta)
          .where('latitude', isLessThanOrEqualTo: lat + latDelta)
          .snapshots()
          .map((snapshot) {
        return snapshot.docs
            .map((doc) => HazardReport.fromFirestore(doc.id, doc.data()))
            .where((h) =>
                h.isVerified &&
                h.isActive &&
                h.longitude >= lng - lngDelta &&
                h.longitude <= lng + lngDelta)
            .toList();
      });
    } catch (_) {
      return Stream.value([]);
    }
  }

  // ── Phase 3: Telemetry Uploading ────────────────────────────────────

  /// Batch upload anonymised telemetry events to Firestore/BigQuery
  Future<void> uploadTelemetryBatch(List<TelemetryEvent> events) async {
    final col = _telemetryCol;
    final db = _db;
    if (col == null || db == null || events.isEmpty) return;

    try {
      final batch = db.batch();
      for (final event in events) {
        final docRef = col.doc(event.id);
        batch.set(docRef, event.toJson());
      }
      await batch.commit();
    } catch (_) {}
  }

  // ── Phase 3: Pre-computed Risk Zones ────────────────────────────────

  /// Fetch predicted high-risk zones for a region
  Future<List<RoadSegmentRisk>> getRiskZones({
    required double centerLat,
    required double centerLng,
  }) async {
    try {
      final col = _riskZonesCol;
      if (col == null) return _getSeededJaipurRiskZones();
      final snapshot = await col.limit(50).get();
      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.map((doc) {
          final data = doc.data();
          return RoadSegmentRisk(
            segmentId: doc.id,
            latitude: (data['latitude'] as num).toDouble(),
            longitude: (data['longitude'] as num).toDouble(),
            riskScore: (data['risk_score'] as num).toDouble(),
            totalEvents: (data['total_events'] as num).toInt(),
            harshBrakingCount: (data['harsh_braking_count'] as num?)?.toInt() ?? 0,
            swerveCount: (data['swerve_count'] as num?)?.toInt() ?? 0,
            accidentCount: (data['accident_count'] as num?)?.toInt() ?? 0,
            riskLevel: data['risk_level'] as String? ?? 'medium',
          );
        }).toList();
      }
    } catch (_) {
      // Fallback to seeded demo risk zones below
    }
    return _getSeededJaipurRiskZones();
  }

  /// Seeded Jaipur accident risk zones for demo & offline operation
  List<RoadSegmentRisk> _getSeededJaipurRiskZones() {
    return const [
      RoadSegmentRisk(
        segmentId: 'JPR_S01_TONK_ROAD',
        latitude: 26.8580,
        longitude: 75.7950,
        riskScore: 0.88,
        totalEvents: 412,
        harshBrakingCount: 184,
        swerveCount: 112,
        accidentCount: 18,
        riskLevel: 'critical',
        peakHours: [20, 21, 22, 23],
      ),
      RoadSegmentRisk(
        segmentId: 'JPR_S02_SANGANER_CROSSING',
        latitude: 26.8640,
        longitude: 75.7820,
        riskScore: 0.74,
        totalEvents: 289,
        harshBrakingCount: 130,
        swerveCount: 88,
        accidentCount: 9,
        riskLevel: 'high',
        peakHours: [18, 19, 20],
      ),
      RoadSegmentRisk(
        segmentId: 'JPR_S03_POORNIMA_APPROACH',
        latitude: 26.8710,
        longitude: 75.7710,
        riskScore: 0.62,
        totalEvents: 145,
        harshBrakingCount: 64,
        swerveCount: 42,
        accidentCount: 4,
        riskLevel: 'medium',
        peakHours: [8, 9, 17, 18],
      ),
      RoadSegmentRisk(
        segmentId: 'JPR_S04_JECRC_GATE',
        latitude: 26.8535,
        longitude: 75.8070,
        riskScore: 0.55,
        totalEvents: 98,
        harshBrakingCount: 45,
        swerveCount: 28,
        accidentCount: 2,
        riskLevel: 'medium',
        peakHours: [16, 17],
      ),
    ];
  }

  /// Calculate distance between two lat/lng coordinates in meters
  static double _haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371000.0; // Earth radius in meters
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
}
