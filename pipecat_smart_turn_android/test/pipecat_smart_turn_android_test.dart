import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pipecat_smart_turn_android/pipecat_smart_turn_android.dart';
import 'package:pipecat_smart_turn_platform_interface/pipecat_smart_turn_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PipecatSmartTurnAndroid', () {
    const kPlatformName = 'Android';
    late PipecatSmartTurnAndroid pipecatSmartTurn;
    late List<MethodCall> log;

    setUp(() async {
      pipecatSmartTurn = PipecatSmartTurnAndroid();

      log = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pipecatSmartTurn.methodChannel, (
            methodCall,
          ) async {
            log.add(methodCall);
            switch (methodCall.method) {
              case 'getPlatformName':
                return kPlatformName;
              default:
                return null;
            }
          });
    });

    test('can be registered', () {
      PipecatSmartTurnAndroid.registerWith();
      expect(PipecatSmartTurnPlatform.instance, isA<PipecatSmartTurnAndroid>());
    });

    test('getPlatformName returns correct name', () async {
      final name = await pipecatSmartTurn.getPlatformName();
      expect(
        log,
        <Matcher>[isMethodCall('getPlatformName', arguments: null)],
      );
      expect(name, equals(kPlatformName));
    });
  });
}
