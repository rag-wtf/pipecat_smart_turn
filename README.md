# pipecat_smart_turn

[![Very Good Ventures][logo_white]][very_good_ventures_link_dark]
[![Very Good Ventures][logo_black]][very_good_ventures_link_light]

Developed with 💙 by [Very Good Ventures][very_good_ventures_link] 🦄

![coverage][coverage_badge]
[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: BSD-2][license_badge]][license_link]

On-device Semantic Voice Activity Detection (VAD) for Flutter, powered by Smart Turn v3.

## Features

- **Semantic Intelligence**: Predicts the end of a speaking turn based on audio semantics, not just silence.
- **Ultra-low Latency**: Optimized for real-time applications with background isolate inference.
- **Zero-Copy Transfers**: Efficiently moves audio data between main UI and background workers.
- **Dynamic Adaptation**: Noise floor tracking for robust performance in noisy environments.

## Getting Started

1. **Acquire the Model**: Smart Turn requires an ONNX model file. Follow the [Model Acquisition Guide](docs/model-acquisition.md).
2. **Platform Setup**: Configure your platform-specific path handling. See [Platform Configuration](docs/platform-configuration.md).

## Quick Start

```dart
final config = SmartTurnConfig(
  customModelPath: '/path/to/smart_turn_v3.onnx',
);

final detector = SmartTurnDetector(config: config);
await detector.initialize();

// In your audio processing loop:
final result = await detector.predict(audioSamples);
if (result?.isComplete ?? false) {
  print('Turn finished! Confidence: ${result!.confidence}');
}
```

[coverage_badge]: pipecat_smart_turn/coverage_badge.svg
[license_badge]: https://img.shields.io/badge/license-BSD-2.svg
[license_link]: https://opensource.org/licenses/BSD-2-Clause
[logo_black]: https://raw.githubusercontent.com/VGVentures/very_good_brand/main/styles/README/vgv_logo_black.png#gh-light-mode-only
[logo_white]: https://raw.githubusercontent.com/VGVentures/very_good_brand/main/styles/README/vgv_logo_white.png#gh-dark-mode-only
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
[very_good_ventures_link]: https://verygood.ventures/?utm_source=github&utm_medium=banner&utm_campaign=core
[very_good_ventures_link_dark]: https://verygood.ventures/?utm_source=github&utm_medium=banner&utm_campaign=core#gh-dark-mode-only
[very_good_ventures_link_light]: https://verygood.ventures/?utm_source=github&utm_medium=banner&utm_campaign=core#gh-light-mode-only