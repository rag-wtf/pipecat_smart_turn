import 'package:flutter_test/flutter_test.dart';
import 'package:pipecat_smart_turn_platform_interface/pipecat_smart_turn_platform_interface.dart';

class PipecatSmartTurnMock extends PipecatSmartTurnPlatform {
  static const mockPlatformName = 'Mock';

  @override
  Future<String?> getPlatformName() async => mockPlatformName;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('PipecatSmartTurnPlatformInterface', () {
    late PipecatSmartTurnPlatform pipecatSmartTurnPlatform;

    setUp(() {
      pipecatSmartTurnPlatform = PipecatSmartTurnMock();
      PipecatSmartTurnPlatform.instance = pipecatSmartTurnPlatform;
    });

    group('getPlatformName', () {
      test('returns correct name', () async {
        expect(
          await PipecatSmartTurnPlatform.instance.getPlatformName(),
          equals(PipecatSmartTurnMock.mockPlatformName),
        );
      });
    });
  });
}
