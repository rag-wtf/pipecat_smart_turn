import 'dart:async';
import 'dart:isolate';
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
  bool shouldFailInit = false;
  bool shouldFailRun = false;

  @override
  Future<void> initialize({
    required String modelFilePath,
    int cpuThreadCount = 1,
  }) async {
    if (shouldFailInit) throw Exception('Init failed');
    initializeCalled = true;
    initializedModelPath = modelFilePath;
    initializedCpuThreadCount = cpuThreadCount;
  }

  @override
  Future<(double, double)> run(Float32List audioSamples) async {
    if (shouldFailRun) throw Exception('Run failed');
    return (1.0, 0.0);
  }

  @override
  void dispose() {
    disposeCalled = true;
  }
}

void main() {
  group('SmartTurnIsolate', () {
    test(
      'predict throws SmartTurnNotInitializedException if not spawned',
      () async {
        final isolate = SmartTurnIsolate();
        expect(
          () => isolate.predict(Float32List(128000)),
          throwsA(isA<SmartTurnNotInitializedException>()),
        );
      },
    );

    test('kill handles null isolate gracefully', () {
      SmartTurnIsolate().kill();
    });

    test('spawn throws on invalid model and covers isolate entry', () async {
      final isolate = SmartTurnIsolate();
      await expectLater(
        isolate.spawn(
          modelFilePath: 'non_existent.onnx',
        ),
        throwsA(isA<SmartTurnModelLoadException>()),
      );
      isolate.kill();
    });

    test('predict returns result on success', () async {
      final isolate = SmartTurnIsolate();
      final receivePort = ReceivePort();
      isolate.commandPortForTesting = receivePort.sendPort;

      // When isolate receives InferenceRequest, send back a success tuple
      receivePort.listen((message) {
        final (_, SendPort replyPort) = message as (InferenceRequest, SendPort);
        replyPort.send((0.8, 0.2));
      });

      final result = await isolate.predict(Float32List(128000));
      expect(result, equals((0.8, 0.2)));

      receivePort.close();
    });

    test('predict throws on error response', () async {
      final isolate = SmartTurnIsolate();
      final receivePort = ReceivePort();
      isolate.commandPortForTesting = receivePort.sendPort;

      receivePort.listen((message) {
        final (_, SendPort replyPort) = message as (InferenceRequest, SendPort);
        replyPort.send(Exception('Isolate Error'));
      });

      await expectLater(
        isolate.predict(Float32List(128000)),
        throwsA(isA<SmartTurnInferenceException>()),
      );

      receivePort.close();
    });

    test('predict throws on unexpected response', () async {
      final isolate = SmartTurnIsolate();
      final receivePort = ReceivePort();
      isolate.commandPortForTesting = receivePort.sendPort;

      receivePort.listen((message) {
        final (_, SendPort replyPort) = message as (InferenceRequest, SendPort);
        replyPort.send('Unexpected String Response');
      });

      await expectLater(
        isolate.predict(Float32List(128000)),
        throwsA(isA<SmartTurnInferenceException>()),
      );

      receivePort.close();
    });
  });

  group('runIsolateLoop', () {
    late MockSmartTurnOnnxSession mockSession;
    late StreamController<dynamic> commandController;
    late ReceivePort errorPort;

    setUp(() {
      mockSession = MockSmartTurnOnnxSession();
      commandController = StreamController<dynamic>();
      errorPort = ReceivePort();
    });

    tearDown(() {
      unawaited(commandController.close());
      errorPort.close();
    });

    test('initializes session and calls onInitialized', () async {
      var onInitializedCalled = false;

      final loopFuture = SmartTurnIsolate.runIsolateLoop(
        commandStream: commandController.stream,
        session: mockSession,
        modelFilePath: 'model.onnx',
        cpuThreadCount: 2,
        initErrorPort: errorPort.sendPort,
        onInitialized: () => onInitializedCalled = true,
      );

      // Wait for init
      await Future<void>.delayed(Duration.zero);

      expect(mockSession.initializeCalled, isTrue);
      expect(mockSession.initializedModelPath, 'model.onnx');
      expect(mockSession.initializedCpuThreadCount, 2);
      expect(onInitializedCalled, isTrue);

      // Close stream to finish loop
      await commandController.close();
      await loopFuture;

      expect(mockSession.disposeCalled, isTrue);
    });

    test('sends error if initialization fails', () async {
      mockSession.shouldFailInit = true;
      var onInitializedCalled = false;

      final loopFuture = SmartTurnIsolate.runIsolateLoop(
        commandStream: commandController.stream,
        session: mockSession,
        modelFilePath: 'model.onnx',
        cpuThreadCount: 1,
        initErrorPort: errorPort.sendPort,
        onInitialized: () => onInitializedCalled = true,
      );

      await loopFuture;

      expect(onInitializedCalled, isFalse);
      expect(mockSession.disposeCalled, isTrue);

      final error = await errorPort.first;
      expect(error, isA<Exception>());
      expect(error.toString(), contains('Init failed'));
    });

    test('processes inference requests', () async {
      final loopFuture = SmartTurnIsolate.runIsolateLoop(
        commandStream: commandController.stream,
        session: mockSession,
        modelFilePath: 'model.onnx',
        cpuThreadCount: 1,
        initErrorPort: errorPort.sendPort,
        onInitialized: () {},
      );

      // Wait for init
      await Future<void>.delayed(Duration.zero);

      final replyPort = ReceivePort();
      final request = InferenceRequest(
        TransferableTypedData.fromList([Float32List(100)]),
      );

      commandController.add((request, replyPort.sendPort));

      final response = await replyPort.first;
      expect(response, equals((1.0, 0.0)));

      await commandController.close();
      await loopFuture;
    });

    test('handles inference errors', () async {
      mockSession.shouldFailRun = true;

      final loopFuture = SmartTurnIsolate.runIsolateLoop(
        commandStream: commandController.stream,
        session: mockSession,
        modelFilePath: 'model.onnx',
        cpuThreadCount: 1,
        initErrorPort: errorPort.sendPort,
        onInitialized: () {},
      );

      // Wait for init
      await Future<void>.delayed(Duration.zero);

      final replyPort = ReceivePort();
      final request = InferenceRequest(
        TransferableTypedData.fromList([Float32List(100)]),
      );

      commandController.add((request, replyPort.sendPort));

      final response = await replyPort.first;
      expect(response, isA<Exception>());
      expect(response.toString(), contains('Run failed'));

      await commandController.close();
      await loopFuture;
    });
  });
}
