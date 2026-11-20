/// App-wide constants for ProjectHUD.
///
/// Safety rule: no interaction requires reading or typing while riding.

import '../../config/api_keys.dart' as keys;

class AppConstants {
  AppConstants._();

  // ── API Keys (read from lib/config/api_keys.dart) ────────────────
  static final String googleMapsApiKey = keys.googleMapsApiKey;
  static final String geminiApiKey = keys.geminiApiKey;

  // ── Navigation ──────────────────────────────────────────────────
  static const double turnWarningDistanceMeters = 500.0;
  static const double turnFinalWarningDistanceMeters = 100.0;
  static const double routeRecalculationThresholdMeters = 50.0;

  // ── Hazard System ───────────────────────────────────────────────
  /// A hazard is broadcast only after this many independent confirmations
  static const int hazardConsensusThreshold = 5;

  /// Distance (meters) before a hazard to trigger warning
  static const double hazardWarningDistanceMeters = 300.0;

  /// Distance within which a rider can confirm/deny a hazard
  static const double hazardConfirmationRadiusMeters = 100.0;

  /// How long a hazard stays active without confirmations (hours)
  static const int hazardExpiryHours = 24;

  // ── HUD Display ─────────────────────────────────────────────────
  /// Maximum elements on HUD at any time
  static const int maxHudElements = 3;

  /// Minimum touch target size in logical pixels (NHTSA / Android guideline)
  static const double minTouchTarget = 64.0;

  /// Maximum glance time in seconds (NHTSA 2-second rule)
  static const double maxGlanceSeconds = 2.0;

  // ── Telemetry (Phase 3) ─────────────────────────────────────────
  /// Harsh braking threshold (m/s² deceleration)
  static const double harshBrakingThreshold = -7.0;

  /// Sudden swerve threshold (°/s lateral acceleration)
  static const double suddenSwerveThreshold = 150.0;

  /// Overspeeding threshold (km/h above speed limit or general)
  static const double overspeedingThresholdKmh = 80.0;

  /// Telemetry batch upload interval (seconds)
  static const int telemetryUploadIntervalSeconds = 60;

  // ── BLE (Phase 2) ───────────────────────────────────────────────
  static const String bleServiceUuid = '00001234-0000-1000-8000-00805f9b34fb';
  static const String bleCharacteristicUuid =
      '00001235-0000-1000-8000-00805f9b34fb';

  // ── Demo Route (Jaipur: JECRC → Poornima) ──────────────────────
  static const double demoStartLat = 26.8528;
  static const double demoStartLng = 75.8084;
  static const double demoEndLat = 26.8764;
  static const double demoEndLng = 75.7640;

  // ── Vehicle Modes ───────────────────────────────────────────────
  static const List<String> vehicleModes = ['Bike', 'Auto-Cab'];

  // ── Languages ───────────────────────────────────────────────────
  static const List<String> supportedLanguages = ['en-IN', 'hi-IN'];
}
