import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:pipecat_smart_turn_platform_interface/src/exceptions.dart';
import 'package:pipecat_smart_turn_platform_interface/src/mel_spectrogram.dart';
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
  ///
  /// [audioSamples] should be exactly 128,000 samples of 16 kHz mono audio.
  /// Internally converts to a Whisper-compatible log-mel spectrogram
  /// [1, 80, 800] before running the ONNX model.
  ///
  /// Returns `(-logit, logit)` so that the caller's `softmax2(-x, x)` gives
  /// `sigmoid(logit)` as the completion probability.
  Future<(double, double)> run(Float32List audioSamples) async {
    if (!_isInitialized || _session == null) {
      throw const SmartTurnNotInitializedException();
    }

    try {
      // Compute log-mel spectrogram: [1, 80, 800] = 64,000 values.
      final melData = MelSpectrogram.compute(audioSamples);

      // Tensor shape: batch=1, n_mels=80, n_frames=800.
      final inputShape = [1.toJS, 80.toJS, 800.toJS].toJS;
      final jsData = melData.toJS;

      // Use callAsConstructor: `new ort.Tensor(type, data, dims)` is the
      // correct API for typed-array tensors.
      final inputTensor = (ort.Tensor as JSFunction).callAsConstructor<Tensor>(
        'float32'.toJS,
        jsData,
        inputShape,
      );

      final feeds = {'input_features': inputTensor}.jsify()! as JSObject;
      final outputs = await _session!.run(feeds).toDart;

      // Model outputs a single logit tensor 'logits' of shape [batch, 1].
      final logitsTensor = outputs['logits'];
      final logit = logitsTensor.data.toDart[0];

      // Return (-logit, logit) so softmax2(-x, x) == sigmoid(x).
      return (-logit, logit);
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
