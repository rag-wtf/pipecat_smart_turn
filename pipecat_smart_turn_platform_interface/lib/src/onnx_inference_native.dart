import 'dart:io';
import 'dart:typed_data';

import 'package:pipecat_smart_turn_platform_interface/src/exceptions.dart';
import 'package:pipecat_smart_turn_platform_interface/src/platform/native/onnxruntime/ort_env.dart';
import 'package:pipecat_smart_turn_platform_interface/src/platform/native/onnxruntime/ort_session.dart';
import 'package:pipecat_smart_turn_platform_interface/src/platform/native/onnxruntime/ort_value.dart';

/// Wraps the ONNX Runtime session for Smart Turn v3.
class SmartTurnOnnxSession {
  OrtSession? _session;
  bool _isInitialized = false;

  /// Initializes the ONNX Runtime environment and session.
  ///
  /// [modelFilePath] must be an absolute path to the .onnx file.
  /// [cpuThreadCount] recommendation is 1 for mobile.
  Future<void> initialize({
    required String modelFilePath,
    int cpuThreadCount = 1,
  }) async {
    if (_isInitialized) return;

    try {
      // Initialize the global ONNX Runtime environment
      // coverage:ignore-start
      OrtEnv.instance.init();

      final sessionOptions = OrtSessionOptions()
        ..setInterOpNumThreads(cpuThreadCount)
        ..setIntraOpNumThreads(cpuThreadCount);

      // Read file into bytes and load from buffer (avoids paths crossing
      // isolate boundaries natively)
      final modelBytes = File(modelFilePath).readAsBytesSync();
      _session = OrtSession.fromBuffer(
        modelBytes,
        sessionOptions,
      );

      sessionOptions.release();
      _isInitialized = true;
      // coverage:ignore-end
    } on Object catch (e) {
      throw SmartTurnModelLoadException('Failed to load ONNX model: $e');
    }
  }

  /// Executes a single forward pass inference.
  ///
  /// [audioSamples] must be exactly 128,000 samples.
  /// Returns raw logits (incompleteLogit, completeLogit).
  Future<(double, double)> run(Float32List audioSamples) async {
    if (!_isInitialized || _session == null) {
      throw const SmartTurnNotInitializedException();
    }

    try {
      // coverage:ignore-start
      final inputShape = [1, 128000];
      final inputTensor = OrtValueTensor.createTensorWithDataList(
        audioSamples,
        inputShape,
      );

      final inputs = {'input': inputTensor};
      final runOptions = OrtRunOptions();

      // Forward pass
      final outputs = _session!.run(runOptions, inputs);

      // Model outputs a single tensor named 'logits' with shape [1, 2]
      final logitsList = outputs[0]?.value as List?;
      if (logitsList == null) {
        throw const SmartTurnInferenceException('Model returned null logits.');
      }
      final logitsRow = logitsList[0] as List;
      final result = (logitsRow[0] as double, logitsRow[1] as double);

      // Cleanup native resources
      inputTensor.release();
      runOptions.release();
      for (final element in outputs) {
        element?.release();
      }

      return result;
    } on Object catch (e) {
      throw SmartTurnInferenceException('ONNX inference failed: $e');
    }
    // coverage:ignore-end
  }

  /// Releases ONNX Runtime session and environment resources.
  void dispose() {
    // coverage:ignore-start
    _session?.release();
    _session = null;
    OrtEnv.instance.release();
    _isInitialized = false;
    // coverage:ignore-end
  }
}
