import 'dart:convert';
import 'package:ads_pocket/app/app.dart';
import 'package:ads_pocket/app/app_controller.dart';
import 'package:ads_pocket/core/longevity.dart';
import 'package:ads_pocket/core/meta_ads_library_url_builder.dart';
import 'package:ads_pocket/data/local_repository.dart';
import 'package:ads_pocket/data/models.dart';
import 'package:ads_pocket/data/offer.dart';
import 'package:ads_pocket/features/browser/browser_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'support.dart';

/// LIVE test against the official Library. It needs network access and real
/// active ads. It passes only when the rendered page shows real ad cards; a
/// valid URL or title is never accepted as proof.
///
/// The DOM is read here only to *verify* what the user sees (test code, not
/// app infrastructure). The app itself never extracts cards.
const _probe = r'''(() => {
  const t = document.body ? document.body.innerText : '';
  return JSON.stringify({
    len: t.length,
    libraryIds: (t.match(/(Library ID|Identificação da biblioteca|ID da biblioteca):?\s*\d{5,}/g) || []).length,
    started: (t.match(/Started running on|Veiculação iniciada em|Começou a ser veiculad|Iniciado em/g) || []).length,
    videos: document.querySelectorAll('video').length,
    images: document.querySelectorAll('img').length,
    challenge: document.documentElement.outerHTML.includes('__rd_verify'),
    width: window.innerWidth
  });
})()''';

/// First advertiser in the results whose name can be typed with adb.
const _asciiAdvertiser = r'''(() => {
  for (const a of document.querySelectorAll('a[href]')) {
    const name = (a.innerText || '').trim();
    if (!/^https:\/\/(www\.|web\.|m\.)?facebook\.com\/[^/?#]+\/?$/.test(a.href) ||
        !/^[A-Za-z][A-Za-z0-9 ]{3,24}$/.test(name)) continue;
    // Advertiser of an ad card: its header block says "Sponsored".
    let e = a;
    for (let i = 0; i < 4 && e; i++, e = e.parentElement) {
      const t = e.innerText || '';
      if (t.length < 300 && /Sponsored|Patrocinado/.test(t)) return name;
    }
  }
  return null;
})()''';

const _searchInput = r'''(() => {
  const i = document.querySelector('input[type=search], input[placeholder]');
  if (!i) return null;
  i.scrollIntoView({block: 'center'});
  const r = i.getBoundingClientRect();
  return JSON.stringify({x: r.left + r.width / 2, y: r.top + r.height / 2});
})()''';

/// Topmost visible element below the search field whose text is the name.
String _suggestion(String name) =>
    '''(() => {
  const i = document.querySelector('input[type=search], input[placeholder]');
  const below = i ? i.getBoundingClientRect().bottom : 0;
  let best = null;
  for (const e of document.querySelectorAll('div,span,li,a')) {
    const t = (e.innerText || '').trim();
    if (t !== ${jsonEncode(name)} && !t.startsWith(${jsonEncode(name)} + '\\n')) continue;
    const r = e.getBoundingClientRect();
    if (r.height === 0 || r.top < below || r.top > window.innerHeight) continue;
    if (!best || r.top < best.top) best = r;
  }
  return best ? JSON.stringify({x: best.left + Math.min(best.width / 2, 60), y: best.top + best.height / 2}) : null;
})()''';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // The advertiser is selected with a real touch from `adb shell input tap`.
  binding.shouldPropagateDevicePointerEvents = true;

  testWidgets('LIVE: search, real ads, select Page, save and reopen', (
    tester,
  ) async {
    final path = '${await getDatabasesPath()}/adspocket.live.db';
    await deleteDatabase(path);
    final repo = await LocalRepository.open(path: path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    final app = AppController(repo, prefs);
    await app.initialize();
    await tester.pumpWidget(AdsPocketApp(controller: app));
    await tester.pumpAndSettle();
    await dismissColdShare(tester);
    await shot(tester, '10-live-explorar');

    // 1-3. Keyword search from the native screen.
    await tester.enterText(find.byType(TextField).first, 'planilha');
    await tester.ensureVisible(find.text('Explorar anúncios'));
    await tester.tap(find.text('Explorar anúncios'));
    await until(tester, () => app.tab == Tabs.library, 'abrir Biblioteca');
    final browser = tester.state<BrowserScreenState>(
      find.byType(BrowserScreen),
    );
    await until(tester, () => browser.loadsCompleted >= 1, 'carga inicial');

    Future<Map<String, dynamic>> probe() async =>
        jsonDecode(
              await browser.controller!.evaluateJavascript(source: _probe)
                  as String,
            )
            as Map<String, dynamic>;

    /// Waits until real ad cards are rendered, or fails with the cause.
    Future<Map<String, dynamic>> ads(String step) async {
      var p = <String, dynamic>{};
      final end = DateTime.now().add(const Duration(seconds: 60));
      while (DateTime.now().isBefore(end)) {
        await dismissExternalPrompt(tester);
        p = await probe();
        if ((p['libraryIds'] as int) > 0 && (p['started'] as int) > 0) {
          debugPrint('LIVE_STEP $step=APROVADO ${jsonEncode(p)}');
          return p;
        }
        await wait(tester, const Duration(seconds: 2));
      }
      debugPrint('LIVE_STEP $step=FALHOU ${jsonEncode(p)}');
      final visible =
          await browser.controller!.evaluateJavascript(
                source: 'document.body ? document.body.innerText : ""',
              )
              as String;
      final lines = visible.split('\n').where((l) => l.trim().isNotEmpty);
      for (final line in lines.take(40)) {
        debugPrint('LIVE_TEXT $line');
      }
      debugPrint('LIVE_URL ${await currentUrl(browser)}');
      fail(
        p['challenge'] == true
            ? 'BLOQUEADO PELO SERVIÇO EXTERNO ($step): página de verificação da Meta.'
            : 'NÃO VERIFICADO ($step): nenhum card com Library ID e data de início apareceu.',
      );
    }

    // 4. Real ads are visible in the search results.
    final results = await ads('resultados');
    expect(results['libraryIds'], greaterThan(0));
    final searchUrl = await currentUrl(browser);
    expect(searchUrl.queryParameters['q'], 'planilha');
    await shot(tester, '11-live-resultados');

    // Assistant: cards read from the page, ages computed in the app.
    await until(
      tester,
      () => browser.cards.length >= 5 && browser.stats != null,
      'assistente leu os cards',
    );
    final st = browser.stats!;
    debugPrint(
      'LIVE_ASSIST cards=${browser.cards.length} results=${st.results} '
      'loaded=${st.loaded} active=${st.active}',
    );
    expect(st.results, isNotEmpty, reason: 'contagem exibida pela Meta');
    final dated = browser.cards.values.where((c) => c.start != null).length;
    expect(dated, greaterThan(0), reason: 'datas de início lidas dos cards');
    debugPrint('LIVE_STEP assistente-leitura=APROVADO dated=$dated');

    // Local age filter: every visible card is >= 30 days, every hidden < 30.
    await app.updateSettings(
      app.settings.copyWith(minDays: () => 30, includeUndated: false),
    );
    await wait(tester, const Duration(seconds: 3));
    final split =
        jsonDecode(
              await browser.controller!.evaluateJavascript(
                    source: '''JSON.stringify((() => {
                const v = [], h = [];
                for (const b of document.querySelectorAll('[data-adspocket]')) {
                  (b.parentElement.style.display === 'none' ? h : v).push(b.getAttribute('data-adspocket'));
                }
                return {v, h}; })())''',
                  )
                  as String,
            )
            as Map<String, dynamic>;
    final today = CivilDate.today();
    int? age(Object? id) => ageInDays(browser.cards[id]?.start, today);
    final shown = (split['v'] as List).cast<String>();
    final hidden = (split['h'] as List).cast<String>();
    debugPrint(
      'LIVE_FILTER30 visiveis=${shown.length} ocultos=${hidden.length}',
    );
    for (final id in shown) {
      expect(age(id), isNotNull, reason: 'visível sem data: $id');
      expect(age(id)!, greaterThanOrEqualTo(30), reason: 'visível $id');
    }
    for (final id in hidden) {
      final a = age(id);
      expect(a == null || a < 30, isTrue, reason: 'oculto $id');
    }
    expect(shown.length + hidden.length, greaterThan(0));
    debugPrint('LIVE_STEP filtro-idade=APROVADO');
    await shot(tester, '11b-live-assistente-filtro');

    // Ads-count filter: Meta's "N ads use this creative and text".
    final counts = <int, int>{};
    for (final c in browser.cards.values) {
      counts[c.variations ?? 1] = (counts[c.variations ?? 1] ?? 0) + 1;
    }
    debugPrint('LIVE_ADS_COUNTS $counts');
    await app.updateSettings(
      app.settings.copyWith(minDays: () => null, minAds: () => 2),
    );
    await wait(tester, const Duration(seconds: 3));
    final byAds =
        jsonDecode(
              await browser.controller!.evaluateJavascript(
                    source: '''JSON.stringify((() => {
                const v = [], h = [];
                for (const b of document.querySelectorAll('[data-adspocket]')) {
                  (b.parentElement.style.display === 'none' ? h : v).push(b.getAttribute('data-adspocket'));
                }
                return {v, h}; })())''',
                  )
                  as String,
            )
            as Map<String, dynamic>;
    int n(Object? id) => browser.cards[id]?.variations ?? 1;
    for (final id in (byAds['v'] as List)) {
      expect(n(id), greaterThanOrEqualTo(2), reason: 'visível $id');
    }
    for (final id in (byAds['h'] as List)) {
      expect(n(id), lessThan(2), reason: 'oculto $id');
    }
    debugPrint(
      'LIVE_STEP filtro-quantidade=${(byAds['v'] as List).isEmpty ? 'INCONCLUSIVO (nenhum card com 2+)' : 'APROVADO'} '
      'visiveis=${(byAds['v'] as List).length} ocultos=${(byAds['h'] as List).length}',
    );
    await shot(tester, '11e-live-filtro-quantidade');
    await app.updateSettings(
      app.settings.copyWith(minDays: () => 30, minAds: () => null),
    );
    await wait(tester, const Duration(seconds: 2));

    // One-tap save with a real touch on the card's save button.
    if (shown.isNotEmpty) {
      final target = shown.first;
      final saveAt =
          jsonDecode(
                await browser.controller!.evaluateJavascript(
                      source:
                          '''(() => { const b = document.querySelector('[data-adspocket="$target"] [data-act=save]');
                b.scrollIntoView({block: 'center'}); const r = b.getBoundingClientRect();
                return JSON.stringify({x: r.left + r.width / 2, y: r.top + r.height / 2}); })()''',
                    )
                    as String,
              )
              as Map<String, dynamic>;
      await wait(tester, const Duration(seconds: 1));
      await physicalTap(
        tester,
        tester.getTopLeft(find.byType(InAppWebView)) +
            Offset(
              (saveAt['x'] as num).toDouble(),
              (saveAt['y'] as num).toDouble(),
            ),
      );
      await until(tester, () => app.offers.isNotEmpty, 'anúncio salvo');
      final saved = app.offers.single;
      expect(saved.adId, target);
      expect(saved.startDate, browser.cards[target]!.start);
      expect(saved.dateSource, DateSource.library);
      expect(saved.advertiser, isNotEmpty);
      await wait(tester, const Duration(seconds: 2));
      final badge = await browser.controller!.evaluateJavascript(
        source:
            'document.querySelector(\'[data-adspocket="$target"] [data-act=save]\').getAttribute("aria-label")',
      );
      expect(badge, 'Salvo no AdsPocket');
      debugPrint(
        'LIVE_STEP salvar-1-toque=APROVADO ${saved.advertiser} ${saved.startDate} ${saved.status.name}',
      );
      await shot(tester, '11c-live-salvo-1-toque');
    }

    // Auto-scroll loads more cards from Meta, then stops.
    final before = browser.stats?.loaded ?? 0;
    await tester.tap(find.text('Auto-rolar'));
    await wait(tester, const Duration(seconds: 3));
    debugPrint(
      'LIVE_SCROLL scrolling=${browser.stats?.scrolling} loaded=${browser.stats?.loaded} visible=${browser.stats?.visible}',
    );
    try {
      await until(
        tester,
        () => (browser.stats?.loaded ?? 0) > before + 5,
        'auto-rolagem carregou mais anúncios',
        timeout: const Duration(seconds: 90),
      );
    } catch (_) {
      // Evidence of what Meta showed when it stopped loading.
      await shot(tester, '11d-live-auto-rolagem-falha');
      debugPrint(
        'LIVE_SCROLL_FAIL ${browser.stats?.loaded} ${await browser.controller!.evaluateJavascript(source: "(document.body.innerText || '').slice(-400)")}',
      );
      rethrow;
    }
    await shot(tester, '11d-live-auto-rolagem');
    if (browser.stats?.scrolling ?? false) {
      await tester.tap(find.text('Parar'));
      await until(
        tester,
        () => !(browser.stats?.scrolling ?? true),
        'parar auto-rolagem',
      );
    }
    debugPrint(
      'LIVE_STEP auto-rolagem=APROVADO $before -> ${browser.stats?.loaded}',
    );

    // Back to an unfiltered page at the top for the next steps.
    await app.updateSettings(
      app.settings.copyWith(minDays: () => null, includeUndated: true),
    );
    await browser.controller!.evaluateJavascript(
      source: 'window.scrollTo(0, 0)',
    );
    await wait(tester, const Duration(seconds: 2));

    // Card "Página" button (real touch): the app opens the ad details as the
    // user would, reads the Page ID under "Sobre o anunciante" and opens all
    // active ads of that Page. The profile link ID is never used.
    final pageAt =
        jsonDecode(
              await browser.controller!.evaluateJavascript(
                    source:
                        '''(() => { const bs = [...document.querySelectorAll('[data-adspocket]')].filter((b) => b.parentElement.style.display !== 'none' && b.querySelector('[data-act=page]'));
              const b = bs[0]; b.scrollIntoView({block: 'center'}); const r = b.querySelector('[data-act=page]').getBoundingClientRect();
              return JSON.stringify({id: b.getAttribute('data-adspocket'), x: r.left + r.width / 2, y: r.top + r.height / 2}); })()''',
                  )
                  as String,
            )
            as Map<String, dynamic>;
    await wait(tester, const Duration(seconds: 1));
    final cardId = pageAt['id'] as String;
    final cardAdvertiser = browser.cards[cardId]!.advertiser;
    await shot(tester, '21-live-acoes-do-card');
    await physicalTap(
      tester,
      tester.getTopLeft(find.byType(InAppWebView)) +
          Offset(
            (pageAt['x'] as num).toDouble(),
            (pageAt['y'] as num).toDouble(),
          ),
    );
    await until(
      tester,
      () =>
          MetaAdsLibraryUrlBuilder.pageId(app.currentUrl) != null ||
          browser.pendingPick != null,
      'Página aberta pelo botão do card',
      timeout: const Duration(seconds: 40),
    );
    // Older Pages show no ID in the details: the app types the advertiser in
    // Meta's search and highlights it; the user's real tap picks it.
    final picked = browser.pendingPick != null;
    if (picked) {
      await wait(tester, const Duration(seconds: 2));
      final optionAt = await browser.controller!.evaluateJavascript(
        source:
            '''(() => { const o = [...document.querySelectorAll('[role=listbox] [role=option]')].find((e) => e.style.outline);
          if (!o) return null; const r = o.getBoundingClientRect();
          return JSON.stringify({x: r.left + r.width / 2, y: r.top + r.height / 2}); })()''',
      );
      if (optionAt == null) {
        fail(
          'NÃO VERIFICADO: a Meta não sugeriu o anunciante "$cardAdvertiser".',
        );
      }
      await shot(tester, '21b-live-escolher-anunciante');
      final o = jsonDecode(optionAt as String) as Map<String, dynamic>;
      await tester.pump();
      await physicalTap(
        tester,
        tester.getTopLeft(find.byType(InAppWebView)) +
            Offset((o['x'] as num).toDouble(), (o['y'] as num).toDouble()),
      );
      await until(
        tester,
        () => MetaAdsLibraryUrlBuilder.pageId(app.currentUrl) != null,
        'Página escolhida na lista da Meta',
        timeout: const Duration(seconds: 30),
      );
    }
    final cardPage = MetaAdsLibraryUrlBuilder.pageId(app.currentUrl)!;
    expect(browser.pageOfAd[cardId], cardPage);
    final profile = browser.cards[cardId]?.profile;
    final profileId = profile == null
        ? null
        : MetaAdsLibraryUrlBuilder.profilePageId(profile);
    // Meta swaps the view without reloading: wait for this Page's own counter
    // and header, not for whatever the previous view left behind.
    await until(
      tester,
      () =>
          browser.stats?.url != null &&
          MetaAdsLibraryUrlBuilder.pageId(browser.stats!.url!) == cardPage &&
          browser.stats!.results.isNotEmpty,
      'contagem da Página do card',
      timeout: const Duration(seconds: 40),
    );
    var named = false;
    for (var i = 0; i < 20 && !named; i++) {
      final text = await browser.controller!.evaluateJavascript(
        source: 'document.body.innerText',
      );
      named = text is String && text.contains(cardAdvertiser);
      if (!named) await wait(tester, const Duration(seconds: 1));
    }
    expect(
      named,
      isTrue,
      reason: 'a Página aberta pelo card deve ser a do anunciante do card',
    );
    expect(app.currentUrl.queryParameters['active_status'], 'active');
    await wait(tester, const Duration(seconds: 2));
    await shot(tester, '22-live-pagina-pelo-card');
    debugPrint(
      'LIVE_STEP pagina-pelo-card=APROVADO ${picked ? 'via lista de anunciantes' : 'via Sobre o anunciante'} $cardAdvertiser anuncio=$cardId pagina=$cardPage perfil=$profileId',
    );
    await browser.jumpTo(app.initialSearch!);
    await until(
      tester,
      () =>
          MetaAdsLibraryUrlBuilder.pageId(app.currentUrl) == null &&
          browser.stats?.url?.queryParameters['q'] == 'planilha' &&
          (browser.stats?.loaded ?? 0) > 0,
      'retorno à pesquisa com os cards',
      timeout: const Duration(seconds: 40),
    );
    debugPrint('LIVE_URL_RETORNO ${await currentUrl(browser)}');
    await wait(tester, const Duration(seconds: 3));
    await browser.controller!.evaluateJavascript(
      source: 'window.scrollTo(0, 0)',
    );

    // 5. Select an advertiser Page the official way: type its name in Meta's
    //    search field and tap the advertiser suggestion (real touch + keys).
    final raw = await browser.controller!.evaluateJavascript(
      source: _asciiAdvertiser,
    );
    if (raw == null) {
      debugPrint('LIVE_STEP selecionar-pagina=INCONCLUSIVO');
      fail('NÃO VERIFICADO: nenhum anunciante com nome digitável nesta busca.');
    }
    final name = raw as String;
    debugPrint('LIVE_ADVERTISER=$name');
    Future<Offset?> center(String js) async {
      final r = await browser.controller!.evaluateJavascript(source: js);
      if (r == null) return null;
      final m = jsonDecode(r as String) as Map<String, dynamic>;
      await tester.pump();
      return tester.getTopLeft(find.byType(InAppWebView)) +
          Offset((m['x'] as num).toDouble(), (m['y'] as num).toDouble());
    }

    final input = await center(_searchInput);
    if (input == null) fail('NÃO VERIFICADO: campo de busca da Meta ausente.');
    await physicalTap(tester, input);
    await physicalDelete(tester, 40);
    await physicalText(tester, name);
    await wait(tester, const Duration(seconds: 5));
    await shot(tester, '12-live-sugestao-anunciante');
    final suggestion = await center(_suggestion(name));
    if (suggestion == null) {
      debugPrint('LIVE_STEP selecionar-pagina=INCONCLUSIVO');
      fail('NÃO VERIFICADO: a Meta não sugeriu o anunciante "$name".');
    }
    await physicalTap(tester, suggestion);
    await until(
      tester,
      () => MetaAdsLibraryUrlBuilder.pageId(app.currentUrl) != null,
      'Página selecionada pela Meta',
    );
    final pageId = MetaAdsLibraryUrlBuilder.pageId(app.currentUrl)!;
    debugPrint('LIVE_STEP selecionar-pagina=APROVADO $name ($pageId)');

    // 6-7. The right Page opened and shows its own ads.
    expect(MetaAdsLibraryUrlBuilder.pageId(await currentUrl(browser)), pageId);
    final pageAds = await ads('anuncios-da-pagina');
    final text =
        await browser.controller!.evaluateJavascript(
              source: 'document.body.innerText',
            )
            as String;
    expect(
      text.contains(name),
      isTrue,
      reason: 'a Página aberta deve exibir o nome do anunciante selecionado',
    );
    debugPrint('LIVE_STEP pagina-correta=APROVADO');
    // Close the soft keyboard; while it is open the app hides its chrome.
    await browser.controller!.evaluateJavascript(
      source: 'document.activeElement && document.activeElement.blur()',
    );
    await until(
      tester,
      () => tester.view.viewInsets.bottom == 0,
      'teclado fechado',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Anúncios da Página'), findsOneWidget);
    await shot(tester, '13-live-pagina-anunciante');

    // 8-9. Open an ad's details and browse its content (visual evidence).
    final opened = await browser.controller!.evaluateJavascript(
      source: '''(() => {
        const b = [...document.querySelectorAll('div[role=button],a,span')]
          .find(e => /^(See ad details|Ver detalhes do anúncio)\$/.test((e.innerText || '').trim()));
        if (!b) return false; b.click(); return true; })()''',
    );
    await wait(tester, const Duration(seconds: 5));
    final details = await probe();
    debugPrint(
      'LIVE_STEP detalhes-anuncio=${opened == true ? 'ABERTO' : 'INCONCLUSIVO'} '
      'antes=${pageAds['len']} depois=${details['len']} '
      'videos=${details['videos']} imagens=${details['images']}',
    );
    await shot(tester, '14-live-detalhes-anuncio');
    await browser.controller!.evaluateJavascript(
      source:
          "document.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', bubbles: true}))",
    );
    await wait(tester, const Duration(seconds: 2));

    // 10. Return to the search through the WebView history.
    await tester.tap(find.widgetWithText(ActionChip, 'Pesquisa'));
    await until(
      tester,
      () => app.currentUrl.queryParameters['q'] == 'planilha',
      'retorno à pesquisa',
    );
    await ads('retorno-a-pesquisa');
    await until(tester, () => browser.canForward, 'avançar disponível');
    await shot(tester, '15-live-retorno-pesquisa');

    // 11. Back to the Page and save the identified advertiser.
    await tester.tap(find.byTooltip('Avançar'));
    await until(
      tester,
      () => MetaAdsLibraryUrlBuilder.pageId(app.currentUrl) == pageId,
      'avançar até a Página',
    );
    await dismissExternalPrompt(tester);
    await tester.tap(find.byTooltip('Salvar anunciante'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome amigável'),
      name,
    );
    await tester.tap(find.text('Salvar').last);
    await until(tester, () => app.bookmarks.isNotEmpty, 'anunciante salvo');
    expect(app.bookmarks.single.kind, BookmarkKind.advertiser);
    expect(app.bookmarks.single.pageId, pageId);
    await until(
      tester,
      () => app.bookmarks.single.metaAdCount != null,
      'contagem da Meta no anunciante',
      timeout: const Duration(seconds: 20),
    );
    // The stored count must be the one displayed on this Page.
    final shownCount = await browser.controller!.evaluateJavascript(
      source:
          r'''(() => { const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        while (w.nextNode()) { const t = (w.currentNode.nodeValue || '').trim();
          if (/^~?\s?[\d.,]+\s?[KkMm]?\s+(results|resultados)$/.test(t) && w.currentNode.parentElement.getClientRects().length) return t; }
        return ''; })()''',
    );
    final stored = app.bookmarks.single.metaAdCount!;
    expect(
      '$shownCount'.replaceAll(' ', '').startsWith(stored),
      isTrue,
      reason: 'salvo "$stored", exibido "$shownCount"',
    );
    debugPrint(
      'LIVE_STEP contagem-meta=APROVADO salvo=$stored exibido=$shownCount',
    );

    // 12-13. Reopen from Favorites; Page ID persisted.
    app.selectTab(Tabs.saved);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anunciantes'));
    await tester.pumpAndSettle();
    await shot(tester, '16-live-favoritos');
    await tester.tap(find.text(name).hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.text('Page ID $pageId'), findsOneWidget);
    final loads = browser.loadsCompleted;
    await tester.tap(find.text('Abrir na Biblioteca'));
    await tester.pumpAndSettle();
    await until(
      tester,
      () => MetaAdsLibraryUrlBuilder.pageId(app.currentUrl) == pageId,
      'reabrir Página',
    );
    // Already open: the app must not reload the same Page.
    await wait(tester, const Duration(seconds: 2));
    debugPrint('LIVE_RELOADS_ON_REOPEN=${browser.loadsCompleted - loads}');
    await ads('reabertura-favorito');
    await shot(tester, '17-live-reabertura');
    final reloaded = await LocalRepository.open(path: path);
    expect((await reloaded.bookmarks()).single.pageId, pageId);
    await reloaded.close();
    debugPrint('LIVE_STEP persistencia-page-id=APROVADO');

    // Feed mode: no app bars, Meta's pinned bars scroll with the page, one
    // floating control.
    // Close the ad details opened by an earlier step, as the user would.
    await browser.controller!.evaluateJavascript(
      source:
          '''for (const d of document.querySelectorAll('[role=dialog]')) { if (!d.getClientRects().length) continue;
        const x = [...d.querySelectorAll('[role=button]')].find((b) => /^(Fechar|Close)\$/.test((b.textContent || '').trim()));
        if (x) x.click(); }''',
    );
    await wait(tester, const Duration(seconds: 2));
    await app.updateSettings(app.settings.copyWith(viewMode: ViewMode.feed));
    await tester.pumpAndSettle();
    await wait(tester, const Duration(seconds: 3));
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byTooltip('Sair do modo feed'), findsOneWidget);
    expect(find.text('Auto-rolar'), findsNothing);
    final pins =
        jsonDecode(
              await browser.controller!.evaluateJavascript(
                    source:
                        '''JSON.stringify({unpinned: document.querySelectorAll('[data-adspocket-pin]').length,
            sticky: [...document.querySelectorAll('body *')].filter((e) => getComputedStyle(e).position === 'sticky' && e.getBoundingClientRect().width >= innerWidth * 0.9).length})''',
                  )
                  as String,
            )
            as Map<String, dynamic>;
    expect(pins['unpinned'], greaterThan(0));
    expect(pins['sticky'], 0);
    await browser.controller!.evaluateJavascript(
      source: 'window.scrollTo(0, 900)',
    );
    await until(
      tester,
      () => !browser.feedControls,
      'controle escondido ao rolar para baixo',
    );
    // Scrolling up brings it back, like a social feed.
    await browser.controller!.evaluateJavascript(
      source: 'window.scrollTo(0, 500)',
    );
    await until(tester, () => browser.feedControls, 'controle do feed');
    await tester.pumpAndSettle();
    await shot(tester, '23-live-modo-feed');
    debugPrint(
      'LIVE_STEP modo-feed=APROVADO barras-soltas=${pins['unpinned']}',
    );
    await tester.tap(find.byTooltip('Sair do modo feed'));
    await tester.pumpAndSettle();
    expect(app.settings.viewMode, ViewMode.standard);
    expect(
      await browser.controller!.evaluateJavascript(
        source: "document.querySelectorAll('[data-adspocket-pin]').length",
      ),
      0,
    );

    // Visual modes (evidence; Meta may ignore the desktop request).
    await app.updateSettings(app.settings.copyWith(viewMode: ViewMode.compact));
    await tester.pumpAndSettle();
    await shot(tester, '18-live-modo-compacto');
    final mobileWidth = (await probe())['width'];
    final desktopLoads = browser.loadsCompleted;
    await app.updateSettings(app.settings.copyWith(viewMode: ViewMode.desktop));
    await until(
      tester,
      () => browser.loadsCompleted > desktopLoads,
      'recarga desktop',
    );
    await wait(tester, const Duration(seconds: 6));
    final desktopWidth = (await probe())['width'];
    debugPrint(
      'LIVE_DESKTOP_VIEWPORT mobile=$mobileWidth desktop=$desktopWidth',
    );
    await shot(tester, '19-live-modo-desktop');
    await app.updateSettings(
      app.settings.copyWith(viewMode: ViewMode.standard),
    );
    await tester.pumpAndSettle();
    debugPrint('ADSPOCKET_LIVE_OK');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    app.dispose();
    await repo.close();
  });
}
