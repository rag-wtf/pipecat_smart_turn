import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pipecat_smart_turn_platform_interface/pipecat_smart_turn_platform_interface.dart';

/// The Android implementation of [PipecatSmartTurnPlatform].
class PipecatSmartTurnAndroid extends PipecatSmartTurnPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('pipecat_smart_turn_android');

  /// Registers this class as the default instance of [PipecatSmartTurnPlatform]
  static void registerWith() {
    PipecatSmartTurnPlatform.instance = PipecatSmartTurnAndroid();
  }

  @override
  Future<String?> getPlatformName() {
    return methodChannel.invokeMethod<String>('getPlatformName');
  }
}
