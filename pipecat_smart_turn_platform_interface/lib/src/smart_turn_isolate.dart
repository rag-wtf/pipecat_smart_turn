import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pipecat_smart_turn_platform_interface/src/exceptions.dart';
import 'package:pipecat_smart_turn_platform_interface/src/onnx_inference.dart';

/// Configuration passed to the background compute function.
@visibleForTesting
class IsolateConfig {
  /// Creates an [IsolateConfig].
  IsolateConfig({
    required this.modelFilePath,
    required this.cpuThreadCount,
    required this.audioData,
    this.onnxLibraryPath,
  });

  /// The path to the model file.
  final String modelFilePath;

  /// The number of CPU threads to use.
  final int cpuThreadCount;

  /// The audio data to inference on.
  final Float32List audioData;

  /// The absolute path to the ONNX Runtime shared library.
  ///
  /// Must be resolved in the **main isolate** via `resolveOnnxLibraryPath()`
  /// (from `bindings.dart`) before [compute()] is called, because
  /// `Platform.resolvedExecutable` returns the wrong path inside a spawned
  /// isolate. Null on platforms where path resolution is not needed
  /// (iOS, macOS).
  final String? onnxLibraryPath;
}

/// Executes inference using the ONNX backend.
/// Designed to run in [compute] for background processing.
Future<(double, double)> _runInference(IsolateConfig config) async {
  final session = SmartTurnOnnxSession();
  try {
    await session.initialize(
      modelFilePath: config.modelFilePath,
      cpuThreadCount: config.cpuThreadCount,
      onnxLibraryPath: config.onnxLibraryPath,
    );
    final result = await session.run(config.audioData);
    return result;
  } finally {
    session.dispose();
  }
}

/// Manages ONNX inference dispatch.
///
/// Uses `compute()` to offload processing to a background thread
/// on Native platforms, and the main thread on Web.
class SmartTurnIsolate {
  String? _modelFilePath;
  int _cpuThreadCount = 1;

  /// The library path resolved once in the main isolate.
  String? _onnxLibraryPath;

  /// Initializes the parameters for subsequent inference calls.
  /// No heavy initialization is done here because [compute] spawns statelessly.
  ///
  /// [onnxLibraryPath] must be pre-resolved in the main isolate via
  /// `resolveOnnxLibraryPath()` from `bindings.dart` before calling this
  /// method. Null on platforms that do not need an explicit path (iOS, macOS).
  Future<void> spawn({
    required String modelFilePath,
    int cpuThreadCount = 1,
    String? onnxLibraryPath,
  }) async {
    _modelFilePath = modelFilePath;
    _cpuThreadCount = cpuThreadCount;
    _onnxLibraryPath = onnxLibraryPath;
  }

  /// Sends audio to [compute] for inference and awaits logits.
  Future<(double, double)> predict(Float32List audio) async {
    if (_modelFilePath == null) {
      throw const SmartTurnNotInitializedException();
    }

    try {
      final config = IsolateConfig(
        modelFilePath: _modelFilePath!,
        cpuThreadCount: _cpuThreadCount,
        audioData: audio,
        onnxLibraryPath: _onnxLibraryPath,
      );

      // On Web, this runs on the main thread.
      // On mobile/desktop, this spawns a background isolate.
      return await compute(_runInference, config);
    } on Exception catch (e) {
      throw SmartTurnInferenceException('Inference error: $e');
    }
  }

  /// Kills any background worker.
  void kill() {
    _modelFilePath = null;
  }
}
