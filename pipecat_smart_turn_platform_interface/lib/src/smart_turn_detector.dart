import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:pipecat_smart_turn_platform_interface/src/audio_preprocessor.dart';
import 'package:pipecat_smart_turn_platform_interface/src/exceptions.dart';
import 'package:pipecat_smart_turn_platform_interface/src/math_utils.dart'; // softmax2
import 'package:pipecat_smart_turn_platform_interface/src/onnx_inference.dart'; // SmartTurnOnnxSession
import 'package:pipecat_smart_turn_platform_interface/src/smart_turn_config.dart';
import 'package:pipecat_smart_turn_platform_interface/src/smart_turn_isolate.dart'; // SmartTurnIsolate
import 'package:pipecat_smart_turn_platform_interface/src/smart_turn_result.dart';

/// Orchestrates VAD, audio preprocessing, and ONNX inference
/// to predict whether a user has finished their speaking turn.
class SmartTurnDetector {
  /// Creates a [SmartTurnDetector] with the given [config].
  SmartTurnDetector({SmartTurnConfig? config})
    : config = config ?? const SmartTurnConfig();

  /// The configuration for the detector.
  final SmartTurnConfig config;

  /// Overrides the isolate for testing.
  @visibleForTesting
  SmartTurnIsolate? isolateOverride;

  /// Overrides the session for testing.
  @visibleForTesting
  SmartTurnOnnxSession? sessionOverride;

  SmartTurnIsolate? _inferenceIsolate;
  SmartTurnOnnxSession? _session;
  bool _isInitialized = false;
  bool _isProcessing = false;

  /// Initializes the detector by loading the ONNX model.
  ///
  /// Thrown when [initialize] is called before the model is loaded
  /// or if the model file cannot be loaded.
  Future<void> initialize() async {
    if (_isInitialized) return;

    final modelPath = config.customModelPath;
    if (modelPath == null) {
      throw const SmartTurnModelLoadException(
        'customModelPath is required. Download the ONNX model and provide '
        'its absolute path via SmartTurnConfig.',
      );
    }

    if (config.useIsolate) {
      _inferenceIsolate = isolateOverride ?? SmartTurnIsolate();
      await _inferenceIsolate!.spawn(
        modelFilePath: modelPath,
        cpuThreadCount: config.cpuThreadCount,
      );
    } else {
      _session = sessionOverride ?? SmartTurnOnnxSession();
      await _session!.initialize(
        modelFilePath: modelPath,
        cpuThreadCount: config.cpuThreadCount,
      );
    }

    _isInitialized = true;
  }

  /// Predicts whether the user has completed their speaking turn.
  ///
  /// Returns `null` if the model is currently processing a previous frame
  /// (backpressure handling). Since Smart Turn evaluates the most recent
  /// audio state, dropping intermediate frames during inference is safe.
  ///
  /// [audioSamples] should be Float32 PCM, 16kHz, mono, normalized [-1.0, 1.0].
  /// The preprocessor will left-pad or crop to exactly 128,000 samples.
  Future<SmartTurnResult?> predict(Float32List audioSamples) async {
    if (!_isInitialized) throw const SmartTurnNotInitializedException();

    // Backpressure: drop this request if the inference thread is still busy.
    if (_isProcessing) return null;
    _isProcessing = true;

    final stopwatch = Stopwatch()..start();

    try {
      final paddedAudio = AudioPreprocessor.prepareInput(audioSamples);

      final (incompleteLogit, completeLogit) = config.useIsolate
          ? await _inferenceIsolate!.predict(paddedAudio)
          : await _session!.run(paddedAudio);

      final (_, completeProbability) = softmax2(incompleteLogit, completeLogit);

      return SmartTurnResult(
        isComplete: completeProbability >= config.completionThreshold,
        confidence: completeProbability,
        latencyMs: stopwatch.elapsedMilliseconds,
        audioLengthMs: AudioPreprocessor.sampleCountToMs(
          audioSamples.length,
        ).toDouble(),
      );
    } finally {
      _isProcessing = false;
    }
  }

  /// Disposes of the ONNX session or background isolate.
  Future<void> dispose() async {
    _inferenceIsolate?.kill();
    _inferenceIsolate = null;
    _session?.dispose();
    _session = null;
    _isInitialized = false;
  }
}
