#if canImport(Flutter)
@preconcurrency import Flutter
#endif
#if canImport(UIKit)
import UIKit
#endif

public class PipecatSmartTurnPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "pipecat_smart_turn_ios", binaryMessenger: registrar.messenger())
    let instance = PipecatSmartTurnPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformName":
      result("iOS")
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
