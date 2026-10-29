import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ads_pocket/app/app.dart';
import 'package:ads_pocket/app/app_controller.dart';
import 'package:ads_pocket/data/local_repository.dart';
import 'package:ads_pocket/features/history/history_screen.dart';
import 'package:ads_pocket/core/meta_ads_library_url_builder.dart';

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
  testWidgets(
    'Explore is native and search stores real query and opens Library',
    (tester) async {
      await tester.pumpWidget(
        AdsPocketApp(controller: app, enableNative: false),
      );
      await tester.pumpAndSettle();
      expect(find.text('AdsPocket'), findsOneWidget);
      expect(find.text('Explorar anúncios'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField).first,
        'planilha financeira',
      );
      await tester.ensureVisible(find.text('Explorar anúncios'));
      await tester.tap(find.text('Explorar anúncios'));
      // SQLite FFI runs real I/O: wait for the condition, not a fixed delay.
      for (var i = 0; i < 50 && app.tab != Tabs.library; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(app.history.single.query, 'planilha financeira');
      expect(app.currentUrl.queryParameters['q'], 'planilha financeira');
      expect(find.text('Biblioteca no Android'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Favorites empty state and settings persist across tabs', (
    tester,
  ) async {
    await tester.pumpWidget(AdsPocketApp(controller: app, enableNative: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvos'));
    await tester.pumpAndSettle();
    expect(app.tab, Tabs.saved);
    expect(find.text('Nenhum anúncio salvo'), findsOneWidget);
    await tester.tap(find.text('Ajustes'));
    await tester.pumpAndSettle();
    expect(app.tab, Tabs.settings);
    expect(find.text('Retomar a última pesquisa'), findsOneWidget);
    await tester.runAsync(
      () => app.updateSettings(app.settings.copyWith(theme: 'light')),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
    await tester.tap(find.text('Explorar'));
    await tester.pumpAndSettle();
    expect(find.text('AdsPocket'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('narrow screen with enlarged text has no layout exception', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
        child: AdsPocketApp(controller: app, enableNative: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('history displays persisted search and filters without network', (
    tester,
  ) async {
    await tester.runAsync(
      () => app.search('planilha', SearchType.keyword, 'BR', 'active'),
    );
    await tester.pumpWidget(MaterialApp(home: HistoryScreen(app: app)));
    await tester.pumpAndSettle();
    expect(find.text('planilha'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'não existe');
    await tester.pumpAndSettle();
    expect(find.text('Nenhuma pesquisa encontrada'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
