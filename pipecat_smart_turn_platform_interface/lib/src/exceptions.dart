/// Base class for all Smart Turn related exceptions.
sealed class SmartTurnException implements Exception {
  const SmartTurnException(this.message);

  /// A message describing the error.
  final String message;

  @override
  String toString() => 'SmartTurnException: $message';
}

/// Thrown when `predict()` is called before `initialize()`.
final class SmartTurnNotInitializedException extends SmartTurnException {
  /// Creates a [SmartTurnNotInitializedException].
  const SmartTurnNotInitializedException()
    : super('SmartTurnDetector must be initialized before calling predict().');
}

/// Thrown when the ONNX model fails to load from the provided path.
final class SmartTurnModelLoadException extends SmartTurnException {
  /// Creates a [SmartTurnModelLoadException].
  const SmartTurnModelLoadException(super.message);
}

/// Thrown when ONNX runtime fails during forward-pass inference.
final class SmartTurnInferenceException extends SmartTurnException {
  /// Creates a [SmartTurnInferenceException].
  const SmartTurnInferenceException(super.message);
}
