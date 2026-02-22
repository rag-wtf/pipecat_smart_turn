import 'package:pipecat_smart_turn_platform_interface/src/method_channel_pipecat_smart_turn.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// {@template pipecat_smart_turn_platform}
/// The interface that implementations of pipecat_smart_turn must implement.
///
/// Platform implementations should extend this class
/// rather than implement it as `PipecatSmartTurn`.
///
/// Extending this class (using `extends`) ensures that the subclass will get
/// the default implementation, while platform implementations that `implements`
/// this interface will be broken by newly added
/// [PipecatSmartTurnPlatform] methods.
/// {@endtemplate}
abstract class PipecatSmartTurnPlatform extends PlatformInterface {
  /// {@macro pipecat_smart_turn_platform}
  PipecatSmartTurnPlatform() : super(token: _token);

  static final Object _token = Object();

  static PipecatSmartTurnPlatform _instance = MethodChannelPipecatSmartTurn();

  /// The default instance of [PipecatSmartTurnPlatform] to use.
  ///
  /// Defaults to [MethodChannelPipecatSmartTurn].
  static PipecatSmartTurnPlatform get instance => _instance;

  /// Platform-specific plugins should set this with their own platform-specific
  /// class that extends [PipecatSmartTurnPlatform] when they register
  /// themselves.
  static set instance(PipecatSmartTurnPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// Return the current platform name.
  Future<String?> getPlatformName();
}
