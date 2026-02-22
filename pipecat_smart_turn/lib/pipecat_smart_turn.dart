import 'package:pipecat_smart_turn_platform_interface/pipecat_smart_turn_platform_interface.dart';

PipecatSmartTurnPlatform get _platform => PipecatSmartTurnPlatform.instance;

/// Returns the name of the current platform.
Future<String> getPlatformName() async {
  final platformName = await _platform.getPlatformName();
  if (platformName == null) throw Exception('Unable to get platform name.');
  return platformName;
}
