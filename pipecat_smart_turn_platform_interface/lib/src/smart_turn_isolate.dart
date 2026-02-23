import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:meta/meta.dart';
import 'package:pipecat_smart_turn_platform_interface/src/exceptions.dart';
import 'package:pipecat_smart_turn_platform_interface/src/onnx_inference.dart';

/// Configuration passed to the background worker isolate.
@visibleForTesting
class IsolateConfig {
  IsolateConfig({
    required this.modelFilePath,
    required this.cpuThreadCount,
    required this.replyPort,
  });

  final String modelFilePath;
  final int cpuThreadCount;
  final SendPort replyPort;
}

/// A request sent to the worker isolate.
@visibleForTesting
class InferenceRequest {
  InferenceRequest(this.audioData);

  final TransferableTypedData audioData;
}

/// Manages a background Dart Isolate for off-thread ONNX inference.
class SmartTurnIsolate {
  Isolate? _isolate;
  SendPort? _commandPort;
  final _initCompleter = Completer<void>();

  /// Spawns the background isolate and initializes the ONNX session.
  Future<void> spawn({
    required String modelFilePath,
    int cpuThreadCount = 1,
  }) async {
    final receivePort = ReceivePort();

    _isolate = await Isolate.spawn(
      _isolateEntry,
      IsolateConfig(
        modelFilePath: modelFilePath,
        cpuThreadCount: cpuThreadCount,
        replyPort: receivePort.sendPort,
      ),
    );

    receivePort.listen((message) {
      if (message is SendPort) {
        _commandPort = message;
        if (!_initCompleter.isCompleted) {
          _initCompleter.complete();
        }
      } else if (message is Exception) {
        if (!_initCompleter.isCompleted) {
          _initCompleter.completeError(message);
        }
      }
    });

    return _initCompleter.future;
  }

  /// Sends audio to the isolate for inference and awaits logits.
  Future<(double, double)> predict(Float32List audio) async {
    if (_commandPort == null) {
      throw const SmartTurnNotInitializedException();
    }

    final responsePort = ReceivePort();
    // Use TransferableTypedData for zero-copy transfer of the large audio
    // buffer.
    _commandPort!.send((
      InferenceRequest(TransferableTypedData.fromList([audio])),
      responsePort.sendPort,
    ));

    final response = await responsePort.first;

    if (response is (double, double)) {
      return response;
    } else if (response is Exception) {
      throw SmartTurnInferenceException('Isolate inference error: $response');
    } else {
      throw SmartTurnInferenceException(
        'Unexpected isolate response: $response',
      );
    }
  }

  /// Entry point for the background isolate.
  static Future<void> _isolateEntry(IsolateConfig config) async {
    final commandPort = ReceivePort();
    // We do NOT send the port here anymore. runIsolateLoop will signal when ready.

    final session = SmartTurnOnnxSession();
    await runIsolateLoop(
      commandStream: commandPort,
      session: session,
      modelFilePath: config.modelFilePath,
      cpuThreadCount: config.cpuThreadCount,
      initErrorPort: config.replyPort,
      onInitialized: () => config.replyPort.send(commandPort.sendPort),
    );
  }

  /// Extracted logic for testing.
  @visibleForTesting
  static Future<void> runIsolateLoop({
    required Stream<dynamic> commandStream,
    required SmartTurnOnnxSession session,
    required String modelFilePath,
    required int cpuThreadCount,
    required SendPort initErrorPort,
    required void Function() onInitialized,
  }) async {
    try {
      await session.initialize(
        modelFilePath: modelFilePath,
        cpuThreadCount: cpuThreadCount,
      );

      onInitialized();

      await for (final message in commandStream) {
        final (request, replyPort) = message as (InferenceRequest, SendPort);
        try {
          // materialized() is fast as it just returns a view of the
          // transferred memory.
          final audio = request.audioData.materialize().asFloat32List();
          final result = await session.run(audio);
          replyPort.send(result);
        } on Exception catch (e) {
          replyPort.send(e);
        }
      }
    } on Exception catch (e) {
      initErrorPort.send(e);
    } finally {
      session.dispose();
    }
  }

  /// Kills the background isolate.
  void kill() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _commandPort = null;
  }
}
