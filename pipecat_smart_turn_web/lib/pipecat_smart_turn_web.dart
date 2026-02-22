import 'package:pipecat_smart_turn_platform_interface/pipecat_smart_turn_platform_interface.dart';

/// The Web implementation of [PipecatSmartTurnPlatform].
class PipecatSmartTurnWeb extends PipecatSmartTurnPlatform {
  /// Registers this class as the default instance of [PipecatSmartTurnPlatform]
  static void registerWith([Object? registrar]) {
    PipecatSmartTurnPlatform.instance = PipecatSmartTurnWeb();
  }

  @override
  Future<String?> getPlatformName() async => 'Web';
}
