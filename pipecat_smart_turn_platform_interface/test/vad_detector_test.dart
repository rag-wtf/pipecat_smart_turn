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
      final vad = EnergyVad(noiseFloorWeight: 0.5)..reset(newNoiseFloor: 0.1);

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

    test('reset clears internal state', () {
      final vad = EnergyVad();
      final speech = Float32List(100)..fillRange(0, 100, 0.5);
      expect(vad.process(speech), equals(VadState.speechStart));
      expect(vad.process(speech), equals(VadState.speech));

      vad.reset();

      // Should restart speech detection from speechStart
      expect(vad.process(speech), equals(VadState.speechStart));
    });

    test('warmup adapts noise floor to ambient room noise', () {
      // Ambient room noise of 0.04
      final ambientRoom = Float32List(100)..fillRange(0, 100, 0.04);
      final vad = EnergyVad(warmupFrames: 5);

      // During 5 warmup frames, returns silence and tracks ambient floor
      for (var i = 0; i < 5; i++) {
        expect(vad.process(ambientRoom), equals(VadState.silence));
      }
      expect(vad.noiseFloor, closeTo(0.04, 0.005));

      // Continuous ambient noise stays silence (not misdetected as speech)
      expect(vad.process(ambientRoom), equals(VadState.silence));

      // Actual speech (0.3 RMS > 2x 0.04) triggers speech
      final speech = Float32List(100)..fillRange(0, 100, 0.3);
      expect(vad.process(speech), equals(VadState.speechStart));
    });

    test('asymmetric upward adaptation handles ambient noise increase', () {
      // Start with initial floor 0.01
      final vad = EnergyVad(initialNoiseFloor: 0.01);
      expect(vad.noiseFloor, equals(0.01));

      // Slightly higher ambient frame (0.015, which is > 1.5x but < 2x floor)
      final ambient2 = Float32List(100)..fillRange(0, 100, 0.015);
      for (var i = 0; i < 50; i++) {
        expect(vad.process(ambient2), equals(VadState.silence));
      }
      // Floor should have adapted upward
      expect(vad.noiseFloor > 0.012, isTrue);
    });
  });
}
