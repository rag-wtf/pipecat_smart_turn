import 'package:flutter_test/flutter_test.dart';
import 'package:pipecat_smart_turn_platform_interface/pipecat_smart_turn_platform_interface.dart';

void main() {
  group('math_utils - softmax2', () {
    test('outputs sum to 1.0', () {
      final (p0, p1) = softmax2(1.2, 0.5);
      expect(p0 + p1, closeTo(1, 1e-9));
    });

    test('higher logit yields higher probability', () {
      final (p0, p1) = softmax2(2, 0.5);
      expect(p0, greaterThan(p1));
    });

    test('is numerically stable for large logit differences', () {
      // Should not overflow or return NaN
      final (p0, p1) = softmax2(100, -100);
      expect(p0, closeTo(1, 1e-6));
      expect(p1, closeTo(0, 1e-6));
    });

    test('is numerically stable for large positive logits', () {
      final (p0, p1) = softmax2(1000, 1000);
      expect(p0, closeTo(0.5, 1e-6));
      expect(p1, closeTo(0.5, 1e-6));
    });
  });
}
