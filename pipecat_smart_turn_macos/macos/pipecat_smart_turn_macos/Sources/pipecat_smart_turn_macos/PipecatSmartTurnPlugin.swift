import FlutterMacOS
import Foundation

public class PipecatSmartTurnPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "pipecat_smart_turn_macos", binaryMessenger: registrar.messenger)
    let instance = PipecatSmartTurnPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    result("macOS")
  }
}
