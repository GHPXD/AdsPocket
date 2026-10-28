import 'dart:convert';
import '../core/meta_ads_library_url_builder.dart';
import 'models.dart';

class BackupData {
  const BackupData(this.bookmarks, this.history, this.settings);
  final List<Bookmark> bookmarks;
  final List<SearchHistory> history;
  final UserSettings settings;
}

class BackupService {
  static const maxBytes = 5 * 1024 * 1024;
  static String encode(
    List<Bookmark> bookmarks,
    List<SearchHistory> history,
    UserSettings settings,
  ) {
    final result = const JsonEncoder.withIndent('  ').convert({
      'app': 'AdsPocket',
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'bookmarks': bookmarks
          .where((b) => b.kind != BookmarkKind.image)
          .map((b) => b.toJson())
          .toList(),
      'history': history.map((h) => h.toJson()).toList(),
      'settings': settings.toJson(),
    });
    if (utf8.encode(result).length > maxBytes) {
      throw const FormatException('O backup ultrapassa 5 MB.');
    }
    return result;
  }

  static BackupData decode(String text) {
    try {
      if (text.length > maxBytes || utf8.encode(text).length > maxBytes) {
        throw const FormatException();
      }
      final j = jsonDecode(text) as Map<String, dynamic>;
      if (j['app'] != 'AdsPocket' ||
          j['version'] != 1 ||
          j['version'] is! int) {
        throw const FormatException();
      }
      final bs = j['bookmarks'] as List;
      final hs = j['history'] as List;
      if (bs.length > 10000 || hs.length > 500) throw const FormatException();
      final bookmarks = bs
          .map((v) => Bookmark.fromJson(v as Map<String, dynamic>))
          .toList();
      final history = hs
          .map((v) => SearchHistory.fromJson(v as Map<String, dynamic>))
          .toList();
      for (final b in bookmarks) {
        _id(b.id);
        _text(b.name, 200, nonEmpty: true);
        _text(b.notes, 10000);
        _text(b.category, 200);
        if (!countries.containsKey(b.country) ||
            b.tags.length > 30 ||
            b.localFile != null ||
            b.kind == BookmarkKind.image) {
          throw const FormatException();
        }
        for (final tag in b.tags) {
          _text(tag, 80);
        }
        final uri = b.kind == BookmarkKind.offer
            ? MetaAdsLibraryUrlBuilder.safeHttps(b.url)
            : MetaAdsLibraryUrlBuilder.validateLibrary(b.url);
        if (uri == null ||
            (b.pageId != null &&
                b.pageId != MetaAdsLibraryUrlBuilder.pageId(uri))) {
          throw const FormatException();
        }
      }
      for (final h in history) {
        _id(h.id);
        _text(h.query, 8192, nonEmpty: true);
        MetaAdsLibraryUrlBuilder.validateLibrary(h.url);
        if (!countries.containsKey(h.country) ||
            !{'active', 'all'}.contains(h.status)) {
          throw const FormatException();
        }
      }
      final settings = validateSettings(j['settings'] as Map<String, dynamic>);
      return BackupData(bookmarks, history, settings);
    } catch (_) {
      throw const FormatException(
        'Backup inválido. Use um JSON AdsPocket versão 1, com até 5 MB. Nenhum dado foi importado.',
      );
    }
  }

  static UserSettings validateSettings(Map<String, dynamic> j) {
    final s = UserSettings.fromJson(j);
    if (!{'dark', 'light', 'system'}.contains(s.theme) ||
        !countries.containsKey(s.country) ||
        !{'active', 'all'}.contains(s.status) ||
        s.zoom < 75 ||
        s.zoom > 200 ||
        s.shortcuts.length > 30) {
      throw const FormatException();
    }
    for (final shortcut in s.shortcuts) {
      _text(shortcut, 80, nonEmpty: true);
    }
    return s;
  }

  static void _id(String id) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) throw const FormatException();
  }

  static void _text(String value, int max, {bool nonEmpty = false}) {
    if (value.length > max ||
        (nonEmpty && value.trim().isEmpty) ||
        value.contains('\u0000')) {
      throw const FormatException();
    }
  }
}
