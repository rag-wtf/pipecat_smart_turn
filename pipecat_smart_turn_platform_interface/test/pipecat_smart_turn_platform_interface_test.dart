import 'package:flutter_test/flutter_test.dart';
import 'package:pipecat_smart_turn_platform_interface/pipecat_smart_turn_platform_interface.dart';
import 'package:pipecat_smart_turn_platform_interface/src/method_channel_pipecat_smart_turn.dart';

class PipecatSmartTurnPlatformMock extends PipecatSmartTurnPlatform {
  @override
  Future<String?> getPlatformName() async => 'Mock';
}

void main() {
  test('exports all required classes', () {
    expect(SmartTurnDetector, isNotNull);
    expect(SmartTurnConfig, isNotNull);
    expect(SmartTurnResult, isNotNull);
    expect(AudioPreprocessor, isNotNull);
    expect(AudioBuffer, isNotNull);
    expect(EnergyVad, isNotNull);
    expect(SmartTurnException, isNotNull);
  });

  group('PipecatSmartTurnPlatform', () {
    test('default instance is MethodChannelPipecatSmartTurn', () {
      expect(
        PipecatSmartTurnPlatform.instance,
        isA<MethodChannelPipecatSmartTurn>(),
      );
    });

    test('instance can be overridden', () {
      PipecatSmartTurnPlatform.instance = PipecatSmartTurnPlatformMock();
      expect(
        PipecatSmartTurnPlatform.instance,
        isA<PipecatSmartTurnPlatformMock>(),
      );
    });

    test('getPlatformName throws UnimplementedError by default', () async {
      // Create a class that extends PlatformInterface but doesn't override getPlatformName
      // Actually PipecatSmartTurnPlatform itself is abstract but we can extend it
      final platform = ExtendsPipecatSmartTurnPlatform();
      expect(
        () => platform.getPlatformName(),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });
}

class ExtendsPipecatSmartTurnPlatform extends PipecatSmartTurnPlatform {}
