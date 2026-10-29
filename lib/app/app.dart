import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../core/meta_ads_library_url_builder.dart';
import '../core/native_bridge.dart';
import '../core/widgets.dart';
import '../core/pocket_icon.dart';
import '../data/models.dart';
import '../features/browser/browser_screen.dart';
import '../features/explore/explore_screen.dart';
import '../features/favorites/bookmark_editor.dart';
import '../features/mining/ocr_screen.dart';
import '../features/saved/saved_screen.dart';
import '../features/settings/settings_screen.dart';
import 'app_controller.dart';
import 'theme.dart';

class AdsPocketApp extends StatelessWidget {
  const AdsPocketApp({
    super.key,
    required this.controller,
    this.enableNative = true,
  });
  final AppController controller;
  final bool enableNative;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => MaterialApp(
      title: 'AdsPocket',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: switch (controller.settings.theme) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      },
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: AppShell(app: controller, enableNative: enableNative),
    ),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.app, required this.enableNative});
  final AppController app;
  final bool enableNative;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  final browserKey = GlobalKey<BrowserScreenState>();
  bool handlingShares = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.enableNative) {
      NativeBridge.channel.setMethodCallHandler((call) async {
        if (call.method == 'sharesChanged') await _shares();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _shares());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.enableNative) NativeBridge.channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.enableNative) {
      unawaited(_shares());
    }
  }

  Future<void> _shares() async {
    if (handlingShares || !mounted) return;
    handlingShares = true;
    try {
      while (mounted) {
        final shares = await NativeBridge.pendingShares();
        if (shares.isEmpty) break;
        for (final text in shares) {
          if (!mounted) return;
          if (text.startsWith('image:')) {
            final file = text.substring(6);
            if (await NativeBridge.imagePath(file) == null || !mounted) {
              continue;
            }
            final choice = await showDialog<String>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Imagem recebida'),
                content: const Text(
                  'Analise o print no aparelho para encontrar a data de início, ou guarde a imagem nos favoritos.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, 'save'),
                    child: const Text('Salvar imagem'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, 'ocr'),
                    child: const Text('Analisar imagem'),
                  ),
                ],
              ),
            );
            if (!mounted) return;
            if (choice == 'ocr') {
              widget.app.selectTab(Tabs.saved);
              await analyzeImage(context, widget.app, file);
            } else if (choice == 'save') {
              await editBookmark(
                context,
                widget.app,
                kind: BookmarkKind.image,
                localFile: file,
                suggestedName: 'Imagem compartilhada',
              );
            } else {
              await NativeBridge.deleteImage(file);
            }
            continue;
          }
          final links = MetaAdsLibraryUrlBuilder.sharedLinks(text);
          if (links.isEmpty) {
            widget.app.showNotice(
              'Nenhum link HTTPS compatível da Biblioteca foi encontrado.',
            );
            continue;
          }
          for (final uri in links) {
            if (!mounted) return;
            final choice = await showDialog<String>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Recebido no AdsPocket'),
                content: SingleChildScrollView(
                  child: SelectableText(uri.toString()),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, 'copy'),
                    child: const Text('Copiar'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, 'save'),
                    child: const Text('Salvar favorito'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, 'open'),
                    child: const Text('Abrir agora'),
                  ),
                ],
              ),
            );
            if (!mounted) return;
            if (choice == 'open') await widget.app.openLibrary(uri);
            if (choice == 'copy' && mounted) {
              await copyLink(context, uri.toString());
            }
            if (choice == 'save' && mounted) {
              await saveCurrentReference(context, widget.app, uri);
            }
          }
        }
      }
    } catch (_) {
      widget.app.showNotice(
        'Não foi possível importar o compartilhamento. Envie um link válido ou uma imagem PNG/JPEG/WebP de até 15 MB.',
      );
    } finally {
      handlingShares = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    if (app.notice != null) {
      final notice = app.notice!;
      app.clearNotice();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(notice)));
        }
      });
    }
    return PopScope(
      canPop: app.tab == Tabs.explore,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (app.tab == Tabs.library &&
            await browserKey.currentState?.handleBack() == true) {
          return;
        }
        app.selectTab(Tabs.explore);
      },
      child: Scaffold(
        body: IndexedStack(
          index: app.tab,
          children: [
            TickerMode(
              enabled: app.tab == 0,
              child: ExploreScreen(app: app),
            ),
            TickerMode(
              enabled: app.tab == 1,
              child: app.browserStarted
                  ? BrowserScreen(key: browserKey, app: app)
                  : const SizedBox.shrink(),
            ),
            TickerMode(
              enabled: app.tab == Tabs.saved,
              child: SavedScreen(app: app),
            ),
            TickerMode(
              enabled: app.tab == Tabs.settings,
              child: SettingsScreen(app: app),
            ),
          ],
        ),
        bottomNavigationBar: app.libraryChromeHidden
            ? null
            : NavigationBar(
                selectedIndex: app.tab,
                onDestinationSelected: (v) {
                  HapticFeedback.selectionClick();
                  app.selectTab(v);
                },
                destinations: const [
                  NavigationDestination(
                    icon: PocketIcon(PocketGlyph.explore),
                    selectedIcon: PocketIcon(PocketGlyph.explore),
                    label: 'Explorar',
                  ),
                  NavigationDestination(
                    icon: PocketIcon(PocketGlyph.library),
                    selectedIcon: PocketIcon(PocketGlyph.library),
                    label: 'Biblioteca',
                  ),
                  NavigationDestination(
                    icon: PocketIcon(PocketGlyph.saved),
                    selectedIcon: PocketIcon(PocketGlyph.saved),
                    label: 'Salvos',
                  ),
                  NavigationDestination(
                    icon: PocketIcon(PocketGlyph.settings),
                    selectedIcon: PocketIcon(PocketGlyph.settings),
                    label: 'Ajustes',
                  ),
                ],
              ),
      ),
    );
  }
}
