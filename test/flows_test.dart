import 'dart:io';
import 'dart:ui';
import 'package:ads_pocket/app/app.dart';
import 'package:ads_pocket/app/app_controller.dart';
import 'package:ads_pocket/core/longevity.dart';
import 'package:ads_pocket/core/meta_ads_library_url_builder.dart';
import 'package:ads_pocket/core/ocr_engine.dart';
import 'package:ads_pocket/data/local_repository.dart';
import 'package:ads_pocket/data/models.dart';
import 'package:ads_pocket/data/offer.dart';
import 'package:ads_pocket/features/browser/browser_screen.dart';
import 'package:ads_pocket/features/browser/library_assistant.dart';
import 'package:ads_pocket/features/favorites/bookmark_editor.dart';
import 'package:ads_pocket/features/mining/ocr_screen.dart';
import 'package:ads_pocket/features/mining/review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final search = MetaAdsLibraryUrlBuilder().build(text: 'planilha');
final page = MetaAdsLibraryUrlBuilder().build(
  text: '20531316728',
  type: SearchType.pageId,
);

class FakeOcr implements OcrEngine {
  FakeOcr(this.lines);
  final List<OcrLine> lines;
  @override
  Future<List<OcrLine>> recognize(String path) async => lines;
}

/// Lets real SQLite I/O finish inside the fake-async test zone.
Future<void> settle(WidgetTester tester, [int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

Offer offer(String name, {CivilDate? start, int? price}) => Offer(
  id: localId(),
  name: name,
  createdAt: DateTime.utc(2026, 10),
  updatedAt: DateTime.utc(2026, 10),
  startDate: start,
  dateSource: start == null ? null : DateSource.manual,
  priceCents: price,
  priceSource: price == null ? PriceSource.unknown : PriceSource.informed,
);

void main() {
  sqfliteFfiInit();
  late AppController app;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final repo = await LocalRepository.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    app = AppController(repo, await SharedPreferences.getInstance());
    await app.initialize();
  });
  tearDown(() async {
    app.dispose();
    await app.repository.close();
  });

  Future<void> host(WidgetTester tester, Widget Function(BuildContext) body) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Builder(builder: body)),
        ),
      );

  Future<void> tapSave(WidgetTester tester, Uri uri) async {
    await host(
      tester,
      (context) => TextButton(
        onPressed: () => saveCurrentReference(context, app, uri),
        child: const Text('Salvar referência'),
      ),
    );
    await tester.tap(find.text('Salvar referência'));
    await tester.pumpAndSettle();
  }

  testWidgets('URL with Page ID opens the identified advertiser form', (
    tester,
  ) async {
    await tapSave(tester, page);
    expect(find.text('Salvar anunciante'), findsOneWidget);
    expect(
      find.text('Anunciante identificado · Page ID 20531316728'),
      findsOneWidget,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome amigável'),
      'Meta',
    );
    await tester.tap(find.text('Salvar'));
    await settle(tester);
    final b = app.bookmarks.single;
    expect(b.kind, BookmarkKind.advertiser);
    expect(b.pageId, '20531316728');
    expect(b.url, page.toString());
    expect(b.lastVisitedAt, isNotNull);
  });

  testWidgets('search URL never becomes an advertiser silently', (
    tester,
  ) async {
    await tapSave(tester, search);
    expect(
      find.text('Não foi possível identificar uma Página nesta URL.'),
      findsOneWidget,
    );
    for (final option in [
      'Salvar como pesquisa',
      'Salvar como referência não identificada',
      'Informar Page ID manualmente',
      'Cancelar',
    ]) {
      expect(find.text(option), findsOneWidget);
    }
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(app.bookmarks, isEmpty);

    await tester.tap(find.text('Salvar referência'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar como pesquisa'));
    await tester.pumpAndSettle();
    expect(find.text('Salvar pesquisa'), findsOneWidget);
    await tester.tap(find.text('Salvar'));
    await settle(tester);
    expect(app.bookmarks.single.kind, BookmarkKind.search);
    expect(app.bookmarks.single.pageId, isNull);

    await tester.tap(find.text('Salvar referência'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar como referência não identificada'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await settle(tester);
    expect(app.bookmarks.map((b) => b.kind).toSet(), {
      BookmarkKind.search,
      BookmarkKind.unidentified,
    });
  });

  testWidgets('manual Page ID is validated and explicitly confirmed', (
    tester,
  ) async {
    await tapSave(tester, search);
    await tester.tap(find.text('Informar Page ID manualmente'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Use apenas números.'), findsOneWidget);
    // The digits-only formatter drops letters, leaving 123.
    await tester.enterText(find.byType(TextFormField), '12a3');
    await tester.tap(find.text('Continuar'));
    await settle(tester, 3);
    expect(find.text('Usar o Page ID 123?'), findsOneWidget);
    expect(find.textContaining('não verifica a quem este ID'), findsOneWidget);
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome amigável'),
      'Página informada',
    );
    await tester.tap(find.text('Salvar'));
    await settle(tester);
    final b = app.bookmarks.single;
    expect(b.kind, BookmarkKind.advertiser);
    expect(b.pageId, '123');
    expect(b.sourceUrl, search.toString());
    expect(b.url, contains('view_all_page_id=123'));
    expect(b.url, contains('country=BR'));
  });

  testWidgets('Salvos: ads, counter, price chip and sections', (tester) async {
    await tester.pumpWidget(AdsPocketApp(controller: app, enableNative: false));
    app.selectTab(Tabs.saved);
    await tester.pumpAndSettle();
    expect(find.text('Nenhum anúncio salvo'), findsOneWidget);
    expect(find.text('0 de 0 anúncios · filtro local'), findsOneWidget);
    expect(find.text('Qualquer idade'), findsOneWidget);

    final today = CivilDate.today();
    await tester.runAsync(() async {
      await app.saveOffer(
        offer('Antiga', start: today.addDays(-40), price: 1990),
      );
      await app.saveOffer(offer('Nova', start: today.addDays(-3), price: 4700));
      await app.saveOffer(offer('Sem data'));
    });
    await tester.pumpAndSettle();
    expect(find.text('3 de 3 anúncios · filtro local'), findsOneWidget);
    expect(find.text('Anúncios · 3'), findsOneWidget);
    expect(find.text('40 dias'), findsOneWidget);

    await tester.tap(find.text('Preço'));
    await tester.pumpAndSettle();
    expect(find.text('2 de 3 anúncios · filtro local'), findsOneWidget);
    await tester.tap(find.text('Limpar'));
    await tester.pumpAndSettle();
    expect(find.text('3 de 3 anúncios · filtro local'), findsOneWidget);

    await tester.tap(find.text('Anunciantes'));
    await tester.pumpAndSettle();
    expect(
      find.text('Um lugar para suas descobertas').hitTestable(),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('one tap on a card saves a complete ad; comment is optional', (
    tester,
  ) async {
    await tester.pumpWidget(AdsPocketApp(controller: app, enableNative: false));
    await tester.runAsync(() => app.openLibrary(search));
    await tester.pumpAndSettle();
    final browser = tester.state<BrowserScreenState>(
      find.byType(BrowserScreen),
    );
    final card = LibraryCard.fromJson({
      'id': '1175443257960186',
      'start': 'Started running on Jul 8, 2025',
      'active': true,
      'advertiser': 'Sólides Educação',
      'text': 'Planilha gratuita de escalas',
      'cta': 'https://solides.com.br/',
    })!;
    browser.cards[card.id] = card;
    await tester.runAsync(() => browser.saveCard(card.id));
    await tester.pumpAndSettle();
    final o = app.offers.single;
    expect(o.adId, card.id);
    expect(o.startDate, CivilDate.of(2025, 7, 8));
    expect(o.dateSource, DateSource.library);
    expect(o.status, AdStatus.active);
    expect(o.advertiser, 'Sólides Educação');
    expect(o.salesUrl, 'https://solides.com.br/');
    expect(find.textContaining('Anúncio salvo · '), findsOneWidget);

    await tester.tap(find.text('Comentar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Oferta forte');
    await tester.tap(find.text('Salvar'));
    // The dialog waits for its close animation before saving (real I/O).
    await settle(tester, 14);
    expect(app.offers.single.notes, 'Oferta forte');

    await tester.runAsync(() => browser.saveCard(card.id));
    await tester.pumpAndSettle();
    expect(app.offers, hasLength(1), reason: 'sem duplicar');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('assistant bar: custom days, ads count, auto-scroll, toggle', (
    tester,
  ) async {
    await tester.pumpWidget(AdsPocketApp(controller: app, enableNative: false));
    await tester.runAsync(() => app.openLibrary(search));
    await tester.pumpAndSettle();
    expect(find.text('14+ dias'), findsOneWidget);
    expect(find.text('Qualquer qtd.'), findsOneWidget);
    expect(find.text('Só ativos'), findsNothing, reason: 'ativos é o padrão');
    expect(find.text('Auto-rolar'), findsOneWidget);
    expect(find.text('Assistente pronto'), findsOneWidget);
    expect(search.queryParameters['active_status'], 'active');

    await tester.tap(find.text('14+ dias'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ativos há 60+ dias').last);
    await settle(tester, 3);
    expect(app.settings.minDays, 60);

    // Any number of days, not only presets.
    await tester.tap(find.text('60+ dias'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personalizado…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '400');
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(find.text('Use um número de 0 a 365.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '45');
    await tester.tap(find.text('Aplicar'));
    await settle(tester, 8);
    expect(app.settings.minDays, 45);
    expect(find.text('45+ dias'), findsOneWidget);

    await tester.tap(find.text('Qualquer qtd.'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5+ anúncios ativos').last);
    await settle(tester, 3);
    expect(app.settings.minAds, 5);
    expect(find.text('5+ anúncios'), findsOneWidget);
    await tester.tap(find.text('5+ anúncios'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personalizado…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '8');
    await tester.tap(find.text('Aplicar'));
    await settle(tester, 8);
    expect(app.settings.minAds, 8);

    await tester.runAsync(
      () => app.updateSettings(app.settings.copyWith(assistant: false)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Auto-rolar'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('feed mode: only the page and one floating control', (
    tester,
  ) async {
    await tester.pumpWidget(AdsPocketApp(controller: app, enableNative: false));
    await tester.runAsync(() => app.openLibrary(search));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.tap(find.byTooltip('Mais opções'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Feed').first);
    await settle(tester, 4);
    expect(app.settings.viewMode, ViewMode.feed);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('Auto-rolar'), findsNothing);
    expect(find.byTooltip('Mais opções'), findsNothing);
    expect(find.byTooltip('Sair do modo feed'), findsOneWidget);

    // Filters stay one tap away.
    await tester.tap(find.byTooltip('Filtros e opções'));
    await tester.pumpAndSettle();
    expect(find.text('Ativos há 14+ dias'), findsOneWidget);
    expect(find.text('Qualquer quantidade'), findsOneWidget);
    await tester.tap(find.text('Sair do modo feed').last);
    await settle(tester, 4);
    expect(app.settings.viewMode, ViewMode.standard);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Auto-rolar'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Explore pills set media and age before the search', (
    tester,
  ) async {
    await tester.pumpWidget(AdsPocketApp(controller: app, enableNative: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filtros de pesquisa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Todas as mídias'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vídeo').last);
    await settle(tester, 3);
    expect(app.settings.media, 'video');
    await tester.tap(find.text('Ativos há 14+ dias'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ativos há 30+ dias').last);
    await settle(tester, 3);
    expect(app.settings.minDays, 30);
    await tester.enterText(find.byType(TextField).first, 'ebook');
    await tester.ensureVisible(find.text('Explorar anúncios'));
    await tester.tap(find.text('Explorar anúncios'));
    for (var i = 0; i < 50 && app.tab != Tabs.library; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(app.currentUrl.queryParameters['media_type'], 'video');
    expect(app.currentUrl.queryParameters['q'], 'ebook');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('quick review classifies, advances and undoes', (tester) async {
    final a = offer('Oferta A'), b = offer('Oferta B');
    await tester.runAsync(() async {
      await app.saveOffer(a);
      await app.saveOffer(b);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewScreen(app: app, ids: [a.id, b.id]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 de 2'), findsOneWidget);
    await tester.tap(find.text('Interessante'));
    await settle(tester);
    expect(
      app.offers.firstWhere((o) => o.id == a.id).analysis,
      Analysis.interesting,
    );
    expect(find.text('2 de 2'), findsOneWidget);
    await tester.tap(find.text('Desfazer'));
    await settle(tester);
    expect(
      app.offers.firstWhere((o) => o.id == a.id).analysis,
      Analysis.notAnalyzed,
    );
    expect(find.text('1 de 2'), findsOneWidget);
    await tester.tap(find.text('Descartar'));
    await settle(tester);
    await tester.tap(find.text('Observar'));
    await settle(tester);
    expect(find.text('Tudo revisado'), findsOneWidget);
    expect(
      app.offers.firstWhere((o) => o.id == b.id).analysis,
      Analysis.watching,
    );
  });

  testWidgets('OCR with several ads requires an explicit choice', (
    tester,
  ) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('adspocket-ocr-'),
    );
    final path = '${dir!.path}/print.png';
    await tester.runAsync(() async {
      final recorder = PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 400, 80),
        Paint()..color = const Color(0xFFFFFFFF),
      );
      final image = await recorder.endRecording().toImage(400, 80);
      final png = await image.toByteData(format: ImageByteFormat.png);
      await File(path).writeAsBytes(png!.buffer.asUint8List());
    });
    app.ocr = FakeOcr(const [
      OcrLine('Iniciado em 12 de outubro de 2026', Rect.fromLTWH(0, 0, 400, 5)),
      OcrLine(
        'Iniciado em 3 de setembro de 2026',
        Rect.fromLTWH(0, 60, 400, 5),
      ),
      OcrLine('R\$ 19,90', Rect.fromLTWH(0, 70, 400, 5)),
    ]);
    OcrResult? result;
    await host(
      tester,
      (context) => TextButton(
        onPressed: () async => result = await Navigator.push<OcrResult>(
          context,
          MaterialPageRoute(
            builder: (_) => OcrScreen(app: app, path: path),
          ),
        ),
        child: const Text('abrir'),
      ),
    );
    await tester.tap(find.text('abrir'));
    await settle(tester);
    expect(find.textContaining('Há 2 datas de início'), findsOneWidget);
    final button = find.widgetWithText(FilledButton, 'Continuar sem data');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.tap(find.textContaining('12/10/2026'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('R\$ 19,90'),
      120,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('R\$ 19,90'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar e catalogar'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmar data de início?'), findsOneWidget);
    expect(find.textContaining('mais de um anúncio'), findsOneWidget);
    await tester.tap(find.text('Usar esta data'));
    await tester.pumpAndSettle();
    expect(result?.date, CivilDate.of(2026, 10, 12));
    expect(result?.price?.cents, 1990);
    expect(result?.text, contains('Iniciado em 3 de setembro'));
    await tester.runAsync(() => dir.delete(recursive: true));
  });

  testWidgets('immersive mode hides app navigation only in the Library', (
    tester,
  ) async {
    await tester.pumpWidget(AdsPocketApp(controller: app, enableNative: false));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.runAsync(() => app.setImmersive(true));
    app.selectTab(Tabs.library);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byTooltip('Voltar à pesquisa'), findsOneWidget);
    expect(find.byTooltip('Mais opções'), findsOneWidget);
    app.selectTab(Tabs.explore);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('toolbar keeps six actions; compact hides the header', (
    tester,
  ) async {
    await tester.pumpWidget(AdsPocketApp(controller: app, enableNative: false));
    await tester.runAsync(() => app.openLibrary(page));
    await tester.pumpAndSettle();
    for (final tip in [
      'Voltar',
      'Avançar',
      'Atualizar',
      'Voltar à pesquisa',
      'Salvar anunciante',
      'Mais opções',
    ]) {
      expect(find.byTooltip(tip), findsOneWidget, reason: tip);
    }
    expect(find.textContaining('Anúncios da Página'), findsOneWidget);
    await tester.runAsync(
      () =>
          app.updateSettings(app.settings.copyWith(viewMode: ViewMode.compact)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Anúncios da Página'), findsNothing);
    expect(find.byTooltip('Salvar anunciante'), findsOneWidget);
    await tester.tap(find.byTooltip('Mais opções'));
    await tester.pumpAndSettle();
    expect(find.text('Catalogar na Mineração'), findsOneWidget);
    expect(find.text('Analisar área visível'), findsOneWidget);
    expect(find.text('Modo imersivo'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final (theme, scale, width) in [
    ('dark', 1.0, 360.0),
    ('light', 1.0, 320.0),
    ('light', 2.0, 360.0),
    ('dark', 1.6, 320.0),
  ]) {
    testWidgets('all tabs render: $theme, text ${scale}x, ${width}dp', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        await app.updateSettings(app.settings.copyWith(theme: theme));
        await app.saveOffer(
          offer('Uma oferta com nome comprido para tela estreita', price: 990),
        );
        await app.save(
          Bookmark(
            id: localId(),
            name: 'Anunciante identificado com nome longo',
            kind: BookmarkKind.advertiser,
            url: page.toString(),
            country: 'BR',
            addedAt: DateTime.utc(2026),
            pageId: '20531316728',
            tags: ['finanças', 'planilha'],
          ),
        );
      });
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(
            size: Size(width, 780),
            textScaler: TextScaler.linear(scale),
          ),
          child: AdsPocketApp(controller: app, enableNative: false),
        ),
      );
      for (final tab in [
        Tabs.explore,
        Tabs.library,
        Tabs.saved,
        Tabs.settings,
      ]) {
        app.selectTab(tab);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'tab $tab');
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
