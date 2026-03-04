import 'dart:typed_data';

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
  Future<(double, double)> run(Float32List audioSamples) async {
    throw UnsupportedError('SmartTurnOnnxSession is not supported on the web.');
  }

  /// Releases ONNX Runtime session and environment resources.
  void dispose() {
    // No-op
  }
}
