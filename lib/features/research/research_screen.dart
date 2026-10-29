import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../app/app_controller.dart';
import '../../core/meta_ads_library_url_builder.dart';
import '../../core/native_bridge.dart';
import '../../core/pocket_grid.dart';
import '../../core/pocket_icon.dart';
import '../../core/widgets.dart';
import '../../data/backup_service.dart';
import '../../data/models.dart';
import '../mining/offer_detail.dart';
import 'research_engine.dart';

class ResearchScreen extends StatefulWidget {
  const ResearchScreen({super.key, required this.app});
  final AppController app;
  @override
  State<ResearchScreen> createState() => _ResearchScreenState();
}

class _ResearchScreenState extends State<ResearchScreen> {
  late final catalog = ResearchCatalog.load();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pesquisa 360°')),
    body: FutureBuilder(
      future: catalog,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('Não foi possível abrir a base local.'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final c = snapshot.data!;
        void page(Widget child) => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => child),
        );
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'O que você quer descobrir?',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text('Escolha uma ferramenta para começar.'),
            const SizedBox(height: 24),
            PocketGrid(
              children: [
                PocketTile(
                  title: 'Nichos e subnichos',
                  glyph: PocketGlyph.grid,
                  onTap: () => page(_Niches(app: widget.app, catalog: c)),
                ),
                PocketTile(
                  title: 'Palavras-chave',
                  glyph: PocketGlyph.search,
                  onTap: () => page(_Keywords(app: widget.app, catalog: c)),
                ),
                PocketTile(
                  title: 'Construir pesquisa',
                  glyph: PocketGlyph.explore,
                  onTap: () => page(MiningBuilder(app: widget.app, catalog: c)),
                ),
                PocketTile(
                  title: 'Pacotes de pesquisa',
                  glyph: PocketGlyph.layers,
                  onTap: () => page(
                    ResearchRecordsScreen(
                      app: widget.app,
                      catalog: c,
                      kind: ResearchKind.package,
                    ),
                  ),
                ),
                PocketTile(
                  title: 'Fontes de pesquisa',
                  glyph: PocketGlyph.source,
                  onTap: () => page(_Sources(app: widget.app)),
                ),
                PocketTile(
                  title: 'Detectar tecnologias',
                  glyph: PocketGlyph.scan,
                  onTap: () => page(_Detector(app: widget.app)),
                ),
                PocketTile(
                  title: 'Dossiês e evidências',
                  glyph: PocketGlyph.evidence,
                  onTap: () => page(
                    ResearchRecordsScreen(
                      app: widget.app,
                      catalog: c,
                      kind: ResearchKind.dossier,
                    ),
                  ),
                ),
                PocketTile(
                  title: 'Agrupar referências',
                  glyph: PocketGlyph.saved,
                  onTap: () => page(_Groups(app: widget.app)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Sobre a base de conhecimento'),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    '${c.terms.length} expressões · ${c.niches.length} nichos.\n${c.data['sourceStatus']}\nClassificações e promessas do material não comprovam eficácia, receita ou escala.',
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

Future<void> launchResearch(
  BuildContext context,
  AppController app,
  String query,
  String source, {
  String country = 'BR',
  String status = 'active',
}) async {
  if (source == 'meta') {
    Navigator.popUntil(context, (r) => r.isFirst);
    await app.search(query, SearchType.keyword, country, status);
  } else {
    final provider = MiningSourceRegistry.sources.firstWhere(
      (s) => s.id == source,
    );
    if (!provider.query) {
      await copyLink(context, query);
      if (!context.mounted) return;
    }
    await app.openExternal(provider.search(query));
  }
}

class _Niches extends StatelessWidget {
  const _Niches({required this.app, required this.catalog});
  final AppController app;
  final ResearchCatalog catalog;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Nichos e subnichos')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        for (final niche in catalog.niches)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ExpansionTile(
              title: Text(niche['name'] as String),
              children: [
                for (final sub in niche['subniches'] as List)
                  ListTile(
                    title: Text(sub as String),
                    trailing: const PocketIcon(PocketGlyph.arrow, size: 18),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => MiningBuilder(
                          app: app,
                          catalog: catalog,
                          initial: {'niche': niche['name'], 'subniche': sub},
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _Keywords extends StatefulWidget {
  const _Keywords({required this.app, required this.catalog});
  final AppController app;
  final ResearchCatalog catalog;
  @override
  State<_Keywords> createState() => _KeywordsState();
}

class _KeywordsState extends State<_Keywords> {
  String text = '';
  String? niche;
  @override
  Widget build(BuildContext context) {
    final terms = widget.catalog.find(text, niche: niche);
    return Scaffold(
      appBar: AppBar(title: const Text('Palavras-chave')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                TextField(
                  onChanged: (v) => setState(() => text = v),
                  decoration: const InputDecoration(
                    hintText: 'Buscar expressão',
                    prefixIcon: PocketIcon(PocketGlyph.search),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: niche ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Nicho'),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Todos os nichos'),
                    ),
                    for (final n in widget.catalog.niches)
                      DropdownMenuItem(
                        value: n['name'] as String,
                        child: Text(n['name'] as String),
                      ),
                  ],
                  onChanged: (v) => setState(() => niche = v == '' ? null : v),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: terms.length,
              itemBuilder: (context, i) {
                final t = terms[i];
                return ListTile(
                  title: Text(t['text'] as String),
                  subtitle: Text(
                    '${t['sourceId']} · ${t['category']}${t['historical'] == true ? ' · histórico' : ''}',
                  ),
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (context) => SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              t['text'] as String,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Origem: ${t['sourceId']}\nPáginas: ${t['pageRange'] ?? 'não se aplica'} (intervalo informado)\n${t['note']}',
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: () => runGuarded(
                                context,
                                () => launchResearch(
                                  context,
                                  widget.app,
                                  t['text'] as String,
                                  'meta',
                                  country: widget.app.settings.country,
                                  status: widget.app.settings.status,
                                ),
                              ),
                              child: const Text('Pesquisar na Meta'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class MiningBuilder extends StatefulWidget {
  const MiningBuilder({
    super.key,
    required this.app,
    required this.catalog,
    this.initial = const {},
    this.existing,
  });
  final AppController app;
  final ResearchCatalog catalog;
  final Map<String, dynamic> initial;
  final ResearchRecord? existing;
  @override
  State<MiningBuilder> createState() => _MiningBuilderState();
}

class _MiningBuilderState extends State<MiningBuilder> {
  late final plan = <String, dynamic>{
    'niche': '',
    'subniche': '',
    'format': 'Planilha pronta',
    'commercial': '',
    'price': '',
    'country': widget.app.settings.country,
    'status': widget.app.settings.status,
    'sourceId': 'meta',
    'media': widget.app.settings.media,
    'minDays': widget.app.settings.minDays?.toString() ?? '',
    'minAds': widget.app.settings.minAds?.toString() ?? '',
    'language': 'Português',
    ...widget.initial,
    ...?widget.existing?.data,
  };
  late final problem = TextEditingController(
    text: plan['problem'] as String? ?? '',
  );
  late final benefit = TextEditingController(
    text: plan['benefit'] as String? ?? '',
  );
  late final excluded = TextEditingController(
    text: plan['excluded'] as String? ?? '',
  );
  late final minDays = TextEditingController(
    text: plan['minDays'] as String? ?? '',
  );
  late final minAds = TextEditingController(
    text: plan['minAds'] as String? ?? '',
  );
  late final notes = TextEditingController(
    text: plan['notes'] as String? ?? '',
  );
  List<String> queries = [];
  late int limit = plan['limit'] as int? ?? 8;
  @override
  void dispose() {
    for (final c in [problem, benefit, excluded, minDays, minAds, notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget select(
    String field,
    String label,
    List<String> values, {
    List<String>? labels,
  }) => DropdownButtonFormField<String>(
    key: ValueKey('$field:${plan[field]}'),
    initialValue: values.contains(plan[field])
        ? plan[field] as String
        : values.first,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      for (var i = 0; i < values.length; i++)
        DropdownMenuItem(
          value: values[i],
          child: Text(
            labels?[i] ?? (values[i].isEmpty ? 'Sem preferência' : values[i]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: (v) => setState(() {
      plan[field] = v;
      if (field == 'niche') plan['subniche'] = '';
      queries = [];
    }),
  );
  void generate() {
    plan.addAll({
      'problem': problem.text.trim(),
      'benefit': benefit.text.trim(),
      'excluded': excluded.text.trim(),
      'minDays': minDays.text.trim(),
      'minAds': minAds.text.trim(),
      'notes': notes.text.trim(),
      'limit': limit,
      'sources': [plan['sourceId']],
    });
    setState(
      () => queries = KeywordMiningEngine().generate(
        niche: plan['niche'] as String,
        subniche: plan['subniche'] as String,
        problem: problem.text,
        benefit: benefit.text,
        delivery:
            (widget.catalog.data['deliveryTerms'] as List).first as String,
        update: (widget.catalog.data['updateTerms'] as List).first as String,
        variants:
            ((widget.catalog.data['formatVariants'] as Map)[plan['format']]
                        as List? ??
                    [])
                .cast<String>(),
        format: plan['format'] as String,
        commercial: [
          plan['commercial'],
          plan['price'],
        ].where((x) => x.toString().isNotEmpty).join(' '),
        limit: limit,
        excluded: excluded.text.split(','),
      ),
    );
  }

  Future<void> open(String query) => runGuarded(context, () async {
    int? number(TextEditingController c, int max, {int min = 1}) {
      if (c.text.trim().isEmpty) return null;
      final n = int.tryParse(c.text);
      if (n == null || n < min || n > max) {
        throw const FormatException('Filtros numéricos inválidos.');
      }
      return n;
    }

    if (plan['sourceId'] == 'meta') {
      final days = number(minDays, 36500, min: 0), ads = number(minAds, 1000);
      await widget.app.updateSettings(
        widget.app.settings.copyWith(
          media: plan['media'] as String,
          minDays: () => days,
          minAds: () => ads,
        ),
      );
    }
    if (widget.existing != null) {
      await widget.app.saveResearch(
        ResearchRecord(
          id: widget.existing!.id,
          name: widget.existing!.name,
          kind: ResearchKind.package,
          createdAt: widget.existing!.createdAt,
          data: {
            ...widget.existing!.data,
            'lastUsedAt': DateTime.now().toUtc().toIso8601String(),
          },
        ),
      );
    }
    if (!mounted) return;
    await launchResearch(
      context,
      widget.app,
      query,
      plan['sourceId'] as String,
      country: plan['country'] as String,
      status: plan['status'] as String,
    );
  });
  @override
  Widget build(BuildContext context) {
    final niche = widget.catalog.niches
        .where((n) => n['name'] == plan['niche'])
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Construir pesquisa'),
        actions: [
          IconButton(
            tooltip: 'Salvar pacote',
            icon: const PocketIcon(PocketGlyph.saved),
            onPressed: () => _save(),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              select('niche', 'Nicho', [
                '',
                ...widget.catalog.niches.map((n) => n['name'] as String),
              ]),
              const SizedBox(height: 12),
              select('subniche', 'Subnicho', [
                '',
                ...?((niche?['subniches'] as List?)?.cast<String>()),
              ]),
              const SizedBox(height: 12),
              select('format', 'Formato', widget.catalog.formats),
              const SizedBox(height: 16),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Refinar pesquisa'),
                children: [
                  TextField(
                    controller: problem,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'Problema ou palavra-chave',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: benefit,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'Benefício ou solução (opcional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  select('commercial', 'Termo comercial', [
                    '',
                    ...(widget.catalog.data['commercial'] as List)
                        .cast<String>(),
                  ]),
                  const SizedBox(height: 12),
                  select('price', 'Preço (critério local)', [
                    '',
                    ...(widget.catalog.data['priceRanges'] as List)
                        .cast<String>(),
                  ]),
                  const SizedBox(height: 12),
                  select(
                    'country',
                    'País',
                    countries.keys.toList(),
                    labels: countries.values.toList(),
                  ),
                  const SizedBox(height: 12),
                  select(
                    'sourceId',
                    'Fonte',
                    MiningSourceRegistry.sources.map((s) => s.id).toList(),
                    labels: MiningSourceRegistry.sources
                        .map((s) => s.name)
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  select(
                    'status',
                    'Status',
                    ['active', 'all'],
                    labels: ['Ativos', 'Todos disponíveis'],
                  ),
                  const SizedBox(height: 12),
                  select(
                    'media',
                    'Mídia',
                    ['all', 'image', 'video'],
                    labels: ['Todas', 'Imagem', 'Vídeo'],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: minDays,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Idade mínima em dias (assistente local)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: minAds,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText:
                          'Quantidade mínima conhecida (assistente local)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  select('language', 'Idioma (critério local)', [
                    'Português',
                    'Inglês',
                    'Espanhol',
                  ]),
                  const SizedBox(height: 12),
                  TextField(
                    controller: excluded,
                    decoration: const InputDecoration(
                      labelText: 'Excluir termos, separados por vírgulas',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notes,
                    maxLength: 10000,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Notas do pacote',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: limit,
                    decoration: const InputDecoration(
                      labelText: 'Limite de sugestões',
                    ),
                    items: [
                      for (final n in [4, 8, 12, 20, 30])
                        DropdownMenuItem(value: n, child: Text('$n')),
                    ],
                    onChanged: (n) => setState(() => limit = n!),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Preço, idioma e nicho orientam a pesquisa local. Não são filtros oficiais da Meta. Outras fontes abrem em navegação assistida.',
                  ),
                  const SizedBox(height: 16),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: generate,
                icon: const PocketIcon(PocketGlyph.layers),
                label: const Text('Gerar sugestões'),
              ),
              if (queries.isNotEmpty) ...[
                const SizedBox(height: 24),
                const SectionTitle('Escolha uma pesquisa'),
                const SizedBox(height: 12),
                for (final q in queries)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(q),
                      trailing: const PocketIcon(PocketGlyph.arrow, size: 18),
                      onTap: () => open(q),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    generate();
    final name = await askResearchName(
      context,
      widget.existing?.name ??
          '${plan['format']} · ${plan['niche'].toString().isEmpty ? 'Pesquisa' : plan['niche']}',
    );
    if (name == null || !mounted) return;
    await runGuarded(context, () async {
      await widget.app.saveResearch(
        ResearchRecord(
          id: widget.existing?.id ?? localId(),
          name: name,
          kind: ResearchKind.package,
          createdAt: widget.existing?.createdAt ?? DateTime.now().toUtc(),
          data: {
            ...plan,
            'queries': queries,
            'notes': plan['notes'] ?? '',
            'lastUsedAt': plan['lastUsedAt'],
          },
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pacote salvo neste aparelho.')),
        );
      }
    });
  }
}

Future<String?> askResearchName(BuildContext context, String initial) async {
  final controller = TextEditingController(text: initial);
  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Nome do pacote'),
      content: TextField(controller: controller, maxLength: 200),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (controller.text.trim().isNotEmpty) {
              Navigator.pop(context, controller.text.trim());
            }
          },
          child: const Text('Salvar'),
        ),
      ],
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  controller.dispose();
  return value;
}

class ResearchRecordsScreen extends StatelessWidget {
  const ResearchRecordsScreen({
    super.key,
    required this.app,
    required this.catalog,
    required this.kind,
  });
  final AppController app;
  final ResearchCatalog catalog;
  final ResearchKind kind;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: app,
    builder: (context, _) {
      final records =
          app.research
              .where(
                (r) =>
                    r.kind == kind ||
                    (kind == ResearchKind.dossier &&
                        r.kind == ResearchKind.evidence),
              )
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return Scaffold(
        appBar: AppBar(
          title: Text(
            kind == ResearchKind.package
                ? 'Pacotes de pesquisa'
                : 'Dossiês e evidências',
          ),
          actions: [
            IconButton(
              tooltip: 'Importar JSON',
              icon: const Icon(Icons.file_download_outlined),
              onPressed: () => runGuarded(context, () async {
                final text = await NativeBridge.importBackup();
                if (text == null) return;
                final backup = BackupService.decode(text);
                if (!context.mounted) return;
                if (await confirm(
                      context,
                      'Importar pesquisa?',
                      '${backup.research.length} registros serão mesclados, preservando os existentes.',
                    ) &&
                    context.mounted) {
                  await app.importBackup(
                    BackupData([], [], app.settings, [], backup.research),
                  );
                }
              }),
            ),
            PopupMenuButton<String>(
              tooltip: 'Adicionar',
              onSelected: (v) {
                if (v == 'package') {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => MiningBuilder(app: app, catalog: catalog),
                    ),
                  );
                } else {
                  editResearchRecord(
                    context,
                    app,
                    kind: v == 'evidence'
                        ? ResearchKind.evidence
                        : ResearchKind.dossier,
                  );
                }
              },
              itemBuilder: (_) => [
                if (kind == ResearchKind.package)
                  const PopupMenuItem(
                    value: 'package',
                    child: Text('Novo pacote'),
                  )
                else ...[
                  const PopupMenuItem(
                    value: 'dossier',
                    child: Text('Novo dossiê'),
                  ),
                  const PopupMenuItem(
                    value: 'evidence',
                    child: Text('Nova evidência'),
                  ),
                ],
              ],
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (kind == ResearchKind.package) ...[
              const SectionTitle('Comece com um modelo'),
              const SizedBox(height: 12),
              PocketGrid(
                children: [
                  for (final p in catalog.presets)
                    PocketTile(
                      title: p['name'] as String,
                      glyph: PocketGlyph.layers,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => MiningBuilder(
                            app: app,
                            catalog: catalog,
                            initial: {...p}..remove('name'),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              const SectionTitle('Seus pacotes'),
              const SizedBox(height: 12),
            ],
            if (records.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Nenhum registro salvo. Use o menu Adicionar para começar.',
                ),
              ),
            for (final record in records)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: PocketIcon(
                    record.kind == ResearchKind.package
                        ? PocketGlyph.layers
                        : PocketGlyph.evidence,
                  ),
                  title: Text(record.name),
                  subtitle: Text(
                    '${record.kind == ResearchKind.package
                        ? 'Pacote'
                        : record.kind == ResearchKind.dossier
                        ? 'Dossiê'
                        : 'Evidência'} · ${dateLabel(record.createdAt)}',
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => record.kind == ResearchKind.package
                          ? MiningBuilder(
                              app: app,
                              catalog: catalog,
                              existing: record,
                            )
                          : _RecordDetail(app: app, id: record.id),
                    ),
                  ),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Opções do registro',
                    onSelected: (v) => runGuarded(context, () async {
                      if (v == 'duplicate') {
                        await app.saveResearch(record.duplicate());
                      }
                      if (v == 'edit' && context.mounted) {
                        if (record.kind == ResearchKind.package) {
                          await Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => MiningBuilder(
                                app: app,
                                catalog: catalog,
                                existing: record,
                              ),
                            ),
                          );
                        } else {
                          await editResearchRecord(
                            context,
                            app,
                            kind: record.kind,
                            existing: record,
                          );
                        }
                      }
                      if (v == 'export') {
                        await NativeBridge.exportBackup(
                          BackupService.encode([], [], app.settings, [], [
                            record,
                          ]),
                        );
                      }
                      if (v == 'share') {
                        final json = BackupService.encode(
                          [],
                          [],
                          app.settings,
                          [],
                          [record],
                        );
                        await SharePlus.instance.share(
                          ShareParams(
                            files: [
                              XFile.fromData(
                                utf8.encode(json),
                                mimeType: 'application/json',
                                name: 'adspocket-pesquisa.json',
                              ),
                            ],
                            fileNameOverrides: ['adspocket-pesquisa.json'],
                          ),
                        );
                      }
                      if (v == 'delete' &&
                          context.mounted &&
                          await confirm(
                            context,
                            'Remover registro?',
                            record.name,
                            action: 'Remover',
                          )) {
                        await app.deleteResearch(record.id);
                      }
                    }),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Editar')),
                      PopupMenuItem(
                        value: 'duplicate',
                        child: Text('Duplicar'),
                      ),
                      PopupMenuItem(
                        value: 'export',
                        child: Text('Exportar JSON'),
                      ),
                      PopupMenuItem(
                        value: 'share',
                        child: Text('Compartilhar JSON'),
                      ),
                      PopupMenuItem(value: 'delete', child: Text('Remover')),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

Future<void> editResearchRecord(
  BuildContext context,
  AppController app, {
  required ResearchKind kind,
  ResearchRecord? existing,
  List<String> offerIds = const [],
}) async {
  final name = TextEditingController(text: existing?.name ?? '');
  final notes = TextEditingController(
    text: existing?.data['notes'] as String? ?? '',
  );
  final url = TextEditingController(
    text: existing?.data['sourceUrl'] as String? ?? '',
  );
  final offers = {
    ...?((existing?.data['offerIds'] as List?)?.cast<String>()),
    ...offerIds,
  };
  final evidence = {
    ...?((existing?.data['evidenceIds'] as List?)?.cast<String>()),
  };
  var confidence =
      existing?.data['confidence'] as String? ?? 'Informado pelo usuário';
  final form = GlobalKey<FormState>();
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(kind == ResearchKind.dossier ? 'Dossiê' : 'Evidência'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: 'Nome'),
                    validator: (s) =>
                        s!.trim().isEmpty ? 'Informe um nome.' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: url,
                    maxLength: 8192,
                    decoration: const InputDecoration(
                      labelText: 'URL da fonte (HTTPS, opcional)',
                    ),
                    validator: (s) =>
                        s!.trim().isNotEmpty &&
                            MetaAdsLibraryUrlBuilder.safeHttps(s.trim()) == null
                        ? 'Use HTTPS.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: confidence,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Confiabilidade',
                    ),
                    items: [
                      for (final s in [
                        'Informado pelo usuário',
                        'Observado em fonte pública',
                        'Estimativa',
                        'Desconhecido',
                      ])
                        DropdownMenuItem(value: s, child: Text(s)),
                    ],
                    onChanged: (v) => confidence = v!,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: notes,
                    maxLength: 10000,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Evidência, hipótese ou observações',
                    ),
                  ),
                  ExpansionTile(
                    title: const Text('Relacionar anúncios'),
                    children: [
                      for (final o in app.offers)
                        CheckboxListTile(
                          value: offers.contains(o.id),
                          title: Text(o.name),
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              offers.add(o.id);
                            } else {
                              offers.remove(o.id);
                            }
                          }),
                        ),
                    ],
                  ),
                  if (kind == ResearchKind.dossier)
                    ExpansionTile(
                      title: const Text('Relacionar evidências'),
                      children: [
                        for (final r in app.research.where(
                          (r) => r.kind == ResearchKind.evidence,
                        ))
                          CheckboxListTile(
                            value: evidence.contains(r.id),
                            title: Text(r.name),
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                evidence.add(r.id);
                              } else {
                                evidence.remove(r.id);
                              }
                            }),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    ),
  );
  final record = ResearchRecord(
    id: existing?.id ?? localId(),
    name: name.text.trim(),
    kind: kind,
    createdAt: existing?.createdAt ?? DateTime.now().toUtc(),
    data: {
      ...?existing?.data,
      'notes': notes.text.trim(),
      'sourceUrl': url.text.trim(),
      'confidence': confidence,
      'collectedAt':
          existing?.data['collectedAt'] ??
          DateTime.now().toUtc().toIso8601String(),
      'offerIds': offers.toList(),
      'evidenceIds': evidence.toList(),
    },
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  for (final c in [name, notes, url]) {
    c.dispose();
  }
  if (saved == true && context.mounted) {
    await runGuarded(context, () => app.saveResearch(record));
  }
}

class _RecordDetail extends StatelessWidget {
  const _RecordDetail({required this.app, required this.id});
  final AppController app;
  final String id;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: app,
    builder: (context, _) {
      final r = app.research.where((r) => r.id == id).firstOrNull;
      return Scaffold(
        appBar: AppBar(
          title: Text(r?.name ?? 'Registro removido'),
          actions: [
            if (r != null)
              IconButton(
                tooltip: 'Editar registro',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () =>
                    editResearchRecord(context, app, kind: r.kind, existing: r),
              ),
          ],
        ),
        body: r == null
            ? null
            : ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(r.data['notes'] as String? ?? ''),
                  const SizedBox(height: 16),
                  Text(
                    'Confiabilidade: ${r.data['confidence'] ?? 'Desconhecida'}\nColeta: ${r.data['collectedAt'] ?? r.createdAt.toIso8601String()}',
                  ),
                  if (r.data['detectionConfidence'] != null)
                    Text(
                      'Detecção: ${r.data['detectionConfidence']} · regra ${r.data['ruleVersion']}',
                    ),
                  if ((r.data['sourceUrl'] as String? ?? '').isNotEmpty)
                    TextButton(
                      onPressed: () => runGuarded(
                        context,
                        () => app.openExternal(
                          Uri.parse(r.data['sourceUrl'] as String),
                        ),
                      ),
                      child: const Text('Abrir fonte'),
                    ),
                  const SizedBox(height: 24),
                  const SectionTitle('Anúncios relacionados'),
                  for (final o in app.offers.where(
                    (o) => (r.data['offerIds'] as List? ?? []).contains(o.id),
                  ))
                    ListTile(
                      title: Text(o.name),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => OfferDetailScreen(app: app, id: o.id),
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  const SectionTitle('Evidências relacionadas'),
                  for (final e in app.research.where(
                    (e) =>
                        (r.data['evidenceIds'] as List? ?? []).contains(e.id),
                  ))
                    ListTile(
                      title: Text(e.name),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => _RecordDetail(app: app, id: e.id),
                        ),
                      ),
                    ),
                ],
              ),
      );
    },
  );
}

class _Sources extends StatelessWidget {
  const _Sources({required this.app});
  final AppController app;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Fontes de pesquisa')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Navegação assistida. Nenhuma fonte abaixo importa métricas automaticamente.',
        ),
        const SizedBox(height: 16),
        PocketGrid(
          children: [
            for (final s in MiningSourceRegistry.sources)
              PocketTile(
                title: s.name,
                subtitle: s.category,
                glyph: PocketGlyph.source,
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (context) => SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            s.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${s.capabilities.join(' · ')}\n${s.authRequired ? 'Pode exigir conta. ' : ''}${s.paidAccess ? 'Pode conter funções pagas. ' : ''}Sem API conectada. Disponibilidade e filtros dependem do provedor.',
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => runGuarded(
                              context,
                              () => app.openExternal(Uri.parse(s.url)),
                            ),
                            child: const Text('Abrir fonte oficial'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

class _Detector extends StatefulWidget {
  const _Detector({required this.app});
  final AppController app;
  @override
  State<_Detector> createState() => _DetectorState();
}

class _DetectorState extends State<_Detector> {
  final url = TextEditingController(), content = TextEditingController();
  List<Detection>? results;
  @override
  void dispose() {
    url.dispose();
    content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Checkouts e tecnologias')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TextField(
          controller: url,
          keyboardType: TextInputType.url,
          maxLength: 8192,
          decoration: const InputDecoration(labelText: 'URL pública HTTPS'),
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Analisar conteúdo público fornecido'),
          children: [
            TextField(
              controller: content,
              minLines: 4,
              maxLines: 8,
              maxLength: 500000,
              decoration: const InputDecoration(
                hintText:
                    'Cole HTML público ou texto que você obteve legitimamente.',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => runGuarded(context, () async {
            setState(
              () => results = PublicTechnologyDetector().detect(
                url.text,
                publicText: content.text,
              ),
            );
          }),
          child: const Text('Verificar evidências'),
        ),
        const SizedBox(height: 12),
        const Text(
          'Análise local. Não abre páginas, não intercepta tráfego e não confirma vendas. Indicadores em HTML são prováveis, pois podem estar inativos.',
        ),
        const SizedBox(height: 24),
        if (results != null && results!.isEmpty)
          const Text(
            'Tecnologia desconhecida: nenhum indicador coberto pelas regras foi encontrado.',
          ),
        for (final r in results ?? <Detection>[])
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              title: Text(r.technology),
              subtitle: Text(
                '${r.confidence}\n${r.evidence}\nRegra ${r.ruleVersion}',
              ),
              isThreeLine: true,
              trailing: IconButton(
                tooltip: 'Salvar evidência',
                icon: const PocketIcon(PocketGlyph.saved),
                onPressed: () => runGuarded(
                  context,
                  () => widget.app.saveResearch(
                    ResearchRecord(
                      id: localId(),
                      name: r.technology,
                      kind: ResearchKind.evidence,
                      createdAt: DateTime.now().toUtc(),
                      data: {
                        ...r.toJson(),
                        'confidence': 'Informado pelo usuário',
                        'detectionConfidence': r.confidence,
                        'sourceUrl': url.text.trim(),
                        'notes': r.evidence,
                        'offerIds': <String>[],
                        'evidenceIds': <String>[],
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _Groups extends StatelessWidget {
  const _Groups({required this.app});
  final AppController app;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: app,
    builder: (context, _) {
      final groups = OfferGroup.group(app.offers);
      return Scaffold(
        appBar: AppBar(title: const Text('Agrupar referências')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Sugestões locais, sem mesclar ou apagar anúncios. Domínio de checkout sozinho não cria grupos.',
            ),
            const SizedBox(height: 16),
            if (groups.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Nenhum grupo encontrado. Cadastre referências com a mesma URL de oferta ou Page ID e nome.',
                ),
              ),
            for (final g in groups)
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  title: Text(
                    '${g.offers.length} referências · ${g.offers.first.name}',
                  ),
                  subtitle: Text(g.reason),
                  children: [
                    for (final o in g.offers)
                      ListTile(
                        title: Text(o.name),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                OfferDetailScreen(app: app, id: o.id),
                          ),
                        ),
                      ),
                    TextButton(
                      onPressed: () => editResearchRecord(
                        context,
                        app,
                        kind: ResearchKind.dossier,
                        offerIds: g.offers.map((o) => o.id).toList(),
                      ),
                      child: const Text('Criar dossiê com este grupo'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}
