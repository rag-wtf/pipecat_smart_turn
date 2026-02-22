# Model Acquisition

Smart Turn v3 requires a specific ONNX model to function. The model is not included in the package to keep the package size small and allow for versioning independent of the code.

## Official Models

| Model Version | Precision | Size | Hash (SHA-256) | Best For |
|---------------|-----------|------|----------------|----------|
| v3.0          | int8      | 8.7MB| `...`          | Mobile CPU (Android/iOS) |
| v3.0          | fp16      | 17MB | `...`          | GPU / High-end Mobile |

> [!IMPORTANT]
> Always use the **int8** quantized model for production mobile applications to reduce latency and memory pressure.

## Downloading the Model

You can find the official releases on the [Daily.co Smart Turn repository](https://github.com/daily-co/smart-turn).

### Checksum Verification

After downloading the model, verify its integrity:

```bash
sha256sum smart_turn_v3_int8.onnx
```

## Bundling with Assets (Optional)

If you wish to bundle the model with your app:

1. Add it to `pubspec.yaml`:
   ```yaml
   flutter:
     assets:
       - assets/models/smart_turn_v3.onnx
   ```

2. Copy it to the local file system at runtime (required since `onnxruntime` needs a `File` path):
   ```dart
   final data = await rootBundle.load('assets/models/smart_turn_v3.onnx');
   final bytes = data.buffer.asUint8List();
   await File(localPath).writeAsBytes(bytes);
   ```
