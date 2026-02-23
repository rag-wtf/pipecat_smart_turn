/// Configuration for the Smart Turn semantic VAD detector.
class SmartTurnConfig {
  /// Creates a [SmartTurnConfig] with optional custom parameters.
  const SmartTurnConfig({
    this.completionThreshold = 0.7,
    this.maxAudioSeconds = 8.0,
    this.customModelPath,
    this.cpuThreadCount = 1,
    this.useIsolate = true,
  }) : assert(
         completionThreshold >= 0.0 && completionThreshold <= 1.0,
         'completionThreshold must be between 0.0 and 1.0',
       ),
       assert(
         maxAudioSeconds > 0.0 && maxAudioSeconds <= 8.0,
         'maxAudioSeconds must be between 0.0 and 8.0',
       ),
       assert(
         cpuThreadCount >= 1,
         'cpuThreadCount must be at least 1',
       );

  /// The probability threshold above which a turn is considered "complete".
  /// Defaults to 0.7 (70%). Range: [0.0, 1.0].
  final double completionThreshold;

  /// The duration of the circular audio buffer in seconds.
  /// Smart Turn v3 supports up to 8 seconds of context.
  /// Defaults to 8. Range: (0.0, 8.0].
  final double maxAudioSeconds;

  /// Absolute path to the Smart Turn ONNX model file.
  /// If `null` (default), the package will automatically extract and use
  /// the bundled `smart-turn-v3.2-cpu.onnx` model from the package assets.
  final String? customModelPath;

  /// Number of CPU threads to use for ONNX inference.
  /// **Recommendation**: Keep this at 1 for mobile devices to avoid
  /// thread orchestration overhead and thermal throttling.
  final int cpuThreadCount;

  /// Whether to run ONNX inference in a separate Dart Isolate.
  /// **Recommendation**: Set to `true` for production apps to keep the
  /// main UI thread responsive during the 10-150ms inference window.
  final bool useIsolate;
}
