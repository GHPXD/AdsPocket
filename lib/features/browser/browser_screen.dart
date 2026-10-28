import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:share_plus/share_plus.dart';
import '../../app/app_controller.dart';
import '../../core/meta_ads_library_url_builder.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../favorites/bookmark_editor.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key, required this.app});
  final AppController app;
  @override
  State<BrowserScreen> createState() => BrowserScreenState();
}

class BrowserScreenState extends State<BrowserScreen> {
  InAppWebViewController? controller;
  Timer? timeout;
  int serial = -1, progress = 0;
  bool canBack = false,
      canForward = false,
      collapsed = false,
      mediaFullscreen = false;
  String? problem;
  ViewMode? mode;
  int? zoom;
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
    PlatformInAppWebViewController.debugLoggingSettings.enabled = false;
    widget.app.addListener(_sync);
  }

  @override
  void dispose() {
    timeout?.cancel();
    widget.app.removeListener(_sync);
    controller = null;
    super.dispose();
  }

  void _sync() {
    final app = widget.app;
    if (app.navigationSerial != serial) {
      serial = app.navigationSerial;
      pending = app.currentUrl;
      if (controller != null) {
        unawaited(_loadPending());
      }
    }
    if (mode != app.settings.viewMode || zoom != app.settings.zoom) {
      mode = app.settings.viewMode;
      zoom = app.settings.zoom;
      if (controller != null) {
        unawaited(
          runGuarded(context, () async {
            await controller!.setSettings(settings: _settings());
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
      await controller!.loadUrl(
        urlRequest: URLRequest(url: WebUri(uri.toString())),
      );
    });
  }

  Future<bool> handleBack() async {
    if (mediaFullscreen) {
      await controller?.evaluateJavascript(
        source: 'document.exitFullscreen && document.exitFullscreen();',
      );
      return true;
    }
    if (widget.app.fullscreen) {
      widget.app.setFullscreen(false);
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
        progress = 0;
      });
    }
    timeout = Timer(const Duration(seconds: 25), () {
      if (mounted && progress < 100) {
        setState(
          () => problem =
              'A Meta está demorando para responder. Você pode continuar esperando ou abrir no navegador.',
        );
      }
    });
  }

  Future<void> _observe(WebUri? url) async {
    final uri = Uri.tryParse(url?.toString() ?? '');
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
    // Never load login, arbitrary origins or deep-link schemes inside this WebView.
    if (uri != null &&
        MetaAdsLibraryUrlBuilder.safeHttps(uri.toString()) != null) {
      if (mounted) await _externalPrompt(uri);
    } else if (mounted) {
      widget.app.showNotice(
        'Este link não é HTTPS. Use a opção Abrir no navegador da Biblioteca para continuar.',
      );
    }
    return NavigationActionPolicy.CANCEL;
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

  Future<void> _menu(String value) async {
    final app = widget.app;
    switch (value) {
      case 'copy':
        await copyLink(context, app.currentUrl.toString());
      case 'share':
        await runGuarded(context, () async {
          await SharePlus.instance.share(
            ShareParams(text: app.currentUrl.toString()),
          );
        });
      case 'advertiser':
        await editBookmark(
          context,
          app,
          uri: app.currentUrl,
          kind: BookmarkKind.advertiser,
        );
      case 'ad':
        await editBookmark(
          context,
          app,
          uri: app.currentUrl,
          kind: BookmarkKind.ad,
        );
      case 'search':
        await editBookmark(
          context,
          app,
          uri: app.currentUrl,
          kind: BookmarkKind.search,
          suggestedName: app.currentUrl.queryParameters['q'],
        );
      case 'external':
        await runGuarded(context, () => app.openExternal(app.currentUrl));
      case 'initial':
        final initial = app.initialSearch;
        if (initial != null) {
          await runGuarded(context, () async {
            final stack = await controller?.getCopyBackForwardList();
            final index = stack?.currentIndex;
            final entries = stack?.list;
            if (index != null && entries != null) {
              for (var i = index; i >= 0; i--) {
                final url = Uri.tryParse(entries[i].url?.toString() ?? '');
                if (url != null &&
                    MetaAdsLibraryUrlBuilder.canonical(url) ==
                        MetaAdsLibraryUrlBuilder.canonical(initial)) {
                  if (i != index) {
                    await controller?.goBackOrForward(steps: i - index);
                  }
                  return;
                }
              }
            }
            await app.openLibrary(initial);
          });
        } else {
          app.selectTab(0);
        }
      case 'fullscreen':
        app.setFullscreen(!app.fullscreen);
      case 'collapse':
        setState(() => collapsed = !collapsed);
      case 'standard':
      case 'compact':
      case 'desktop':
        await runGuarded(
          context,
          () => app.updateSettings(
            app.settings.copyWith(viewMode: ViewMode.values.byName(value)),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final compact =
        app.settings.viewMode == ViewMode.compact ||
        collapsed ||
        app.fullscreen;
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        children: [
          if (!compact)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.public_rounded, color: colors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          MetaAdsLibraryUrlBuilder.pageId(app.currentUrl) !=
                                  null
                              ? 'Anúncios da Página'
                              : 'Biblioteca oficial',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'facebook.com · ${app.settings.viewMode.label}',
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Abrir no navegador',
                    onPressed: () => _menu('external'),
                    icon: const Icon(Icons.open_in_browser_rounded),
                  ),
                  _options(),
                ],
              ),
            ),
          if (progress < 100 && app.browserStarted && supported)
            LinearProgressIndicator(
              value: progress == 0 ? null : progress / 100,
              minHeight: 2,
            ),
          if (problem != null)
            Material(
              color: colors.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      problem!,
                      style: TextStyle(color: colors.onErrorContainer),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: () => _menu('external'),
                          icon: const Icon(Icons.open_in_browser),
                          label: const Text('Abrir no navegador'),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() => problem = null);
                            runGuarded(context, () async {
                              await controller?.reload();
                            });
                          },
                          child: const Text('Tentar novamente'),
                        ),
                        TextButton(
                          onPressed: () => setState(() => problem = null),
                          child: const Text('Fechar aviso'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: !supported
                      ? EmptyState(
                          icon: Icons.phone_android,
                          title: 'Biblioteca no Android',
                          message:
                              'O navegador integrado está disponível no aplicativo Android. Você pode abrir o site no navegador externo.',
                          action: FilledButton(
                            onPressed: () => _menu('external'),
                            child: const Text('Abrir Biblioteca oficial'),
                          ),
                        )
                      : InAppWebView(
                          key: const ValueKey('official-library'),
                          initialUrlRequest: URLRequest(
                            url: WebUri(firstUrl.toString()),
                          ),
                          initialSettings: _settings(),
                          onWebViewCreated: (c) {
                            controller = c;
                            serial = app.navigationSerial;
                            if (pending != null && pending != firstUrl) {
                              unawaited(_loadPending());
                            } else {
                              pending = null;
                            }
                            mode = app.settings.viewMode;
                            zoom = app.settings.zoom;
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
                            }
                          },
                          onUpdateVisitedHistory: (c, url, reload) =>
                              _observe(url),
                          shouldOverrideUrlLoading: (c, action) =>
                              _navigation(action),
                          onReceivedError: (c, request, error) {
                            if (request.isForMainFrame == true && mounted) {
                              timeout?.cancel();
                              setState(() {
                                progress = 100;
                                problem =
                                    'Não foi possível carregar a Biblioteca. Verifique a conexão ou abra no navegador.';
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
                          onReceivedServerTrustAuthRequest:
                              (c, challenge) async => ServerTrustAuthResponse(
                                action: ServerTrustAuthResponseAction.CANCEL,
                              ),
                          onPermissionRequest: (c, request) async =>
                              PermissionResponse(
                                resources: request.resources,
                                action: PermissionResponseAction.DENY,
                              ),
                          onCreateWindow: (c, action) async {
                            final uri = Uri.tryParse(
                              action.request.url?.toString() ?? '',
                            );
                            if (uri != null &&
                                MetaAdsLibraryUrlBuilder.isLibrary(uri)) {
                              await app.openLibrary(uri);
                            } else if (uri != null &&
                                MetaAdsLibraryUrlBuilder.safeHttps(
                                      uri.toString(),
                                    ) !=
                                    null &&
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
                            final uri = MetaAdsLibraryUrlBuilder.safeHttps(
                              request.url.toString(),
                            );
                            if (uri != null && mounted) {
                              final go = await confirm(
                                context,
                                'Download pela origem',
                                'O navegador cuidará do download oferecido pelo site. Se ele não estiver disponível, salve o link do anúncio.',
                                action: 'Abrir origem',
                              );
                              if (go && context.mounted) {
                                await runGuarded(
                                  context,
                                  () => app.openExternal(uri),
                                );
                              }
                            } else {
                              app.showNotice(
                                'Este arquivo não pode ser baixado diretamente. Use Salvar link do anúncio.',
                              );
                            }
                          },
                          onEnterFullscreen: (c) {
                            mediaFullscreen = true;
                            app.setFullscreen(true);
                          },
                          onExitFullscreen: (c) {
                            mediaFullscreen = false;
                            app.setFullscreen(false);
                          },
                        ),
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton.small(
                    heroTag: 'top',
                    tooltip: 'Voltar ao topo',
                    onPressed: () => runGuarded(context, () async {
                      await controller?.scrollTo(x: 0, y: 0, animated: true);
                    }),
                    child: const Icon(Icons.vertical_align_top_rounded),
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: colors.surface,
            child: LayoutBuilder(
              builder: (context, constraints) => Wrap(
                alignment: WrapAlignment.spaceEvenly,
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
                  if (!compact)
                    IconButton(
                      tooltip: 'Avançar',
                      onPressed: canForward
                          ? () => runGuarded(context, () async {
                              await controller?.goForward();
                            })
                          : null,
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                  IconButton(
                    tooltip: 'Atualizar',
                    onPressed: () => runGuarded(context, () async {
                      await controller?.reload();
                    }),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    tooltip: 'Voltar à pesquisa inicial',
                    onPressed: () => _menu('initial'),
                    icon: const Icon(Icons.manage_search_rounded),
                  ),
                  IconButton(
                    tooltip: 'Salvar anunciante',
                    onPressed: () => _menu('advertiser'),
                    icon: Icon(
                      Icons.bookmark_add_outlined,
                      color: colors.primary,
                    ),
                  ),
                  if (!compact)
                    IconButton(
                      tooltip: 'Compartilhar link',
                      onPressed: () => _menu('share'),
                      icon: const Icon(Icons.ios_share_rounded),
                    ),
                  if (compact) _options(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _options() => PopupMenuButton<String>(
    tooltip: 'Opções da Biblioteca',
    onSelected: _menu,
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'external', child: Text('Abrir no navegador')),
      const PopupMenuItem(value: 'copy', child: Text('Copiar link')),
      const PopupMenuItem(value: 'share', child: Text('Compartilhar link')),
      const PopupMenuItem(
        value: 'advertiser',
        child: Text('Salvar anunciante'),
      ),
      const PopupMenuItem(value: 'ad', child: Text('Salvar link do anúncio')),
      const PopupMenuItem(
        value: 'search',
        child: Text('Salvar pesquisa atual'),
      ),
      const PopupMenuDivider(),
      ...ViewMode.values.map(
        (v) => CheckedPopupMenuItem(
          value: v.name,
          checked: widget.app.settings.viewMode == v,
          child: Text('Modo ${v.label.toLowerCase()}'),
        ),
      ),
      PopupMenuItem(
        value: 'collapse',
        child: Text(
          collapsed ? 'Expandir ferramentas' : 'Recolher ferramentas',
        ),
      ),
      PopupMenuItem(
        value: 'fullscreen',
        child: Text(
          widget.app.fullscreen ? 'Sair da tela cheia' : 'Tela cheia',
        ),
      ),
    ],
  );
}
