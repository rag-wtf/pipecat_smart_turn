import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:meta/meta.dart';
import 'package:path_provider/path_provider.dart';
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
  /// If `customModelPath` is null in the config, the bundled model will be
  /// extracted to the application support directory and loaded.
  ///
  /// Thrown when the model file cannot be loaded or extracted.
  Future<void> initialize() async {
    if (_isInitialized) return;

    var modelPath = config.customModelPath ?? '';

    if (modelPath.isEmpty) {
      try {
        final dir = await getApplicationSupportDirectory();
        final file = File('${dir.path}/smart-turn-v3.2-cpu.onnx');
        modelPath = file.path;

        // Extract if it doesn't exist to save I/O over-writes on hot restarts.
        if (!file.existsSync()) {
          final byteData = await rootBundle.load(
            'packages/pipecat_smart_turn_platform_interface/assets/smart-turn-v3.2-cpu.onnx',
          );
          await file.writeAsBytes(
            byteData.buffer.asUint8List(
              byteData.offsetInBytes,
              byteData.lengthInBytes,
            ),
          );
        }
      } catch (e) {
        throw SmartTurnModelLoadException(
          'Failed to extract bundled ONNX model from assets. Verify the asset '
          'exists in pubspec.yaml or provide a customModelPath. Error: $e',
        );
      }
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
