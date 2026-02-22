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
  Future<void> initialize({required String modelFilePath, int cpuThreadCount = 1}) async {
    initializeCalled = true;
    initializedModelPath = modelFilePath;
    initializedCpuThreadCount = cpuThreadCount;
  }

  @override
  Future<(double, double)> run(Float32List audioSamples) async {
    return runResult;
  }

  (double, double) runResult = (5.0, 0.0);

  void setRunResult(double incomplete, double complete) {
    runResult = (incomplete, complete);
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
  Future<void> spawn({required String modelFilePath, int cpuThreadCount = 1}) async {
    spawnCalled = true;
    spawnedModelPath = modelFilePath;
    spawnedCpuThreadCount = cpuThreadCount;
  }

  @override
  Future<(double, double)> predict(Float32List audio) async {
      return predictResult;
  }

  (double, double) predictResult = (5.0, 0.0);

  void setPredictResult(double incomplete, double complete) {
    predictResult = (incomplete, complete);
  }

  @override
  void kill() {
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
      );
      detector.sessionOverride = mockSession;

      await detector.initialize();

      expect(mockSession.initializeCalled, isTrue);
      expect(mockSession.initializedModelPath, 'model.onnx');
      expect(mockSession.initializedCpuThreadCount, 2);
    });

    test('initializes with isolate when useIsolate is true', () async {
      detector = SmartTurnDetector(
        config: const SmartTurnConfig(
          customModelPath: 'model.onnx',
          useIsolate: true,
          cpuThreadCount: 4,
        ),
      );
      detector.isolateOverride = mockIsolate;

      await detector.initialize();

      expect(mockIsolate.spawnCalled, isTrue);
      expect(mockIsolate.spawnedModelPath, 'model.onnx');
      expect(mockIsolate.spawnedCpuThreadCount, 4);
    });

    test('throws if initialized without customModelPath', () {
      detector = SmartTurnDetector(
        config: const SmartTurnConfig(customModelPath: null),
      );
      expect(
        () => detector.initialize(),
        throwsA(isA<SmartTurnModelLoadException>()),
      );
    });

    test('initialize is idempotent', () async {
       detector = SmartTurnDetector(
        config: const SmartTurnConfig(customModelPath: 'model.onnx', useIsolate: false),
      );
      detector.sessionOverride = mockSession;
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
            customModelPath: 'model.onnx', useIsolate: false),
      );
      detector.sessionOverride = mockSession;
      await detector.initialize();

      mockSession.setRunResult(0.0, 10.0); // High confidence for complete
      final result = await detector.predict(Float32List(16000));

      expect(result, isNotNull);
      expect(result!.isComplete, isTrue);
      expect(result.confidence, closeTo(1.0, 0.001));
    });

    test('predict uses isolate when useIsolate is true', () async {
      detector = SmartTurnDetector(
        config: const SmartTurnConfig(
            customModelPath: 'model.onnx', useIsolate: true),
      );
      detector.isolateOverride = mockIsolate;
      await detector.initialize();

      mockIsolate.setPredictResult(10.0, 0.0); // High confidence for incomplete
      final result = await detector.predict(Float32List(16000));

      expect(result, isNotNull);
      expect(result!.isComplete, isFalse);
      expect(result.confidence, closeTo(0.0, 0.001));
    });

    test('dispose clears resources', () async {
      detector = SmartTurnDetector(
        config: const SmartTurnConfig(
            customModelPath: 'model.onnx', useIsolate: false),
      );
      detector.sessionOverride = mockSession;
      await detector.initialize();
      await detector.dispose();

      expect(mockSession.disposeCalled, isTrue);
    });

    test('dispose clears isolate resources', () async {
      detector = SmartTurnDetector(
        config: const SmartTurnConfig(
            customModelPath: 'model.onnx', useIsolate: true),
      );
      detector.isolateOverride = mockIsolate;
      await detector.initialize();
      await detector.dispose();

      expect(mockIsolate.killCalled, isTrue);
    });

    test('backpressure handling', () async {
      // To test backpressure, we need the session.run to be slow.
      // We can use a Completer to control when run returns.

      final completer = Completer<(double, double)>();

      final slowSession = SlowMockSession(completer);
      detector = SmartTurnDetector(
        config: const SmartTurnConfig(
            customModelPath: 'model.onnx', useIsolate: false),
      );
      detector.sessionOverride = slowSession;
      await detector.initialize();

      // Start first prediction
      final future1 = detector.predict(Float32List(16000));

      // Start second prediction immediately. It should return null because processing is true.
      final result2 = await detector.predict(Float32List(16000));
      expect(result2, isNull);

      // Complete first prediction
      completer.complete((10.0, 0.0));
      final result1 = await future1;
      expect(result1, isNotNull);
    });
  });
}

class SlowMockSession extends MockSmartTurnOnnxSession {
  final Completer<(double, double)> completer;
  SlowMockSession(this.completer);

  @override
  Future<(double, double)> run(Float32List audioSamples) {
    return completer.future;
  }
}
