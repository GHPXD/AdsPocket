import 'package:ads_pocket/app/app.dart';
import 'package:ads_pocket/app/app_controller.dart';
import 'package:ads_pocket/core/meta_ads_library_url_builder.dart';
import 'package:ads_pocket/data/local_repository.dart';
import 'package:ads_pocket/data/models.dart';
import 'package:ads_pocket/features/browser/browser_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android: search, browser preservation, favorites and local restart', (
    tester,
  ) async {
    final path = '${await getDatabasesPath()}/adspocket.integration.db';
    await deleteDatabase(path);
    final repo = await LocalRepository.open(path: path);
    final prefs = await SharedPreferences.getInstance();
    final app = AppController(repo, prefs);
    await app.initialize();
    await app.updateSettings(const UserSettings());
    await tester.pumpWidget(AdsPocketApp(controller: app));
    await tester.pumpAndSettle();
    expect(find.text('AdsPocket'), findsOneWidget);
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    var coldShare = false;
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (find.text('Recebido no AdsPocket').evaluate().isNotEmpty) {
        coldShare = true;
        await binding.takeScreenshot('00-compartilhamento-inicial');
        await tester.tap(find.text('Cancelar').last);
        await tester.pump(const Duration(milliseconds: 500));
        break;
      }
    }
    debugPrint('ADSPOCKET_COLD_SHARE_RECEIVED=$coldShare');
    await binding.takeScreenshot('01-explorar');
    await tester.enterText(find.byType(TextField).first, 'planilha');
    await tester.ensureVisible(find.text('Explorar anúncios'));
    await tester.tap(find.text('Explorar anúncios'));
    await tester.pump(const Duration(seconds: 2));
    expect(app.tab, 1);
    expect(app.history.single.query, 'planilha');
    final browser = tester.state<BrowserScreenState>(
      find.byType(BrowserScreen),
    );
    // Native platform-view creation is asynchronous, especially on a cold emulator.
    for (var i = 0; i < 180 && browser.controller == null; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    expect(browser.controller, isNotNull);
    for (
      var i = 0;
      i < 40 && browser.progress < 100 && browser.problem == null;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 250));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    final url = await browser.controller!.getUrl();
    debugPrint(
      'ANDROID_META_URL_IS_LIBRARY=${url != null && MetaAdsLibraryUrlBuilder.isLibrary(Uri.parse(url.toString()))}',
    );
    debugPrint('ANDROID_META_TITLE=${await browser.controller!.getTitle()}');
    debugPrint('ANDROID_META_HAS_ERROR=${browser.problem != null}');
    debugPrint('ADSPOCKET_WEBVIEW_CHECKED');
    await _dismissExternalPrompt(tester);
    final originalController = browser.controller;
    app.selectTab(0);
    await tester.pump();
    app.selectTab(1);
    await tester.pump();
    expect(
      tester.state<BrowserScreenState>(find.byType(BrowserScreen)).controller,
      same(originalController),
    );

    // Meta's public Page ID for its own Facebook Page, supplied explicitly.
    // This validates saved-link navigation; availability of live results is separate.
    final page = MetaAdsLibraryUrlBuilder().build(
      text: '20531316728',
      type: SearchType.pageId,
    );
    await app.openLibrary(page);
    await tester.pump(const Duration(seconds: 2));
    await _dismissExternalPrompt(tester);
    await tester.tap(find.byTooltip('Salvar anunciante'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome amigável'),
      'Meta · referência de teste',
    );
    await tester.tap(find.text('Salvar').last);
    await tester.pump(const Duration(seconds: 2));
    expect(app.bookmarks, hasLength(1));
    expect(app.bookmarks.single.pageId, '20531316728');
    app.selectTab(2);
    await tester.pumpAndSettle();
    debugPrint('ADSPOCKET_BOOKMARK_SAVED');
    await app.updateSettings(app.settings.copyWith(theme: 'light'));
    app.selectTab(3);
    await tester.pumpAndSettle();
    debugPrint('ADSPOCKET_THEME_CHANGED');
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
    if (const bool.fromEnvironment('TEST_ANDROID_SHARES') && !coldShare) {
      debugPrint('ADSPOCKET_READY_SHARE_FOREGROUND');
      await _waitForSharedDialog(tester);
      await tester.tap(find.text('Cancelar').last);
      await tester.pump(const Duration(milliseconds: 500));
      debugPrint('ADSPOCKET_READY_SHARE_BACKGROUND');
      await _waitForSharedDialog(tester);
      await tester.tap(find.text('Abrir agora').last);
      await tester.pump(const Duration(seconds: 2));
      expect(app.currentUrl.queryParameters['view_all_page_id'], '20531316728');
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    app.dispose();
    await repo.close();
    final reopened = await LocalRepository.open(path: path);
    final next = AppController(reopened, prefs);
    await next.initialize();
    expect(next.history.single.query, 'planilha');
    expect(next.bookmarks.single.name, 'Meta · referência de teste');
    expect(next.settings.theme, 'light');
    await tester.pumpWidget(AdsPocketApp(controller: next));
    await tester.pumpAndSettle();
    await next.visit(next.bookmarks.single);
    await tester.pump(const Duration(seconds: 2));
    expect(next.currentUrl.queryParameters['view_all_page_id'], '20531316728');
    expect(next.bookmarks.single.lastVisitedAt, isNotNull);
    await next.openExternal(next.currentUrl);
    await Future<void>.delayed(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    next.dispose();
    await reopened.close();
  });
}

Future<void> _waitForSharedDialog(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.text('Recebido no AdsPocket').evaluate().isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  fail('O intent Android de compartilhamento não chegou no prazo.');
}

Future<void> _dismissExternalPrompt(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 250));
    if (find.text('Continuar no navegador?').evaluate().isNotEmpty) {
      await tester.tap(find.text('Cancelar').last);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
    } else {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.byType(AlertDialog).evaluate().isEmpty) return;
    }
  }
}
