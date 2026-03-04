import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:pipecat_smart_turn_platform_interface/src/exceptions.dart';
import 'package:pipecat_smart_turn_platform_interface/src/onnx_runtime_web.dart';

/// Wraps the ONNX Runtime session for Smart Turn v3 on Web.
class SmartTurnOnnxSession {
  InferenceSession? _session;
  bool _isInitialized = false;

  /// Initializes the ONNX Runtime environment and session.
  ///
  /// [modelFilePath] must be an HTTP URL to the .onnx file (e.g., an asset
  /// path).
  Future<void> initialize({
    required String modelFilePath,
    int cpuThreadCount = 1,
  }) async {
    if (_isInitialized) return;

    try {
      ort.env.wasm.numThreads = cpuThreadCount;
      final sessionOptions = createSessionOptions(executionProviders: ['wasm']);
      _session = await ort.InferenceSession.create(
        modelFilePath.toJS,
        sessionOptions,
      ).toDart;
      _isInitialized = true;
    } on Object catch (e) {
      throw SmartTurnModelLoadException(
        'Failed to load ONNX model via JS interop: $e',
      );
    }
  }

  /// Executes a single forward pass inference.
  Future<(double, double)> run(Float32List audioSamples) async {
    if (!_isInitialized || _session == null) {
      throw const SmartTurnNotInitializedException();
    }

    try {
      final inputShape = [1.toJS, 128000.toJS].toJS;
      final jsData = audioSamples.toJS;
      // Use callAsConstructor because `new ort.Tensor(type, data, dims)` is
      // the correct API for typed-array tensors. `Tensor.create()` is an
      // async image factory and does not accept (type, TypedArray, dims).
      final inputTensor = (ort.Tensor as JSFunction).callAsConstructor<Tensor>(
        'float32'.toJS,
        jsData,
        inputShape,
      );

      final feeds = {'input': inputTensor}.jsify()! as JSObject;

      final outputs = await _session!.run(feeds).toDart;

      // The model outputs a single tensor named 'logits'
      final logitsTensor = outputs['logits'];

      final logitsData = logitsTensor.data.toDart;
      final result = (logitsData[0], logitsData[1]);
      return result;
    } on Object catch (e) {
      throw SmartTurnInferenceException('ONNX Web inference failed: $e');
    }
  }

  /// Releases ONNX Runtime session and environment resources.
  void dispose() {
    _session?.release();
    _session = null;
    _isInitialized = false;
  }
}
