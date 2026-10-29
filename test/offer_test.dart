import 'package:ads_pocket/core/longevity.dart';
import 'package:ads_pocket/data/backup_service.dart';
import 'package:ads_pocket/data/models.dart';
import 'package:ads_pocket/data/offer.dart';
import 'package:ads_pocket/features/mining/mining_filter.dart';
import 'package:flutter_test/flutter_test.dart';

final today = CivilDate.of(2026, 10, 28)!;

Offer offer({
  String name = 'Planilha financeira',
  int? price,
  String currency = 'BRL',
  CivilDate? start,
  AdStatus status = AdStatus.unknown,
  Analysis analysis = Analysis.notAnalyzed,
  MediaType media = MediaType.unknown,
  String advertiser = '',
  String niche = '',
  String? adId,
  int? clarity,
}) => Offer(
  id: localId(),
  name: name,
  createdAt: DateTime.utc(2026, 10),
  updatedAt: DateTime.utc(2026, 10),
  priceCents: price,
  currency: currency,
  priceSource: price == null ? PriceSource.unknown : PriceSource.informed,
  startDate: start,
  dateSource: start == null ? null : DateSource.manual,
  status: status,
  analysis: analysis,
  mediaType: media,
  advertiser: advertiser,
  niche: niche,
  adId: adId,
  clarity: clarity,
);

void main() {
  test('validation rejects inconsistent or unsafe offers', () {
    offer(price: 1990, start: today).validate();
    final bad = <Offer Function()>[
      () => offer(name: ' '),
      () => Offer(
        id: localId(),
        name: 'x',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        priceCents: 990,
      ),
      () => Offer(
        id: localId(),
        name: 'x',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        startDate: today,
      ),
      () => Offer(
        id: localId(),
        name: 'x',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        pageId: '12a',
      ),
      () => Offer(
        id: localId(),
        name: 'x',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        salesUrl: 'http://loja.example.com',
      ),
      () => Offer(
        id: localId(),
        name: 'x',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        url: 'https://evil.com/ads/library/',
      ),
      () => Offer(
        id: localId(),
        name: 'x',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        imageFile: '../../secret.png',
      ),
      () => offer(clarity: 6),
    ];
    for (final make in bad) {
      expect(() => make().validate(), throwsFormatException);
    }
  });

  test('json round trip keeps every field including status checks', () {
    final o = offer(
      price: 4700,
      start: today.addDays(-30),
      adId: '123',
    ).confirmStatus(AdStatus.active, DateTime.utc(2026, 10, 27));
    final back = Offer.fromJson(o.toJson());
    expect(back.toJson(), o.toJson());
    expect(back.lastCheckedAt, DateTime.utc(2026, 10, 27));
    expect(back.status, AdStatus.active);
  });

  test('identity uses the public ad ID only', () {
    expect(offer(adId: '99').identity, 'ad:99');
    final fromUrl = Offer(
      id: localId(),
      name: 'x',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      url: 'https://www.facebook.com/ads/library/?id=99',
    );
    expect(fromUrl.identity, 'ad:99');
    expect(offer().identity, isNull);
  });

  test('score shows coverage and never fills missing data', () {
    final empty = OpportunityScore.of(offer(), today, PriceRange.lowTicket);
    expect(empty.value, isNull);
    expect(empty.coverage, 0);
    expect(empty.pending, hasLength(6));

    final partial = OpportunityScore.of(
      offer(price: 1990, start: today.addDays(-60), clarity: 5),
      today,
      PriceRange.lowTicket,
    );
    expect(partial.coverage, 30 + 15 + 15);
    expect(partial.value, 30 + 15 + 15);
    expect(partial.pending.map((c) => c.label), [
      'Diversidade conhecida de criativos',
      'Qualidade da página de vendas',
      'Avaliação manual',
    ]);
    // A price in another currency is not compared against the BRL range.
    final usd = OpportunityScore.of(
      offer(price: 1990, currency: 'USD'),
      today,
      PriceRange.lowTicket,
    );
    expect(usd.coverage, 0);
    // Future dates do not earn longevity points.
    expect(
      OpportunityScore.of(
        offer(start: today.addDays(2)),
        today,
        PriceRange.lowTicket,
      ).value,
      isNull,
    );
  });

  test('low ticket range: defaults, bounds and currency', () {
    const r = PriceRange.lowTicket;
    expect((r.minCents, r.maxCents, r.currency), (990, 9700, 'BRL'));
    expect(r.contains(990, 'BRL'), isTrue);
    expect(r.contains(9700, 'BRL'), isTrue);
    expect(r.contains(9701, 'BRL'), isFalse);
    expect(r.contains(1990, 'USD'), isFalse);
    expect(const PriceRange(100, 50, 'BRL').valid, isFalse);
  });

  group('mining filter', () {
    final items = [
      offer(
        name: 'Antiga',
        start: today.addDays(-90),
        price: 1990,
        status: AdStatus.active,
        media: MediaType.video,
        advertiser: 'Loja A',
        niche: 'Finanças',
      ),
      offer(name: 'Recente', start: today.addDays(-2), price: 4700),
      offer(name: 'Sem data', price: 25000),
      offer(
        name: 'Interessante',
        start: today.addDays(-20),
        analysis: Analysis.interesting,
        niche: 'Finanças',
      ),
    ];
    List<String> names(MiningFilter f, [OfferSort s = OfferSort.oldest]) => f
        .apply(items, s, today, PriceRange.lowTicket)
        .map((o) => o.name)
        .toList();

    test('14 days with and without undated records', () {
      expect(
        names(const MiningFilter(longevity: LongevityFilter(minDays: 14))),
        ['Antiga', 'Interessante', 'Sem data'],
      );
      expect(
        names(
          const MiningFilter(
            longevity: LongevityFilter(minDays: 14, includeUndated: false),
          ),
        ),
        ['Antiga', 'Interessante'],
      );
    });

    test('price filter excludes unknown unless asked', () {
      const f = MiningFilter(price: PriceRange.lowTicket);
      expect(names(f), ['Antiga', 'Recente']);
      expect(names(f.copyWith(includeUnknownPrice: true)), [
        'Antiga',
        'Interessante',
        'Recente',
      ]);
    });

    test('combined filters', () {
      final f =
          const MiningFilter(
            longevity: LongevityFilter(minDays: 30, includeUndated: false),
          ).copyWith(
            niche: () => 'Finanças',
            statuses: {AdStatus.active},
            media: {MediaType.video},
            price: () => PriceRange.lowTicket,
          );
      expect(names(f), ['Antiga']);
      expect(f.activeCount, 5);
      expect(names(f.copyWith(statuses: {AdStatus.inactive})), isEmpty);
      expect(
        names(const MiningFilter().copyWith(analyses: {Analysis.interesting})),
        ['Interessante'],
      );
    });

    test('sorting puts unknown values last', () {
      expect(names(const MiningFilter(), OfferSort.newest), [
        'Recente',
        'Interessante',
        'Antiga',
        'Sem data',
      ]);
      expect(names(const MiningFilter(), OfferSort.price).last, 'Interessante');
      expect(names(const MiningFilter(text: 'antiga')), ['Antiga']);
    });
  });

  test('CSV escapes separators and neutralises formulas', () {
    final csv = CsvExport.offers([
      offer(
        name: 'A; "B"',
        price: 990,
        start: today.addDays(-10),
      ).copyWith(notes: '=HYPERLINK("x")'),
    ], today);
    final lines = csv.substring(1).trim().split('\r\n');
    expect(lines.first.split(';').first, 'nome');
    expect(lines[1], contains('"A; ""B"""'));
    expect(lines[1], contains("\"'=HYPERLINK(\"\"x\"\")\""));
    expect(lines[1], contains('9,90'));
    expect(lines[1], contains(';10;'));
  });

  test('archive policy blocks traversal, duplicates and oversized files', () {
    const image = 'images/0f8fad5b-d9cb-469f-a165-70867728950e.png';
    ArchivePolicy.validate([('backup.json', 100), (image, 1000)]);
    for (final entries in <List<(String, int)>>[
      [('backup.json', 1), ('../evil.png', 1)],
      [('backup.json', 1), ('/abs/backup.json', 1)],
      [('backup.json', 1), ('images\\x.png', 1)],
      [('backup.json', 1), ('C:/x.png', 1)],
      [('backup.json', 1), (image, 1), (image, 1)],
      [('backup.json', 1), ('backup.json', 1)],
      [('backup.json', 1), (image, 20 * 1024 * 1024)],
      [(image, 1)],
      [('backup.json', 1), ('images/run.sh', 1)],
    ]) {
      expect(() => ArchivePolicy.validate(entries), throwsFormatException);
    }
  });
}
