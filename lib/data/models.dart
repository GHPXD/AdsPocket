import 'dart:math';
import '../core/meta_ads_library_url_builder.dart';
import 'offer.dart';

String localId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

enum BookmarkKind {
  advertiser('Anunciantes'),
  search('Pesquisas'),
  ad('Anúncios'),
  offer('Lojas e ofertas'),
  image('Imagens'),
  unidentified('Não identificadas');

  const BookmarkKind(this.label);
  final String label;
}

class Bookmark {
  const Bookmark({
    required this.id,
    required this.name,
    required this.kind,
    required this.url,
    required this.country,
    required this.addedAt,
    this.pageId,
    this.lastVisitedAt,
    this.tags = const [],
    this.notes = '',
    this.category = '',
    this.localFile,
    this.niche = '',
    this.watchlist = false,
    this.legacyKind,
    this.sourceUrl,
    this.metaAdCount,
    this.metaAdCountAt,
  });
  final String id, name, url, country, notes, category, niche;

  /// Result count Meta displayed for this Page (e.g. "~180") and when it was
  /// seen. It is Meta's own label, never a number computed by the app.
  final String? metaAdCount;
  final DateTime? metaAdCountAt;
  final BookmarkKind kind;
  final String? pageId, localFile;

  /// Original kind of a v1 record reclassified during migration.
  final String? legacyKind;

  /// URL the user was on when a Page ID was typed manually.
  final String? sourceUrl;
  final bool watchlist;
  final DateTime addedAt;
  final DateTime? lastVisitedAt;
  final List<String> tags;

  bool get needsReview => legacyKind != null;

  Bookmark copyWith({
    String? name,
    String? notes,
    List<String>? tags,
    String? category,
    String? niche,
    bool? watchlist,
    DateTime? lastVisitedAt,
    String? metaAdCount,
    DateTime? metaAdCountAt,
  }) => Bookmark(
    id: id,
    name: name ?? this.name,
    kind: kind,
    url: url,
    country: country,
    addedAt: addedAt,
    pageId: pageId,
    lastVisitedAt: lastVisitedAt ?? this.lastVisitedAt,
    tags: tags ?? this.tags,
    notes: notes ?? this.notes,
    category: category ?? this.category,
    localFile: localFile,
    niche: niche ?? this.niche,
    watchlist: watchlist ?? this.watchlist,
    legacyKind: legacyKind,
    sourceUrl: sourceUrl,
    metaAdCount: metaAdCount ?? this.metaAdCount,
    metaAdCountAt: metaAdCountAt ?? this.metaAdCountAt,
  );

  /// Turns a reference into an identified advertiser, keeping ID, name, tags
  /// and notes. The previous URL is kept as [sourceUrl].
  Bookmark identifyAs(Uri pageUrl) {
    final id = MetaAdsLibraryUrlBuilder.pageId(pageUrl);
    if (id == null) {
      throw const FormatException('A URL não contém um Page ID válido.');
    }
    return Bookmark(
      id: this.id,
      name: name,
      kind: BookmarkKind.advertiser,
      url: pageUrl.toString(),
      country: country,
      addedAt: addedAt,
      pageId: id,
      lastVisitedAt: lastVisitedAt,
      tags: tags,
      notes: notes,
      category: category,
      niche: niche,
      watchlist: watchlist,
      sourceUrl: url == pageUrl.toString() ? sourceUrl : url,
    );
  }

  /// v1 allowed "advertiser" records without a Page ID. Reclassify only with
  /// evidence from the saved URL; never invent an ID.
  Bookmark reclassifyLegacy() {
    if (kind != BookmarkKind.advertiser) return this;
    final fromUrl = MetaAdsLibraryUrlBuilder.pageId(Uri.tryParse(url) ?? Uri());
    if (fromUrl != null) {
      return pageId == fromUrl ? this : identifyAs(Uri.parse(url));
    }
    return Bookmark(
      id: id,
      name: name,
      kind: BookmarkKind.unidentified,
      url: url,
      country: country,
      addedAt: addedAt,
      lastVisitedAt: lastVisitedAt,
      tags: tags,
      notes: notes,
      category: category,
      niche: niche,
      watchlist: watchlist,
      legacyKind: BookmarkKind.advertiser.name,
    );
  }

  /// An identified advertiser always carries the Page ID from its URL.
  void validateKind() {
    if (kind == BookmarkKind.advertiser &&
        (pageId == null ||
            pageId !=
                MetaAdsLibraryUrlBuilder.pageId(Uri.tryParse(url) ?? Uri()))) {
      throw const FormatException(
        'Não foi possível identificar uma Página nesta URL.',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'url': url,
    'country': country,
    'addedAt': addedAt.toIso8601String(),
    'pageId': pageId,
    'lastVisitedAt': lastVisitedAt?.toIso8601String(),
    'tags': tags,
    'notes': notes,
    'category': category,
    'localFile': localFile,
    'niche': niche,
    'watchlist': watchlist,
    'legacyKind': legacyKind,
    'sourceUrl': sourceUrl,
    'metaAdCount': metaAdCount,
    'metaAdCountAt': metaAdCountAt?.toIso8601String(),
  };

  factory Bookmark.fromJson(Map<String, dynamic> j) => Bookmark(
    id: j['id'] as String,
    name: j['name'] as String,
    kind: BookmarkKind.values.byName(j['kind'] as String),
    url: j['url'] as String,
    country: j['country'] as String,
    addedAt: DateTime.parse(j['addedAt'] as String),
    pageId: j['pageId'] as String?,
    lastVisitedAt: j['lastVisitedAt'] == null
        ? null
        : DateTime.parse(j['lastVisitedAt'] as String),
    tags: List<String>.from(j['tags'] as List),
    notes: j['notes'] as String? ?? '',
    category: j['category'] as String? ?? '',
    localFile: j['localFile'] as String?,
    niche: j['niche'] as String? ?? '',
    watchlist: j['watchlist'] as bool? ?? false,
    legacyKind: j['legacyKind'] as String?,
    sourceUrl: j['sourceUrl'] as String?,
    metaAdCount: j['metaAdCount'] as String?,
    metaAdCountAt: j['metaAdCountAt'] == null
        ? null
        : DateTime.parse(j['metaAdCountAt'] as String),
  );
}

// Explicit domain names; shared fields and persistence are unified in Bookmark.
typedef AdvertiserBookmark = Bookmark;
typedef SavedSearch = Bookmark;
typedef SavedAdReference = Bookmark;

class SearchHistory {
  const SearchHistory({
    required this.id,
    required this.query,
    required this.type,
    required this.country,
    required this.status,
    required this.url,
    required this.visitedAt,
  });
  final String id, query, country, status, url;
  final SearchType type;
  final DateTime visitedAt;
  Map<String, Object?> toJson() => {
    'id': id,
    'query': query,
    'type': type.name,
    'country': country,
    'status': status,
    'url': url,
    'visitedAt': visitedAt.toIso8601String(),
  };
  factory SearchHistory.fromJson(Map<String, dynamic> j) => SearchHistory(
    id: j['id'] as String,
    query: j['query'] as String,
    type: SearchType.values.byName(j['type'] as String),
    country: j['country'] as String,
    status: j['status'] as String,
    url: j['url'] as String,
    visitedAt: DateTime.parse(j['visitedAt'] as String),
  );
}

enum ViewMode {
  standard('Padrão'),
  compact('Compacto'),

  /// Only the ads: no app bars around the page, one floating control.
  feed('Feed'),
  desktop('Desktop');

  const ViewMode(this.label);
  final String label;
}

class UserSettings {
  const UserSettings({
    this.theme = 'dark',
    this.country = 'BR',
    this.status = 'active',
    this.viewMode = ViewMode.standard,
    this.externalBrowser = false,
    this.zoom = 100,
    this.shortcuts = const [
      'E-book',
      'Planilha',
      'Curso online',
      'Pack digital',
      'Acesso imediato',
      'Templates',
      'Manual completo',
    ],
    this.immersive = false,
    this.restoreSession = true,
    this.minDays = 14,
    this.includeUndated = true,
    this.priceRange = PriceRange.lowTicket,
    this.favoriteRanges = const [PriceRange.lowTicket],
    this.assistant = true,
    this.minAds,
    this.media = 'all',
    this.scrollTarget = 20,
  });

  /// Library assistant: card badges, one-tap save, local filter, auto-scroll.
  final bool assistant;

  /// Minimum "N ads use this creative and text" shown by Meta on a card;
  /// null means any. Active-only is the search default (`active_status`).
  final int? minAds;

  /// Meta `media_type` for new searches: all, image or video.
  final String media;

  /// Cards to find before auto-scroll stops.
  final int scrollTarget;
  final String theme, country, status;
  final ViewMode viewMode;
  final bool externalBrowser, immersive, restoreSession, includeUndated;
  final int zoom;

  /// Default local longevity filter in days; null means no filter.
  final int? minDays;
  final PriceRange priceRange;
  final List<PriceRange> favoriteRanges;
  final List<String> shortcuts;
  UserSettings copyWith({
    String? theme,
    String? country,
    String? status,
    ViewMode? viewMode,
    bool? externalBrowser,
    int? zoom,
    List<String>? shortcuts,
    bool? immersive,
    bool? restoreSession,
    int? Function()? minDays,
    bool? includeUndated,
    PriceRange? priceRange,
    List<PriceRange>? favoriteRanges,
    bool? assistant,
    int? Function()? minAds,
    String? media,
    int? scrollTarget,
  }) => UserSettings(
    theme: theme ?? this.theme,
    country: country ?? this.country,
    status: status ?? this.status,
    viewMode: viewMode ?? this.viewMode,
    externalBrowser: externalBrowser ?? this.externalBrowser,
    zoom: zoom ?? this.zoom,
    shortcuts: shortcuts ?? this.shortcuts,
    immersive: immersive ?? this.immersive,
    restoreSession: restoreSession ?? this.restoreSession,
    minDays: minDays == null ? this.minDays : minDays(),
    includeUndated: includeUndated ?? this.includeUndated,
    priceRange: priceRange ?? this.priceRange,
    favoriteRanges: favoriteRanges ?? this.favoriteRanges,
    assistant: assistant ?? this.assistant,
    minAds: minAds == null ? this.minAds : minAds(),
    media: media ?? this.media,
    scrollTarget: scrollTarget ?? this.scrollTarget,
  );
  Map<String, Object?> toJson() => {
    'theme': theme,
    'country': country,
    'status': status,
    'viewMode': viewMode.name,
    'externalBrowser': externalBrowser,
    'zoom': zoom,
    'shortcuts': shortcuts,
    'immersive': immersive,
    'restoreSession': restoreSession,
    'minDays': minDays,
    'includeUndated': includeUndated,
    'priceRange': priceRange.toJson(),
    'favoriteRanges': favoriteRanges.map((r) => r.toJson()).toList(),
    'assistant': assistant,
    'minAds': minAds,
    'media': media,
    'scrollTarget': scrollTarget,
  };

  /// Fields added in 1.1.0 are optional so 1.0.0 settings and backups load.
  factory UserSettings.fromJson(Map<String, dynamic> j) => UserSettings(
    theme: j['theme'] as String,
    country: j['country'] as String,
    status: j['status'] as String,
    viewMode: ViewMode.values.byName(j['viewMode'] as String),
    externalBrowser: j['externalBrowser'] as bool,
    zoom: j['zoom'] as int,
    shortcuts: List<String>.from(j['shortcuts'] as List),
    immersive: j['immersive'] as bool? ?? false,
    restoreSession: j['restoreSession'] as bool? ?? true,
    minDays: j.containsKey('minDays') ? j['minDays'] as int? : 14,
    includeUndated: j['includeUndated'] as bool? ?? true,
    priceRange: j['priceRange'] == null
        ? PriceRange.lowTicket
        : PriceRange.fromJson(j['priceRange'] as Map<String, dynamic>),
    favoriteRanges: j['favoriteRanges'] == null
        ? const [PriceRange.lowTicket]
        : [
            for (final r in j['favoriteRanges'] as List)
              PriceRange.fromJson(r as Map<String, dynamic>),
          ],
    assistant: j['assistant'] as bool? ?? true,
    minAds: j['minAds'] as int?,
    media: j['media'] as String? ?? 'all',
    scrollTarget: j['scrollTarget'] as int? ?? 20,
  );
}
