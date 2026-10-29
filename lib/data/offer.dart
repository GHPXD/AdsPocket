import '../core/longevity.dart';
import '../core/meta_ads_library_url_builder.dart';
import '../core/text_extraction.dart';

enum PriceSource {
  confirmed('Confirmado'),
  informed('Informado'),
  ocr('Sugerido por OCR'),
  unknown('Desconhecido');

  const PriceSource(this.label);
  final String label;
}

enum DateSource {
  manual('Informada pelo usuário'),
  ocr('OCR confirmado pelo usuário'),
  library('Lida do card na Biblioteca');

  const DateSource(this.label);
  final String label;
}

enum MediaType {
  image('Imagem'),
  video('Vídeo'),
  carousel('Carrossel'),
  unknown('Não informado');

  const MediaType(this.label);
  final String label;
}

enum Analysis {
  notAnalyzed('Não analisado'),
  watching('Em observação'),
  interesting('Interessante'),
  discarded('Descartado'),
  futureModel('Modelagem futura');

  const Analysis(this.label);
  final String label;
}

class StatusCheck {
  const StatusCheck(this.status, this.at);
  final AdStatus status;
  final DateTime at;
  Map<String, Object?> toJson() => {
    'status': status.name,
    'at': at.toIso8601String(),
  };
  factory StatusCheck.fromJson(Map<String, dynamic> j) => StatusCheck(
    AdStatus.values.byName(j['status'] as String),
    DateTime.parse(j['at'] as String),
  );
}

/// A reference catalogued by the user (Mineração). Every value is typed or
/// confirmed by the user; nothing is fetched from Meta.
class Offer {
  const Offer({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.advertiser = '',
    this.pageId,
    this.adId,
    this.url,
    this.niche = '',
    this.category = '',
    this.priceCents,
    this.currency = 'BRL',
    this.priceSource = PriceSource.unknown,
    this.startDate,
    this.dateSource,
    this.status = AdStatus.unknown,
    this.checks = const [],
    this.mediaType = MediaType.unknown,
    this.salesUrl,
    this.tags = const [],
    this.notes = '',
    this.imageFile,
    this.ocrText = '',
    this.capturedAt,
    this.hook = '',
    this.headline = '',
    this.cta = '',
    this.angle = '',
    this.variations,
    this.clarity,
    this.salesPageQuality,
    this.manualRating,
    this.analysis = Analysis.notAnalyzed,
  });

  final String id, name, advertiser, niche, category, currency, notes;
  final String ocrText, hook, headline, cta, angle;
  final String? pageId, adId, url, salesUrl, imageFile;
  final int? priceCents, variations, clarity, salesPageQuality, manualRating;
  final PriceSource priceSource;
  final CivilDate? startDate;
  final DateSource? dateSource;
  final AdStatus status;
  final List<StatusCheck> checks;
  final MediaType mediaType;
  final List<String> tags;
  final DateTime createdAt, updatedAt;
  final DateTime? capturedAt;
  final Analysis analysis;

  DateTime? get lastCheckedAt => checks.isEmpty ? null : checks.last.at;
  int? age(CivilDate today) => ageInDays(startDate, today);

  /// Duplicate key: the public ad ID, typed or taken from an ad URL (`id=`).
  /// Page and search URLs are shared by many ads, so they are not keys.
  String? get identity {
    final key =
        adId ??
        (url == null ? null : Uri.tryParse(url!)?.queryParameters['id']);
    return key == null ? null : 'ad:$key';
  }

  Offer copyWith({
    String? name,
    String? advertiser,
    String? niche,
    String? category,
    String? notes,
    List<String>? tags,
    Analysis? analysis,
    CivilDate? startDate,
    DateSource? dateSource,
    AdStatus? status,
    List<StatusCheck>? checks,
    DateTime? updatedAt,
    String? ocrText,
    String? imageFile,
  }) => Offer(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now().toUtc(),
    advertiser: advertiser ?? this.advertiser,
    pageId: pageId,
    adId: adId,
    url: url,
    niche: niche ?? this.niche,
    category: category ?? this.category,
    priceCents: priceCents,
    currency: currency,
    priceSource: priceSource,
    startDate: startDate ?? this.startDate,
    dateSource: dateSource ?? this.dateSource,
    status: status ?? this.status,
    checks: checks ?? this.checks,
    mediaType: mediaType,
    salesUrl: salesUrl,
    tags: tags ?? this.tags,
    notes: notes ?? this.notes,
    imageFile: imageFile ?? this.imageFile,
    ocrText: ocrText ?? this.ocrText,
    capturedAt: capturedAt,
    hook: hook,
    headline: headline,
    cta: cta,
    angle: angle,
    variations: variations,
    clarity: clarity,
    salesPageQuality: salesPageQuality,
    manualRating: manualRating,
    analysis: analysis ?? this.analysis,
  );

  /// Records a dated status confirmation; the status never ages silently.
  Offer confirmStatus(AdStatus value, DateTime at) {
    final next = [...checks, StatusCheck(value, at.toUtc())];
    return copyWith(
      status: value,
      checks: next.length > 50 ? next.sublist(next.length - 50) : next,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'advertiser': advertiser,
    'pageId': pageId,
    'adId': adId,
    'url': url,
    'niche': niche,
    'category': category,
    'priceCents': priceCents,
    'currency': currency,
    'priceSource': priceSource.name,
    'startDate': startDate?.toIso(),
    'dateSource': dateSource?.name,
    'status': status.name,
    'checks': checks.map((c) => c.toJson()).toList(),
    'mediaType': mediaType.name,
    'salesUrl': salesUrl,
    'tags': tags,
    'notes': notes,
    'imageFile': imageFile,
    'ocrText': ocrText,
    'capturedAt': capturedAt?.toIso8601String(),
    'hook': hook,
    'headline': headline,
    'cta': cta,
    'angle': angle,
    'variations': variations,
    'clarity': clarity,
    'salesPageQuality': salesPageQuality,
    'manualRating': manualRating,
    'analysis': analysis.name,
  };

  factory Offer.fromJson(Map<String, dynamic> j) {
    final start = j['startDate'] as String?;
    final date = start == null ? null : CivilDate.tryParse(start);
    if (start != null && date == null) throw const FormatException();
    return Offer(
      id: j['id'] as String,
      name: j['name'] as String,
      createdAt: DateTime.parse(j['createdAt'] as String),
      updatedAt: DateTime.parse(j['updatedAt'] as String),
      advertiser: j['advertiser'] as String? ?? '',
      pageId: j['pageId'] as String?,
      adId: j['adId'] as String?,
      url: j['url'] as String?,
      niche: j['niche'] as String? ?? '',
      category: j['category'] as String? ?? '',
      priceCents: j['priceCents'] as int?,
      currency: j['currency'] as String? ?? 'BRL',
      priceSource: PriceSource.values.byName(
        j['priceSource'] as String? ?? 'unknown',
      ),
      startDate: date,
      dateSource: j['dateSource'] == null
          ? null
          : DateSource.values.byName(j['dateSource'] as String),
      status: AdStatus.values.byName(j['status'] as String? ?? 'unknown'),
      checks: [
        for (final c in j['checks'] as List? ?? const [])
          StatusCheck.fromJson(c as Map<String, dynamic>),
      ],
      mediaType: MediaType.values.byName(
        j['mediaType'] as String? ?? 'unknown',
      ),
      salesUrl: j['salesUrl'] as String?,
      tags: List<String>.from(j['tags'] as List? ?? const []),
      notes: j['notes'] as String? ?? '',
      imageFile: j['imageFile'] as String?,
      ocrText: j['ocrText'] as String? ?? '',
      capturedAt: j['capturedAt'] == null
          ? null
          : DateTime.parse(j['capturedAt'] as String),
      hook: j['hook'] as String? ?? '',
      headline: j['headline'] as String? ?? '',
      cta: j['cta'] as String? ?? '',
      angle: j['angle'] as String? ?? '',
      variations: j['variations'] as int?,
      clarity: j['clarity'] as int?,
      salesPageQuality: j['salesPageQuality'] as int?,
      manualRating: j['manualRating'] as int?,
      analysis: Analysis.values.byName(
        j['analysis'] as String? ?? 'notAnalyzed',
      ),
    );
  }

  /// Throws [FormatException] with a user-facing message.
  void validate() {
    void text(String v, int max, String field, {bool required = false}) {
      if (v.length > max || v.contains('\u0000')) {
        throw FormatException('$field ultrapassa $max caracteres.');
      }
      if (required && v.trim().isEmpty) {
        throw FormatException('Informe $field.');
      }
    }

    void rating(int? v) {
      if (v != null && (v < 0 || v > 5)) {
        throw const FormatException('Avaliações vão de 0 a 5.');
      }
    }

    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
      throw const FormatException('Identificador local inválido.');
    }
    text(name, 200, 'o nome da oferta', required: true);
    for (final (v, f) in [
      (advertiser, 'Anunciante'),
      (niche, 'Nicho'),
      (category, 'Categoria'),
      (hook, 'Hook'),
      (headline, 'Headline'),
      (cta, 'CTA'),
      (angle, 'Ângulo'),
    ]) {
      text(v, 500, f);
    }
    text(notes, 10000, 'Notas');
    text(ocrText, 20000, 'Texto reconhecido');
    for (final (v, f) in [(pageId, 'Page ID'), (adId, 'ID do anúncio')]) {
      if (v != null && !RegExp(r'^\d{1,40}$').hasMatch(v)) {
        throw FormatException('$f deve conter apenas números.');
      }
    }
    if (url != null) MetaAdsLibraryUrlBuilder.validateLibrary(url!);
    if (salesUrl != null &&
        MetaAdsLibraryUrlBuilder.safeHttps(salesUrl!) == null) {
      throw const FormatException('A página de vendas deve usar HTTPS.');
    }
    if (!currencies.containsKey(currency)) {
      throw const FormatException('Moeda não suportada.');
    }
    if (priceCents != null && (priceCents! < 0 || priceCents! > 100000000)) {
      throw const FormatException('Preço fora do intervalo aceito.');
    }
    if ((priceCents == null) != (priceSource == PriceSource.unknown)) {
      throw const FormatException('Informe a origem do preço.');
    }
    if ((startDate == null) != (dateSource == null)) {
      throw const FormatException('Informe a origem da data de início.');
    }
    if (variations != null && (variations! < 1 || variations! > 10000)) {
      throw const FormatException('Variações conhecidas: de 1 a 10.000.');
    }
    rating(clarity);
    rating(salesPageQuality);
    rating(manualRating);
    if (tags.length > 30 || tags.any((t) => t.length > 80)) {
      throw const FormatException('Máximo 30 tags de até 80 caracteres.');
    }
    if (checks.length > 50) {
      throw const FormatException('Histórico de verificações muito grande.');
    }
    if (imageFile != null &&
        !RegExp(r'^[a-f0-9-]{36}\.(png|jpg|webp)$').hasMatch(imageFile!)) {
      throw const FormatException('Arquivo de imagem inválido.');
    }
  }
}

class PriceRange {
  const PriceRange(this.minCents, this.maxCents, this.currency);
  static const lowTicket = PriceRange(990, 9700, 'BRL');
  final int minCents, maxCents;
  final String currency;
  bool contains(int cents, String cur) =>
      cur == currency && cents >= minCents && cents <= maxCents;
  String get label =>
      '${formatMoney(minCents, currency)} – ${formatMoney(maxCents, currency)}';
  Map<String, Object?> toJson() => {
    'min': minCents,
    'max': maxCents,
    'currency': currency,
  };
  factory PriceRange.fromJson(Map<String, dynamic> j) =>
      PriceRange(j['min'] as int, j['max'] as int, j['currency'] as String);
  bool get valid =>
      minCents >= 0 &&
      maxCents >= minCents &&
      maxCents <= 100000000 &&
      currencies.containsKey(currency);
  @override
  bool operator ==(Object other) =>
      other is PriceRange &&
      other.minCents == minCents &&
      other.maxCents == maxCents &&
      other.currency == currency;
  @override
  int get hashCode => Object.hash(minCents, maxCents, currency);
}

class ScoreCriterion {
  const ScoreCriterion(this.label, this.max, this.points, this.pending);
  final String label;
  final int max;
  final int? points;
  final String pending;
  bool get known => points != null;
}

/// Optional 0–100 score. Missing data never earns or loses points; it lowers
/// coverage instead, which the UI always shows next to the score.
class OpportunityScore {
  OpportunityScore._(this.criteria);
  final List<ScoreCriterion> criteria;
  int get points => criteria.fold(0, (s, c) => s + (c.points ?? 0));
  int get coverage =>
      criteria.where((c) => c.known).fold(0, (s, c) => s + c.max);
  int? get value => coverage == 0 ? null : points;
  List<ScoreCriterion> get pending => criteria.where((c) => !c.known).toList();

  factory OpportunityScore.of(Offer o, CivilDate today, PriceRange range) {
    final age = o.age(today);
    int? fit;
    if (o.priceCents != null && o.currency == range.currency) {
      final p = o.priceCents!;
      fit = range.contains(p, o.currency)
          ? 15
          : (p >= range.minCents * .5 && p <= range.maxCents * 1.5)
          ? 7
          : 0;
    }
    return OpportunityScore._([
      ScoreCriterion(
        'Longevidade',
        30,
        age == null || age < 0 ? null : (age.clamp(0, 60) * 30 / 60).round(),
        'Data de início',
      ),
      ScoreCriterion(
        'Diversidade conhecida de criativos',
        15,
        switch (o.variations) {
          null => null,
          1 => 3,
          2 => 6,
          3 || 4 => 10,
          _ => 15,
        },
        'Quantidade de variações',
      ),
      ScoreCriterion(
        'Clareza da oferta',
        15,
        o.clarity == null ? null : o.clarity! * 3,
        'Avaliar clareza',
      ),
      ScoreCriterion(
        'Adequação ao low ticket',
        15,
        fit,
        o.priceCents == null ? 'Preço' : 'Preço na moeda da faixa',
      ),
      ScoreCriterion(
        'Qualidade da página de vendas',
        15,
        o.salesPageQuality == null ? null : o.salesPageQuality! * 3,
        'Avaliar página de vendas',
      ),
      ScoreCriterion(
        'Avaliação manual',
        10,
        o.manualRating == null ? null : o.manualRating! * 2,
        'Sua avaliação',
      ),
    ]);
  }
}
