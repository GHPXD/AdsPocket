import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../core/longevity.dart';
import '../../core/meta_ads_library_url_builder.dart';
import '../../core/text_extraction.dart';
import '../../core/widgets.dart';
import '../../data/offer.dart';

String priceLabel(Offer o) => o.priceCents == null
    ? 'Preço não informado'
    : formatMoney(o.priceCents!, o.currency);

Uri? adLink(Offer o) {
  if (o.url != null) return Uri.parse(o.url!);
  if (o.adId == null) return null;
  return MetaAdsLibraryUrlBuilder.home.replace(queryParameters: {'id': o.adId});
}

Uri? advertiserLink(Offer o, String country) => o.pageId == null
    ? null
    : MetaAdsLibraryUrlBuilder().build(
        text: o.pageId!,
        type: SearchType.pageId,
        country: country,
      );

Future<void> openAd(BuildContext context, AppController app, Offer o) async {
  final link = adLink(o);
  if (link == null) {
    app.showNotice('Informe o ID ou o link do anúncio para abri-lo.');
    return;
  }
  await runGuarded(context, () => app.openLibrary(link));
}

Future<void> openAdvertiser(
  BuildContext context,
  AppController app,
  Offer o,
) async {
  final link = advertiserLink(o, app.settings.country);
  if (link == null) {
    app.showNotice('Informe o Page ID do anunciante para abrir a Página.');
    return;
  }
  await runGuarded(context, () => app.openLibrary(link));
}

Future<void> openSales(BuildContext context, AppController app, Offer o) async {
  if (o.salesUrl == null) {
    app.showNotice('Nenhuma página de vendas cadastrada.');
    return;
  }
  await runGuarded(context, () => app.openExternal(Uri.parse(o.salesUrl!)));
}

Color statusColor(AdStatus s, ColorScheme c) => switch (s) {
  AdStatus.active => const Color(0xFF22A06B),
  AdStatus.inactive => c.error,
  AdStatus.unknown => c.outline,
};

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.icon, this.color});
  final String text;
  final IconData? icon;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: c),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: c),
            ),
          ),
        ],
      ),
    );
  }
}

class OfferCard extends StatelessWidget {
  const OfferCard({
    super.key,
    required this.offer,
    required this.today,
    required this.range,
    this.selected = false,
    this.onTap,
    this.onLongPress,
  });
  final Offer offer;
  final CivilDate today;
  final PriceRange range;
  final bool selected;
  final VoidCallback? onTap, onLongPress;

  @override
  Widget build(BuildContext context) {
    final o = offer;
    final colors = Theme.of(context).colorScheme;
    final age = o.age(today);
    final score = OpportunityScore.of(o, today, range);
    return Card(
      color: selected ? colors.primaryContainer : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          o.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (o.advertiser.isNotEmpty)
                          Text(
                            o.advertiser,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_circle_rounded, color: colors.primary)
                  else if (score.value != null)
                    Semantics(
                      label:
                          'Score ${score.value} de 100, cobertura ${score.coverage}%',
                      child: Column(
                        children: [
                          Text(
                            '${score.value}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: colors.primary,
                            ),
                          ),
                          Text(
                            '${score.coverage}%',
                            style: TextStyle(
                              fontSize: 10,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Pill(
                    ageLabel(age),
                    icon: Icons.schedule_rounded,
                    color: age != null && age >= 0 ? colors.primary : null,
                  ),
                  Pill(
                    o.status.label,
                    icon: Icons.circle,
                    color: statusColor(o.status, colors),
                  ),
                  if (o.priceCents != null)
                    Pill(priceLabel(o), icon: Icons.sell_outlined),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ScoreView extends StatelessWidget {
  const ScoreView({super.key, required this.score});
  final OpportunityScore score;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 12, color: colors.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              score.value == null ? '—' : '${score.value}',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                color: colors.primary,
              ),
            ),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Text(
                'de 100 · cobertura ${score.coverage}%',
                style: muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final c in score.criteria)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(child: Text(c.label)),
                Text(
                  c.known ? '${c.points}/${c.max}' : 'Pendente: ${c.pending}',
                  style: c.known ? null : muted,
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Score alto não significa vendas comprovadas. Critérios pendentes não somam nem subtraem pontos.',
          style: muted,
        ),
      ],
    );
  }
}

/// Quick comment and tags after a one-tap save; no form to fill.
Future<void> commentOffer(
  BuildContext context,
  AppController app,
  String id,
) async {
  final o = app.offers.where((x) => x.id == id).firstOrNull;
  if (o == null) return;
  final note = TextEditingController(text: o.notes);
  final tags = TextEditingController(text: o.tags.join(', '));
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Comentário'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: note,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            maxLength: 2000,
            decoration: const InputDecoration(
              hintText: 'O que chamou atenção?',
            ),
          ),
          TextField(
            controller: tags,
            maxLength: 300,
            decoration: const InputDecoration(
              hintText: 'Tags: ebook, planilha, finanças',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Salvar'),
        ),
      ],
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  final text = note.text.trim();
  final list = tags.text
      .split(',')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty && t.length <= 80)
      .toSet()
      .take(30)
      .toList();
  note.dispose();
  tags.dispose();
  if (ok != true || !context.mounted) return;
  await runGuarded(
    context,
    () => app.saveOffer(o.copyWith(notes: text, tags: list)),
  );
}
