import 'package:flutter_test/flutter_test.dart';
import 'package:pipecat_smart_turn/pipecat_smart_turn.dart';

void main() {
  test('re-exports the smart turn API', () {
    // Basic verification that the app package correctly exposes the
    // platform interface.
    expect(SmartTurnDetector, isNotNull);
    expect(SmartTurnConfig, isNotNull);
  });

  test('has correct version', () {
    expect(getPipecatSmartTurnVersion(), '0.1.0+1');
  });
}
