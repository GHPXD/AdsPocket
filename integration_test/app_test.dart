import 'package:ads_pocket/app/app.dart';
import 'package:ads_pocket/app/app_controller.dart';
import 'package:ads_pocket/core/meta_ads_library_url_builder.dart';
import 'package:ads_pocket/data/local_repository.dart';
import 'package:ads_pocket/data/models.dart';
import 'package:ads_pocket/features/browser/browser_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'support.dart';

/// Android checks of the logic AdsPocket controls: WebView lifecycle,
/// navigation, history, persistence and error handling. Whether Meta shows
/// ads is verified separately by `live_meta_test.dart`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Meta's public Page ID for its own Facebook Page, supplied explicitly.
  const pageId = '20531316728';

  testWidgets('Android: WebView navigation, history, favorites and restart', (
    tester,
  ) async {
    final path = '${await getDatabasesPath()}/adspocket.integration.db';
    await deleteDatabase(path);
    final repo = await LocalRepository.open(path: path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    final app = AppController(repo, prefs);
    await app.initialize();
    await tester.pumpWidget(AdsPocketApp(controller: app));
    await tester.pumpAndSettle();
    expect(find.text('AdsPocket'), findsOneWidget);
    await dismissColdShare(tester);
    await shot(tester, '01-explorar');

    // 1. Search from the native Explore screen.
    await tester.enterText(find.byType(TextField).first, 'planilha');
    await tester.ensureVisible(find.text('Explorar anúncios'));
    await tester.tap(find.text('Explorar anúncios'));
    await until(tester, () => app.tab == Tabs.library, 'abrir Biblioteca');
    expect(app.tab, Tabs.library);
    expect(app.history.single.query, 'planilha');
    final browser = tester.state<BrowserScreenState>(
      find.byType(BrowserScreen),
    );
    await until(tester, () => browser.controller != null, 'WebView criado');
    await until(tester, () => browser.loadsCompleted >= 1, 'carga concluída');
    await dismissExternalPrompt(tester);
    final searchUrl = await currentUrl(browser);
    expect(MetaAdsLibraryUrlBuilder.isLibrary(searchUrl), isTrue);
    expect(searchUrl.queryParameters['q'], 'planilha');
    expect(browser.failed, isFalse, reason: 'sem erro principal');
    debugPrint('ANDROID_SEARCH_TITLE=${await browser.controller!.getTitle()}');

    // 2. Switching tabs keeps the same native WebView.
    final original = browser.controller;
    app.selectTab(Tabs.explore);
    await tester.pump();
    app.selectTab(Tabs.library);
    await tester.pump();
    expect(
      tester.state<BrowserScreenState>(find.byType(BrowserScreen)).controller,
      same(original),
    );

    // 3. Saving on a search URL never creates an advertiser.
    await tester.tap(find.byTooltip('Salvar referência'));
    await tester.pumpAndSettle();
    expect(
      find.text('Não foi possível identificar uma Página nesta URL.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(app.bookmarks, isEmpty);

    // 4. Open a Page, then return to the search through WebView history.
    final page = MetaAdsLibraryUrlBuilder().build(
      text: pageId,
      type: SearchType.pageId,
    );
    final loadsBefore = browser.loadsCompleted;
    await app.openLibrary(page);
    await until(
      tester,
      () => browser.loadsCompleted > loadsBefore,
      'Página carregada',
    );
    await dismissExternalPrompt(tester);
    expect(MetaAdsLibraryUrlBuilder.pageId(await currentUrl(browser)), pageId);
    await until(tester, () => browser.canBack, 'histórico disponível');
    expect(find.textContaining('Anúncios da Página'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Pesquisa'), findsOneWidget);

    await tester.tap(find.widgetWithText(ActionChip, 'Pesquisa'));
    await until(
      tester,
      () => app.currentUrl.queryParameters['q'] == 'planilha',
      'retorno à pesquisa',
    );
    expect((await currentUrl(browser)).queryParameters['q'], 'planilha');
    // Forward stays available only if the jump moved back in history instead
    // of loading the search again as a new entry.
    await until(tester, () => browser.canForward, 'avançar disponível');

    // 5. Forward to the Page and save the identified advertiser.
    await tester.tap(find.byTooltip('Avançar'));
    await until(
      tester,
      () => MetaAdsLibraryUrlBuilder.pageId(app.currentUrl) == pageId,
      'avançar até a Página',
    );
    await dismissExternalPrompt(tester);
    await tester.tap(find.byTooltip('Salvar anunciante'));
    await tester.pumpAndSettle();
    expect(
      find.text('Anunciante identificado · Page ID $pageId'),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome amigável'),
      'Meta · referência de teste',
    );
    await tester.tap(find.text('Salvar').last);
    await until(tester, () => app.bookmarks.isNotEmpty, 'anunciante salvo');
    expect(app.bookmarks.single.kind, BookmarkKind.advertiser);
    expect(app.bookmarks.single.pageId, pageId);

    // 6. Main-frame failure shows the error state, retry recovers.
    await browser.controller!.loadUrl(
      urlRequest: URLRequest(url: WebUri('https://adspocket-test.invalid/')),
    );
    await until(tester, () => browser.failed, 'erro de carregamento');
    expect(find.text('Não foi possível carregar a Biblioteca'), findsOneWidget);
    await shot(tester, '03-erro-carregamento');
    expect(find.text('Abrir no navegador'), findsWidgets);
    final loadsBeforeRetry = browser.loadsCompleted;
    await tester.tap(find.text('Tentar novamente'));
    await until(
      tester,
      () => !browser.failed && browser.loadsCompleted > loadsBeforeRetry,
      'recuperação',
    );
    expect(MetaAdsLibraryUrlBuilder.pageId(await currentUrl(browser)), pageId);

    // 7. Immersive mode hides the app navigation in the Library.
    await app.setImmersive(true);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    await app.setImmersive(false);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);

    // 8. Restart: data persists and the favorite reopens the right Page.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    app.dispose();
    await repo.close();
    final reopened = await LocalRepository.open(path: path);
    final next = AppController(reopened, prefs);
    await next.initialize();
    expect(next.history.single.query, 'planilha');
    expect(next.bookmarks.single.pageId, pageId);
    expect(MetaAdsLibraryUrlBuilder.pageId(next.currentUrl), pageId);
    await tester.pumpWidget(AdsPocketApp(controller: next));
    await tester.pumpAndSettle();
    await next.visit(next.bookmarks.single);
    await tester.pump(const Duration(seconds: 1));
    final second = tester.state<BrowserScreenState>(find.byType(BrowserScreen));
    await until(tester, () => second.loadsCompleted >= 1, 'reabertura');
    expect(MetaAdsLibraryUrlBuilder.pageId(await currentUrl(second)), pageId);
    expect(next.bookmarks.single.lastVisitedAt, isNotNull);
    expect(await next.visits(next.bookmarks.single), hasLength(1));
    await shot(tester, '02-reabertura-favorito');
    debugPrint('ADSPOCKET_DETERMINISTIC_ANDROID_OK');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    next.dispose();
    await reopened.close();
  });
}
