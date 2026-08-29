# Platform Configuration

Smart Turn v3 is a pure-Dart implementation that relies on `onnxruntime` for native inference. The `smart-turn-v3.2-cpu.onnx` model (8.7 MB) is bundled with the package and extracted automatically on first initialization. You can optionally supply a custom model path via `SmartTurnConfig.customModelPath`.

## Recommended File Handling

When supplying a custom model file at runtime, we recommend using the [path_provider](https://pub.dev/packages/path_provider) package to manage device-agnostic file paths.

### 1. Custom Model Storage

Place your custom `.onnx` model in your application's `assets` folder or download it at runtime.

### 2. Accessing the Model Path

```dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pipecat_smart_turn/pipecat_smart_turn.dart';

Future<void> initSmartTurn() async {
  // Get the application documents directory
  final directory = await getApplicationDocumentsDirectory();
  final modelPath = '${directory.path}/smart-turn-v3.2-cpu.onnx';

  // Ensure the model exists at this path
  if (!await File(modelPath).exists()) {
    // Download or copy from assets here
  }

  final config = SmartTurnConfig(
    customModelPath: modelPath,
  );

  final detector = SmartTurnDetector(config: config);
  await detector.initialize();
}
```

## Android Requirements

- **Min SDK**: 21 (required by `onnxruntime`)
- **Memory**: Ensure your app has sufficient heap for the ~8.7MB model.

## iOS Requirements

- **Deployment Target**: 13.0+
- **Background Modes**: If processing audio in the background, ensure 'Audio, AirPlay, and Picture in Picture' is enabled.
