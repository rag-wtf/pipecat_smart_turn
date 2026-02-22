import 'package:flutter_test/flutter_test.dart';
import 'package:pipecat_smart_turn_platform_interface/pipecat_smart_turn_platform_interface.dart';
import 'package:pipecat_smart_turn_web/pipecat_smart_turn_web.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PipecatSmartTurnWeb', () {
    const kPlatformName = 'Web';
    late PipecatSmartTurnWeb pipecatSmartTurn;

    setUp(() async {
      pipecatSmartTurn = PipecatSmartTurnWeb();
    });

    test('can be registered', () {
      PipecatSmartTurnWeb.registerWith();
      expect(PipecatSmartTurnPlatform.instance, isA<PipecatSmartTurnWeb>());
    });

    test('getPlatformName returns correct name', () async {
      final name = await pipecatSmartTurn.getPlatformName();
      expect(name, equals(kPlatformName));
    });
  });
}
