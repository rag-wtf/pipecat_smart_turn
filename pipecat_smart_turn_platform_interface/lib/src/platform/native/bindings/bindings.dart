import 'dart:ffi';
import 'dart:io';
import 'package:pipecat_smart_turn_platform_interface/src/platform/native/bindings/onnxruntime_bindings_generated.dart';

/// Resolves the absolute path to the ONNX Runtime shared library for the
/// current platform. Must be called from the **main isolate** (where
/// [Platform.resolvedExecutable] points to the app bundle executable) and
/// the result passed into any [compute()] isolates via a message.
///
/// Returns `null` on platforms that don't need an explicit path
/// (iOS, macOS use [DynamicLibrary.process()]).
String? resolveOnnxLibraryPath() {
  if (Platform.isLinux) {
    final execDir = File(Platform.resolvedExecutable).parent.path;
    return '$execDir/lib/libonnxruntime.so.1.24.2';
  }
  if (Platform.isWindows) {
    final execDir = File(Platform.resolvedExecutable).parent.path;
    return '$execDir/onnxruntime.dll';
  }
  return null;
}

/// Opens the ONNX Runtime [DynamicLibrary] for the current platform.
///
/// On Linux and Windows, [libraryPath] must be the absolute path resolved
/// by [resolveOnnxLibraryPath()] in the main isolate. On other platforms
/// the parameter is ignored.
DynamicLibrary openOnnxLibrary(String? libraryPath) {
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libonnxruntime.so');
  }
  if (Platform.isIOS || Platform.isMacOS) {
    return DynamicLibrary.process();
  }
  if (Platform.isLinux || Platform.isWindows) {
    if (libraryPath == null) {
      throw ArgumentError(
        'libraryPath must be provided on Linux/Windows. '
        'Call resolveOnnxLibraryPath() in the main isolate first.',
      );
    }
    return DynamicLibrary.open(libraryPath);
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}

/// Returns an [OnnxRuntimeBindings] instance for the given [libraryPath].
/// See [openOnnxLibrary] and [resolveOnnxLibraryPath] for details.
OnnxRuntimeBindings openOnnxRuntimeBinding(String? libraryPath) =>
    OnnxRuntimeBindings(openOnnxLibrary(libraryPath));
