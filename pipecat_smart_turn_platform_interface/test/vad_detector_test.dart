import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pipecat_smart_turn_platform_interface/pipecat_smart_turn_platform_interface.dart';

void main() {
  group('EnergyVad', () {
    test('initial state is silence', () {
      final vad = EnergyVad();
      final silence = Float32List(100)..fillRange(0, 100, 0);
      expect(vad.process(silence), equals(VadState.silence));
    });

    test('transitions to speechStart on high energy', () {
      final vad = EnergyVad();
      final speech = Float32List(100)..fillRange(0, 100, 0.5);
      expect(vad.process(speech), equals(VadState.speechStart));
    });

    test('maintains speech state', () {
      final vad = EnergyVad();
      final speech = Float32List(100)..fillRange(0, 100, 0.5);
      vad.process(speech); // speechStart
      expect(vad.process(speech), equals(VadState.speech));
    });

    test('evaluates silence after speech', () {
      final vad = EnergyVad();
      final speech = Float32List(100)..fillRange(0, 100, 0.5);
      final silence = Float32List(100)..fillRange(0, 100, 0);

      vad.process(speech); // speechStart

      expect(vad.process(silence), equals(VadState.evaluatingSilence));
      expect(vad.process(silence), equals(VadState.evaluatingSilence));
      expect(vad.process(silence), equals(VadState.silenceAfterSpeech));
      expect(vad.process(silence), equals(VadState.silence));
    });

    test('noise floor adapts to low signal', () {
      // Use high weight for fast adaptation in test
      final vad = EnergyVad(noiseFloorWeight: 0.5);

      // Simulate high noise floor initially
      final initialNoise = Float32List(100)..fillRange(0, 100, 0.1);
      for (var i = 0; i < 10; i++) {
        vad.process(initialNoise);
      }

      // A signal of 0.12 should be silence (0.1 * 1.5 = 0.15 > 0.12)
      final midSignal = Float32List(100)..fillRange(0, 100, 0.12);
      expect(vad.process(midSignal), equals(VadState.silence));

      // Adaptation should happen...
      for (var i = 0; i < 20; i++) {
        vad.process(midSignal);
      }

      // Now a signal of 0.3 should be speech (since noise floor dropped)
      final speech = Float32List(100)..fillRange(0, 100, 0.3);
      expect(vad.process(speech), equals(VadState.speechStart));
    });
  });
}
