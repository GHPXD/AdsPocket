import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../core/meta_ads_library_url_builder.dart';
import '../../core/widgets.dart';
import '../../core/pocket_icon.dart';
import '../../core/pocket_grid.dart';
import '../research/research_screen.dart';
import '../browser/filter_chips.dart';
import '../../data/models.dart';
import '../favorites/bookmark_editor.dart';
import '../history/history_screen.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key, required this.app});
  final AppController app;
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final query = TextEditingController();
  SearchType type = SearchType.keyword;
  String? country, status;
  bool busy = false;
  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> search([String? text]) async {
    FocusScope.of(context).unfocus();
    if (busy) return;
    setState(() => busy = true);
    await runGuarded(
      context,
      () => widget.app.search(
        text ?? query.text,
        type,
        country ?? widget.app.settings.country,
        status ?? widget.app.settings.status,
      ),
    );
    if (mounted) setState(() => busy = false);
  }

  bool allShortcuts = false;
  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
            children: [
              Row(
                children: [
                  PocketIcon(
                    PocketGlyph.pocket,
                    color: colors.primary,
                    size: 30,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'AdsPocket',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.6,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Configurações',
                    onPressed: () => app.selectTab(Tabs.settings),
                    icon: const PocketIcon(PocketGlyph.settings),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Text(
                'Encontre uma boa ideia.',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.6,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: query,
                onSubmitted: (_) => search(),
                textInputAction: TextInputAction.search,
                keyboardType: type == SearchType.pageId
                    ? TextInputType.number
                    : type == SearchType.directLink
                    ? TextInputType.url
                    : TextInputType.text,
                maxLength: type == SearchType.directLink ? 8192 : 2000,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: switch (type) {
                    SearchType.keyword => 'Palavra-chave ou produto',
                    SearchType.advertiser => 'Nome de uma Página',
                    SearchType.pageId => 'ID público da Página',
                    SearchType.directLink => 'Link da Biblioteca',
                  },
                  prefixIcon: const Padding(
                    padding: EdgeInsets.all(16),
                    child: PocketIcon(PocketGlyph.search, size: 20),
                  ),
                  suffixIcon: IconButton(
                    tooltip: 'Limpar pesquisa',
                    onPressed: query.clear,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                key: const PageStorageKey('explore-filters'),
                tilePadding: EdgeInsets.zero,
                shape: const Border(),
                collapsedShape: const Border(),
                leading: const PocketIcon(PocketGlyph.settings, size: 20),
                title: const Text(
                  'Filtros de pesquisa',
                  style: TextStyle(fontSize: 14),
                ),
                children: [
                  DropdownButtonFormField<SearchType>(
                    initialValue: type,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Pesquisar por',
                    ),
                    items: SearchType.values
                        .map(
                          (v) =>
                              DropdownMenuItem(value: v, child: Text(v.label)),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => type = v!),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _pill<String>(
                        Icons.public_rounded,
                        country ?? app.settings.country,
                        countries,
                        (v) => setState(() => country = v),
                      ),
                      _pill<String>(
                        Icons.circle_outlined,
                        status ?? app.settings.status,
                        const {'active': 'Ativos', 'all': 'Todos'},
                        (v) => setState(() => status = v),
                      ),
                      _pill<String>(
                        Icons.perm_media_outlined,
                        app.settings.media,
                        const {
                          'all': 'Todas as mídias',
                          'image': 'Imagem',
                          'video': 'Vídeo',
                        },
                        (v) => _setting(app.settings.copyWith(media: v)),
                      ),
                      daysChip(
                        value: app.settings.minDays,
                        long: true,
                        onChanged: (v) =>
                            _setting(app.settings.copyWith(minDays: () => v)),
                      ),
                      adsChip(
                        value: app.settings.minAds,
                        long: true,
                        onChanged: (v) =>
                            _setting(app.settings.copyWith(minAds: () => v)),
                      ),
                    ],
                  ),
                  if (type == SearchType.advertiser)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Selecione a Página nos controles oficiais da Meta.',
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: busy ? null : search,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const PocketIcon(PocketGlyph.arrow, size: 20),
                label: const Text('Explorar anúncios'),
              ),
              const SizedBox(height: 28),
              PocketGrid(
                children: [
                  PocketTile(
                    title: 'Pesquisa 360°',
                    subtitle: 'Nichos, fontes e estratégias',
                    glyph: PocketGlyph.explore,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ResearchScreen(app: app),
                      ),
                    ),
                  ),
                  PocketTile(
                    title: 'Seu repertório',
                    subtitle: 'Anúncios e anunciantes',
                    glyph: PocketGlyph.saved,
                    onTap: () => app.selectTab(Tabs.saved),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SectionTitle(
                'Pesquisas rápidas',
                action: IconButton(
                  tooltip: 'Editar atalhos',
                  onPressed: _editShortcuts,
                  icon: const Icon(Icons.edit_outlined, size: 19),
                ),
              ),
              const SizedBox(height: 12),
              PocketGrid(
                children: [
                  for (final term
                      in allShortcuts
                          ? app.settings.shortcuts
                          : app.settings.shortcuts.take(4))
                    Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () {
                          setState(() {
                            type = SearchType.keyword;
                            query.text = term;
                          });
                          search(term);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 20,
                          ),
                          child: Row(
                            children: [
                              PocketIcon(
                                PocketGlyph.document,
                                color: colors.primary,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  term,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (app.settings.shortcuts.length > 4)
                TextButton(
                  onPressed: () => setState(() => allShortcuts = !allShortcuts),
                  child: Text(
                    allShortcuts ? 'Mostrar menos' : 'Ver todos os atalhos',
                  ),
                ),
              if (app.initialSearch != null || app.lastAdvertiser != null) ...[
                const SizedBox(height: 20),
                const SectionTitle('Continuar pesquisa'),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      if (app.initialSearch != null)
                        ListTile(
                          leading: const PocketIcon(PocketGlyph.search),
                          title: const Text('Última pesquisa'),
                          subtitle: Text(
                            app.initialSearch!.queryParameters['q'] ??
                                'Biblioteca',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => runGuarded(
                            context,
                            () => app.openLibrary(app.initialSearch!),
                          ),
                        ),
                      if (app.lastAdvertiser != null)
                        ListTile(
                          leading: const PocketIcon(PocketGlyph.library),
                          title: const Text('Última Página visitada'),
                          subtitle: Text(
                            _pageLabel(app),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => runGuarded(
                            context,
                            () => app.openLibrary(app.lastAdvertiser!),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                shape: const Border(),
                collapsedShape: const Border(),
                title: const Text(
                  'Pesquisas recentes',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                children: [
                  if (app.history.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text(
                        'Suas pesquisas ficarão salvas neste aparelho.',
                      ),
                    ),
                  for (final h in app.history.take(3))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        h.query,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${countries[h.country]} · ${dateLabel(h.visitedAt)}',
                      ),
                      onTap: () => runGuarded(context, () => app.repeat(h)),
                      trailing: IconButton(
                        tooltip: 'Salvar pesquisa',
                        icon: const PocketIcon(PocketGlyph.saved, size: 20),
                        onPressed: () => editBookmark(
                          context,
                          app,
                          uri: Uri.parse(h.url),
                          kind: BookmarkKind.search,
                          suggestedName: h.query,
                        ),
                      ),
                    ),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => HistoryScreen(app: app),
                      ),
                    ),
                    child: const Text('Ver histórico completo'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Independente da Meta. Seus dados ficam no aparelho.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setting(UserSettings value) =>
      runGuarded(context, () => widget.app.updateSettings(value));

  Widget _pill<T>(
    IconData icon,
    T value,
    Map<T, String> options,
    ValueChanged<T> onSelected,
  ) => PopupMenuButton<T>(
    initialValue: value,
    onSelected: onSelected,
    itemBuilder: (_) => [
      for (final e in options.entries)
        PopupMenuItem(value: e.key, child: Text(e.value)),
    ],
    child: Chip(
      avatar: Icon(icon, size: 18),
      label: Text(options[value] ?? '$value'),
    ),
  );

  String _pageLabel(AppController app) {
    final id = MetaAdsLibraryUrlBuilder.pageId(app.lastAdvertiser!)!;
    final saved = app.savedAdvertiser(id);
    return saved == null ? 'Page ID $id' : '${saved.name} · Page ID $id';
  }

  Future<void> _editShortcuts() async {
    final editor = TextEditingController(
      text: widget.app.settings.shortcuts.join('\n'),
    );
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seus atalhos'),
        content: TextField(
          controller: editor,
          minLines: 5,
          maxLines: 10,
          maxLength: 2400,
          decoration: const InputDecoration(
            helperText: 'Um termo por linha. Até 30 termos de 80 caracteres.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, editor.text),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    // Dialog route animations can still reference its controller for one frame.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    editor.dispose();
    if (result == null || !mounted) return;
    await runGuarded(
      context,
      () => widget.app.updateSettings(
        widget.app.settings.copyWith(
          shortcuts: result
              .split('\n')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toSet()
              .toList(),
        ),
      ),
    );
  }
}
