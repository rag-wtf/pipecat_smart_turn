import 'package:pipecat_smart_turn_platform_interface/src/method_channel_pipecat_smart_turn.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// The interface that implementations of pipecat_smart_turn must implement.
abstract class PipecatSmartTurnPlatform extends PlatformInterface {
  /// Constructs a [PipecatSmartTurnPlatform].
  PipecatSmartTurnPlatform() : super(token: _token);

  static final Object _token = Object();

  static PipecatSmartTurnPlatform _instance = MethodChannelPipecatSmartTurn();

  /// The default instance of [PipecatSmartTurnPlatform] to use.
  ///
  /// Defaults to [MethodChannelPipecatSmartTurn].
  static PipecatSmartTurnPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [PipecatSmartTurnPlatform] when
  /// they register themselves.
  static set instance(PipecatSmartTurnPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Returns the name of the platform.
  Future<String?> getPlatformName() {
    throw UnimplementedError('getPlatformName() has not been implemented.');
  }
}
