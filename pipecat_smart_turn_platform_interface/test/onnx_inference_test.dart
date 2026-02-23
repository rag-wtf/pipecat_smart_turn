import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pipecat_smart_turn_platform_interface/pipecat_smart_turn_platform_interface.dart';
import 'package:pipecat_smart_turn_platform_interface/src/onnx_inference.dart';

void main() {
  group('SmartTurnOnnxSession', () {
    late SmartTurnOnnxSession session;

    setUp(() {
      session = SmartTurnOnnxSession();
    });

    test(
      'run throws SmartTurnNotInitializedException if not initialized',
      () async {
        expect(
          () => session.run(Float32List(128000)),
          throwsA(isA<SmartTurnNotInitializedException>()),
        );
      },
    );

    // We can't easily test success case without a valid model and ONNX runtime.
    // But we can test failure to load model if we provide invalid path.
    // However, initialize calls OrtEnv.init() which might fail if native lib
    // is missing.
    // If it fails, it throws SmartTurnModelLoadException.

    test('initialize throws SmartTurnModelLoadException on failure', () async {
      // This test might fail if OrtEnv.init() crashes or if it succeeds but
      // file load fails. We expect SmartTurnModelLoadException.
      try {
        await session.initialize(modelFilePath: 'non_existent_file.onnx');
        fail('Should have thrown SmartTurnModelLoadException');
      } on SmartTurnModelLoadException catch (e) {
        expect(e, isNotNull);
      }
    });
  });
}
