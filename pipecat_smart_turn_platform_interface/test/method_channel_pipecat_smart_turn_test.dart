import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pipecat_smart_turn_platform_interface/src/method_channel_pipecat_smart_turn.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MethodChannelPipecatSmartTurn', () {
    const channel = MethodChannel('pipecat_smart_turn');
    final platform = MethodChannelPipecatSmartTurn();

    test('getPlatformName', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        channel,
        (MethodCall methodCall) async {
          return '42';
        },
      );

      expect(await platform.getPlatformName(), '42');
    });
  });
}
