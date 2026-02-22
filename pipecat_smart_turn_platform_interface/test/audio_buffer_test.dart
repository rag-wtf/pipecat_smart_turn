import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pipecat_smart_turn_platform_interface/pipecat_smart_turn_platform_interface.dart';

void main() {
  group('AudioBuffer', () {
    test('initializes with correct length', () {
      final buffer = AudioBuffer(maxSeconds: 1); // 16,000 samples
      expect(buffer.maxSamples, equals(16000));
      expect(buffer.length, equals(0));
      expect(buffer.hasContent, isFalse);
    });

    test('appends data correctly', () {
      final buffer = AudioBuffer(maxSeconds: 1);
      final chunk = Float32List(100);
      buffer.append(chunk);
      expect(buffer.length, equals(100));
      expect(buffer.hasContent, isTrue);
    });

    test('clamps to maxSamples and maintains order when overfilled', () {
      final buffer = AudioBuffer(maxSeconds: 1); // 16,000 samples max

      // Fill first 10,000 with 1.0
      final chunk1 = Float32List(10000)..fillRange(0, 10000, 1);
      // Fill next 10,000 with 2.0
      final chunk2 = Float32List(10000)..fillRange(0, 10000, 2);

      buffer
        ..append(chunk1)
        ..append(chunk2); // 20,000 total — should clamp to 16,000

      expect(buffer.length, equals(16000));

      final output = buffer.toFloat32List();

      // The oldest 4,000 samples of chunk1 are evicted.
      // Remaining: 6,000 samples of 1.0, then 10,000 samples of 2.0.
      expect(output[0], equals(1));
      expect(output[5999], equals(1));
      expect(output[6000], equals(2));
      expect(output[15999], equals(2));
    });

    test('handles chunks larger than buffer capacity', () {
      final buffer = AudioBuffer(maxSeconds: 1); // 16,000 samples
      final largeChunk = Float32List(20000);
      for (var i = 0; i < 20000; i++) {
        largeChunk[i] = i.toDouble();
      }

      buffer.append(largeChunk);

      expect(buffer.length, equals(16000));
      final output = buffer.toFloat32List();
      // Should contain the last 16,000 samples of largeChunk
      expect(output[0], equals(4000));
      expect(output[15999], equals(19999));
    });

    test('clear resets the buffer', () {
      final buffer = AudioBuffer(maxSeconds: 1)
        ..append(Float32List(1000))
        ..clear();
      expect(buffer.length, equals(0));
      expect(buffer.hasContent, isFalse);
    });

    test('append with empty samples does nothing', () {
      final buffer = AudioBuffer(maxSeconds: 1);
      buffer.append(Float32List(0));
      expect(buffer.length, equals(0));
    });

    test('append wraps around correctly (exact fit)', () {
      final buffer = AudioBuffer(maxSeconds: 0.1); // 1600 samples
      // Fill buffer completely
      buffer.append(Float32List(1600)..fillRange(0, 1600, 1));
      // Append more data, exactly fitting remaining space if any (here full rewrite)
      // Actually let's do partial fill first
      buffer.clear();

      // buffer size 1600.
      // Fill 1500.
      buffer.append(Float32List(1500)..fillRange(0, 1500, 1));
      // Append 100. Should fit exactly at the end.
      buffer.append(Float32List(100)..fillRange(0, 100, 2));

      expect(buffer.length, 1600);
      final output = buffer.toFloat32List();
      expect(output[0], 1);
      expect(output[1499], 1);
      expect(output[1500], 2);
      expect(output[1599], 2);
    });

    test('append wraps around correctly (overflow)', () {
      final buffer = AudioBuffer(maxSeconds: 0.1); // 1600 samples
      // Fill 1500.
      buffer.append(Float32List(1500)..fillRange(0, 1500, 1));
      // Append 200. Should wrap around by 100.
      buffer.append(Float32List(200)..fillRange(0, 200, 2));

      expect(buffer.length, 1600);
      final output = buffer.toFloat32List();
      // Oldest 100 samples (from first 1500) are evicted.
      // Remaining: 1400 samples of 1, then 200 samples of 2.
      expect(output[0], 1);
      expect(output[1399], 1);
      expect(output[1400], 2);
      expect(output[1599], 2);
    });
  });
}
