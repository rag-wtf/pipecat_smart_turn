import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pipecat_smart_turn_platform_interface/src/method_channel_pipecat_smart_turn.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const kPlatformName = 'platformName';

  group('$MethodChannelPipecatSmartTurn', () {
    late MethodChannelPipecatSmartTurn methodChannelPipecatSmartTurn;
    final log = <MethodCall>[];

    setUp(() async {
      methodChannelPipecatSmartTurn = MethodChannelPipecatSmartTurn();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            methodChannelPipecatSmartTurn.methodChannel,
            (methodCall) async {
              log.add(methodCall);
              switch (methodCall.method) {
                case 'getPlatformName':
                  return kPlatformName;
                default:
                  return null;
              }
            },
          );
    });

    tearDown(log.clear);

    test('getPlatformName', () async {
      final platformName = await methodChannelPipecatSmartTurn
          .getPlatformName();
      expect(
        log,
        <Matcher>[isMethodCall('getPlatformName', arguments: null)],
      );
      expect(platformName, equals(kPlatformName));
    });
  });
}
