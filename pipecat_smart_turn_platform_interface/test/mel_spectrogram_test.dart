import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pipecat_smart_turn_platform_interface/src/mel_spectrogram.dart';

void main() {
  group('MelSpectrogram', () {
    test('compute returns correct output length for 128k samples', () {
      final audio = Float32List(128000); // all zeros (silence)
      final result = MelSpectrogram.compute(audio);

      expect(
        result.length,
        equals(MelSpectrogram.kNMels * MelSpectrogram.kNumFrames),
      );
      expect(result.length, equals(64000));
    });

    test('compute output contains only finite values (no NaN/Inf)', () {
      final audio = Float32List(128000); // silence
      final result = MelSpectrogram.compute(audio);

      for (final v in result) {
        expect(v.isFinite, isTrue, reason: 'Found non-finite value: $v');
      }
    });

    test('compute with sine wave produces non-uniform energy', () {
      // 440 Hz sine wave at 16 kHz
      const freq = 440.0;
      const sr = 16000.0;
      final audio = Float32List(128000);
      for (var i = 0; i < audio.length; i++) {
        audio[i] = math.sin(2 * math.pi * freq * i / sr);
      }

      final result = MelSpectrogram.compute(audio);

      // At least some frames should have non-trivial energy (> log floor).
      final nonFloor = result.where((v) => v > -20.0).length;
      expect(
        nonFloor,
        greaterThan(0),
        reason: 'Sine wave should produce non-floor energy in mel spec',
      );
    });

    test('kNumFrames matches expected value for 128k samples', () {
      // 128000 / hop_length(160) = 800 frames with center padding.
      expect(MelSpectrogram.kNumFrames, equals(800));
      expect(MelSpectrogram.kNMels, equals(80));
    });
  });
}
