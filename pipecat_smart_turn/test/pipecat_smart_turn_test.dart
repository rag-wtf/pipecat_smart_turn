import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pipecat_smart_turn/pipecat_smart_turn.dart';
import 'package:pipecat_smart_turn_platform_interface/pipecat_smart_turn_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockPipecatSmartTurnPlatform extends Mock
    with MockPlatformInterfaceMixin
    implements PipecatSmartTurnPlatform {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(PipecatSmartTurnPlatform, () {
    late PipecatSmartTurnPlatform pipecatSmartTurnPlatform;

    setUp(() {
      pipecatSmartTurnPlatform = MockPipecatSmartTurnPlatform();
      PipecatSmartTurnPlatform.instance = pipecatSmartTurnPlatform;
    });

    group('getPlatformName', () {
      test('returns correct name when platform implementation exists',
          () async {
        const platformName = '__test_platform__';
        when(
          () => pipecatSmartTurnPlatform.getPlatformName(),
        ).thenAnswer((_) async => platformName);

        final actualPlatformName = await getPlatformName();
        expect(actualPlatformName, equals(platformName));
      });

      test('throws exception when platform implementation is missing',
          () async {
        when(
          () => pipecatSmartTurnPlatform.getPlatformName(),
        ).thenAnswer((_) async => null);

        expect(getPlatformName, throwsException);
      });
    });
  });
}
