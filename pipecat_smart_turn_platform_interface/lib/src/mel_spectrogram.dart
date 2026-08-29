import 'dart:math' as math;
import 'dart:typed_data';

/// Computes a Whisper-compatible log-mel spectrogram from raw audio.
///
/// Parameters match the Smart Turn v3.x model preprocessing:
/// - Sample rate: 16 kHz
/// - Window size (n_fft): 400 samples (25 ms)
/// - FFT size: 400 (matches n_fft for Whisper parity)
/// - Hop length: 160 samples (10 ms)
/// - Mel bands (n_mels): 80
/// - Centering: true (reflects n_fft/2 = 200 samples on each side)
///
/// For 128,000 input samples this produces a flat [Float32List] of
/// length 80 x 800 = 64,000 values, logically shaped [80, 800].
///
/// Uses a pure-Dart mixed-radix 16x25 Cooley-Tukey FFT with precomputed
/// trigonometric tables and a sparse mel filter bank. This provides exact
/// mathematical parity with WhisperFeatureExtractor while reducing compute
/// latency to well within mobile real-time budgets (< 100 ms).
class MelSpectrogram {
  // coverage:ignore-start
  MelSpectrogram._();
  // coverage:ignore-end

  /// Sample rate of the input audio (Hz).
  static const int kSampleRate = 16000;

  /// Analysis window length in samples (25 ms @ 16 kHz).
  static const int kNFft = 400;

  /// FFT size — exactly n_fft for Whisper.
  static const int kFftSize = 400;

  /// Number of samples between successive frames (10 ms @ 16 kHz).
  static const int kHopLength = 160;

  /// Number of mel filter banks.
  static const int kNMels = 80;

  /// Number of time frames produced for 128,000 input samples with centering.
  static const int kNumFrames = 800;

  /// Number of unique FFT frequency bins = kFftSize / 2 + 1.
  static const int kNFreqs = kFftSize ~/ 2 + 1; // 201

  /// First 2D FFT factorization radix dimension (16 x 25 = 400).
  static const int kFftRadix1 = 16;

  /// Second 2D FFT factorization radix dimension (16 x 25 = 400).
  static const int kFftRadix2 = 25;

  // Cached Hann window (length kNFft).
  static final Float64List _hannWindow = _buildHannWindow();

  // Cached sparse mel filter bank [kNMels].
  static final List<_SparseMelFilter> _sparseMelFilters =
      _buildSparseMelFilters();

  // Precomputed Cooley-Tukey 16x25 FFT tables
  static final Float64List _cos16 = _buildCos16();
  static final Float64List _sin16 = _buildSin16();
  static final Float64List _twiddleCos = _buildTwiddleCos();
  static final Float64List _twiddleSin = _buildTwiddleSin();
  static final Float64List _cos25 = _buildCos25();
  static final Float64List _sin25 = _buildSin25();

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

    // Power spectrogram [kNumFrames * kNFreqs] in frame-major order.
    final powerSpec = Float64List(kNumFrames * kNFreqs);

    final x2Re = Float64List(16 * 25);
    final x2Im = Float64List(16 * 25);

    for (var t = 0; t < kNumFrames; t++) {
      final start = t * kHopLength;
      final tOffset = t * kNFreqs;

      // 16-point DFT along columns + twiddle multiplication
      for (var n2 = 0; n2 < 25; n2++) {
        for (var k1 = 0; k1 < 16; k1++) {
          var sRe = 0.0;
          var sIm = 0.0;
          final offset16 = k1 * 16;
          for (var n1 = 0; n1 < 16; n1++) {
            final n = n1 * 25 + n2;
            final val = padded[start + n] * _hannWindow[n];
            sRe += val * _cos16[offset16 + n1];
            sIm += val * _sin16[offset16 + n1];
          }
          final twIdx = k1 * 25 + n2;
          final twC = _twiddleCos[twIdx];
          final twS = _twiddleSin[twIdx];
          x2Re[twIdx] = sRe * twC - sIm * twS;
          x2Im[twIdx] = sRe * twS + sIm * twC;
        }
      }

      // 25-point DFT along rows (only for positive frequency bins k < 201)
      for (var k1 = 0; k1 < 16; k1++) {
        final rowOffset = k1 * 25;
        for (var k2 = 0; k2 < 25; k2++) {
          final k = k1 + 16 * k2;
          if (k < kNFreqs) {
            var sRe = 0.0;
            var sIm = 0.0;
            final offset25 = k2 * 25;
            for (var n2 = 0; n2 < 25; n2++) {
              final re = x2Re[rowOffset + n2];
              final im = x2Im[rowOffset + n2];
              final c = _cos25[offset25 + n2];
              final s = _sin25[offset25 + n2];
              sRe += re * c - im * s;
              sIm += re * s + im * c;
            }
            powerSpec[tOffset + k] = sRe * sRe + sIm * sIm;
          }
        }
      }
    }

    // Apply sparse mel filter bank and log10-compress → [kNMels × kNumFrames].
    const floorVal = 1e-10;
    final output = Float32List(kNMels * kNumFrames);
    var maxVal = double.negativeInfinity;

    for (var m = 0; m < kNMels; m++) {
      final filter = _sparseMelFilters[m];
      final startBin = filter.startBin;
      final weights = filter.weights;
      final wLen = weights.length;
      final mOffset = m * kNumFrames;

      for (var t = 0; t < kNumFrames; t++) {
        var energy = 0.0;
        final tOffset = t * kNFreqs + startBin;
        for (var i = 0; i < wLen; i++) {
          energy += weights[i] * powerSpec[tOffset + i];
        }
        final val = math.log(math.max(energy, floorVal)) / math.ln10;
        output[mOffset + t] = val;
        if (val > maxVal) {
          maxVal = val;
        }
      }
    }

    // Whisper scaling: clamp to max - 8, then (x + 4) / 4
    final clampMin = maxVal - 8.0;
    for (var i = 0; i < output.length; i++) {
      var val = output[i];
      if (val < clampMin) val = clampMin;
      output[i] = (val + 4.0) / 4.0;
    }

    return output;
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  static Float64List _buildCos16() {
    final table = Float64List(16 * 16);
    for (var k = 0; k < 16; k++) {
      for (var n = 0; n < 16; n++) {
        table[k * 16 + n] = math.cos(-2 * math.pi * k * n / 16);
      }
    }
    return table;
  }

  static Float64List _buildSin16() {
    final table = Float64List(16 * 16);
    for (var k = 0; k < 16; k++) {
      for (var n = 0; n < 16; n++) {
        table[k * 16 + n] = math.sin(-2 * math.pi * k * n / 16);
      }
    }
    return table;
  }

  static Float64List _buildTwiddleCos() {
    final table = Float64List(16 * 25);
    for (var k1 = 0; k1 < 16; k1++) {
      for (var n2 = 0; n2 < 25; n2++) {
        table[k1 * 25 + n2] = math.cos(-2 * math.pi * k1 * n2 / kFftSize);
      }
    }
    return table;
  }

  static Float64List _buildTwiddleSin() {
    final table = Float64List(16 * 25);
    for (var k1 = 0; k1 < 16; k1++) {
      for (var n2 = 0; n2 < 25; n2++) {
        table[k1 * 25 + n2] = math.sin(-2 * math.pi * k1 * n2 / kFftSize);
      }
    }
    return table;
  }

  static Float64List _buildCos25() {
    final table = Float64List(25 * 25);
    for (var k = 0; k < 25; k++) {
      for (var n = 0; n < 25; n++) {
        table[k * 25 + n] = math.cos(-2 * math.pi * k * n / 25);
      }
    }
    return table;
  }

  static Float64List _buildSin25() {
    final table = Float64List(25 * 25);
    for (var k = 0; k < 25; k++) {
      for (var n = 0; n < 25; n++) {
        table[k * 25 + n] = math.sin(-2 * math.pi * k * n / 25);
      }
    }
    return table;
  }

  static Float64List _buildHannWindow() {
    final w = Float64List(kNFft);
    for (var i = 0; i < kNFft; i++) {
      w[i] = 0.5 * (1.0 - math.cos(2 * math.pi * i / kNFft));
    }
    return w;
  }

  /// Builds sparse mel filter representations for fast evaluation.
  static List<_SparseMelFilter> _buildSparseMelFilters() {
    const fMin = 0.0;
    const fMax = 8000.0; // Nyquist
    const minLogHz = 1000.0;
    const fSp = 200.0 / 3.0; // 66.6666666...
    const minLogMel = (minLogHz - fMin) / fSp;
    final logStep = math.log(6.4) / 27.0;

    double hzToMel(double hz) {
      if (hz >= minLogHz) {
        return minLogMel + math.log(hz / minLogHz) / logStep;
      } else {
        return (hz - fMin) / fSp;
      }
    }

    double melToHz(double mel) {
      if (mel >= minLogMel) {
        return minLogHz * math.exp(logStep * (mel - minLogMel));
      } else {
        return fMin + fSp * mel;
      }
    }

    final melMin = hzToMel(fMin);
    final melMax = hzToMel(fMax);

    final fPoints = List<double>.generate(kNMels + 2, (i) {
      final mel = melMin + (melMax - melMin) * i / (kNMels + 1);
      return melToHz(mel);
    });

    final fftFreqs = List<double>.generate(kNFreqs, (i) {
      return i * kSampleRate / kFftSize;
    });

    final list = <_SparseMelFilter>[];

    for (var m = 0; m < kNMels; m++) {
      final leftHz = fPoints[m];
      final centerHz = fPoints[m + 1];
      final rightHz = fPoints[m + 2];
      final enorm = 2.0 / (rightHz - leftHz);

      var startBin = -1;
      final tempWeights = <double>[];

      for (var k = 0; k < kNFreqs; k++) {
        final hz = fftFreqs[k];
        if (leftHz <= hz && hz <= rightHz) {
          if (startBin == -1) startBin = k;
          var weight = 0.0;
          if (hz <= centerHz) {
            weight = (hz - leftHz) / (centerHz - leftHz);
          } else {
            weight = (rightHz - hz) / (rightHz - centerHz);
          }
          tempWeights.add(weight * enorm);
        } else if (startBin != -1) {
          break;
        }
      }

      if (startBin == -1) {
        startBin = 0;
        tempWeights.add(0);
      }

      final wList = Float64List(tempWeights.length);
      for (var i = 0; i < tempWeights.length; i++) {
        wList[i] = tempWeights[i];
      }
      list.add(_SparseMelFilter(startBin, wList));
    }
    return list;
  }

  /// Centre-reflects [audio] by [padSize] samples on each end.
  static Float64List _centreReflectPad(Float32List audio, int padSize) {
    if (audio.length < padSize + 2) {
      throw ArgumentError('Audio too short for padding (len < ${padSize + 2})');
    }
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

class _SparseMelFilter {
  _SparseMelFilter(this.startBin, this.weights);
  final int startBin;
  final Float64List weights;
}
