import 'dart:math' as math;
import 'dart:typed_data';

/// Computes a Whisper-compatible log-mel spectrogram from raw audio.
///
/// Parameters match the Smart Turn v3.x model preprocessing:
/// - Sample rate: 16 kHz
/// - Window size (n_fft): 400 samples (25 ms)
/// - FFT size: 512 (next power-of-2 ≥ n_fft, for efficiency)
/// - Hop length: 160 samples (10 ms)
/// - Mel bands (n_mels): 80
/// - Centering: true (reflects n_fft/2 = 200 samples on each side)
///
/// For 128,000 input samples this produces a flat [Float32List] of length
/// 80 × 800 = 64,000 values, logically shaped [80, 800].
///
/// Uses a pure-Dart radix-2 in-place FFT (no Uint64List — Web-compatible).
class MelSpectrogram {
  // coverage:ignore-start
  MelSpectrogram._();
  // coverage:ignore-end

  /// Sample rate of the input audio (Hz).
  static const int kSampleRate = 16000;

  /// Analysis window length in samples (25 ms @ 16 kHz).
  static const int kNFft = 400;

  /// FFT size — next power of 2 ≥ kNFft. Zero-padding improves interpolation.
  static const int kFftSize = 512;

  /// Number of samples between successive frames (10 ms @ 16 kHz).
  static const int kHopLength = 160;

  /// Number of mel filter banks.
  static const int kNMels = 80;

  /// Number of time frames produced for 128,000 input samples with centering.
  static const int kNumFrames = 800;

  /// Number of unique FFT frequency bins = kFftSize / 2 + 1.
  static const int kNFreqs = kFftSize ~/ 2 + 1; // 257

  // Cached Hann window (length kNFft, zero-padded inline when applied).
  static final Float64List _hannWindow = _buildHannWindow();

  // Cached mel filter bank [kNMels × kNFreqs].
  static final List<Float64List> _melFilters = _buildMelFilterBank();

  // Reusable FFT buffers — allocated once, reused per frame.
  static final Float64List _real = Float64List(kFftSize);
  static final Float64List _imag = Float64List(kFftSize);

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Computes the log-mel spectrogram of [audio] (raw float32, 16 kHz, mono).
  ///
  /// [audio] should contain exactly 128,000 samples after padding/cropping.
  ///
  /// Returns a flat [Float32List] of length [kNMels] × [kNumFrames] = 64,000
  /// in row-major order: `result[mel * kNumFrames + frame]`.
  static Float32List compute(Float32List audio) {
    // Centre-pad with reflect padding (n_fft/2 = 200 samples each side).
    final padded = _centreReflectPad(audio, kNFft ~/ 2);

    // Power spectrogram [kNFreqs × kNumFrames] accumulated over frames.
    final powerSpec = List<Float64List>.generate(
      kNFreqs,
      (_) => Float64List(kNumFrames),
    );

    for (var t = 0; t < kNumFrames; t++) {
      final start = t * kHopLength;

      // Fill real[] with windowed frame, zero-pad (kNFft..kFftSize).
      for (var i = 0; i < kNFft; i++) {
        _real[i] = padded[start + i] * _hannWindow[i];
      }
      for (var i = kNFft; i < kFftSize; i++) {
        _real[i] = 0;
      }
      // Clear imaginary part.
      for (var i = 0; i < kFftSize; i++) {
        _imag[i] = 0;
      }

      // In-place radix-2 FFT (modifies _real / _imag).
      _fftInPlace(_real, _imag, kFftSize);

      // Accumulate power |X|² for the positive-frequency bins.
      for (var k = 0; k < kNFreqs; k++) {
        final re = _real[k];
        final im = _imag[k];
        powerSpec[k][t] = re * re + im * im;
      }
    }

    // Apply mel filter bank and log-compress → [kNMels × kNumFrames].
    const floorVal = 1e-10;
    final output = Float32List(kNMels * kNumFrames);
    for (var m = 0; m < kNMels; m++) {
      final filter = _melFilters[m];
      for (var t = 0; t < kNumFrames; t++) {
        var energy = 0.0;
        for (var k = 0; k < kNFreqs; k++) {
          energy += filter[k] * powerSpec[k][t];
        }
        output[m * kNumFrames + t] = math.log(math.max(energy, floorVal));
      }
    }

    return output;
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  /// In-place Cooley-Tukey radix-2 DIT FFT.
  ///
  /// [n] must be a power of 2. Operates purely on [Float64List] — no
  /// [Uint64List] — so it works on Flutter Web.
  static void _fftInPlace(Float64List real, Float64List imag, int n) {
    // Bit-reversal permutation.
    var j = 0;
    for (var i = 1; i < n; i++) {
      var bit = n >> 1;
      while (j & bit != 0) {
        j ^= bit;
        bit >>= 1;
      }
      j ^= bit;
      if (i < j) {
        var tmp = real[i];
        real[i] = real[j];
        real[j] = tmp;
        tmp = imag[i];
        imag[i] = imag[j];
        imag[j] = tmp;
      }
    }

    // Butterfly stages.
    var halfLen = 1;
    while (halfLen < n) {
      final len = halfLen << 1;
      final ang = -math.pi / halfLen; // -2π/len
      final wBaseRe = math.cos(ang);
      final wBaseIm = math.sin(ang);

      for (var i = 0; i < n; i += len) {
        var wRe = 1.0;
        var wIm = 0.0;
        for (var k = 0; k < halfLen; k++) {
          final uRe = real[i + k];
          final uIm = imag[i + k];
          final vRe = real[i + k + halfLen] * wRe - imag[i + k + halfLen] * wIm;
          final vIm = real[i + k + halfLen] * wIm + imag[i + k + halfLen] * wRe;
          real[i + k] = uRe + vRe;
          imag[i + k] = uIm + vIm;
          real[i + k + halfLen] = uRe - vRe;
          imag[i + k + halfLen] = uIm - vIm;
          final nextWRe = wRe * wBaseRe - wIm * wBaseIm;
          wIm = wRe * wBaseIm + wIm * wBaseRe;
          wRe = nextWRe;
        }
      }
      halfLen = len;
    }
  }

  static Float64List _buildHannWindow() {
    final w = Float64List(kNFft);
    for (var i = 0; i < kNFft; i++) {
      w[i] = 0.5 * (1.0 - math.cos(2 * math.pi * i / kNFft));
    }
    return w;
  }

  /// Builds the mel filter bank matrix of shape [kNMels × kNFreqs].
  ///
  /// Frequency resolution per bin = kSampleRate / kFftSize Hz.
  static List<Float64List> _buildMelFilterBank() {
    const fMin = 0.0;
    const fMax = kSampleRate / 2.0; // Nyquist

    // HTK mel scale.
    double hzToMel(double hz) =>
        2595.0 * math.log(1.0 + hz / 700.0) / math.ln10;
    double melToHz(double mel) => 700.0 * (math.pow(10.0, mel / 2595.0) - 1.0);

    final melMin = hzToMel(fMin);
    final melMax = hzToMel(fMax);

    // kNMels + 2 evenly-spaced mel points → convert back to Hz → FFT bins.
    final binPoints = List<double>.generate(kNMels + 2, (i) {
      final mel = melMin + (melMax - melMin) * i / (kNMels + 1);
      final hz = melToHz(mel);
      return (hz / kSampleRate * kFftSize).floorToDouble();
    });

    final filters = List<Float64List>.generate(
      kNMels,
      (_) => Float64List(kNFreqs),
    );
    for (var m = 0; m < kNMels; m++) {
      final left = binPoints[m].toInt();
      final center = binPoints[m + 1].toInt();
      final right = binPoints[m + 2].toInt();

      for (var k = left; k <= center && k < kNFreqs; k++) {
        if (center != left) filters[m][k] = (k - left) / (center - left);
      }
      for (var k = center; k <= right && k < kNFreqs; k++) {
        if (right != center) filters[m][k] = (right - k) / (right - center);
      }
    }
    return filters;
  }

  /// Centre-reflects [audio] by [padSize] samples on each end.
  static Float64List _centreReflectPad(Float32List audio, int padSize) {
    final len = audio.length;
    final out = Float64List(len + 2 * padSize);
    for (var i = 0; i < len; i++) {
      out[padSize + i] = audio[i];
    }
    // Left reflect.
    for (var i = 0; i < padSize; i++) {
      out[padSize - 1 - i] = audio[i + 1];
    }
    // Right reflect.
    for (var i = 0; i < padSize; i++) {
      out[padSize + len + i] = audio[len - 2 - i];
    }
    return out;
  }
}
