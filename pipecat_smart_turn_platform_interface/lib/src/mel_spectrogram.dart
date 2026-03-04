import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

/// Computes a Whisper-compatible log-mel spectrogram from raw audio.
///
/// Parameters match the Smart Turn v3.x model preprocessing:
/// - Sample rate: 16 kHz
/// - FFT size (n_fft): 400 (25 ms window)
/// - Hop length: 160 (10 ms hop)
/// - Mel bands (n_mels): 80
/// - Centering: true (pads n_fft/2 zeros at both ends)
///
/// For 128,000 input samples this produces an output of shape [80, 800].
class MelSpectrogram {
  MelSpectrogram._();

  /// Sample rate of the input audio (Hz).
  static const int kSampleRate = 16000;

  /// Number of FFT frequency bins to compute.
  static const int kNFft = 400;

  /// Number of samples between successive FFT frames.
  static const int kHopLength = 160;

  /// Number of mel filter banks.
  static const int kNMels = 80;

  /// Number of time frames produced for 128,000 input samples with centering.
  static const int kNumFrames = 800;

  /// Minimum frequency for mel filter bank (Hz).
  static const double kFMin = 0;

  /// Maximum frequency for mel filter bank (Hz) – defaults to Nyquist.
  static const double kFMax = kSampleRate / 2.0;

  // Cached Hann window (length kNFft).
  static final Float64List _hannWindow = _buildHannWindow();

  // Cached mel filter bank matrix [kNMels × (kNFft/2+1)].
  static final List<Float64List> _melFilters = _buildMelFilterBank();

  /// Precomputed FFT instance.
  static final FFT _fft = FFT(kNFft);

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Computes the log-mel spectrogram of [audio] (raw float32, 16 kHz, mono).
  ///
  /// [audio] should contain exactly 128,000 samples after
  /// `AudioPreprocessor.prepareInput` has been applied.
  ///
  /// Returns a flat [Float32List] of length [kNMels] × [kNumFrames] = 64,000
  /// in row-major order: `result[mel * kNumFrames + frame]`.
  static Float32List compute(Float32List audio) {
    // 1. Centre-pad by n_fft/2 = 200 samples on each side (reflect padding).
    final padded = _centreReflectPad(audio, kNFft ~/ 2);

    // 2. Pre-emphasis (not applied, consistent with Whisper).

    // 3. STFT → power spectrogram [nFreqs × kNumFrames].
    const nFreqs = kNFft ~/ 2 + 1; // 201
    final powerSpec = List<Float64List>.generate(
      nFreqs,
      (_) => Float64List(kNumFrames),
    );

    final frame = Float64List(kNFft);
    for (var t = 0; t < kNumFrames; t++) {
      final start = t * kHopLength;
      // Apply Hann window.
      for (var i = 0; i < kNFft; i++) {
        frame[i] = padded[start + i] * _hannWindow[i];
      }
      // In-place FFT — returns complex output as Float64x2List.
      final spectrum = _fft.realFft(frame);
      // Accumulate power |X|².
      for (var k = 0; k < nFreqs; k++) {
        final c = spectrum[k];
        powerSpec[k][t] = c.x * c.x + c.y * c.y;
      }
    }

    // 4. Apply mel filter bank and log-compress → [kNMels × kNumFrames].
    const floorVal = 1e-10;
    final output = Float32List(kNMels * kNumFrames);
    for (var m = 0; m < kNMels; m++) {
      final filter = _melFilters[m];
      for (var t = 0; t < kNumFrames; t++) {
        var energy = 0.0;
        for (var k = 0; k < nFreqs; k++) {
          energy += filter[k] * powerSpec[k][t];
        }
        // Log-mel energy (natural log, matches typical librosa default).
        output[m * kNumFrames + t] = math.log(math.max(energy, floorVal));
      }
    }

    return output;
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  static Float64List _buildHannWindow() {
    final w = Float64List(kNFft);
    for (var i = 0; i < kNFft; i++) {
      w[i] = 0.5 * (1.0 - math.cos(2 * math.pi * i / kNFft));
    }
    return w;
  }

  /// Builds the mel filter bank matrix of shape [kNMels × nFreqs].
  static List<Float64List> _buildMelFilterBank() {
    const nFreqs = kNFft ~/ 2 + 1; // 201
    // Map Hz to mel scale (O'Shaughnessy / HTK formula).
    double hzToMel(double hz) =>
        2595.0 * math.log(1.0 + hz / 700.0) / math.ln10;
    double melToHz(double mel) => 700.0 * (math.pow(10.0, mel / 2595.0) - 1.0);

    final melMin = hzToMel(kFMin);
    final melMax = hzToMel(kFMax);

    // kNMels + 2 evenly-spaced points in mel space.
    final melPoints = Float64List(kNMels + 2);
    for (var i = 0; i < melPoints.length; i++) {
      melPoints[i] = melMin + (melMax - melMin) * i / (kNMels + 1);
    }

    // Convert mel points back to Hz, then to FFT bin indices.
    final freqPoints = Float64List(kNMels + 2);
    for (var i = 0; i < freqPoints.length; i++) {
      freqPoints[i] = melToHz(melPoints[i]);
    }
    final binPoints = Float64List(kNMels + 2);
    for (var i = 0; i < binPoints.length; i++) {
      binPoints[i] = (freqPoints[i] / kSampleRate * kNFft).floorToDouble();
    }

    // Build triangular filter banks.
    final filters = List<Float64List>.generate(
      kNMels,
      (_) => Float64List(nFreqs),
    );
    for (var m = 0; m < kNMels; m++) {
      final left = binPoints[m].toInt();
      final center = binPoints[m + 1].toInt();
      final right = binPoints[m + 2].toInt();

      for (var k = left; k <= center && k < nFreqs; k++) {
        if (center != left) {
          filters[m][k] = (k - left) / (center - left);
        }
      }
      for (var k = center; k <= right && k < nFreqs; k++) {
        if (right != center) {
          filters[m][k] = (right - k) / (right - center);
        }
      }
    }
    return filters;
  }

  /// Pads [audio] with [padSize] samples on each side using reflect padding.
  static Float64List _centreReflectPad(Float32List audio, int padSize) {
    final len = audio.length;
    final out = Float64List(len + 2 * padSize);

    // Copy main signal.
    for (var i = 0; i < len; i++) {
      out[padSize + i] = audio[i];
    }
    // Left reflect (mirror the first padSize samples).
    for (var i = 0; i < padSize; i++) {
      out[padSize - 1 - i] = audio[i + 1];
    }
    // Right reflect (mirror the last padSize samples).
    for (var i = 0; i < padSize; i++) {
      out[padSize + len + i] = audio[len - 2 - i];
    }
    return out;
  }
}
