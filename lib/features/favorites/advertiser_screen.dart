import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../core/longevity.dart';
import '../../core/widgets.dart';
import '../../data/offer.dart';
import '../mining/offer_detail.dart';
import '../mining/offer_editor.dart';
import '../mining/offer_widgets.dart';
import 'bookmark_editor.dart';

class AdvertiserScreen extends StatelessWidget {
  const AdvertiserScreen({super.key, required this.app, required this.id});
  final AppController app;
  final String id;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: app,
    builder: (context, _) {
      final b = app.bookmarks.where((x) => x.id == id).firstOrNull;
      if (b == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('Anunciante removido.')),
        );
      }
      final colors = Theme.of(context).colorScheme;
      final muted = TextStyle(fontSize: 13, color: colors.onSurfaceVariant);
      final today = CivilDate.today();
      final local = app.offersForPage(
        b.pageId,
      )..sort((x, y) => (x.startDate ?? today).compareTo(y.startDate ?? today));
      return Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
              tooltip: b.watchlist
                  ? 'Tirar da observação'
                  : 'Adicionar à observação',
              onPressed: () => runGuarded(
                context,
                () => app.save(b.copyWith(watchlist: !b.watchlist)),
              ),
              icon: Icon(
                b.watchlist
                    ? Icons.visibility_rounded
                    : Icons.visibility_outlined,
              ),
            ),
            IconButton(
              tooltip: 'Editar',
              onPressed: () => editBookmark(context, app, existing: b),
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          children: [
            Text(
              b.name,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(
              'Page ID ${b.pageId}${b.niche.isEmpty ? '' : ' · ${b.niche}'}',
              style: muted,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => runGuarded(context, () async {
                      await app.visit(b);
                      if (context.mounted) Navigator.pop(context);
                    }),
                    icon: const Icon(Icons.public_rounded),
                    label: const Text('Abrir na Biblioteca'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => openOfferEditor(
                      context,
                      app,
                      advertiser: b.name,
                      pageId: b.pageId,
                    ),
                    icon: const Icon(Icons.playlist_add_rounded),
                    label: const Text('Catalogar'),
                  ),
                ),
              ],
            ),
            if (b.notes.isNotEmpty) ...[
              const SizedBox(height: 20),
              SelectableText(b.notes),
            ],
            const SizedBox(height: 28),
            SectionTitle('Anúncios salvos no AdsPocket · ${local.length}'),
            const SizedBox(height: 4),
            Text(
              'Somente o que você catalogou. Os anúncios exibidos pela Meta e suas quantidades aparecem apenas na Biblioteca.',
              style: muted,
            ),
            const SizedBox(height: 12),
            if (local.isEmpty)
              Text(
                'Nenhuma referência catalogada para esta Página.',
                style: muted,
              )
            else
              for (final o in local)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OfferCard(
                    offer: o,
                    today: today,
                    range: app.settings.priceRange,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => OfferDetailScreen(app: app, id: o.id),
                      ),
                    ),
                  ),
                ),
            const SizedBox(height: 16),
            const SectionTitle('Histórico de visitas'),
            const SizedBox(height: 8),
            FutureBuilder<List<DateTime>>(
              future: app.visits(b),
              builder: (context, snap) {
                final visits = snap.data ?? const [];
                if (visits.isEmpty) {
                  return Text('Nenhuma visita registrada ainda.', style: muted);
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final v in visits.take(20))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          '${dateLabel(v)} · ${v.toLocal().hour.toString().padLeft(2, '0')}:${v.toLocal().minute.toString().padLeft(2, '0')}',
                        ),
                      ),
                  ],
                );
              },
            ),
            if (local.any((o) => o.analysis == Analysis.interesting)) ...[
              const SizedBox(height: 16),
              Text(
                '${local.where((o) => o.analysis == Analysis.interesting).length} marcados como interessantes.',
                style: muted,
              ),
            ],
          ],
        ),
      );
    },
  );
}
