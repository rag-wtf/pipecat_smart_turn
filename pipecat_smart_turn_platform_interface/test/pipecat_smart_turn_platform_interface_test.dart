import 'package:flutter_test/flutter_test.dart';
import 'package:pipecat_smart_turn_platform_interface/pipecat_smart_turn_platform_interface.dart';

void main() {
  test('exports all required classes', () {
    // Verify that the barrel file exports the main API classes
    // (Testing for existence by referencing them)
    expect(SmartTurnDetector, isNotNull);
    expect(SmartTurnConfig, isNotNull);
    expect(SmartTurnResult, isNotNull);
    expect(AudioPreprocessor, isNotNull);
    expect(AudioBuffer, isNotNull);
    expect(EnergyVad, isNotNull);
    expect(SmartTurnException, isNotNull);
  });
}
