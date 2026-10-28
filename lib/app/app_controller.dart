import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/meta_ads_library_url_builder.dart';
import '../core/native_bridge.dart';
import '../data/backup_service.dart';
import '../data/local_repository.dart';
import '../data/models.dart';

class AppController extends ChangeNotifier {
  AppController(this.repository, this.preferences);
  final LocalRepository repository;
  final SharedPreferences preferences;
  UserSettings settings = const UserSettings();
  List<Bookmark> bookmarks = [];
  List<SearchHistory> history = [];
  int tab = 0;
  Uri currentUrl = MetaAdsLibraryUrlBuilder.home;
  Uri? initialSearch;
  Uri? lastAdvertiser;
  bool browserStarted = false;
  bool fullscreen = false;
  int navigationSerial = 0;
  String? notice;

  Future<void> initialize() async {
    final saved = preferences.getString('settings.v1');
    if (saved != null) {
      try {
        settings = BackupService.validateSettings(
          jsonDecode(saved) as Map<String, dynamic>,
        );
      } catch (_) {
        notice = 'As configurações foram restauradas para o padrão.';
      }
    }
    final last = preferences.getString('lastAdvertiser');
    if (last != null) {
      try {
        lastAdvertiser = MetaAdsLibraryUrlBuilder.validateLibrary(last);
      } catch (_) {
        /* Ignore invalid saved URL. */
      }
    }
    await refresh();
  }

  Future<void> refresh() async {
    bookmarks = await repository.bookmarks();
    history = await repository.history();
    notifyListeners();
  }

  void selectTab(int index) {
    tab = index;
    if (index == 1) browserStarted = true;
    notifyListeners();
  }

  void setFullscreen(bool value) {
    fullscreen = value;
    notifyListeners();
  }

  void showNotice(String message) {
    notice = message;
    notifyListeners();
  }

  void clearNotice() {
    notice = null;
  }

  Future<void> updateSettings(UserSettings value) async {
    BackupService.validateSettings(value.toJson());
    final success = await preferences.setString(
      'settings.v1',
      jsonEncode(value.toJson()),
    );
    if (!success) throw StateError('Não foi possível salvar as configurações.');
    settings = value;
    notifyListeners();
  }

  Future<void> search(
    String text,
    SearchType type,
    String country,
    String status,
  ) async {
    final uri = MetaAdsLibraryUrlBuilder().build(
      text: text,
      type: type,
      country: country,
      status: status,
    );
    await repository.record(
      SearchHistory(
        id: localId(),
        query: MetaAdsLibraryUrlBuilder.normalizeText(text),
        type: type,
        country: country,
        status: status,
        url: uri.toString(),
        visitedAt: DateTime.now().toUtc(),
      ),
    );
    initialSearch = uri;
    if (type == SearchType.advertiser) {
      notice =
          'Selecione a Página nos controles oficiais da Meta. O nome não identifica uma Página de forma única.';
    }
    await refresh();
    await openLibrary(uri);
  }

  Future<void> openLibrary(Uri uri) async {
    MetaAdsLibraryUrlBuilder.validateLibrary(uri.toString());
    if (settings.externalBrowser) {
      await openExternal(uri);
      return;
    }
    currentUrl = uri;
    browserStarted = true;
    tab = 1;
    navigationSerial++;
    await observeUrl(uri);
    notifyListeners();
  }

  Future<void> observeUrl(Uri uri) async {
    if (!MetaAdsLibraryUrlBuilder.isLibrary(uri)) return;
    currentUrl = uri;
    if (MetaAdsLibraryUrlBuilder.pageId(uri) != null) {
      lastAdvertiser = uri;
      await preferences.setString('lastAdvertiser', uri.toString());
    }
    notifyListeners();
  }

  Future<void> openExternal(Uri uri) async {
    if (MetaAdsLibraryUrlBuilder.safeHttps(uri.toString()) == null) {
      throw const FormatException(
        'Apenas links HTTPS seguros podem ser abertos.',
      );
    }
    final mode = await supportsLaunchMode(LaunchMode.inAppBrowserView)
        ? LaunchMode.inAppBrowserView
        : LaunchMode.externalApplication;
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    var launched = android && mode == LaunchMode.externalApplication
        ? await NativeBridge.openBrowser(uri)
        : await launchUrl(
            uri,
            mode: mode,
            browserConfiguration: const BrowserConfiguration(showTitle: true),
          );
    if (!launched && android && mode != LaunchMode.externalApplication) {
      launched = await NativeBridge.openBrowser(uri);
    }
    if (!launched) {
      throw StateError(
        'Nenhum navegador disponível. Copie o link e abra manualmente.',
      );
    }
  }

  Future<void> repeat(SearchHistory h) =>
      search(h.query, h.type, h.country, h.status);
  Future<void> save(Bookmark b) async {
    await repository.saveBookmark(b);
    await refresh();
  }

  Future<void> remove(Bookmark b) async {
    await repository.deleteBookmark(b.id);
    await refresh();
    if (b.kind == BookmarkKind.image && b.localFile != null) {
      await NativeBridge.deleteImage(b.localFile!);
    }
  }

  Future<void> deleteHistory(SearchHistory h) async {
    await repository.deleteHistory(h.id);
    await refresh();
  }

  Future<void> clearHistory() async {
    await repository.clearHistory();
    await refresh();
  }

  Future<void> visit(Bookmark b) async {
    if (b.kind == BookmarkKind.offer) {
      await openExternal(Uri.parse(b.url));
    } else if (b.kind != BookmarkKind.image) {
      await openLibrary(Uri.parse(b.url));
    }
    await save(b.copyWith(lastVisitedAt: DateTime.now().toUtc()));
  }

  String exportBackup() => BackupService.encode(bookmarks, history, settings);
  Future<int> importBackup(
    BackupData backup, {
    bool restoreSettings = false,
  }) async {
    final count = await repository.merge(backup.bookmarks, backup.history);
    if (restoreSettings) await updateSettings(backup.settings);
    await refresh();
    return count;
  }
}
