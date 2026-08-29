import 'dart:math' as math;
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
  /// - Applies per-utterance zero-mean / unit-variance normalization.
  /// - For near-silence input (variance < 1e-8), returns a zero-filled buffer
  ///   to avoid amplifying microphone dither noise to unit variance.
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

    // Zero-mean / unit-variance normalization (per-utterance)
    var sum = 0.0;
    for (var i = 0; i < kMaxSamples; i++) {
      sum += result[i];
    }
    final mean = sum / kMaxSamples;

    var sumSqDiff = 0.0;
    for (var i = 0; i < kMaxSamples; i++) {
      final diff = result[i] - mean;
      sumSqDiff += diff * diff;
    }

    final variance = sumSqDiff / kMaxSamples;
    final std = math.sqrt(variance);

    // Near-silence floor check: avoid amplifying quiet dither noise.
    // When standard deviation is below 1e-4 (~-80 dBFS), treat as silence.
    if (std < 1e-4) {
      return Float32List(kMaxSamples);
    }

    // Whisper uses variance without Bessel's correction, std = sqrt(var / N)
    final safeStd = math.max(std, 1e-5);

    for (var i = 0; i < kMaxSamples; i++) {
      result[i] = (result[i] - mean) / safeStd;
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
  ///
  /// **Offset/length guards**: The [bytes] parameter may be a *sublist view*
  /// of a larger [ByteBuffer] (e.g. when the `record` package streams audio
  /// chunks from its internal ring buffer). If the sublist view has an
  /// unaligned [Uint8List.offsetInBytes], it is copied to an aligned buffer
  /// before conversion.
  static Float32List bytesToFloat32(Uint8List bytes) {
    if (!bytes.lengthInBytes.isEven) {
      throw ArgumentError(
        'bytesToFloat32 expects an even number of bytes, '
        'got ${bytes.lengthInBytes}',
      );
    }

    final Int16List int16Data;
    if (bytes.offsetInBytes.isOdd) {
      // Unaligned view in byte buffer: copy slice to aligned buffer.
      final alignedBytes = Uint8List.fromList(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      int16Data = alignedBytes.buffer.asInt16List(
        0,
        alignedBytes.lengthInBytes ~/ 2,
      );
    } else {
      int16Data = bytes.buffer.asInt16List(
        bytes.offsetInBytes,
        bytes.lengthInBytes ~/ 2,
      );
    }
    return int16ToFloat32(int16Data);
  }

  /// Converts Stereo Float32 audio to Mono by averaging channels.
  static Float32List stereoToMono(Float32List stereo) {
    if (!stereo.length.isEven) {
      throw ArgumentError(
        'stereoToMono expects an even number of samples, '
        'got ${stereo.length}',
      );
    }
    final mono = Float32List(stereo.length ~/ 2);
    for (var i = 0; i < mono.length; i++) {
      mono[i] = (stereo[i * 2] + stereo[i * 2 + 1]) / 2.0;
    }
    return mono;
  }

  /// Simple decimation fallback for 48kHz to 16kHz (drops 2 of 3 samples).
  /// For production with high frequency content, use a windowed polyphase
  /// resampler.
  static Float32List resample48To16(Float32List input) {
    final output = Float32List(input.length ~/ 3);
    for (var i = 0; i < output.length; i++) {
      output[i] = input[i * 3];
    }
    return output;
  }

  /// Computes Root Mean Square (RMS) energy for [audio] samples.
  static double computeRms(Float32List audio) {
    if (audio.isEmpty) return 0;
    var sumSquares = 0.0;
    for (final sample in audio) {
      sumSquares += sample * sample;
    }
    return math.sqrt(sumSquares / audio.length);
  }

  /// Converts sample count to milliseconds at 16kHz.
  static int sampleCountToMs(int samples) => (samples * 1000) ~/ kSampleRate;
}
