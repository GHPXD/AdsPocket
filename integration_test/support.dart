import 'package:ads_pocket/features/browser/browser_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Asks the host script (`tool/android_tests.sh`) to take a real `adb
/// screencap`. Flutter's own capture cannot include the hybrid WebView.
Future<void> shot(WidgetTester tester, String name) async {
  debugPrint('ADSPOCKET_SHOT=$name');
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 150));
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
}

/// Asks the host script for a real touch (`adb shell input tap`) at a point
/// given in Flutter logical pixels.
Future<void> physicalTap(WidgetTester tester, Offset logical) async {
  final ratio = tester.view.devicePixelRatio;
  debugPrint(
    'ADSPOCKET_TAP=${(logical.dx * ratio).round()},${(logical.dy * ratio).round()}',
  );
  await wait(tester, const Duration(seconds: 3));
}

/// Real Backspace presses through `adb shell input keyevent`.
Future<void> physicalDelete(WidgetTester tester, int count) async {
  debugPrint('ADSPOCKET_DEL=$count');
  await wait(tester, const Duration(seconds: 4));
}

/// Real keyboard input through `adb shell input text` (ASCII only).
Future<void> physicalText(WidgetTester tester, String text) async {
  assert(RegExp(r'^[A-Za-z0-9 ]+$').hasMatch(text));
  debugPrint('ADSPOCKET_TEXT=${text.replaceAll(' ', '%s')}');
  await wait(tester, const Duration(seconds: 3));
}

Future<void> until(
  WidgetTester tester,
  bool Function() condition,
  String what, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) fail('Tempo esgotado: $what');
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  await tester.pump();
}

Future<void> wait(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

Future<Uri> currentUrl(BrowserScreenState b) async =>
    Uri.parse((await b.controller!.getUrl()).toString());

/// Closes the "Continuar no navegador?" prompt if Meta tries to leave.
Future<void> dismissExternalPrompt(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    if (find.text('Continuar no navegador?').evaluate().isNotEmpty) {
      await tester.tap(find.text('Cancelar').last);
      await tester.pump(const Duration(milliseconds: 500));
    } else if (find.byType(AlertDialog).evaluate().isEmpty) {
      return;
    }
  }
}

Future<void> dismissColdShare(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (find.text('Recebido no AdsPocket').evaluate().isNotEmpty) {
      await tester.tap(find.text('Cancelar').last);
      await tester.pump(const Duration(milliseconds: 500));
      return;
    }
  }
}
