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

  // Cached Hann window (length kNFft, zero-padded inline when applied).
  static final Float64List _hannWindow = _buildHannWindow();

  // Cached mel filter bank [kNMels × kNFreqs].
  static final List<Float64List> _melFilters = _buildMelFilterBank();

  static final Float64List _cosTable = _buildCosTable();
  static final Float64List _sinTable = _buildSinTable();

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

    final realBuffer = Float64List(kFftSize);
    final outRealBuffer = Float64List(kNFreqs);
    final outImagBuffer = Float64List(kNFreqs);

    for (var t = 0; t < kNumFrames; t++) {
      final start = t * kHopLength;

      // Fill realBuffer with windowed frame.
      for (var i = 0; i < kNFft; i++) {
        realBuffer[i] = padded[start + i] * _hannWindow[i];
      }

      // Compute DFT (input is real-only).
      _computeDft(realBuffer, outRealBuffer, outImagBuffer);

      // Accumulate power |X|² for the positive-frequency bins.
      for (var k = 0; k < kNFreqs; k++) {
        final re = outRealBuffer[k];
        final im = outImagBuffer[k];
        powerSpec[k][t] = re * re + im * im;
      }
    }

    // Apply mel filter bank and log10-compress → [kNMels × kNumFrames].
    const floorVal = 1e-10;
    final output = Float32List(kNMels * kNumFrames);
    var maxVal = double.negativeInfinity;

    for (var m = 0; m < kNMels; m++) {
      final filter = _melFilters[m];
      for (var t = 0; t < kNumFrames; t++) {
        var energy = 0.0;
        for (var k = 0; k < kNFreqs; k++) {
          energy += filter[k] * powerSpec[k][t];
        }
        final val = math.log(math.max(energy, floorVal)) / math.ln10;
        output[m * kNumFrames + t] = val;
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

  static Float64List _buildCosTable() {
    final table = Float64List(kNFreqs * kFftSize);
    for (var k = 0; k < kNFreqs; k++) {
      for (var n = 0; n < kFftSize; n++) {
        table[k * kFftSize + n] = math.cos(-2 * math.pi * k * n / kFftSize);
      }
    }
    return table;
  }

  static Float64List _buildSinTable() {
    final table = Float64List(kNFreqs * kFftSize);
    for (var k = 0; k < kNFreqs; k++) {
      for (var n = 0; n < kFftSize; n++) {
        table[k * kFftSize + n] = math.sin(-2 * math.pi * k * n / kFftSize);
      }
    }
    return table;
  }

  static void _computeDft(Float64List real, Float64List outReal, Float64List outImag) {
    for (var k = 0; k < kNFreqs; k++) {
      var sumRe = 0.0;
      var sumIm = 0.0;
      final offset = k * kFftSize;
      for (var n = 0; n < kFftSize; n++) {
        final val = real[n];
        sumRe += val * _cosTable[offset + n];
        sumIm += val * _sinTable[offset + n];
      }
      outReal[k] = sumRe;
      outImag[k] = sumIm;
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
  /// Uses Slaney area normalization and Slaney mel scale.
  static List<Float64List> _buildMelFilterBank() {
    const fMin = 0.0;
    const fMax = 8000.0; // Nyquist
    const minLogHz = 1000.0;
    const fSp = 200.0 / 3.0; // 66.6666666...
    final minLogMel = (minLogHz - fMin) / fSp;
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

    // kNMels + 2 evenly-spaced mel points → convert back to Hz
    final fPoints = List<double>.generate(kNMels + 2, (i) {
      final mel = melMin + (melMax - melMin) * i / (kNMels + 1);
      return melToHz(mel);
    });

    final fftFreqs = List<double>.generate(kNFreqs, (i) {
      return i * kSampleRate / kFftSize;
    });

    final filters = List<Float64List>.generate(
      kNMels,
      (_) => Float64List(kNFreqs),
    );

    for (var m = 0; m < kNMels; m++) {
      final leftHz = fPoints[m];
      final centerHz = fPoints[m + 1];
      final rightHz = fPoints[m + 2];

      for (var k = 0; k < kNFreqs; k++) {
        final hz = fftFreqs[k];
        if (leftHz <= hz && hz <= rightHz) {
          double weight = 0.0;
          if (hz <= centerHz) {
            weight = (hz - leftHz) / (centerHz - leftHz);
          } else {
            weight = (rightHz - hz) / (rightHz - centerHz);
          }
          filters[m][k] = weight;
        }
      }

      // Slaney area normalization
      final enorm = 2.0 / (rightHz - leftHz);
      for (var k = 0; k < kNFreqs; k++) {
        filters[m][k] *= enorm;
      }
    }
    return filters;
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
