import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../core/meta_ads_library_url_builder.dart';
import '../../core/widgets.dart';
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

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            children: [
              Row(
                children: [
                  Icon(Icons.layers_rounded, color: colors.primary, size: 26),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'AdsPocket',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.5,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Configurações',
                    onPressed: () => app.selectTab(Tabs.settings),
                    icon: const Icon(Icons.tune_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Text(
                'O que vamos pesquisar?',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.5,
                ),
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<SearchType>(
                        initialValue: type,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Pesquisar por',
                        ),
                        items: SearchType.values
                            .map(
                              (v) => DropdownMenuItem(
                                value: v,
                                child: Text(v.label),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => type = v!),
                      ),
                      const SizedBox(height: 16),
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
                            SearchType.keyword => 'Ex.: planilha financeira',
                            SearchType.advertiser => 'Nome de uma Página',
                            SearchType.pageId => 'ID numérico público',
                            SearchType.directLink =>
                              'https://www.facebook.com/ads/library/…',
                          },
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: IconButton(
                            tooltip: 'Limpar pesquisa',
                            onPressed: query.clear,
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Filters chosen before the search; age and "only
                      // active" are applied by the Library assistant.
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
                            onChanged: (v) => _setting(
                              app.settings.copyWith(minDays: () => v),
                            ),
                          ),
                          adsChip(
                            value: app.settings.minAds,
                            long: true,
                            onChanged: (v) => _setting(
                              app.settings.copyWith(minAds: () => v),
                            ),
                          ),
                        ],
                      ),
                      if (type == SearchType.advertiser) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Escolha a Página na interface oficial após abrir a busca.',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: busy ? null : search,
                        icon: busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.arrow_forward_rounded),
                        label: const Text('Explorar anúncios'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SectionTitle(
                'Inspiração em um toque',
                action: IconButton(
                  tooltip: 'Editar atalhos',
                  onPressed: _editShortcuts,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: app.settings.shortcuts
                    .map(
                      (s) => ActionChip(
                        label: Text(s),
                        onPressed: () {
                          setState(() {
                            type = SearchType.keyword;
                            query.text = s;
                          });
                          search(s);
                        },
                      ),
                    )
                    .toList(),
              ),
              if (app.lastAdvertiser != null || app.initialSearch != null) ...[
                const SizedBox(height: 24),
                const SectionTitle('Continue de onde parou'),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      if (app.initialSearch != null)
                        ListTile(
                          leading: Icon(
                            Icons.manage_search_rounded,
                            color: colors.primary,
                          ),
                          title: const Text('Última pesquisa'),
                          subtitle: Text(
                            app.initialSearch!.queryParameters['q'] ??
                                'Biblioteca',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.arrow_forward_rounded),
                          onTap: () => runGuarded(
                            context,
                            () => app.openLibrary(app.initialSearch!),
                          ),
                        ),
                      if (app.lastAdvertiser != null)
                        ListTile(
                          leading: Icon(
                            Icons.storefront_rounded,
                            color: colors.primary,
                          ),
                          title: const Text('Última Página visitada'),
                          subtitle: Text(_pageLabel(app)),
                          trailing: const Icon(Icons.arrow_forward_rounded),
                          onTap: () => runGuarded(
                            context,
                            () => app.openLibrary(app.lastAdvertiser!),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SectionTitle(
                'Pesquisas recentes',
                action: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => HistoryScreen(app: app),
                    ),
                  ),
                  child: const Text('Ver todas'),
                ),
              ),
              if (app.history.isEmpty)
                const EmptyState(
                  icon: Icons.manage_search_rounded,
                  title: 'O início de uma boa descoberta',
                  message:
                      'Suas pesquisas aparecerão aqui. Tudo fica salvo neste aparelho.',
                )
              else
                ...app.history
                    .take(4)
                    .map(
                      (h) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.history_rounded),
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
                          icon: const Icon(Icons.bookmark_add_outlined),
                          onPressed: () => editBookmark(
                            context,
                            app,
                            uri: Uri.parse(h.url),
                            kind: BookmarkKind.search,
                            suggestedName: h.query,
                          ),
                        ),
                      ),
                    ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Pessoal e independente. Sem afiliação à Meta.\nOs resultados são exibidos pela Biblioteca oficial.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
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
