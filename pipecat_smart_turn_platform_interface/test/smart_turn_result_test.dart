import 'package:flutter_test/flutter_test.dart';
import 'package:pipecat_smart_turn_platform_interface/pipecat_smart_turn_platform_interface.dart';

void main() {
  group('SmartTurnResult', () {
    test('incompleteConfidence returns 1.0 - confidence', () {
      const result = SmartTurnResult(
        isComplete: false,
        confidence: 0.3,
        latencyMs: 10,
        audioLengthMs: 1000,
      );
      expect(result.incompleteConfidence, closeTo(0.7, 0.0001));
    });

    test('toString formats correctly', () {
      const result = SmartTurnResult(
        isComplete: true,
        confidence: 0.98765,
        latencyMs: 123,
        audioLengthMs: 8000,
      );
      expect(
        result.toString(),
        equals(
          'SmartTurnResult(isComplete: true, '
          'confidence: 0.988, latency: 123ms)',
        ),
      );
    });
  });
}
