import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pipecat_smart_turn_platform_interface/pipecat_smart_turn_platform_interface.dart';

void main() {
  group('AudioPreprocessor', () {
    test('prepareInput left-pads short audio to 128,000 samples', () {
      final shortAudio = Float32List(48000)..fillRange(0, 48000, 0.5);
      final result = AudioPreprocessor.prepareInput(shortAudio);

      expect(result.length, equals(128000));
      // Verify zero-mean and unit-variance
      var sum = 0.0;
      for (final s in result) {
        sum += s;
      }
      expect(sum / 128000, closeTo(0.0, 1e-4));

      var variance = 0.0;
      for (final s in result) {
        variance += s * s;
      }
      expect(variance / 128000, closeTo(1.0, 1e-4));

      // Check left padding implies first elements are equal to each other
      // (since they were all 0s)
      expect(result[0], equals(result[1000]));
      // Check the jump happens at 80,000
      expect(result[79999], isNot(equals(result[80000])));
    });

    test('prepareInput crops overlong audio to last 128,000 samples', () {
      final longAudio = Float32List(150000);
      for (var i = 0; i < 150000; i++) {
        longAudio[i] = i.toDouble();
      }
      final result = AudioPreprocessor.prepareInput(longAudio);
      expect(result.length, equals(128000));
      // Should contain the LAST 128,000 samples.

      // Verify zero-mean and unit-variance
      var sum = 0.0;
      for (final s in result) {
        sum += s;
      }
      expect(sum / 128000, closeTo(0.0, 1e-4));

      var variance = 0.0;
      for (final s in result) {
        variance += s * s;
      }
      expect(variance / 128000, closeTo(1.0, 1e-4));

      // Since it's monotonically increasing, the normalized values should be
      // increasing
      expect(result[0] < result[127999], isTrue);
    });

    test('int16ToFloat32 conversion', () {
      final input = Int16List.fromList([-32768, 0, 32767]);
      final output = AudioPreprocessor.int16ToFloat32(input);
      expect(output[0], equals(-1.0));
      expect(output[1], equals(0.0));
      expect(output[2], closeTo(1.0, 0.0001)); // 32767/32768
    });

    test('bytesToFloat32 conversion', () {
      // Little Endian: 0x00, 0x80 -> -32768
      // 0x00, 0x00 -> 0
      // 0xFF, 0x7F -> 32767
      final input = Uint8List.fromList([0x00, 0x80, 0x00, 0x00, 0xFF, 0x7F]);
      final output = AudioPreprocessor.bytesToFloat32(input);
      expect(output.length, 3);
      expect(output[0], equals(-1.0));
      expect(output[1], equals(0.0));
      expect(output[2], closeTo(0.999969, 0.0001));
    });

    test('stereoToMono conversion', () {
      // L, R, L, R
      final input = Float32List.fromList([1.0, 0.0, 0.5, 0.5]);
      final output = AudioPreprocessor.stereoToMono(input);
      expect(output.length, 2);
      expect(output[0], 0.5); // (1+0)/2
      expect(output[1], 0.5); // (0.5+0.5)/2
    });

    test('resample48To16', () {
      // Should take every 3rd sample? No, implementation takes every 3rd?
      // "Simple decimation fallback for 48kHz to 16kHz (drops 2 of 3 samples)."
      // Code: output[i] = input[i * 3];

      final input = Float32List.fromList([
        1.0, 2.0, 3.0, // Should take 1.0
        4.0, 5.0, 6.0, // Should take 4.0
        7.0, 8.0, 9.0, // Should take 7.0
      ]);
      final output = AudioPreprocessor.resample48To16(input);
      expect(output.length, 3);
      expect(output[0], 1.0);
      expect(output[1], 4.0);
      expect(output[2], 7.0);
    });

    test('computeRms', () {
      final audio = Float32List.fromList([0.5, -0.5, 0.5, -0.5]);
      // (0.25 * 4) / 4 = 0.25 => sqrt(0.25) = 0.5
      expect(AudioPreprocessor.computeRms(audio), equals(0.5));
      expect(AudioPreprocessor.computeRms(Float32List(0)), 0.0);
    });

    test('sampleCountToMs', () {
      // kSampleRate = 16000
      // 16000 samples -> 1000ms
      expect(AudioPreprocessor.sampleCountToMs(16000), 1000);
      // 8000 samples -> 500ms
      expect(AudioPreprocessor.sampleCountToMs(8000), 500);
    });
  });
}
