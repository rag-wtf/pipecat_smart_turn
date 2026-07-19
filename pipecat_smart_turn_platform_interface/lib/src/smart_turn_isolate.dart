import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:pipecat_smart_turn_platform_interface/src/exceptions.dart';
import 'package:pipecat_smart_turn_platform_interface/src/onnx_inference.dart';

/// Configuration passed to the background worker isolate.
@visibleForTesting
class IsolateConfig {
  IsolateConfig({
    required this.modelFilePath,
    required this.cpuThreadCount,
    this.onnxLibraryPath,
    required this.sendPort,
  });

  final String modelFilePath;
  final int cpuThreadCount;
  final String? onnxLibraryPath;
  final SendPort sendPort;
}

enum _WorkerCommand { infer, dispose }

class _WorkerRequest {
  _WorkerRequest(this.command, [this.audioData]);
  final _WorkerCommand command;
  final Float32List? audioData;
}

class _WorkerResponse {
  _WorkerResponse({this.result, this.error});
  final double? result;
  final String? error;
}

void _workerEntrypoint(IsolateConfig config) async {
  final receivePort = ReceivePort();
  config.sendPort.send(receivePort.sendPort);

  final session = SmartTurnOnnxSession();
  try {
    await session.initialize(
      modelFilePath: config.modelFilePath,
      cpuThreadCount: config.cpuThreadCount,
      onnxLibraryPath: config.onnxLibraryPath,
    );
  } catch (e) {
    config.sendPort.send(_WorkerResponse(error: e.toString()));
    return;
  }

  // Acknowledge initialization success
  config.sendPort.send(_WorkerResponse(result: 0.0));

  await for (final message in receivePort) {
    if (message is _WorkerRequest) {
      if (message.command == _WorkerCommand.dispose) {
        session.dispose();
        receivePort.close();
        break;
      } else if (message.command == _WorkerCommand.infer) {
        try {
          final result = await session.run(message.audioData!);
          config.sendPort.send(_WorkerResponse(result: result));
        } catch (e) {
          config.sendPort.send(_WorkerResponse(error: e.toString()));
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
  StreamController<_WorkerResponse>? _responseStream;
  bool _isInitializing = false;

  // For web fallback
  SmartTurnOnnxSession? _webSession;

  /// Initializes the parameters and spawns the background isolate.
  Future<void> spawn({
    required String modelFilePath,
    int cpuThreadCount = 1,
    String? onnxLibraryPath,
  }) async {
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
    final receivePort = ReceivePort();
    _responseStream = StreamController<_WorkerResponse>.broadcast();

    receivePort.listen((message) {
      if (message is SendPort) {
        _sendPort = message;
      } else if (message is _WorkerResponse) {
        _responseStream!.add(message);
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
    final initResponse = await _responseStream!.stream.first;
    _isInitializing = false;

    if (initResponse.error != null) {
      kill();
      throw SmartTurnModelLoadException('Worker isolate failed to initialize: ${initResponse.error}');
    }
  }

  /// Sends audio to the worker isolate for inference and awaits probability.
  Future<double> predict(Float32List audio) async {
    if (kIsWeb) {
      if (_webSession == null) throw const SmartTurnNotInitializedException();
      return _webSession!.run(audio).timeout(
        const Duration(milliseconds: 2000),
        onTimeout: () => throw SmartTurnInferenceException('Inference timed out'),
      );
    }

    if (_isolate == null || _sendPort == null) {
      if (_isInitializing) {
        throw SmartTurnInferenceException('Isolate is still initializing');
      }
      throw const SmartTurnNotInitializedException();
    }

    _sendPort!.send(_WorkerRequest(_WorkerCommand.infer, audio));

    // Wait for response with a 2-second timeout (H4 fix)
    final response = await _responseStream!.stream.first.timeout(
      const Duration(milliseconds: 2000),
      onTimeout: () => throw SmartTurnInferenceException('Inference timed out'),
    );

    if (response.error != null) {
      throw SmartTurnInferenceException(response.error!);
    }

    return response.result!;
  }

  /// Kills any background worker.
  void kill() {
    if (kIsWeb) {
      _webSession?.dispose();
      _webSession = null;
      return;
    }

    _sendPort?.send(_WorkerRequest(_WorkerCommand.dispose));
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _sendPort = null;
    _responseStream?.close();
    _responseStream = null;
  }
}
