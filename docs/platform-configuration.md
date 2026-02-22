# Platform Configuration

Smart Turn v3 is a pure-Dart implementation, but it relies on `onnxruntime` for native inference. Because the ONNX model is not bundled with the package, you must provide an absolute file path to the model on the device.

## Recommended File Handling

We recommend using the [path_provider](https://pub.dev/packages/path_provider) package to manage device-agnostic file paths.

### 1. Model Storage

Place your `.onnx` model in your application's `assets` folder or download it at runtime.

### 2. Accessing the Model Path

```dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pipecat_smart_turn/pipecat_smart_turn.dart';

Future<void> initSmartTurn() async {
  // Get the application documents directory
  final directory = await getApplicationDocumentsDirectory();
  final modelPath = '${directory.path}/smart_turn_v3.onnx';

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

- **Deployment Target**: 12.0+
- **Background Modes**: If processing audio in the background, ensure 'Audio, AirPlay, and Picture in Picture' is enabled.
