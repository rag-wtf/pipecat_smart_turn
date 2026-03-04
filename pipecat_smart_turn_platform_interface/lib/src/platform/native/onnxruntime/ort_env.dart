import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'package:pipecat_smart_turn_platform_interface/src/platform/native/bindings/bindings.dart';
import 'package:pipecat_smart_turn_platform_interface/src/platform/native/bindings/onnxruntime_bindings_generated.dart'
    as bg;
import 'package:pipecat_smart_turn_platform_interface/src/platform/native/onnxruntime/ort_status.dart';

/// A class about onnx runtime environment.
class OrtEnv {
  /// Internal constructor for [OrtEnv].
  OrtEnv._() {
    _ortApiPtr = onnxRuntimeBinding.OrtGetApiBase().ref.GetApi
        .asFunction<ffi.Pointer<bg.OrtApi> Function(int)>()(apiVersion.value);
  }

  /// The singleton instance of [OrtEnv].
  static OrtEnv get instance => _instance;

  static final OrtEnv _instance = OrtEnv._();

  /// The API version of onnx runtime.
  static OrtApiVersion apiVersion = OrtApiVersion.api14;

  ffi.Pointer<bg.OrtEnv>? _ptr;

  late ffi.Pointer<bg.OrtApi> _ortApiPtr;

  /// Initialize the onnx runtime environment.
  void init({
    OrtLoggingLevel level = OrtLoggingLevel.warning,
    String logId = 'DartOnnxRuntime',
  }) {
    final pp = calloc<ffi.Pointer<bg.OrtEnv>>();
    final statusPtr = _ortApiPtr.ref.CreateEnv
        .asFunction<
          bg.OrtStatusPtr Function(
            int,
            ffi.Pointer<ffi.Char>,
            ffi.Pointer<ffi.Pointer<bg.OrtEnv>>,
          )
        >()(level.value, logId.toNativeUtf8().cast<ffi.Char>(), pp);
    OrtStatus.checkOrtStatus(statusPtr);
    _ptr = pp.value;
    _setLanguageProjection();
    calloc.free(pp);
  }

  /// Release the onnx runtime environment.
  void release() {
    if (_ptr == null) {
      return;
    }
    _ortApiPtr.ref.ReleaseEnv
        .asFunction<void Function(ffi.Pointer<bg.OrtEnv>)>()(_ptr!);
    _ptr = null;
  }

  /// Gets the version of onnx runtime.
  static String get version => onnxRuntimeBinding.OrtGetApiBase()
      .ref
      .GetVersionString
      .asFunction<ffi.Pointer<ffi.Char> Function()>()()
      .cast<Utf8>()
      .toDartString();

  /// Gets the onnx runtime API pointer.
  ffi.Pointer<bg.OrtApi> get ortApiPtr => _ortApiPtr;

  /// Gets the onnx runtime environment pointer.
  ffi.Pointer<bg.OrtEnv> get ptr {
    if (_ptr == null) {
      init();
    }
    return _ptr!;
  }

  void _setLanguageProjection() {
    if (_ptr == null) {
      init();
    }
    final status = _ortApiPtr.ref.SetLanguageProjection
        .asFunction<
          bg.OrtStatusPtr Function(ffi.Pointer<bg.OrtEnv>, int)
        >()(_ptr!, 0); // ORT_PROJECTION_C
    OrtStatus.checkOrtStatus(status);
  }
}

/// An enumerated value of api's version.
enum OrtApiVersion {
  /// API version 1.
  api1(1),

  /// API version 2.
  api2(2),

  /// API version 3.
  api3(3),

  /// API version 7.
  api7(7),

  /// API version 8.
  api8(8),

  /// API version 11.
  api11(11),

  /// API version 13.
  api13(13),

  /// API version 14.
  api14(14),

  /// Training API version 1.
  trainingApi1(1)
  ;

  const OrtApiVersion(this.value);

  /// The version value.
  final int value;
}

/// An enumerated value of log's level.
enum OrtLoggingLevel {
  /// Verbose logging level.
  verbose(0),

  /// Info logging level.
  info(1),

  /// Warning logging level.
  warning(2),

  /// Error logging level.
  error(3),

  /// Fatal logging level.
  fatal(4)
  ;

  const OrtLoggingLevel(this.value);

  /// The logging level value.
  final int value;
}

/// A class that manages ORT default allocator.
class OrtAllocator {
  /// Internal constructor for [OrtAllocator].
  OrtAllocator._() {
    final pp = calloc<ffi.Pointer<bg.OrtAllocator>>();
    final statusPtr = OrtEnv
        .instance
        .ortApiPtr
        .ref
        .GetAllocatorWithDefaultOptions
        .asFunction<
          bg.OrtStatusPtr Function(ffi.Pointer<ffi.Pointer<bg.OrtAllocator>>)
        >()(pp);
    OrtStatus.checkOrtStatus(statusPtr);
    _ptr = pp.value;
    calloc.free(pp);
  }

  /// The singleton instance of [OrtAllocator].
  static OrtAllocator get instance => _instance;

  static final OrtAllocator _instance = OrtAllocator._();

  late ffi.Pointer<bg.OrtAllocator> _ptr;

  /// Gets the onnx runtime allocator pointer.
  ffi.Pointer<bg.OrtAllocator> get ptr => _ptr;
}
