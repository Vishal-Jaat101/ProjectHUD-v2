/// Voice assistant overlay screen.
///
/// Semi-transparent overlay drawn on top of the HUD. Shows a pulsing
/// amber microphone while listening, the rider's transcribed speech,
/// and the assistant's response. Auto-closes after TTS playback.
///
/// Safety: overlay is non-interactive beyond auto-dismiss — the rider
/// never needs to touch the screen.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:project_hud/app/providers/app_providers.dart';
import 'package:project_hud/app/theme/app_theme.dart';
import 'package:project_hud/features/hazards/providers/hazard_providers.dart';
import 'package:project_hud/features/voice/providers/voice_providers.dart';
import 'package:project_hud/features/voice/services/gemini_service.dart';
import 'package:project_hud/features/voice/services/voice_service.dart';
import 'package:project_hud/models/hazard_models.dart';

/// Full-screen voice assistant overlay.
///
/// Usage: push as a full-screen dialog or overlay route:
/// ```dart
/// Navigator.of(context).push(
///   PageRouteBuilder(
///     opaque: false,
///     pageBuilder: (_, __, ___) => const VoiceAssistantScreen(),
///   ),
/// );
/// ```
class VoiceAssistantScreen extends ConsumerStatefulWidget {
  const VoiceAssistantScreen({
    super.key,
    this.rideContext = const RideContext(),
  });

  /// Current ride context for Gemini's situational awareness.
  final RideContext rideContext;

  @override
  ConsumerState<VoiceAssistantScreen> createState() =>
      _VoiceAssistantScreenState();
}

class _VoiceAssistantScreenState extends ConsumerState<VoiceAssistantScreen>
    with SingleTickerProviderStateMixin {
  late final VoiceService _voiceService;
  late final GeminiService _geminiService;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();

    _voiceService = VoiceService();
    _geminiService = GeminiService();

    // Pulsing animation for the microphone icon while listening.
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Kick off listening immediately.
    _startVoiceFlow();
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _pulseController.dispose();
    _voiceService.dispose();
    super.dispose();
  }

  // ── Voice Flow ──────────────────────────────────────────────────

  Future<void> _startVoiceFlow() async {
    final language = ref.read(voiceLanguageProvider);

    await _voiceService.initialise(language: language);

    ref.read(voiceStateProvider.notifier).state = VoiceState.listening;
    ref.read(transcribedTextProvider.notifier).state = '';
    ref.read(assistantResponseProvider.notifier).state = '';

    await _voiceService.startListening(
      onResult: (text, isFinal) {
        ref.read(transcribedTextProvider.notifier).state = text;

        if (isFinal && text.trim().isNotEmpty) {
          _processCommand(text.trim());
        }
      },
      onDone: () {
        // STT timed out without final result — close if nothing captured.
        final captured = ref.read(transcribedTextProvider);
        if (captured.trim().isEmpty) {
          _dismiss();
        } else {
          _processCommand(captured.trim());
        }
      },
    );
  }

  Future<void> _processCommand(String userSpeech) async {
    await _voiceService.stopListening();

    ref.read(voiceStateProvider.notifier).state = VoiceState.processing;

    final rideContext = widget.rideContext.isNavigating
        ? widget.rideContext
        : RideContext(
            language: ref.read(voiceLanguageProvider),
          );

    final response = await _geminiService.processCommand(
      userSpeech,
      rideContext,
    );

    if (!mounted) return;

    _executeAssistantAction(response);

    ref.read(assistantResponseProvider.notifier).state = response.text;
    ref.read(voiceStateProvider.notifier).state = VoiceState.speaking;

    // Speak the response.
    await _voiceService.speak(response.text);

    if (!mounted) return;

    ref.read(voiceStateProvider.notifier).state = VoiceState.idle;

    // Auto-dismiss after the response is spoken.
    _autoDismissTimer = Timer(const Duration(seconds: 2), _dismiss);
  }

  void _executeAssistantAction(AssistantResponse response) {
    if (response.action == AssistantAction.reportHazard) {
      final hazardTypeStr = response.actionData['hazardType'] as String?;
      final hazardType = HazardType.values.firstWhere(
        (h) => h.name.toLowerCase() == hazardTypeStr?.toLowerCase(),
        orElse: () => HazardType.pothole,
      );
      final rideState = ref.read(rideStateProvider);
      final lat = rideState.currentLat != 0 ? rideState.currentLat : 26.8528;
      final lng = rideState.currentLng != 0 ? rideState.currentLng : 75.8084;
      ref.read(firestoreServiceProvider).reportHazard(
        type: hazardType,
        lat: lat,
        lng: lng,
        anonymisedUserId: 'rider_voice_${DateTime.now().millisecondsSinceEpoch}',
      );
      final newHazard = HazardReport(
        id: 'HAZ_${DateTime.now().millisecondsSinceEpoch}',
        type: hazardType,
        latitude: lat,
        longitude: lng,
        reportedAt: DateTime.now(),
        reportedBy: 'rider_voice',
        confirmations: 1,
        denials: 0,
        isVerified: false,
      );
      final list = ref.read(seededHazardsProvider);
      ref.read(seededHazardsProvider.notifier).state = [newHazard, ...list];
    } else if (response.action == AssistantAction.confirmHazard) {
      final confirmed = response.actionData['confirmed'] == true;
      ref.read(hazardConfirmationPendingProvider.notifier).resolve(confirmed);
    } else if (response.action == AssistantAction.stopNavigation) {
      ref.read(rideStateProvider.notifier).endRide();
    }
  }

  void _dismiss() {
    if (!mounted) return;
    ref.read(voiceStateProvider.notifier).state = VoiceState.idle;
    ref.read(transcribedTextProvider.notifier).state = '';
    ref.read(assistantResponseProvider.notifier).state = '';
    Navigator.of(context).maybePop();
  }

  // ── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final voiceState = ref.watch(voiceStateProvider);
    final transcribedText = ref.watch(transcribedTextProvider);
    final assistantResponse = ref.watch(assistantResponseProvider);

    return Scaffold(
      backgroundColor: AppColors.overlay,
      body: SafeArea(
        child: GestureDetector(
          onTap: _dismiss,
          behavior: HitTestBehavior.opaque,
          child: Column(
            children: [
              const Spacer(flex: 2),

              // ── Microphone Icon ──────────────────────────────
              _buildMicrophoneIcon(voiceState),

              const SizedBox(height: 32),

              // ── State Label ──────────────────────────────────
              _buildStateLabel(voiceState),

              const SizedBox(height: 40),

              // ── Transcribed Text ─────────────────────────────
              if (transcribedText.isNotEmpty)
                _buildTranscribedText(transcribedText),

              const SizedBox(height: 24),

              // ── Assistant Response ───────────────────────────
              if (assistantResponse.isNotEmpty)
                _buildAssistantResponse(assistantResponse),

              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }

  // ── Widgets ─────────────────────────────────────────────────────

  Widget _buildMicrophoneIcon(VoiceState state) {
    final bool isActive = state == VoiceState.listening;

    Widget icon = Icon(
      isActive ? Icons.mic : Icons.mic_none,
      size: 72,
      color: AppColors.amber,
    );

    if (isActive) {
      // Pulsing ring + scaling icon while actively listening.
      icon = AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _pulseAnimation.value,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.amber.withOpacity(
                    0.3 + 0.4 * (_pulseAnimation.value - 0.8) / 0.4,
                  ),
                  width: 3,
                ),
              ),
              child: child,
            ),
          );
        },
        child: const Icon(
          Icons.mic,
          size: 72,
          color: AppColors.amber,
        ),
      );
    } else if (state == VoiceState.processing) {
      icon = const SizedBox(
        width: 72,
        height: 72,
        child: CircularProgressIndicator(
          color: AppColors.amber,
          strokeWidth: 3,
        ),
      );
    } else if (state == VoiceState.speaking) {
      icon = const Icon(
        Icons.volume_up_rounded,
        size: 72,
        color: AppColors.amber,
      );
    }

    return Center(child: icon);
  }

  Widget _buildStateLabel(VoiceState state) {
    final String label;
    switch (state) {
      case VoiceState.listening:
        label = 'Listening…';
      case VoiceState.processing:
        label = 'Processing…';
      case VoiceState.speaking:
        label = 'Speaking…';
      case VoiceState.idle:
        label = '';
    }

    if (label.isEmpty) return const SizedBox.shrink();

    return Text(
      label,
      style: AppTypography.heading3.copyWith(
        color: AppColors.textSecondary,
      ),
    );
  }

  Widget _buildTranscribedText(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Text(
        '"$text"',
        textAlign: TextAlign.center,
        style: AppTypography.bodyLarge.copyWith(
          color: AppColors.textPrimary,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _buildAssistantResponse(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppTypography.heading2.copyWith(
          color: AppColors.amber,
        ),
      ),
    );
  }
}

// ── AnimatedBuilder (alias for AnimatedWidget pattern) ─────────────

/// Utility wrapper around [AnimatedWidget] for inline builder pattern.
class AnimatedBuilder extends AnimatedWidget {
  const AnimatedBuilder({
    super.key,
    required Animation<double> animation,
    required this.builder,
    this.child,
  }) : super(listenable: animation);

  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return builder(context, child);
  }
}
