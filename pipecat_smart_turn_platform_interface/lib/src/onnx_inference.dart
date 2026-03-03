export 'onnx_inference_stub.dart'
    if (dart.library.ffi) 'onnx_inference_native.dart'
    if (dart.library.js_interop) 'onnx_inference_web.dart';
