import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../core/longevity.dart';
import '../../core/text_extraction.dart';
import '../../core/widgets.dart';
import '../../data/offer.dart';
import 'compare_screen.dart';
import 'mining_filter.dart';
import 'ocr_screen.dart';
import 'offer_detail.dart';
import 'offer_editor.dart';
import 'offer_widgets.dart';
import 'review_screen.dart';

class MiningScreen extends StatefulWidget {
  const MiningScreen({super.key, required this.app, this.embedded = false});
  final AppController app;

  /// Inside Salvos: no own title or add button.
  final bool embedded;
  @override
  State<MiningScreen> createState() => _MiningScreenState();
}

class _MiningScreenState extends State<MiningScreen> {
  // Saved ads were chosen on purpose: no age filter until the user asks.
  MiningFilter filter = const MiningFilter();
  OfferSort sort = OfferSort.oldest;
  final selected = <String>{};

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final colors = Theme.of(context).colorScheme;
    final today = CivilDate.today();
    final range = app.settings.priceRange;
    final items = filter.apply(app.offers, sort, today, range);
    final total = app.offers.length;
    final days = filter.longevity.minDays;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: selected.isNotEmpty || widget.embedded
          ? null
          : FloatingActionButton(
              tooltip: 'Catalogar referência',
              onPressed: _add,
              child: const Icon(Icons.add_rounded),
            ),
      bottomNavigationBar: selected.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => setState(selected.clear),
                      child: const Text('Cancelar'),
                    ),
                    const Spacer(),
                    Text('${selected.length} de 2'),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: selected.length == 2
                          ? () {
                              final pair = app.offers
                                  .where((o) => selected.contains(o.id))
                                  .toList();
                              Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => CompareScreen(
                                    app: app,
                                    a: pair[0],
                                    b: pair[1],
                                  ),
                                ),
                              );
                            }
                          : null,
                      child: const Text('Comparar'),
                    ),
                  ],
                ),
              ),
            ),
      body: SafeArea(
        child: Column(
          children: [
            if (!widget.embedded)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Mineração',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Revisão rápida',
                      onPressed: items.isEmpty
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => ReviewScreen(
                                  app: app,
                                  ids: [for (final o in items) o.id],
                                ),
                              ),
                            ),
                      icon: const Icon(Icons.style_outlined),
                    ),
                    IconButton(
                      tooltip: 'Comparar duas referências',
                      onPressed: total < 2
                          ? null
                          : () => app.showNotice(
                              'Toque e segure duas referências para comparar.',
                            ),
                      icon: const Icon(Icons.compare_arrows_rounded),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
              child: TextField(
                onChanged: (v) =>
                    setState(() => filter = filter.copyWith(text: v)),
                decoration: const InputDecoration(
                  hintText: 'Buscar oferta, anunciante ou nota',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                scrollDirection: Axis.horizontal,
                children: [
                  _chip(
                    days == null ? 'Qualquer idade' : '≥ $days dias',
                    filter.longevity.active,
                    Icons.schedule_rounded,
                    _filters,
                  ),
                  _chip(
                    filter.price == null ? 'Preço' : filter.price!.label,
                    filter.price != null,
                    Icons.sell_outlined,
                    () => setState(
                      () => filter = filter.copyWith(
                        price: () => filter.price == null ? range : null,
                      ),
                    ),
                  ),
                  _chip(
                    filter.activeCount > 0
                        ? 'Filtros · ${filter.activeCount}'
                        : 'Filtros',
                    false,
                    Icons.tune_rounded,
                    _filters,
                  ),
                  PopupMenuButton<OfferSort>(
                    tooltip: 'Ordenar',
                    initialValue: sort,
                    onSelected: (v) => setState(() => sort = v),
                    itemBuilder: (_) => [
                      for (final s in OfferSort.values)
                        PopupMenuItem(value: s, child: Text(s.label)),
                    ],
                    child: Chip(
                      avatar: const Icon(Icons.sort_rounded, size: 18),
                      label: Text(sort.label),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${items.length} de $total ${total == 1 ? 'anúncio' : 'anúncios'} · filtro local',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (widget.embedded) ...[
                    IconButton(
                      tooltip: 'Revisão rápida',
                      onPressed: items.isEmpty
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => ReviewScreen(
                                  app: app,
                                  ids: [for (final o in items) o.id],
                                ),
                              ),
                            ),
                      icon: const Icon(Icons.style_outlined),
                    ),
                  ],
                  if (filter.activeCount > 0 || filter.text.isNotEmpty)
                    TextButton(
                      onPressed: () => setState(
                        () => filter = const MiningFilter(
                          longevity: LongevityFilter(),
                        ),
                      ),
                      child: const Text('Limpar'),
                    ),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? SingleChildScrollView(
                      child: EmptyState(
                        icon: Icons.inventory_2_outlined,
                        title: total == 0
                            ? 'Nenhum anúncio salvo'
                            : 'Nenhuma referência neste filtro',
                        message: total == 0
                            ? 'Na Biblioteca, toque em + Salvar no card do anúncio. Data, anunciante e texto vêm preenchidos.'
                            : 'Ajuste a idade mínima, o preço ou inclua registros sem data.',
                        action: total == 0
                            ? FilledButton.tonalIcon(
                                onPressed: () => app.selectTab(Tabs.library),
                                icon: const Icon(Icons.public_rounded),
                                label: const Text('Abrir Biblioteca'),
                              )
                            : null,
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 96),
                      itemCount: items.length,
                      separatorBuilder: (_, i) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final o = items[i];
                        return OfferCard(
                          offer: o,
                          today: today,
                          range: range,
                          selected: selected.contains(o.id),
                          onTap: selected.isNotEmpty
                              ? () => _toggle(o)
                              : () => Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        OfferDetailScreen(app: app, id: o.id),
                                  ),
                                ),
                          onLongPress: () => _toggle(o),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggle(Offer o) => setState(() {
    if (!selected.remove(o.id) && selected.length < 2) selected.add(o.id);
  });

  Widget _chip(String label, bool on, IconData icon, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          avatar: Icon(icon, size: 18),
          label: Text(label),
          selected: on,
          showCheckmark: false,
          onSelected: (_) => onTap(),
        ),
      );

  Future<void> _add() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_note_rounded),
              title: const Text('Preencher manualmente'),
              onTap: () => Navigator.pop(context, 'manual'),
            ),
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Analisar print (OCR local)'),
              subtitle: const Text('Reconhece datas e preços no aparelho'),
              onTap: () => Navigator.pop(context, 'ocr'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'manual') {
      await openOfferEditor(context, widget.app);
    } else if (choice == 'ocr') {
      await analyzeImportedImage(context, widget.app);
    }
  }

  Future<void> _filters() async {
    final result = await showModalBottomSheet<MiningFilter>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FilterSheet(app: widget.app, filter: filter),
    );
    if (result != null) setState(() => filter = result);
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.app, required this.filter});
  final AppController app;
  final MiningFilter filter;
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late MiningFilter f = widget.filter;
  late final custom = TextEditingController(
    text: LongevityFilter.presets.contains(f.longevity.minDays)
        ? ''
        : '${f.longevity.minDays}',
  );
  late final min = TextEditingController(
    text: _plain((f.price ?? widget.app.settings.priceRange).minCents),
  );
  late final max = TextEditingController(
    text: _plain((f.price ?? widget.app.settings.priceRange).maxCents),
  );
  late String currency = (f.price ?? widget.app.settings.priceRange).currency;
  late bool priceOn = f.price != null;
  String? error;

  static String _plain(int c) =>
      '${c ~/ 100},${(c % 100).toString().padLeft(2, '0')}';

  @override
  void dispose() {
    custom.dispose();
    min.dispose();
    max.dispose();
    super.dispose();
  }

  void _days(int? d) => setState(
    () => f = f.copyWith(
      longevity: LongevityFilter(
        minDays: d,
        includeUndated: f.longevity.includeUndated,
      ),
    ),
  );

  PriceRange? _range() {
    final a = parseMoneyToCents(min.text), b = parseMoneyToCents(max.text);
    if (a == null || b == null) return null;
    final r = PriceRange(a, b, currency);
    return r.valid ? r : null;
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final colors = Theme.of(context).colorScheme;
    Set<String> values(String Function(Offer) pick) =>
        app.offers.map(pick).where((v) => v.isNotEmpty).toSet();
    Widget title(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
      child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
    Widget choices<T>(
      Set<T> all,
      Set<T> on,
      String Function(T) label,
      void Function(Set<T>) set,
    ) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in all)
          FilterChip(
            label: Text(label(v)),
            selected: on.contains(v),
            onSelected: (sel) =>
                setState(() => set(sel ? {...on, v} : ({...on}..remove(v)))),
          ),
      ],
    );
    Widget pick(
      String label,
      Set<String> options,
      String? value,
      void Function(String?) set,
    ) => options.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 12),
            child: DropdownButtonFormField<String?>(
              initialValue: value,
              isExpanded: true,
              decoration: InputDecoration(labelText: label),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todos')),
                for (final o in options)
                  DropdownMenuItem(value: o, child: Text(o)),
              ],
              onChanged: (v) => setState(() => set(v)),
            ),
          );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .85,
      maxChildSize: .95,
      builder: (context, scroll) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              children: [
                Text(
                  'Filtros locais',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Aplicam-se apenas às referências catalogadas no AdsPocket, nunca à Biblioteca da Meta.',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                title('Ativo há pelo menos'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final d in LongevityFilter.presets)
                      ChoiceChip(
                        label: Text(d == null ? 'Sem filtro' : '$d dias'),
                        selected:
                            f.longevity.minDays == d && custom.text.isEmpty,
                        onSelected: (_) {
                          custom.clear();
                          _days(d);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: custom,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Personalizado (0 a 365 dias)',
                    errorText: error,
                  ),
                  onChanged: (v) {
                    final n = int.tryParse(v.trim());
                    setState(
                      () => error =
                          v.trim().isEmpty || (n != null && n >= 0 && n <= 365)
                          ? null
                          : 'Use um valor entre 0 e 365.',
                    );
                    if (error == null && n != null) _days(n);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Incluir registros sem data'),
                  value: f.longevity.includeUndated,
                  onChanged: (v) => setState(
                    () => f = f.copyWith(
                      longevity: LongevityFilter(
                        minDays: f.longevity.minDays,
                        includeUndated: v,
                      ),
                    ),
                  ),
                ),
                title('Status'),
                choices<AdStatus>(
                  AdStatus.values.toSet(),
                  f.statuses,
                  (s) => s.label,
                  (v) => f = f.copyWith(statuses: v),
                ),
                title('Situação'),
                choices<Analysis>(
                  Analysis.values.toSet(),
                  f.analyses,
                  (s) => s.label,
                  (v) => f = f.copyWith(analyses: v),
                ),
                title('Tipo de mídia'),
                choices<MediaType>(
                  MediaType.values.toSet(),
                  f.media,
                  (s) => s.label,
                  (v) => f = f.copyWith(media: v),
                ),
                pick(
                  'Anunciante',
                  values((o) => o.advertiser),
                  f.advertiser,
                  (v) => f = f.copyWith(advertiser: () => v),
                ),
                pick(
                  'Nicho',
                  values((o) => o.niche),
                  f.niche,
                  (v) => f = f.copyWith(niche: () => v),
                ),
                pick(
                  'Categoria',
                  values((o) => o.category),
                  f.category,
                  (v) => f = f.copyWith(category: () => v),
                ),
                title('Preço'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Filtrar por faixa de preço'),
                  value: priceOn,
                  onChanged: (v) => setState(() => priceOn = v),
                ),
                if (priceOn) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final r in app.settings.favoriteRanges)
                        ActionChip(
                          label: Text(r.label),
                          onPressed: () => setState(() {
                            min.text = _plain(r.minCents);
                            max.text = _plain(r.maxCents);
                            currency = r.currency;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: min,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Mínimo',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: max,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Máximo',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 96,
                        child: DropdownButtonFormField<String>(
                          initialValue: currency,
                          decoration: const InputDecoration(labelText: 'Moeda'),
                          items: [
                            for (final c in currencies.keys)
                              DropdownMenuItem(value: c, child: Text(c)),
                          ],
                          onChanged: (v) => setState(() => currency = v!),
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Incluir preço desconhecido'),
                    value: f.includeUnknownPrice,
                    onChanged: (v) =>
                        setState(() => f = f.copyWith(includeUnknownPrice: v)),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => runGuarded(context, () async {
                        final r = _range();
                        if (r == null) {
                          throw const FormatException(
                            'Faixa de preço inválida.',
                          );
                        }
                        final favs = {
                          ...app.settings.favoriteRanges,
                          r,
                        }.toList();
                        if (favs.length > 10) {
                          throw const FormatException(
                            'Máximo de 10 faixas favoritas.',
                          );
                        }
                        await app.updateSettings(
                          app.settings.copyWith(favoriteRanges: favs),
                        );
                        setState(() {});
                      }),
                      icon: const Icon(Icons.star_outline_rounded),
                      label: const Text('Salvar faixa favorita'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(
                      context,
                      const MiningFilter(longevity: LongevityFilter()),
                    ),
                    child: const Text('Limpar filtros'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: error != null
                        ? null
                        : () {
                            final r = priceOn ? _range() : null;
                            if (priceOn && r == null) {
                              setState(() => error = null);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Faixa de preço inválida.'),
                                ),
                              );
                              return;
                            }
                            Navigator.pop(context, f.copyWith(price: () => r));
                          },
                    child: const Text('Aplicar'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
