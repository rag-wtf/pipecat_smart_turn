import 'package:flutter_test/flutter_test.dart';
import 'package:pipecat_smart_turn_platform_interface/pipecat_smart_turn_platform_interface.dart';

void main() {
  group('SmartTurnConfig', () {
    test('defaults are correct', () {
      const config = SmartTurnConfig();
      expect(config.completionThreshold, equals(0.7));
      expect(config.maxAudioSeconds, equals(8));
      expect(config.cpuThreadCount, equals(1));
      expect(config.useIsolate, isTrue);
      expect(config.customModelPath, isNull);
    });

    test('accepts valid custom values', () {
      const config = SmartTurnConfig(
        completionThreshold: 0.5,
        maxAudioSeconds: 5,
        cpuThreadCount: 4,
        useIsolate: false,
        customModelPath: '/path/to/model.onnx',
      );
      expect(config.completionThreshold, equals(0.5));
      expect(config.maxAudioSeconds, equals(5));
      expect(config.cpuThreadCount, equals(4));
      expect(config.useIsolate, isFalse);
      expect(config.customModelPath, equals('/path/to/model.onnx'));
    });

    group('assertions', () {
      test('throws on invalid completionThreshold', () {
        expect(
          () => SmartTurnConfig(completionThreshold: -0.1),
          throwsAssertionError,
        );
        expect(
          () => SmartTurnConfig(completionThreshold: 1.1),
          throwsAssertionError,
        );
      });

      test('throws on invalid maxAudioSeconds', () {
        expect(
          () => SmartTurnConfig(maxAudioSeconds: 0),
          throwsAssertionError,
        );
        expect(
          () => SmartTurnConfig(maxAudioSeconds: 8.1),
          throwsAssertionError,
        );
      });

      test('throws on invalid cpuThreadCount', () {
        expect(() => SmartTurnConfig(cpuThreadCount: 0), throwsAssertionError);
      });
    });
  });
}
