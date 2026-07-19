# Production Readiness Audit - pipecat_smart_turn

**Original audit date:** 2026-07-11
**Current review date:** 2026-07-19
**Scope:** Current working tree, including uncommitted remediation work across all 8
packages, native code, CI, docs, and tests.
**Review type:** Documentation update against current code. No production source
changes are part of this document update.

---

## Current status

The 2026-07-11 audit is no longer an accurate description of the current working
tree. Several original critical and high-severity issues have been addressed in
source, but the package is still not production-ready.

The most important remaining blockers are:

- Linux and Windows x64 ONNX Runtime binaries are still absent, and native CMake
  still silently omits missing runtime libraries.
- The new long-lived worker isolate fixes the old per-prediction model reload,
  but introduces a response-correlation bug: late or early responses can be
  delivered to the wrong request because worker messages have no request IDs.
- Native FFI cleanup remains exception-unsafe. This is more serious now that the
  default native path keeps an ONNX session alive across predictions.
- The preprocessing pipeline has been substantially rewritten toward Whisper
  semantics, but parity is not independently proven against upstream
  `WhisperFeatureExtractor` output.
- CI coverage improved, but platform workflows still do not cover all package
  changes, and current local verification was not completed successfully during
  this update.

Historical claims from the original audit, including "62/62 pass" and "all 7
other packages pass", should be treated as 2026-07-11 evidence only.

---

## Stack

Flutter federated plugin for on-device end-of-turn detection using the pipecat
`smart-turn-v3.2-cpu.onnx` model.

| Package | Role |
|---|---|
| `pipecat_smart_turn` | App-facing umbrella package that re-exports the platform interface and now endorses platform implementations. |
| `pipecat_smart_turn_platform_interface` | Real Dart logic: `SmartTurnDetector`, VAD, audio preprocessing, mel spectrogram, ONNX Runtime wrappers, native/web inference, and isolate offloading. |
| `pipecat_smart_turn_android` | Android plugin and ONNX Runtime Android dependency metadata. |
| `pipecat_smart_turn_ios` | iOS plugin, CocoaPods metadata, and SPM runtime declaration. |
| `pipecat_smart_turn_linux` | Linux plugin and native ONNX Runtime bundling. |
| `pipecat_smart_turn_macos` | macOS plugin, CocoaPods metadata, and SPM runtime declaration. |
| `pipecat_smart_turn_windows` | Windows plugin and native ONNX Runtime DLL bundling. |
| `pipecat_smart_turn_web` | Web plugin wrapper; real web inference lives in the platform interface via `onnxruntime-web` interop. |

---

## Remediation summary

| Original finding | Current status | Notes |
|---|---:|---|
| C1 double-sigmoid output handling | Fixed in source | Native/web inference now return a single probability and detector compares it directly to `completionThreshold`. |
| C2 preprocessing mismatch | Partially fixed | n_fft, log10 scaling, Slaney filters, and waveform normalization were changed, but no upstream golden proves parity. |
| C3 web compile architecture | Fixed in source | Platform-specific inference is now behind conditional imports. Needs CI evidence. |
| C4 Windows bundled-library variable typo | Fixed in source | Variable is now `pipecat_smart_turn_windows_bundled_libraries`. |
| C5 x64 native binaries missing | Open | x64 Linux/Windows binaries are still absent; CMake silently skips missing libraries. |
| C6 umbrella package endorsement | Fixed in source | Platform `default_package` entries were added. |
| H1 model reload per prediction | Fixed with regression | Long-lived worker isolate now keeps the session alive, but the request protocol is unsafe. |
| H2 native memory leaks / exception cleanup | Open | Happy-path cleanup exists in some places; failure paths still leak or skip release. |
| H3 dispose during in-flight prediction | Partially fixed | Detector waits on `_isProcessing`, but timeouts and isolate kill can still race with native work. |
| H4 no inference timeout | Partially fixed | Isolate/web path has a 2 second timeout; non-isolate native path still has none, and late responses can corrupt later requests. |
| H5 model extraction atomicity | Partially fixed | New extraction writes temp then renames, but existing files are not size/hash validated. |
| H6 broken E2E CI | Partially fixed | Fluttium was replaced by integration tests and current runners, but workflow path filters miss many package changes. |
| H7 Android minSdk | Fixed in source | Android minSdk is now 21. |
| H8 Apple SPM runtime declaration | Fixed in source | iOS/macOS Package.swift files declare ONNX Runtime. |
| M1 RMS calculation | Fixed in source | `computeRms` now returns square root of mean square. |
| M2 VAD noise floor | Partially fixed | Units changed with RMS fix, but warm-up and calibration still need production validation. |
| M3 shared mel buffers | Fixed in source | Mel buffers are per-call rather than shared static mutable state. |
| M4 isolate/init error handling | Partially fixed | `initialize()` is serialized, but worker protocol and some error correlation remain unsafe. |
| M5 Apple method dispatch | Fixed in source | iOS/macOS now dispatch by method instead of answering all calls. |
| M6 observability | Open | Still no logging or diagnostics hooks for inference, drops, extraction, or ORT state. |
| M7 CI quality gates | Partially fixed | Pana/license work improved, but Flutter versions and coverage remain inconsistent. |
| M8 duplicated constants | Partially fixed | Dart model constants exist; native/runtime version constants are still duplicated across build systems. |
| M9 audio utility edge cases | Partially fixed | Odd byte length is assert-only in release; decimation remains a documented fallback. |
| M10 package metadata | Partially fixed | Some metadata was updated, but release-readiness still needs a final package-by-package pass. |
| L6 Android CI runner cost | Fixed in source | Android E2E now runs on Ubuntu. |

---

## Current critical findings

### C5. x64 native binaries are still missing

Linux and Windows still only have committed ARM64 ONNX Runtime binaries. The
Linux CMake file references `linux/x64/libonnxruntime.so.1.24.2`; the Windows
CMake file references `windows/x64/onnxruntime.dll`. Those paths do not exist in
the current tree.

Current behavior is still dangerous:

- Linux selects the expected binary by `CMAKE_SYSTEM_PROCESSOR`, but silently
  appends nothing if the selected binary is absent.
- Windows appends any DLL path that exists, without architecture selection, and
  silently appends nothing for missing paths.
- A consumer can build successfully and fail only at runtime when
  `DynamicLibrary.open` cannot load ONNX Runtime.

**Required fix:** commit or reliably download x64 Linux and Windows ONNX Runtime
binaries, select by target architecture, and fail CMake with `message(FATAL_ERROR
...)` when the expected runtime is absent.

### C7. Worker isolate responses are not correlated to requests

The current long-lived isolate protocol uses `_WorkerRequest` and
`_WorkerResponse`, but neither message includes a request ID. `predict()` sends
one request and awaits `_responseStream.stream.first`.

This has two production failure modes:

- During `spawn()`, a fast initialization response can be added to the broadcast
  stream before the `.first` subscriber is attached. Broadcast streams do not
  buffer events for later subscribers.
- If inference request A times out, the worker can still finish A later. The next
  request B awaits the first response and may receive A's stale result.

The second case is a correctness bug: a user can receive a completion probability
for the wrong audio window.

**Required fix:** add monotonic request IDs to worker requests/responses, keep a
pending completer map by ID, complete only the matching request, and decide a
clear policy for timed-out requests. The safest policy after native timeout is to
restart the worker isolate so late native results cannot contaminate later
predictions.

### C8. Native FFI cleanup is still exception-unsafe

The persistent-session work makes this more important than in the original
audit. The old per-call isolate masked some native leaks by terminating the
isolate after each inference; the default native path now keeps native state
alive.

Remaining cleanup risks include:

- `SmartTurnOnnxSession.run()` releases `inputTensor`, `runOptions`, and outputs
  only on the happy path.
- `OrtSession.run()` still allocates native input/output name pointers and other
  native structures without full `try/finally` cleanup across every failure path.
- `OrtEnv` and `OrtValue` helpers still contain native allocations that are not
  consistently released if a status check throws partway through setup.

**Required fix:** wrap every native allocation owner in `try/finally`, free every
`toNativeUtf8()` result, and release tensors/options/outputs even when ORT throws.
Add repeated failure-path tests where possible, and use leak tooling for native
platform validation.

---

## Current high findings

### H1. Preprocessing parity is improved but not proven

The implementation now matches several Whisper preprocessing requirements:

- `kNFft`/`kFftSize` are 400.
- Mel filters use Slaney scale and Slaney area normalization.
- Log compression uses log10 and Whisper-style `max - 8` clamp plus `(x + 4) / 4`.
- Audio preparation applies zero-mean/unit-variance normalization.
- The prior extra fade-in was removed from behavior.

However, correctness is not established until the produced feature matrix is
compared against upstream `WhisperFeatureExtractor` output for fixed audio. The
current golden test is a repo-generated regression snapshot; it does not prove
parity against the reference implementation that smart-turn was trained with.

**Required fix:** check in a reference WAV or deterministic PCM fixture and a
golden feature matrix generated by upstream `transformers.WhisperFeatureExtractor`.
Assert shape and numeric tolerance against Dart output.

### H2. Mel spectrogram performance regressed from FFT to direct DFT

The current `MelSpectrogram` documentation says it uses a pure-Dart radix-2 FFT,
but the implementation calls `_computeDft`, which loops over every positive
frequency bin and every sample.

For one 8 second input this is approximately:

- 800 frames
- 201 frequency bins
- 400 samples per bin
- about 64 million multiply/add operations, plus cached trig table reads

That may be acceptable on desktop, but it is a significant risk on mobile and
web, especially when followed by ONNX inference. The original performance summary
talked about an FFT-based cost and is now stale.

**Required fix:** either restore an actual FFT implementation for `kFftSize ==
400` semantics, use an efficient real-FFT approach with correct Whisper parity,
or benchmark and document that the direct DFT stays inside latency budgets on
target devices.

### H3. Inference timeout behavior is incomplete

The isolate/web path applies a fixed 2 second timeout. The non-isolate native path
still awaits `_session.run()` with no timeout.

The isolate timeout is also unsafe without request IDs. Timing out clears
`SmartTurnDetector._isProcessing` in `finally`, so a later `predict()` can be
accepted while the old native call may still complete in the worker.

**Required fix:** make timeout configurable, apply it consistently, and pair it
with request IDs and a worker restart/quarantine policy after timeout.

### H4. `dispose()` is safer but not fully race-free

`SmartTurnDetector.dispose()` now marks the detector uninitialized and waits while
`_isProcessing` is true. That addresses the original straightforward
dispose-during-predict case.

Residual risks remain:

- `_isProcessing` is cleared when `predict()` times out, even if the worker's
  native inference is still executing.
- `SmartTurnIsolate.kill()` sends a dispose message and immediately kills the
  isolate with `Isolate.immediate`, so native cleanup ordering is not well
  defined.
- Non-isolate native inference still lacks a timeout and can keep dispose waiting
  indefinitely.

**Required fix:** track the actual pending inference future and completion state,
make kill/dispose deterministic, and treat a timed-out worker as poisoned unless
it can prove the stale response has been drained and ignored.

### H5. Model extraction is atomic but existing files are not validated

`extractBundledModel()` now writes to `*.tmp` and renames to the final model path.
That fixes the original direct-write corruption window.

It still trusts any existing file. A truncated or stale model at the destination
will be reused forever until app data is cleared.

**Required fix:** validate file size at minimum, preferably SHA-256, against the
bundled asset. Re-extract when validation fails.

### H6. CI is improved but still misses release-gating scenarios

The old Fluttium workflow has been replaced with `integration_test` jobs and
current runners, including Ubuntu Android and Windows 2022. That fixes several
original CI breakages.

Remaining gaps:

- The umbrella workflow triggers only for `.github/workflows/pipecat_smart_turn.yaml`
  and `pipecat_smart_turn/**`. Changes in `pipecat_smart_turn_platform_interface`
  and platform packages can bypass these E2E jobs.
- Toolchain versions are not consistent across workflows.
- Native binary bundling is still not tested in a way that would catch missing
  x64 runtimes before runtime.

**Required fix:** broaden workflow path filters to all federated packages, pin one
Flutter version intentionally, and add platform checks that verify the expected
ONNX Runtime binary is present for the runner architecture.

---

## Current medium findings

### M1. Stub API type drift

The native and web `SmartTurnOnnxSession.run()` APIs now return `double`, but the
stub implementation must be kept in lockstep. Any remaining stub signature or
return shape that still represents two logits will break analysis or unsupported
platform builds.

**Required fix:** keep native, web, and stub inference surfaces identical and add
a compile test that exercises unsupported/native/web conditional exports.

### M2. Code comments still contain stale preprocessing claims

`AudioPreprocessor.prepareInput()` documentation still mentions a 5 ms fade-in,
but the implementation no longer applies one. `SmartTurnOnnxSession.run()` still
documents a raw-logit return even though it now returns a probability.

**Required fix:** update comments so API readers do not tune behavior around
removed or obsolete preprocessing/output semantics.

### M3. VAD calibration still needs validation after RMS fix

`computeRms()` now returns true RMS, which fixes the unit bug. Thresholds and
noise-floor adaptation behavior still need validation under real microphone
conditions because the numeric scale changed relative to the original
mean-square behavior.

**Required fix:** add fixtures or integration tests covering quiet speech,
background noise, and startup warm-up behavior.

### M4. Model/runtime constants are only partially centralized

The Dart model filename and asset path have moved to constants. ONNX Runtime
version and binary names remain duplicated across FFI bindings, CMake, Gradle,
podspec/SPM files, and committed binary paths.

**Required fix:** document a single runtime-version update procedure, or generate
the repeated native package values from one source.

### M5. Audio utility edge cases remain

`bytesToFloat32()` has an even-length `assert`, but asserts are disabled in
release. Odd byte chunks will still be truncated by integer division. The
48kHz-to-16kHz converter remains naive decimation without anti-alias filtering,
which is acceptable only as a clearly documented fallback.

**Required fix:** throw a real `ArgumentError` for odd byte lengths in release and
avoid presenting naive decimation as production resampling.

### M6. Observability is still absent

There are still no library-level hooks for initialization, model extraction,
inference latency, dropped predictions, timeout, worker restart, or native load
errors.

**Required fix:** add a minimal optional logging callback or diagnostic stream to
`SmartTurnConfig`, without introducing a third-party dependency into the core
library.

---

## Lower-priority release hygiene

- README and public usage documentation still need a platform support matrix,
  threshold guidance, setup requirements, and web `onnxruntime-web` script
  instructions.
- Published package metadata still needs a final consistency pass across
  pubspecs, podspecs, package versions, license declarations, authors, and
  homepage fields.
- Native binary provenance is still not documented in repo. Add release URLs,
  checksums, licenses, and a CI validation step for committed binaries.
- `publish_to: none` and path dependencies still mean the federated split is not
  publish-ready.
- Tests for native bundling, lifecycle, repeated init/predict/dispose, timeout,
  worker restart, and web compile remain release blockers.

---

## Current verification status

This document update is based on code review of the current working tree and the
prior independent review. It intentionally does not claim a passing test run.

Attempted local verification during the 2026-07-19 review did not produce a
reliable pass/fail summary because environment setup emitted sudo-password
errors, and later Flutter test invocations did not return a complete result
summary through the local command wrapper.

Before treating this package as production-ready, collect clean output for:

```bash
source setup.sh
cd pipecat_smart_turn_platform_interface
flutter test
flutter test --platform chrome
flutter analyze
cd ../pipecat_smart_turn/example
flutter test integration_test/app_test.dart -d linux
flutter test integration_test/app_test.dart -d chrome
```

Native platform smoke tests should also verify that ONNX Runtime is actually
bundled and loadable on Android, iOS, macOS, Linux x64, Linux ARM64, Windows x64,
and Windows ARM64.

---

## Suggested fix order

1. Fix C5 by adding/verifying x64 binaries and making CMake fail loudly for
   missing architecture-specific runtimes.
2. Fix the isolate protocol with request IDs, timeout quarantine/restart, and
   deterministic dispose semantics.
3. Make FFI allocation cleanup exception-safe across session/env/value/run paths.
4. Prove preprocessing parity with an upstream-generated golden fixture.
5. Benchmark or replace the direct DFT implementation.
6. Broaden CI path filters and add native runtime bundling checks.
7. Clean up stale comments, package metadata, release docs, and observability.

All currently recommended fixes can preserve the public Dart API. The likely
backwards-compatible additions are timeout configuration and optional diagnostic
callbacks.
