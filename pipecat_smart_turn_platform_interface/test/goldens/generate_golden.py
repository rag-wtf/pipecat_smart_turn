#!/usr/bin/env python3
"""Generate and verify the mel spectrogram golden file using upstream WhisperFeatureExtractor.

Requirements:
  pip install transformers numpy
  (or run with: uv run --with transformers --with numpy python3 generate_golden.py)

This script validates numerical parity between HuggingFace transformers
WhisperFeatureExtractor and the committed mel_spectrogram_golden.bin file.
"""

import os
import sys
import numpy as np


def generate_golden(output_path: str = "mel_spectrogram_golden.bin") -> None:
    """Generate golden binary using WhisperFeatureExtractor."""
    from transformers import WhisperFeatureExtractor

    sr = 16000
    n_samples = 128000  # 8 seconds

    # Generate 1-second 440 Hz sine wave at the end (left-padded with zeros)
    audio = np.zeros(n_samples, dtype=np.float32)
    for i in range(n_samples - sr, n_samples):
        audio[i] = np.sin(2 * np.pi * 440.0 * i / sr)

    # Apply per-utterance zero-mean / unit-variance normalization
    mean = float(np.mean(audio))
    variance = float(np.mean((audio - mean) ** 2))
    std = max(float(np.sqrt(variance)), 1e-5)
    audio_norm = (audio - mean) / std

    extractor = WhisperFeatureExtractor(
        sampling_rate=16000,
        feature_size=80,
        n_fft=400,
        hop_length=160,
        chunk_length=8,
        n_samples=128000,
        return_attention_mask=False,
    )

    features = extractor(
        audio_norm, sampling_rate=16000, return_tensors="np"
    )["input_features"]
    features_flat = features[0].flatten().astype(np.float32)

    script_dir = os.path.dirname(os.path.abspath(__file__))
    target_file = os.path.join(script_dir, output_path)

    if os.path.exists(target_file):
        existing = np.fromfile(target_file, dtype=np.float32)
        max_diff = float(np.max(np.abs(existing - features_flat)))
        print(f"Comparison with existing golden: max absolute diff = {max_diff:.2e}")
        if max_diff < 1e-4:
            print("Golden matches upstream WhisperFeatureExtractor within tolerance (1e-4).")
        else:
            print("Updating golden file with upstream WhisperFeatureExtractor output...")
            features_flat.tofile(target_file)
            print(f"Wrote {target_file} ({features_flat.nbytes} bytes).")
    else:
        features_flat.tofile(target_file)
        print(f"Generated {target_file} ({features_flat.nbytes} bytes).")


def main() -> int:
    generate_golden()
    return 0


if __name__ == "__main__":
    sys.exit(main())
