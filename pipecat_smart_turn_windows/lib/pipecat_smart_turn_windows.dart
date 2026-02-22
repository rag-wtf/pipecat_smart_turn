import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pipecat_smart_turn_platform_interface/pipecat_smart_turn_platform_interface.dart';

/// The Windows implementation of [PipecatSmartTurnPlatform].
class PipecatSmartTurnWindows extends PipecatSmartTurnPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('pipecat_smart_turn_windows');

  /// Registers this class as the default instance of [PipecatSmartTurnPlatform]
  static void registerWith() {
    PipecatSmartTurnPlatform.instance = PipecatSmartTurnWindows();
  }

  @override
  Future<String?> getPlatformName() {
    return methodChannel.invokeMethod<String>('getPlatformName');
  }
}
