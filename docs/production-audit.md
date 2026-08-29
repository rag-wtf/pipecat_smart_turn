# Production Readiness Audit — pipecat_smart_turn

**Audit date:** 2026-08-28
**Baseline:** commit `80ba3b3` (main). All `lib/`, `test/`, build, and CI
files verified identical to HEAD; the working tree additionally carries
uncommitted `analyzer: exclude:` blocks in each package's
`analysis_options.yaml` (added to scope `flutter analyze` to Dart sources —
they affect no `lib/`/`test/` diagnostics) that should be committed with
the remediation, plus one stray zero-byte untracked file at the repo root
literally named `Float64List(kNFreqs)` — a shell-redirect accident that
should simply be deleted.
**Scope:** All 8 federated packages, native build files (CMake, Gradle,
podspec/SPM), CI workflows, tests, and docs.
**Method:** Full source read of every core Dart file plus native plugin
sources, verified by local `flutter test` runs for every package and
`flutter analyze` on the platform interface. Every finding below cites the
evidence it was verified against. This audit supersedes the 2026-07-19
document; a delta against that audit's findings is at the end.

---

## Verdict

**Not releasable in its current state.** The tree at `80ba3b3` does not
compile: the 2026-07-23 remediation commits landed the new
`SmartTurnDetector` (timeout + logging) and its tests, but not the matching
`SmartTurnConfig` / `SmartTurnIsolate` changes. Every package's test suite
fails to load, and `flutter analyze` reports hard errors. Main is broken and
CI cannot have passed on it.

Beyond the compile break, three of the four remaining critical issues from
the previous audit are still open (missing x64 runtimes — now with the root
cause identified, uncorrelated isolate responses, unproven Whisper parity),
plus new findings in the VAD, the isolate lifecycle, and FFI cleanup.

---

## Stack

Flutter federated plugin for on-device end-of-turn detection using the
pipecat `smart-turn-v3.2-cpu.onnx` model (bundled, 8.7 MB).

| Package | Role |
|---|---|
| `pipecat_smart_turn` | Umbrella package; re-exports the platform interface and endorses all platform implementations. |
| `pipecat_smart_turn_platform_interface` | All real logic: `SmartTurnDetector`, `EnergyVad`, `AudioBuffer`, `AudioPreprocessor`, `MelSpectrogram` (pure-Dart DFT), ONNX Runtime FFI wrappers (`OrtEnv`/`OrtSession`/`OrtValue`), web `onnxruntime-web` JS interop, worker-isolate offloading. |
| `pipecat_smart_turn_{android,ios,linux,macos,windows,web}` | Thin platform plugins (`getPlatformName` method channels) plus per-platform ONNX Runtime bundling (Gradle dep, podspec/SPM dep, committed `.so`/`.dll`). |

Dependencies are minimal and current (`ffi`, `path_provider`,
`plugin_platform_interface`, `meta`; ONNX Runtime 1.24.2). No third-party
inference packages.

---

## Verification results (local, Windows x64 host, 2026-08-28)

| Command | Result |
|---|---|
| `flutter test` in `pipecat_smart_turn_platform_interface` | **FAIL** — 10 of 14 test files fail to *load* (compile errors in `smart_turn_detector.dart`); 10 tests in the remaining files pass. |
| `flutter test` in `pipecat_smart_turn` | **FAIL** — suite fails to load (same compile errors via the barrel export). |
| `flutter test` in each platform package | **FAIL** — every suite fails to load (all import the platform-interface barrel, which pulls in the broken detector). |
| `flutter analyze` in `pipecat_smart_turn_platform_interface` | **FAIL** — 53 issues: 11 `error`-severity (6 undefined `logger`/`inferenceTimeoutMs`/`timeoutMs` references, 5 stub-type-drift errors — details in C1/C2), 3 warnings, 39 infos. |
| Secrets sweep (`git grep` for keys/tokens/passwords) | Clean — no hardcoded secrets found in any source, build, or CI file. |

The real-model inference test (`onnx_inference_real_model_test.dart`) and
Whisper-parity check could not be exercised: the former is skipped when the
native runtime is unavailable to the test harness, the latter has no
upstream fixture (see H4).

---

## Critical

### C1. The package does not compile — detector API halves never landed

**Files:**
- `pipecat_smart_turn_platform_interface/lib/src/smart_turn_detector.dart:109, 124, 129, 160`
- `pipecat_smart_turn_platform_interface/lib/src/smart_turn_config.dart` (missing fields)
- `pipecat_smart_turn_platform_interface/lib/src/smart_turn_isolate.dart:137` (missing parameter)

The detector references `config.logger` (lines 109, 129) and
`config.inferenceTimeoutMs` (lines 124, 160), and calls
`_inferenceIsolate!.predict(paddedAudio, timeoutMs: ...)` (line 124).
`SmartTurnConfig` declares neither field, and `SmartTurnIsolate.predict`
takes no `timeoutMs` parameter. Commit `b4d7c8d` ("prevent segfault when
dispose races with native timeout") shipped the new detector *and* tests
written against the intended API (`smart_turn_detector_test.dart:63` mocks
`predict(audio, {timeoutMs})`; line 251 constructs
`SmartTurnConfig(inferenceTimeoutMs: 50)`) — but the config and isolate
halves of the change were never committed.

**Production impact:** nothing that depends on this package builds. Main is
red; any tag cut from it is dead on arrival.

**Proposed fix (API-additive, allowed under the constraints):**
1. Add to `SmartTurnConfig`: `final void Function(String message)? logger;`
   and `final int inferenceTimeoutMs;` (default `2000`, assert `> 0`).
2. Change `SmartTurnIsolate.predict` to
   `Future<double> predict(Float32List audio, {int timeoutMs = 2000})` and
   use `timeoutMs` for both the isolate and web timeouts (replacing the two
   hardcoded `Duration(milliseconds: 2000)` at
   `smart_turn_isolate.dart:141, 157`).
3. Re-run the full suite; the existing tests already cover the new surface.

### C2. Stub inference API drift — analyzer errors, unsupported-platform builds broken

**File:** `pipecat_smart_turn_platform_interface/lib/src/onnx_inference_stub.dart:21`

The conditional-import stub still declares
`Future<(double, double)> run(...)` while the native and web
implementations return `Future<double>`. The analyzer resolves the default
branch of `onnx_inference.dart` to the stub, producing hard errors
(`smart_turn_isolate.dart:67` `argument_type_not_assignable`,
`smart_turn_isolate.dart:140` `return_of_invalid_type`,
`smart_turn_detector.dart:149/159` `invalid_assignment`/`return_of_invalid_type`,
`smart_turn_detector_test.dart:27` `invalid_override`) — verified in the
local `flutter analyze` run. No real compile target selects the stub
(`dart.library.ffi` and `dart.library.js_interop` cover every Flutter
platform), so the direct blast radius is the analyzer/CI gate rather than
shipped builds — but that gate is a release precondition (H8).

**Proposed fix:** change the stub's `run` to `Future<double>` (still
throwing `UnsupportedError`). Keep all three inference surfaces
signature-identical; the CI analyze step already gates this once green.
(Cosmetic, same file: the stub's error strings say "not supported on the
web" even though the stub is the *non*-web, non-FFI fallback.)

### C3. x64 ONNX Runtime binaries are missing — and `.gitignore` guarantees they stay missing

**Files:**
- `pipecat_smart_turn_windows/windows/.gitignore:10` and
  `pipecat_smart_turn_linux/linux/.gitignore:10` — both contain `x64/`
  (line 11 adds `x86/`; the whole file is a Visual Studio template, copied
  verbatim even into the Linux plugin)
- `pipecat_smart_turn_linux/linux/CMakeLists.txt:23-42`,
  `pipecat_smart_turn_windows/windows/CMakeLists.txt:18-33` — silent skip
  when the binary is absent

Only ARM64 runtimes are committed
(`linux/arm64/libonnxruntime.so.1.24.2`, `windows/arm64/onnxruntime.dll`).
The two CMake files fail differently:

- **Linux** selects by `CMAKE_SYSTEM_PROCESSOR`, so an x86_64 build takes
  the `x64/` branch, `EXISTS` fails, and the bundled-libraries list is
  exported *empty* — the app ships with no runtime at all.
- **Windows** has *no architecture guard*: it appends whichever of
  `x64/onnxruntime.dll` / `arm64/onnxruntime.dll` exists. Today that means
  every Windows build — x64 included — bundles the **ARM64** DLL, which
  fails to load on x64 (wrong machine type), not "file not found". And
  because both candidates share the basename `onnxruntime.dll`, restoring
  the x64 binary without an arch guard would bundle two different DLLs to
  the same destination.

Neither file emits a warning or `FATAL_ERROR`. **Root cause of the
recurrence:** the platform-package `.gitignore`s ignore `x64/` entirely, so
even a developer who adds the x64 binaries locally will silently fail to
commit them.

**Production impact:** on x64 Linux/Windows — the majority of desktop
targets — apps build and ship successfully, then crash on the first
`initialize()`: on Linux `DynamicLibrary.open` finds no ONNX Runtime, on
Windows it finds an ARM64 DLL it cannot load.

**Proposed fix:**
1. Delete the `x64/` (and `x86/`) lines from both plugin `.gitignore`s.
2. Commit the x64 binaries (or add a checksum-verified CMake
   `file(DOWNLOAD ...)` step) for `linux/x64` and `windows/x64`.
3. In both CMakeLists, select strictly by target architecture (Windows
   currently has no arch branch at all — add one keyed on
   `CMAKE_GENERATOR_PLATFORM`/`CMAKE_SYSTEM_PROCESSOR`) and
   `message(FATAL_ERROR ...)` when the expected runtime is absent, so a
   missing binary fails the *build*, not the end user's session.
4. Add a CI step per desktop platform asserting the bundle contains the
   runtime for the runner's architecture (the current E2E would pass
   without it — see H8).

### C4. Worker-isolate responses are uncorrelated — a prediction can return the probability of the wrong audio

**File:** `pipecat_smart_turn_platform_interface/lib/src/smart_turn_isolate.dart` (`spawn()` lines 104-133, `predict()` lines 137-166)

`predict()` sends a `_WorkerRequest` (line 153) and awaits
`_responseStream!.stream.first` with a timeout (line 156). Neither
`_WorkerRequest` nor `_WorkerResponse` (lines 27-37) carries a request ID.
Note that `Future.timeout` does *not* cancel the underlying `.first`
subscription — it only completes the outer future with an error — so a
timed-out request leaves an orphaned live subscription on the broadcast
stream. Failure sequence:

1. Request A times out at 2 s; `predict` throws, the detector's
   `_isProcessing` clears, and the *worker is still computing A*. A's
   `.first` subscription stays subscribed.
2. The app calls `predict` with new audio B; the send succeeds and B's
   `.first` subscribes alongside the orphan.
3. When the worker finishes A, the broadcast stream delivers A's result to
   *both* subscriptions — B's caller receives A's completion probability
   for different audio. This is deterministic whenever B subscribes before
   A's late response arrives (the common case — the worker was still
   crunching A when B was sent); if A's response arrives first, the orphan
   consumes it and the streams happen to resync.

This is a silent correctness bug in the core product decision (end-of-turn),
not a crash. Two aggravating protocol flaws:

- The worker's init ack is `_WorkerResponse(result: 0.0)` (line 56) —
  structurally identical to a legitimate inference result of probability
  0.0 on the same channel, so a delayed ack consumed by `predict()` is a
  plausible-looking wrong answer.
- With a broadcast stream, two concurrent `predict()` calls would *both*
  receive the first response and the second response would be dropped. The
  detector's `_isProcessing` gate masks this today, but `SmartTurnIsolate`
  documents no single-flight contract.

Separately, the `spawn()` handshake (line 127) subscribes
`.first` only *after* `await Isolate.spawn(...)` returns (line 116), while
the `receivePort.listen` callback (line 108) adds worker messages to the
**broadcast** controller (line 106), which drops events with no listeners.
Today this is latent fragility rather than a reachable hang:
`Isolate.spawn`'s future resolves off a bootstrap ready-port message sent
before the entrypoint runs, its `await` continuation is a microtask, and
the worker cannot ack before `session.initialize()` (8.7 MB read + ORT
session creation) completes — so line 127 subscribes first in practice.
Pre-subscribing before `Isolate.spawn` is still the correct hardening;
any refactor of this code can silently make the drop reachable.

**Proposed fix:** add a monotonic `id` to `_WorkerRequest`/`_WorkerResponse`
(which also disambiguates the init ack); keep a
`Map<int, Completer<double>>` of pending requests and complete only
the matching one; treat a timed-out worker as poisoned (kill + respawn, or
drop responses whose ID has already timed out); buffer or pre-subscribe the
init handshake before `Isolate.spawn`. All internal — no public API change.

---

## High

### H1. The inference timeout cannot fire in non-isolate mode, and inference blocks the UI thread

**Files:** `onnx_inference_native.dart:88-130`, `smart_turn_detector.dart:147-165`

`SmartTurnOnnxSession.run()` is `async` but contains no `await`: the mel
spectrogram (~129 M multiply-adds, see H6) and the synchronous FFI
`OrtApi.Run` execute entirely on the calling isolate before the returned
future exists to be raced. With `useIsolate: false`,
`_runNativeWithTimeout`'s `.timeout(...)` races an already-completed
future — it can never interrupt anything — and the whole computation runs
on the main isolate, freezing the UI for the duration of every prediction.
The unit tests pass only because mocks are genuinely asynchronous. (Scope:
mostly native — the web session genuinely awaits the JS promise at
`onnx_inference_web.dart:75`, so the web timeout at
`smart_turn_isolate.dart:140-143` covers the ONNX call; but the mel DFT at
`onnx_inference_web.dart:60` runs synchronously *before* that await, so the
~129 M-op spectrogram (H6) executes on the browser main thread before the
timeout clock even exists — the web path has no worker. The detector's own
dispose comment at lines 171-174 shows the authors knew the native call was
synchronous.)

**Proposed fix:** document `useIsolate: false` as test-only, or route it
through `Isolate.run()` internally so the timeout is real. At minimum, the
`inferenceTimeoutMs` doc (once C1 lands) must state it has no effect on the
non-isolate native path.

### H2. `SmartTurnIsolate.kill()` guarantees the native session is never released

**File:** `smart_turn_isolate.dart:176-181`

`kill()` sends the dispose message and then immediately calls
`_isolate?.kill(priority: Isolate.immediate)`. The worker is destroyed
before it can process the dispose request, so `session.dispose()` (worker
entrypoint, line 61) — which releases the native `OrtSession` and
`OrtEnv` — effectively never runs. Each detector lifecycle leaks the full
native session (model weights + arena). Long-running apps that
re-initialize (e.g. on model swap or route changes) grow native memory
unboundedly. Additionally, `_responseStream?.close()` while a `predict()`
is awaiting `.first` surfaces as a raw `StateError` ("No element") instead
of a `SmartTurnException`. The parent-side `ReceivePort` created at line
105 is also never closed anywhere (`kill()` closes only `_responseStream`;
line 62 closes the *worker's* port, a different object), so every detector
lifecycle additionally leaks an open receive port and its listener.

**Proposed fix:** make `kill()` async-capable internally: send dispose,
await an ack with a short deadline (e.g. 500 ms), then `Isolate.kill` as
the escalation. Complete all pending request completers (per C4's map) with
`SmartTurnInferenceException('Detector disposed')` before closing the
stream. `SmartTurnDetector.dispose()` already awaits, so no API change.

### H3. `SmartTurnOnnxSession.run()` leaks native tensors on every failed inference

**File:** `onnx_inference_native.dart:93-129`

`inputTensor.release()`, `runOptions.release()`, and the output releases
(lines 117-121) run only on the happy path; the sole `try` is paired with a
`catch` that wraps and rethrows as `SmartTurnInferenceException` (lines
125-127), not a `finally` — and in passing double-wraps the
`'Model returned null logits.'` exception thrown at line 112. Any ORT
failure leaks a
256 KB input tensor (64 000 floats) plus run options and any produced
outputs, per call. Combined with a timeout loop (H1/C4) this is
unbounded native growth precisely when the system is already unhealthy.
(`OrtSession.run()` itself now has `try/finally` — commit `7a8ae0b`
verified — but its `finally` only frees the Dart-side `calloc`
allocations; ORT-owned output values can still leak if extraction throws
mid-way — the `'Unexpected output type'` throw at `ort_session.dart:233`,
or (more likely) the `OrtValueTensor` constructor at `ort_session.dart:231`,
which runs the un-guarded `OrtTensorTypeAndShapeInfo` path from M4 for
every output; either leaks all raw output handles plus any tensors already
wrapped. The discipline needs to cover ORT handles too.)

**Proposed fix:** allocate `inputTensor`/`runOptions` into locals, wrap the
run + extraction in `try`, release everything in `finally` (guarding
partially-created outputs).

### H4. Whisper preprocessing parity remains unproven — the golden is self-generated

**Files:** `test/goldens/generate_golden.py:7-9`, `test/mel_spectrogram_golden_test.dart`

The golden test is a regression snapshot: the committed
`mel_spectrogram_golden.bin` was produced by the Dart `MelSpectrogram`
itself, as the generation script explicitly states (the script is otherwise
inert — its `main()` only prints instructions). It proves the code
hasn't changed, not that it matches the `WhisperFeatureExtractor` output
smart-turn was trained against. Any systematic deviation (filter bank,
scaling, padding) produces silently wrong probabilities on every platform —
the worst failure mode for an ML library because nothing crashes.

A concrete deviation candidate already exists:
`AudioPreprocessor.prepareInput` applies per-utterance zero-mean /
unit-variance normalization to the raw waveform
(`audio_preprocessor.dart:37-55`), which stock `WhisperFeatureExtractor`
does not do unless `do_normalize` is set. Whether that matches smart-turn's
training pipeline is exactly the question only an upstream fixture can
answer.

**Proposed fix:** generate a fixture with upstream
`transformers.WhisperFeatureExtractor` (the script already sketches how) on
a deterministic input, commit input + expected output, and assert numeric
tolerance in the existing test. One-time cost, permanent proof.

### H5. `EnergyVad`'s noise floor cannot adapt upward — normal room noise locks it in "speech"

**File:** `vad_detector.dart:48, 57-63`

The floor starts at `0.001` and the EMA update is gated on
`frameRms < _noiseFloor * 1.5`, so the floor can only creep toward values
already under 1.5x itself — for any *stationary* ambient level, from the
`0.001` seed its reachable ceiling is strictly below `0.0015` (~-56 dBFS).
Any real ambient RMS above that never opens the gate, the floor freezes,
`isHighEnergy` is permanently true, and the VAD never emits
`silenceAfterSpeech`. Apps keyed
on VAD transitions (as the example app is) never trigger a turn check;
every production call site uses bare `reset()` (`example/lib/main.dart:133,
199, 233, 256, 288`), and the one place a workable floor appears is the
unit test, which injects `reset(newNoiseFloor: 0.1)` — the "adapts" test
passes only because of that injection. There is no warm-up: the public
class doc (lines 25-26) advertises "dynamic noise floor tracking via
Exponential Moving Average (EMA)", and the `_noiseFloor` field doc (lines
45-47) says the detector "requires a brief warm-up period to adapt this
floor" — neither of which the code can deliver from a low floor. The core
`SmartTurnDetector.predict()` path is unaffected, but `EnergyVad` is
exported public API and the advertised usage pattern.

**Proposed fix:** seed the floor from the first N frames (e.g. min or
percentile RMS over the first ~0.5 s), and/or use asymmetric adaptation (a
slow ungated upward EMA plus the existing fast downward tracking). Add
tests for quiet-mic, noisy-ambient, and warm-up scenarios.

### H6. Mel DFT cost is significant and the "benchmarked" claim is unsubstantiated

**File:** `mel_spectrogram.dart:17-21, 155-172`

The direct DFT is 800 frames x 201 bins x 400 samples x 2 (cos+sin)
≈ 129 M multiply-adds per 8-second prediction, plus an 80x201x800 filter
application. The doc comment asserts it "benchmarks within latency budgets
on mobile devices", but no benchmark exists anywhere in the repo. On
low-end mobile and single-threaded WASM (where this runs on the *main
thread* — the web path has no worker), this plausibly costs hundreds of
milliseconds per prediction, ahead of ONNX inference itself. There is also
an undocumented first-inference spike: the lazily-built cos/sin tables are
two `Float64List(201 * 400)` (~1.3 MB) filled with 160 800 `math.cos`/`sin`
calls (`mel_spectrogram.dart:135-153`) — re-paid in every spawned inference
isolate.

**Proposed fix:** commit a benchmark (a `flutter test` timing harness is
enough) with a stated budget per tier; if it misses, implement a real-FFT
path for N=400 (mixed-radix 16x25 or Bluestein) with the golden test (H4)
guarding parity. Do not change `kNFft`; zero-padding to 512 changes Whisper
semantics.

### H7. Extracted model file is trusted forever without validation

**File:** `onnx_inference_native.dart:17-35`

`extractBundledModel()` writes atomically (temp + rename — good) but reuses
any pre-existing file unconditionally. A file truncated by an older app
version, disk-full event, or crash prior to the atomic-write fix is loaded
on every launch until the user clears app data; the resulting ORT load
error is permanent and self-healing never occurs. (The filename embeds the
model version — `smart-turn-v3.2-cpu.onnx` — so a model *upgrade* does get
a fresh path; the residual risk is corruption, not version skew — though
the flip side is that superseded model files are never deleted, so each
shipped model version permanently costs ~8.7 MB of app-support storage.
Also, the temp filename is a fixed constant, so two isolates/processes
racing first-run extraction interleave writes into the same `.tmp`; a
failed write orphans the `.tmp` forever (nothing cleans it up); and the
function has no error handling, so a `FileSystemException` escapes raw
instead of as `SmartTurnModelLoadException` like every other failure in
this file.)

**Proposed fix:** compare the existing file's length to the bundled asset's
`lengthInBytes` (cheap, catches truncation) and re-extract on mismatch;
prefer a SHA-256 check if startup cost allows (8.7 MB hash is ~tens of ms).

### H8. CI cannot catch the failures that matter for release

**Files:** `.github/workflows/pipecat_smart_turn.yaml`, `pipecat_smart_turn_platform_interface.yaml`, `pipecat_smart_turn/example/integration_test/app_test.dart`

Verified gaps (11 workflow files total):
- **Main is currently red** (C1 landed on main), so either required checks
  are not enforced on the default branch or the workflows did not run.
  Branch protection with the package workflows as required checks is a
  release precondition.
- **Three different Flutter toolchains** across jobs: `3.41.1` (the eight
  per-package build jobs), `3.44.6` (the web-compile job), and unpinned
  floating Flutter at *seven* call sites — the six E2E jobs use bare
  `subosito/flutter-action@v2` with no `with:` block at all (action
  default: latest stable), plus `pana.yaml` (`channel: stable`, no
  version), which is reused by eight pana jobs — 13 floating job
  instantiations in total. Results are not comparable and
  unpinned jobs drift. Compounding this, the root `.gitignore` ignores
  `pubspec.lock` repo-wide, including the example *app*, so E2E runs are
  fully non-reproducible.
- **The E2E test only exercises the platform name** (`app_test.dart:12-18`)
  — and contains no `expect()` at all; its only failure mode is
  `ensureVisible` throwing on a missing finder. It passes on a build with
  no ONNX runtime bundled, no model, and a broken pipeline — i.e., it would
  not catch C3, the exact class of failure E2E exists for. Note the desktop
  E2E runners (`windows-2022`, `ubuntu-latest`) are x86_64, so with only
  ARM64 runtimes committed, even a real inference E2E would today *fail*
  on those runners — which is the point: it would have caught C3.
- `license_check.yaml` triggers only on two of the pubspec paths (umbrella
  + platform interface) while checking all eight packages; a dependency
  added to a platform package never re-triggers the gate. Its `allowed`
  list also includes both MIT and BSD-2-Clause, so it cannot catch the L1
  license mismatch.
- `pana.yaml` gates on `min_score: 120` but parses the score from `pana`
  stdout with a `sed` that assumes the output format. A pana *crash* does
  fail the step (the `$(pana .)` assignment propagates the exit code under
  `bash -e`) — the real hole is a format shift: `sed` then yields an empty
  `SCORE`, the `(( $SCORE < 120 ))` arithmetic becomes a syntax error
  inside an `if` condition (which `set -e` ignores), the condition
  evaluates false, and the step exits 0 — the gate silently passes.
- The android E2E job installs Java 11 (`pipecat_smart_turn.yaml:64-67`,
  the only Java setup in CI) while the plugin pins AGP 8.12.0
  (`settings.gradle.kts:12`, Gradle wrapper 8.13), which requires JDK 17 —
  the Android E2E build cannot succeed as configured (see L5).

**Proposed fix:** enforce required checks on main; pin one Flutter version
via a single source (e.g. a repo variable); commit the example app's
`pubspec.lock`; extend the E2E to
`initialize()` + `predict()` on a bundled fixture and assert a sane
probability — that single test transitively verifies runtime bundling,
model extraction, FFI loading, and the full pipeline per platform.

---

## Medium

### M1. Disposing one session releases the isolate-global `OrtEnv` — and re-initializing leaks one

**Files:** `onnx_inference_native.dart:62, 133-144`, `ort_env.dart:18-25, 47-50, 57-70, 73-81`

`SmartTurnOnnxSession.dispose()` calls `OrtEnv.instance.release()`, which
destroys the shared native env and nulls the singleton for the whole
isolate (Dart statics are per-isolate, not process-global — and the shipped
architecture creates one session per worker isolate, so this is reachable
mainly via `useIsolate: false` or `sessionOverride`). Two detectors with
`useIsolate: false` in one isolate: disposing the first breaks the second
(next `run()` hits a released env). Also, `OrtEnv.instance`'s only guard is
an `assert`, so in release builds a post-dispose use surfaces as an opaque
null-check `TypeError` instead of a diagnosable error.

The inverse path leaks: `initialize()` calls `OrtEnv.instance.init()`
unconditionally (`onnx_inference_native.dart:62`), and `init()` overwrites
`_ptr` without releasing any existing env (`ort_env.dart:67`) — a second
session in the same isolate orphans the first native `OrtEnv` (thread pools
included), and `release()` can then only free the newest one.

**Proposed fix:** reference-count env acquisition per session (or never
release the env for the isolate lifetime — ORT envs are designed to be
singletons), make `init()` idempotent, and replace the assert with a real
`StateError`.

### M2. Web runtime script: no SRI, and README pins a different version than everything else

**Files:** `README.md:28` (`onnxruntime-web@1.22.0`), `pipecat_smart_turn/example/web/index.html:35` (`@1.24.2`), `constants.dart:9` (`1.24.2`)

The README instructs integrators to load 1.22.0 from jsDelivr while the
native runtimes and the example are 1.24.2 — a preprocessing/runtime skew
integrators will copy-paste. Neither script tag carries an `integrity`
(SRI) hash, so the CDN is a silent supply-chain dependency for every web
deployment.

**Proposed fix:** document one version sourced from `kOnnxRuntimeVersion`,
add the SRI hash to the documented tag, and mention self-hosting
`ort.min.js` + WASM assets as the production-recommended option.

### M3. Release-mode input validation gaps in audio utilities

**File:** `audio_preprocessor.dart:82-89, 100-108`

`bytesToFloat32` guards odd byte lengths with `assert` only — in release
builds an odd-length chunk is silently truncated (and asserts never run),
which was precisely the class of bug the offset-view fix addressed. Worse,
`asInt16List` *throws* in all build modes when `offsetInBytes` is not
2-byte aligned — and an odd-offset sublist view of a larger recording
buffer is exactly the scenario the function's own doc comment (lines 71-81)
cites as its reason for existing. `stereoToMono` (lines 92-98) silently
truncates odd-length input with no assert at all.
`resample48To16` is naive decimation (aliases everything above 8 kHz into
band); it is documented as a fallback but nothing stops production use.

**Proposed fix:** throw `ArgumentError` for odd lengths/misaligned views in
all build modes (copy instead of view when misaligned);
keep decimation but rename/annotate it (`@visibleForTesting` or an explicit
`naive` in the name) or implement a small windowed-sinc decimator.

### M4. FFI failure-path leaks in setup code

**Files:** `ort_session.dart:16-36` (`fromBuffer`: `pp`, `bufferPtr` — a
full copy of the ~8.7 MB model — leak if `CreateSessionFromArray` fails,
which is exactly the H7 corrupt-model scenario; even on success, the Dart
`readAsBytesSync` buffer and this native copy are live simultaneously — a
~17 MB load-time spike on top of ORT's own copy), `ort_env.dart:57-70`
(`init`: the `logId.toNativeUtf8()` pointer is never captured in a
variable, so it leaks on *every* call including success; `pp` leaks if the
status check *or* the subsequent `_setLanguageProjection()` throws),
`ort_value.dart:83-150` (`createTensorWithDataList`: `dataPtr` (allocated
at 83-94), `shapePtr`, `ortMemoryInfoPtrPtr` leak if a status check throws;
`ortValuePtrPtr` too at the second check; and the final
`return OrtValueTensor(ortValuePtr, dataPtr)` at line 150 sits outside any
guard, so a throw in that constructor leaks the just-created ORT tensor
plus the 256 KB buffer), `ort_session.dart:101-157`
(`_getInputNames`/`_getOutputNames`: `namePtrPtr` leaks on throw; the
allocator-owned name string leaks only in the narrow window where
`toDartString()` itself throws — the status-check paths don't leak it).

Further sites in the same class, previously unlisted:
- `onnx_inference_native.dart:64-76` — `sessionOptions.release()` sits
  after `OrtSession.fromBuffer`, so a model-load failure leaks the options.
- `ort_value.dart:232-251` — the `OrtTensorTypeAndShapeInfo` constructor
  has no `try/finally`; a throw skips both the native info release and
  `calloc.free`. This runs per output tensor of *every* inference — hot
  path, unlike the rest.
- `ort_value.dart:162-195` — `OrtValueTensor.value` leaks `dataPtrPtr` on
  throw.
- None of the `release()` methods null `_ptr` after freeing
  (`ort_session.dart:261-264, 289-292, 354-357`, `ort_value.dart:26-29`),
  so a double `release()` is a native double-free (segfault), not a no-op.
  (`OrtValueTensor.release()` is half-guarded: it nulls `_dataPtr` but
  still double-releases the ORT handle via `super.release()`.) Note `_ptr`
  is `late` non-nullable in all four classes, so the fix needs an
  `ffi.nullptr` sentinel or a `_released` flag rather than nulling.
- `OrtEnv` *resurrects itself* after `release()`: both the `ptr` getter
  (`ort_env.dart:96-101`) and `_setLanguageProjection` (103-106) call
  `init()` when `_ptr == null`, so a post-dispose touch silently creates a
  fresh native env instead of failing — compounding M1. `setup()` also
  silently discards a differing `binding` (`_instance ??=`, line 48), so a
  second `initialize()` with a different `onnxLibraryPath` is ignored.

Not all init-time: `createTensorWithDataList`, `OrtValueTensor.value`, and
the `OrtTensorTypeAndShapeInfo` constructor run per inference — the same
hot path as H3; only `fromBuffer`, `OrtEnv.init`, and `_get*Names` are
genuinely one-shot. The same `try/finally` discipline applied to
`OrtSession.run()` in `7a8ae0b` should be applied uniformly, plus
idempotent `release()`.

### M5. Per-prediction isolate messaging copies 512 KB; README claims "Zero-Copy Transfers"

**Files:** `smart_turn_isolate.dart:153` (send), `README.md:18`

`SendPort.send(Float32List(128000))` copies the buffer into the worker
(and Dart may copy again internally). At a realistic cadence (a prediction
every few hundred ms) this is tolerable but measurable on mobile; the
README's "Zero-Copy Transfers" feature claim is currently false. The next
line of the same feature list (`README.md:19`, "Dynamic Adaptation: Noise
floor tracking for robust performance in noisy environments") is equally
false per H5.

**Proposed fix:** use `TransferableTypedData` for the audio payload (true
move semantics), or correct the README (both lines).

### M6. Observability is still absent (the intended hook is the unshipped `logger`)

The only planned observability is `config.logger` — part of the C1 fix.
Once landed, actually emit on the events an operator needs: model
extraction (hit/miss/re-extract), native library load failure with the
attempted path, worker spawn/restart, inference latency, timeout, and
backpressure drops (the detector already logs the last two). No third-party
dependency needed.

### M7. `SmartTurnConfig` validation is debug-only

**File:** `smart_turn_config.dart:10-21`

All range checks are `assert`s; a release build accepts
`completionThreshold: 5.0` (never completes) or `cpuThreadCount: 0`
(ORT-defined behavior) without complaint. Because the constructor is
`const`, runtime throws are not an option without dropping `const`.

**Proposed fix:** keep the asserts, and add validation at the point of use
(`initialize()` can throw `ArgumentError` for out-of-range values) — this
preserves the `const` constructor and the public API.

### M8. `spawn()` has no timeout, and failure states wedge the object permanently

**File:** `smart_turn_isolate.dart:104-133`

The init handshake `await _responseStream!.stream.first` (line 127) is
unbounded. A worker stuck loading a model (huge file on slow storage, or
the C4 dropped message) hangs the app's `initialize()` with no error. Two
adjacent robustness gaps:

- `_isInitializing` is set at line 104 and cleared only if line 127
  returns; if `Isolate.spawn` throws or the ack is lost, it stays `true`
  forever and every later `predict()` throws the misleading
  `'Isolate is still initializing'`. (Native path only — the web branch
  returns at line 102 before the flag is set.) An `Isolate.spawn` throw
  also leaves `receivePort` and `_responseStream` open with no `kill()`
  ever called.
- `Isolate.spawn` is called with no `onError`/`onExit` ports, so a worker
  that dies outside its one `try` block dies silently — `_sendPort` stays
  non-null and every subsequent `predict()` burns the full timeout with no
  recovery path.

Add a spawn timeout (e.g. 30 s) that kills the isolate and throws
`SmartTurnModelLoadException`, reset `_isInitializing` on all failure
paths, and attach `onError`/`onExit` ports that poison the session.

### M9. Near-silence is amplified to full scale before inference

**File:** `audio_preprocessor.dart:51`

`prepareInput`'s normalization divides by
`math.max(math.sqrt(variance / kMaxSamples), 1e-5)`. For a quiet-room
buffer the divisor is tiny, so microphone dither/noise is scaled up to
unit variance and the model receives a speech-loudness noise spectrogram.
There is no minimum-energy bail-out before inference, so predictions on
effective silence are garbage-in rather than a defined "no speech" result.
(The example app's VAD gating would normally prevent this — but H5 means
the VAD gate is itself broken.) Add an energy floor below which `predict`
short-circuits to incomplete, or document the required VAD gating as a
contract.

### M10. `SmartTurnConfig.maxAudioSeconds` is inert

**Files:** `smart_turn_config.dart:30`, `smart_turn_detector.dart:119`

The field is declared, documented, and assert-validated, but no library
code reads it: the detector hardcodes the 8-second/128 000-sample window
via `AudioPreprocessor.prepareInput`. Only tests and the example app
consume it. Either wire it through (the model input is fixed at 8 s, so
likely: remove/deprecate it) or document it as example-only.

---

## Low / release hygiene

- **L1 — Version and metadata drift:** `PipecatSmartTurn.version` returns
  `'0.0.1'` while pubspecs say `0.1.0+1`
  (`pipecat_smart_turn/lib/pipecat_smart_turn.dart:6`); the iOS/macOS
  podspecs declare `license MIT` while the repo LICENSE and README badge
  are BSD-2 (and the podspecs' `:file => '../LICENSE'` doesn't resolve —
  `pod lib lint` would fail); podspec versions are `0.0.1`. Seven of the
  eight packages are `publish_to: none` with path dependencies — the
  exception is `pipecat_smart_turn_platform_interface`, which has **no**
  `publish_to` key at all and is therefore the one package (the one
  carrying the 8.7 MB model) publishable by accident. The root README's
  license badge URL is also malformed (`license-BSD-2.svg` — the unescaped
  dash breaks shields.io parsing), and the umbrella package's own
  `pipecat_smart_turn/README.md` — the one pub.dev would render — declares
  **MIT** (lines 10, 17) and is otherwise still the unedited Very Good CLI
  template body, making the license story three-way inconsistent (repo
  LICENSE + root README: BSD-2; umbrella README + podspecs: MIT).
- **L2 — Broken/stale docs:** `README.md:23` links `docs/model-acquisition.md`,
  which does not exist; `docs/platform-configuration.md` says the model "is
  not bundled with the package" (it is, since the asset landed), refers to
  the model as `smart_turn_v3.onnx` (real name: `smart-turn-v3.2-cpu.onnx`;
  README's Quick Start repeats the wrong name), and lists
  iOS deployment target 12.0 while `Package.swift` requires 13.0.
- **L3 — Stale code comments / false doc claims:**
  `audio_preprocessor.dart:21-23` documents a 5 ms fade-in that is not
  applied (`pipecat_smart_turn_platform_interface/README.md:8` advertises
  it too); `onnx_inference_native.dart:87`
  documents "Returns raw logits (incompleteLogit, completeLogit)" for a
  method returning a single probability; `audio_buffer.dart:4` calls the
  ring buffer "zero-allocation" while `toFloat32List()` allocates a fresh
  512 KB list per call. Readers tuning thresholds will be misled.
- **L4 — `AudioBuffer` accepts non-positive `maxSeconds`** without
  validation (`audio_buffer.dart:10-14`); `maxSamples == 0` silently
  produces an empty buffer. Add an assert/ArgumentError for consistency
  with `SmartTurnConfig`.
- **L5 — Android Gradle style:** the `dependencies { ... }` block is nested
  inside `android { ... }` (`pipecat_smart_turn_android/android/build.gradle:41-45`);
  it works via Groovy delegation but breaks on Kotlin DSL migration and
  confuses tooling. Move it top-level. CI installs Java 11 while the plugin
  pins AGP 8.12.0, which requires JDK 17 — a hard incompatibility, not a
  style nit (elevated into H8: the Android E2E job cannot build as
  configured).
- **L6 — Native binary provenance:** the committed
  `libonnxruntime.so.1.24.2` / `onnxruntime.dll` have a source URL recorded
  only in a planning doc (`docs/onnxruntime-implementation-plan.md:21-22`,
  pointing at the `microsoft/onnxruntime` v1.24.2 GitHub release) — no
  checksum, no canonical provenance file, no CI verification. Notably,
  `docs/implementation-guide.md:1270-1321` contains a checksum-verification
  CI snippet (with a `REPLACE_WITH_YOUR_ACTUAL_SHA256...` placeholder) that
  was never carried into `.github/workflows/` — the repo documents the
  control it doesn't implement. Add a `THIRD_PARTY.md` recording release
  URL + SHA-256 per file, and a CI check.
- **L7 — `setup.sh`** is Linux/apt-only, uses `sudo` six times, uses the
  long-deprecated `apt-key add` (removed in Ubuntu 22.04+/Debian 12),
  refuses to run unless *sourced* (lines 4-8), and installs only the *Dart*
  SDK — no Flutter. Its closing `dart pub get` runs from the repo root,
  which has no `pubspec.yaml` at all, so it fails with "Could not find a
  file named pubspec.yaml" before Flutter-SDK resolution is even attempted.
  It fails entirely on the Windows/macOS dev environments this repo is
  actually developed on (the prior audit's verification failed partly
  because of it). Scope it or document it as CI-only.

Security summary: no hardcoded secrets (verified by sweep), no injection
surfaces (no SQL/shell/network calls in library code), no authz surface
(on-device library). The security-relevant items are supply-chain: M2 (CDN
script without SRI) and L6 (undocumented binary provenance).

Deployment-readiness summary (library framing): "health check" =
`initialize()` must fail fast and loudly (C3, M8); "graceful shutdown" =
`dispose()` must actually release native resources (H2, M1); "migrations" =
model re-extraction on corruption (H7 — version upgrades already get a
fresh path via the versioned filename). Docker is N/A.

---

## Status of the 2026-07-19 findings (verified against `80ba3b3`)

| Prior finding | Status now | Evidence |
|---|---|---|
| C5 x64 binaries missing | **Open, root cause found** | See C3 — `.gitignore` blocks the fix. |
| C7 uncorrelated isolate responses | **Open** | See C4 — unchanged protocol. |
| C8 FFI cleanup exception-unsafe | **Partially fixed** | `OrtSession.run` now `try/finally` (`7a8ae0b`), though only for Dart-side allocations; `SmartTurnOnnxSession.run` and setup paths still leak (H3, M4). |
| H1 preprocessing parity unproven | **Open** | See H4 — golden still self-generated; `913222c` removed self-generation from the test but committed the same Dart-generated golden. |
| H2 DFT performance | **Open** | See H6 — docs corrected (`22d3114`) but now claim a benchmark that doesn't exist. |
| H3 incomplete timeout | **Regressed into C1** | The fix was attempted; half of it landed and broke the build. |
| H4 dispose race | **Fixed in intent, unverifiable** | `_nativeInferenceFuture` tracking landed (`b4d7c8d`) and the test exists, but the suite cannot run until C1 is fixed. |
| H5 extraction validation | **Open** | See H7. |
| H6 CI path filters | **Fixed** | `80ba3b3` broadened the umbrella workflow to all packages (verified in workflow file). |
| M1 stub type drift | **Open** | See C2 — now producing hard analyzer errors. |
| M2 stale comments | **Open** | See L3 — both cited comments unchanged. |
| M6 observability | **Open** | See M6 — `logger` designed but unshipped (C1). |

---

## Suggested fix order

1. **C1 + C2** — restore compilation (config fields, `timeoutMs` parameter,
   stub signature). Everything else is unverifiable until the suite runs.
2. **C3** — un-ignore `x64/`, add binaries, add the missing Windows arch
   guard, make CMake fail loudly.
3. **C4 + H2 + M8** — request-ID protocol, ack-then-kill dispose, spawn
   timeout + failure-path resets (one coherent isolate-lifecycle change).
4. **H3 + M4** — `try/finally` across all FFI allocation paths, idempotent
   `release()`.
5. **H4** — upstream Whisper golden fixture (which also adjudicates the
   waveform-normalization question); then **H6** benchmark (the
   golden protects any FFT optimization).
6. **H5** — VAD warm-up/adaptation fix with tests; **M9** silence gate.
7. **H7, H8, M1-M3, M7, M10** — extraction validation, CI hardening, env
   refcount, SRI/doc alignment, release-mode validation, config cleanup.
8. **Low items** as a final release-hygiene pass.

All proposed fixes preserve the public Dart API. The only public-surface
changes are additive: `SmartTurnConfig.logger`,
`SmartTurnConfig.inferenceTimeoutMs`, and the optional `timeoutMs`
parameter on `SmartTurnIsolate.predict` — all three already assumed by the
committed tests.
