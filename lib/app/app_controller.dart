import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/longevity.dart';
import '../core/meta_ads_library_url_builder.dart';
import '../core/native_bridge.dart';
import '../core/ocr_engine.dart';
import '../data/backup_service.dart';
import '../data/local_repository.dart';
import '../data/models.dart';
import '../data/offer.dart';
import '../features/research/research_engine.dart';

const appVersion = '1.2.0';

/// Tab indexes of the app shell.
abstract final class Tabs {
  static const explore = 0, library = 1, saved = 2, settings = 3;
}

class AppController extends ChangeNotifier {
  AppController(this.repository, this.preferences);
  final LocalRepository repository;
  final SharedPreferences preferences;

  /// Replaceable in tests; the default runs ML Kit on the device.
  OcrEngine ocr = MlKitOcrEngine();
  UserSettings settings = const UserSettings();
  List<Bookmark> bookmarks = [];
  List<SearchHistory> history = [];
  List<Offer> offers = [];
  List<ResearchRecord> research = [];
  int tab = Tabs.explore;
  Uri currentUrl = MetaAdsLibraryUrlBuilder.home;

  /// Latest search results page (from Explore or typed inside the Library).
  Uri? initialSearch;
  Uri? lastAdvertiser;
  bool browserStarted = false;

  /// Media fullscreen requested by the website.
  bool fullscreen = false;
  int navigationSerial = 0;
  String? notice;

  /// True when the Library hides the app navigation bar.
  bool get libraryChromeHidden =>
      tab == Tabs.library &&
      (fullscreen || settings.immersive || settings.viewMode == ViewMode.feed);

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
    lastAdvertiser = _savedUrl('lastAdvertiser');
    initialSearch = _savedUrl('lastSearch');
    if (settings.restoreSession) {
      currentUrl = _savedUrl('lastUrl') ?? initialSearch ?? currentUrl;
    }
    await refresh();
  }

  Uri? _savedUrl(String key) {
    final value = preferences.getString(key);
    if (value == null) return null;
    try {
      return MetaAdsLibraryUrlBuilder.validateLibrary(value);
    } catch (_) {
      return null;
    }
  }

  Future<void> refresh() async {
    bookmarks = await repository.bookmarks();
    history = await repository.history();
    offers = await repository.offers();
    research = await repository.research();
    notifyListeners();
  }

  void selectTab(int index) {
    tab = index;
    if (index == Tabs.library) browserStarted = true;
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

  Future<void> setImmersive(bool value) =>
      updateSettings(settings.copyWith(immersive: value));

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
      media: settings.media,
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
    if (MetaAdsLibraryUrlBuilder.pageId(uri) == null) await _setSearch(uri);
    if (type == SearchType.advertiser) {
      notice =
          'Selecione a Página nos controles oficiais da Meta. O nome não identifica uma Página de forma única.';
    }
    await refresh();
    await openLibrary(uri);
  }

  Future<void> _setSearch(Uri uri) async {
    initialSearch = uri;
    await preferences.setString('lastSearch', uri.toString());
  }

  Future<void> openLibrary(Uri uri) async {
    MetaAdsLibraryUrlBuilder.validateLibrary(uri.toString());
    if (settings.externalBrowser) {
      await openExternal(uri);
      return;
    }
    currentUrl = uri;
    browserStarted = true;
    tab = Tabs.library;
    navigationSerial++;
    await observeUrl(uri);
    notifyListeners();
  }

  Future<void> observeUrl(Uri uri) async {
    if (!MetaAdsLibraryUrlBuilder.isLibrary(uri)) return;
    currentUrl = uri;
    await preferences.setString('lastUrl', uri.toString());
    if (MetaAdsLibraryUrlBuilder.pageId(uri) != null) {
      lastAdvertiser = uri;
      await preferences.setString('lastAdvertiser', uri.toString());
    } else if ((uri.queryParameters['q'] ?? '').isNotEmpty) {
      // Searches typed inside Meta's own controls become the return point.
      await _setSearch(uri);
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

  /// Returns false when the same reference is already saved.
  Future<bool> save(Bookmark b) async {
    final saved = await repository.saveBookmark(b);
    await refresh();
    return saved;
  }

  /// IDs taken from profile links and tried as Page IDs. Live tests showed
  /// they can differ from the Library Page ID, so saving one warns the user.
  final unverifiedPageIds = <String>{};

  Bookmark? savedAdvertiser(String pageId) => bookmarks
      .where((b) => b.kind == BookmarkKind.advertiser && b.pageId == pageId)
      .firstOrNull;

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
    final now = DateTime.now().toUtc();
    if (b.kind == BookmarkKind.advertiser) {
      await repository.recordVisit(b.id, now);
    }
    await save(b.copyWith(lastVisitedAt: now));
  }

  Future<List<DateTime>> visits(Bookmark b) => repository.visits(b.id);

  /// Keeps the result count Meta showed for a saved advertiser's Page.
  Future<void> noteMetaCount(String pageId, String count) async {
    final b = savedAdvertiser(pageId);
    if (b == null || count.isEmpty || count.length > 20) return;
    final now = DateTime.now().toUtc();
    final same =
        b.metaAdCount == count &&
        b.metaAdCountAt != null &&
        now.difference(b.metaAdCountAt!).inHours < 6;
    if (!same) {
      await save(b.copyWith(metaAdCount: count, metaAdCountAt: now));
    }
  }

  Set<String> get savedAdIds => {
    for (final o in offers)
      if (o.adId != null) o.adId!,
  };

  Future<void> saveOffer(Offer o) async {
    await repository.saveOffer(o);
    await refresh();
  }

  Future<void> deleteOffer(Offer o) async {
    await repository.deleteOffer(o.id);
    await refresh();
    final file = o.imageFile;
    if (file != null &&
        !offers.any((x) => x.imageFile == file) &&
        !bookmarks.any((b) => b.localFile == file)) {
      await NativeBridge.deleteImage(file);
    }
  }

  /// "Anúncios salvos no AdsPocket" for a Page; never Meta's own totals.
  List<Offer> offersForPage(String? pageId) => pageId == null
      ? <Offer>[]
      : offers.where((o) => o.pageId == pageId).toList();

  String exportBackup() =>
      BackupService.encode(bookmarks, history, settings, offers, research);
  Future<void> saveResearch(ResearchRecord record) async {
    await repository.saveResearch(record);
    await refresh();
  }

  Future<void> deleteResearch(String id) async {
    await repository.deleteResearch(id);
    await refresh();
  }

  String exportOffersCsv() => CsvExport.offers(offers, CivilDate.today());
  String exportBookmarksCsv() => CsvExport.bookmarks(bookmarks);

  Future<int> importBackup(
    BackupData backup, {
    bool restoreSettings = false,
  }) async {
    final count = await repository.merge(
      backup.bookmarks,
      backup.history,
      backup.offers,
      backup.research,
    );
    if (restoreSettings) await updateSettings(backup.settings);
    await refresh();
    return count;
  }
}
