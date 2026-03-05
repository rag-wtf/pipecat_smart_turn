import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

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
