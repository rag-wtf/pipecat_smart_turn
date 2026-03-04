import 'dart:io';
import 'dart:typed_data';

import 'package:pipecat_smart_turn_platform_interface/src/exceptions.dart';
import 'package:pipecat_smart_turn_platform_interface/src/mel_spectrogram.dart';
import 'package:pipecat_smart_turn_platform_interface/src/platform/native/bindings/bindings.dart';
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
  /// [onnxLibraryPath] must be the absolute path to libonnxruntime resolved
  /// in the main isolate via [resolveOnnxLibraryPath]. Ignored on platforms
  /// that use [DynamicLibrary.process()] (iOS, macOS).
  Future<void> initialize({
    required String modelFilePath,
    int cpuThreadCount = 1,
    String? onnxLibraryPath,
  }) async {
    if (_isInitialized) return;

    try {
      // coverage:ignore-start
      // Build the binding from the library path resolved in the main isolate.
      final binding = openOnnxRuntimeBinding(onnxLibraryPath);

      // Initialize (or reuse) the global ONNX Runtime environment.
      OrtEnv.setup(binding).init();

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
      // Compute log-mel spectrogram: shape [1, 80, 800] = 64,000 values.
      final melData = MelSpectrogram.compute(audioSamples);
      final inputShape = [1, MelSpectrogram.kNMels, MelSpectrogram.kNumFrames];
      final inputTensor = OrtValueTensor.createTensorWithDataList(
        melData,
        inputShape,
      );

      final inputs = {'input_features': inputTensor};
      final runOptions = OrtRunOptions();

      // Forward pass
      final outputs = _session!.run(runOptions, inputs);

      // Model outputs a single logit tensor 'logits' of shape [batch, 1].
      final logitsList = outputs[0]?.value as List?;
      if (logitsList == null) {
        throw const SmartTurnInferenceException('Model returned null logits.');
      }
      final logit = (logitsList[0] as List)[0] as double;

      // Return (-logit, logit) so softmax2(-x, x) == sigmoid(x).
      final result = (-logit, logit);

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
    // Only release resources that were actually acquired. If initialize()
    // threw before OrtEnv.setup() was called, _isInitialized is false and
    // OrtEnv._instance is null — calling OrtEnv.instance would crash.
    if (!_isInitialized) return;
    _session?.release();
    _session = null;
    OrtEnv.instance.release();
    _isInitialized = false;
    // coverage:ignore-end
  }
}
