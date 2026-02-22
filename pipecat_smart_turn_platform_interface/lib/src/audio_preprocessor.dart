import 'dart:typed_data';

/// Handles audio preparation and format conversion for Smart Turn.
class AudioPreprocessor {
  /// The target sample rate required by the model.
  static const int kSampleRate = 16000;

  /// The context window supported by Smart Turn v3 (8 seconds).
  static const int kMaxDurationSeconds = 8;

  /// Total samples required for a forward pass (16kHz * 8s).
  static const int kMaxSamples = 128000;

  /// Prepares an audio segment for the ONNX model.
  ///
  /// Requirement: input must be exactly 128,000 samples.
  /// Behavior:
  /// - If [audio] < 128,000, it is **left-padded** with zeros.
  /// - If [audio] > 128,000, it is **cropped** to the most recent samples.
  /// - Applies a 5ms (80 samples) linear fade-in to the start of the audio
  ///   signal (post-padding) to prevent impulsive noise (clicks) from
  ///   triggering false "complete" detections.
  static Float32List prepareInput(Float32List audio) {
    final result = Float32List(kMaxSamples);

    if (audio.length >= kMaxSamples) {
      // Crop to last 128k samples
      final startOffset = audio.length - kMaxSamples;
      result.setRange(0, kMaxSamples, audio, startOffset);
    } else {
      // Left-pad with zeros
      final paddingLength = kMaxSamples - audio.length;
      result.setRange(paddingLength, kMaxSamples, audio);
    }

    // Apply 5ms (80 samples) fade-in to the start of the audio signal
    final signalStartIdx = (kMaxSamples - audio.length).clamp(0, kMaxSamples);
    const fadeSamples = 80;
    for (
      var i = 0;
      i < fadeSamples && (signalStartIdx + i) < kMaxSamples;
      i++
    ) {
      result[signalStartIdx + i] *= i / fadeSamples;
    }

    return result;
  }

  /// Converts 16-bit PCM (Int16) to normalized Float32 [-1.0, 1.0].
  static Float32List int16ToFloat32(Int16List input) {
    final output = Float32List(input.length);
    for (var i = 0; i < input.length; i++) {
      output[i] = input[i] / 32768.0;
    }
    return output;
  }

  /// Converts raw bytes (Int16 Little Endian) to normalized Float32.
  static Float32List bytesToFloat32(Uint8List bytes) {
    final int16Data = bytes.buffer.asInt16List();
    return int16ToFloat32(int16Data);
  }

  /// Converts Stereo Float32 audio to Mono by averaging channels.
  static Float32List stereoToMono(Float32List stereo) {
    final mono = Float32List(stereo.length ~/ 2);
    for (var i = 0; i < mono.length; i++) {
      mono[i] = (stereo[i * 2] + stereo[i * 2 + 1]) / 2.0;
    }
    return mono;
  }

  /// Simple decimation fallback for 48kHz to 16kHz (drops 2 of 3 samples).
  /// For production, use a proper polyphase resampler.
  static Float32List resample48To16(Float32List input) {
    final output = Float32List(input.length ~/ 3);
    for (var i = 0; i < output.length; i++) {
      output[i] = input[i * 3];
    }
    return output;
  }

  /// Computes Root Mean Square (RMS) energy of an audio signal.
  static double computeRms(Float32List audio) {
    if (audio.isEmpty) return 0;
    var sumSquares = 0.0;
    for (final sample in audio) {
      sumSquares += sample * sample;
    }
    return sumSquares / audio.length;
  }

  /// Converts sample count to milliseconds at 16kHz.
  static int sampleCountToMs(int samples) => (samples * 1000) ~/ kSampleRate;
}
