import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pipecat_smart_turn_platform_interface/pipecat_smart_turn_platform_interface.dart';
import 'package:pipecat_smart_turn_platform_interface/src/onnx_inference.dart';
import 'package:pipecat_smart_turn_platform_interface/src/smart_turn_isolate.dart';

class MockSmartTurnOnnxSession implements SmartTurnOnnxSession {
  bool initializeCalled = false;
  bool disposeCalled = false;
  String? initializedModelPath;
  int? initializedCpuThreadCount;

  @override
  Future<void> initialize({
    required String modelFilePath,
    int cpuThreadCount = 1,
    String? onnxLibraryPath,
  }) async {
    initializeCalled = true;
    initializedModelPath = modelFilePath;
    initializedCpuThreadCount = cpuThreadCount;
  }

  @override
  Future<double> run(Float32List audioSamples) async {
    return runResult;
  }

  double runResult = 0;

  /// Sets the run result for testing.
  // ignore: use_setters_to_change_properties
  void setRunResult(double probability) {
    runResult = probability;
  }

  @override
  void dispose() {
    disposeCalled = true;
  }
}

class MockSmartTurnIsolate implements SmartTurnIsolate {
  bool spawnCalled = false;
  bool killCalled = false;
  String? spawnedModelPath;
  int? spawnedCpuThreadCount;

  @override
  Future<void> spawn({
    required String modelFilePath,
    int cpuThreadCount = 1,
    String? onnxLibraryPath,
  }) async {
    spawnCalled = true;
    spawnedModelPath = modelFilePath;
    spawnedCpuThreadCount = cpuThreadCount;
  }

  @override
  Future<double> predict(Float32List audio, {int timeoutMs = 2000}) async {
    return predictResult;
  }

  double predictResult = 0;

  /// Sets the predict result for testing.
  // ignore: use_setters_to_change_properties
  void setPredictResult(double probability) {
    predictResult = probability;
  }

  @override
  Future<void> kill() async {
    killCalled = true;
  }
}

// Extensions removed as I implemented methods directly in Mock classes.

void main() {
  group('SmartTurnDetector', () {
    late SmartTurnDetector detector;
    late MockSmartTurnOnnxSession mockSession;
    late MockSmartTurnIsolate mockIsolate;

    setUp(() {
      mockSession = MockSmartTurnOnnxSession();
      mockIsolate = MockSmartTurnIsolate();
    });

    test('initializes with session when useIsolate is false', () async {
      detector = SmartTurnDetector(
        config: const SmartTurnConfig(
          customModelPath: 'model.onnx',
          useIsolate: false,
          cpuThreadCount: 2,
        ),
      )..sessionOverride = mockSession;

      await detector.initialize();

      expect(mockSession.initializeCalled, isTrue);
      expect(mockSession.initializedModelPath, 'model.onnx');
      expect(mockSession.initializedCpuThreadCount, 2);
    });

    test('initializes with isolate when useIsolate is true', () async {
      detector = SmartTurnDetector(
        config: const SmartTurnConfig(
          customModelPath: 'model.onnx',
          cpuThreadCount: 4,
        ),
      )..isolateOverride = mockIsolate;

      await detector.initialize();

      expect(mockIsolate.spawnCalled, isTrue);
      expect(mockIsolate.spawnedModelPath, 'model.onnx');
      expect(mockIsolate.spawnedCpuThreadCount, 4);
    });

    test('throws if initialized without customModelPath', () {
      detector = SmartTurnDetector(
        config: const SmartTurnConfig(),
      );
      expect(
        () => detector.initialize(),
        throwsA(isA<SmartTurnModelLoadException>()),
      );
    });

    test('initialize is idempotent', () async {
      detector = SmartTurnDetector(
        config: const SmartTurnConfig(
          customModelPath: 'model.onnx',
          useIsolate: false,
        ),
      )..sessionOverride = mockSession;
      await detector.initialize();
      expect(mockSession.initializeCalled, isTrue);

      mockSession.initializeCalled = false;
      await detector.initialize();
      expect(mockSession.initializeCalled, isFalse);
    });

    test('predict throws if not initialized', () {
      detector = SmartTurnDetector(
        config: const SmartTurnConfig(customModelPath: 'model.onnx'),
      );
      expect(
        () => detector.predict(Float32List(0)),
        throwsA(isA<SmartTurnNotInitializedException>()),
      );
    });

    test('predict uses session when useIsolate is false', () async {
      detector = SmartTurnDetector(
        config: const SmartTurnConfig(
          customModelPath: 'model.onnx',
          useIsolate: false,
        ),
      )..sessionOverride = mockSession;
      await detector.initialize();

      mockSession.setRunResult(1); // High confidence for complete
      final result = await detector.predict(Float32List(16000));

      expect(result, isNotNull);
      expect(result!.isComplete, isTrue);
      expect(result.confidence, closeTo(1.0, 0.001));
    });

    test('predict uses isolate when useIsolate is true', () async {
      detector = SmartTurnDetector(
        config: const SmartTurnConfig(customModelPath: 'model.onnx'),
      )..isolateOverride = mockIsolate;
      await detector.initialize();

      mockIsolate.setPredictResult(0); // High confidence for incomplete
      final result = await detector.predict(Float32List(16000));

      expect(result, isNotNull);
      expect(result!.isComplete, isFalse);
      expect(result.confidence, closeTo(0.0, 0.001));
    });

    test('dispose clears resources', () async {
      detector = SmartTurnDetector(
        config: const SmartTurnConfig(
          customModelPath: 'model.onnx',
          useIsolate: false,
        ),
      )..sessionOverride = mockSession;
      await detector.initialize();
      await detector.dispose();

      expect(mockSession.disposeCalled, isTrue);
    });

    test('dispose clears isolate resources', () async {
      detector = SmartTurnDetector(
        config: const SmartTurnConfig(customModelPath: 'model.onnx'),
      )..isolateOverride = mockIsolate;
      await detector.initialize();
      await detector.dispose();

      expect(mockIsolate.killCalled, isTrue);
    });

    test('backpressure handling', () async {
      // To test backpressure, we need the session.run to be slow.
      // We can use a Completer to control when run returns.

      final completer = Completer<double>();

      final slowSession = SlowMockSession(completer);
      detector = SmartTurnDetector(
        config: const SmartTurnConfig(
          customModelPath: 'model.onnx',
          useIsolate: false,
        ),
      )..sessionOverride = slowSession;
      await detector.initialize();

      // Start first prediction
      final future1 = detector.predict(Float32List(16000));

      // Start second prediction immediately. It should return null because
      // processing is true.
      final result2 = await detector.predict(Float32List(16000));
      expect(result2, isNull);

      // Complete first prediction
      completer.complete(1.0);
      final result1 = await future1;
      expect(result1, isNotNull);
    });

    test('dispose waits for native inference after timeout', () async {
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
      await expectLater(
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

    test('invokes logger on lifecycle and inference events', () async {
      final logs = <String>[];
      detector = SmartTurnDetector(
        config: SmartTurnConfig(
          customModelPath: 'model.onnx',
          useIsolate: false,
          logger: logs.add,
        ),
      )..sessionOverride = mockSession;

      await detector.initialize();
      expect(logs.any((l) => l.contains('initializing session')), isTrue);

      final result = await detector.predict(Float32List(16000));
      expect(result, isNotNull);
      expect(logs.any((l) => l.contains('prediction complete in')), isTrue);

      await detector.dispose();
      expect(logs.any((l) => l.contains('disposed')), isTrue);
    });
  });
}

class SlowMockSession extends MockSmartTurnOnnxSession {
  SlowMockSession(this.completer);
  final Completer<double> completer;

  @override
  Future<double> run(Float32List audioSamples) {
    return completer.future;
  }
}
