# Production Readiness Audit — pipecat_smart_turn

**Date:** 2026-07-11
**Scope:** Entire repository (all 8 packages, native code, CI, example app)
**Constraint honored:** Audit only — no source changes made. Public API change proposals are flagged where unavoidable.

---

## Stack

Flutter **federated plugin** (Dart ^3.11) for on-device end-of-turn detection using the pipecat `smart-turn-v3.2-cpu.onnx` model (8.6 MB, quantized, bundled as an asset):

| Package | Role |
|---|---|
| `pipecat_smart_turn` | App-facing umbrella (re-exports platform interface) |
| `pipecat_smart_turn_platform_interface` | **All real logic**: `SmartTurnDetector`, `EnergyVad`, `AudioBuffer`, mel spectrogram, ONNX Runtime via `dart:ffi` (native) and `onnxruntime-web` JS interop (web), isolate offloading |
| `pipecat_smart_turn_{android,ios,linux,macos,windows,web}` | Template stubs (`getPlatformName` method channel) + native onnxruntime binary bundling |

Test status (all run during this audit):
- `pipecat_smart_turn_platform_interface`: **62/62 pass**
- All 7 other packages: pass (trivial `getPlatformName` coverage only)

## Verification methodology

Findings marked **[verified]** were confirmed empirically, not just by code reading:

1. **Web compile check** — compiled the platform-interface library for the web target (`flutter test --platform chrome` with a temporary probe test, deleted afterwards).
2. **Model graph inspection** — parsed the bundled ONNX file with the `onnx` Python package (inputs, outputs, final graph ops).
3. **Model asset integrity** — SHA-256 of the bundled model matches the official `pipecat-ai/smart-turn-v3` HuggingFace release (`2bb02631…67e4f`). The asset itself is authentic.
4. **Feature-pipeline parity harness** — re-implemented the Dart `MelSpectrogram` numerically in NumPy, generated features with the authoritative `transformers.WhisperFeatureExtractor` (the extractor upstream smart-turn uses), and ran both through the bundled model on synthetic audio, TTS speech, and real human speech (Harvard sentences).
5. **Upstream reference** — cross-checked `pipecat-ai/smart-turn` `inference.py` preprocessing and output handling.

---

## CRITICAL

### C1. Model output is double-sigmoided — confidence values and threshold semantics are wrong **[verified]**

- `pipecat_smart_turn_platform_interface/lib/src/onnx_inference_native.dart:88-91`
- `pipecat_smart_turn_platform_interface/lib/src/onnx_inference_web.dart:73-76`
- `pipecat_smart_turn_platform_interface/lib/src/smart_turn_detector.dart:134`

The final node of the bundled ONNX graph is **`Sigmoid`** (confirmed by graph inspection; upstream `inference.py` likewise treats the output directly as a probability: `prediction = 1 if probability > 0.5`). The output tensor is named `logits` but contains a **probability in [0, 1]**.

The Dart code treats it as a raw logit: it returns `(-p, p)` and the detector applies `softmax2(-p, p)`, which equals `sigmoid(2p)`. Consequences:

- Reported `confidence` is compressed into **[0.5, 0.881]** — it can never be below 0.5 or above 0.881.
- The default `completionThreshold` of 0.7 actually fires at a true model probability of **0.42**, far more trigger-happy than intended.
- Any user-configured threshold **> 0.881 can never fire**; any threshold **< 0.5 always fires**.
- Empirically: on silence, synthetic audio, TTS speech, and real human speech the model emitted outputs of 0.96–0.99 (clear "complete"). Through the double sigmoid these map to reported confidences of 0.872–0.878 — a ~4× compression of the model's dynamic range — while a clearly "incomplete" output of e.g. 0.05 would be reported as 0.525 instead of 0.05.

**Why it matters in production:** the core product signal — "did the user finish speaking?" — is numerically wrong. Turn-taking will interrupt users early, and tuning `completionThreshold` behaves nonsensically.

**Fix:** in both `run()` implementations, treat the model output as the completion probability directly (`p_complete = output`), delete the `(-logit, logit)` / `softmax2` round-trip in `SmartTurnDetector.predict`, and keep `softmax2` only if a genuinely two-logit model variant is ever supported. No public API change: `SmartTurnResult.confidence` keeps its documented [0, 1] meaning — it starts actually honoring it.

### C2. Mel-spectrogram features do not match the model's training preprocessing **[verified]**

- `pipecat_smart_turn_platform_interface/lib/src/mel_spectrogram.dart:110` (natural `log` instead of `log10` + Whisper dynamic-range normalization)
- `mel_spectrogram.dart:185-221` (HTK mel scale, no Slaney area normalization, filter edges quantized with `floorToDouble`)
- `mel_spectrogram.dart:29-31` (FFT size 512 vs Whisper's 400)
- `pipecat_smart_turn_platform_interface/lib/src/audio_preprocessor.dart:23-48` (no waveform zero-mean/unit-variance normalization; adds a 5 ms fade-in upstream does not apply)

Upstream smart-turn generates `input_features` with `WhisperFeatureExtractor(chunk_length=8, do_normalize=True)`: Slaney-scale, area-normalized mel filters, `log10`, clamp to `max − 8`, scale `(x + 4) / 4`, plus per-utterance waveform normalization. The Dart pipeline implements none of these.

Measured feature ranges on the same audio: Dart **[−23.0, +4.3]** vs Whisper reference **[−1.07, +0.93]**. The quantized model receives inputs far outside its calibration range. On real human speech the raw model output differed materially between pipelines (e.g. 0.839 vs 0.985 for the same utterance).

**Why it matters in production:** accuracy silently degrades versus the published smart-turn v3 benchmarks. Combined with C1, predictions become both mis-scaled and mis-featured; any quality evaluation done against upstream numbers is invalid.

**Fix:** port `WhisperFeatureExtractor` semantics exactly: n_fft = 400 (no 512 zero-padding), Slaney mel scale + Slaney area normalization with float (non-floored) bin edges, `log10`, per-utterance `max − 8` clamp, `(x + 4) / 4` scaling, and zero-mean/unit-variance waveform normalization; drop the extra fade-in (or validate it against reference outputs). Add a golden test comparing `MelSpectrogram.compute` to `WhisperFeatureExtractor` output within tolerance (see T1).

### C3. Library does not compile for web, despite shipping a web implementation **[verified]**

- `pipecat_smart_turn_platform_interface/lib/src/smart_turn_detector.dart:2,13` (unconditional `dart:io` and `dart:ffi`-backed `bindings.dart` imports)
- `pipecat_smart_turn_platform_interface/lib/src/smart_turn_isolate.dart:45` and `smart_turn_detector.dart:103` (pass `onnxLibraryPath:` to the web `SmartTurnOnnxSession.initialize`, which doesn't declare that parameter — `onnx_inference_web.dart:18-21`)

Compiling for the web target fails with:

```
lib/src/platform/native/bindings/bindings.dart:2:8: Error: Dart library 'dart:ffi' is not available on this platform.
lib/src/smart_turn_detector.dart:103:9: Error: No named parameter with the name 'onnxLibraryPath'.
lib/src/smart_turn_isolate.dart:45:7: Error: No named parameter with the name 'onnxLibraryPath'.
```

The `kIsWeb` branch in `initialize()` (`smart_turn_detector.dart:53-55`), the entire `onnx_inference_web.dart`/`onnx_runtime_web.dart` implementation, and the `pipecat_smart_turn_web` package are unreachable dead code.

**Why it matters in production:** any consumer app with a web target fails to build. CI never catches this because no workflow compiles the platform interface for web.

**Fix:** route platform-specific code through conditional imports: move `resolveOnnxLibraryPath()` behind the existing `onnx_inference.dart` conditional-export pattern (stub returns `null`), extract model-file extraction (`dart:io`, `path_provider`) into a conditionally imported helper, and add `onnxLibraryPath` as an (ignored) parameter to the web/stub `initialize()`. Add a web compile check to CI (see T4).

### C4. Windows never bundles onnxruntime.dll — CMake variable-name typo

`pipecat_smart_turn_windows/windows/CMakeLists.txt:30` sets `pipecat_smart_turn_bundled_libraries`, but Flutter's generated aggregator (`example/windows/flutter/generated_plugins.cmake:19`) reads `pipecat_smart_turn_windows_bundled_libraries`. The DLL is never copied next to the executable, so `DynamicLibrary.open('<exe dir>/onnxruntime.dll')` (`bindings.dart:18-21`) fails at runtime on every Windows machine. (Linux uses the correctly suffixed variable.)

**Fix:** rename the variable to `pipecat_smart_turn_windows_bundled_libraries`.

### C5. x64 native binaries missing — Linux/Windows fail on the dominant desktop architecture

Only `arm64` binaries are committed: `pipecat_smart_turn_linux/linux/arm64/libonnxruntime.so.1.24.2` and `pipecat_smart_turn_windows/windows/arm64/onnxruntime.dll`. The x64 paths referenced by `pipecat_smart_turn_linux/linux/CMakeLists.txt:32-37` and `pipecat_smart_turn_windows/windows/CMakeLists.txt:19-23` don't exist; `if(EXISTS)` guards skip them **silently**, producing builds with no onnxruntime at all → FFI load failure at first `initialize()`.

**Fix:** commit or download-at-build the x64 binaries; make CMake fail loudly (`message(FATAL_ERROR …)`) when the expected binary for the target arch is absent.

### C6. App-facing package endorses no platform implementations

`pipecat_smart_turn/pubspec.yaml` deliberately omits the `flutter: plugin: platforms: … default_package:` block. A consumer depending only on `pipecat_smart_turn` gets: no platform package, no native onnxruntime bundled, and `MissingPluginException` from the default method channel (`method_channel_pipecat_smart_turn.dart:9`). The example app itself lists only `_android`, `_linux`, `_windows` (`example/pubspec.yaml:21-26`), so the example is broken on iOS/macOS/web.

**Fix:** add the plugin block with `default_package` entries for all six platforms and add the three missing path-deps to the example. (Pubspec metadata change — not a Dart API change.)

---

## HIGH

### H1. Default mode reloads the 8.6 MB model on **every** prediction

`smart_turn_isolate.dart:39-54,99`: with `useIsolate: true` (the default and the documented production recommendation), each `predict()` runs `compute(_runInference, …)`, which creates an ORT env, **reads and deserializes the model from disk, builds a session, runs one inference, and destroys everything**. Model load typically dwarfs the 10–150 ms inference itself; on low-end mobile this can add hundreds of ms of latency and significant CPU/battery churn per utterance-end check, and it defeats ORT's session warm-up.

**Fix:** replace `compute()`-per-call with a long-lived worker isolate (spawn once in `spawn()`, keep the session alive, communicate via `SendPort`/`ReceivePort`, tear down in `kill()`). Public API (`spawn`/`predict`/`kill`) unchanged.

### H2. Native memory leaks in the FFI layer (per-inference leak in persistent-session mode)

- `ort_session.dart:170,179`: the `toNativeUtf8()` allocations for input/output names are never freed — only the pointer arrays are (`:228-232`). Leaks every `run()` call.
- `ort_session.dart:160-234`: no `try/finally`; if `Run` fails, all six native allocations leak.
- `onnx_inference_native.dart:62-107`: `inputTensor.release()`/`runOptions.release()`/output releases (`:94-98`) are skipped when an exception is thrown mid-run — the 256 KB input tensor leaks on every failed inference.
- `ort_env.dart:65`: `logId.toNativeUtf8()` leaked (once per env creation — which is per-prediction under H1).
- `ort_value.dart:106-150`: `dataPtr`, `shapePtr`, and the memory-info pointers leak if any status check throws.

**Why it matters in production:** a voice pipeline calls `predict()` continuously for the app's lifetime. In non-isolate mode leaks accumulate in-process; in isolate mode H1 currently masks them (isolate death frees memory) — fixing H1 without fixing this converts a latency bug into a leak.

**Fix:** wrap `run()` bodies in `try/finally`, free every `toNativeUtf8()` result, and release tensors/options in `finally` blocks.

### H3. `dispose()` during in-flight prediction → use-after-free risk

`smart_turn_detector.dart:150-156` releases the session/isolate without checking `_isProcessing`. In non-isolate mode, `dispose()` while `_session.run()` is awaiting native `Run` releases the `OrtSession` under an active native call — undefined behavior/crash in onnxruntime. Typical trigger: user closes the voice screen while an inference is running.

**Fix:** make `dispose()` await any in-flight `predict()` (track the pending future) before releasing; guard `predict()` against post-dispose calls (`_isInitialized` already handles this once dispose ordering is fixed).

### H4. No timeout around inference — one hang permanently disables the detector

`smart_turn_detector.dart:118-147`: `predict()` awaits the isolate/session with no timeout. If the native call hangs (corrupt model, ORT bug, wasm stall), `_isProcessing` stays `true` forever and the backpressure gate at `:122` silently returns `null` for **every subsequent call**. The voice UX degrades to "never completes a turn" with zero signal.

**Fix:** wrap the await in `Future.timeout` (config value, e.g. `inferenceTimeout` defaulting to a few seconds — additive, non-breaking config field), reset `_isProcessing`, and surface a `SmartTurnInferenceException`.

### H5. Model asset extraction is not atomic — a corrupted file bricks initialization forever

`smart_turn_detector.dart:63-74`: extraction writes directly to the final path and skips extraction whenever the file exists. If the process dies mid-`writeAsBytes` (app kill, crash, out-of-disk), a truncated model persists; every later launch sees `existsSync() == true`, loads the corrupt file, and fails — until the user clears app data.

**Fix:** write to a temp file and `rename()` (atomic on the same filesystem), and/or validate the extracted file length against `byteData.lengthInBytes` before use. Also re-extract when the bundled model version changes (filename currently encodes the version, which helps — but keep it in one constant, see M8).

### H6. Broken end-to-end CI: Fluttium flow tests a UI that no longer exists

E2E jobs live in `.github/workflows/pipecat_smart_turn.yaml` (`ci.yaml` itself is only a semantic-PR-title check):

- `example/flows/test_platform_name.yaml:3` presses `"Get Platform Name"` — no such button exists in the rewritten example (`example/lib/main.dart:448,485` has `TEST (Zero)`, `LIVE MIC`/`STOP`).
- `example/actions/check_platform_name/lib/src/check_platform_name.dart:56` asserts `'Platform Name: …'` but the app renders `'Platform: …'` (`main.dart:353`).
- `pipecat_smart_turn.yaml:171` targets the retired `windows-2019` runner (removed by GitHub mid-2025) — job cannot schedule. The macOS E2E job pins `macos-13` (`:135`), also past GitHub's retirement window and due to stop scheduling if it hasn't already.
- The Linux E2E job is permanently disabled with `if: false` (`pipecat_smart_turn.yaml:113`, TODO referencing a Fluttium issue).
- The correct test (`example/integration_test/app_test.dart`, asserts `'Platform: …'`) is wired to **no** workflow.
- Even with the flow fixed, the Android assertion still fails: the Kotlin plugin returns `"Android ${Build.VERSION.RELEASE}"` (e.g. `Android 14`), while both test suites expect exactly `Android` (`PipecatSmartTurnPlugin.kt:21`, `check_platform_name.dart:45`, `app_test.dart:25`).

**Why it matters in production:** every platform E2E job fails (or can't run), so CI provides no release gate — regressions like C3–C5 ship undetected.

**Fix:** delete/replace the Fluttium flow with the existing `integration_test`, run it in CI, move Windows E2E to `windows-2022`, drop the version suffix from the Android platform name (or relax the assertions).

### H7. Android minSdk 19 is below onnxruntime-android's minimum

`pipecat_smart_turn_android/android/build.gradle:38` declares `minSdkVersion 19`; `onnxruntime-android:1.24.2` (`:42`) requires API 21+. Manifest merge fails at consumer build time, or if overridden, crashes at library load on API < 21 devices.
**Fix:** raise to 21 (or onnxruntime's current floor).

### H8. Apple builds under Swift Package Manager get no onnxruntime

`pipecat_smart_turn_ios/ios/pipecat_smart_turn_ios/Package.swift:14` and the macOS equivalent declare `dependencies: []`; only the CocoaPods podspecs pull `onnxruntime-objc`. Projects using Flutter's SPM integration link no onnxruntime → `DynamicLibrary.process()` lookups fail at runtime.
**Fix:** add the onnxruntime SPM dependency to both `Package.swift` files, or explicitly document CocoaPods-only support.

---

## MEDIUM

### M1. `computeRms` returns mean-square, not RMS

`audio_preprocessor.dart:100-107`: missing `sqrt`. The VAD is internally self-consistent, but: (a) the public name/doc is wrong for anyone using it directly; (b) `EnergyVad.silenceThreshold = 2.0` acts as 2× on **energy** = only ~1.41× on amplitude — tuned constants don't mean what they say; (c) `_noiseFloor = 0.01` initial value (`vad_detector.dart:45`) is speech-level in mean-square units (see M2).
**Fix:** add `sqrt` and re-verify VAD constants, or rename to `computeMeanSquareEnergy` and document units. (Renaming is API-breaking — prefer adding `sqrt` and retuning constants.)

### M2. VAD noise floor starts at speech level and adapts slowly

`vad_detector.dart:45,54-58`: initial `_noiseFloor = 0.01` in mean-square units is typical *speech* energy; with EMA weight 0.98 it needs ~115 quiet frames to decay 10×. For the first several seconds after construction, quiet speech may be classified as silence. `reset()` (`:83-86`) intentionally keeps the floor, but nothing lets a caller re-seed it.
**Fix:** start the floor near a realistic ambient value for the chosen units (after M1), or calibrate from the first N frames; document the warm-up.

### M3. `MelSpectrogram` uses shared static mutable buffers — not reentrant

`mel_spectrogram.dart:51-52`: `_real`/`_imag` are static and mutated by `compute()`. Two `SmartTurnDetector`s with `useIsolate: false` (or any concurrent direct use in one isolate) interleave writes and corrupt features silently.
**Fix:** allocate per-call or per-instance buffers (the 8 KB allocation is trivial next to the 800-frame loop).

### M4. Error handling gaps in the isolate path

- `smart_turn_isolate.dart:100-102`: catches `on Exception` only — `Error`s (e.g. `ArgumentError` from `openOnnxLibrary`, OOM in `compute`) escape unwrapped, bypassing the package's sealed exception hierarchy.
- `kill()` (`:106-108`) only nulls a string; the name implies worker teardown. Harmless today, misleading after H1's fix.
- `smart_turn_detector.dart:47-108`: two concurrent `initialize()` calls both run the full path (flag set only at the end) — double extraction/session creation.
**Fix:** catch `Object` and rethrow wrapped; guard `initialize()` with an in-flight future.

### M5. iOS/macOS native handler answers every method with the platform name

`PipecatSmartTurnPlugin.swift:11-13` (both packages) never inspects `call.method` and never returns `notImplemented` — unknown methods succeed with a bogus string, masking integration errors. Android/Windows/Linux do this correctly.
**Fix:** switch on `call.method`.

### M6. No logging/observability hooks

No logging exists anywhere in `lib/` — initialization milestones, extraction, inference failures, backpressure drops (`smart_turn_detector.dart:122` silently returns `null`) are all invisible. ORT's native log level is hardcoded to `warning` with no configuration path (`ort_env.dart:53-56`). In production, "turn detection feels wrong" is undiagnosable.
**Fix (non-breaking):** add an optional `onLog`/`logger` callback (or `package:logging`) covering init, extraction, inference latency, dropped frames, and errors; expose ORT log level through `SmartTurnConfig`.

### M7. Silent CI quality-gate fragility and coverage holes

- `pana.yaml:47`: `SCORE=SCORE_ARR[0]` assigns a literal string; the gate only works by accidental arithmetic re-evaluation on the next line.
- Package workflows pin Flutter `3.41.1` while E2E/pana jobs float on `stable` — builds and tests use different toolchains.
- `license_check.yaml` covers only 2 of 8 packages and ignores the bundled onnxruntime binaries' licenses.
**Fix:** `SCORE=${SCORE_ARR[0]}`, pin one Flutter version repo-wide, extend license check.

### M8. Configuration values duplicated/hardcoded

- Model filename/asset path appears in three places: `smart_turn_detector.dart:55,60,66`.
- onnxruntime version is baked into a path string: `bindings.dart:16` (`libonnxruntime.so.1.24.2`) — must be kept in lockstep with the binaries committed in the Linux package and the versions in `build.gradle`/podspecs, with no single source of truth and no cross-check.
**Fix:** single `const` for model asset name; a shared constant (or generated file) for the ORT version referenced by CMake/gradle/podspec docs.

### M9. Audio utility edge cases

- `audio_preprocessor.dart:72-78` (`bytesToFloat32`): odd `lengthInBytes` silently drops the trailing byte — a misaligned upstream chunk shifts all subsequent samples; worth an assert/log.
- `audio_preprocessor.dart:91-97` (`resample48To16`): naive decimation without an anti-aliasing filter folds 8–24 kHz content into the band the model sees; the doc admits it. Fine as a labeled fallback, dangerous if a consumer treats it as production-ready.
- `mel_spectrogram.dart:224-239` (`_centreReflectPad`): crashes on inputs shorter than `padSize + 2` — unreachable via `SmartTurnDetector` (prepareInput pads to 128 k) but public and unguarded.

### M10. Example app metadata / platform gaps (see also C6)

Podspecs ship `http://example.com` / `email@example.com` and version `0.0.1` vs pubspec `0.1.0+1` (`pipecat_smart_turn_ios/ios/pipecat_smart_turn_ios.podspec:6,11-13`, macOS same). Both podspecs declare `license { :type => 'BSD' }` while the repository `LICENSE` (and README badge) is **MIT** — contradictory license metadata in a published pod. macOS deployment target is inconsistent: podspec says unversioned `s.platform = :osx` (`pipecat_smart_turn_macos.podspec:19`) while `Package.swift:9` pins `.macOS("10.15")`; both should be verified against `onnxruntime-objc` 1.24.2's minimum before release. macOS native returns `"macOS"` while Dart tests expect `"MacOS"` (`PipecatSmartTurnPlugin.swift:12` vs `app_test.dart:27`). Blocks/embarrasses a pub.dev release; the casing bug will fail the first real macOS E2E.

---

## LOW

- **L1** — `pipecat_smart_turn/lib/pipecat_smart_turn.dart:6`: `PipecatSmartTurn.version` hardcodes `'0.0.1'` (pubspec: `0.1.0+1`). Dead demo API in the public surface.
- **L2** — `ort_env.dart:73-81,84-90`: `OrtEnv.version` crashes with a null assertion if called after `release()`; `OrtAllocator` caches a pointer that survives env release.
- **L3** — Linux plugin `dispose` never unrefs `registrar`/`channel` (`pipecat_smart_turn_linux_plugin.cc:39-41`) — app-lifetime leak, cosmetic.
- **L4** — `windows/CMakeLists.txt:19-28` has `if(EXISTS)` guards but no architecture selection: if both x64 and arm64 DLLs are present it bundles **both** (Linux correctly branches on `CMAKE_SYSTEM_PROCESSOR`).
- **L5** — `dependabot.yaml`: pub ecosystem entries are mostly no-ops (path deps); `enable-beta-ecosystems: true` is stale.
- **L6** — `.github/workflows/pipecat_smart_turn.yaml:42`: Android E2E on `macos-latest` (~10× the cost of `ubuntu-latest` for an emulator job).
- **L7** — README is untouched Very Good CLI boilerplate: no usage docs, no platform-support matrix, no threshold guidance, and no mention that web consumers must add the `onnxruntime-web` script tag to their `index.html` (the example does it at `example/web/index.html:35`, but nothing documents it). The only real docs live in `docs/` design documents.
- **L8** — No integrity check (size/hash) on the extracted model at load time (compounds H5).
- **L9** — All packages are `publish_to: none` with path dependencies — the federated split currently provides no distribution benefit and blocks publishing as-is.
- **L10** — `list_shape_extension.dart` `flatten` silently drops non-`T` elements — type mistakes vanish instead of throwing (internal-only today).

### Security review

No hardcoded secrets, tokens, or credentials anywhere (verified by sweep). No network calls in library code (model is bundled; web loads it as an asset URL). No injection surfaces. Native attack surface is limited to the bundled, hash-verified ONNX model parsed by onnxruntime — supply-chain risk is the committed binary blobs (`libonnxruntime.so.1.24.2`, `onnxruntime.dll`), which have no provenance/checksum documentation in-repo (**recommend**: record upstream release URLs + SHA-256 in a `THIRD_PARTY.md`, verify in CI). Dependency versions (`ffi`, `path_provider`, `plugin_platform_interface`) are current; several of the example's transitive `record_*` platform packages have newer majors available (constraint-limited) — cosmetic, not a security exposure. Note the example's web page loads `onnxruntime-web` from the jsDelivr CDN (`example/web/index.html:35`) — an external runtime dependency consumers should be told to pin/self-host (and which is required but undocumented, see L7).

---

## Test coverage gaps on critical paths

- **T1 — No feature-parity golden test.** Nothing compares `MelSpectrogram.compute` against `WhisperFeatureExtractor` reference output. Would have caught C2. Add a checked-in golden feature matrix for a short reference WAV.
- **T2 — No real-model inference test.** The model ships in the repo, yet no test loads it and asserts sane output on known audio (or even that output ∈ [0,1]). Would have caught C1. The entire FFI layer (`ort_*.dart`, ~1,000 lines) is `coverage:ignore`d and untested.
- **T3 — Isolate path untested end-to-end.** `_runInference` and the `compute` round-trip are coverage-ignored; `SmartTurnIsolate` tests only check config storage.
- **T4 — No web-target compile or test job.** `flutter test --platform chrome` (or `flutter build web` on the example) in CI would have caught C3 immediately.
- **T5 — Platform packages test only the dead `getPlatformName` demo channel**; no test exercises native library bundling or FFI loading per platform (would have caught C4/C5). Native Kotlin/Swift/C++ has zero tests.
- **T6 — No dispose/lifecycle/leak tests** (H2/H3): repeated init→predict→dispose cycles, dispose-during-predict.
- **T7 — Integration test exists but is not run in CI** (H6).

## Performance risks summary

| Risk | Ref |
|---|---|
| Model reload per prediction (default mode) | H1 |
| Native memory leaks per inference | H2 |
| `useIsolate: false` runs mel (800×512 FFT + 80×257 matmul ≈ tens of ms) **and** ORT on the UI thread | config doc says so, but default example encourages toggling |
| No inference timeout → permanent silent stall | H4 |
| Extra copies: model bytes duplicated into native buffer per session create (`ort_session.dart:18-19`), features flattened via growable `List<double>` (`ort_value.dart:89-94`) | minor next to H1 |

## Deployment readiness

Server-style items (health checks, Dockerfile, migrations) don't apply to a Flutter plugin. The equivalents:

| Item | Status |
|---|---|
| Consumers can depend on the plugin and get working native bits | ❌ C4, C5, C6, H7, H8 |
| All claimed platforms build | ❌ web (C3), Windows/Linux x64 (C4/C5) |
| CI release gate | ❌ E2E broken (H6), pana gate fragile (M7) |
| Publishable metadata | ❌ `publish_to: none`, boilerplate README (L7/L9/M10) |
| Model/runtime provenance | ⚠️ model hash verified against upstream (done in this audit); native binaries undocumented (Security) |
| Graceful shutdown | ⚠️ `dispose()` exists but unsafe mid-inference (H3) |

---

## Suggested fix order

1. **C1 + C2** (prediction correctness) with T1/T2 regression tests.
2. **C3** (web compile) + T4 CI job.
3. **C4/C5/C6** (native bundling & endorsement) so the plugin actually runs everywhere it claims.
4. **H1–H5** (performance + lifecycle robustness).
5. **H6–H8, M-tier** (CI, platform hygiene), then L-tier cleanups.

All proposed fixes preserve the existing public API (`SmartTurnDetector`, `SmartTurnConfig`, `SmartTurnResult`, `EnergyVad`, `AudioBuffer`, preprocessing statics); additions are backwards-compatible optional parameters/config fields only.
