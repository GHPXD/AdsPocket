import 'dart:convert';
import 'dart:io';
import 'package:ads_pocket/app/app_controller.dart';
import 'package:ads_pocket/core/longevity.dart';
import 'package:ads_pocket/core/meta_ads_library_url_builder.dart';
import 'package:ads_pocket/data/backup_service.dart';
import 'package:ads_pocket/data/local_repository.dart';
import 'package:ads_pocket/data/models.dart';
import 'package:ads_pocket/data/offer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const searchUrl =
    'https://www.facebook.com/ads/library/?active_status=active&ad_type=all&country=BR&q=planilha&search_type=keyword_unordered';
const pageUrl =
    'https://www.facebook.com/ads/library/?active_status=active&ad_type=all&country=BR&view_all_page_id=20531316728&search_type=page';

/// A record exactly as 1.0.0 wrote it (no 1.1.0 fields).
Map<String, Object?> v1Bookmark(String kind, String url, {String? pageId}) => {
  'id': localId(),
  'name': 'Salvo na 1.0.0 ($kind)',
  'kind': kind,
  'url': url,
  'country': 'BR',
  'addedAt': '2026-10-01T10:00:00.000Z',
  'pageId': pageId,
  'lastVisitedAt': null,
  'tags': ['antigo'],
  'notes': 'nota preservada',
  'category': '',
  'localFile': null,
};

Future<String> createV1Database(List<Map<String, Object?>> rows) async {
  final dir = await Directory.systemTemp.createTemp('adspocket-v1-');
  final path = '${dir.path}/adspocket.db';
  final db = await databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) => LocalRepository.createV1(db),
    ),
  );
  for (final r in rows) {
    final b = Bookmark.fromJson(r.cast<String, dynamic>());
    await db.insert('bookmarks', {
      'id': b.id,
      'identity':
          '${b.kind.name}:${MetaAdsLibraryUrlBuilder.canonical(Uri.parse(b.url))}',
      'data': jsonEncode(r),
    });
  }
  await db.insert('history', {
    'id': localId(),
    'identity': MetaAdsLibraryUrlBuilder.canonical(Uri.parse(searchUrl)),
    'visited_at': '2026-10-02T10:00:00.000Z',
    'data': jsonEncode({
      'id': localId(),
      'query': 'planilha',
      'type': 'keyword',
      'country': 'BR',
      'status': 'active',
      'url': searchUrl,
      'visitedAt': '2026-10-02T10:00:00.000Z',
    }),
  });
  await db.close();
  return path;
}

void main() {
  sqfliteFfiInit();

  test(
    'v1 → v2 keeps every record and reclassifies only with evidence',
    () async {
      final legacySearch = v1Bookmark('advertiser', searchUrl);
      final legacyPage = v1Bookmark('advertiser', pageUrl);
      final ad = v1Bookmark('ad', searchUrl);
      final path = await createV1Database([legacySearch, legacyPage, ad]);
      final repo = await LocalRepository.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      expect(await repo.db.getVersion(), LocalRepository.schemaVersion);
      final all = {for (final b in await repo.bookmarks()) b.id: b};
      expect(all, hasLength(3));

      final s = all[legacySearch['id']]!;
      expect(s.kind, BookmarkKind.unidentified);
      expect(s.legacyKind, 'advertiser');
      expect(s.pageId, isNull, reason: 'IDs are never invented');
      expect(s.notes, 'nota preservada');
      expect(s.tags, ['antigo']);
      expect(s.url, searchUrl);

      final p = all[legacyPage['id']]!;
      expect(p.kind, BookmarkKind.advertiser);
      expect(p.pageId, '20531316728', reason: 'evidence from the URL');
      expect(p.needsReview, isFalse);

      expect(all[ad['id']]!.kind, BookmarkKind.ad);
      expect(await repo.history(), hasLength(1));
      expect(await repo.offers(), isEmpty);

      // Manual correction keeps ID and notes.
      final fixed = s.identifyAs(
        MetaAdsLibraryUrlBuilder().build(text: '987', type: SearchType.pageId),
      );
      expect(await repo.saveBookmark(fixed), isTrue);
      final reloaded = (await repo.bookmarks()).firstWhere((b) => b.id == s.id);
      expect(reloaded.kind, BookmarkKind.advertiser);
      expect(reloaded.pageId, '987');
      expect(reloaded.sourceUrl, searchUrl);
      expect(reloaded.notes, 'nota preservada');
      await repo.close();

      // Reopening does not migrate twice.
      final again = await LocalRepository.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      expect(await again.bookmarks(), hasLength(3));
      await again.close();
    },
  );

  group('repository v2', () {
    late LocalRepository repo;
    setUp(() async {
      repo = await LocalRepository.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
    });
    tearDown(() => repo.close());

    test('an advertiser without Page ID cannot be saved', () async {
      final b = Bookmark(
        id: localId(),
        name: 'Pesquisa',
        kind: BookmarkKind.advertiser,
        url: searchUrl,
        country: 'BR',
        addedAt: DateTime.utc(2026),
      );
      await expectLater(repo.saveBookmark(b), throwsFormatException);
      final forged = Bookmark(
        id: localId(),
        name: 'ID trocado',
        kind: BookmarkKind.advertiser,
        url: pageUrl,
        country: 'BR',
        addedAt: DateTime.utc(2026),
        pageId: '111',
      );
      await expectLater(repo.saveBookmark(forged), throwsFormatException);
      expect(await repo.bookmarks(), isEmpty);
    });

    test(
      'saved search and unidentified reference coexist for one URL',
      () async {
        for (final kind in [BookmarkKind.search, BookmarkKind.unidentified]) {
          expect(
            await repo.saveBookmark(
              Bookmark(
                id: localId(),
                name: kind.label,
                kind: kind,
                url: searchUrl,
                country: 'BR',
                addedAt: DateTime.utc(2026),
              ),
            ),
            isTrue,
          );
        }
        expect(await repo.bookmarks(), hasLength(2));
      },
    );

    test('duplicate advertiser is reported, not overwritten', () async {
      Bookmark page(String name) => Bookmark(
        id: localId(),
        name: name,
        kind: BookmarkKind.advertiser,
        url: pageUrl,
        country: 'BR',
        addedAt: DateTime.utc(2026),
        pageId: '20531316728',
      );
      expect(await repo.saveBookmark(page('Primeiro')), isTrue);
      expect(await repo.saveBookmark(page('Segundo')), isFalse);
      expect((await repo.bookmarks()).single.name, 'Primeiro');
    });

    test('offers persist, update and reject duplicate ad IDs', () async {
      final o = Offer(
        id: localId(),
        name: 'Planilha',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        adId: '555',
      );
      await repo.saveOffer(o);
      await repo.saveOffer(o.copyWith(analysis: Analysis.interesting));
      expect((await repo.offers()).single.analysis, Analysis.interesting);
      final dup = Offer(
        id: localId(),
        name: 'Outra',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        url: 'https://www.facebook.com/ads/library/?id=555',
      );
      await expectLater(repo.saveOffer(dup), throwsStateError);
      expect(await repo.offers(), hasLength(1));
    });

    test('visits are recorded per advertiser and removed with it', () async {
      await repo.recordVisit('a' * 32, DateTime.utc(2026, 10, 1));
      await repo.recordVisit('a' * 32, DateTime.utc(2026, 10, 3));
      expect((await repo.visits('a' * 32)).first, DateTime.utc(2026, 10, 3));
      await repo.deleteBookmark('a' * 32);
      expect(await repo.visits('a' * 32), isEmpty);
    });
  });

  test('1.0.0 backup imports and reclassifies like the migration', () async {
    final text = jsonEncode({
      'app': 'AdsPocket',
      'version': 1,
      'exportedAt': '2026-10-10T00:00:00.000Z',
      'bookmarks': [v1Bookmark('advertiser', searchUrl)],
      'history': [],
      'settings': {
        'theme': 'dark',
        'country': 'BR',
        'status': 'active',
        'viewMode': 'standard',
        'externalBrowser': false,
        'zoom': 100,
        'shortcuts': ['E-book'],
      },
    });
    final backup = BackupService.decode(text);
    expect(backup.bookmarks.single.kind, BookmarkKind.unidentified);
    expect(backup.settings.minDays, 14, reason: 'new defaults fill gaps');
    expect(backup.settings.priceRange, PriceRange.lowTicket);
  });

  test('2.0 backup round trip includes offers, strips image paths', () {
    final o = Offer(
      id: localId(),
      name: 'Com imagem',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      imageFile: '0f8fad5b-d9cb-469f-a165-70867728950e.png',
      ocrText: 'Iniciado em 12 de outubro de 2026',
      startDate: CivilDate.of(2026, 10, 12),
      dateSource: DateSource.ocr,
    );
    final back = BackupService.decode(
      BackupService.encode([], [], const UserSettings(), [o]),
    );
    expect(back.offers.single.imageFile, isNull);
    expect(back.offers.single.ocrText, o.ocrText);
    expect(back.offers.single.startDate, CivilDate.of(2026, 10, 12));
  });

  test('session restore and settings survive a restart', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = await LocalRepository.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final app = AppController(repo, prefs);
    await app.initialize();
    await app.search('planilha', SearchType.keyword, 'BR', 'active');
    await app.observeUrl(Uri.parse(pageUrl));
    await app.updateSettings(
      app.settings.copyWith(minDays: () => 30, immersive: true),
    );
    final next = AppController(repo, prefs);
    await next.initialize();
    expect(next.currentUrl.toString(), pageUrl);
    expect(next.initialSearch?.queryParameters['q'], 'planilha');
    expect(
      MetaAdsLibraryUrlBuilder.pageId(next.lastAdvertiser!),
      '20531316728',
    );
    expect(next.settings.minDays, 30);
    expect(next.settings.immersive, isTrue);
    await next.updateSettings(next.settings.copyWith(restoreSession: false));
    final third = AppController(repo, prefs);
    await third.initialize();
    expect(third.currentUrl, MetaAdsLibraryUrlBuilder.home);
    for (final c in [app, next, third]) {
      c.dispose();
    }
    await repo.close();
  });
}
