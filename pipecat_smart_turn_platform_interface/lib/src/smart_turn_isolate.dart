import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:pipecat_smart_turn_platform_interface/src/exceptions.dart';
import 'package:pipecat_smart_turn_platform_interface/src/onnx_inference.dart';

/// Configuration passed to the background worker isolate.
@visibleForTesting
class IsolateConfig {
  /// Creates an [IsolateConfig].
  IsolateConfig({
    required this.modelFilePath,
    required this.cpuThreadCount,
    required this.sendPort,
    this.onnxLibraryPath,
  });

  /// Path to the ONNX model file.
  final String modelFilePath;

  /// CPU thread count for inference.
  final int cpuThreadCount;

  /// Optional ONNX library path.
  final String? onnxLibraryPath;

  /// SendPort for communicate back to the main isolate.
  final SendPort sendPort;
}

enum _WorkerCommand { infer, dispose }

class _WorkerRequest {
  _WorkerRequest(this.command, {this.requestId = 0, this.audioData});
  final _WorkerCommand command;
  final int requestId;
  final Float32List? audioData;
}

class _WorkerResponse {
  _WorkerResponse({required this.requestId, this.result, this.error});
  final int requestId;
  final double? result;
  final String? error;
}

Future<void> _workerEntrypoint(IsolateConfig config) async {
  final receivePort = ReceivePort();
  config.sendPort.send(receivePort.sendPort);

  final session = SmartTurnOnnxSession();
  try {
    await session.initialize(
      modelFilePath: config.modelFilePath,
      cpuThreadCount: config.cpuThreadCount,
      onnxLibraryPath: config.onnxLibraryPath,
    );
  } on Object catch (e) {
    config.sendPort.send(_WorkerResponse(requestId: 0, error: e.toString()));
    return;
  }

  // Acknowledge initialization success (requestId 0)
  config.sendPort.send(_WorkerResponse(requestId: 0, result: 0));

  await for (final message in receivePort) {
    if (message is _WorkerRequest) {
      if (message.command == _WorkerCommand.dispose) {
        session.dispose();
        receivePort.close();
        break;
      } else if (message.command == _WorkerCommand.infer) {
        try {
          final result = await session.run(message.audioData!);
          config.sendPort.send(
            _WorkerResponse(requestId: message.requestId, result: result),
          );
        } on Object catch (e) {
          config.sendPort.send(
            _WorkerResponse(requestId: message.requestId, error: e.toString()),
          );
        }
      }
    }
  }
}

/// Manages ONNX inference dispatch.
///
/// Uses a long-lived isolate on Native platforms, and the main thread on Web.
class SmartTurnIsolate {
  Isolate? _isolate;
  SendPort? _sendPort;
  bool _isInitializing = false;
  int _nextRequestId = 1;
  final Map<int, Completer<_WorkerResponse>> _pendingRequests = {};
  Completer<_WorkerResponse>? _initCompleter;

  // Stored parameters for restarting isolate after timeout
  String? _modelFilePath;
  int _cpuThreadCount = 1;
  String? _onnxLibraryPath;

  // For web fallback
  SmartTurnOnnxSession? _webSession;

  /// Initializes the parameters and spawns the background isolate.
  Future<void> spawn({
    required String modelFilePath,
    int cpuThreadCount = 1,
    String? onnxLibraryPath,
  }) async {
    _modelFilePath = modelFilePath;
    _cpuThreadCount = cpuThreadCount;
    _onnxLibraryPath = onnxLibraryPath;

    if (kIsWeb) {
      _webSession = SmartTurnOnnxSession();
      await _webSession!.initialize(
        modelFilePath: modelFilePath,
        cpuThreadCount: cpuThreadCount,
        onnxLibraryPath: onnxLibraryPath,
      );
      return;
    }

    _isInitializing = true;
    _initCompleter = Completer<_WorkerResponse>();
    final receivePort = ReceivePort()
      ..listen((message) {
        if (message is SendPort) {
          _sendPort = message;
        } else if (message is _WorkerResponse) {
          if (message.requestId == 0) {
            if (_initCompleter != null && !_initCompleter!.isCompleted) {
              _initCompleter!.complete(message);
            }
          } else {
            final completer = _pendingRequests.remove(message.requestId);
            if (completer != null && !completer.isCompleted) {
              completer.complete(message);
            }
          }
        }
      });

    _isolate = await Isolate.spawn(
      _workerEntrypoint,
      IsolateConfig(
        modelFilePath: modelFilePath,
        cpuThreadCount: cpuThreadCount,
        onnxLibraryPath: onnxLibraryPath,
        sendPort: receivePort.sendPort,
      ),
    );

    // Wait for the isolate to initialize the model.
    final initResponse = await _initCompleter!.future;
    _isInitializing = false;

    if (initResponse.error != null) {
      kill();
      throw SmartTurnModelLoadException(
        'Worker isolate failed to initialize: ${initResponse.error}',
      );
    }
  }

  /// Sends audio to the worker isolate for inference and awaits probability.
  Future<double> predict(Float32List audio, {int timeoutMs = 2000}) async {
    if (kIsWeb) {
      if (_webSession == null) throw const SmartTurnNotInitializedException();
      return _webSession!
          .run(audio)
          .timeout(
            Duration(milliseconds: timeoutMs),
            onTimeout: () =>
                throw const SmartTurnInferenceException('Inference timed out'),
          );
    }

    if (_isolate == null || _sendPort == null) {
      if (_isInitializing) {
        throw const SmartTurnInferenceException(
          'Isolate is still initializing',
        );
      }
      throw const SmartTurnNotInitializedException();
    }

    final requestId = _nextRequestId++;
    final completer = Completer<_WorkerResponse>();
    _pendingRequests[requestId] = completer;

    _sendPort!.send(
      _WorkerRequest(
        _WorkerCommand.infer,
        requestId: requestId,
        audioData: audio,
      ),
    );

    try {
      final response = await completer.future.timeout(
        Duration(milliseconds: timeoutMs),
        onTimeout: () {
          _pendingRequests.remove(requestId);
          _restartWorkerOnTimeout();
          throw const SmartTurnInferenceException('Inference timed out');
        },
      );

      if (response.error != null) {
        throw SmartTurnInferenceException(response.error!);
      }

      return response.result!;
    } catch (e) {
      _pendingRequests.remove(requestId);
      rethrow;
    }
  }

  void _restartWorkerOnTimeout() {
    final modelPath = _modelFilePath;
    final threadCount = _cpuThreadCount;
    final libPath = _onnxLibraryPath;
    kill();
    if (modelPath != null) {
      spawn(
        modelFilePath: modelPath,
        cpuThreadCount: threadCount,
        onnxLibraryPath: libPath,
      ).ignore();
    }
  }

  /// Kills any background worker.
  void kill() {
    if (kIsWeb) {
      _webSession?.dispose();
      _webSession = null;
      return;
    }

    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          const SmartTurnInferenceException('Worker isolate killed'),
        );
      }
    }
    _pendingRequests.clear();

    _sendPort?.send(_WorkerRequest(_WorkerCommand.dispose));
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
    _initCompleter = null;
  }
}
