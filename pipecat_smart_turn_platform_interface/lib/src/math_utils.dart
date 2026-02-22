import 'dart:math' as math;

/// Computes a numerically stable softmax over two logits.
///
/// Returns a [Record] containing (incompleteProbability, completeProbability).
///
/// Smart Turn v3 outputs two logits:
/// - index 0: "Incomplete" (speaking)
/// - index 1: "Complete" (finished)
(double, double) softmax2(double logit0, double logit1) {
  final maxLogit = math.max(logit0, logit1);

  final exp0 = math.exp(logit0 - maxLogit);
  final exp1 = math.exp(logit1 - maxLogit);
  final sum = exp0 + exp1;

  return (exp0 / sum, exp1 / sum);
}
