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
  final TransferableTypedData? audioData;
}

class _WorkerResponse {
  _WorkerResponse({required this.requestId, this.result, this.error});
  final int requestId;
  final double? result;
  final String? error;
}

class _WorkerParams {
  const _WorkerParams({
    required this.modelFilePath,
    required this.cpuThreadCount,
    this.onnxLibraryPath,
  });

  final String modelFilePath;
  final int cpuThreadCount;
  final String? onnxLibraryPath;
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
        config.sendPort.send(
          _WorkerResponse(requestId: message.requestId, result: 0),
        );
        receivePort.close();
        break;
      } else if (message.command == _WorkerCommand.infer) {
        try {
          final audioList = message.audioData!.materialize().asFloat32List();
          final result = await session.run(audioList);
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
  ReceivePort? _receivePort;
  ReceivePort? _errorPort;
  ReceivePort? _exitPort;
  bool _isInitializing = false;
  int _nextRequestId = 1;
  final Map<int, Completer<_WorkerResponse>> _pendingRequests = {};
  Completer<_WorkerResponse>? _initCompleter;

  // Stored parameters for restarting isolate after timeout
  _WorkerParams? _workerParams;

  // For web fallback
  SmartTurnOnnxSession? _webSession;

  /// Initializes the parameters and spawns the background isolate.
  Future<void> spawn({
    required String modelFilePath,
    int cpuThreadCount = 1,
    String? onnxLibraryPath,
  }) async {
    _workerParams = _WorkerParams(
      modelFilePath: modelFilePath,
      cpuThreadCount: cpuThreadCount,
      onnxLibraryPath: onnxLibraryPath,
    );

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

    _receivePort = ReceivePort()
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

    _errorPort = ReceivePort()
      ..listen((dynamic error) {
        _handleWorkerError('Worker isolate crashed: $error');
      });

    _exitPort = ReceivePort()
      ..listen((dynamic _) {
        _handleWorkerError('Worker isolate exited unexpectedly');
      });

    try {
      _isolate = await Isolate.spawn(
        _workerEntrypoint,
        IsolateConfig(
          modelFilePath: modelFilePath,
          cpuThreadCount: cpuThreadCount,
          onnxLibraryPath: onnxLibraryPath,
          sendPort: _receivePort!.sendPort,
        ),
        onError: _errorPort!.sendPort,
        onExit: _exitPort!.sendPort,
      );

      // Wait for the isolate to initialize the model (with 30s timeout).
      final initResponse = await _initCompleter!.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw const SmartTurnModelLoadException(
          'Worker isolate initialization timed out after 30 seconds',
        ),
      );

      if (initResponse.error != null) {
        await kill();
        throw SmartTurnModelLoadException(
          'Worker isolate failed to initialize: ${initResponse.error}',
        );
      }
    } on Object {
      await kill();
      rethrow;
    } finally {
      _isInitializing = false;
    }
  }

  void _handleWorkerError(String errorMessage) {
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(SmartTurnInferenceException(errorMessage));
      }
    }
    _pendingRequests.clear();
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
        audioData: TransferableTypedData.fromList([audio]),
      ),
    );

    try {
      final response = await completer.future.timeout(
        Duration(milliseconds: timeoutMs),
        onTimeout: () {
          _pendingRequests.remove(requestId);
          unawaited(_restartWorkerOnTimeout());
          throw const SmartTurnInferenceException('Inference timed out');
        },
      );

      if (response.error != null) {
        throw SmartTurnInferenceException(response.error!);
      }

      return response.result!;
    } on Object {
      _pendingRequests.remove(requestId);
      rethrow;
    }
  }

  Future<void> _restartWorkerOnTimeout() async {
    final params = _workerParams;
    await kill();
    if (params != null) {
      spawn(
        modelFilePath: params.modelFilePath,
        cpuThreadCount: params.cpuThreadCount,
        onnxLibraryPath: params.onnxLibraryPath,
      ).ignore();
    }
  }

  /// Kills any background worker and closes all ports.
  Future<void> kill() async {
    _isInitializing = false;

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

    if (_sendPort != null && _isolate != null) {
      final disposeCompleter = Completer<_WorkerResponse>();
      final requestId = _nextRequestId++;
      _pendingRequests[requestId] = disposeCompleter;
      try {
        _sendPort!.send(
          _WorkerRequest(_WorkerCommand.dispose, requestId: requestId),
        );
        await disposeCompleter.future.timeout(
          const Duration(milliseconds: 500),
          onTimeout: () => _WorkerResponse(requestId: requestId),
        );
      } on Object catch (_) {
        // Fall back to immediate kill below
      } finally {
        _pendingRequests.remove(requestId);
      }
    }

    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
    _initCompleter = null;

    _receivePort?.close();
    _receivePort = null;
    _errorPort?.close();
    _errorPort = null;
    _exitPort?.close();
    _exitPort = null;
  }
}
