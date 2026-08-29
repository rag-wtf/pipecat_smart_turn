@TestOn('vm')
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pipecat_smart_turn_platform_interface/src/audio_preprocessor.dart';
import 'package:pipecat_smart_turn_platform_interface/src/smart_turn_config.dart';
import 'package:pipecat_smart_turn_platform_interface/src/smart_turn_detector.dart';

void main() {
  test(
    'SmartTurnDetector runs real model and outputs sane probability',
    () async {
      // 1. Locate the model. In tests, the CWD is typically the package root.
      final modelFile = File(
        '../pipecat_smart_turn_platform_interface/assets/smart-turn-v3.2-cpu.onnx',
      );
      if (!modelFile.existsSync()) {
        markTestSkipped('Real ONNX model not found at ${modelFile.path}.');
        return;
      }

      final detector = SmartTurnDetector(
        config: SmartTurnConfig(
          customModelPath: modelFile.path,
          useIsolate: false, // Run directly in test isolate
        ),
      );

      // This initialization is expected to throw
      // SmartTurnModelLoadException if FFI fails to load onnxruntime,
      // which happens in pure Dart tests if we don't manually load DLL/so.
      // We will skip if onnxruntime is missing rather than failing.
      try {
        await detector.initialize();
      } catch (e) {
        if (e.toString().contains('Failed to load ONNX model')) {
          markTestSkipped(
            'Skipping real model test because ONNX Runtime native bindings '
            'are not available in this test environment. Error: $e',
          );
          return;
        }
        rethrow;
      }

      // Generate a 1-second 440 Hz sine wave
      const sr = 16000;
      final audio = Float32List(128000); // 8 seconds, left-padded
      for (var i = 128000 - sr; i < 128000; i++) {
        audio[i] = math.sin(2 * math.pi * 440.0 * i / sr);
      }

      // Normalize it
      final prepared = AudioPreprocessor.prepareInput(audio);

      final result = await detector.predict(prepared);

      expect(result, isNotNull);
      expect(result!.confidence, greaterThanOrEqualTo(0.0));
      expect(result.confidence, lessThanOrEqualTo(1.0));

      await detector.dispose();
    },
  );
}
