/// HUDScreen — The core glanceable HUD riding view.
///
/// Design Rules:
///   1. Amber monochrome (#FFB300) for all guidance elements.
///   2. Maximum 3 elements: turn arrow + distance, speed, hazard icon.
///   3. ALL content in the LOWER THIRD of the screen. Upper 2/3 remains empty
///      so the rider's forward view is never blocked.
///   4. 2-second glance rule (NHTSA): large, sunlight-readable typography.
///   5. Screen stays awake continuously.
///   6. Single tap to report hazard (when stopped), voice-first while moving.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../app/constants/app_constants.dart';
import '../../../app/providers/app_providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../models/hazard_models.dart';
import '../../../models/navigation_models.dart';
import '../../hazards/providers/hazard_providers.dart';
import '../../hazards/screens/hazard_report_screen.dart';
import '../../hazards/widgets/still_there_dialog.dart';
import '../../voice/screens/voice_assistant_screen.dart';
import '../../voice/services/voice_service.dart';
import '../providers/hud_providers.dart';
import '../widgets/eta_strip_widget.dart';
import '../widgets/hazard_banner_widget.dart';
import '../widgets/speed_display_widget.dart';
import '../widgets/turn_arrow_widget.dart';

class HUDScreen extends ConsumerStatefulWidget {
  const HUDScreen({super.key});

  @override
  ConsumerState<HUDScreen> createState() => _HUDScreenState();
}

class _HUDScreenState extends ConsumerState<HUDScreen> {
  StreamSubscription<Position>? _positionSubscription;
  final VoiceService _voiceService = VoiceService();
  final Set<int> _announced500m = {};
  final Set<int> _announced100m = {};

  @override
  void initState() {
    super.initState();
    // Keep screen awake for HUD mode
    WakelockPlus.enable();

    // Hide system bars for complete immersive HUD experience
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _voiceService.initialise();
    _startLiveGpsTracking();
  }

  void _startLiveGpsTracking() {
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2, // Every 2 meters
      ),
    ).listen(
      _onGpsUpdate,
      onError: (_) {
        // Handle transient GPS errors silently without interrupting HUD
      },
    );
  }

  void _onGpsUpdate(Position position) {
    if (!mounted) return;

    // 1. Calculate real speed in km/h directly from GPS stream (m/s * 3.6)
    final speedMps = position.speed >= 0 ? position.speed : 0.0;
    final speedKmh = (speedMps * 3.6).clamp(0.0, 180.0);

    // 2. Update rideState position & speed from real GPS
    ref.read(rideStateProvider.notifier).updatePosition(
          lat: position.latitude,
          lng: position.longitude,
          bearing: position.heading,
          speedKmh: speedKmh,
        );

    // 3. Proximity check for hazards ("Still there?" prompt)
    ref.read(hazardConfirmationPendingProvider.notifier).checkProximity(
          position.latitude,
          position.longitude,
        );

    // 4. Update route progress against active Google Directions route
    final route = ref.read(activeRouteProvider);
    final rideState = ref.read(rideStateProvider);
    if (route != null && route.steps.isNotEmpty) {
      final currentIdx =
          rideState.currentStepIndex.clamp(0, route.steps.length - 1);
      final currentStep = route.steps[currentIdx];

      final distToStepEnd = _calculateDistance(
        position.latitude,
        position.longitude,
        currentStep.endLat,
        currentStep.endLng,
      );

      // Voice announcements at 500m & 100m marks
      if (distToStepEnd <= 500 &&
          distToStepEnd > 450 &&
          !_announced500m.contains(currentIdx)) {
        _announced500m.add(currentIdx);
        _voiceService.speak('In 500 metres, ${currentStep.instruction}');
      } else if (distToStepEnd <= 100 &&
          distToStepEnd > 50 &&
          !_announced100m.contains(currentIdx)) {
        _announced100m.add(currentIdx);
        _voiceService.speak(currentStep.instruction);
      }

      // Step completion threshold: within 25m of maneuver point
      if (distToStepEnd <= 25 && currentIdx < route.steps.length - 1) {
        final nextIdx = currentIdx + 1;
        final nextStep = route.steps[nextIdx];
        _voiceService.speak(nextStep.instruction);

        ref.read(rideStateProvider.notifier).updateNavigation(
              stepIndex: nextIdx,
              distanceToNextStep: _calculateDistance(
                position.latitude,
                position.longitude,
                nextStep.endLat,
                nextStep.endLng,
              ),
              remainingDistance: (rideState.remainingDistanceMeters -
                      currentStep.distanceMeters)
                  .clamp(0, double.infinity),
              remainingDuration: (rideState.remainingDurationSeconds -
                      currentStep.durationSeconds)
                  .clamp(0, double.infinity),
              distanceTravelled: rideState.distanceTravelledMeters +
                  currentStep.distanceMeters,
            );
      } else {
        ref.read(rideStateProvider.notifier).updateNavigation(
              stepIndex: currentIdx,
              distanceToNextStep: distToStepEnd,
              remainingDistance: rideState.remainingDistanceMeters,
              remainingDuration: rideState.remainingDurationSeconds,
              distanceTravelled: rideState.distanceTravelledMeters,
            );
      }

      // Final destination arrival check
      final dest = ref.read(hudDestinationProvider);
      if (dest != null) {
        final distToDest = _calculateDistance(
          position.latitude,
          position.longitude,
          dest.lat,
          dest.lng,
        );
        if (distToDest <= 30 && currentIdx >= route.steps.length - 1) {
          _voiceService
              .speak('You have arrived at your destination: ${dest.name}');
          ref.read(rideStateProvider.notifier).endRide();
          if (mounted) {
            context.go('/ride-summary');
          }
        }
      }
    }
  }

  double _calculateDistance(
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

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _voiceService.stopListening();
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  void _openHazardReportSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const HazardReportBottomSheet(),
    );
  }

  void _openVoiceAssistant() {
    showDialog(
      context: context,
      barrierColor: AppColors.overlay,
      builder: (_) => const VoiceAssistantScreen(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rideState = ref.watch(rideStateProvider);
    final hudState = ref.watch(hudStateProvider);
    final activeAlert = ref.watch(activeHazardAlertProvider);
    final isStillTherePending = ref.watch(hazardConfirmationPendingProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // ── Tappable Screen Area ──────────────────────────────────────
          // Single tap on screen opens quick hazard report
          // Long press activates Voice Assistant hands-free fallback
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _openHazardReportSheet,
              onLongPress: _openVoiceAssistant,
              child: const SizedBox.expand(),
            ),
          ),

          // ── UPPER 2/3: Empty for clear visor/windshield view ─────────
          Positioned(
            top: 24,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Minimal exit button (only visible when stationary)
                if (rideState.currentSpeedKmh < 3)
                  InkWell(
                    onTap: () {
                      context.go('/ride-summary');
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.panel.withOpacity(0.8),
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'END RIDE',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox.shrink(),

                // Voice Assistant quick trigger pill
                InkWell(
                  onTap: _openVoiceAssistant,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.panel.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.mic_rounded,
                          color: AppColors.amber,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'HUD ASSISTANT',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.amber,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── LOWER THIRD: Pure Monochrome HUD Guidance Elements ────────
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Hazard Banner Alert (if within 300m of hazard)
                  if (activeAlert != null) ...[
                    HazardBannerWidget(
                      hazard: activeAlert,
                      distanceMeters: AppConstants.hazardWarningDistanceMeters,
                    ),
                    const SizedBox(height: 12),
                  ],

                  // 2. Primary Guidance Row: [Turn Arrow + Distance] & [Speed]
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Next Turn Arrow & Distance (Monochrome Signal Amber)
                      TurnArrowWidget(
                        direction: hudState.currentDirection,
                        distanceMeters: rideState.distanceToNextStepMeters,
                        size: 96,
                      ),

                      // Current GPS Speed (Barlow Semi Condensed 96pt)
                      SpeedDisplayWidget(
                        speedKmh: rideState.currentSpeedKmh,
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // 3. ETA & Remaining Distance Strip
                  ETAStripWidget(
                    remainingDistanceMeters: rideState.remainingDistanceMeters,
                    remainingDurationSeconds: rideState.remainingDurationSeconds,
                  ),
                ],
              ),
            ),
          ),

          // ── "Still There?" Verification Overlay ────────────────────────
          if (isStillTherePending != null)
            Positioned(
              bottom: 180,
              left: 20,
              right: 20,
              child: StillThereDialog(
                hazard: isStillTherePending,
                onConfirmed: () {
                  ref
                      .read(hazardConfirmationPendingProvider.notifier)
                      .resolve(true);
                },
                onDenied: () {
                  ref
                      .read(hazardConfirmationPendingProvider.notifier)
                      .resolve(false);
                },
              ),
            ),
        ],
      ),
    );
  }
}
