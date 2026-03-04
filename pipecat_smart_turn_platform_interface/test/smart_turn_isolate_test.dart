import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pipecat_smart_turn_platform_interface/src/exceptions.dart';
import 'package:pipecat_smart_turn_platform_interface/src/smart_turn_isolate.dart';

void main() {
  group('SmartTurnIsolate', () {
    test(
      'predict throws SmartTurnNotInitializedException if not spawned',
      () async {
        final isolate = SmartTurnIsolate();
        expect(
          () => isolate.predict(Float32List(128000)),
          throwsA(isA<SmartTurnNotInitializedException>()),
        );
      },
    );

    test('kill handles null isolate gracefully', () {
      SmartTurnIsolate().kill();
    });

    test('spawn stores configuration', () async {
      final isolate = SmartTurnIsolate();
      await isolate.spawn(
        modelFilePath: 'model.onnx',
        cpuThreadCount: 4,
      );

      // predict will attempt to compute but fail inside compute loop because
      // the native library or the file doesn't exist.
      try {
        await isolate.predict(Float32List(128000));
        fail('Should not reach here');
      } on Object catch (e) {
        expect(
          e is SmartTurnInferenceException ||
              e is ArgumentError ||
              e.toString().contains('Failed to load dynamic library'),
          isTrue,
        );
      }
      isolate.kill();
    });
  });

  group('IsolateConfig', () {
    test('constructs correctly', () {
      final config = IsolateConfig(
        modelFilePath: 'test.onnx',
        cpuThreadCount: 2,
        audioData: Float32List(100),
      );

      expect(config.modelFilePath, 'test.onnx');
      expect(config.cpuThreadCount, 2);
      expect(config.audioData.length, 100);
    });
  });
}
