import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:pipecat_smart_turn_platform_interface/src/platform/native/bindings/onnxruntime_bindings_generated.dart'
    as bg;
import 'package:pipecat_smart_turn_platform_interface/src/platform/native/onnxruntime/ort_env.dart';
import 'package:pipecat_smart_turn_platform_interface/src/platform/native/onnxruntime/ort_status.dart';
import 'package:pipecat_smart_turn_platform_interface/src/platform/native/onnxruntime/ort_value.dart';

/// A class that represents an ONNX Runtime session.
class OrtSession {
  /// Creates a session from buffer.
  OrtSession.fromBuffer(Uint8List modelBuffer, OrtSessionOptions options) {
    final pp = calloc<ffi.Pointer<bg.OrtSession>>();
    final size = modelBuffer.length;
    final bufferPtr = calloc<ffi.Uint8>(size);
    bufferPtr.asTypedList(size).setRange(0, size, modelBuffer);
    final statusPtr = OrtEnv.instance.ortApiPtr.ref.CreateSessionFromArray
        .asFunction<
          bg.OrtStatusPtr Function(
            ffi.Pointer<bg.OrtEnv>,
            ffi.Pointer<ffi.Void>,
            int,
            ffi.Pointer<bg.OrtSessionOptions>,
            ffi.Pointer<ffi.Pointer<bg.OrtSession>>,
          )
        >()(OrtEnv.instance.ptr, bufferPtr.cast(), size, options._ptr, pp);
    OrtStatus.checkOrtStatus(statusPtr);
    _ptr = pp.value;
    calloc
      ..free(pp)
      ..free(bufferPtr);
    _init();
  }

  /// Creates a session from a pointer's address.
  OrtSession.fromAddress(int address) {
    _ptr = ffi.Pointer.fromAddress(address);
    _init();
  }
  late ffi.Pointer<bg.OrtSession> _ptr;
  late int _inputCount;
  late List<String> _inputNames;
  late int _outputCount;
  late List<String> _outputNames;

  /// Gets the address of the session pointer.
  int get address => _ptr.address;

  /// Gets the number of inputs.
  int get inputCount => _inputCount;

  /// Gets the input names.
  List<String> get inputNames => _inputNames;

  /// Gets the number of outputs.
  int get outputCount => _outputCount;

  /// Gets the output names.
  List<String> get outputNames => _outputNames;

  void _init() {
    _inputCount = _getInputCount();
    _inputNames = _getInputNames();
    _outputCount = _getOutputCount();
    _outputNames = _getOutputNames();
  }

  int _getInputCount() {
    final countPtr = calloc<ffi.Size>();
    final statusPtr = OrtEnv.instance.ortApiPtr.ref.SessionGetInputCount
        .asFunction<
          bg.OrtStatusPtr Function(
            ffi.Pointer<bg.OrtSession>,
            ffi.Pointer<ffi.Size>,
          )
        >()(_ptr, countPtr);
    OrtStatus.checkOrtStatus(statusPtr);
    final count = countPtr.value;
    calloc.free(countPtr);
    return count;
  }

  int _getOutputCount() {
    final countPtr = calloc<ffi.Size>();
    final statusPtr = OrtEnv.instance.ortApiPtr.ref.SessionGetOutputCount
        .asFunction<
          bg.OrtStatusPtr Function(
            ffi.Pointer<bg.OrtSession>,
            ffi.Pointer<ffi.Size>,
          )
        >()(_ptr, countPtr);
    OrtStatus.checkOrtStatus(statusPtr);
    final count = countPtr.value;
    calloc.free(countPtr);
    return count;
  }

  List<String> _getInputNames() {
    final list = <String>[];
    for (var i = 0; i < _inputCount; ++i) {
      final namePtrPtr = calloc<ffi.Pointer<ffi.Char>>();
      var statusPtr = OrtEnv.instance.ortApiPtr.ref.SessionGetInputName
          .asFunction<
            bg.OrtStatusPtr Function(
              ffi.Pointer<bg.OrtSession>,
              int,
              ffi.Pointer<bg.OrtAllocator>,
              ffi.Pointer<ffi.Pointer<ffi.Char>>,
            )
          >()(_ptr, i, OrtAllocator.instance.ptr, namePtrPtr);
      OrtStatus.checkOrtStatus(statusPtr);
      final name = namePtrPtr.value.cast<Utf8>().toDartString();
      list.add(name);
      statusPtr = OrtEnv.instance.ortApiPtr.ref.AllocatorFree
          .asFunction<
            bg.OrtStatusPtr Function(
              ffi.Pointer<bg.OrtAllocator>,
              ffi.Pointer<ffi.Void>,
            )
          >()(OrtAllocator.instance.ptr, namePtrPtr.value.cast());
      OrtStatus.checkOrtStatus(statusPtr);
      calloc.free(namePtrPtr);
    }
    return list;
  }

  List<String> _getOutputNames() {
    final list = <String>[];
    for (var i = 0; i < _outputCount; ++i) {
      final namePtrPtr = calloc<ffi.Pointer<ffi.Char>>();
      var statusPtr = OrtEnv.instance.ortApiPtr.ref.SessionGetOutputName
          .asFunction<
            bg.OrtStatusPtr Function(
              ffi.Pointer<bg.OrtSession>,
              int,
              ffi.Pointer<bg.OrtAllocator>,
              ffi.Pointer<ffi.Pointer<ffi.Char>>,
            )
          >()(_ptr, i, OrtAllocator.instance.ptr, namePtrPtr);
      OrtStatus.checkOrtStatus(statusPtr);
      final name = namePtrPtr.value.cast<Utf8>().toDartString();
      list.add(name);
      statusPtr = OrtEnv.instance.ortApiPtr.ref.AllocatorFree
          .asFunction<
            bg.OrtStatusPtr Function(
              ffi.Pointer<bg.OrtAllocator>,
              ffi.Pointer<ffi.Void>,
            )
          >()(OrtAllocator.instance.ptr, namePtrPtr.value.cast());
      OrtStatus.checkOrtStatus(statusPtr);
      calloc.free(namePtrPtr);
    }
    return list;
  }

  /// Performs inference synchronously.
  List<OrtValue?> run(
    OrtRunOptions runOptions,
    Map<String, OrtValue> inputs, [
    List<String>? outputNames,
  ]) {
    final inputLength = inputs.length;
    final inputNamePtrs = calloc<ffi.Pointer<ffi.Char>>(inputLength);
    final inputPtrs = calloc<ffi.Pointer<bg.OrtValue>>(inputLength);
    var i = 0;
    for (final entry in inputs.entries) {
      inputNamePtrs[i] = entry.key.toNativeUtf8().cast<ffi.Char>();
      inputPtrs[i] = entry.value.ptr;
      ++i;
    }
    outputNames ??= _outputNames;
    final outputLength = outputNames.length;
    final outputNamePtrs = calloc<ffi.Pointer<ffi.Char>>(outputLength);
    final outputPtrs = calloc<ffi.Pointer<bg.OrtValue>>(outputLength);
    for (var i = 0; i < outputLength; ++i) {
      outputNamePtrs[i] = outputNames[i].toNativeUtf8().cast<ffi.Char>();
      outputPtrs[i] = ffi.nullptr;
    }
    var statusPtr =
        OrtEnv.instance.ortApiPtr.ref.Run
            .asFunction<
              bg.OrtStatusPtr Function(
                ffi.Pointer<bg.OrtSession>,
                ffi.Pointer<bg.OrtRunOptions>,
                ffi.Pointer<ffi.Pointer<ffi.Char>>,
                ffi.Pointer<ffi.Pointer<bg.OrtValue>>,
                int,
                ffi.Pointer<ffi.Pointer<ffi.Char>>,
                int,
                ffi.Pointer<ffi.Pointer<bg.OrtValue>>,
              )
            >()(
          _ptr,
          runOptions._ptr,
          inputNamePtrs,
          inputPtrs,
          inputLength,
          outputNamePtrs,
          outputLength,
          outputPtrs,
        );
    OrtStatus.checkOrtStatus(statusPtr);
    final outputs = List<OrtValue?>.generate(outputLength, (index) {
      final ortValuePtr = outputPtrs[index];
      final onnxTypePtr = calloc<ffi.Int32>();
      statusPtr = OrtEnv.instance.ortApiPtr.ref.GetValueType
          .asFunction<
            bg.OrtStatusPtr Function(
              ffi.Pointer<bg.OrtValue>,
              ffi.Pointer<ffi.UnsignedInt>,
            )
          >()(ortValuePtr, onnxTypePtr.cast());
      OrtStatus.checkOrtStatus(statusPtr);
      final onnxType = ONNXType.fromValue(onnxTypePtr.value);
      calloc.free(onnxTypePtr);
      if (onnxType == ONNXType.tensor) {
        return OrtValueTensor(ortValuePtr);
      } else {
        throw Exception(
          'Unexpected output type: $onnxType. '
          'ONNX model only produces tensors.',
        );
      }
    });
    calloc
      ..free(inputNamePtrs)
      ..free(inputPtrs)
      ..free(outputNamePtrs)
      ..free(outputPtrs);
    return outputs;
  }

  /// Releases the session.
  void release() {
    OrtEnv.instance.ortApiPtr.ref.ReleaseSession
        .asFunction<void Function(ffi.Pointer<bg.OrtSession>)>()(_ptr);
  }
}

/// A class that represents session options.
class OrtSessionOptions {
  /// Internal constructor for [OrtSessionOptions].
  OrtSessionOptions() {
    _create();
  }
  late ffi.Pointer<bg.OrtSessionOptions> _ptr;

  void _create() {
    final pp = calloc<ffi.Pointer<bg.OrtSessionOptions>>();
    final statusPtr = OrtEnv.instance.ortApiPtr.ref.CreateSessionOptions
        .asFunction<
          bg.OrtStatusPtr Function(
            ffi.Pointer<ffi.Pointer<bg.OrtSessionOptions>>,
          )
        >()(pp);
    OrtStatus.checkOrtStatus(statusPtr);
    _ptr = pp.value;
    calloc.free(pp);
  }

  /// Releases the session options.
  void release() {
    OrtEnv.instance.ortApiPtr.ref.ReleaseSessionOptions
        .asFunction<void Function(ffi.Pointer<bg.OrtSessionOptions>)>()(_ptr);
  }

  /// Sets the number of intra op threads.
  void setIntraOpNumThreads(int numThreads) {
    final statusPtr = OrtEnv.instance.ortApiPtr.ref.SetIntraOpNumThreads
        .asFunction<
          bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtSessionOptions>, int)
        >()(_ptr, numThreads);
    OrtStatus.checkOrtStatus(statusPtr);
  }

  /// Sets the number of inter op threads.
  void setInterOpNumThreads(int numThreads) {
    final statusPtr = OrtEnv.instance.ortApiPtr.ref.SetInterOpNumThreads
        .asFunction<
          bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtSessionOptions>, int)
        >()(_ptr, numThreads);
    OrtStatus.checkOrtStatus(statusPtr);
  }

  /// Sets the level of session graph optimization.
  void setSessionGraphOptimizationLevel(GraphOptimizationLevel level) {
    final statusPtr = OrtEnv
        .instance
        .ortApiPtr
        .ref
        .SetSessionGraphOptimizationLevel
        .asFunction<
          bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtSessionOptions>, int)
        >()(_ptr, level.value);
    OrtStatus.checkOrtStatus(statusPtr);
  }
}

/// A class that represents run options.
class OrtRunOptions {
  /// Internal constructor for [OrtRunOptions].
  OrtRunOptions() {
    _create();
  }

  /// Creates run options from a pointer's address.
  OrtRunOptions.fromAddress(int address) {
    _ptr = ffi.Pointer.fromAddress(address);
  }
  late ffi.Pointer<bg.OrtRunOptions> _ptr;

  /// Gets the address of the run options pointer.
  int get address => _ptr.address;

  void _create() {
    final pp = calloc<ffi.Pointer<bg.OrtRunOptions>>();
    final statusPtr = OrtEnv.instance.ortApiPtr.ref.CreateRunOptions
        .asFunction<
          bg.OrtStatusPtr Function(ffi.Pointer<ffi.Pointer<bg.OrtRunOptions>>)
        >()(pp);
    OrtStatus.checkOrtStatus(statusPtr);
    _ptr = pp.value;
    calloc.free(pp);
  }

  /// Releases the run options.
  void release() {
    OrtEnv.instance.ortApiPtr.ref.ReleaseRunOptions
        .asFunction<void Function(ffi.Pointer<bg.OrtRunOptions> input)>()(_ptr);
  }
}

/// An enumerated value of graph optimization level.
enum GraphOptimizationLevel {
  /// Disable all optimizations.
  ortDisableAll(0),

  /// Enable basic optimizations.
  ortEnableBasic(1),

  /// Enable extended optimizations.
  ortEnableExtended(2),

  /// Enable all optimizations.
  ortEnableAll(99)
  ;

  const GraphOptimizationLevel(this.value);

  /// The level value.
  final int value;
}
