import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:pipecat_smart_turn_platform_interface/src/exceptions.dart';
import 'package:pipecat_smart_turn_platform_interface/src/onnx_inference.dart';

/// Configuration passed to the background worker isolate.
class _IsolateConfig {
  _IsolateConfig({
    required this.modelFilePath,
    required this.cpuThreadCount,
    required this.replyPort,
  });

  final String modelFilePath;
  final int cpuThreadCount;
  final SendPort replyPort;
}

/// A request sent to the worker isolate.
class _InferenceRequest {
  _InferenceRequest(this.audioData);

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
      _IsolateConfig(
        modelFilePath: modelFilePath,
        cpuThreadCount: cpuThreadCount,
        replyPort: receivePort.sendPort,
      ),
    );

    receivePort.listen((message) {
      if (message is SendPort) {
        _commandPort = message;
        _initCompleter.complete();
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
      _InferenceRequest(TransferableTypedData.fromList([audio])),
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
  static Future<void> _isolateEntry(_IsolateConfig config) async {
    final commandPort = ReceivePort();
    config.replyPort.send(commandPort.sendPort);

    final session = SmartTurnOnnxSession();
    try {
      await session.initialize(
        modelFilePath: config.modelFilePath,
        cpuThreadCount: config.cpuThreadCount,
      );

      await for (final message in commandPort) {
        final (request, replyPort) = message as (_InferenceRequest, SendPort);
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
      config.replyPort.send(e);
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
