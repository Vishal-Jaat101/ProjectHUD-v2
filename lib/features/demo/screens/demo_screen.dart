/// DemoScreen — Simulated ride in Jaipur (JECRC University → Poornima Institute).
///
/// Features:
///   - Route playback with moving position along Jaipur coordinates.
///   - Real-time varying speed (20-48 km/h).
///   - Voice turn announcements (500m & 100m marks).
///   - One crowd-verified hazard alert (Pothole at 40%).
///   - One Phase 3 predictive risk warning (Sitapura High Risk Zone at 70%).
///   - Interactive playback controls: Play/Pause, Fast-Forward Step, Skip to Summary.
///   - Automatic seamless transition to Ride Summary upon arrival.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/constants/app_constants.dart';
import '../../../app/providers/app_providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../models/hazard_models.dart';
import '../../../models/navigation_models.dart';
import '../../hud/widgets/eta_strip_widget.dart';
import '../../hud/widgets/hazard_banner_widget.dart';
import '../../hud/widgets/speed_display_widget.dart';
import '../../hud/widgets/turn_arrow_widget.dart';
import '../providers/demo_providers.dart';

class DemoScreen extends ConsumerStatefulWidget {
  const DemoScreen({super.key});

  @override
  ConsumerState<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends ConsumerState<DemoScreen> {
  bool _hasStarted = false;

  void _startDemo() {
    setState(() => _hasStarted = true);
    final controller = ref.read(demoControllerProvider);
    controller.startSimulation(
      onFinished: () {
        if (mounted) {
          context.go('/ride-summary');
        }
      },
    );
  }

  void _stopAndExit() {
    ref.read(demoControllerProvider).stopSimulation();
    context.pop();
  }

  @override
  void dispose() {
    ref.read(demoControllerProvider).stopSimulation();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = ref.watch(isDemoRunningProvider);
    final isPaused = ref.watch(isDemoPausedProvider);
    final wpIndex = ref.watch(demoCurrentWaypointIndexProvider);
    final voiceSubtitle = ref.watch(demoVoiceSubtitleProvider);
    final currentWp = demoWaypoints[wpIndex];
    final controller = ref.read(demoControllerProvider);

    if (!_hasStarted) {
      return _buildBriefingScreen();
    }

    final progress = (wpIndex + 1) / demoWaypoints.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Top Bar: Simulated Status, Voice Subtitles & Playback Controls ──
            Positioned(
              top: 8,
              left: 16,
              right: 16,
              child: Column(
                children: [
                  // Row: Simulated Badge + Action Controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.panel,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.amber),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.science_outlined,
                              color: AppColors.amber,
                              size: 15,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'SIMULATED RIDE: JECRC → POORNIMA',
                              style: AppTypography.caption.copyWith(
                                color: AppColors.amber,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Play/Pause button
                          IconButton(
                            icon: Icon(
                              isPaused ? Icons.play_arrow : Icons.pause,
                              color: AppColors.amber,
                              size: 22,
                            ),
                            tooltip: isPaused ? 'Resume' : 'Pause',
                            onPressed: controller.togglePause,
                          ),
                          // Fast-Forward Step button
                          IconButton(
                            icon: const Icon(
                              Icons.skip_next,
                              color: AppColors.textPrimary,
                              size: 22,
                            ),
                            tooltip: 'Next Waypoint',
                            onPressed: controller.advanceToNextStep,
                          ),
                          // Close/Exit
                          IconButton(
                            icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 22),
                            onPressed: _stopAndExit,
                          ),
                        ],
                      ),
                    ],
                  ),

                  // Route Progress Bar
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: AppColors.panel,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.amber),
                      minHeight: 6,
                    ),
                  ),

                  // Spoken Voice Subtitle Banner (HUD Assistant live voice readout)
                  if (voiceSubtitle.isNotEmpty && currentWp.riskZoneAlert == null) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.panel.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.amber.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.volume_up_rounded,
                            color: AppColors.amber,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              voiceSubtitle,
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Phase 3 Predictive Alert Banner at Step 6 (70% route mark)
                  if (currentWp.riskZoneAlert != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.danger, width: 1.5),
                      ),
                      child: Row(
                        children: [
                          const _PulsingWarningIcon(),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'PHASE 3 ACCIDENT RISK WARNING',
                                  style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.danger,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  currentWp.riskZoneAlert!,
                                  style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.textPrimary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Center View: Intentionally empty for clear visor/road sightline ──

            // ── Lower Third: Pure HUD Guidance (Arrow, Distance, Speed, ETA) ──
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Hazard alert if active at this waypoint (Pothole at Step 4)
                    if (currentWp.hazardAlert != null) ...[
                      HazardBannerWidget(
                        hazard: HazardReport(
                          id: 'DEMO_HAZ_POTHOLE',
                          type: currentWp.hazardAlert!,
                          latitude: currentWp.lat,
                          longitude: currentWp.lng,
                          reportedAt: DateTime.now(),
                          reportedBy: 'fleet_consensus',
                          confirmations: 6,
                          isVerified: true,
                        ),
                        distanceMeters: 300,
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Primary Guidance Row: Turn Arrow + Distance & Speed
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        TurnArrowWidget(
                          direction: currentWp.direction,
                          distanceMeters: currentWp.distanceToNextTurnMeters,
                          size: 96,
                        ),
                        SpeedDisplayWidget(
                          speedKmh: currentWp.speedKmh,
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // ETA Strip
                    ETAStripWidget(
                      remainingDistanceMeters: currentWp.remainingDistanceMeters,
                      remainingDurationSeconds:
                          currentWp.remainingDistanceMeters / 8.0,
                    ),

                    const SizedBox(height: 10),

                    // Quick Jump to Summary button
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.fast_forward, color: AppColors.textPrimary, size: 16),
                        label: Text(
                          'SKIP TO SUMMARY',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textPrimary,
                            letterSpacing: 0.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: AppColors.panel.withOpacity(0.9),
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                        onPressed: () {
                          controller.skipToEnd();
                          context.go('/ride-summary');
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBriefingScreen() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('DEMO MODE SIMULATION'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.amber),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.science,
                      color: AppColors.amber,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'TABLETOP EVALUATION MODE — SIMULATED GPS & ROUTE PLAYBACK',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.amber,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Route Briefing Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'JAIPUR ROUTE',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.amber,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildRouteLeg(
                      icon: Icons.radio_button_checked,
                      title: 'JECRC University',
                      subtitle: 'Plot No. IS-2036, Ramchandrapura, Sitapura',
                      color: AppColors.amber,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 11),
                      child: Container(
                        width: 2,
                        height: 28,
                        color: AppColors.border,
                      ),
                    ),
                    _buildRouteLeg(
                      icon: Icons.location_on,
                      title: 'Poornima Institute',
                      subtitle: 'ISI-2, RIICO Institutional Area, Sitapura',
                      color: AppColors.verified,
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: AppColors.border),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildStat('DISTANCE', '3.8 km'),
                        _buildStat('EST. TIME', '9 min'),
                        _buildStat('WAYPOINTS', '8 stages'),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Included Demonstration Highlights
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DEMONSTRATION SEQUENCE',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildHighlightItem('Moving GPS position & dynamic speed variations (20 - 48 km/h)'),
                    _buildHighlightItem('Voice turn announcements (at 500m & 100m marks)'),
                    _buildHighlightItem('One verified Pothole hazard warning alert (Tonk Road)'),
                    _buildHighlightItem('One Phase 3 Predictive Accident-Risk Zone warning (Sitapura)'),
                    _buildHighlightItem('Full post-ride summary (Distance, Time, Avg Speed, Phone touches: 0)'),
                  ],
                ),
              ),

              const Spacer(),

              // Start Demo Button (64dp target)
              SizedBox(
                height: 64,
                child: ElevatedButton(
                  onPressed: _startDemo,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.play_arrow_rounded, size: 28),
                      const SizedBox(width: 8),
                      Text(
                        'START DEMO RIDE',
                        style: AppTypography.buttonLarge,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRouteLeg({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTypography.heading3.copyWith(fontSize: 16)),
            Text(subtitle, style: AppTypography.caption),
          ],
        ),
      ],
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.caption),
        Text(
          value,
          style: AppTypography.heading3.copyWith(
            color: AppColors.amber,
            fontSize: 18,
          ),
        ),
      ],
    );
  }

  Widget _buildHighlightItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.verified, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: AppTypography.caption.copyWith(color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}


/// Pulsing warning icon used by the Phase 3 alert banner — draws the eye
/// to the flagship warning without distracting motion elsewhere.
class _PulsingWarningIcon extends StatefulWidget {
  const _PulsingWarningIcon();

  @override
  State<_PulsingWarningIcon> createState() => _PulsingWarningIconState();
}

class _PulsingWarningIconState extends State<_PulsingWarningIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 1.0, end: 1.3).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: const Icon(
        Icons.warning_amber_rounded,
        color: AppColors.danger,
        size: 26,
      ),
    );
  }
}
