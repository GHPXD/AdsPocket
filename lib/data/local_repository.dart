import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../core/meta_ads_library_url_builder.dart';
import 'models.dart';
import 'offer.dart';

class LocalRepository {
  LocalRepository(this.db);
  final Database db;
  static const schemaVersion = 2;

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
          await createV1(db);
          await _migrateToV2(db);
        },
        // sqflite runs onUpgrade inside a transaction: a failure rolls back
        // every step and keeps the v1 data untouched.
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 1 || newVersion > schemaVersion) {
            throw StateError('Migração de banco não suportada.');
          }
          if (oldVersion < 2) await _migrateToV2(db);
        },
      ),
    );
    return LocalRepository(db);
  }

  /// Schema shipped with 1.0.0. Kept verbatim so migrations are testable.
  static Future<void> createV1(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE bookmarks (id TEXT PRIMARY KEY, identity TEXT NOT NULL UNIQUE, data TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE history (id TEXT PRIMARY KEY, identity TEXT NOT NULL UNIQUE, visited_at TEXT NOT NULL, data TEXT NOT NULL)',
    );
  }

  static Future<void> _migrateToV2(DatabaseExecutor db) async {
    await db.execute(
      'CREATE TABLE offers (id TEXT PRIMARY KEY, identity TEXT UNIQUE, updated_at TEXT NOT NULL, data TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE TABLE visits (id INTEGER PRIMARY KEY AUTOINCREMENT, bookmark_id TEXT NOT NULL, visited_at TEXT NOT NULL)',
    );
    await db.execute(
      'CREATE INDEX visits_bookmark ON visits (bookmark_id, visited_at)',
    );
    // Reclassify 1.0.0 "advertiser" records that have no Page ID. Records are
    // rewritten in place (same ID); nothing is deleted.
    for (final row in await db.query('bookmarks')) {
      final old = Bookmark.fromJson(
        jsonDecode(row['data'] as String) as Map<String, dynamic>,
      );
      final next = old.reclassifyLegacy();
      if (identical(next, old)) continue;
      final identity = bookmarkIdentity(next);
      final clash = await db.query(
        'bookmarks',
        where: 'identity = ? AND id != ?',
        whereArgs: [identity, old.id],
      );
      await db.update(
        'bookmarks',
        {
          'identity': clash.isEmpty ? identity : 'legacy:${old.id}',
          'data': jsonEncode(next.toJson()),
        },
        where: 'id = ?',
        whereArgs: [old.id],
      );
    }
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

  /// Returns false when another record already has the same identity.
  Future<bool> saveBookmark(Bookmark b) async {
    b.validateKind();
    final identity = bookmarkIdentity(b);
    var saved = false;
    await db.transaction((tx) async {
      final rows = await tx.query(
        'bookmarks',
        where: 'identity = ?',
        whereArgs: [identity],
      );
      if (rows.isNotEmpty && rows.first['id'] != b.id) return;
      await tx.delete('bookmarks', where: 'id = ?', whereArgs: [b.id]);
      await tx.insert('bookmarks', {
        'id': b.id,
        'identity': identity,
        'data': jsonEncode(b.toJson()),
      });
      saved = true;
    });
    return saved;
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

  Future<void> deleteBookmark(String id) => db.transaction((tx) async {
    await tx.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
    await tx.delete('visits', where: 'bookmark_id = ?', whereArgs: [id]);
  });
  Future<void> deleteHistory(String id) =>
      db.delete('history', where: 'id = ?', whereArgs: [id]);
  Future<void> clearHistory() => db.delete('history');

  Future<void> recordVisit(String bookmarkId, DateTime at) => db.transaction((
    tx,
  ) async {
    await tx.insert('visits', {
      'bookmark_id': bookmarkId,
      'visited_at': at.toUtc().toIso8601String(),
    });
    // Keep the latest 100 visits per advertiser.
    await tx.rawDelete(
      'DELETE FROM visits WHERE bookmark_id = ? AND id NOT IN (SELECT id FROM visits WHERE bookmark_id = ? ORDER BY visited_at DESC LIMIT 100)',
      [bookmarkId, bookmarkId],
    );
  });

  Future<List<DateTime>> visits(String bookmarkId) async => [
    for (final r in await db.query(
      'visits',
      where: 'bookmark_id = ?',
      whereArgs: [bookmarkId],
      orderBy: 'visited_at DESC',
    ))
      DateTime.parse(r['visited_at'] as String),
  ];

  Future<List<Offer>> offers() async => [
    for (final r in await db.query('offers', orderBy: 'updated_at DESC'))
      Offer.fromJson(jsonDecode(r['data'] as String) as Map<String, dynamic>),
  ];

  /// Inserts or updates. Throws [StateError] on a duplicate ad ID or URL.
  Future<void> saveOffer(Offer o) async {
    o.validate();
    final identity = o.identity;
    await db.transaction((tx) async {
      if (identity != null) {
        final rows = await tx.query(
          'offers',
          where: 'identity = ? AND id != ?',
          whereArgs: [identity, o.id],
        );
        if (rows.isNotEmpty) {
          throw StateError('Esta referência já está catalogada.');
        }
      }
      await tx.insert('offers', {
        'id': o.id,
        'identity': identity,
        'updated_at': o.updatedAt.toIso8601String(),
        'data': jsonEncode(o.toJson()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> deleteOffer(String id) =>
      db.delete('offers', where: 'id = ?', whereArgs: [id]);

  Future<int> merge(
    List<Bookmark> bookmarks,
    List<SearchHistory> history, [
    List<Offer> offers = const [],
  ]) async {
    var added = 0;
    await db.transaction((tx) async {
      Future<bool> inserted(String table, Map<String, Object?> row) async {
        // Ignore both ID and identity conflicts; import never overwrites.
        final id = await tx.insert(
          table,
          row,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        return id > 0 &&
            (await tx.rawQuery('SELECT changes() AS n')).first['n'] == 1;
      }

      for (final b in bookmarks) {
        if (await inserted('bookmarks', {
          'id': b.id,
          'identity': bookmarkIdentity(b),
          'data': jsonEncode(b.toJson()),
        })) {
          added++;
        }
      }
      for (final o in offers) {
        if (await inserted('offers', {
          'id': o.id,
          'identity': o.identity,
          'updated_at': o.updatedAt.toIso8601String(),
          'data': jsonEncode(o.toJson()),
        })) {
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
