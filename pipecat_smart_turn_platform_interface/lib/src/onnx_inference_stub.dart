import 'dart:typed_data';

/// Resolves ONNX library path (stub implementation returns null).
String? resolveOnnxLibraryPath() => null;

/// Extracts bundled model asset (stub implementation throws UnsupportedError).
Future<String> extractBundledModel() async {
  throw UnsupportedError(
    'extractBundledModel is not supported on this platform.',
  );
}

/// Wraps the ONNX Runtime session for Smart Turn v3.
class SmartTurnOnnxSession {
  /// Initializes the ONNX Runtime environment and session.
  Future<void> initialize({
    required String modelFilePath,
    int cpuThreadCount = 1,
    String? onnxLibraryPath,
  }) async {
    throw UnsupportedError('SmartTurnOnnxSession is not supported on the web.');
  }

  /// Executes a single forward pass inference.
  Future<double> run(Float32List audioSamples) async {
    throw UnsupportedError('SmartTurnOnnxSession is not supported on the web.');
  }

  /// Releases ONNX Runtime session and environment resources.
  void dispose() {
    // No-op
  }
}
