import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../core/longevity.dart';
import '../../core/widgets.dart';
import '../../data/offer.dart';
import 'offer_widgets.dart';

class CompareScreen extends StatelessWidget {
  const CompareScreen({
    super.key,
    required this.app,
    required this.a,
    required this.b,
  });
  final AppController app;
  final Offer a, b;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final today = CivilDate.today();
    final range = app.settings.priceRange;
    final sa = OpportunityScore.of(a, today, range);
    final sb = OpportunityScore.of(b, today, range);
    String text(String v) => v.trim().isEmpty ? 'Não informado' : v;
    String score(OpportunityScore s) => s.value == null
        ? 'Não informado'
        : '${s.value} (cobertura ${s.coverage}%)';
    final rows = <(String, String, String)>[
      ('Nome', a.name, b.name),
      ('Anunciante', text(a.advertiser), text(b.advertiser)),
      ('Nicho', text(a.niche), text(b.niche)),
      (
        'Preço',
        a.priceCents == null ? 'Não informado' : priceLabel(a),
        b.priceCents == null ? 'Não informado' : priceLabel(b),
      ),
      ('Origem do preço', a.priceSource.label, b.priceSource.label),
      (
        'Idade',
        a.startDate == null ? 'Não informado' : ageLabel(a.age(today)),
        b.startDate == null ? 'Não informado' : ageLabel(b.age(today)),
      ),
      (
        'Data inicial',
        a.startDate?.label ?? 'Não informado',
        b.startDate?.label ?? 'Não informado',
      ),
      ('Status', a.status.label, b.status.label),
      (
        'Última verificação',
        a.lastCheckedAt == null ? 'Não informado' : dateLabel(a.lastCheckedAt),
        b.lastCheckedAt == null ? 'Não informado' : dateLabel(b.lastCheckedAt),
      ),
      ('Mídia', a.mediaType.label, b.mediaType.label),
      (
        'Variações conhecidas',
        a.variations?.toString() ?? 'Não informado',
        b.variations?.toString() ?? 'Não informado',
      ),
      ('Score', score(sa), score(sb)),
      ('Situação', a.analysis.label, b.analysis.label),
      ('Funil', a.salesUrl ?? 'Não informado', b.salesUrl ?? 'Não informado'),
      ('Notas', text(a.notes), text(b.notes)),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Comparar ofertas')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          if (sa.coverage != sb.coverage)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Os scores têm coberturas diferentes (${sa.coverage}% e ${sb.coverage}%). Compare com cautela.',
                style: TextStyle(color: colors.error, fontSize: 13),
              ),
            ),
          for (final (label, x, y) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: SelectableText(x, maxLines: 6)),
                      const SizedBox(width: 16),
                      Expanded(child: SelectableText(y, maxLines: 6)),
                    ],
                  ),
                ],
              ),
            ),
          const Divider(height: 32),
          Text(
            'Valores ausentes aparecem como "Não informado". Score alto não significa vendas comprovadas.',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
