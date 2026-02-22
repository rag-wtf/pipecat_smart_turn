import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pipecat_smart_turn_platform_interface/pipecat_smart_turn_platform_interface.dart';
import 'package:pipecat_smart_turn_windows/pipecat_smart_turn_windows.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PipecatSmartTurnWindows', () {
    const kPlatformName = 'Windows';
    late PipecatSmartTurnWindows pipecatSmartTurn;
    late List<MethodCall> log;

    setUp(() async {
      pipecatSmartTurn = PipecatSmartTurnWindows();

      log = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pipecatSmartTurn.methodChannel, (methodCall) async {
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
      PipecatSmartTurnWindows.registerWith();
      expect(PipecatSmartTurnPlatform.instance, isA<PipecatSmartTurnWindows>());
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
