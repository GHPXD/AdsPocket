import 'dart:convert';
import '../core/longevity.dart';
import '../core/meta_ads_library_url_builder.dart';
import 'models.dart';
import 'offer.dart';
import '../features/research/research_engine.dart';

class BackupData {
  const BackupData(
    this.bookmarks,
    this.history,
    this.settings, [
    this.offers = const [],
    this.research = const [],
  ]);
  final List<Bookmark> bookmarks;
  final List<SearchHistory> history;
  final UserSettings settings;
  final List<Offer> offers;
  final List<ResearchRecord> research;
}

class BackupService {
  static const maxBytes = 5 * 1024 * 1024;
  static const version = 3;
  static String encode(
    List<Bookmark> bookmarks,
    List<SearchHistory> history,
    UserSettings settings, [
    List<Offer> offers = const [],
    List<ResearchRecord> research = const [],
  ]) {
    final result = const JsonEncoder.withIndent('  ').convert({
      'app': 'AdsPocket',
      'version': version,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'bookmarks': bookmarks
          .where((b) => b.kind != BookmarkKind.image)
          .map((b) => b.toJson())
          .toList(),
      // Images stay on the device; the JSON keeps text and references only.
      'offers': offers.map((o) => o.toJson()..['imageFile'] = null).toList(),
      'history': history.map((h) => h.toJson()).toList(),
      'settings': settings.toJson(),
      'research': research.map((r) {
        r.validate();
        return r.toJson();
      }).toList(),
    });
    if (utf8.encode(result).length > maxBytes) {
      throw const FormatException('O backup ultrapassa 5 MB.');
    }
    return result;
  }

  /// Accepts 1.0.0 (version 1) and 1.1.0 (version 2) backups.
  static BackupData decode(String text) {
    try {
      if (text.length > maxBytes || utf8.encode(text).length > maxBytes) {
        throw const FormatException();
      }
      final j = jsonDecode(text) as Map<String, dynamic>;
      final v = j['version'];
      if (j['app'] != 'AdsPocket' || v is! int || v < 1 || v > version) {
        throw const FormatException();
      }
      final bs = j['bookmarks'] as List;
      final hs = j['history'] as List;
      final os = v >= 2 ? j['offers'] as List : const [];
      final rs = v >= 3 ? j['research'] as List : const [];
      if (rs.length > 10000) throw const FormatException();
      final research = rs
          .map((r) => ResearchRecord.fromJson(r as Map<String, dynamic>))
          .toList();
      if (bs.length > 10000 || hs.length > 500 || os.length > 10000) {
        throw const FormatException();
      }
      final bookmarks = bs
          .map((v) => Bookmark.fromJson(v as Map<String, dynamic>))
          .toList();
      final history = hs
          .map((v) => SearchHistory.fromJson(v as Map<String, dynamic>))
          .toList();
      final offers = os
          .map((v) => Offer.fromJson(v as Map<String, dynamic>))
          .toList();
      for (final b in bookmarks) {
        _id(b.id);
        _text(b.name, 200, nonEmpty: true);
        _text(b.notes, 10000);
        _text(b.category, 200);
        _text(b.niche, 200);
        _text(b.metaAdCount ?? '', 20);
        if (!countries.containsKey(b.country) ||
            b.tags.length > 30 ||
            b.localFile != null ||
            b.kind == BookmarkKind.image ||
            (b.legacyKind != null && b.legacyKind != 'advertiser')) {
          throw const FormatException();
        }
        for (final tag in b.tags) {
          _text(tag, 80);
        }
        if (b.sourceUrl != null) {
          MetaAdsLibraryUrlBuilder.validateLibrary(b.sourceUrl!);
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
      for (final o in offers) {
        o.validate();
        if (o.imageFile != null) throw const FormatException();
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
      return BackupData(
        // Old "advertiser" records without a Page ID are reclassified exactly
        // like the database migration does.
        [for (final b in bookmarks) b.reclassifyLegacy()],
        history,
        settings,
        offers,
        research,
      );
    } catch (_) {
      throw const FormatException(
        'Backup inválido. Use um JSON AdsPocket (versão 1, 2 ou 3), com até 5 MB. Nenhum dado foi importado.',
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
        s.shortcuts.length > 30 ||
        (s.minDays != null &&
            (s.minDays! < 0 || s.minDays! > LongevityFilter.maxDays)) ||
        !s.priceRange.valid ||
        s.favoriteRanges.length > 10 ||
        s.favoriteRanges.any((r) => !r.valid) ||
        !{'all', 'image', 'video'}.contains(s.media) ||
        (s.minAds != null && (s.minAds! < 1 || s.minAds! > 1000)) ||
        s.scrollTarget < 5 ||
        s.scrollTarget > 200) {
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

/// CSV (RFC 4180, `;` separator for spreadsheet apps in pt-BR). Values that a
/// spreadsheet could run as a formula are prefixed with an apostrophe.
class CsvExport {
  static String _cell(Object? value) {
    var s = value?.toString() ?? '';
    if (s.isNotEmpty && '=+-@\t\r'.contains(s[0])) s = "'$s";
    return s.contains(RegExp(r'[;"\r\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  static String _rows(List<List<Object?>> rows) =>
      '﻿${rows.map((r) => r.map(_cell).join(';')).join('\r\n')}\r\n';

  static String offers(List<Offer> offers, CivilDate today) => _rows([
    [
      'nome',
      'anunciante',
      'page_id',
      'id_anuncio',
      'url',
      'nicho',
      'categoria',
      'preco',
      'moeda',
      'origem_preco',
      'data_inicio',
      'origem_data',
      'idade_dias',
      'status',
      'ultima_verificacao',
      'midia',
      'pagina_vendas',
      'situacao',
      'hook',
      'headline',
      'cta',
      'angulo',
      'variacoes_conhecidas',
      'tags',
      'notas',
    ],
    for (final o in offers)
      [
        o.name,
        o.advertiser,
        o.pageId,
        o.adId,
        o.url,
        o.niche,
        o.category,
        o.priceCents == null
            ? null
            : '${o.priceCents! ~/ 100},${(o.priceCents! % 100).toString().padLeft(2, '0')}',
        o.currency,
        o.priceSource.label,
        o.startDate?.toIso(),
        o.dateSource?.label,
        o.age(today),
        o.status.label,
        o.lastCheckedAt?.toIso8601String(),
        o.mediaType.label,
        o.salesUrl,
        o.analysis.label,
        o.hook,
        o.headline,
        o.cta,
        o.angle,
        o.variations,
        o.tags.join(', '),
        o.notes,
      ],
  ]);

  static String bookmarks(List<Bookmark> bookmarks) => _rows([
    [
      'nome',
      'tipo',
      'page_id',
      'url',
      'pais',
      'nicho',
      'tags',
      'notas',
      'ultima_visita',
    ],
    for (final b in bookmarks.where((b) => b.kind != BookmarkKind.image))
      [
        b.name,
        b.kind.label,
        b.pageId,
        b.url,
        b.country,
        b.niche,
        b.tags.join(', '),
        b.notes,
        b.lastVisitedAt?.toIso8601String(),
      ],
  ]);
}

/// Entry policy for a future ZIP backup with images (not exported yet).
/// Validating names before extraction blocks path traversal and duplicates.
class ArchivePolicy {
  static const maxEntries = 2001;
  static const maxImageBytes = 15 * 1024 * 1024;
  static const maxTotalBytes = 300 * 1024 * 1024;
  static final _image = RegExp(
    r'^images/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\.(png|jpg|webp)$',
  );

  /// Throws [FormatException] when any entry is unsafe.
  static void validate(List<(String name, int size)> entries) {
    if (entries.isEmpty || entries.length > maxEntries) {
      throw const FormatException('Arquivo de backup com entradas inválidas.');
    }
    final seen = <String>{};
    var total = 0;
    var hasJson = false;
    for (final (name, size) in entries) {
      final isJson = name == 'backup.json';
      if (name.contains('\\') ||
          name.contains('\u0000') ||
          name.startsWith('/') ||
          name.contains('..') ||
          RegExp(r'^[a-zA-Z]:').hasMatch(name) ||
          !(isJson || _image.hasMatch(name))) {
        throw FormatException('Caminho não permitido: $name');
      }
      if (!seen.add(name.toLowerCase())) {
        throw FormatException('Arquivo duplicado: $name');
      }
      if (size < 0 ||
          size > (isJson ? BackupService.maxBytes : maxImageBytes)) {
        throw FormatException('Tamanho não permitido: $name');
      }
      total += size;
      hasJson |= isJson;
    }
    if (!hasJson || total > maxTotalBytes) {
      throw const FormatException('Backup incompleto ou grande demais.');
    }
  }
}
