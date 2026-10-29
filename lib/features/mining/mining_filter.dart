import '../../core/longevity.dart';
import '../../data/offer.dart';

enum OfferSort {
  oldest('Mais antigos'),
  newest('Mais recentes'),
  lastCheck('Última verificação'),
  price('Preço'),
  priority('Prioridade');

  const OfferSort(this.label);
  final String label;
}

/// Local filter over references catalogued in AdsPocket. It never claims to
/// filter Meta's remote Library.
class MiningFilter {
  const MiningFilter({
    this.text = '',
    this.longevity = const LongevityFilter(),
    this.statuses = const {},
    this.analyses = const {},
    this.media = const {},
    this.advertiser,
    this.niche,
    this.category,
    this.price,
    this.includeUnknownPrice = false,
  });
  final String text;
  final LongevityFilter longevity;
  final Set<AdStatus> statuses;
  final Set<Analysis> analyses;
  final Set<MediaType> media;
  final String? advertiser, niche, category;
  final PriceRange? price;
  final bool includeUnknownPrice;

  int get activeCount =>
      (longevity.active ? 1 : 0) +
      (statuses.isEmpty ? 0 : 1) +
      (analyses.isEmpty ? 0 : 1) +
      (media.isEmpty ? 0 : 1) +
      (advertiser == null ? 0 : 1) +
      (niche == null ? 0 : 1) +
      (category == null ? 0 : 1) +
      (price == null ? 0 : 1);

  MiningFilter copyWith({
    String? text,
    LongevityFilter? longevity,
    Set<AdStatus>? statuses,
    Set<Analysis>? analyses,
    Set<MediaType>? media,
    String? Function()? advertiser,
    String? Function()? niche,
    String? Function()? category,
    PriceRange? Function()? price,
    bool? includeUnknownPrice,
  }) => MiningFilter(
    text: text ?? this.text,
    longevity: longevity ?? this.longevity,
    statuses: statuses ?? this.statuses,
    analyses: analyses ?? this.analyses,
    media: media ?? this.media,
    advertiser: advertiser == null ? this.advertiser : advertiser(),
    niche: niche == null ? this.niche : niche(),
    category: category == null ? this.category : category(),
    price: price == null ? this.price : price(),
    includeUnknownPrice: includeUnknownPrice ?? this.includeUnknownPrice,
  );

  bool matches(Offer o, CivilDate today) {
    if (!longevity.matches(o.startDate, today)) return false;
    if (statuses.isNotEmpty && !statuses.contains(o.status)) return false;
    if (analyses.isNotEmpty && !analyses.contains(o.analysis)) return false;
    if (media.isNotEmpty && !media.contains(o.mediaType)) return false;
    if (advertiser != null && o.advertiser != advertiser) return false;
    if (niche != null && o.niche != niche) return false;
    if (category != null && o.category != category) return false;
    if (price != null) {
      if (o.priceCents == null) {
        if (!includeUnknownPrice) return false;
      } else if (!price!.contains(o.priceCents!, o.currency)) {
        return false;
      }
    }
    final q = text.trim().toLowerCase();
    if (q.isNotEmpty &&
        !'${o.name} ${o.advertiser} ${o.niche} ${o.category} ${o.tags.join(' ')} ${o.notes} ${o.hook} ${o.headline}'
            .toLowerCase()
            .contains(q)) {
      return false;
    }
    return true;
  }

  List<Offer> apply(
    List<Offer> offers,
    OfferSort sort,
    CivilDate today,
    PriceRange range,
  ) {
    final result = offers.where((o) => matches(o, today)).toList();
    // Unknown values always sort last so they never look like extremes.
    int nullsLast(Comparable<dynamic>? a, Comparable<dynamic>? b, bool desc) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return desc ? b.compareTo(a) : a.compareTo(b);
    }

    result.sort(
      (a, b) => switch (sort) {
        OfferSort.oldest => nullsLast(a.startDate, b.startDate, false),
        OfferSort.newest => nullsLast(a.startDate, b.startDate, true),
        OfferSort.lastCheck => nullsLast(
          a.lastCheckedAt,
          b.lastCheckedAt,
          true,
        ),
        OfferSort.price => nullsLast(a.priceCents, b.priceCents, false),
        OfferSort.priority => nullsLast(
          OpportunityScore.of(a, today, range).value,
          OpportunityScore.of(b, today, range).value,
          true,
        ),
      },
    );
    return result;
  }
}
