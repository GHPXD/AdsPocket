import 'dart:convert';
import 'package:flutter/services.dart';
import '../../core/meta_ads_library_url_builder.dart';
import '../../data/models.dart';
import '../../data/offer.dart';

String researchKey(String value) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  var s = String.fromCharCodes(
    value.runes.map((c) => c >= 0xff01 && c <= 0xff5e ? c - 0xfee0 : c),
  ).toLowerCase();
  for (var i = 0; i < from.length; i++) {
    s = s.replaceAll(from[i], to[i]);
  }
  return s
      .replaceAll(RegExp(r'[\u0300-\u036f\u200b-\u200d\ufeff]'), '')
      .replaceAll(RegExp(r'r\$\s*'), r'r$ ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

class ResearchCatalog {
  ResearchCatalog(this.data);
  final Map<String, dynamic> data;
  static Future<ResearchCatalog> load() async => ResearchCatalog(
    jsonDecode(await rootBundle.loadString('assets/knowledge/catalog.v1.json'))
        as Map<String, dynamic>,
  );
  List<Map<String, dynamic>> get niches =>
      (data['niches'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get terms =>
      (data['terms'] as List).cast<Map<String, dynamic>>();
  List<String> get formats => (data['formats'] as List).cast<String>();
  List<Map<String, dynamic>> get presets =>
      (data['presets'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> find(String query, {String? niche}) => terms
      .where(
        (t) =>
            (niche == null || t['niche'] == niche) &&
            researchKey(t['text'] as String).contains(researchKey(query)),
      )
      .toList();
}

class KeywordMiningEngine {
  List<String> generate({
    required String niche,
    String subniche = '',
    String problem = '',
    String format = '',
    String commercial = '',
    String benefit = '',
    String delivery = '',
    String update = '',
    List<String> variants = const [],
    int limit = 12,
    List<String> excluded = const [],
  }) {
    if (limit < 1 || limit > 30) {
      throw const FormatException('Limite de 1 a 30 sugestões.');
    }
    final subject = subniche.isNotEmpty ? subniche : niche;
    final candidates = [
      if (subject.isNotEmpty && format.isNotEmpty) '$format $subject',
      if (problem.isNotEmpty && format.isNotEmpty) '$format $problem',
      if (benefit.isNotEmpty && format.isNotEmpty) '$format $benefit',
      if (subject.isNotEmpty) subject,
      if (format.isNotEmpty) format,
      if (subject.isNotEmpty && commercial.isNotEmpty) '$subject $commercial',
      if (format.isNotEmpty && commercial.isNotEmpty) '$format $commercial',
      if (niche.isNotEmpty && subniche.isNotEmpty && format.isNotEmpty)
        '$format $niche',
      if (format.isNotEmpty && delivery.isNotEmpty) '$format $delivery',
      if (format.isNotEmpty && update.isNotEmpty) '$format $update',
      for (final variant in variants.take(8)) ...[
        if (subject.isNotEmpty) '$variant $subject',
        variant,
      ],
      if (problem.isNotEmpty) problem,
    ];
    final seen = <String>{};
    return candidates
        .map(MetaAdsLibraryUrlBuilder.normalizeText)
        .where(
          (s) =>
              s.isNotEmpty &&
              s.length <= 2000 &&
              !excluded.any(
                (e) =>
                    e.trim().isNotEmpty &&
                    researchKey(s).contains(researchKey(e)),
              ) &&
              seen.add(researchKey(s)),
        )
        .take(limit)
        .toList();
  }
}

class MiningSource {
  const MiningSource(
    this.id,
    this.name,
    this.category,
    this.url, {
    this.query = false,
    this.authRequired = false,
    this.paidAccess = false,
  });
  final String id, name, category, url;
  final bool query, authRequired, paidAccess;
  // Assisted navigation is explicitly distinct from an automatic data API.
  List<String> get capabilities => [
    'Navegação assistida',
    'Registro manual',
    'Importação JSON',
  ];
  bool? get officialApiAvailable => null;
  DateTime? get lastVerifiedAt => null; // No automated access/API verified.
  List<String> get countries => const [];
  List<String> get supportedImportFormats => const ['JSON', 'manual'];
  Uri search(String text) {
    final uri = Uri.parse(url);
    return query
        ? uri.replace(queryParameters: {...uri.queryParameters, 'q': text})
        : uri;
  }
}

abstract final class MiningSourceRegistry {
  static const sources = [
    MiningSource(
      'meta',
      'Meta Ads Library',
      'Anúncios',
      'https://www.facebook.com/ads/library/',
    ),
    MiningSource(
      'google-ads',
      'Google Ads Transparency',
      'Anúncios',
      'https://adstransparency.google.com/',
    ),
    MiningSource(
      'tiktok',
      'TikTok Creative Center',
      'Anúncios',
      'https://ads.tiktok.com/business/creativecenter/',
    ),
    MiningSource(
      'google',
      'Google Search',
      'Demanda',
      'https://www.google.com/search',
      query: true,
    ),
    MiningSource(
      'trends',
      'Google Trends',
      'Demanda',
      'https://trends.google.com/trends/explore',
      query: true,
    ),
    MiningSource(
      'reddit',
      'Reddit',
      'Dores',
      'https://www.reddit.com/search/',
      query: true,
    ),
    MiningSource(
      'reclame',
      'Reclame Aqui',
      'Dores',
      'https://www.reclameaqui.com.br/',
    ),
    MiningSource(
      'mercado',
      'Mercado Livre',
      'Produtos',
      'https://www.mercadolivre.com.br/',
    ),
    MiningSource(
      'semrush',
      'Semrush',
      'Demanda',
      'https://www.semrush.com/',
      authRequired: true,
      paidAccess: true,
    ),
    MiningSource(
      'similarweb',
      'Similarweb',
      'Demanda',
      'https://www.similarweb.com/',
      paidAccess: true,
    ),
  ];
}

class Detection {
  const Detection(
    this.technology,
    this.evidence,
    this.confidence,
    this.ruleVersion,
    this.source,
  );
  final String technology, evidence, confidence, ruleVersion, source;
  Map<String, dynamic> toJson() => {
    'technology': technology,
    'evidence': evidence,
    'confidence': confidence,
    'ruleVersion': ruleVersion,
    'source': source,
    'collectedAt': DateTime.now().toUtc().toIso8601String(),
  };
}

class PublicTechnologyDetector {
  static const version = '2026-10-29.1';
  static const checkouts = {
    'pay.kiwify.com.br': (
      'Kiwify',
      'https://ajuda.kiwify.com.br/pt-br/article/como-preencher-os-campos-do-checkout-pela-url-de7ezo/',
    ),
    'pay.cakto.com.br': ('Cakto', 'https://cakto.com.br/checkout'),
    'pay.hotmart.com': ('Hotmart', 'https://pay.hotmart.com/'),
  };
  List<Detection> detect(String url, {String publicText = ''}) {
    final uri = MetaAdsLibraryUrlBuilder.safeHttps(url.trim());
    if (uri == null || publicText.length > 500000) {
      throw const FormatException(
        'Use uma URL HTTPS válida e conteúdo público de até 500 mil caracteres.',
      );
    }
    final result = <Detection>[];
    final checkout = checkouts[uri.host];
    if (checkout != null) {
      result.add(
        Detection(
          checkout.$1,
          'Domínio exato: ${uri.host}',
          'Confirmado (domínio)',
          version,
          checkout.$2,
        ),
      );
    }
    final text = publicText.toLowerCase();
    for (final entry in const {
      'UTMify': [
        'cdn.utmify.com.br/scripts/utms/',
        'https://cdn.utmify.com.br/scripts/utms/latest.js',
      ],
      'WordPress': ['/wp-content/', 'https://developer.wordpress.org/'],
      'Elementor': ['elementor-widget', 'https://developers.elementor.com/'],
      'Google Tag Manager': [
        'googletagmanager.com/gtm.js',
        'https://developers.google.com/tag-platform/tag-manager/web',
      ],
      'Google tag (Analytics/Ads)': [
        'googletagmanager.com/gtag/js',
        'https://developers.google.com/analytics/devguides/collection/ga4',
      ],
      'Meta Pixel': [
        'connect.facebook.net',
        'https://developers.facebook.com/docs/meta-pixel/',
      ],
      'Shopify': ['cdn.shopify.com', 'https://shopify.dev/docs'],
      'Typebot': ['typebot.io', 'https://docs.typebot.io/'],
    }.entries) {
      if (text.contains(entry.value[0]) &&
          (entry.key != 'Meta Pixel' || text.contains('fbevents.js'))) {
        result.add(
          Detection(
            entry.key,
            'Indicador no conteúdo fornecido: ${entry.value[0]}',
            'Provável; conteúdo pode estar desatualizado',
            version,
            entry.value[1],
          ),
        );
      }
    }
    return result;
  }
}

enum ResearchKind { package, dossier, evidence }

class ResearchRecord {
  const ResearchRecord({
    required this.id,
    required this.name,
    required this.kind,
    required this.createdAt,
    required this.data,
  });
  final String id, name;
  final ResearchKind kind;
  final DateTime createdAt;
  final Map<String, dynamic> data;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'createdAt': createdAt.toIso8601String(),
    'data': data,
  };
  factory ResearchRecord.fromJson(Map<String, dynamic> j) {
    final r = ResearchRecord(
      id: j['id'] as String,
      name: j['name'] as String,
      kind: ResearchKind.values.byName(j['kind'] as String),
      createdAt: DateTime.parse(j['createdAt'] as String),
      data: j['data'] as Map<String, dynamic>,
    );
    r.validate();
    return r;
  }
  void validate() {
    if (kind == ResearchKind.package) {
      if (data['country'] != null && !countries.containsKey(data['country'])) {
        throw const FormatException('País inválido.');
      }
      if (data['sourceId'] != null &&
          !MiningSourceRegistry.sources.any((s) => s.id == data['sourceId'])) {
        throw const FormatException('Fonte inválida.');
      }
      if (data['media'] != null &&
          !['all', 'image', 'video'].contains(data['media'])) {
        throw const FormatException('Mídia inválida.');
      }
      if (data['status'] != null &&
          !['active', 'all'].contains(data['status'])) {
        throw const FormatException('Status inválido.');
      }
      if (data['limit'] != null &&
          ![4, 8, 12, 20, 30].contains(data['limit'])) {
        throw const FormatException('Limite inválido.');
      }
      for (final key in ['minDays', 'minAds']) {
        final value = data[key];
        if (value != null && value != '') {
          final n = value is String ? int.tryParse(value) : null;
          if (n == null ||
              n < (key == 'minAds' ? 1 : 0) ||
              n > (key == 'minAds' ? 1000 : 36500)) {
            throw const FormatException('Filtro numérico inválido.');
          }
        }
      }
    }
    for (final field in [
      'niche',
      'subniche',
      'format',
      'commercial',
      'price',
      'country',
      'status',
      'sourceId',
      'media',
      'language',
      'problem',
      'benefit',
      'excluded',
      'minDays',
      'minAds',
      'notes',
      'sourceUrl',
      'confidence',
      'collectedAt',
      'lastUsedAt',
    ]) {
      if (data[field] != null && data[field] is! String) {
        throw const FormatException('Campo de pesquisa inválido.');
      }
    }
    for (final field in ['queries', 'offerIds', 'evidenceIds', 'sources']) {
      if (data[field] != null &&
          (data[field] is! List ||
              (data[field] as List).any((x) => x is! String))) {
        throw const FormatException('Lista de pesquisa inválida.');
      }
    }
    if (data['confidence'] != null &&
        ![
          'Informado pelo usuário',
          'Observado em fonte pública',
          'Estimativa',
          'Desconhecido',
        ].contains(data['confidence'])) {
      throw const FormatException('Confiabilidade inválida.');
    }
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
        name.trim().isEmpty ||
        name.length > 200 ||
        jsonEncode(data).length > 500000) {
      throw const FormatException('Registro de pesquisa inválido.');
    }
    void check(dynamic value, int depth) {
      if (depth > 12) throw const FormatException('Registro muito complexo.');
      if (value is String &&
          (value.length > 10000 || value.contains('\u0000'))) {
        throw const FormatException('Texto inválido.');
      }
      if (value is Map) {
        for (final entry in value.entries) {
          if (entry.key is! String) throw const FormatException();
          if (['url', 'sourceUrl', 'source'].contains(entry.key) &&
              entry.value is String &&
              (entry.value as String).isNotEmpty &&
              MetaAdsLibraryUrlBuilder.safeHttps(entry.value as String) ==
                  null) {
            throw const FormatException('Fonte deve ser HTTPS.');
          }
          check(entry.value, depth + 1);
        }
      }
      if (value is List) {
        if (value.length > 500) throw const FormatException();
        for (final x in value) {
          check(x, depth + 1);
        }
      }
    }

    check(data, 0);
  }

  ResearchRecord duplicate() => ResearchRecord(
    id: localId(),
    name: '${name.length > 180 ? name.substring(0, 180) : name} (cópia)',
    kind: kind,
    createdAt: DateTime.now().toUtc(),
    data: jsonDecode(jsonEncode(data)) as Map<String, dynamic>,
  );
}

class OfferGroup {
  const OfferGroup(this.key, this.reason, this.offers);
  final String key, reason;
  final List<Offer> offers;
  static List<OfferGroup> group(List<Offer> offers) {
    final groups = <String, List<Offer>>{};
    for (final o in offers) {
      final uri = o.salesUrl == null
          ? null
          : MetaAdsLibraryUrlBuilder.safeHttps(o.salesUrl!);
      // Never group by a checkout host alone. Require exact product path.
      final key = uri != null && uri.path.length > 1
          ? 'url:${MetaAdsLibraryUrlBuilder.canonical(uri)}'
          : o.pageId != null
          ? 'page:${o.pageId}:${researchKey(o.name)}'
          : 'local:${o.id}';
      (groups[key] ??= []).add(o);
    }
    return [
      for (final e in groups.entries)
        if (e.value.length > 1)
          OfferGroup(
            e.key,
            e.key.startsWith('url:')
                ? 'Mesma URL pública de oferta (incluindo parâmetros)'
                : 'Mesmo Page ID e nome normalizado; revisar associação',
            e.value,
          ),
    ];
  }
}
