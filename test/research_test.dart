import 'dart:convert';
import 'dart:io';
import 'package:ads_pocket/app/app.dart';
import 'package:ads_pocket/app/app_controller.dart';
import 'package:ads_pocket/core/pocket_grid.dart';
import 'package:ads_pocket/core/pocket_icon.dart';
import 'package:ads_pocket/data/backup_service.dart';
import 'package:ads_pocket/data/local_repository.dart';
import 'package:ads_pocket/data/models.dart';
import 'package:ads_pocket/data/offer.dart';
import 'package:ads_pocket/features/research/research_engine.dart';
import 'package:ads_pocket/features/research/research_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

ResearchRecord record(
  ResearchKind kind, {
  Map<String, dynamic> data = const {},
}) => ResearchRecord(
  id: localId(),
  name: 'Pesquisa de teste',
  kind: kind,
  createdAt: DateTime.utc(2026, 10, 29),
  data: data,
);
Offer offer(String name, String url) => Offer(
  id: localId(),
  name: name,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  salesUrl: url,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late LocalRepository repo;
  late AppController app;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repo = await LocalRepository.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    app = AppController(repo, await SharedPreferences.getInstance());
    await app.initialize();
  });
  tearDown(() async {
    app.dispose();
    await repo.close();
  });
  test(
    'catalog imports supplied transcription with provenance, not imaginary PDF pages',
    () async {
      final c = await ResearchCatalog.load();
      expect(c.niches, hasLength(8));
      expect(c.terms, hasLength(449));
      expect(c.presets, hasLength(10));
      expect(
        c.presets.singleWhere(
          (p) => p['name'] == 'Ofertas com 30+ dias',
        )['minDays'],
        '30',
      );
      expect(c.find('PLANILHA PRONTA'), isNotEmpty);
      expect(c.find('Disfuncao eretil'), isNotEmpty);
      for (final term in c.terms) {
        expect(term['sourceId'], isNotEmpty);
        expect(term['page'], isNull);
        expect(term['importedAt'], '2026-10-29');
      }
      expect(c.terms.where((t) => t['historical'] == true), isNotEmpty);
      expect(
        c.terms.where((t) => t['sourceId'] == 'system-expansion'),
        hasLength(14),
      );
    },
  );
  test(
    'keyword engine limits ranks deduplicates and excludes without mass queries',
    () {
      final engine = KeywordMiningEngine();
      final q = engine.generate(
        niche: 'Finanças pessoais',
        subniche: 'Controle de gastos',
        format: 'Planilha pronta',
        commercial: 'R\$ 9,90',
        limit: 4,
      );
      expect(q, hasLength(4));
      expect(q.first, 'Planilha pronta Controle de gastos');
      final expanded = engine.generate(
        niche: 'Finanças',
        format: 'Planilha',
        benefit: 'organização',
        delivery: 'Entrega imediata',
        update: 'Versão atualizada',
        variants: ['Excel pronto'],
        limit: 30,
      );
      expect(
        expanded,
        containsAll([
          'Planilha organização',
          'Planilha Entrega imediata',
          'Planilha Versão atualizada',
          'Excel pronto Finanças',
        ]),
      );
      expect(researchKey('Ｒ＄9,90'), researchKey(r'R$ 9,90'));
      expect(researchKey('Finanças'), researchKey('Finanças'));
      expect(
        engine
            .generate(niche: 'Planilha pronta', format: 'Planilha pronta')
            .map(researchKey)
            .toSet()
            .length,
        engine
            .generate(niche: 'Planilha pronta', format: 'Planilha pronta')
            .length,
      );
      expect(
        engine
            .generate(
              niche: 'Finanças',
              format: 'Planilha',
              excluded: ['planilha'],
            )
            .every((s) => !researchKey(s).contains('planilha')),
        isTrue,
      );
      expect(
        () => engine.generate(niche: 'x', limit: 999),
        throwsFormatException,
      );
    },
  );
  test('checkout matches exact verified hosts and rejects deceptive domains', () {
    final detector = PublicTechnologyDetector();
    for (final host in PublicTechnologyDetector.checkouts.keys) {
      expect(
        detector.detect('https://$host/produto').single.confidence,
        'Confirmado (domínio)',
      );
    }
    expect(
      detector.detect('https://pay.kiwify.com.br.evil.example/produto'),
      isEmpty,
    );
    expect(() => detector.detect('javascript:alert(1)'), throwsFormatException);
    expect(
      () => detector.detect('https://example.com', publicText: 'x' * 500001),
      throwsFormatException,
    );
    expect(
      detector
          .detect(
            'https://example.com',
            publicText:
                '<script src="https://www.googletagmanager.com/gtm.js?id=GTM-EXAMPLE"></script>',
          )
          .single
          .confidence,
      contains('Provável'),
    );
  });
  test('grouping never merges different products on a shared checkout', () {
    final a = offer('Referência A', 'https://pay.kiwify.com.br/produto-a');
    final b = offer('Referência B', 'https://pay.kiwify.com.br/produto-b');
    expect(OfferGroup.group([a, b]), isEmpty);
    expect(
      OfferGroup.group([
        a,
        offer('Outra referência A', a.salesUrl!),
      ]).single.offers,
      hasLength(2),
    );
    expect(
      OfferGroup.group([
        offer('A', 'https://pay.hotmart.com/P?off=a'),
        offer('B', 'https://pay.hotmart.com/P?off=b'),
      ]),
      isEmpty,
    );
  });
  test(
    'records persist edit duplicate delete and round-trip in backup v3',
    () async {
      final r = record(
        ResearchKind.package,
        data: {
          'queries': ['planilha'],
          'sourceId': 'meta',
          'country': 'BR',
        },
      );
      await app.saveResearch(r);
      expect(app.research.single.id, r.id);
      await app.saveResearch(
        ResearchRecord(
          id: r.id,
          name: 'Editado',
          kind: r.kind,
          createdAt: r.createdAt,
          data: r.data,
        ),
      );
      await app.saveResearch(r.duplicate());
      expect(app.research, hasLength(2));
      final backup = BackupService.decode(app.exportBackup());
      expect(backup.research, hasLength(2));
      expect(await app.importBackup(backup), 0);
      expect(app.research, hasLength(2));
      await app.deleteResearch(r.id);
      expect(app.research, hasLength(1));
    },
  );
  test(
    'unsafe backup and malformed lists fail before any database changes',
    () async {
      final original = record(ResearchKind.dossier);
      await app.saveResearch(original);
      for (final data in [
        {'sourceUrl': 'javascript:alert(1)'},
        {
          'queries': [42],
        },
        {'country': 'INVALID'},
        {'sourceId': 'fake-api'},
        {'minDays': 'abc'},
      ]) {
        final r = record(ResearchKind.package, data: data);
        expect(r.validate, throwsFormatException);
      }
      final json = jsonDecode(app.exportBackup()) as Map<String, dynamic>;
      json['research'][0]['data'] = {'sourceUrl': 'http://example.com'};
      expect(
        () => BackupService.decode(jsonEncode(json)),
        throwsFormatException,
      );
      expect(app.research.single.id, original.id);
    },
  );
  test(
    'v2 database migrates without dropping existing tables or records',
    () async {
      final dir = await Directory.systemTemp.createTemp('adspocket-research-');
      final path = '${dir.path}/db';
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, _) async {
            await LocalRepository.createV1(db);
            await db.execute(
              'CREATE TABLE offers (id TEXT PRIMARY KEY, identity TEXT UNIQUE, updated_at TEXT NOT NULL, data TEXT NOT NULL)',
            );
            await db.execute(
              'CREATE TABLE visits (id INTEGER PRIMARY KEY, bookmark_id TEXT, visited_at TEXT)',
            );
            await db.insert('visits', {
              'id': 1,
              'bookmark_id': 'kept',
              'visited_at': '2026-10-29',
            });
          },
        ),
      );
      await old.close();
      final migrated = await LocalRepository.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      expect((await migrated.db.query('visits')).single['bookmark_id'], 'kept');
      await migrated.saveResearch(record(ResearchKind.dossier));
      await migrated.close();
      final reopened = await LocalRepository.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      expect(await reopened.research(), hasLength(1));
      await reopened.close();
      await dir.delete(recursive: true);
    },
  );
  testWidgets('home hides advanced filters and exposes original icon grid', (
    tester,
  ) async {
    await tester.pumpWidget(AdsPocketApp(controller: app, enableNative: false));
    await tester.pumpAndSettle();
    expect(find.byType(PocketIcon), findsWidgets);
    expect(find.byType(PocketGrid), findsWidgets);
    expect(find.text('Todas as mídias'), findsNothing);
    await tester.tap(find.text('Filtros de pesquisa'));
    await tester.pumpAndSettle();
    expect(find.text('Todas as mídias'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('builder generates and persists an editable research package', (
    tester,
  ) async {
    final catalog = (await tester.runAsync(ResearchCatalog.load))!;
    await tester.pumpWidget(
      MaterialApp(
        home: MiningBuilder(
          app: app,
          catalog: catalog,
          initial: const {
            'niche': 'Finanças Pessoais',
            'subniche': 'Controle de gastos',
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Gerar sugestões'));
    await tester.tap(find.text('Gerar sugestões'));
    await tester.pumpAndSettle();
    expect(find.text('Planilha pronta Controle de gastos'), findsOneWidget);
    await tester.tap(find.byTooltip('Salvar pacote'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar').last);
    for (var i = 0; i < 20 && app.research.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(app.research.single.kind, ResearchKind.package);
    expect(app.research.single.data['queries'], isNotEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  for (final width in [320.0, 411.0, 760.0]) {
    testWidgets('research hub has no overflow at $width dp with large type', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.8)),
            child: child!,
          ),
          home: ResearchScreen(app: app),
        ),
      );
      for (var i = 0; i < 15; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Construir pesquisa'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
