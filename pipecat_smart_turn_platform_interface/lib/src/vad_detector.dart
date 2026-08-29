import 'dart:math' as math;
import 'dart:typed_data';
import 'package:pipecat_smart_turn_platform_interface/src/audio_preprocessor.dart';

/// Represents the state of Voice Activity Detection.
enum VadState {
  /// No speech detected.
  silence,

  /// Signal energy just crossed the speech threshold.
  speechStart,

  /// Ongoing speech detected.
  speech,

  /// Signal energy dropped below threshold after active speech.
  silenceAfterSpeech,

  /// Evaluating if the current silence is long enough to trigger
  /// a semantic turn check (inference).
  evaluatingSilence,
}

/// A lightweight, energy-based Voice Activity Detector.
///
/// Uses dynamic noise floor tracking via Exponential Moving Average (EMA)
/// and a multi-poll mechanism to distinguish between brief gaps and
/// actual silence.
class EnergyVad {
  /// Creates an [EnergyVad] with the given thresholds.
  EnergyVad({
    this.silenceThreshold = 2.0, // multiplier over noise floor
    this.noiseFloorWeight = 0.98,
    this.silenceGraceFrames = 3,
    this.warmupFrames = 0,
    this.initialNoiseFloor = 0.001,
  }) : _noiseFloor = initialNoiseFloor;

  /// The multiplier over noise floor to consider signal as speech.
  final double silenceThreshold;

  /// The weight of the noise floor EMA.
  final double noiseFloorWeight;

  /// The number of silent frames to wait before declaring silence.
  final int silenceGraceFrames;

  /// Number of initial frames used to warm up and seed the noise floor.
  final int warmupFrames;

  /// Initial noise floor seed.
  final double initialNoiseFloor;

  double _noiseFloor;
  int _silenceCounter = 0;
  int _warmupCount = 0;
  bool _isSpeaking = false;

  int _speechFrames = 0;

  /// Current estimated noise floor RMS.
  double get noiseFloor => _noiseFloor;

  /// Processes a new audio frame and returns the detected VAD state.
  VadState process(Float32List frame) {
    final frameRms = AudioPreprocessor.computeRms(frame);

    // Warm-up phase: seed noise floor directly from ambient frames
    if (_warmupCount < warmupFrames) {
      _warmupCount++;
      if (_warmupCount == 1) {
        _noiseFloor = math.max(frameRms, 0.0001);
      } else {
        _noiseFloor = (_noiseFloor * 0.6) + (math.max(frameRms, 0.0001) * 0.4);
      }
      return VadState.silence;
    }

    // Dynamic noise floor adaptation
    if (!_isSpeaking) {
      if (frameRms < _noiseFloor * 1.5) {
        // Fast downward / close-ambient tracking
        _noiseFloor =
            (_noiseFloor * noiseFloorWeight) +
            (frameRms * (1.0 - noiseFloorWeight));
      } else {
        // Upward adaptation for rising ambient noise
        _noiseFloor = (_noiseFloor * 0.98) + (frameRms * 0.02);
      }
    } else {
      // If continuous high energy persists without pauses (e.g. steady
      // room noise rather than speech), slowly adapt the floor upward to
      // avoid permanent lockup.
      _speechFrames++;
      if (_speechFrames > 20) {
        _noiseFloor = (_noiseFloor * 0.98) + (frameRms * 0.02);
      }
    }

    final isHighEnergy = frameRms > (_noiseFloor * silenceThreshold);

    if (isHighEnergy) {
      _silenceCounter = 0;
      if (!_isSpeaking) {
        _isSpeaking = true;
        _speechFrames = 1;
        return VadState.speechStart;
      }
      return VadState.speech;
    } else {
      _speechFrames = 0;
      if (_isSpeaking) {
        _silenceCounter++;
        if (_silenceCounter >= silenceGraceFrames) {
          _isSpeaking = false;
          return VadState.silenceAfterSpeech;
        }
        return VadState.evaluatingSilence;
      }
      return VadState.silence;
    }
  }

  /// Resets internal state (e.g., after a turn is complete).
  /// If [newNoiseFloor] is provided, it replaces the current tracked floor.
  void reset({double? newNoiseFloor}) {
    _silenceCounter = 0;
    _isSpeaking = false;
    _speechFrames = 0;
    if (newNoiseFloor != null) {
      _noiseFloor = newNoiseFloor;
      _warmupCount = warmupFrames;
    } else {
      _warmupCount = 0;
      _noiseFloor = initialNoiseFloor;
    }
  }
}
