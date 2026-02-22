# Smart Turn Flutter Package: Comprehensive Build & Release Guide

> **What you're building:** A production-ready Flutter package that brings Smart Turn v3's on-device semantic VAD (Voice Activity Detection) — the same model powering Pipecat Cloud — directly to mobile, desktop, and web Flutter applications.
>
> **Note:** This implementation is optimized for elite mobile performance, featuring zero-allocation memory management, zero-copy threading, dynamic signal processing, and battery-optimized inference.

---

## Table of Contents

1. [Understanding the Model Before You Write a Line of Code](#1-understanding-the-model)
2. [Architecture Decisions: How the Package Will Work](#2-architecture-decisions)
3. [Project Setup & Repository Structure](#3-project-setup--repository-structure)
4. [Acquiring & Preparing the ONNX Model Files](#4-acquiring--preparing-the-onnx-model-files)
5. [Core Dart API Design](#5-core-dart-api-design)
6. [Audio Preprocessing Pipeline (Signal Processing)](#6-audio-preprocessing-pipeline)
7. [ONNX Inference Integration (Zero-Copy & Thermal Opts)](#7-onnx-inference-integration)
8. [VAD Integration (Dynamic Noise & Multi-Poll)](#8-vad-integration)
9. [Platform-Specific Configuration](#9-platform-specific-configuration)
10. [Complete Implementation (Backpressure Handled)](#10-complete-implementation)
11. [Testing Strategy](#11-testing-strategy)
12. [Performance Optimization](#12-performance-optimization)
13. [Example App (Reactive & Lifecycle-Aware)](#13-example-app)
14. [Documentation & API Reference](#14-documentation--api-reference)
15. [Publishing to pub.dev (CI/CD Checksums)](#15-publishing-to-pubdev)
16. [Post-Release Maintenance](#16-post-release-maintenance)

---

## 1. Understanding the Model

Before writing a single line of Dart, you must deeply internalize what Smart Turn v3 is. Building the wrong abstraction is expensive.

### 1.1 What Smart Turn v3 Actually Does

Smart Turn is a binary audio classifier. It answers one question: *"Has the user finished speaking their turn?"*

It is **NOT** a transcription model. It operates entirely on raw waveform data, which means it captures prosodic cues (intonation, rhythm, fillers like "um...") that transcription misses entirely.

The model architecture is:

- **Backbone:** Whisper Tiny encoder layers only (frozen, used as a feature extractor — not the full Whisper Tiny model)
- **Head:** Shallow linear classifier
- **Total Parameters:** ~8M (encoder layers + classification head combined)
- **Export format:** ONNX

> **Clarification on parameters:** The full Whisper Tiny model contains ~39M parameters. Smart Turn v3 uses only the *encoder* portion as its backbone feature extractor (frozen weights), combined with a lightweight linear classification head — totalling approximately 8M parameters for the complete ONNX export.

For Flutter on mobile, always use the CPU int8 variant (~8.7 MB).

### 1.2 Exact Input Specification

This is the most critical section of this entire guide. Getting the input format wrong produces silently incorrect results.

```
Input format:
- Sample rate:    16,000 Hz (16 kHz)
- Channels:       Mono (1 channel)
- Encoding:       PCM float32
- Duration:       Up to 8 seconds maximum
- Sample count:   Up to 128,000 samples (8s × 16,000 Hz)
- Padding:        Zero-pad at the BEGINNING (not the end)
- Shape:          [1, 128000] — batch size 1, 128,000 samples
```

**Critical padding rule:** If the user speaks for only 3 seconds (48,000 samples), you do NOT trim to 48,000 samples. You create a 128,000-sample array, fill the FIRST 80,000 positions with zeros, and put the 48,000 audio samples at the END.

### 1.3 Output Specification & Workflow

The model outputs two logits representing:

- `logit[0]`: Score for "NOT complete" (user is still speaking)
- `logit[1]`: Score for "COMPLETE" (user has finished their turn)

Apply softmax to get probabilities, then threshold at 0.5 (or configurable) on `logit[1]`.

Smart Turn is not a standalone solution. It runs **after** a basic VAD detects silence. It only runs during silence periods, preserving CPU/battery.

---

## 2. Architecture Decisions

These decisions directly shape everything downstream.

### 2.1 Package Topology: Pure Dart vs. Plugin

**Decision:** Dart-first plugin with native ONNX bridges.

Depend on the **`onnxruntime`** package (v1.3.1+). It handles iOS/Android/macOS/Linux/Windows native FFI implementations out-of-the-box via direct ONNX Runtime bindings.

> ⚠️ **Critical: Two packages share similar names on pub.dev — do not confuse them.**
>
> | Package | Publisher | API Style | Use for this guide? |
> |---|---|---|---|
> | `onnxruntime` | gtbluesky | `OrtSession`, `OrtValueTensor`, `OrtSessionOptions` | ✅ **YES** |
> | `flutter_onnxruntime` | masic.ai | `OnnxRuntime()`, `OrtValue.fromList()`, `createSessionFromAsset()` | ❌ **NO** |
>
> Every code example in this guide uses the `onnxruntime` API. Substituting `flutter_onnxruntime` will cause compile-time failures throughout.

### 2.2 Model Bundling Strategy

**Decision:** Avoid binary bloat — support external loading.

Bundling the ~8.7 MB CPU model as a package asset adds that weight to every consumer's app permanently. **Solution:** Provide a `customModelPath` override parameter. Allow consumers to download the model dynamically to their app's documents directory.

### 2.3 Threading Model

**Decision:** Dart Isolate with Zero-Copy messaging.

ONNX inference is CPU-intensive. Run it on a persistent Isolate. We will use `TransferableTypedData` to pass the 512KB audio buffers across the isolate boundary to prevent deep copying, UI thread locking, and Garbage Collection (GC) fragmentation.

---

## 3. Project Setup & Repository Structure

### 3.1 Create the Package

```bash
flutter create --template=package --org=com.yourorg smart_turn_dart
cd smart_turn_dart
```

### 3.2 `pubspec.yaml`

```yaml
name: smart_turn_dart
description: >
  On-device semantic turn detection for voice AI applications.
  Uses the Smart Turn v3 ONNX model to detect when a user has
  finished speaking, supporting 23 languages with 8-100ms latency.
version: 0.1.0
homepage: https://github.com/yourorg/smart_turn_dart

environment:
  sdk: ">=3.3.0 <4.0.0"
  flutter: ">=3.19.0"

dependencies:
  flutter:
    sdk: flutter
  onnxruntime: ^1.3.1        # ✅ CORRECT: 'onnxruntime' package by gtbluesky

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
```

> **Correction:** The original guide specified `flutter_onnxruntime: ^1.6.0`. This is a different package with a completely incompatible API. All code in this guide requires the `onnxruntime` package. See Section 2.1 for the full comparison.

---

## 4. Acquiring & Preparing the ONNX Model Files

Download the model and record the exact SHA-256 hash. We will use this in our CI pipeline to prevent corrupted publishes.

```bash
# Download using HuggingFace CLI
pip install huggingface_hub

# Download the CPU-optimized int8 model (recommended for mobile)
huggingface-cli download pipecat-ai/smart-turn-v3 \
  smart-turn-v3.1-cpu.onnx \
  --local-dir ./assets/models/

# Record file size and SHA-256 for integrity checks
ls -lh assets/models/smart-turn-v3.1-cpu.onnx
shasum -a 256 assets/models/smart-turn-v3.1-cpu.onnx
```

> **Note on repo contents:** The HuggingFace repo (`pipecat-ai/smart-turn-v3`) contains multiple files including older `v3.0` variants and a `smart-turn-v3.1-gpu.onnx` (fp32, ~32 MB for GPU inference). The command above downloads only the correct CPU variant. The CPU int8 model is approximately **8.68–8.76 MB**.

**Save the SHA-256 hash output now.** You will paste it into the CI script in Step 15. Do not skip this step.

---

## 5. Core Dart API Design

### 5.1 `smart_turn_config.dart`

```dart
/// Configuration for the Smart Turn detector.
class SmartTurnConfig {
  /// Probability threshold above which a turn is considered complete.
  /// Range: 0.0-1.0. Default 0.5 (equal probability).
  final double completionThreshold;

  /// Maximum audio duration to feed to the model, in seconds.
  ///
  /// **Note:** This field is validated but the preprocessor currently always
  /// uses the model's hard-coded maximum of 8.0 seconds (128,000 samples at
  /// 16kHz). A value less than 8.0 would require truncating the audio before
  /// calling [AudioPreprocessor.prepareInput]. If you want to limit audio
  /// length, slice [audioSamples] before calling [SmartTurnDetector.predict].
  /// This field is retained for forward compatibility with future model
  /// versions that may support shorter context windows.
  final double maxAudioSeconds;

  /// Path to a custom ONNX model file. Highly recommended to keep app
  /// size small by downloading the model to the app's documents directory.
  final String? customModelPath;

  /// Number of CPU threads for ONNX inference. Default 1 is optimal
  /// for mobile (see Performance section for rationale).
  final int cpuThreadCount;

  /// Whether to run inference in a separate Dart isolate (recommended true).
  final bool useIsolate;

  const SmartTurnConfig({
    this.completionThreshold = 0.5,
    this.maxAudioSeconds = 8.0,
    this.customModelPath,
    this.cpuThreadCount = 1,
    this.useIsolate = true,
  })  : assert(completionThreshold >= 0.0 && completionThreshold <= 1.0),
        assert(maxAudioSeconds > 0.0 && maxAudioSeconds <= 8.0),
        assert(cpuThreadCount >= 1);
}
```

### 5.2 `smart_turn_result.dart`

```dart
/// The result of a Smart Turn inference pass.
class SmartTurnResult {
  final bool isComplete;
  final double confidence;
  final int latencyMs;
  final int audioLengthMs;

  double get incompleteConfidence => 1.0 - confidence;

  const SmartTurnResult({
    required this.isComplete,
    required this.confidence,
    required this.latencyMs,
    required this.audioLengthMs,
  });

  @override
  String toString() =>
      'SmartTurnResult(isComplete=$isComplete, '
      'confidence=${confidence.toStringAsFixed(3)}, '
      'latency=${latencyMs}ms, audio=${audioLengthMs}ms)';
}
```

### 5.3 `exceptions.dart`

```dart
sealed class SmartTurnException implements Exception {
  final String message;
  const SmartTurnException(this.message);
  @override String toString() => '$runtimeType: $message';
}

final class SmartTurnNotInitializedException extends SmartTurnException {
  const SmartTurnNotInitializedException() : super('Call initialize() first.');
}

final class SmartTurnModelLoadException extends SmartTurnException {
  const SmartTurnModelLoadException(super.message);
}

final class SmartTurnInferenceException extends SmartTurnException {
  const SmartTurnInferenceException(super.message);
}
```

### 5.4 `math_utils.dart`

`softmax2` is extracted into its own exported file so that it is accessible via the public API (needed by tests and by any consumer who wants to interpret raw logits directly). Keeping it in `onnx_inference.dart` would make it inaccessible through the barrel export without also exposing internal session classes.

```dart
import 'dart:math' as math;

/// Numerically stable softmax over 2 logits.
///
/// Subtracts the maximum logit before exponentiating to prevent
/// floating-point overflow on large logit values.
///
/// Returns a record of (probability_class_0, probability_class_1)
/// whose values sum to 1.0.
///
/// Example:
/// ```dart
/// final (pIncomplete, pComplete) = softmax2(logit0, logit1);
/// ```
(double, double) softmax2(double logit0, double logit1) {
  final maxLogit = math.max(logit0, logit1);
  final exp0 = math.exp(logit0 - maxLogit);
  final exp1 = math.exp(logit1 - maxLogit);
  final sum = exp0 + exp1;
  return (exp0 / sum, exp1 / sum);
}
```

---

## 6. Audio Preprocessing Pipeline

This section addresses critical signal processing requirements: a fade-in window to prevent transients, and a circular ring buffer to eliminate memory fragmentation.

### 6.1 `audio_preprocessor.dart`

```dart
import 'dart:typed_data';
import 'dart:math' as math;

/// Prepares raw audio data for input into the Smart Turn v3 ONNX model.
class AudioPreprocessor {
  static const int kSampleRate = 16000;
  static const int kMaxDurationSeconds = 8;
  static const int kMaxSamples = kSampleRate * kMaxDurationSeconds; // 128,000

  /// Prepares [audioSamples] (float32, 16kHz mono PCM) for model input.
  ///
  /// Applies left-zero-padding (beginning) to reach [kMaxSamples] length,
  /// and a 5ms fade-in to suppress transient artifacts at the padding boundary.
  static Float32List prepareInput(Float32List audioSamples) {
    final output = Float32List(kMaxSamples);

    if (audioSamples.length >= kMaxSamples) {
      // Audio is at or over max: take only the last 128,000 samples
      final offset = audioSamples.length - kMaxSamples;
      output.setRange(0, kMaxSamples, audioSamples, offset);
    } else {
      // Left-pad with zeros, place audio at the end
      final paddingLength = kMaxSamples - audioSamples.length;
      output.setRange(paddingLength, kMaxSamples, audioSamples);

      // Apply a 5ms fade-in (80 samples) to prevent a mathematically
      // instantaneous transient (click) when transitioning from 0.0 padding
      // to the first audio sample. Transients severely confuse Whisper's
      // convolutional feature extractors.
      const fadeSamples = 80;
      for (var i = 0; i < fadeSamples && i < audioSamples.length; i++) {
        output[paddingLength + i] *= (i / fadeSamples);
      }
    }

    return output;
  }

  /// Converts int16 PCM samples to normalized float32 in range [-1.0, 1.0].
  static Float32List int16ToFloat32(Int16List int16Samples) {
    final output = Float32List(int16Samples.length);
    for (var i = 0; i < int16Samples.length; i++) {
      output[i] = int16Samples[i] / 32768.0;
    }
    return output;
  }

  /// Converts a raw byte buffer (int16 PCM) to float32.
  static Float32List bytesToFloat32(Uint8List bytes) {
    if (bytes.length % 2 != 0) throw ArgumentError('Buffer length must be even');
    return int16ToFloat32(bytes.buffer.asInt16List());
  }

  /// Mixes stereo float32 PCM to mono by averaging channels.
  static Float32List stereoToMono(Float32List stereoSamples) {
    final monoLength = stereoSamples.length ~/ 2;
    final mono = Float32List(monoLength);
    for (var i = 0; i < monoLength; i++) {
      mono[i] = (stereoSamples[i * 2] + stereoSamples[i * 2 + 1]) / 2.0;
    }
    return mono;
  }

  /// Linear interpolation resampler. For fallback use only.
  ///
  /// WARNING: Linear decimation causes high-frequency aliasing above the
  /// Nyquist frequency of the output rate. In production, strongly advise
  /// users to capture at 16kHz natively or use an OS-level resampler via
  /// platform channels.
  static Float32List resampleFallback(Float32List samples, int sourceRate) {
    if (sourceRate == kSampleRate) return samples;
    final ratio = sourceRate / kSampleRate;
    final outputLength = (samples.length / ratio).floor();
    final output = Float32List(outputLength);
    for (var i = 0; i < outputLength; i++) {
      final srcPos = i * ratio;
      final srcIdx = srcPos.floor();
      final frac = srcPos - srcIdx;
      if (srcIdx + 1 < samples.length) {
        output[i] = samples[srcIdx] * (1.0 - frac) + samples[srcIdx + 1] * frac;
      } else {
        output[i] = samples[srcIdx];
      }
    }
    return output;
  }

  /// Computes the Root Mean Square energy of a sample frame.
  static double computeRms(Float32List samples) {
    if (samples.isEmpty) return 0.0;
    var sum = 0.0;
    for (final sample in samples) sum += sample * sample;
    return math.sqrt(sum / samples.length);
  }

  /// Converts a sample count to milliseconds at 16kHz.
  static int sampleCountToMs(int sampleCount) =>
      (sampleCount * 1000 / kSampleRate).round();
}
```

### 6.2 `audio_buffer.dart` (Zero-Allocation Ring Buffer)

```dart
import 'dart:typed_data';

/// A zero-allocation circular buffer for streaming audio.
///
/// Prevents GC churn and memory fragmentation during real-time audio capture
/// by reusing a fixed-size backing Float32List. Only allocates when
/// [toFloat32List] is explicitly called.
class AudioBuffer {
  final int maxSamples;
  final Float32List _buffer;
  int _head = 0;
  int _count = 0;

  AudioBuffer({int maxSeconds = 8})
      : maxSamples = maxSeconds * 16000,
        _buffer = Float32List(maxSeconds * 16000);

  /// Appends [newSamples] without allocating new memory blocks.
  /// When the buffer is full, the oldest samples are silently overwritten.
  void append(Float32List newSamples) {
    for (var i = 0; i < newSamples.length; i++) {
      _buffer[_head] = newSamples[i];
      _head = (_head + 1) % maxSamples;
      if (_count < maxSamples) _count++;
    }
  }

  /// Extracts the continuous audio segment in chronological order.
  /// This is the only method that allocates.
  Float32List toFloat32List() {
    final result = Float32List(_count);
    for (var i = 0; i < _count; i++) {
      final index = (_head - _count + i + maxSamples) % maxSamples;
      result[i] = _buffer[index];
    }
    return result;
  }

  /// Resets the buffer without deallocating underlying memory.
  void clear() {
    _head = 0;
    _count = 0;
  }

  int get length => _count;
  bool get hasContent => _count > 0;
}
```

---

## 7. ONNX Inference Integration

### 7.1 `onnx_inference.dart`

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:onnxruntime/onnxruntime.dart';

import 'exceptions.dart';
import 'audio_preprocessor.dart';
import 'math_utils.dart';  // softmax2 lives here, exported via barrel file

class SmartTurnOnnxSession {
  // Note: The input tensor name 'input' and output tensor name 'logits'
  // are used in post-release verification (Section 16). The run() method
  // accesses the output by list position since Smart Turn has exactly one
  // output tensor. If the model gains multiple outputs in a future version,
  // switch to the named output approach using outputNames parameter.
  static const String inputTensorName = 'input';

  OrtSession? _session;
  bool _isInitialized = false;

  Future<void> initialize({
    required String? modelFilePath,
    int cpuThreadCount = 1,
  }) async {
    if (modelFilePath == null) {
      throw const SmartTurnModelLoadException('Model file path is required.');
    }

    try {
      // ✅ REQUIRED: Initialize the ONNX Runtime native environment.
      // This must be called before creating any OrtSession.
      // The corresponding release() must be called in dispose().
      OrtEnv.instance.init();

      final sessionOptions = OrtSessionOptions()
        ..setIntraOpNumThreads(cpuThreadCount)
        ..setInterOpNumThreads(1);

      // --- Execution Provider Note ---
      // The Smart Turn v3.1-cpu.onnx model is int8 quantized.
      //
      // ONNX Runtime's default CPU Execution Provider has native int8 support
      // and is the correct and recommended starting point for this model.
      //
      // XNNPACK is optimized primarily for float32/fp16 workloads. Its benefit
      // for int8 quantized models is device-specific and NOT guaranteed.
      // Official ONNX Runtime mobile docs recommend starting with the CPU
      // provider for quantized models.
      //
      // If you wish to benchmark XNNPACK on a specific device, the correct
      // method name is:
      //
      //   sessionOptions.appendXnnpackProvider();   // ✅ Correct method name
      //
      // (NOT appendExecutionProvider_XNNPACK() — that method does not exist.)
      //
      // Only enable XNNPACK if device-specific benchmarks confirm improvement.

      // ✅ OrtSession.fromFile() requires a dart:io File object, not a String.
      _session = OrtSession.fromFile(File(modelFilePath), sessionOptions);

      _isInitialized = true;
    } catch (e) {
      throw SmartTurnModelLoadException('Failed to load ONNX model: $e');
    }
  }

  Future<(double, double)> run(Float32List paddedAudio) async {
    if (!_isInitialized || _session == null) {
      throw const SmartTurnNotInitializedException();
    }

    try {
      final inputTensor = OrtValueTensor.createTensorWithDataList(
        paddedAudio,
        [1, AudioPreprocessor.kMaxSamples],
      );

      final inputs = {inputTensorName: inputTensor};
      final runOptions = OrtRunOptions();
      final outputs = await _session!.runAsync(runOptions, inputs);

      inputTensor.release();
      runOptions.release();

      final outputTensor = outputs!.first as OrtValueTensor;
      final logits = (await outputTensor.getValue()) as List;
      outputTensor.release();

      return (
        (logits[0][0] as num).toDouble(),
        (logits[0][1] as num).toDouble(),
      );
    } catch (e) {
      throw SmartTurnInferenceException('ONNX inference failed: $e');
    }
  }

  void dispose() {
    _session?.release();
    _session = null;
    _isInitialized = false;
    // ✅ Release the ONNX Runtime environment to match the init() call.
    OrtEnv.instance.release();
  }
}
```

### 7.2 Isolate Manager (Zero-Copy Messaging)

```dart
import 'dart:isolate';
import 'dart:typed_data';

import 'exceptions.dart';
import 'onnx_inference.dart';

class _InferenceRequest {
  final TransferableTypedData audioTransferable;
  final SendPort replyPort;
  const _InferenceRequest(this.audioTransferable, this.replyPort);
}

class _IsolateConfig {
  final SendPort initPort;
  final String? modelFilePath;
  final int cpuThreadCount;
  const _IsolateConfig({
    required this.initPort,
    required this.modelFilePath,
    required this.cpuThreadCount,
  });
}

class SmartTurnIsolate {
  Isolate? _isolate;
  SendPort? _sendPort;
  final ReceivePort _receivePort = ReceivePort();

  Future<void> spawn({
    required String? modelFilePath,
    required int cpuThreadCount,
  }) async {
    _isolate = await Isolate.spawn(
      _isolateEntry,
      _IsolateConfig(
        initPort: _receivePort.sendPort,
        modelFilePath: modelFilePath,
        cpuThreadCount: cpuThreadCount,
      ),
    );
    _sendPort = await _receivePort.first as SendPort;
  }

  Future<(double, double)> predict(Float32List paddedAudio) async {
    final replyPort = ReceivePort();

    // Use TransferableTypedData to transfer memory ownership across the
    // isolate boundary without a 512KB deep copy. This prevents UI thread
    // GC jank during real-time audio streaming.
    final transferable =
        TransferableTypedData.fromList([paddedAudio.buffer.asUint8List()]);

    _sendPort!.send(_InferenceRequest(transferable, replyPort.sendPort));

    final result = await replyPort.first;
    replyPort.close();

    // Type-check before casting: the isolate sends an exception object on
    // failure. A blind `as (double, double)` cast would throw a TypeError,
    // swallowing the original error message. Instead, re-throw cleanly.
    if (result is (double, double)) return result;
    throw SmartTurnInferenceException(
      'Inference isolate returned an error: $result',
    );
  }

  void kill() {
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort.close();
  }

  static Future<void> _isolateEntry(_IsolateConfig config) async {
    final session = SmartTurnOnnxSession();
    await session.initialize(
      modelFilePath: config.modelFilePath,
      cpuThreadCount: config.cpuThreadCount,
    );

    final commandPort = ReceivePort();
    config.initPort.send(commandPort.sendPort);

    await for (final message in commandPort) {
      if (message is _InferenceRequest) {
        try {
          // Safely materialize the zero-copy buffer back into a Float32List
          final bytes =
              message.audioTransferable.materialize().asUint8List();
          final audioList = Float32List.view(
            bytes.buffer,
            bytes.offsetInBytes,
            bytes.lengthInBytes ~/ 4,
          );

          final logits = await session.run(audioList);
          message.replyPort.send(logits);
        } catch (e) {
          message.replyPort.send(e);
        }
      }
    }
  }
}
```

---

## 8. VAD Integration (Dynamic Noise & Multi-Poll)

### 8.1 `vad_detector.dart`

A hardcoded energy threshold breaks in real-world conditions (noisy cafes, HVAC, wind). We use an Exponential Moving Average (EMA) to track the dynamic noise floor. Crucially, we emit `evaluatingSilence` *repeatedly* during long pauses so the model can evaluate the *duration* of the silence — not just the exact moment speech stops.

```dart
import 'dart:typed_data';
import 'dart:math' as math;

import 'audio_preprocessor.dart';

enum VadState {
  silence,
  speechStart,
  speech,
  silenceAfterSpeech,   // First silence threshold hit (e.g., 300ms)
  evaluatingSilence,    // Emitted repeatedly during extended pauses
}

class EnergyVad {
  final int silenceFrameCount;
  final int pollIntervalFrames;

  // Dynamic noise floor tracking via EMA
  double _noiseFloor = 0.005;
  int _consecutiveSilenceFrames = 0;
  bool _isSpeaking = false;

  EnergyVad({
    this.silenceFrameCount = 10,    // e.g., 10 × 30ms = 300ms of silence
    this.pollIntervalFrames = 5,    // Evaluate model every 150ms thereafter
  });

  VadState process(Float32List frame) {
    final rms = AudioPreprocessor.computeRms(frame);

    // Dynamic threshold: 2.5× noise floor, with a minimum sensitivity floor
    final dynamicThreshold = math.max(_noiseFloor * 2.5, 0.01);

    if (rms > dynamicThreshold) {
      _consecutiveSilenceFrames = 0;

      if (!_isSpeaking) {
        _isSpeaking = true;
        return VadState.speechStart;
      }
      return VadState.speech;
    } else {
      _consecutiveSilenceFrames++;
      // Slowly adapt noise floor downward during silence
      _noiseFloor = (_noiseFloor * 0.99) + (rms * 0.01);

      if (_isSpeaking) {
        if (_consecutiveSilenceFrames == silenceFrameCount) {
          // First threshold crossing — fire the initial silence event
          return VadState.silenceAfterSpeech;
        } else if (_consecutiveSilenceFrames > silenceFrameCount &&
            _consecutiveSilenceFrames % pollIntervalFrames == 0) {
          // Multi-poll fix: continue emitting during extended silence so the
          // model can evaluate whether the silence duration is long enough
          // to confirm a completed turn — not just the instant speech stops.
          return VadState.evaluatingSilence;
        }
      }

      return _isSpeaking ? VadState.speech : VadState.silence;
    }
  }

  void reset() {
    _consecutiveSilenceFrames = 0;
    _isSpeaking = false;
  }
}
```

---

## 9. Platform-Specific Configuration

Consumer apps using your package need the following native configuration. These apply to the **app** consuming your package, not to the package itself.

### iOS — `ios/Runner/Info.plist`

```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app uses the microphone to detect when you finish speaking.</string>
```

**`ios/Podfile`** — set minimum deployment target:

```ruby
platform :ios, '16.0'

# Add inside your target block:
use_frameworks! :linkage => :static
```

> **Why iOS 16.0?** The `onnxruntime` package requires iOS 16 as its minimum deployment target due to its ONNX Runtime native dependency.

### Android — `android/app/src/main/AndroidManifest.xml`

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
```

**`android/app/build.gradle`** — set minimum SDK:

```groovy
android {
    defaultConfig {
        minSdkVersion 24
    }
}
```

**`android/app/proguard-rules.pro`** — ⚠️ Required for release builds:

```
-keep class ai.onnxruntime.** { *; }
```

> **Critical:** This file is required to prevent R8/ProGuard from stripping ONNX Runtime classes during release builds. Without it, your app will compile fine in debug mode but **crash at runtime in release builds** when trying to load the ONNX model. Run this command to create it:
>
> ```bash
> echo "-keep class ai.onnxruntime.** { *; }" > android/app/proguard-rules.pro
> ```

### macOS — `macos/Podfile`

```ruby
platform :osx, '14.0'
```

Also set `Minimum Deployments` to `14.0` in your Runner Xcode project's General settings.

---

## 10. Complete Implementation

### 10.1 `smart_turn_detector.dart`

Fixing the **"Queue of Death"**: If audio buffers arrive faster than the Isolate can infer (e.g., on low-end devices), we implement explicit backpressure using `_isProcessing`. Smart Turn only cares about the *most recent* audio state, so dropping intermediate frames during processing is correct behavior.

```dart
import 'dart:async';
import 'dart:typed_data';

import 'smart_turn_config.dart';
import 'smart_turn_result.dart';
import 'exceptions.dart';
import 'audio_preprocessor.dart';
import 'math_utils.dart';      // softmax2
import 'onnx_inference.dart';  // SmartTurnOnnxSession, SmartTurnIsolate

class SmartTurnDetector {
  final SmartTurnConfig config;

  SmartTurnIsolate? _inferenceIsolate;
  SmartTurnOnnxSession? _session;
  bool _isInitialized = false;
  bool _isProcessing = false;

  SmartTurnDetector({SmartTurnConfig? config})
      : config = config ?? const SmartTurnConfig();

  Future<void> initialize() async {
    if (_isInitialized) return;

    final modelPath = config.customModelPath;
    if (modelPath == null) {
      throw const SmartTurnModelLoadException(
        'customModelPath is required. Download the ONNX model to the app '
        'documents directory and provide its path via SmartTurnConfig.',
      );
    }

    if (config.useIsolate) {
      _inferenceIsolate = SmartTurnIsolate();
      await _inferenceIsolate!.spawn(
        modelFilePath: modelPath,
        cpuThreadCount: config.cpuThreadCount,
      );
    } else {
      _session = SmartTurnOnnxSession();
      await _session!.initialize(
        modelFilePath: modelPath,
        cpuThreadCount: config.cpuThreadCount,
      );
    }

    _isInitialized = true;
  }

  /// Predicts whether the user has completed their speaking turn.
  ///
  /// Returns [null] if the model is currently processing a previous frame
  /// (backpressure handling). Since Smart Turn evaluates the most recent
  /// audio state, dropped frames during inference are safe to ignore.
  ///
  /// [audioSamples] must be float32 PCM, 16kHz, mono, normalized to [-1.0, 1.0].
  Future<SmartTurnResult?> predict(Float32List audioSamples) async {
    if (!_isInitialized) throw const SmartTurnNotInitializedException();

    // Backpressure: drop this request if the isolate is still busy.
    if (_isProcessing) return null;
    _isProcessing = true;

    final stopwatch = Stopwatch()..start();

    try {
      final paddedAudio = AudioPreprocessor.prepareInput(audioSamples);

      final (incompleteLogit, completeLogit) = config.useIsolate
          ? await _inferenceIsolate!.predict(paddedAudio)
          : await _session!.run(paddedAudio);

      final (_, completeProbability) = softmax2(incompleteLogit, completeLogit);

      return SmartTurnResult(
        isComplete: completeProbability >= config.completionThreshold,
        confidence: completeProbability,
        latencyMs: stopwatch.elapsedMilliseconds,
        audioLengthMs: AudioPreprocessor.sampleCountToMs(audioSamples.length),
      );
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> dispose() async {
    _inferenceIsolate?.kill();
    _inferenceIsolate = null;
    _session?.dispose();
    _session = null;
    _isInitialized = false;
  }
}
```

### 10.2 Barrel File — `smart_turn_dart.dart`

```dart
library smart_turn_dart;

export 'src/smart_turn_detector.dart';
export 'src/smart_turn_result.dart';
export 'src/smart_turn_config.dart';
export 'src/audio_preprocessor.dart';
export 'src/audio_buffer.dart';
export 'src/vad_detector.dart';
export 'src/exceptions.dart';
export 'src/math_utils.dart';  // Exports softmax2 for testing and advanced consumers
```

---

## 11. Testing Strategy

### 11.1 Audio Buffer Circular Logic Test

```dart
// test/audio_buffer_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_turn_dart/smart_turn_dart.dart';

void main() {
  test('AudioBuffer clamps to maxSamples and maintains order when overfilled', () {
    final buffer = AudioBuffer(maxSeconds: 1); // 16,000 samples max

    final chunk1 = Float32List(10000)..fillRange(0, 10000, 1.0);
    final chunk2 = Float32List(10000)..fillRange(0, 10000, 2.0);

    buffer.append(chunk1);
    buffer.append(chunk2); // 20,000 total — should clamp to 16,000

    expect(buffer.length, equals(16000));

    final output = buffer.toFloat32List();

    // The oldest 4,000 samples of chunk1 are evicted.
    // Remaining: 6,000 samples of 1.0, then 10,000 samples of 2.0.
    expect(output[0], equals(1.0));
    expect(output[5999], equals(1.0));
    expect(output[6000], equals(2.0));
    expect(output[15999], equals(2.0));
  });
}
```

### 11.2 Audio Preprocessor Padding Test

```dart
// test/audio_preprocessor_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_turn_dart/smart_turn_dart.dart';

void main() {
  test('prepareInput left-pads short audio to 128,000 samples', () {
    final shortAudio = Float32List(48000)..fillRange(0, 48000, 0.5);
    final result = AudioPreprocessor.prepareInput(shortAudio);

    expect(result.length, equals(128000));
    // First 80,000 samples should be zero (padding)
    expect(result[0], equals(0.0));
    expect(result[79999], equals(0.0));
    // Index 80000 is the FIRST audio sample, multiplied by fade factor 0/80 = 0.0
    expect(result[80000], equals(0.0));
    // Index 80079 is the LAST fade-in sample, factor = 79/80 ≈ 0.9875
    expect(result[80079], closeTo(0.5 * (79.0 / 80.0), 1e-6));
    // Index 80080 is the first sample past the fade-in — full amplitude
    expect(result[80080], closeTo(0.5, 1e-6));
  });

  test('prepareInput crops overlong audio to last 128,000 samples', () {
    final longAudio = Float32List(200000);
    for (var i = 0; i < 200000; i++) {
      longAudio[i] = i.toDouble();
    }
    final result = AudioPreprocessor.prepareInput(longAudio);
    expect(result.length, equals(128000));
    // Should contain the LAST 128,000 samples
    expect(result[0], equals(72000.0));
    expect(result[127999], equals(199999.0));
  });
}
```

### 11.3 Softmax Correctness Test

```dart
// test/softmax_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_turn_dart/smart_turn_dart.dart';

void main() {
  test('softmax2 outputs sum to 1.0', () {
    final (p0, p1) = softmax2(1.2, 0.5);
    expect(p0 + p1, closeTo(1.0, 1e-9));
  });

  test('softmax2 higher logit yields higher probability', () {
    final (p0, p1) = softmax2(2.0, 0.5);
    expect(p0, greaterThan(p1));
  });

  test('softmax2 is numerically stable for large logit differences', () {
    // Should not overflow or return NaN
    final (p0, p1) = softmax2(100.0, -100.0);
    expect(p0, closeTo(1.0, 1e-6));
    expect(p1, closeTo(0.0, 1e-6));
  });
}
```

---

## 12. Performance Optimization

### Expected Latency on Real Hardware

These are approximate estimates. Actual results vary by device thermal state, background load, OS version, and model quantization behavior. Always benchmark on your target devices.

| Device Class | Approximate Inference Latency |
|---|---|
| iPhone 15 (A16) | ~10–20ms |
| Mid-range Android (2023) | ~30–80ms |
| Low-end Android | ~80–150ms |

### Golden Rule: CPU Thread Count on Mobile

**Keep `cpuThreadCount = 1` in your configuration.** This is counter-intuitive but correct.

Using 4 or 8 threads on a mobile device typically *slows down* inference due to:

1. **Thread orchestration overhead** — spawning and synchronizing threads has a fixed cost that exceeds the computation savings for an 8M parameter model.
2. **ARM big.LITTLE architecture** — mobile SoCs have heterogeneous cores (fast "big" + efficient "LITTLE"). Multi-threaded inference often pulls work onto LITTLE cores, which are slower than a single big core running the full workload.
3. **Thermal throttling** — saturating all cores generates heat, causing the SoC to throttle clock speeds mid-inference, increasing tail latency.

### On XNNPACK for int8 Models

XNNPACK's primary optimizations target float32 and float16 workloads on ARM NEON. For int8 quantized models (which Smart Turn v3.1-cpu.onnx is), the default CPU Execution Provider is generally the correct choice. ONNX Runtime's CPU provider has mature int8 support via kernel-level optimizations.

If you choose to evaluate XNNPACK, benchmark using `Stopwatch` over at least 100 inference calls on a physically warm device to account for thermal throttling effects.

---

## 13. Example App (Reactive & Lifecycle-Aware)

Two key rules for production audio apps:

1. **Never use `setState` in a 30fps audio loop.** Use `ValueNotifier` to scope rebuilds to the minimum subtree.
2. **Always implement `WidgetsBindingObserver`** to dispose and reinitialize the ONNX session on app lifecycle changes. iOS will terminate apps in the background that hold native resources.

```dart
// example/lib/main.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:smart_turn_dart/smart_turn_dart.dart';

void main() => runApp(const SmartTurnDemoApp());

class SmartTurnDemoApp extends StatelessWidget {
  const SmartTurnDemoApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Smart Turn Demo',
        theme: ThemeData.dark(useMaterial3: true),
        home: const SmartTurnScreen(),
      );
}

class SmartTurnScreen extends StatefulWidget {
  const SmartTurnScreen({super.key});

  @override
  State<SmartTurnScreen> createState() => _SmartTurnScreenState();
}

class _SmartTurnScreenState extends State<SmartTurnScreen>
    with WidgetsBindingObserver {
  late SmartTurnDetector _detector;
  late AudioBuffer _audioBuffer;
  late EnergyVad _vad;

  // Isolate reactive state to prevent whole-widget-tree rebuilds at 30fps
  final ValueNotifier<bool> _isInitialized = ValueNotifier(false);
  final ValueNotifier<bool> _isSpeaking = ValueNotifier(false);
  final ValueNotifier<SmartTurnResult?> _lastResult = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDetector();
  }

  // Prevent zombie isolates & iOS background terminations
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _detector.dispose();
      _isInitialized.value = false;
    } else if (state == AppLifecycleState.resumed) {
      _initDetector();
    }
  }

  Future<void> _initDetector() async {
    _detector = SmartTurnDetector(
      config: const SmartTurnConfig(useIsolate: true),
    );
    _audioBuffer = AudioBuffer(maxSeconds: 8);
    _vad = EnergyVad();

    // In a real app, download the model to the documents directory first,
    // then pass its path via SmartTurnConfig(customModelPath: downloadedPath).
    await _detector.initialize();
    _isInitialized.value = true;
  }

  // Called from your audio stream subscription (e.g., via the `record` package)
  Future<void> _processAudioFrame(Float32List frame) async {
    _audioBuffer.append(frame);
    final vadState = _vad.process(frame);

    if (vadState == VadState.speechStart) {
      _isSpeaking.value = true;
    } else if (vadState == VadState.silenceAfterSpeech ||
        vadState == VadState.evaluatingSilence) {
      _isSpeaking.value = false;

      final result = await _detector.predict(_audioBuffer.toFloat32List());

      // result is null when backpressure drops the frame — safe to ignore.
      if (result == null) return;

      _lastResult.value = result;

      if (result.isComplete) {
        // Turn complete! Clear buffers and trigger downstream LLM pipeline.
        _audioBuffer.clear();
        _vad.reset();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Smart Turn Demo')),
      body: Center(
        child: ValueListenableBuilder<bool>(
          valueListenable: _isInitialized,
          builder: (context, initialized, _) {
            if (!initialized) return const CircularProgressIndicator();

            return ValueListenableBuilder<SmartTurnResult?>(
              valueListenable: _lastResult,
              builder: (context, result, _) => Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Model Ready',
                    style: TextStyle(color: Colors.green),
                  ),
                  const SizedBox(height: 16),
                  ValueListenableBuilder<bool>(
                    valueListenable: _isSpeaking,
                    builder: (context, speaking, _) => Text(
                      speaking ? '🎙 Speaking...' : '⏸ Listening...',
                    ),
                  ),
                  if (result != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Prediction: ${result.isComplete ? "COMPLETE ✅" : "INCOMPLETE ⏳"}',
                      style: TextStyle(
                        fontSize: 18,
                        color: result.isComplete ? Colors.green : Colors.orange,
                      ),
                    ),
                    Text('Confidence: ${(result.confidence * 100).toInt()}%'),
                    Text('Latency: ${result.latencyMs}ms'),
                    Text('Audio: ${result.audioLengthMs}ms'),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detector.dispose();
    _isInitialized.dispose();
    _isSpeaking.dispose();
    _lastResult.dispose();
    super.dispose();
  }
}
```

---

## 14. Documentation & API Reference

Ensure your dartdoc comments are complete. A strong pub.dev score requires excellent documentation coverage. All public API surfaces should be documented.

```dart
/// Predicts whether the user has completed their speaking turn.
///
/// Returns [SmartTurnResult] with prediction confidence and latency metrics,
/// or [null] if the model is currently processing a previous frame
/// (backpressure handling — safe to ignore, discard the frame).
///
/// Throws [SmartTurnNotInitializedException] if [initialize] has not
/// been called, and [SmartTurnInferenceException] if ONNX inference fails.
///
/// [audioSamples] requirements:
/// - Encoding: Float32 PCM
/// - Sample rate: 16,000 Hz (16 kHz)
/// - Channels: Mono (1 channel)
/// - Normalized: values in range [-1.0, 1.0]
///
/// Example:
/// ```dart
/// final result = await detector.predict(audioBuffer.toFloat32List());
/// if (result?.isComplete == true) {
///   // User has finished speaking — trigger LLM pipeline
/// }
/// ```
Future<SmartTurnResult?> predict(Float32List audioSamples) async { ... }
```

---

## 15. Publishing to pub.dev (CI/CD Checksums)

Prevent corrupted models or missing Git LFS payloads from breaking production apps by enforcing SHA-256 integrity checks in CI.

```yaml
# .github/workflows/ci.yml
name: CI
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.19.x'
          channel: stable

      - run: flutter pub get
      - run: flutter test

      # Enforce ONNX Model Integrity
      - name: Verify ONNX Checksum
        run: |
          # !! IMPORTANT: Replace the value below with the ACTUAL SHA-256 hash
          # you recorded in Step 4 by running:
          #   shasum -a 256 assets/models/smart-turn-v3.1-cpu.onnx
          #
          # Do NOT leave this as the placeholder value. The CI check will
          # fail if you haven't replaced it, which is intentional.
          EXPECTED_SHA="REPLACE_WITH_YOUR_ACTUAL_SHA256_FROM_STEP_4"

          # Guard against forgotten placeholder
          if [ "$EXPECTED_SHA" = "REPLACE_WITH_YOUR_ACTUAL_SHA256_FROM_STEP_4" ]; then
            echo "❌ ERROR: You must replace EXPECTED_SHA with the actual"
            echo "   SHA-256 hash from Step 4. See the guide for instructions."
            exit 1
          fi

          ACTUAL_SHA=$(shasum -a 256 assets/models/smart-turn-v3.1-cpu.onnx | awk '{ print $1 }')

          if [ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]; then
            echo "❌ Checksum mismatch — possible model corruption or"
            echo "   missing Git LFS payload."
            echo "   Expected: $EXPECTED_SHA"
            echo "   Actual:   $ACTUAL_SHA"
            exit 1
          fi

          echo "✅ ONNX model checksum verified."

      - run: dart pub publish --dry-run
```

> **Why the original guide's SHA was wrong:** The value `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` is the universally recognized SHA-256 hash of a **zero-byte (empty) file**. If copied verbatim into a CI script, it would cause the integrity check to pass only when the model file is empty or missing — the opposite of the intended security guarantee. The corrected script above fails loudly if the placeholder has not been replaced.

---

## 16. Post-Release Maintenance

When Pipecat AI releases a new version of Smart Turn:

1. Download the new ONNX file from HuggingFace.
2. Run a Python smoke test to confirm input and output tensor names haven't changed:

```python
import onnxruntime as ort

session = ort.InferenceSession("smart-turn-v3.1-cpu.onnx")
print("Inputs:", [i.name for i in session.get_inputs()])
print("Outputs:", [o.name for o in session.get_outputs()])
print("Input shape:", session.get_inputs()[0].shape)
# Expected:
#   Inputs: ['input']
#   Outputs: ['logits']
#   Input shape: [1, 128000]
```

3. Verify the new model still expects `[1, 128000]` shape.
4. Update `EXPECTED_SHA` in your GitHub Actions CI file with the new model's hash.
5. Bump the package minor version and publish:

```bash
# Update version in pubspec.yaml, then:
dart pub publish
```

---

## Appendix: Corrections Applied

### Round 1 — Fact-Check Audit (Original → First Corrected)

| # | Section | Original (Incorrect) | Corrected |
|---|---|---|---|
| 1 | `pubspec.yaml` | `flutter_onnxruntime: ^1.6.0` | `onnxruntime: ^1.3.1` — different package with the correct API |
| 2 | `onnx_inference.dart` | `sessionOptions.appendExecutionProvider_XNNPACK()` | `sessionOptions.appendXnnpackProvider()` — correct method name |
| 3 | `onnx_inference.dart` | `OrtSession.fromFile(modelFilePath, ...)` (String) | `OrtSession.fromFile(File(modelFilePath), ...)` (File object) |
| 4 | `onnx_inference.dart` | XNNPACK recommended as default for all models | XNNPACK not recommended for int8 quantized models; CPU provider is correct default |
| 5 | CI/CD checksums | SHA-256 placeholder was hash of empty file | Placeholder clearly labeled + CI script fails loudly if not replaced |
| 6 | Section 1.1 | "Parameters: ~8M" (ambiguous vs. Whisper Tiny's 39M total) | Clarified: 8M = Whisper encoder layers only + linear classification head |
| 7 | Section 2.1 | Model described as "8 MB" | Corrected to "~8.68–8.76 MB" |
| 8 | Section 9 | Missing Android `proguard-rules.pro` | Added with explanation of release build crash risk |
| 9 | Section 7.1 | Missing `OrtEnv.instance.init()` / `release()` | Added init in `initialize()` and matching `release()` in `dispose()` |
| 10 | Section 4 | No mention of multiple ONNX files in HuggingFace repo | Added note on v3.0, v3.1-cpu, and v3.1-gpu variants |

### Round 2 — Deep Review (First Corrected → Final)

| # | Section | Issue | Fix Applied |
|---|---|---|---|
| 11 | Section 7.2 | **Critical formatting bug**: closing code fence for Section 7.2 was missing — placed at end of file instead, causing Sections 8–16 to render as raw code | Closing ` ``` ` inserted after `SmartTurnIsolate` class; stray fence at EOF removed |
| 12 | Sections 5, 10, 11 | **Compilation bug**: `softmax2` defined in `onnx_inference.dart` (not exported) but called in `smart_turn_detector.dart` and tested via public API in test 11.3 | Extracted `softmax2` to `src/math_utils.dart`; added to barrel exports; updated all imports |
| 13 | Section 7.2 | **Runtime bug**: `await replyPort.first as (double, double)` blindly casts isolate response — throws `TypeError` if isolate sends an exception instead | Added type-check before cast; re-throws as clean `SmartTurnInferenceException` |
| 14 | Section 7.1 | **Dead code / linter warning**: `_outputTensorName` constant declared but never used in `run()` | Removed unused constant; added explanatory comment about single-output access pattern |
| 15 | Section 8.1 | **Dead code**: `_signalPeak` field updated each frame but never read or used in threshold logic | Removed `_signalPeak` from `EnergyVad`; updated `process()` accordingly |
| 16 | Section 5.1 | **Misleading API**: `maxAudioSeconds` validated in assert but never applied to actual audio clipping | Added detailed doc comment explaining current behavior and how to use it manually |
| 17 | Section 11.2 | **Imprecise test assertion**: `expect(result[80000], lessThan(0.5))` — the fade-in at i=0 multiplies by `0/80 = 0.0`, so it's exactly `0.0`, not just "less than 0.5" | Replaced with `equals(0.0)`; added precise mid-fade and post-fade assertions |

---

*This guide incorporates elite mobile engineering paradigms: zero-copy memory transfer, reactive UI bounding, dynamic noise-adaptive VAD, and robust CI MLOps integrity checks. Adhering to these patterns ensures your package works flawlessly under real-world device constraints.*
