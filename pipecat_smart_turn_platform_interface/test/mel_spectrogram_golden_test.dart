@TestOn('vm')
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pipecat_smart_turn_platform_interface/src/audio_preprocessor.dart';
import 'package:pipecat_smart_turn_platform_interface/src/mel_spectrogram.dart';

void main() {
  test('MelSpectrogram matches golden snapshot', () async {
    // Generate a 1-second 440 Hz sine wave
    const sr = 16000;
    final audio = Float32List(128000); // 8 seconds, left-padded
    for (var i = 128000 - sr; i < 128000; i++) {
      audio[i] = math.sin(2 * math.pi * 440.0 * i / sr);
    }

    // Normalize it
    final prepared = AudioPreprocessor.prepareInput(audio);

    // Compute Mel spectrogram
    final result = MelSpectrogram.compute(prepared);

    // Compare against committed golden file.
    // See test/goldens/generate_golden.py for regeneration
    // instructions and upstream parity notes.
    final goldenFile = File('test/goldens/mel_spectrogram_golden.bin');
    expect(
      goldenFile.existsSync(),
      isTrue,
      reason:
          'Golden file missing. '
          'See test/goldens/generate_golden.py for how to '
          'regenerate.',
    );

    final goldenBytes = goldenFile.readAsBytesSync();
    final goldenFloat32 = goldenBytes.buffer.asFloat32List(
      goldenBytes.offsetInBytes,
      goldenBytes.lengthInBytes ~/ 4,
    );

    expect(result.length, goldenFloat32.length);
    for (var i = 0; i < result.length; i++) {
      expect(result[i], closeTo(goldenFloat32[i], 1e-4));
    }
  });
}
