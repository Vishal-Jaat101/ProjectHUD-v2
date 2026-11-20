/// Voice interface service: speech-to-text and text-to-speech.
///
/// Uses [speech_to_text] for STT and [flutter_tts] for TTS.
/// Supports Indian English ('en-IN') and Hindi ('hi-IN').
///
/// All spoken messages follow the 2-second rule: short enough to
/// be understood in one phrase while riding.

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'package:project_hud/models/hazard_models.dart';
import 'package:project_hud/models/navigation_models.dart';

/// Callback fired each time partial / final STT results arrive.
typedef OnSpeechResult = void Function(String text, bool isFinal);

/// Callback fired when the STT session ends (timeout or error).
typedef OnListeningDone = void Function();

class VoiceService {
  VoiceService({
    SpeechToText? stt,
    FlutterTts? tts,
  })  : _stt = stt ?? SpeechToText(),
        _tts = tts ?? FlutterTts();

  final SpeechToText _stt;
  final FlutterTts _tts;

  bool _sttInitialised = false;
  bool _ttsInitialised = false;

  /// Currently active language locale.
  String _language = 'en-IN';

  /// Whether TTS is currently speaking.
  bool get isSpeaking => _isSpeaking;
  bool _isSpeaking = false;

  /// Whether STT is currently listening.
  bool get isListening => _stt.isListening;

  // ── Initialisation ───────────────────────────────────────────────

  /// Initialise both STT and TTS engines. Call once at app startup or
  /// before the first voice interaction.
  Future<bool> initialise({String language = 'en-IN'}) async {
    _language = language;

    try {
      // Speech-to-text
      _sttInitialised = await _stt.initialize(
        onError: (error) {
          // Log but do not crash — STT errors are transient.
        },
        onStatus: (status) {
          // 'listening', 'notListening', 'done'
        },
      );
    } catch (_) {
      _sttInitialised = false;
    }

    try {
      // Text-to-speech
      await _configureTts(language);
      _ttsInitialised = true;
    } catch (_) {
      _ttsInitialised = false;
    }

    return _sttInitialised || _ttsInitialised;
  }

  /// Set the active language. Updates both STT and TTS locales.
  Future<void> setLanguage(String language) async {
    _language = language;
    await _configureTts(language);
  }

  Future<void> _configureTts(String language) async {
    await _tts.setLanguage(language);
    // flutter_tts rate scales differ per platform: on Android and web,
    // 1.0 is normal speed and 0.5 is half speed (a slow-motion effect);
    // on iOS/macOS, ~0.5 is the normal rate. Pick per platform.
    final isApple = defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS;
    await _tts.setSpeechRate(isApple ? 0.52 : 1.0);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _tts.setCompletionHandler(() {
      _isSpeaking = false;
    });
  }

  // ── Speech-to-Text ──────────────────────────────────────────────

  /// Start listening for rider speech.
  ///
  /// [onResult] fires with partial and final transcriptions.
  /// [onDone] fires when the STT session ends naturally.
  Future<void> startListening({
    required OnSpeechResult onResult,
    OnListeningDone? onDone,
  }) async {
    if (!_sttInitialised) {
      final ok = await initialise(language: _language);
      if (!ok) return;
    }

    if (_stt.isListening) return;

    await _stt.listen(
      onResult: (SpeechRecognitionResult result) {
        onResult(
          result.recognizedWords,
          result.finalResult,
        );
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
      localeId: _language,
      cancelOnError: true,
      listenMode: ListenMode.dictation,
      onSoundLevelChange: (_) {
        // Could be used for microphone level animation.
      },
    );

    // Fire onDone when STT stops on its own (timeout / silence).
    if (onDone != null) {
      _stt.statusListener = (String status) {
        if (status == 'done' || status == 'notListening') {
          onDone();
        }
      };
    }
  }

  /// Stop listening immediately.
  Future<void> stopListening() async {
    if (_stt.isListening) {
      await _stt.stop();
    }
  }

  // ── Text-to-Speech ──────────────────────────────────────────────

  /// Speak [text] aloud. Optionally override [language] for this call.
  Future<void> speak(
    String text, {
    String? language,
  }) async {
    if (!_ttsInitialised) {
      await initialise(language: language ?? _language);
    }

    // Switch locale if needed for this utterance.
    if (language != null && language != _language) {
      await _tts.setLanguage(language);
    }

    _isSpeaking = true;
    try {
      await _tts.speak(text);
    } catch (_) {}

    // Restore original locale if we switched.
    if (language != null && language != _language) {
      await _tts.setLanguage(_language);
    }
  }

  /// Stop any ongoing TTS playback.
  Future<void> stopSpeaking() async {
    _isSpeaking = false;
    await _tts.stop();
  }

  // ── Navigation Announcements ────────────────────────────────────

  /// Announce an upcoming turn.
  ///
  /// Example EN: "Turn left in 500 meters"
  /// Example HI: "500 मीटर में बाएँ मुड़ें"
  Future<void> announceTurn(
    NavigationStep step,
    double distanceMeters,
  ) async {
    final dist = _formatDistance(distanceMeters);

    if (_language.startsWith('hi')) {
      final dir = _turnDirectionHi(step.direction);
      await speak('$dist में $dir', language: 'hi-IN');
    } else {
      final dir = _turnDirectionEn(step.direction);
      await speak('$dir in $dist', language: 'en-IN');
    }
  }

  // ── Hazard Announcements ────────────────────────────────────────

  /// Warn the rider about an approaching hazard.
  Future<void> announceHazard(
    HazardType hazardType,
    double distanceMeters,
  ) async {
    final dist = _formatDistance(distanceMeters);

    if (_language.startsWith('hi')) {
      await speak(
        '$dist में ${hazardType.spokenWarningHi}',
        language: 'hi-IN',
      );
    } else {
      await speak(
        '${hazardType.spokenWarningEn} In $dist.',
        language: 'en-IN',
      );
    }
  }

  // ── Risk Zone Announcements (Phase 3) ───────────────────────────

  /// Announce entry into a predictive risk zone.
  ///
  /// [riskLevel] is a normalised 0.0–1.0 score.
  Future<void> announceRiskZone(double riskLevel) async {
    if (riskLevel >= 0.8) {
      if (_language.startsWith('hi')) {
        await speak('खतरनाक ज़ोन। सावधान रहें।', language: 'hi-IN');
      } else {
        await speak('Warning! High accident risk zone ahead. Multiple incidents reported.', language: 'en-IN');
      }
    } else if (riskLevel >= 0.5) {
      if (_language.startsWith('hi')) {
        await speak('ध्यान दें। दुर्घटना-प्रवण क्षेत्र।', language: 'hi-IN');
      } else {
        await speak('Caution. Accident-prone area.', language: 'en-IN');
      }
    }
    // riskLevel < 0.5 — no announcement (don't distract the rider)
  }

  /// Direct spoken alert for custom risk zone warning text
  Future<void> announceRiskMessage(String message) async {
    await speak(message);
  }

  // ── Hazard Confirmation Prompt ──────────────────────────────────

  /// Ask the rider whether a previously reported hazard is still there.
  ///
  /// E.g. "Pothole reported ahead. Still there?"
  Future<void> askStillThere(HazardType hazardType) async {
    if (_language.startsWith('hi')) {
      final label = _hazardLabelHi(hazardType);
      await speak(
        'आगे $label की सूचना है। अभी भी है?',
        language: 'hi-IN',
      );
    } else {
      await speak(
        '${hazardType.label} reported ahead. Still there?',
        language: 'en-IN',
      );
    }
  }

  // ── Cleanup ─────────────────────────────────────────────────────

  /// Release STT and TTS resources.
  Future<void> dispose() async {
    await stopListening();
    await stopSpeaking();
    _stt.cancel();
  }

  // ── Private Helpers ─────────────────────────────────────────────

  String _formatDistance(double meters) {
    if (_language.startsWith('hi')) {
      if (meters >= 1000) {
        return '${(meters / 1000).toStringAsFixed(1)} किलोमीटर';
      }
      return '${meters.round()} मीटर';
    }
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} kilometers';
    }
    return '${meters.round()} meters';
  }

  String _turnDirectionEn(TurnDirection direction) {
    switch (direction) {
      case TurnDirection.left:
        return 'Turn left';
      case TurnDirection.right:
        return 'Turn right';
      case TurnDirection.slightLeft:
        return 'Keep left';
      case TurnDirection.slightRight:
        return 'Keep right';
      case TurnDirection.sharpLeft:
        return 'Sharp left';
      case TurnDirection.sharpRight:
        return 'Sharp right';
      case TurnDirection.uTurn:
        return 'Take a U-turn';
      case TurnDirection.roundabout:
        return 'Enter the roundabout';
      case TurnDirection.arrive:
        return 'You have arrived';
      case TurnDirection.straight:
        return 'Continue straight';
    }
  }

  String _turnDirectionHi(TurnDirection direction) {
    switch (direction) {
      case TurnDirection.left:
        return 'बाएँ मुड़ें';
      case TurnDirection.right:
        return 'दाएँ मुड़ें';
      case TurnDirection.slightLeft:
        return 'बाएँ रहें';
      case TurnDirection.slightRight:
        return 'दाएँ रहें';
      case TurnDirection.sharpLeft:
        return 'तेज़ बाएँ';
      case TurnDirection.sharpRight:
        return 'तेज़ दाएँ';
      case TurnDirection.uTurn:
        return 'यू-टर्न लें';
      case TurnDirection.roundabout:
        return 'गोलचक्कर में जाएँ';
      case TurnDirection.arrive:
        return 'आप पहुँच गए';
      case TurnDirection.straight:
        return 'सीधे चलें';
    }
  }

  String _hazardLabelHi(HazardType type) {
    switch (type) {
      case HazardType.pothole:
        return 'गड्ढा';
      case HazardType.accident:
        return 'दुर्घटना';
      case HazardType.waterlogging:
        return 'जलभराव';
      case HazardType.roadWork:
        return 'सड़क का काम';
      case HazardType.policeCheck:
        return 'पुलिस चेकपॉइंट';
      case HazardType.speedBreaker:
        return 'स्पीड ब्रेकर';
    }
  }
}
