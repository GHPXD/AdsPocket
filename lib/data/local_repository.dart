import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../core/meta_ads_library_url_builder.dart';
import 'models.dart';

class LocalRepository {
  LocalRepository(this.db);
  final Database db;
  static const schemaVersion = 1;

  static Future<LocalRepository> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? '${await f.getDatabasesPath()}/adspocket.db';
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE bookmarks (id TEXT PRIMARY KEY, identity TEXT NOT NULL UNIQUE, data TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE history (id TEXT PRIMARY KEY, identity TEXT NOT NULL UNIQUE, visited_at TEXT NOT NULL, data TEXT NOT NULL)',
          );
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          // Add ordered, transactional migrations when schemaVersion increases.
          if (oldVersion != newVersion) {
            throw StateError('Migração de banco não suportada.');
          }
        },
      ),
    );
    return LocalRepository(db);
  }

  static String bookmarkIdentity(Bookmark b) =>
      '${b.kind.name}:${b.kind == BookmarkKind.image ? b.localFile : MetaAdsLibraryUrlBuilder.canonical(Uri.parse(b.url))}';
  Future<List<Bookmark>> bookmarks() async => (await db.query('bookmarks'))
      .map(
        (r) => Bookmark.fromJson(
          jsonDecode(r['data'] as String) as Map<String, dynamic>,
        ),
      )
      .toList();
  Future<List<SearchHistory>> history() async =>
      (await db.query('history', orderBy: 'visited_at DESC'))
          .map(
            (r) => SearchHistory.fromJson(
              jsonDecode(r['data'] as String) as Map<String, dynamic>,
            ),
          )
          .toList();

  Future<void> saveBookmark(Bookmark b) async {
    final identity = bookmarkIdentity(b);
    await db.transaction((tx) async {
      final rows = await tx.query(
        'bookmarks',
        where: 'identity = ?',
        whereArgs: [identity],
      );
      if (rows.isNotEmpty && rows.first['id'] != b.id) return;
      await tx.insert('bookmarks', {
        'id': b.id,
        'identity': identity,
        'data': jsonEncode(b.toJson()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> record(SearchHistory item) async {
    final identity = MetaAdsLibraryUrlBuilder.canonical(Uri.parse(item.url));
    await db.transaction((tx) async {
      final old = await tx.query(
        'history',
        where: 'identity = ?',
        whereArgs: [identity],
      );
      final data = item.toJson();
      data['id'] = old.isEmpty ? item.id : old.first['id'];
      await tx.insert('history', {
        'id': data['id'],
        'identity': identity,
        'visited_at': item.visitedAt.toIso8601String(),
        'data': jsonEncode(data),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await tx.rawDelete(
        'DELETE FROM history WHERE id NOT IN (SELECT id FROM history ORDER BY visited_at DESC LIMIT 500)',
      );
    });
  }

  Future<void> deleteBookmark(String id) =>
      db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  Future<void> deleteHistory(String id) =>
      db.delete('history', where: 'id = ?', whereArgs: [id]);
  Future<void> clearHistory() => db.delete('history');

  Future<int> merge(
    List<Bookmark> bookmarks,
    List<SearchHistory> history,
  ) async {
    var added = 0;
    await db.transaction((tx) async {
      for (final b in bookmarks) {
        // Ignore both ID and URL conflicts; import never overwrites existing data.
        final id = await tx.insert('bookmarks', {
          'id': b.id,
          'identity': bookmarkIdentity(b),
          'data': jsonEncode(b.toJson()),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        if (id > 0 &&
            (await tx.rawQuery('SELECT changes() AS n')).first['n'] == 1) {
          added++;
        }
      }
      for (final h in history) {
        await tx.insert('history', {
          'id': h.id,
          'identity': MetaAdsLibraryUrlBuilder.canonical(Uri.parse(h.url)),
          'visited_at': h.visitedAt.toIso8601String(),
          'data': jsonEncode(h.toJson()),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await tx.rawDelete(
        'DELETE FROM history WHERE id NOT IN (SELECT id FROM history ORDER BY visited_at DESC LIMIT 500)',
      );
    });
    return added;
  }

  Future<void> close() => db.close();
}
