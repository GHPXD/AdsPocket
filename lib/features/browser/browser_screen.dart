import 'dart:collection';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:share_plus/share_plus.dart';
import '../../app/app_controller.dart';
import '../../core/longevity.dart';
import '../../core/meta_ads_library_url_builder.dart';
import '../../core/native_bridge.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../favorites/bookmark_editor.dart';
import '../mining/ocr_screen.dart';
import '../mining/offer_editor.dart';
import '../mining/offer_widgets.dart';
import 'filter_chips.dart';
import 'library_assistant.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key, required this.app});
  final AppController app;
  @override
  State<BrowserScreen> createState() => BrowserScreenState();
}

class BrowserScreenState extends State<BrowserScreen>
    with WidgetsBindingObserver {
  InAppWebViewController? controller;
  Timer? timeout, blankCheck;
  int serial = -1, progress = 0;

  /// Completed main-frame navigations; tests wait on this instead of logs.
  int loadsCompleted = 0;
  bool canBack = false, canForward = false, collapsed = false;
  bool mediaFullscreen = false;

  /// Non-blocking warning (slow response, HTTP error, blank page).
  String? problem;

  /// Main-frame failure: the page is replaced by a clear error state.
  bool failed = false;
  ViewMode? mode;
  int? zoom;

  /// Cards read by the assistant on the current page, by Library ID.
  final cards = <String, LibraryCard>{};
  AssistantStats? stats;
  String? assistantConfig;

  /// Library Page IDs read from ad details, by ad and by profile link, and
  /// the advertiser names shown there. Kept for the whole session.
  final pageOfAd = <String, String>{};
  final pageByProfile = <String, String>{};
  final pageNames = <String, String>{};

  /// Card whose advertiser the user is choosing in Meta's suggestion list.
  ({String id, String name, DateTime at})? pendingPick;

  /// Feed mode: the floating control hides while scrolling down.
  bool feedControls = true;
  int lastScrollY = 0;
  Uri? pending;
  bool externalPromptOpen = false;
  late final Uri firstUrl;
  bool get supported =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      InAppWebViewPlatform.instance != null;

  @override
  void initState() {
    super.initState();
    firstUrl = widget.app.currentUrl;
    serial = widget.app.navigationSerial;
    mode = widget.app.settings.viewMode;
    zoom = widget.app.settings.zoom;
    PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
    widget.app.addListener(_sync);
    WidgetsBinding.instance.addObserver(this);
  }

  /// Keyboard open/close changes the window insets; rebuild the chrome.
  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    timeout?.cancel();
    blankCheck?.cancel();
    widget.app.removeListener(_sync);
    WidgetsBinding.instance.removeObserver(this);
    controller = null;
    super.dispose();
  }

  void _sync() {
    final app = widget.app;
    final config =
        '${app.settings.assistant}|${app.settings.minDays}|${app.settings.includeUndated}|${app.settings.minAds}|${app.savedAdIds.length}';
    if (config != assistantConfig) {
      final wasOn = assistantConfig?.startsWith('true') ?? true;
      assistantConfig = config;
      if (controller != null) {
        if (wasOn != app.settings.assistant) {
          unawaited(
            _js(
              app.settings.assistant
                  ? 'window.AdsPocketAssist && AdsPocketAssist.enable()'
                  : 'window.AdsPocketAssist && AdsPocketAssist.disable()',
            ),
          );
          if (!app.settings.assistant && mounted) setState(() => stats = null);
        }
        if (app.settings.assistant) unawaited(_applyAssistant());
      }
    }
    if (app.navigationSerial != serial) {
      serial = app.navigationSerial;
      pending = app.currentUrl;
      if (controller != null) unawaited(_loadPending());
    }
    if (mode != app.settings.viewMode || zoom != app.settings.zoom) {
      final desktopChanged =
          (mode == ViewMode.desktop) !=
          (app.settings.viewMode == ViewMode.desktop);
      mode = app.settings.viewMode;
      zoom = app.settings.zoom;
      if (controller != null) {
        unawaited(
          runGuarded(context, () async {
            await controller!.setSettings(settings: _settings());
            // The content mode only applies to a new document load.
            if (desktopChanged) await controller!.reload();
            await _applyFeed();
          }),
        );
      }
    }
  }

  InAppWebViewSettings _settings() => InAppWebViewSettings(
    javaScriptEnabled: true,
    useShouldOverrideUrlLoading: true,
    useOnDownloadStart: true,
    mediaPlaybackRequiresUserGesture: true,
    allowsInlineMediaPlayback: true,
    supportMultipleWindows: true,
    javaScriptCanOpenWindowsAutomatically: false,
    safeBrowsingEnabled: true,
    mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
    allowFileAccess: false,
    allowContentAccess: false,
    builtInZoomControls: true,
    displayZoomControls: false,
    supportZoom: true,
    thirdPartyCookiesEnabled: false,
    textZoom: widget.app.settings.zoom,
    preferredContentMode: widget.app.settings.viewMode == ViewMode.desktop
        ? UserPreferredContentMode.DESKTOP
        : UserPreferredContentMode.RECOMMENDED,
  );

  Future<void> _loadPending() async {
    final uri = pending;
    pending = null;
    if (uri == null || controller == null) return;
    await runGuarded(context, () async {
      // Avoid duplicate loads when the requested page is already open.
      final now = Uri.tryParse((await controller!.getUrl())?.toString() ?? '');
      if (now != null &&
          MetaAdsLibraryUrlBuilder.sameView(now, uri) &&
          !failed) {
        return;
      }
      await controller!.loadUrl(
        urlRequest: URLRequest(url: WebUri(uri.toString())),
      );
    });
  }

  /// Moves through the WebView history to [target] when it is there, which
  /// keeps its scroll position; loads it otherwise.
  Future<void> jumpTo(Uri target) async {
    final stack = await controller?.getCopyBackForwardList();
    final index = stack?.currentIndex;
    final entries = stack?.list;
    if (index != null && entries != null) {
      int? best;
      for (var i = 0; i < entries.length; i++) {
        final url = Uri.tryParse(entries[i].url?.toString() ?? '');
        if (url != null &&
            MetaAdsLibraryUrlBuilder.sameView(url, target) &&
            (best == null || (i - index).abs() < (best - index).abs())) {
          best = i;
        }
      }
      if (best != null) {
        if (best != index) {
          await controller?.goBackOrForward(steps: best - index);
        }
        return;
      }
    }
    await widget.app.openLibrary(target);
  }

  /// Unpins Meta's sticky bars in feed mode (they scroll with the page).
  Future<void> _applyFeed() => _js(
    'window.AdsPocketAssist && AdsPocketAssist.feed(${widget.app.settings.viewMode == ViewMode.feed})',
  );

  Future<void> _js(String source) async {
    try {
      await controller?.evaluateJavascript(source: source);
    } catch (_) {
      // The page may be navigating; the next message re-syncs the assistant.
    }
  }

  /// Sends civil ages (computed here, not in the page) and the local filter.
  Future<void> _applyAssistant() async {
    final s = widget.app.settings;
    if (!s.assistant) return;
    final today = CivilDate.today();
    await _js(
      assistantApply(
        ages: {for (final c in cards.values) c.id: ageInDays(c.start, today)},
        saved: widget.app.savedAdIds,
        minDays: s.minDays,
        includeUndated: s.includeUndated,
        minAds: s.minAds,
        pages: {for (final c in cards.values) c.id: ?pageOf(c)},
      ),
    );
  }

  /// Library Page ID of a card when known: the current Page view, the ad
  /// details read earlier, or another ad from the same profile.
  String? pageOf(LibraryCard card) =>
      MetaAdsLibraryUrlBuilder.pageId(widget.app.currentUrl) ??
      pageOfAd[card.id] ??
      pageByProfile[card.profile?.toString()];

  String _adUrl(String id) => MetaAdsLibraryUrlBuilder.home
      .replace(queryParameters: {'id': id})
      .toString();

  /// Opens every active ad of the card's Page, as on the desktop Library.
  Future<void> openCardPage(
    String id,
    String? page,
    String? name, {
    bool pick = false,
  }) async {
    final app = widget.app;
    if (page == null) {
      if (pick && name != null) {
        // Meta only accepts the user's own tap on its suggestion list.
        pendingPick = (id: id, name: name, at: DateTime.now());
        app.showNotice(
          'Esta Página não mostra o ID nos detalhes. Toque em "$name" na lista de anunciantes da Meta (destacado) para abrir os anúncios dela.',
        );
      } else {
        app.showNotice(
          'Não encontrei o ID da Página deste anúncio. Pesquise o anunciante no campo da Meta e escolha-o na lista.',
        );
      }
      return;
    }
    _learnPage(id, page, name);
    final from = app.currentUrl.queryParameters;
    await runGuarded(
      context,
      () => app.openLibrary(
        MetaAdsLibraryUrlBuilder().build(
          text: page,
          type: SearchType.pageId,
          country: countries.containsKey(from['country'])
              ? from['country']!
              : app.settings.country,
          status: 'active',
        ),
      ),
    );
  }

  void _learnPage(String id, String page, String? name) {
    pageOfAd[id] = page;
    final profile = cards[id]?.profile?.toString();
    if (profile != null) pageByProfile[profile] = page;
    final advertiser = name ?? cards[id]?.advertiser;
    if (advertiser != null && advertiser.isNotEmpty) {
      pageNames[page] = advertiser;
    }
  }

  Future<void> _onAssistant(Object? raw) async {
    final m = parseAssistantMessage(raw);
    if (m == null || !mounted) return;
    if (m.stats != null) setState(() => stats = m.stats);
    switch (m.type) {
      case 'ready':
        await _applyFeed();
        if (!widget.app.settings.assistant) {
          await _js('AdsPocketAssist.disable()');
          return;
        }
        await _applyAssistant();
      case 'cards':
        for (final c in m.cards) {
          cards[c.id] = c;
        }
        if (cards.length > 3000) cards.remove(cards.keys.first);
        await _applyAssistant();
      case 'save':
        if (m.id != null) await saveCard(m.id!);
      case 'page':
        if (m.id != null) {
          await openCardPage(m.id!, m.page, m.name, pick: m.pick);
        }
      case 'copy':
        if (m.id != null && mounted) {
          await copyLink(
            context,
            _adUrl(m.id!),
            message: 'Link do anúncio copiado',
          );
        }
      case 'share':
        if (m.id != null && mounted) {
          await runGuarded(context, () async {
            await SharePlus.instance.share(ShareParams(text: _adUrl(m.id!)));
          });
        }
      case 'scrollDone':
        widget.app.showNotice(
          m.found == 0
              ? 'Nenhum anúncio novo passou no filtro.'
              : '${m.found} ${m.found == 1 ? 'anúncio novo' : 'anúncios novos'} no filtro · ${stats?.visible ?? 0} no total.',
        );
    }
    await _noteCount();
  }

  /// Stores Meta's counter for a saved advertiser only when it was read on
  /// that same Page (never a search count left over in the DOM).
  Future<void> _noteCount() async {
    final pageId = MetaAdsLibraryUrlBuilder.pageId(widget.app.currentUrl);
    final st = stats;
    if (pageId == null || st == null || st.results.isEmpty) return;
    final measured = st.url == null
        ? null
        : MetaAdsLibraryUrlBuilder.pageId(st.url!);
    if (measured == pageId) await widget.app.noteMetaCount(pageId, st.results);
  }

  /// One-tap save from a card badge: every field comes from the card.
  Future<void> saveCard(String id) async {
    final card = cards[id];
    if (card == null) return;
    final offer = card.toOffer(pageId: pageOf(card));
    try {
      await widget.app.saveOffer(offer);
    } on StateError {
      widget.app.showNotice('Este anúncio já está salvo.');
      return;
    } on FormatException catch (e) {
      widget.app.showNotice(e.message);
      return;
    }
    await HapticFeedback.lightImpact();
    await _applyAssistant();
    if (!mounted) return;
    final age = ageInDays(card.start, CivilDate.today());
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          // Actions make snackbars persist by default; this one must not
          // keep covering the Library toolbar.
          persist: false,
          duration: const Duration(seconds: 4),
          content: Text(
            'Anúncio salvo${age == null || age < 0 ? '' : ' · ${ageLabel(age)}'}',
          ),
          action: SnackBarAction(
            label: 'Comentar',
            onPressed: () => commentOffer(context, widget.app, offer.id),
          ),
        ),
      );
  }

  Future<void> toggleAutoScroll() async {
    if (stats?.scrolling ?? false) {
      await _js('window.AdsPocketAssist && AdsPocketAssist.stop()');
    } else {
      await _js(
        'window.AdsPocketAssist && AdsPocketAssist.autoScroll(${widget.app.settings.scrollTarget})',
      );
    }
  }

  Future<bool> handleBack() async {
    if (mediaFullscreen) {
      await controller?.evaluateJavascript(
        source: 'document.exitFullscreen && document.exitFullscreen();',
      );
      return true;
    }
    if (await controller?.canGoBack() ?? false) {
      await controller?.goBack();
      return true;
    }
    return false;
  }

  Future<void> _historyState() async {
    final back = await controller?.canGoBack() ?? false;
    final forward = await controller?.canGoForward() ?? false;
    if (mounted) {
      setState(() {
        canBack = back;
        canForward = forward;
      });
    }
  }

  void _started() {
    timeout?.cancel();
    if (mounted) {
      setState(() {
        problem = null;
        failed = false;
        progress = 0;
        stats = null;
      });
    }
    cards.clear();
    timeout = Timer(const Duration(seconds: 25), () {
      if (mounted && progress < 100) {
        setState(
          () => problem =
              'A Meta está demorando para responder. Aguarde ou abra no navegador.',
        );
      }
    });
  }

  Future<void> _observe(WebUri? url) async {
    final uri = Uri.tryParse(url?.toString() ?? '');
    final pick = pendingPick;
    final picked = uri == null ? null : MetaAdsLibraryUrlBuilder.pageId(uri);
    if (pick != null && picked != null) {
      pendingPick = null;
      // The user chose the advertiser in Meta's list shortly after the tap.
      if (DateTime.now().difference(pick.at) < const Duration(minutes: 2)) {
        _learnPage(pick.id, picked, pick.name);
      }
    }
    if (uri != null && MetaAdsLibraryUrlBuilder.isLibrary(uri)) {
      await widget.app.observeUrl(uri);
    }
    await _historyState();
  }

  Future<NavigationActionPolicy> _navigation(NavigationAction action) async {
    if (action.isForMainFrame == false) return NavigationActionPolicy.ALLOW;
    final uri = Uri.tryParse(action.request.url?.toString() ?? '');
    if (uri != null && MetaAdsLibraryUrlBuilder.isLibrary(uri)) {
      return NavigationActionPolicy.ALLOW;
    }
    final profileId = uri == null
        ? null
        : MetaAdsLibraryUrlBuilder.profilePageId(uri);
    if (profileId != null) {
      if (mounted) await _advertiserPrompt(uri!, profileId);
      return NavigationActionPolicy.CANCEL;
    }
    // Never load login, arbitrary origins or deep-link schemes inside this WebView.
    if (uri != null &&
        MetaAdsLibraryUrlBuilder.safeHttps(uri.toString()) != null) {
      if (mounted) await _externalPrompt(uri);
    } else if (mounted) {
      widget.app.showNotice(
        'Este link não é HTTPS. Use Abrir no navegador para continuar.',
      );
    }
    return NavigationActionPolicy.CANCEL;
  }

  /// The user tapped an advertiser whose profile link carries a numeric ID.
  Future<void> _advertiserPrompt(Uri profile, String id) async {
    if (externalPromptOpen || !mounted) return;
    externalPromptOpen = true;
    try {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Perfil do anunciante'),
          content: Text(
            'Este link leva ao perfil no Facebook (ID $id). Esse número nem sempre é o Page ID da Biblioteca.\n\nPara identificar a Página com segurança, pesquise o nome no campo da Biblioteca e escolha o anunciante na lista.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'profile'),
              child: const Text('Perfil no navegador'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'ads'),
              child: const Text('Tentar como Page ID'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      final from = widget.app.currentUrl.queryParameters;
      if (choice == 'ads') {
        widget.app.unverifiedPageIds.add(id);
        await runGuarded(
          context,
          () => widget.app.openLibrary(
            MetaAdsLibraryUrlBuilder().build(
              text: id,
              type: SearchType.pageId,
              country: countries.containsKey(from['country'])
                  ? from['country']!
                  : widget.app.settings.country,
              status: {'active', 'all'}.contains(from['active_status'])
                  ? from['active_status']!
                  : widget.app.settings.status,
            ),
          ),
        );
      } else if (choice == 'profile') {
        await runGuarded(context, () => widget.app.openExternal(profile));
      }
    } finally {
      externalPromptOpen = false;
    }
  }

  Future<void> _externalPrompt(Uri uri) async {
    if (externalPromptOpen || !mounted) return;
    externalPromptOpen = true;
    try {
      final go = await confirm(
        context,
        'Continuar no navegador?',
        'Este link sai da Biblioteca ou exige uma etapa externa.\n\n${uri.host}',
        action: 'Abrir no navegador',
      );
      if (go && mounted) {
        await runGuarded(context, () => widget.app.openExternal(uri));
      }
    } finally {
      externalPromptOpen = false;
    }
  }

  Future<void> _reload() => runGuarded(context, () async {
    if (failed) {
      await controller?.loadUrl(
        urlRequest: URLRequest(url: WebUri(widget.app.currentUrl.toString())),
      );
    } else {
      await controller?.reload();
    }
  });

  Future<void> _external() =>
      runGuarded(context, () => widget.app.openExternal(widget.app.currentUrl));

  /// Return point for the switch between a Page and the latest search.
  Uri? get switchTarget {
    final app = widget.app;
    return MetaAdsLibraryUrlBuilder.pageId(app.currentUrl) != null
        ? app.initialSearch
        : app.lastAdvertiser;
  }

  Future<void> _home() async {
    final initial = widget.app.initialSearch;
    if (initial == null) {
      widget.app.selectTab(Tabs.explore);
      return;
    }
    await runGuarded(context, () => jumpTo(initial));
  }

  /// Explicit, single capture of the visible area for local OCR.
  Future<void> _analyzeVisible() async {
    await runGuarded(context, () async {
      final bytes = await controller?.takeScreenshot(
        screenshotConfiguration: ScreenshotConfiguration(
          compressFormat: CompressFormat.PNG,
        ),
      );
      final file = bytes == null || bytes.isEmpty
          ? null
          : await NativeBridge.saveImageBytes(bytes);
      if (!mounted) return;
      if (file == null) {
        final pick = await confirm(
          context,
          'Captura indisponível',
          'O WebView não forneceu uma imagem da área visível. Você pode importar um print.',
          action: 'Importar print',
        );
        if (pick && mounted) await analyzeImportedImage(context, widget.app);
        return;
      }
      await analyzeImage(
        context,
        widget.app,
        file,
        capturedAt: DateTime.now().toUtc(),
        url: widget.app.currentUrl,
      );
    });
  }

  Future<void> _more() async {
    final app = widget.app;
    final target = switchTarget;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _MoreSheet(app: app, switchTarget: target),
    );
    if (!mounted) return;
    switch (action) {
      case 'external':
        await _external();
      case 'copy':
        await copyLink(context, app.currentUrl.toString());
      case 'share':
        await runGuarded(context, () async {
          await SharePlus.instance.share(
            ShareParams(text: app.currentUrl.toString()),
          );
        });
      case 'top':
        await runGuarded(context, () async {
          await controller?.scrollTo(x: 0, y: 0, animated: true);
        });
      case 'switch':
        if (target != null) await runGuarded(context, () => jumpTo(target));
      case 'search':
        await editBookmark(
          context,
          app,
          uri: app.currentUrl,
          kind: BookmarkKind.search,
          suggestedName: app.currentUrl.queryParameters['q'],
        );
      case 'ad':
        await editBookmark(
          context,
          app,
          uri: app.currentUrl,
          kind: BookmarkKind.ad,
        );
      case 'catalog':
        await openOfferEditor(context, app, fromUrl: app.currentUrl);
      case 'ocr':
        await _analyzeVisible();
      case 'collapse':
        setState(() => collapsed = true);
      case 'feed':
        await runGuarded(context, () => setFeed(true));
    }
  }

  Future<void> setFeed(bool on) async {
    final s = widget.app.settings;
    if ((s.viewMode == ViewMode.feed) == on) return;
    setState(() => feedControls = true);
    await widget.app.updateSettings(
      s.copyWith(viewMode: on ? ViewMode.feed : ViewMode.standard),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final colors = Theme.of(context).colorScheme;
    // The shell Scaffold strips viewInsets from its body; read the window.
    final keyboard = View.of(context).viewInsets.bottom > 0;
    final feed = app.settings.viewMode == ViewMode.feed;
    final compact =
        app.settings.viewMode == ViewMode.compact || app.settings.immersive;
    final showHeader = !compact && !feed && !keyboard && !mediaFullscreen;
    final showToolbar = !feed && !keyboard && !mediaFullscreen;
    return SafeArea(
      child: Column(
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: showHeader ? _header(colors) : const SizedBox.shrink(),
          ),
          if (app.settings.assistant && !feed && !keyboard && !mediaFullscreen)
            _assistantBar(colors),
          SizedBox(
            height: 2,
            child: progress < 100 && supported
                ? LinearProgressIndicator(
                    value: progress == 0 ? null : progress / 100,
                    minHeight: 2,
                  )
                : null,
          ),
          if (problem != null && !failed) _banner(colors),
          if (app.settings.assistant &&
              !keyboard &&
              (stats?.loaded ?? 0) > 0 &&
              stats?.visible == 0 &&
              !(stats?.scrolling ?? false))
            _filterEmpty(colors),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: supported ? _webView() : _fallback()),
                if (feed && !keyboard && !mediaFullscreen && !failed)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 200),
                      offset: feedControls ? Offset.zero : const Offset(0, 2),
                      child: _feedControls(colors),
                    ),
                  ),
                if (failed)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: Center(
                        child: SingleChildScrollView(
                          child: EmptyState(
                            icon: Icons.cloud_off_rounded,
                            title: 'Não foi possível carregar a Biblioteca',
                            message:
                                'Verifique a conexão. Se a Meta restringir o WebView, continue no navegador.',
                            action: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                FilledButton.icon(
                                  onPressed: _reload,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Tentar novamente'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _external,
                                  icon: const Icon(
                                    Icons.open_in_browser_rounded,
                                  ),
                                  label: const Text('Abrir no navegador'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: !showToolbar
                ? const SizedBox(width: double.infinity)
                : collapsed
                ? _handle(colors)
                : _toolbar(colors, compact),
          ),
        ],
      ),
    );
  }

  Widget _assistantBar(ColorScheme colors) {
    final app = widget.app;
    final s = app.settings;
    final st = stats;
    final scrolling = st?.scrolling ?? false;
    Widget gap() => const SizedBox(width: 8);
    return SizedBox(
      height: 44,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        scrollDirection: Axis.horizontal,
        children: [
          daysChip(
            value: s.minDays,
            compact: true,
            onChanged: (v) => runGuarded(
              context,
              () => app.updateSettings(s.copyWith(minDays: () => v)),
            ),
          ),
          gap(),
          adsChip(
            value: s.minAds,
            compact: true,
            onChanged: (v) => runGuarded(
              context,
              () => app.updateSettings(s.copyWith(minAds: () => v)),
            ),
          ),
          gap(),
          ActionChip(
            avatar: Icon(
              scrolling ? Icons.stop_rounded : Icons.play_arrow_rounded,
              size: 18,
            ),
            label: Text(scrolling ? 'Parar' : 'Auto-rolar'),
            tooltip: scrolling
                ? 'Parar a rolagem automática'
                : 'Rolar até achar mais ${s.scrollTarget} anúncios no filtro',
            visualDensity: VisualDensity.compact,
            onPressed: toggleAutoScroll,
          ),
          gap(),
          Center(
            child: Text(
              st == null
                  ? 'Assistente pronto'
                  : [
                      if (st.results.isNotEmpty) '${st.results} na Meta',
                      '${st.visible} de ${st.loaded} no filtro',
                      if (st.active > 0) '${st.active} ativos carregados',
                    ].join(' · '),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Feed mode keeps a single floating control over the page.
  Widget _feedControls(ColorScheme colors) {
    final scrolling = stats?.scrolling ?? false;
    return Material(
      color: colors.surfaceContainerHigh.withValues(alpha: 0.94),
      elevation: 4,
      shape: const StadiumBorder(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Voltar',
            onPressed: canBack
                ? () => runGuarded(context, () async {
                    await controller?.goBack();
                  })
                : null,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          IconButton(
            tooltip: 'Filtros e opções',
            onPressed: _feedSheet,
            icon: const Icon(Icons.tune_rounded),
          ),
          if (widget.app.settings.assistant)
            IconButton(
              tooltip: scrolling ? 'Parar a rolagem automática' : 'Auto-rolar',
              onPressed: toggleAutoScroll,
              icon: Icon(
                scrolling ? Icons.stop_rounded : Icons.play_arrow_rounded,
              ),
            ),
          IconButton(
            tooltip: 'Sair do modo feed',
            onPressed: () => runGuarded(context, () => setFeed(false)),
            icon: const Icon(Icons.close_fullscreen_rounded),
          ),
        ],
      ),
    );
  }

  Future<void> _feedSheet() async {
    final app = widget.app;
    final target = switchTarget;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final s = app.settings;
          final st = stats;
          final onPage =
              MetaAdsLibraryUrlBuilder.pageId(app.currentUrl) != null;
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (s.assistant) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        daysChip(
                          value: s.minDays,
                          long: true,
                          onChanged: (v) => runGuarded(
                            context,
                            () => app.updateSettings(
                              s.copyWith(minDays: () => v),
                            ),
                          ),
                        ),
                        adsChip(
                          value: s.minAds,
                          long: true,
                          onChanged: (v) => runGuarded(
                            context,
                            () =>
                                app.updateSettings(s.copyWith(minAds: () => v)),
                          ),
                        ),
                      ],
                    ),
                    if (st != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          [
                            if (st.results.isNotEmpty) '${st.results} na Meta',
                            '${st.visible} de ${st.loaded} no filtro',
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    const Divider(height: 24),
                  ],
                  if (target != null)
                    ListTile(
                      leading: Icon(
                        onPage
                            ? Icons.manage_search_rounded
                            : Icons.storefront_rounded,
                      ),
                      title: Text(
                        onPage ? 'Voltar à pesquisa' : 'Abrir última Página',
                      ),
                      onTap: () => Navigator.pop(context, 'switch'),
                    ),
                  ListTile(
                    leading: const Icon(Icons.refresh_rounded),
                    title: const Text('Atualizar'),
                    onTap: () => Navigator.pop(context, 'reload'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.more_horiz_rounded),
                    title: const Text('Mais opções'),
                    onTap: () => Navigator.pop(context, 'more'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.close_fullscreen_rounded),
                    title: const Text('Sair do modo feed'),
                    onTap: () => Navigator.pop(context, 'exit'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'switch':
        if (target != null) await runGuarded(context, () => jumpTo(target));
      case 'reload':
        await _reload();
      case 'more':
        await _more();
      case 'exit':
        await runGuarded(context, () => setFeed(false));
    }
  }

  Widget _header(ColorScheme colors) {
    final app = widget.app;
    final pageId = MetaAdsLibraryUrlBuilder.pageId(app.currentUrl);
    final query = app.currentUrl.queryParameters['q'];
    final saved = pageId == null ? null : app.savedAdvertiser(pageId);
    final target = switchTarget;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pageId != null
                      ? saved?.name ?? pageNames[pageId] ?? 'Página $pageId'
                      : query?.isNotEmpty == true
                      ? query!
                      : 'Biblioteca de Anúncios',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                Text(
                  [
                    pageId != null
                        ? 'Anúncios da Página'
                        : query?.isNotEmpty == true
                        ? 'Pesquisa'
                        : 'facebook.com',
                    if (app.settings.assistant &&
                        (stats?.results.isNotEmpty ?? false))
                      '${stats!.results} na Meta',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (target != null)
            ActionChip(
              avatar: Icon(
                pageId != null
                    ? Icons.manage_search_rounded
                    : Icons.storefront_rounded,
                size: 18,
              ),
              label: Text(pageId != null ? 'Pesquisa' : 'Última Página'),
              tooltip: pageId != null
                  ? 'Voltar à pesquisa'
                  : 'Abrir a última Página visitada',
              onPressed: () => runGuarded(context, () => jumpTo(target)),
            ),
          IconButton(
            tooltip: 'Abrir no navegador',
            onPressed: _external,
            icon: const Icon(Icons.open_in_browser_rounded),
          ),
        ],
      ),
    );
  }

  Widget _banner(ColorScheme colors) => Material(
    color: colors.secondaryContainer,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              problem!,
              style: TextStyle(color: colors.onSecondaryContainer),
            ),
          ),
          TextButton(onPressed: _external, child: const Text('Navegador')),
          IconButton(
            tooltip: 'Fechar aviso',
            onPressed: () => setState(() => problem = null),
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
        ],
      ),
    ),
  );

  /// Every loaded card is hidden by the local filter; say so instead of
  /// leaving what looks like an empty page.
  Widget _filterEmpty(ColorScheme colors) {
    final app = widget.app;
    return Material(
      color: colors.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Nenhum dos ${stats!.loaded} anúncios carregados passa no filtro.',
                style: TextStyle(
                  color: colors.onTertiaryContainer,
                  fontSize: 13,
                ),
              ),
            ),
            TextButton(
              onPressed: toggleAutoScroll,
              child: const Text('Procurar mais'),
            ),
            TextButton(
              onPressed: () => runGuarded(
                context,
                () => app.updateSettings(
                  app.settings.copyWith(
                    minDays: () => null,
                    minAds: () => null,
                  ),
                ),
              ),
              child: const Text('Limpar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _handle(ColorScheme colors) => Material(
    color: colors.surface,
    child: InkWell(
      onTap: () => setState(() => collapsed = false),
      child: Semantics(
        button: true,
        label: 'Mostrar controles',
        child: SizedBox(
          height: 28,
          width: double.infinity,
          child: Center(
            child: Icon(
              Icons.keyboard_arrow_up_rounded,
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    ),
  );

  Widget _toolbar(ColorScheme colors, bool compact) {
    final pageId = MetaAdsLibraryUrlBuilder.pageId(widget.app.currentUrl);
    final saved = pageId != null && widget.app.savedAdvertiser(pageId) != null;
    Widget button(
      String tip,
      IconData icon,
      VoidCallback? onPressed, {
      Color? color,
    }) => Expanded(
      child: IconButton(
        tooltip: tip,
        onPressed: onPressed == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onPressed();
              },
        icon: Icon(icon, color: onPressed == null ? null : color),
      ),
    );
    return Material(
      color: colors.surface,
      child: SizedBox(
        height: compact ? 48 : 56,
        child: Row(
          children: [
            button(
              'Voltar',
              Icons.arrow_back_rounded,
              canBack
                  ? () => runGuarded(context, () async {
                      await controller?.goBack();
                    })
                  : null,
            ),
            button(
              'Avançar',
              Icons.arrow_forward_rounded,
              canForward
                  ? () => runGuarded(context, () async {
                      await controller?.goForward();
                    })
                  : null,
            ),
            button('Atualizar', Icons.refresh_rounded, _reload),
            button('Voltar à pesquisa', Icons.manage_search_rounded, _home),
            button(
              pageId != null ? 'Salvar anunciante' : 'Salvar referência',
              saved ? Icons.bookmark_rounded : Icons.bookmark_add_outlined,
              () async {
                await saveCurrentReference(
                  context,
                  widget.app,
                  widget.app.currentUrl,
                );
                await _noteCount();
              },
              color: colors.primary,
            ),
            button('Mais opções', Icons.more_horiz_rounded, _more),
          ],
        ),
      ),
    );
  }

  Widget _fallback() => SingleChildScrollView(
    child: EmptyState(
      icon: Icons.phone_android,
      title: 'Biblioteca no Android',
      message:
          'O navegador integrado está disponível no aplicativo Android. Você pode abrir o site no navegador externo.',
      action: FilledButton(
        onPressed: _external,
        child: const Text('Abrir Biblioteca oficial'),
      ),
    ),
  );

  Widget _webView() {
    final app = widget.app;
    return InAppWebView(
      key: const ValueKey('official-library'),
      initialUrlRequest: URLRequest(url: WebUri(firstUrl.toString())),
      initialSettings: _settings(),
      initialUserScripts: UnmodifiableListView([
        UserScript(
          source: assistantScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
        ),
      ]),
      onWebViewCreated: (c) {
        controller = c;
        c.addJavaScriptHandler(
          handlerName: 'adspocket',
          callback: (args) {
            unawaited(_onAssistant(args.isEmpty ? null : args.first));
            return null;
          },
        );
        serial = app.navigationSerial;
        if (pending != null && pending != firstUrl) {
          unawaited(_loadPending());
        } else {
          pending = null;
        }
      },
      onLoadStart: (c, url) {
        _started();
        _observe(url);
      },
      onProgressChanged: (c, value) {
        if (mounted) setState(() => progress = value);
      },
      onLoadStop: (c, url) async {
        timeout?.cancel();
        if (mounted) {
          setState(() {
            progress = 100;
            loadsCompleted++;
          });
        }
        await _observe(url);
        // A single conservative readiness check, with no card/credential extraction.
        final blank = await c.evaluateJavascript(
          source:
              '(document.body && document.body.innerText.trim().length === 0 && document.body.children.length === 0)',
        );
        if (blank == true && mounted) {
          setState(
            () => problem =
                'A página ficou em branco. Recarregue ou continue no navegador.',
          );
          return;
        }
        // Meta may answer with an automatic verification page that reloads
        // itself. If nothing readable appears, offer the browser instead of
        // waiting silently. Nothing is bypassed or retried by the app.
        final load = loadsCompleted;
        blankCheck?.cancel();
        blankCheck = Timer(const Duration(seconds: 12), () async {
          if (!mounted || loadsCompleted != load || controller == null) return;
          final empty = await controller!.evaluateJavascript(
            source:
                '(!document.body || document.body.innerText.trim().length === 0)',
          );
          if (empty == true && mounted && loadsCompleted == load) {
            setState(
              () => problem =
                  'A Meta não exibiu conteúdo neste navegador integrado. Continue no navegador.',
            );
          }
        });
      },
      onUpdateVisitedHistory: (c, url, reload) => _observe(url),
      onScrollChanged: (c, x, y) {
        // Like a social feed: hide the control going down, show it going up.
        final delta = y - lastScrollY;
        if (delta.abs() < 24) return;
        lastScrollY = y;
        final show = delta < 0 || y < 80;
        if (show != feedControls && mounted) {
          setState(() => feedControls = show);
        }
      },
      shouldOverrideUrlLoading: (c, action) => _navigation(action),
      onReceivedError: (c, request, error) {
        if (request.isForMainFrame == true && mounted) {
          timeout?.cancel();
          setState(() {
            progress = 100;
            failed = true;
          });
        }
      },
      onReceivedHttpError: (c, request, response) {
        if (request.isForMainFrame == true &&
            (response.statusCode ?? 0) >= 400 &&
            mounted) {
          setState(
            () => problem =
                'A Meta retornou um erro ou restringiu este acesso. Continue no navegador.',
          );
        }
      },
      onReceivedServerTrustAuthRequest: (c, challenge) async =>
          ServerTrustAuthResponse(action: ServerTrustAuthResponseAction.CANCEL),
      onPermissionRequest: (c, request) async => PermissionResponse(
        resources: request.resources,
        action: PermissionResponseAction.DENY,
      ),
      onCreateWindow: (c, action) async {
        final uri = Uri.tryParse(action.request.url?.toString() ?? '');
        final profileId = uri == null
            ? null
            : MetaAdsLibraryUrlBuilder.profilePageId(uri);
        if (uri != null && MetaAdsLibraryUrlBuilder.isLibrary(uri)) {
          await app.openLibrary(uri);
        } else if (profileId != null && mounted) {
          await _advertiserPrompt(uri!, profileId);
        } else if (uri != null &&
            MetaAdsLibraryUrlBuilder.safeHttps(uri.toString()) != null &&
            mounted) {
          await _externalPrompt(uri);
        } else {
          app.showNotice(
            'Este pop-up não tem um link compatível. Continue no navegador externo.',
          );
        }
        return false;
      },
      onDownloadStartRequest: (c, request) async {
        final uri = MetaAdsLibraryUrlBuilder.safeHttps(request.url.toString());
        if (uri != null && mounted) {
          final go = await confirm(
            context,
            'Download pela origem',
            'O navegador cuidará do download oferecido pelo site. Se ele não estiver disponível, salve o link do anúncio.',
            action: 'Abrir origem',
          );
          if (go && mounted) {
            await runGuarded(context, () => app.openExternal(uri));
          }
        } else {
          app.showNotice(
            'Este arquivo não pode ser baixado diretamente. Use Salvar link do anúncio.',
          );
        }
      },
      onEnterFullscreen: (c) {
        setState(() => mediaFullscreen = true);
        app.setFullscreen(true);
      },
      onExitFullscreen: (c) {
        setState(() => mediaFullscreen = false);
        app.setFullscreen(false);
      },
    );
  }
}

class _MoreSheet extends StatelessWidget {
  const _MoreSheet({required this.app, required this.switchTarget});
  final AppController app;
  final Uri? switchTarget;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: app,
    builder: (context, _) {
      final s = app.settings;
      final onPage = MetaAdsLibraryUrlBuilder.pageId(app.currentUrl) != null;
      final colors = Theme.of(context).colorScheme;
      Widget quick(String value, IconData icon, String label) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.pop(context, value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              children: [
                Icon(icon),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      );
      Widget item(String value, IconData icon, String label) => ListTile(
        leading: Icon(icon),
        title: Text(label),
        onTap: () => Navigator.pop(context, value),
      );
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  quick('external', Icons.open_in_browser_rounded, 'Navegador'),
                  quick('copy', Icons.link_rounded, 'Copiar'),
                  quick('share', Icons.ios_share_rounded, 'Compartilhar'),
                  quick('top', Icons.vertical_align_top_rounded, 'Topo'),
                  quick('feed', Icons.view_agenda_outlined, 'Feed'),
                ],
              ),
              const Divider(height: 24),
              if (switchTarget != null)
                item(
                  'switch',
                  onPage
                      ? Icons.manage_search_rounded
                      : Icons.storefront_rounded,
                  onPage ? 'Voltar à pesquisa' : 'Abrir última Página',
                ),
              item(
                'catalog',
                Icons.playlist_add_rounded,
                'Catalogar na Mineração',
              ),
              item(
                'ocr',
                Icons.document_scanner_outlined,
                'Analisar área visível',
              ),
              item('search', Icons.saved_search_rounded, 'Salvar pesquisa'),
              item('ad', Icons.ad_units_outlined, 'Salvar link do anúncio'),
              item('collapse', Icons.unfold_less_rounded, 'Recolher controles'),
              const Divider(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<ViewMode>(
                  showSelectedIcon: false,
                  segments: [
                    for (final v in ViewMode.values)
                      ButtonSegment(
                        value: v,
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(v.label, maxLines: 1, softWrap: false),
                        ),
                      ),
                  ],
                  selected: {s.viewMode},
                  onSelectionChanged: (v) => runGuarded(context, () async {
                    await app.updateSettings(s.copyWith(viewMode: v.single));
                    if (v.single == ViewMode.desktop) {
                      app.showNotice(
                        'Layout desktop solicitado ao WebView. A Meta pode manter a versão mobile.',
                      );
                    }
                  }),
                ),
              ),
              SwitchListTile(
                title: const Text('Modo imersivo'),
                subtitle: const Text('Oculta a navegação do app'),
                value: s.immersive,
                onChanged: (v) =>
                    runGuarded(context, () => app.setImmersive(v)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Row(
                  children: [
                    Icon(
                      Icons.text_fields_rounded,
                      size: 20,
                      color: colors.onSurfaceVariant,
                    ),
                    Expanded(
                      child: Slider(
                        value: s.zoom.toDouble(),
                        min: 75,
                        max: 200,
                        divisions: 5,
                        label: '${s.zoom}%',
                        semanticFormatterCallback: (v) =>
                            'Texto do site ${v.round()}%',
                        onChanged: (v) => runGuarded(
                          context,
                          () => app.updateSettings(s.copyWith(zoom: v.round())),
                        ),
                      ),
                    ),
                    Text('${s.zoom}%'),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
