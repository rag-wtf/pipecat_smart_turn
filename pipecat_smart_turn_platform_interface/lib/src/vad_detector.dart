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
  });

  /// The multiplier over noise floor to consider signal as speech.
  final double silenceThreshold;

  /// The weight of the noise floor EMA.
  final double noiseFloorWeight;

  /// The number of silent frames to wait before declaring silence.
  final int silenceGraceFrames;

  double _noiseFloor = 0.01; // Initial floor estimate
  int _silenceCounter = 0;
  bool _isSpeaking = false;

  /// Processes a new audio frame and returns the detected VAD state.
  VadState process(Float32List frame) {
    final frameRms = AudioPreprocessor.computeRms(frame);

    // Update noise floor EMA during silence
    if (frameRms < _noiseFloor * 1.5) {
      _noiseFloor =
          (_noiseFloor * noiseFloorWeight) +
          (frameRms * (1.0 - noiseFloorWeight));
    }

    final isHighEnergy = frameRms > (_noiseFloor * silenceThreshold);

    if (isHighEnergy) {
      _silenceCounter = 0;
      if (!_isSpeaking) {
        _isSpeaking = true;
        return VadState.speechStart;
      }
      return VadState.speech;
    } else {
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
  void reset() {
    _silenceCounter = 0;
    _isSpeaking = false;
  }
}
