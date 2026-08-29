import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pipecat_smart_turn/pipecat_smart_turn.dart';
import 'package:pipecat_smart_turn_example/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('E2E', () {
    testWidgets('shows platform name in AppBar', (tester) async {
      app.main();
      await tester.pumpAndSettle();
      final expected = expectedPlatformName();
      // Platform name is displayed in the AppBar subtitle area
      await tester.ensureVisible(find.text('Platform: $expected'));
      expect(find.text('Platform: $expected'), findsOneWidget);
    });

    testWidgets('initializes and runs end-to-end inference prediction', (
      tester,
    ) async {
      final detector = SmartTurnDetector();
      await detector.initialize();

      // Create 1.0 second of synthetic 16kHz audio (16,000 samples)
      final audioSamples = Float32List(16000);
      for (var i = 0; i < 16000; i++) {
        audioSamples[i] = math.sin(2 * math.pi * 440.0 * i / 16000) * 0.5;
      }

      final result = await detector.predict(audioSamples);

      expect(result, isNotNull);
      expect(result!.confidence, inInclusiveRange(0.0, 1.0));
      expect(result.latencyMs, greaterThanOrEqualTo(0));
      expect(result.audioLengthMs, equals(1000.0));

      await detector.dispose();
    });
  });
}

String expectedPlatformName() {
  if (isWeb) return 'Web';
  if (Platform.isAndroid) return 'Android';
  if (Platform.isIOS) return 'iOS';
  if (Platform.isLinux) return 'Linux';
  if (Platform.isMacOS) return 'MacOS';
  if (Platform.isWindows) return 'Windows';
  throw UnsupportedError('Unsupported platform ${Platform.operatingSystem}');
}

bool get isWeb => identical(0, 0.0);
