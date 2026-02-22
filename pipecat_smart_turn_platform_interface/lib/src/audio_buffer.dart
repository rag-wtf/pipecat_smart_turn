import 'dart:typed_data';
import 'package:pipecat_smart_turn_platform_interface/src/audio_preprocessor.dart';

/// A zero-allocation circular ring buffer for storing recent audio context.
///
/// Designed to hold up to the specified duration of 16kHz audio. When the
/// buffer is full, new samples evict the oldest samples.
class AudioBuffer {
  /// Creates an [AudioBuffer] that holds up to [maxSeconds] of audio.
  AudioBuffer({double maxSeconds = 8.0})
    : maxSamples = (maxSeconds * AudioPreprocessor.kSampleRate).toInt(),
      _buffer = Float32List(
        (maxSeconds * AudioPreprocessor.kSampleRate).toInt(),
      );

  /// The maximum number of samples the buffer can hold.
  final int maxSamples;
  final Float32List _buffer;
  int _writeIdx = 0;
  int _count = 0;

  /// Appends new audio samples to the circular buffer.
  void append(Float32List samples) {
    if (samples.isEmpty) return;

    if (samples.length >= maxSamples) {
      // New chunk is larger than total buffer: keep only the tail of the chunk.
      final startOffset = samples.length - maxSamples;
      _buffer.setRange(0, maxSamples, samples, startOffset);
      _writeIdx = 0;
      _count = maxSamples;
      return;
    }

    // Standard circular write
    final firstPart = (maxSamples - _writeIdx).clamp(0, samples.length);
    _buffer.setRange(_writeIdx, _writeIdx + firstPart, samples);

    if (firstPart < samples.length) {
      // Wrap around
      final secondPart = samples.length - firstPart;
      _buffer.setRange(0, secondPart, samples, firstPart);
      _writeIdx = secondPart;
    } else {
      _writeIdx = (_writeIdx + samples.length) % maxSamples;
    }

    _count = (_count + samples.length).clamp(0, maxSamples);
  }

  /// Returns a contiguous [Float32List] of all samples in chronological order.
  Float32List toFloat32List() {
    final result = Float32List(_count);
    if (_count < maxSamples) {
      // Buffer not yet wrapped
      result.setRange(0, _count, _buffer);
    } else {
      // Buffer wrapped: [Tail][Head] order
      final headPartSize = maxSamples - _writeIdx;
      result
        ..setRange(0, headPartSize, _buffer, _writeIdx)
        ..setRange(headPartSize, maxSamples, _buffer, 0);
    }
    return result;
  }

  /// Resets the buffer state and clears all content.
  void clear() {
    _writeIdx = 0;
    _count = 0;
    _buffer.fillRange(0, maxSamples, 0);
  }

  /// The number of samples currently in the buffer.
  int get length => _count;

  /// Whether the buffer contains any samples.
  bool get hasContent => _count > 0;
}
