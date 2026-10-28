import 'dart:math';
import '../core/meta_ads_library_url_builder.dart';

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
  image('Imagens');

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
  });
  final String id, name, url, country, notes, category;
  final BookmarkKind kind;
  final String? pageId, localFile;
  final DateTime addedAt;
  final DateTime? lastVisitedAt;
  final List<String> tags;

  Bookmark copyWith({
    String? name,
    String? notes,
    List<String>? tags,
    String? category,
    DateTime? lastVisitedAt,
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
  );

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
  });
  final String theme, country, status;
  final ViewMode viewMode;
  final bool externalBrowser;
  final int zoom;
  final List<String> shortcuts;
  UserSettings copyWith({
    String? theme,
    String? country,
    String? status,
    ViewMode? viewMode,
    bool? externalBrowser,
    int? zoom,
    List<String>? shortcuts,
  }) => UserSettings(
    theme: theme ?? this.theme,
    country: country ?? this.country,
    status: status ?? this.status,
    viewMode: viewMode ?? this.viewMode,
    externalBrowser: externalBrowser ?? this.externalBrowser,
    zoom: zoom ?? this.zoom,
    shortcuts: shortcuts ?? this.shortcuts,
  );
  Map<String, Object?> toJson() => {
    'theme': theme,
    'country': country,
    'status': status,
    'viewMode': viewMode.name,
    'externalBrowser': externalBrowser,
    'zoom': zoom,
    'shortcuts': shortcuts,
  };
  factory UserSettings.fromJson(Map<String, dynamic> j) => UserSettings(
    theme: j['theme'] as String,
    country: j['country'] as String,
    status: j['status'] as String,
    viewMode: ViewMode.values.byName(j['viewMode'] as String),
    externalBrowser: j['externalBrowser'] as bool,
    zoom: j['zoom'] as int,
    shortcuts: List<String>.from(j['shortcuts'] as List),
  );
}
