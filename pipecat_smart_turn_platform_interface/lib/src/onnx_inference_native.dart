import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'package:pipecat_smart_turn_platform_interface/src/constants.dart';
import 'package:pipecat_smart_turn_platform_interface/src/exceptions.dart';
import 'package:pipecat_smart_turn_platform_interface/src/mel_spectrogram.dart';
import 'package:pipecat_smart_turn_platform_interface/src/platform/native/bindings/bindings.dart'
    as ffi_bindings;
import 'package:pipecat_smart_turn_platform_interface/src/platform/native/onnxruntime/ort_env.dart';
import 'package:pipecat_smart_turn_platform_interface/src/platform/native/onnxruntime/ort_session.dart';
import 'package:pipecat_smart_turn_platform_interface/src/platform/native/onnxruntime/ort_value.dart';

/// Resolves the platform-specific ONNX Runtime dynamic library path.
String? resolveOnnxLibraryPath() => ffi_bindings.resolveOnnxLibraryPath();

/// Extracts the bundled ONNX model asset to the application support directory.
Future<String> extractBundledModel({
  void Function(String message)? logger,
}) async {
  try {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$kDefaultModelFilename');
    final byteData = await rootBundle.load(kDefaultModelAssetPath);
    final expectedLength = byteData.lengthInBytes;

    // Re-extract if file doesn't exist or size does not match asset length.
    if (!file.existsSync() || file.lengthSync() != expectedLength) {
      if (!file.existsSync()) {
        logger?.call('extractBundledModel: model cache miss, extracting');
      } else {
        logger?.call(
          'extractBundledModel: model corrupted or size mismatch, '
          're-extracting',
        );
      }
      final tempFile = File(
        '${dir.path}/$kDefaultModelFilename.${pid}_'
        '${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      try {
        await tempFile.writeAsBytes(
          byteData.buffer.asUint8List(
            byteData.offsetInBytes,
            byteData.lengthInBytes,
          ),
          flush: true,
        );
        await tempFile.rename(file.path);
      } on Object {
        if (tempFile.existsSync()) {
          try {
            await tempFile.delete();
          } on Object {
            // Ignore error during cleanup of temporary file.
          }
        }
        rethrow;
      }
    } else {
      logger?.call(
        'extractBundledModel: model cache hit ($kDefaultModelFilename)',
      );
    }
    return file.path;
  } on Object catch (e) {
    if (e is SmartTurnException) rethrow;
    throw SmartTurnModelLoadException(
      'Failed to extract bundled ONNX model: $e',
    );
  }
}

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
      final binding = ffi_bindings.openOnnxRuntimeBinding(onnxLibraryPath);

      // Initialize (or reuse) the global ONNX Runtime environment.
      OrtEnv.setup(binding).init();

      final sessionOptions = OrtSessionOptions()
        ..setInterOpNumThreads(cpuThreadCount)
        ..setIntraOpNumThreads(cpuThreadCount);

      try {
        // Read file into bytes and load from buffer (avoids paths crossing
        // isolate boundaries natively)
        final modelBytes = File(modelFilePath).readAsBytesSync();
        _session = OrtSession.fromBuffer(
          modelBytes,
          sessionOptions,
        );
      } finally {
        sessionOptions.release();
      }

      _isInitialized = true;
      // coverage:ignore-end
    } on Object catch (e) {
      throw SmartTurnModelLoadException('Failed to load ONNX model: $e');
    }
  }

  /// Executes a single forward pass inference.
  ///
  /// [audioSamples] must be exactly 128,000 samples.
  /// Returns turn completion probability in range [0.0, 1.0].
  Future<double> run(Float32List audioSamples) async {
    if (!_isInitialized || _session == null) {
      throw const SmartTurnNotInitializedException();
    }

    // coverage:ignore-start
    OrtValueTensor? inputTensor;
    OrtRunOptions? runOptions;
    List<OrtValue?>? outputs;

    try {
      // Compute log-mel spectrogram: shape [1, 80, 800] = 64,000 values.
      final melData = MelSpectrogram.compute(audioSamples);
      final inputShape = [1, MelSpectrogram.kNMels, MelSpectrogram.kNumFrames];
      inputTensor = OrtValueTensor.createTensorWithDataList(
        melData,
        inputShape,
      );

      final inputs = {'input_features': inputTensor};
      runOptions = OrtRunOptions();

      // Forward pass
      outputs = _session!.run(runOptions, inputs);

      // Model outputs a single probability tensor 'logits' of shape [batch, 1].
      final logitsList = outputs[0]?.value as List?;
      if (logitsList == null) {
        throw const SmartTurnInferenceException('Model returned null logits.');
      }
      final probability = (logitsList[0] as List)[0] as double;

      return probability;
    } on Object catch (e) {
      if (e is SmartTurnInferenceException) rethrow;
      throw SmartTurnInferenceException('ONNX inference failed: $e');
    } finally {
      inputTensor?.release();
      runOptions?.release();
      if (outputs != null) {
        for (final element in outputs) {
          element?.release();
        }
      }
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
