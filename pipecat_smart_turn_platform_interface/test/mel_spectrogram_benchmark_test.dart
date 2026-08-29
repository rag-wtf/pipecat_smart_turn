import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pipecat_smart_turn_platform_interface/src/audio_preprocessor.dart';
import 'package:pipecat_smart_turn_platform_interface/src/mel_spectrogram.dart';

void main() {
  group('MelSpectrogram Benchmark', () {
    test('computes 800 frames within latency budget', () {
      // Prepare 8 seconds of synthetic audio (128,000 samples)
      final audio = Float32List(128000);
      for (var i = 0; i < 128000; i++) {
        audio[i] = math.sin(2 * math.pi * 440.0 * i / 16000);
      }
      final prepared = AudioPreprocessor.prepareInput(audio);

      // Warm-up run to ensure JIT compilation and static table initialization
      final warmup = MelSpectrogram.compute(prepared);
      expect(warmup.length, equals(64000));

      // Timed runs
      const iterations = 5;
      final stopwatch = Stopwatch()..start();

      for (var i = 0; i < iterations; i++) {
        final result = MelSpectrogram.compute(prepared);
        expect(result.length, equals(64000));
      }

      stopwatch.stop();
      final avgDurationMs = stopwatch.elapsedMilliseconds / iterations;

      // Verify that per-inference Mel DFT latency is within budget (< 500ms).
      // On modern desktop x86/ARM CPUs, this typically runs in 10-60ms.
      expect(
        avgDurationMs,
        lessThan(500),
        reason:
            'MelSpectrogram compute took ${avgDurationMs}ms on average, '
            'exceeding latency budget of 500ms.',
      );
    });
  });
}
