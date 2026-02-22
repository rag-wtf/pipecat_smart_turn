import 'dart:io';
import 'dart:typed_data';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:pipecat_smart_turn_platform_interface/src/exceptions.dart';

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
      OrtEnv.instance.init();

      final sessionOptions = OrtSessionOptions()
        ..setInterOpNumThreads(cpuThreadCount)
        ..setIntraOpNumThreads(cpuThreadCount);

      // Note: XNNPACK is not recommended for int8 quantized models (CPU only)
      // but can be added via sessionOptions.appendXnnpackProvider() if needed.

      _session = OrtSession.fromFile(
        File(modelFilePath),
        sessionOptions,
      );

      sessionOptions.release();
      _isInitialized = true;
    } catch (e) {
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
      final logits = outputs[0]?.value as List<List<double>>?;
      if (logits == null) {
        throw const SmartTurnInferenceException('Model returned null logits.');
      }
      final result = (logits[0][0], logits[0][1]);

      // Cleanup native resources
      inputTensor.release();
      runOptions.release();
      for (final element in outputs) {
        element?.release();
      }

      return result;
    } catch (e) {
      throw SmartTurnInferenceException('ONNX inference failed: $e');
    }
  }

  /// Releases ONNX Runtime session and environment resources.
  void dispose() {
    _session?.release();
    _session = null;
    OrtEnv.instance.release();
    _isInitialized = false;
  }
}
