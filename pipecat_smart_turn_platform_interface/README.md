# pipecat_smart_turn_platform_interface

[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]

A common platform interface for the `pipecat_smart_turn` package.

This package contains the core implementation of the Smart Turn v3 semantic VAD, including:
- **Audio Preprocessing**: Padding, fade-ins, and format conversion.
- **Isolate Management**: Background threading for ONNX inference.
- **VAD Logic**: Energy-based VAD for speech detection.
- **ONNX Session**: Native inference management.

## Architecture

Smart Turn follows a federated plugin structure, but unlike traditional plugins, the core logic is contained within this platform interface to allow for cross-isolate usage and easier testing of pure-Dart logic.

[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis