import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pipecat_smart_turn_platform_interface/src/pipecat_smart_turn_platform.dart';

/// An implementation of [PipecatSmartTurnPlatform] that uses method channels.
class MethodChannelPipecatSmartTurn extends PipecatSmartTurnPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('pipecat_smart_turn');

  @override
  Future<String?> getPlatformName() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformName');
    return version;
  }
}
