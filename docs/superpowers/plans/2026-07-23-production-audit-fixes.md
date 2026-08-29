# Production Audit Review Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all 5 issues identified in the code review of the production audit fix commit.

**Architecture:** Five independent fixes across FFI cleanup, detector dispose safety, documentation accuracy, test correctness, and CI coverage. All changes preserve the existing public Dart API.

**Tech Stack:** Dart 3.x, `package:test`, `package:very_good_analysis`, GitHub Actions YAML

## Global Constraints

- No third-party dependencies in core library
- Line length: 80 characters (`dart format --line-length 80 lib test`)
- All tests must pass: `flutter test`
- Static analysis must pass: `flutter analyze`
- Follow TDD: write failing test then implement then verify pass
- The file `ort_session.dart` is `// coverage:ignore-file` — tests for FFI cleanup are not required (native FFI cannot run in test VM)
- Changes to `onnx_inference_native.dart` are inside `// coverage:ignore-start/end` blocks

---

### Task 1: Fix FFI memory leaks in `OrtSession.run()`

**Files:**
- Modify: `pipecat_smart_turn_platform_interface/lib/src/platform/native/onnxruntime/ort_session.dart:163-227` (the `run()` method)

**Interfaces:**
- Consumes: existing `OrtSession`, `OrtValue`, `OrtRunOptions` types
- Produces: same `List<OrtValue?>` return type — no API change

- [ ] **Step 1: Wrap run() allocations in try/finally and free toNativeUtf8 strings**

The current `run()` method allocates native strings via `toNativeUtf8()` for input/output names but never frees them. It also only frees pointer arrays on the happy path. Wrap everything in `try/finally` and free individual strings.

Replace the `run()` method body (lines 163-227) with:

```dart
  List<OrtValue?> run(
    OrtRunOptions runOptions,
    Map<String, OrtValue> inputs, [
    List<String>? outputNames,
  ]) {
    final inputLength = inputs.length;
    final inputNamePtrs = calloc<ffi.Pointer<ffi.Char>>(inputLength);
    final inputPtrs = calloc<ffi.Pointer<bg.OrtValue>>(inputLength);
    var inputNamesAllocated = 0;

    outputNames ??= _outputNames;
    final outputLength = outputNames.length;
    final outputNamePtrs =
        calloc<ffi.Pointer<ffi.Char>>(outputLength);
    final outputPtrs =
        calloc<ffi.Pointer<bg.OrtValue>>(outputLength);
    var outputNamesAllocated = 0;

    try {
      var i = 0;
      for (final entry in inputs.entries) {
        inputNamePtrs[i] =
            entry.key.toNativeUtf8().cast<ffi.Char>();
        inputPtrs[i] = entry.value.ptr;
        inputNamesAllocated = ++i;
      }

      for (var j = 0; j < outputLength; j++) {
        outputNamePtrs[j] =
            outputNames[j].toNativeUtf8().cast<ffi.Char>();
        outputPtrs[j] = ffi.nullptr;
        outputNamesAllocated = j + 1;
      }

      final statusPtr = OrtEnv.instance.ortApiPtr.ref.Run
          .asFunction<
            bg.OrtStatusPtr Function(
              ffi.Pointer<bg.OrtSession>,
              ffi.Pointer<bg.OrtRunOptions>,
              ffi.Pointer<ffi.Pointer<ffi.Char>>,
              ffi.Pointer<ffi.Pointer<bg.OrtValue>>,
              int,
              ffi.Pointer<ffi.Pointer<ffi.Char>>,
              int,
              ffi.Pointer<ffi.Pointer<bg.OrtValue>>,
            )
          >()(
        _ptr,
        runOptions._ptr,
        inputNamePtrs,
        inputPtrs,
        inputLength,
        outputNamePtrs,
        outputLength,
        outputPtrs,
      );
      OrtStatus.checkOrtStatus(statusPtr);

      return List<OrtValue?>.generate(
        outputLength,
        (index) {
          final ortValuePtr = outputPtrs[index];
          final onnxTypePtr = calloc<ffi.Int32>();
          try {
            final typeStatusPtr = OrtEnv
                .instance
                .ortApiPtr
                .ref
                .GetValueType
                .asFunction<
                  bg.OrtStatusPtr Function(
                    ffi.Pointer<bg.OrtValue>,
                    ffi.Pointer<ffi.UnsignedInt>,
                  )
                >()(ortValuePtr, onnxTypePtr.cast());
            OrtStatus.checkOrtStatus(typeStatusPtr);
            final onnxType =
                ONNXType.fromValue(onnxTypePtr.value);
            if (onnxType == ONNXType.tensor) {
              return OrtValueTensor(ortValuePtr);
            } else {
              throw Exception(
                'Unexpected output type: $onnxType. '
                'ONNX model only produces tensors.',
              );
            }
          } finally {
            calloc.free(onnxTypePtr);
          }
        },
      );
    } finally {
      // Free individual toNativeUtf8() strings.
      for (var k = 0; k < inputNamesAllocated; k++) {
        calloc.free(inputNamePtrs[k]);
      }
      for (var k = 0; k < outputNamesAllocated; k++) {
        calloc.free(outputNamePtrs[k]);
      }
      // Free pointer arrays.
      calloc
        ..free(inputNamePtrs)
        ..free(inputPtrs)
        ..free(outputNamePtrs)
        ..free(outputPtrs);
    }
  }
```

- [ ] **Step 2: Run analysis to verify no issues**

Run: `cd pipecat_smart_turn_platform_interface && flutter analyze`
Expected: No analysis errors

- [ ] **Step 3: Run tests to verify no regressions**

Run: `cd pipecat_smart_turn_platform_interface && flutter test`
Expected: All existing tests pass (this file is `// coverage:ignore-file`)

- [ ] **Step 4: Format code**

Run: `dart format --line-length 80 pipecat_smart_turn_platform_interface/lib`

- [ ] **Step 5: Commit**

```bash
git add pipecat_smart_turn_platform_interface/lib/src/platform/native/onnxruntime/ort_session.dart
git commit -m "fix: make OrtSession.run() FFI cleanup exception-safe

Wrap all native allocations in try/finally blocks. Free individual
toNativeUtf8() strings (inputNamePtrs, outputNamePtrs) on every
exit path, not just the happy path. Track allocation counts to
safely free only what was allocated before an exception.

Addresses C8 from production audit."
```

---

### Task 2: Fix dispose segfault risk for non-isolate native path

**Files:**
- Modify: `pipecat_smart_turn_platform_interface/lib/src/smart_turn_detector.dart`
- Modify: `pipecat_smart_turn_platform_interface/test/smart_turn_detector_test.dart`

**Interfaces:**
- Consumes: `SmartTurnOnnxSession`, `SmartTurnIsolate`, `SmartTurnConfig`
- Produces: same public `SmartTurnDetector` API — no signature changes

The problem: when the non-isolate native path times out via `.timeout()`, the `finally` block clears `_isProcessing`, allowing `dispose()` to proceed and tear down `OrtSession` while the synchronous FFI call is still executing. This causes a segmentation fault.

The fix: track the actual native inference `Future` separately. In `dispose()`, await that future (ignoring its result) before releasing native resources, ensuring the FFI call has completed.

- [ ] **Step 1: Write failing test for dispose-during-timeout safety**

Add to the bottom of `smart_turn_detector_test.dart`, inside the `SmartTurnDetector` group, before the closing `});`:

```dart
    test('dispose waits for native inference after timeout',
        () async {
      final nativeCompleter = Completer<double>();
      final slowSession = SlowMockSession(nativeCompleter);

      detector = SmartTurnDetector(
        config: const SmartTurnConfig(
          customModelPath: 'model.onnx',
          useIsolate: false,
          inferenceTimeoutMs: 50,
        ),
      )..sessionOverride = slowSession;

      await detector.initialize();

      // Start a prediction that will time out
      expect(
        detector.predict(Float32List(16000)),
        throwsA(isA<SmartTurnInferenceException>()),
      );

      // Give the timeout a chance to fire
      await Future<void>.delayed(
        const Duration(milliseconds: 100),
      );

      // Start disposing — must wait for native future
      final disposeFuture = detector.dispose();

      // Verify dispose hasn't completed yet
      var disposeCompleted = false;
      unawaited(
        disposeFuture.then((_) => disposeCompleted = true),
      );
      await Future<void>.delayed(
        const Duration(milliseconds: 50),
      );
      expect(disposeCompleted, isFalse);

      // Now let the native call complete
      nativeCompleter.complete(0.5);
      await disposeFuture;
      expect(disposeCompleted, isTrue);
      expect(slowSession.disposeCalled, isTrue);
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd pipecat_smart_turn_platform_interface && flutter test test/smart_turn_detector_test.dart`
Expected: FAIL — dispose completes immediately (doesn't wait for native future)

- [ ] **Step 3: Implement the fix in smart_turn_detector.dart**

Add a `_nativeInferenceFuture` field after the `_initFuture` declaration (around line 45):

```dart
  Future<double>? _nativeInferenceFuture;
```

Replace the ternary expression in `predict()` that runs inference (the `final completeProbability = ...` assignment around lines 126-137) with:

```dart
      final completeProbability = config.useIsolate
          ? await _inferenceIsolate!.predict(
              paddedAudio,
              timeoutMs: config.inferenceTimeoutMs,
            )
          : await _runNativeWithTimeout(paddedAudio);
```

Add a new private method `_runNativeWithTimeout` after `predict()` and before `dispose()`:

```dart
  Future<double> _runNativeWithTimeout(Float32List audio) async {
    final nativeFuture = _session!.run(audio);
    _nativeInferenceFuture = nativeFuture;
    try {
      return await nativeFuture.timeout(
        Duration(milliseconds: config.inferenceTimeoutMs),
        onTimeout: () => throw const SmartTurnInferenceException(
          'Inference timed out',
        ),
      );
    } finally {
      _nativeInferenceFuture = null;
    }
  }
```

Replace `dispose()` to await the actual native future:

```dart
  /// Disposes of the ONNX session or background isolate.
  Future<void> dispose() async {
    _isInitialized = false; // Prevent new predictions

    // Await the actual native FFI future if one is in progress.
    // Dart's .timeout() does not cancel the underlying synchronous
    // FFI call, so we must wait for it to complete before releasing
    // the native OrtSession to avoid a segfault.
    final pendingNative = _nativeInferenceFuture;
    if (pendingNative != null) {
      try {
        await pendingNative;
      } on Object catch (_) {
        // Ignore — we only need the FFI call to finish.
      }
    }

    // Wait for any ongoing predict() frame to finish Dart work.
    while (_isProcessing) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    _inferenceIsolate?.kill();
    _inferenceIsolate = null;
    _session?.dispose();
    _session = null;
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd pipecat_smart_turn_platform_interface && flutter test test/smart_turn_detector_test.dart`
Expected: All tests pass including the new one

- [ ] **Step 5: Run full test suite and analysis**

Run: `cd pipecat_smart_turn_platform_interface && flutter test && flutter analyze`
Expected: All pass

- [ ] **Step 6: Format code**

Run: `dart format --line-length 80 pipecat_smart_turn_platform_interface/lib pipecat_smart_turn_platform_interface/test`

- [ ] **Step 7: Commit**

```bash
git add pipecat_smart_turn_platform_interface/lib/src/smart_turn_detector.dart pipecat_smart_turn_platform_interface/test/smart_turn_detector_test.dart
git commit -m "fix: prevent segfault when dispose races with native timeout

Track the actual native inference Future separately from the
_isProcessing flag. In dispose(), await the native future before
releasing the OrtSession, ensuring the synchronous FFI call has
completed. Dart's .timeout() does not cancel the underlying native
call, so the previous _isProcessing-only approach allowed session
teardown while C++ was still executing.

Addresses H4 from production audit."
```

---

### Task 3: Fix mel spectrogram documentation accuracy

**Files:**
- Modify: `pipecat_smart_turn_platform_interface/lib/src/mel_spectrogram.dart` (class doc and comments only)

**Interfaces:**
- No code changes — documentation only

The class doc claims "Uses a pure-Dart radix-2 in-place FFT" but the implementation uses `_computeDft`, a direct O(N squared) DFT. `kFftSize = 400` is not a power of 2, so radix-2 FFT does not apply.

- [ ] **Step 1: Update class documentation**

Replace the class doc comment (lines 4-17) with:

```dart
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
/// Uses a pure-Dart direct DFT with precomputed trigonometric tables.
/// A radix-2 FFT is not applicable because kFftSize (400) is not a
/// power of two. The precomputed cos/sin tables reduce per-frame
/// cost to ~201 x 400 multiply-adds, which benchmarks within
/// latency budgets on mobile devices for the 800-frame workload.
```

- [ ] **Step 2: Run analysis**

Run: `cd pipecat_smart_turn_platform_interface && flutter analyze`
Expected: No analysis errors

- [ ] **Step 3: Run tests**

Run: `cd pipecat_smart_turn_platform_interface && flutter test`
Expected: All pass (doc-only change)

- [ ] **Step 4: Format code**

Run: `dart format --line-length 80 pipecat_smart_turn_platform_interface/lib/src/mel_spectrogram.dart`

- [ ] **Step 5: Commit**

```bash
git add pipecat_smart_turn_platform_interface/lib/src/mel_spectrogram.dart
git commit -m "docs: correct mel spectrogram FFT documentation

Update class documentation to accurately describe the direct DFT
implementation with precomputed trig tables. The previous claim of
'radix-2 in-place FFT' was incorrect — kFftSize (400) is not a
power of 2.

Addresses H2 from production audit."
```

---

### Task 4: Fix golden mel spectrogram test self-generation

**Files:**
- Modify: `pipecat_smart_turn_platform_interface/test/mel_spectrogram_golden_test.dart`
- Create: `pipecat_smart_turn_platform_interface/test/goldens/generate_golden.py` (reference script)

**Interfaces:**
- No production code changes

The current golden test auto-creates the golden file if missing, which means it only proves regression stability, not upstream parity. Fix: remove auto-create, fail clearly if golden is absent, and add a documented Python script for regenerating against upstream.

- [ ] **Step 1: Update golden test to remove auto-generation**

Replace the entire file with:

```dart
@TestOn('vm')
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pipecat_smart_turn_platform_interface/src/audio_preprocessor.dart';
import 'package:pipecat_smart_turn_platform_interface/src/mel_spectrogram.dart';

void main() {
  test('MelSpectrogram matches golden snapshot', () async {
    // Generate a 1-second 440 Hz sine wave
    const sr = 16000;
    final audio = Float32List(128000); // 8 seconds, left-padded
    for (var i = 128000 - sr; i < 128000; i++) {
      audio[i] = math.sin(2 * math.pi * 440.0 * i / sr);
    }

    // Normalize it
    final prepared = AudioPreprocessor.prepareInput(audio);

    // Compute Mel spectrogram
    final result = MelSpectrogram.compute(prepared);

    // Compare against committed golden file.
    // See test/goldens/generate_golden.py for regeneration
    // instructions and upstream parity notes.
    final goldenFile =
        File('test/goldens/mel_spectrogram_golden.bin');
    expect(
      goldenFile.existsSync(),
      isTrue,
      reason: 'Golden file missing. '
          'See test/goldens/generate_golden.py for how to '
          'regenerate.',
    );

    final goldenBytes = goldenFile.readAsBytesSync();
    final goldenFloat32 = goldenBytes.buffer.asFloat32List(
      goldenBytes.offsetInBytes,
      goldenBytes.lengthInBytes ~/ 4,
    );

    expect(result.length, goldenFloat32.length);
    for (var i = 0; i < result.length; i++) {
      expect(result[i], closeTo(goldenFloat32[i], 1e-4));
    }
  });
}
```

- [ ] **Step 2: Create Python reference generation script**

Create `test/goldens/generate_golden.py`:

```python
#!/usr/bin/env python3
"""Generate the mel spectrogram golden file.

This script documents the golden generation process for the
mel spectrogram regression test.

The committed golden was generated by the Dart MelSpectrogram
implementation. To prove upstream parity, extend this script
to compare against transformers.WhisperFeatureExtractor.

To regenerate the Dart golden after intentional preprocessing
changes:
  1. Delete test/goldens/mel_spectrogram_golden.bin
  2. Temporarily restore the auto-generate logic in the test
  3. Run: flutter test test/mel_spectrogram_golden_test.dart
  4. Verify the new golden is correct
  5. Remove the auto-generate logic again

Future improvement (upstream parity):
  pip install transformers torch numpy
  - Generate a 128000-sample fixture with 1s 440 Hz sine
  - Run WhisperFeatureExtractor on it
  - Compare output against mel_spectrogram_golden.bin
"""

import sys


def main():
    """Print regeneration instructions."""
    print(__doc__)
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 3: Run tests to verify golden test passes with existing golden**

Run: `cd pipecat_smart_turn_platform_interface && flutter test test/mel_spectrogram_golden_test.dart`
Expected: PASS (the golden file exists and matches)

- [ ] **Step 4: Format Dart code**

Run: `dart format --line-length 80 pipecat_smart_turn_platform_interface/test/mel_spectrogram_golden_test.dart`

- [ ] **Step 5: Commit**

```bash
git add pipecat_smart_turn_platform_interface/test/mel_spectrogram_golden_test.dart pipecat_smart_turn_platform_interface/test/goldens/generate_golden.py
git commit -m "test: remove golden test self-generation, add reference script

Remove auto-create logic that silently generated the golden
snapshot if it was missing. The test now fails clearly if the
golden is absent, with instructions for regeneration.

Add a Python reference script documenting the generation process
and noting that upstream WhisperFeatureExtractor parity should be
validated separately.

Addresses H1 from production audit."
```

---

### Task 5: Broaden CI E2E workflow path filters

**Files:**
- Modify: `.github/workflows/pipecat_smart_turn.yaml` (lines 7-19, path filters)

**Interfaces:**
- No code changes — CI configuration only

The E2E workflow only triggers on `pipecat_smart_turn/**` changes. Changes to `pipecat_smart_turn_platform_interface` and platform packages bypass E2E tests entirely.

- [ ] **Step 1: Broaden path filters to all federated packages**

Replace the `on:` section (lines 7-19) with:

```yaml
on:
  pull_request:
    paths:
      - ".github/workflows/pipecat_smart_turn.yaml"
      - "pipecat_smart_turn/**"
      - "pipecat_smart_turn_platform_interface/**"
      - "pipecat_smart_turn_android/**"
      - "pipecat_smart_turn_ios/**"
      - "pipecat_smart_turn_linux/**"
      - "pipecat_smart_turn_macos/**"
      - "pipecat_smart_turn_web/**"
      - "pipecat_smart_turn_windows/**"
  push:
    branches:
      - main
    paths:
      - ".github/workflows/pipecat_smart_turn.yaml"
      - "pipecat_smart_turn/**"
      - "pipecat_smart_turn_platform_interface/**"
      - "pipecat_smart_turn_android/**"
      - "pipecat_smart_turn_ios/**"
      - "pipecat_smart_turn_linux/**"
      - "pipecat_smart_turn_macos/**"
      - "pipecat_smart_turn_web/**"
      - "pipecat_smart_turn_windows/**"
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/pipecat_smart_turn.yaml
git commit -m "ci: broaden E2E workflow to all federated packages

The E2E workflow previously triggered only on changes to the
umbrella package. Changes in platform_interface or platform
packages now correctly trigger E2E tests.

Addresses H6 from production audit."
```
