import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pipecat_smart_turn_platform_interface/src/audio_preprocessor.dart';
import 'package:pipecat_smart_turn_platform_interface/src/exceptions.dart';
import 'package:pipecat_smart_turn_platform_interface/src/onnx_inference.dart'; // SmartTurnOnnxSession, resolveOnnxLibraryPath, extractBundledModel
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
  Future<double>? _nativeInferenceFuture;
  bool _isInitialized = false;
  bool _isProcessing = false;
  Future<void>? _initFuture;

  /// Initializes the detector by loading the ONNX model.
  ///
  /// If `customModelPath` is null in the config, the bundled model will be
  /// extracted to the application support directory and loaded.
  ///
  /// Thrown when the model file cannot be loaded or extracted.
  Future<void> initialize() async {
    if (_isInitialized) return;
    if (_initFuture != null) return _initFuture;

    _initFuture = _doInitialize();
    try {
      await _initFuture;
    } finally {
      _initFuture = null;
    }
  }

  Future<void> _doInitialize() async {
    // Point-of-use validation (works in release mode where asserts are off)
    if (config.completionThreshold < 0.0 || config.completionThreshold > 1.0) {
      throw ArgumentError.value(
        config.completionThreshold,
        'completionThreshold',
        'completionThreshold must be between 0.0 and 1.0',
      );
    }
    if (config.maxAudioSeconds <= 0.0 || config.maxAudioSeconds > 8.0) {
      throw ArgumentError.value(
        config.maxAudioSeconds,
        'maxAudioSeconds',
        'maxAudioSeconds must be between 0.0 and 8.0',
      );
    }
    if (config.cpuThreadCount < 1) {
      throw ArgumentError.value(
        config.cpuThreadCount,
        'cpuThreadCount',
        'cpuThreadCount must be at least 1',
      );
    }
    if (config.inferenceTimeoutMs <= 0) {
      throw ArgumentError.value(
        config.inferenceTimeoutMs,
        'inferenceTimeoutMs',
        'inferenceTimeoutMs must be positive',
      );
    }

    var modelPath = config.customModelPath ?? '';

    if (modelPath.isEmpty) {
      config.logger?.call(
        'SmartTurnDetector: resolving bundled ONNX model',
      );
      try {
        modelPath = await extractBundledModel(logger: config.logger);
      } on Object catch (e) {
        // coverage:ignore-start
        throw SmartTurnModelLoadException(
          'Failed to extract bundled ONNX model from assets. '
          'Verify the asset exists in pubspec.yaml or provide '
          'a customModelPath. Error: $e',
        );
        // coverage:ignore-end
      }
    }

    // Resolve the native library path here, in the main isolate, where
    // Platform.resolvedExecutable correctly points to the app bundle.
    // This is then passed into session/isolate so compute() workers get it.
    final onnxLibraryPath = resolveOnnxLibraryPath();
    if (onnxLibraryPath == null && !kIsWeb) {
      config.logger?.call(
        'SmartTurnDetector: native ONNX library path unresolved; '
        'falling back to system dynamic linker search',
      );
    }
    config.logger?.call(
      'SmartTurnDetector: initializing session with model=$modelPath, '
      'useIsolate=${config.useIsolate}, threads=${config.cpuThreadCount}, '
      'libPath=$onnxLibraryPath',
    );

    if (config.useIsolate) {
      _inferenceIsolate =
          isolateOverride ?? SmartTurnIsolate(logger: config.logger);
      await _inferenceIsolate!.spawn(
        modelFilePath: modelPath,
        cpuThreadCount: config.cpuThreadCount,
        onnxLibraryPath: onnxLibraryPath,
      );
    } else {
      _session = sessionOverride ?? SmartTurnOnnxSession();
      await _session!.initialize(
        modelFilePath: modelPath,
        cpuThreadCount: config.cpuThreadCount,
        onnxLibraryPath: onnxLibraryPath,
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
    if (_isProcessing) {
      config.logger?.call(
        'SmartTurnDetector: backpressure drop - inference thread busy',
      );
      return null;
    }
    _isProcessing = true;

    final stopwatch = Stopwatch()..start();

    try {
      final paddedAudio = AudioPreprocessor.prepareInput(audioSamples);

      final completeProbability = config.useIsolate
          ? await _inferenceIsolate!.predict(
              paddedAudio,
              timeoutMs: config.inferenceTimeoutMs,
            )
          : await _runNativeWithTimeout(paddedAudio);

      final latency = stopwatch.elapsedMilliseconds;
      config.logger?.call(
        'SmartTurnDetector: prediction complete in ${latency}ms '
        '(prob: ${completeProbability.toStringAsFixed(3)})',
      );

      return SmartTurnResult(
        isComplete: completeProbability >= config.completionThreshold,
        confidence: completeProbability,
        latencyMs: latency,
        audioLengthMs: AudioPreprocessor.sampleCountToMs(
          audioSamples.length,
        ).toDouble(),
      );
    } finally {
      _isProcessing = false;
    }
  }

  Future<double> _runNativeWithTimeout(Float32List audio) async {
    final nativeFuture = _session!.run(audio);
    _nativeInferenceFuture = nativeFuture;
    unawaited(
      nativeFuture
          .whenComplete(() {
            if (_nativeInferenceFuture == nativeFuture) {
              _nativeInferenceFuture = null;
            }
          })
          .catchError((_) => 0.0),
    );
    return nativeFuture.timeout(
      Duration(milliseconds: config.inferenceTimeoutMs),
      onTimeout: () => throw const SmartTurnInferenceException(
        'Inference timed out',
      ),
    );
  }

  /// Disposes of the ONNX session or background isolate.
  Future<void> dispose() async {
    _isInitialized = false; // Prevent new predictions

    // Await the actual native FFI future if one is in progress.
    // Dart's .timeout() does not cancel the underlying synchronous
    // FFI call, so we must wait for it to complete before releasing
    // the native OrtSession to avoid a segfault.
    final pendingNative = _nativeInferenceFuture;
    if (pendingNative != null) {
      try {
        await pendingNative;
      } on Object catch (_) {
        // Ignore — we only need the FFI call to finish.
      }
    }

    // Wait for any ongoing predict() frame to finish Dart work.
    while (_isProcessing) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    await _inferenceIsolate?.kill();
    _inferenceIsolate = null;
    _session?.dispose();
    _session = null;
    config.logger?.call('SmartTurnDetector: disposed');
  }
}
