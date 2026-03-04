import 'dart:ffi';
import 'dart:io';
import 'package:pipecat_smart_turn_platform_interface/src/platform/native/bindings/onnxruntime_bindings_generated.dart';

final DynamicLibrary _dylib = () {
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libonnxruntime.so');
  }

  if (Platform.isIOS) {
    return DynamicLibrary.process();
  }

  if (Platform.isMacOS) {
    return DynamicLibrary.process();
  }

  if (Platform.isWindows) {
    return DynamicLibrary.open('onnxruntime.dll');
  }

  if (Platform.isLinux) {
    return DynamicLibrary.open('libonnxruntime.so.1.24.2');
  }

  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

/// ONNX Runtime Bindings
final onnxRuntimeBinding = OnnxRuntimeBindings(_dylib);
