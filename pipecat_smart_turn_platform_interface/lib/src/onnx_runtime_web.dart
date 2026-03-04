// Ignore public API docs because JS interop bindings are implementation
// details.
// ignore_for_file: public_member_api_docs

import 'dart:js_interop';

@JS('ort')
external OrtGlobal get ort;

@JS()
extension type OrtGlobal._(JSObject _) implements JSObject {
  external EnvNamespace get env;
  // Ignore non constant identifier names to map to the JS InferenceSession
  // constructor.
  // ignore: non_constant_identifier_names
  external InferenceSessionConstructor get InferenceSession;
  // Ignore non constant identifier names to map to the JS Tensor
  // constructor.
  // ignore: non_constant_identifier_names
  external TensorConstructor get Tensor;
}

@JS()
extension type EnvNamespace._(JSObject _) implements JSObject {
  external WasmNamespace get wasm;
}

@JS()
extension type WasmNamespace._(JSObject _) implements JSObject {
  external String get wasmPaths;
  external set wasmPaths(String paths);
  external int get numThreads;
  external set numThreads(int threads);
}

@JS()
extension type SessionOptions._(JSObject _) implements JSObject {
  external JSArray<JSString> get executionProviders;
  external set executionProviders(JSArray<JSString> value);
}

/// Creates a [SessionOptions] object with the given [executionProviders].
SessionOptions createSessionOptions({
  List<String> executionProviders = const ['wasm'],
}) {
  final opts = <String, Object>{}.jsify()! as SessionOptions;
  opts.executionProviders = executionProviders.map((e) => e.toJS).toList().toJS;
  return opts;
}

@JS()
extension type InferenceSessionConstructor._(JSObject _) implements JSObject {
  external JSPromise<InferenceSession> create(
    JSAny modelData, [
    SessionOptions? options,
  ]);
}

@JS()
extension type TensorConstructor._(JSObject _) implements JSObject {
  external Tensor create(
    String type,
    JSFloat32Array data,
    JSArray<JSNumber> dims,
  );
}

@JS()
extension type InferenceSession._(JSObject _) implements JSObject {
  external JSPromise<RunResult> run(JSObject feeds);
  external JSPromise<JSAny?> release();
}

@JS()
extension type Tensor._(JSObject _) implements JSObject {
  external JSFloat32Array get data;
  external JSArray<JSNumber> get dims;
}

@JS()
extension type RunResult._(JSObject _) implements JSObject {
  external Tensor operator [](String key);
}
