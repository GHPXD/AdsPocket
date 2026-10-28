import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ads_pocket/app/app_controller.dart';
import 'package:ads_pocket/core/meta_ads_library_url_builder.dart';
import 'package:ads_pocket/data/backup_service.dart';
import 'package:ads_pocket/data/local_repository.dart';
import 'package:ads_pocket/data/models.dart';

Bookmark bookmark({String? id, String name = 'Minha Página'}) => Bookmark(
  id: id ?? localId(),
  name: name,
  kind: BookmarkKind.advertiser,
  url: 'https://www.facebook.com/ads/library/?view_all_page_id=123',
  country: 'BR',
  addedAt: DateTime.utc(2026),
  pageId: '123',
  tags: ['referência'],
  notes: 'Uma nota',
);
SearchHistory history({String query = 'planilha'}) => SearchHistory(
  id: localId(),
  query: query,
  type: SearchType.keyword,
  country: 'BR',
  status: 'active',
  url: MetaAdsLibraryUrlBuilder().build(text: query).toString(),
  visitedAt: DateTime.now().toUtc(),
);

void main() {
  sqfliteFfiInit();
  late LocalRepository repo;
  setUp(() async {
    repo = await LocalRepository.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });
  tearDown(() async {
    await repo.close();
  });
  test('history deduplicates repeat visits and keeps stable ID', () async {
    final first = history();
    await repo.record(first);
    await repo.record(history());
    final saved = await repo.history();
    expect(saved.length, 1);
    expect(saved.single.id, first.id);
    await repo.deleteHistory(first.id);
    expect(await repo.history(), isEmpty);
  });
  test('favorites support edit, URL deduplication and delete', () async {
    final b = bookmark();
    await repo.saveBookmark(b);
    await repo.saveBookmark(bookmark());
    expect((await repo.bookmarks()).length, 1);
    await repo.saveBookmark(
      b.copyWith(name: 'Renomeada', notes: 'Nova nota', tags: ['tag']),
    );
    final updated = (await repo.bookmarks()).single;
    expect(updated.name, 'Renomeada');
    expect(updated.notes, 'Nova nota');
    expect(updated.tags, ['tag']);
    await repo.deleteBookmark(b.id);
    expect(await repo.bookmarks(), isEmpty);
  });
  test('clearing history preserves bookmarks', () async {
    await repo.saveBookmark(bookmark());
    await repo.record(history());
    await repo.clearHistory();
    expect(await repo.history(), isEmpty);
    expect(await repo.bookmarks(), hasLength(1));
  });
  test('actual file database survives closing and reopening', () async {
    final dir = await Directory.systemTemp.createTemp('adspocket-test-');
    final path = '${dir.path}/test.db';
    final disk = await LocalRepository.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    final b = bookmark();
    await disk.saveBookmark(b);
    await disk.record(history());
    await disk.close();
    final reopened = await LocalRepository.open(
      factory: databaseFactoryFfi,
      path: path,
    );
    expect((await reopened.bookmarks()).single.id, b.id);
    expect(await reopened.history(), hasLength(1));
    await reopened.close();
    await dir.delete(recursive: true);
  });
  test('SQL input remains data', () async {
    await repo.record(history(query: "' OR 1=1; DROP TABLE history;--"));
    await repo.record(history(query: 'outra'));
    expect(await repo.history(), hasLength(2));
  });
  test('backup round trip preserves data and settings', () {
    final b = bookmark();
    final h = history();
    final text = BackupService.encode(
      [b],
      [h],
      const UserSettings(theme: 'light', zoom: 150),
    );
    final backup = BackupService.decode(text);
    expect(backup.bookmarks.single.toJson(), b.toJson());
    expect(backup.history.single.toJson(), h.toJson());
    expect(backup.settings.theme, 'light');
    expect(backup.settings.zoom, 150);
  });
  test(
    'backup rejects malformed, incompatible, unsafe and path-bearing records',
    () {
      expect(() => BackupService.decode('garbage'), throwsFormatException);
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (j) => j['version'] = 2,
        (j) => j['version'] = 1.0,
        (j) => j['bookmarks'][0]['url'] = 'javascript:alert(1)',
        (j) => j['bookmarks'][0]['pageId'] = '999',
        (j) => j['bookmarks'][0]['localFile'] = '../../secrets',
        (j) => j['settings']['zoom'] = 999,
        (j) => j['bookmarks'][0]['id'] = 'bad',
      ]) {
        final json =
            jsonDecode(
                  BackupService.encode([bookmark()], [], const UserSettings()),
                )
                as Map<String, dynamic>;
        mutate(json);
        expect(
          () => BackupService.decode(jsonEncode(json)),
          throwsFormatException,
        );
      }
    },
  );
  test('backup excludes local media', () {
    final image = Bookmark(
      id: localId(),
      name: 'Imagem',
      kind: BookmarkKind.image,
      url: '',
      country: 'BR',
      addedAt: DateTime.now(),
      localFile: 'file.jpg',
    );
    expect(
      BackupService.decode(
        BackupService.encode([image], [], const UserSettings()),
      ).bookmarks,
      isEmpty,
    );
  });
  test('merge preserves existing records on ID or URL conflicts', () async {
    final existing = bookmark();
    await repo.saveBookmark(existing);
    await repo.merge(
      [
        bookmark(id: existing.id, name: 'Sobrescrita'),
        bookmark(name: 'Duplicada'),
      ],
      [history()],
    );
    expect((await repo.bookmarks()).single.name, existing.name);
    expect(await repo.history(), hasLength(1));
  });
  test('new records import once and report count accurately', () async {
    final incoming = bookmark();
    expect(await repo.merge([incoming], []), 1);
    expect(await repo.merge([incoming], []), 0);
  });
  test('settings persist and controller search creates real history', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final app = AppController(repo, prefs);
    await app.initialize();
    await app.updateSettings(
      app.settings.copyWith(
        theme: 'light',
        country: 'PT',
        shortcuts: ['Curso'],
      ),
    );
    await app.search('planilha financeira', SearchType.keyword, 'BR', 'active');
    expect(app.tab, 1);
    expect(app.history.single.query, 'planilha financeira');
    final next = AppController(repo, prefs);
    await next.initialize();
    expect(next.settings.theme, 'light');
    expect(next.settings.country, 'PT');
    expect(next.history, hasLength(1));
    await next.openLibrary(
      MetaAdsLibraryUrlBuilder().build(text: '123', type: SearchType.pageId),
    );
    final third = AppController(repo, prefs);
    await third.initialize();
    expect(MetaAdsLibraryUrlBuilder.pageId(third.lastAdvertiser!), '123');
    app.dispose();
    next.dispose();
    third.dispose();
  });
}
