import 'package:flutter_test/flutter_test.dart';
import 'package:pipecat_smart_turn_platform_interface/pipecat_smart_turn_platform_interface.dart';

void main() {
  group('SmartTurnException', () {
    test('SmartTurnNotInitializedException toString', () {
      const exception = SmartTurnNotInitializedException();
      expect(
        exception.toString(),
        contains('SmartTurnDetector must be initialized'),
      );
    });

    test('SmartTurnModelLoadException toString', () {
      const exception = SmartTurnModelLoadException('file not found');
      expect(exception.toString(), contains('file not found'));
    });

    test('SmartTurnInferenceException toString', () {
      const exception = SmartTurnInferenceException('inference failed');
      expect(exception.toString(), contains('inference failed'));
    });
  });
}
