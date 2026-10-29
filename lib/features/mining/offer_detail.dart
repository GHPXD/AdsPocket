import 'dart:io';
import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../core/longevity.dart';
import '../../core/native_bridge.dart';
import '../../core/widgets.dart';
import '../../data/offer.dart';
import 'offer_editor.dart';
import 'offer_widgets.dart';

class OfferDetailScreen extends StatelessWidget {
  const OfferDetailScreen({super.key, required this.app, required this.id});
  final AppController app;
  final String id;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: app,
    builder: (context, _) {
      final o = app.offers.where((x) => x.id == id).firstOrNull;
      if (o == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('Referência removida.')),
        );
      }
      final colors = Theme.of(context).colorScheme;
      final today = CivilDate.today();
      final age = o.age(today);
      final stale =
          o.status == AdStatus.active &&
          isStaleCheck(o.lastCheckedAt, DateTime.now());
      final muted = TextStyle(color: colors.onSurfaceVariant, fontSize: 13);
      String info(String v) => v.trim().isEmpty ? 'Não informado' : v;
      Widget row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 132, child: Text(label, style: muted)),
            Expanded(child: SelectableText(value)),
          ],
        ),
      );
      Widget section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle(title),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      );
      return Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
              tooltip: 'Editar',
              onPressed: () => openOfferEditor(context, app, existing: o),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Remover',
              onPressed: () async {
                if (await confirm(
                      context,
                      'Remover referência?',
                      o.name,
                      action: 'Remover',
                    ) &&
                    context.mounted) {
                  await runGuarded(context, () async {
                    await app.deleteOffer(o);
                    if (context.mounted) Navigator.pop(context);
                  });
                }
              },
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          children: [
            Text(
              o.name,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            if (o.advertiser.isNotEmpty) Text(o.advertiser, style: muted),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Pill(ageLabel(age), icon: Icons.schedule_rounded),
                Pill(
                  o.status.label,
                  icon: Icons.circle,
                  color: statusColor(o.status, colors),
                ),
                Pill(o.analysis.label),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: adLink(o) == null
                      ? null
                      : () => openAd(context, app, o),
                  icon: const Icon(Icons.ad_units_outlined),
                  label: const Text('Anúncio'),
                ),
                FilledButton.tonalIcon(
                  onPressed: o.pageId == null
                      ? null
                      : () => openAdvertiser(context, app, o),
                  icon: const Icon(Icons.storefront_outlined),
                  label: const Text('Anunciante'),
                ),
                FilledButton.tonalIcon(
                  onPressed: o.salesUrl == null
                      ? null
                      : () => openSales(context, app, o),
                  icon: const Icon(Icons.shopping_cart_outlined),
                  label: const Text('Página de vendas'),
                ),
              ],
            ),
            section('Longevidade', [
              row('Data de início', o.startDate?.label ?? 'Não informada'),
              row('Origem da data', o.dateSource?.label ?? 'Não informada'),
              row('Idade', ageLabel(age)),
              row('Status', o.status.label),
              row('Última verificação', dateLabel(o.lastCheckedAt)),
              if (stale)
                Text(
                  'A última confirmação de atividade tem mais de 7 dias. Verifique na Biblioteca.',
                  style: TextStyle(color: colors.error, fontSize: 13),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => runGuarded(
                      context,
                      () => app.saveOffer(
                        o.confirmStatus(AdStatus.active, DateTime.now()),
                      ),
                    ),
                    child: const Text('Ativo hoje'),
                  ),
                  OutlinedButton(
                    onPressed: () => runGuarded(
                      context,
                      () => app.saveOffer(
                        o.confirmStatus(AdStatus.inactive, DateTime.now()),
                      ),
                    ),
                    child: const Text('Inativo'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Idade indica tempo desde o início, não atividade contínua nem lucratividade.',
                style: muted,
              ),
            ]),
            section('Oferta', [
              row('Preço', priceLabel(o)),
              row('Origem do preço', o.priceSource.label),
              row('Nicho', info(o.niche)),
              row('Categoria', info(o.category)),
              row('Mídia', o.mediaType.label),
              row('Page ID', o.pageId ?? 'Não informado'),
              row('ID do anúncio', o.adId ?? 'Não informado'),
            ]),
            section('Criativo', [
              row('Hook', info(o.hook)),
              row('Headline', info(o.headline)),
              row('CTA', info(o.cta)),
              row('Ângulo', info(o.angle)),
              row(
                'Variações conhecidas',
                o.variations?.toString() ?? 'Não informado',
              ),
            ]),
            section('Score de oportunidade', [
              ScoreView(
                score: OpportunityScore.of(o, today, app.settings.priceRange),
              ),
            ]),
            if (o.tags.isNotEmpty || o.notes.isNotEmpty)
              section('Notas', [
                if (o.tags.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final t in o.tags) Pill(t)],
                  ),
                if (o.notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SelectableText(o.notes),
                ],
              ]),
            if (o.imageFile != null)
              section('Imagem', [
                if (o.capturedAt != null)
                  Text('Capturada em ${dateLabel(o.capturedAt)}', style: muted),
                const SizedBox(height: 8),
                FutureBuilder<String?>(
                  future: NativeBridge.imagePath(o.imageFile!),
                  builder: (context, snap) => snap.data == null
                      ? Text(
                          'Imagem indisponível neste aparelho.',
                          style: muted,
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: InteractiveViewer(
                            maxScale: 5,
                            child: Image.file(File(snap.data!)),
                          ),
                        ),
                ),
              ]),
            if (o.ocrText.isNotEmpty)
              section('Texto reconhecido', [
                SelectableText(o.ocrText, maxLines: 12),
                TextButton.icon(
                  onPressed: () =>
                      copyLink(context, o.ocrText, message: 'Texto copiado.'),
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copiar texto'),
                ),
              ]),
          ],
        ),
      );
    },
  );
}
