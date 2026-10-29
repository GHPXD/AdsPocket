import 'package:ads_pocket/app/app.dart';
import 'package:ads_pocket/app/app_controller.dart';
import 'package:ads_pocket/core/pocket_icon.dart';
import 'package:ads_pocket/data/backup_service.dart';
import 'package:ads_pocket/data/local_repository.dart';
import 'package:ads_pocket/data/models.dart';
import 'package:ads_pocket/features/browser/library_assistant.dart';
import 'package:ads_pocket/features/research/research_engine.dart';
import 'package:ads_pocket/features/research/research_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'support.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android: redesign, packages, evidence and restart', (
    tester,
  ) async {
    // Isolated database and in-memory preferences; never clear personal data.
    SharedPreferences.setMockInitialValues({});
    final path = '${await getDatabasesPath()}/research-qa-${localId()}.db';
    var repo = await LocalRepository.open(path: path);
    var app = AppController(repo, await SharedPreferences.getInstance());
    await app.initialize();
    await tester.pumpWidget(AdsPocketApp(controller: app, enableNative: false));
    await tester.pumpAndSettle();
    expect(find.byType(PocketIcon), findsWidgets);
    expect(find.text('Todas as mídias'), findsNothing);
    await shot(tester, '120-explorar-escuro');

    await app.updateSettings(app.settings.copyWith(theme: 'light'));
    await tester.pumpAndSettle();
    await shot(tester, '120-explorar-claro');
    await app.updateSettings(app.settings.copyWith(theme: 'dark'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Pesquisa 360°'));
    await tester.tap(find.text('Pesquisa 360°'));
    await until(
      tester,
      () => find.text('Construir pesquisa').evaluate().isNotEmpty,
      'base local carregada',
    );
    await tester.pumpAndSettle();
    await shot(tester, '120-pesquisa-360');
    await tester.tap(find.text('Construir pesquisa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sem preferência').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finanças Pessoais').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sem preferência').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Controle de gastos').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gerar sugestões'));
    await tester.pumpAndSettle();
    expect(find.text('Planilha pronta Controle de gastos'), findsOneWidget);
    await shot(tester, '120-construtor');
    await tester.tap(find.byTooltip('Salvar pacote'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar').last);
    await until(tester, () => app.research.isNotEmpty, 'pacote persistido');
    expect(app.research.single.kind, ResearchKind.package);

    final navigator = Navigator.of(tester.element(find.byType(MiningBuilder)));
    navigator.pop();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Detectar tecnologias'));
    await tester.tap(find.text('Detectar tecnologias'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'https://pay.kiwify.com.br/referencia-qa',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verificar evidências'));
    await tester.pumpAndSettle();
    expect(find.text('Kiwify'), findsOneWidget);
    await shot(tester, '120-detector');
    await tester.tap(find.byTooltip('Salvar evidência'));
    await until(tester, () => app.research.length == 2, 'evidência persistida');
    expect(BackupService.decode(app.exportBackup()).research, hasLength(2));

    await tester.pumpWidget(const SizedBox());
    app.dispose();
    await repo.close();
    repo = await LocalRepository.open(path: path);
    app = AppController(repo, await SharedPreferences.getInstance());
    await app.initialize();
    expect(app.research, hasLength(2));
    app.dispose();
    await repo.close();
    await deleteDatabase(path); // This test's uniquely named database only.
  });

  testWidgets('Android WebView: missing dates and counts stay unknown', (
    tester,
  ) async {
    InAppWebViewController? web;
    final cards = <LibraryCard>[];
    var loaded = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InAppWebView(
            initialData: InAppWebViewInitialData(
              baseUrl: WebUri('https://www.facebook.com/ads/library/'),
              data: '''<!doctype html><html><body>
          <article id="unknown"><div>Library ID: 111111</div><div>Ativo</div><div>QA</div><div>Patrocinado</div><div>Referência sem data e quantidade</div></article>
          <article id="known"><div>Library ID: 222222</div><div>Ativo</div><div>QA</div><div>Patrocinado</div><div>3 anúncios usam esse criativo e esse texto</div></article>
          </body></html>''',
            ),
            onWebViewCreated: (controller) {
              web = controller;
              controller.addJavaScriptHandler(
                handlerName: 'adspocket',
                callback: (args) {
                  if (args.isNotEmpty) {
                    cards.addAll(
                      parseAssistantMessage(args.first)?.cards ?? [],
                    );
                  }
                },
              );
            },
            onLoadStop: (_, _) => loaded = true,
          ),
        ),
      ),
    );
    await until(tester, () => loaded && web != null, 'WebView de fixture');
    await web!.evaluateJavascript(source: assistantScript);
    await until(tester, () => cards.length == 2, 'cards de fixture');
    expect(cards.first.start, isNull);
    expect(cards.first.variations, isNull);
    await web!.evaluateJavascript(
      source: assistantApply(
        ages: const {'111111': null, '222222': null},
        saved: {},
        minDays: 30,
        includeUndated: true,
        minAds: 1,
      ),
    );
    expect(
      await web!.evaluateJavascript(
        source: "document.getElementById('unknown').style.display",
      ),
      'none',
    );
    expect(
      await web!.evaluateJavascript(
        source: "document.getElementById('known').style.display",
      ),
      '',
    );
    await web!.evaluateJavascript(
      source: assistantApply(
        ages: const {'111111': null, '222222': null},
        saved: {},
        minDays: 30,
        includeUndated: false,
        minAds: null,
      ),
    );
    expect(
      await web!.evaluateJavascript(
        source: "document.getElementById('known').style.display",
      ),
      'none',
    );
    await web!.evaluateJavascript(
      source: assistantApply(
        ages: const {'111111': null, '222222': null},
        saved: {},
        minDays: null,
        includeUndated: true,
        minAds: null,
      ),
    );
    expect(
      await web!.evaluateJavascript(
        source: "document.getElementById('unknown').style.display",
      ),
      '',
    );
    await tester.pumpWidget(const SizedBox());
  });
}
