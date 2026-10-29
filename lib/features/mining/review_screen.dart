import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/app_controller.dart';
import '../../core/longevity.dart';
import '../../core/widgets.dart';
import '../../data/offer.dart';
import 'offer_widgets.dart';

/// One reference at a time, large one-hand actions, undo for every change.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.app, required this.ids});
  final AppController app;
  final List<String> ids;
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  int index = 0;
  final done = <Analysis, int>{};

  Offer? get current => index >= widget.ids.length
      ? null
      : widget.app.offers.where((o) => o.id == widget.ids[index]).firstOrNull;

  Future<void> _apply(
    Offer next, {
    bool advance = false,
    String? message,
  }) async {
    final before = current!;
    await runGuarded(context, () async {
      await widget.app.saveOffer(next);
      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      final from = index;
      setState(() {
        if (advance) {
          done[next.analysis] = (done[next.analysis] ?? 0) + 1;
          index++;
        }
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            persist: false,
            duration: const Duration(seconds: 4),
            content: Text(message ?? 'Marcado como ${next.analysis.label}.'),
            action: SnackBarAction(
              label: 'Desfazer',
              onPressed: () => runGuarded(context, () async {
                await widget.app.saveOffer(before);
                if (!mounted) return;
                setState(() {
                  if (advance) {
                    done[next.analysis] = (done[next.analysis] ?? 1) - 1;
                  }
                  index = from;
                });
              }),
            ),
          ),
        );
    });
  }

  Future<void> _note(Offer o) async {
    final input = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Adicionar nota'),
        content: TextField(
          controller: input,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          maxLength: 2000,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text.trim()),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    input.dispose();
    if (text == null || text.isEmpty) return;
    final notes = o.notes.isEmpty ? text : '${o.notes}\n$text';
    if (notes.length > 10000) {
      widget.app.showNotice(
        'As notas atingiram o limite de 10.000 caracteres.',
      );
      return;
    }
    await _apply(o.copyWith(notes: notes), message: 'Nota adicionada.');
  }

  Future<void> _date(Offer o) async {
    final today = CivilDate.today();
    final picked = await showDatePicker(
      context: context,
      initialDate: (o.startDate ?? today).toLocalDateTime(),
      firstDate: DateTime(2018),
      lastDate: today.toLocalDateTime(),
      helpText: 'Confirmar data de início',
    );
    if (picked == null) return;
    await _apply(
      o.copyWith(
        startDate: CivilDate.fromDateTime(picked),
        dateSource: DateSource.manual,
      ),
      message: 'Data de início confirmada.',
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.app,
    builder: (context, _) {
      final o = current;
      final colors = Theme.of(context).colorScheme;
      final today = CivilDate.today();
      return Scaffold(
        appBar: AppBar(
          title: Text(
            o == null
                ? 'Revisão concluída'
                : '${index + 1} de ${widget.ids.length}',
          ),
        ),
        body: o == null
            ? Center(
                child: EmptyState(
                  icon: Icons.task_alt_rounded,
                  title: 'Tudo revisado',
                  message: done.isEmpty
                      ? 'Nenhuma classificação nesta sessão.'
                      : done.entries
                            .where((e) => e.value > 0)
                            .map((e) => '${e.key.label}: ${e.value}')
                            .join(' · '),
                  action: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Voltar à Mineração'),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  Text(
                    o.name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (o.advertiser.isNotEmpty)
                    Text(
                      o.advertiser,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Pill(
                        ageLabel(o.age(today)),
                        icon: Icons.schedule_rounded,
                      ),
                      Pill(
                        o.status.label,
                        icon: Icons.circle,
                        color: statusColor(o.status, colors),
                      ),
                      Pill(priceLabel(o), icon: Icons.sell_outlined),
                      Pill(o.mediaType.label),
                      Pill('Atual: ${o.analysis.label}'),
                    ],
                  ),
                  for (final (label, value) in [
                    ('Hook', o.hook),
                    ('Headline', o.headline),
                    ('Ângulo', o.angle),
                    ('Notas', o.notes),
                  ])
                    if (value.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      Text(value, style: const TextStyle(fontSize: 16)),
                    ],
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.ad_units_outlined, size: 18),
                        label: const Text('Anúncio'),
                        onPressed: adLink(o) == null
                            ? null
                            : () => openAd(context, widget.app, o),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.storefront_outlined, size: 18),
                        label: const Text('Anunciante'),
                        onPressed: o.pageId == null
                            ? null
                            : () => openAdvertiser(context, widget.app, o),
                      ),
                      ActionChip(
                        avatar: const Icon(
                          Icons.shopping_cart_outlined,
                          size: 18,
                        ),
                        label: const Text('Página de vendas'),
                        onPressed: o.salesUrl == null
                            ? null
                            : () => openSales(context, widget.app, o),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.notes_rounded, size: 18),
                        label: const Text('Nota'),
                        onPressed: () => _note(o),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.event_outlined, size: 18),
                        label: const Text('Confirmar data'),
                        onPressed: () => _date(o),
                      ),
                    ],
                  ),
                ],
              ),
        bottomNavigationBar: o == null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          _big(
                            'Descartar',
                            Icons.close_rounded,
                            colors.error,
                            () => _apply(
                              o.copyWith(analysis: Analysis.discarded),
                              advance: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _big(
                            'Observar',
                            Icons.visibility_outlined,
                            colors.tertiary,
                            () => _apply(
                              o.copyWith(analysis: Analysis.watching),
                              advance: true,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _big(
                            'Interessante',
                            Icons.favorite_border_rounded,
                            const Color(0xFF22A06B),
                            () => _apply(
                              o.copyWith(analysis: Analysis.interesting),
                              advance: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _apply(
                                o.copyWith(analysis: Analysis.futureModel),
                                advance: true,
                              ),
                              icon: const Icon(Icons.bookmark_add_outlined),
                              label: const Text('Salvar para modelar'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => setState(() => index++),
                            child: const Text('Pular'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      );
    },
  );

  Widget _big(String label, IconData icon, Color color, VoidCallback onTap) =>
      Expanded(
        child: SizedBox(
          height: 64,
          child: FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: color,
              backgroundColor: color.withValues(alpha: .14),
              padding: EdgeInsets.zero,
            ),
            onPressed: onTap,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon),
                const SizedBox(height: 2),
                Text(label, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      );
}
