import 'dart:isolate';
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
      try {
        await isolate.spawn(
          modelFilePath: 'model.onnx',
          cpuThreadCount: 4,
        );
        fail('Should not reach here');
      } on Object catch (e) {
        expect(e, isA<SmartTurnModelLoadException>());
      }
      isolate.kill();
    });
  });

  group('IsolateConfig', () {
    test('constructs correctly', () {
      final port = ReceivePort();
      final config = IsolateConfig(
        modelFilePath: 'test.onnx',
        cpuThreadCount: 2,
        sendPort: port.sendPort,
      );

      expect(config.modelFilePath, 'test.onnx');
      expect(config.cpuThreadCount, 2);
    });
  });
}
