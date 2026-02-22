/// The result of a Smart Turn inference.
class SmartTurnResult {
  /// Creates a [SmartTurnResult] with the given values.
  const SmartTurnResult({
    required this.isComplete,
    required this.confidence,
    required this.latencyMs,
    required this.audioLengthMs,
  });

  /// Whether the user has finished their speaking turn.
  final bool isComplete;

  /// The confidence score of the prediction [0.0, 1.0].
  final double confidence;

  /// The time taken for inference in milliseconds.
  final int latencyMs;

  /// The duration of the audio context evaluated in milliseconds.
  final double audioLengthMs;

  /// The probability [0.0 - 1.0] that the turn is still ongoing (incomplete).
  double get incompleteConfidence => 1.0 - confidence;

  @override
  String toString() {
    return 'SmartTurnResult(isComplete: $isComplete, '
        'confidence: ${confidence.toStringAsFixed(3)}, '
        'latency: ${latencyMs}ms)';
  }
}
