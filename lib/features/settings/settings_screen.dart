import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../app/app_controller.dart';
import '../../core/longevity.dart';
import '../../core/text_extraction.dart';
import '../../core/meta_ads_library_url_builder.dart';
import '../../core/native_bridge.dart';
import '../../core/widgets.dart';
import '../../data/backup_service.dart';
import '../../data/models.dart';
import '../../data/offer.dart';
import '../history/history_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.app});
  final AppController app;
  @override
  Widget build(BuildContext context) {
    final s = app.settings;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Ajustes',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Suas preferências. Seus dados. Seu aparelho.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              const SectionTitle('Aparência'),
              const SizedBox(height: 12),
              _select<String>(context, 'Tema', s.theme, const {
                'dark': 'Escuro',
                'light': 'Claro',
                'system': 'Seguir sistema',
              }, (v) => app.updateSettings(s.copyWith(theme: v))),
              const SizedBox(height: 24),
              const SectionTitle('Biblioteca'),
              const SizedBox(height: 12),
              _select<String>(
                context,
                'País padrão',
                s.country,
                countries,
                (v) => app.updateSettings(s.copyWith(country: v)),
              ),
              const SizedBox(height: 12),
              _select<String>(context, 'Status padrão', s.status, const {
                'active': 'Anúncios ativos',
                'all': 'Todos disponíveis',
              }, (v) => app.updateSettings(s.copyWith(status: v))),
              const SizedBox(height: 12),
              _select<ViewMode>(context, 'Modo visual', s.viewMode, {
                for (final v in ViewMode.values) v: v.label,
              }, (v) => app.updateSettings(s.copyWith(viewMode: v))),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Modo imersivo'),
                      subtitle: const Text(
                        'Biblioteca em tela cheia com controles compactos',
                      ),
                      value: s.immersive,
                      onChanged: (v) =>
                          runGuarded(context, () => app.setImmersive(v)),
                    ),
                    SwitchListTile(
                      title: const Text('Retomar a última pesquisa'),
                      subtitle: const Text(
                        'Reabrir a Biblioteca onde você parou',
                      ),
                      value: s.restoreSession,
                      onChanged: (v) => runGuarded(
                        context,
                        () => app.updateSettings(s.copyWith(restoreSession: v)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: SwitchListTile(
                  title: const Text('Usar navegador externo'),
                  subtitle: const Text(
                    'Abrir pesquisas e favoritos no navegador padrão',
                  ),
                  value: s.externalBrowser,
                  onChanged: (v) => runGuarded(
                    context,
                    () => app.updateSettings(s.copyWith(externalBrowser: v)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tamanho do texto no site: ${s.zoom}%'),
                      Slider(
                        value: s.zoom.toDouble(),
                        min: 75,
                        max: 200,
                        divisions: 5,
                        label: '${s.zoom}%',
                        onChanged: (v) => runGuarded(
                          context,
                          () => app.updateSettings(s.copyWith(zoom: v.round())),
                        ),
                      ),
                      const Text(
                        'Também é possível usar o gesto de pinça para zoom.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const SectionTitle('Assistente da Biblioteca'),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Assistente nos cards'),
                      subtitle: const Text(
                        'Dias ativos, salvar em 1 toque, filtro e auto-rolagem. Lê apenas o texto visível dos cards.',
                      ),
                      value: s.assistant,
                      onChanged: (v) => runGuarded(
                        context,
                        () => app.updateSettings(s.copyWith(assistant: v)),
                      ),
                    ),
                    ListTile(
                      title: const Text('Auto-rolar até encontrar'),
                      trailing: DropdownButton<int>(
                        value: s.scrollTarget,
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final n in const [10, 20, 30, 50, 100])
                            DropdownMenuItem(
                              value: n,
                              child: Text('$n anúncios'),
                            ),
                        ],
                        onChanged: (v) => runGuarded(
                          context,
                          () => app.updateSettings(s.copyWith(scrollTarget: v)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const SectionTitle('Filtros'),
              const SizedBox(height: 4),
              Text(
                'Também ajustáveis na barra da Biblioteca e no Explorar.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              _select<int>(
                context,
                'Ativos há pelo menos',
                s.minDays ?? -1,
                {
                  for (final d in LongevityFilter.presets)
                    d ?? -1: d == null
                        ? 'Sem filtro'
                        : 'Ativos há $d dias ou mais',
                  if (s.minDays != null &&
                      !LongevityFilter.presets.contains(s.minDays))
                    s.minDays!: '${s.minDays} dias',
                },
                (v) => app.updateSettings(
                  s.copyWith(minDays: () => v < 0 ? null : v),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Incluir registros sem data'),
                      subtitle: const Text(
                        'Mostrar referências sem data de início no filtro',
                      ),
                      value: s.includeUndated,
                      onChanged: (v) => runGuarded(
                        context,
                        () => app.updateSettings(s.copyWith(includeUndated: v)),
                      ),
                    ),
                    ListTile(
                      title: const Text('Faixa low ticket'),
                      subtitle: Text(s.priceRange.label),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _editRange(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const SectionTitle('Dados no aparelho'),
              const SizedBox(height: 12),
              _tile(
                Icons.history_rounded,
                'Histórico de pesquisas',
                'Buscar, repetir e excluir',
                () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => HistoryScreen(app: app),
                  ),
                ),
              ),
              _tile(
                Icons.bookmarks_outlined,
                'Gerenciar favoritos',
                'Anunciantes, anúncios e ofertas',
                () => app.selectTab(Tabs.saved),
              ),
              _tile(
                Icons.delete_sweep_outlined,
                'Limpar histórico',
                'Preserva os favoritos',
                () async {
                  if (await confirm(
                        context,
                        'Limpar histórico?',
                        'Esta ação remove as pesquisas recentes.',
                        action: 'Limpar',
                      ) &&
                      context.mounted) {
                    await runGuarded(context, app.clearHistory);
                  }
                },
              ),
              _tile(
                Icons.cleaning_services_outlined,
                'Limpar cache do navegador',
                'Preserva favoritos, histórico e cookies',
                () async {
                  if (await confirm(
                        context,
                        'Limpar cache?',
                        'Os arquivos temporários do WebView serão removidos. Seus dados locais serão preservados.',
                        action: 'Limpar',
                      ) &&
                      context.mounted) {
                    await runGuarded(context, () async {
                      await InAppWebViewController.clearAllCache();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Cache limpo.')),
                        );
                      }
                    });
                  }
                },
              ),
              _tile(
                Icons.file_upload_outlined,
                'Exportar backup JSON',
                'Favoritos, mineração, pesquisas e ajustes',
                () => runGuarded(context, () async {
                  final saved = await NativeBridge.exportBackup(
                    app.exportBackup(),
                  );
                  if (saved && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Backup exportado. Imagens não são incluídas.',
                        ),
                      ),
                    );
                  }
                }),
              ),
              _tile(
                Icons.table_chart_outlined,
                'Exportar Mineração (CSV)',
                'Planilha das referências catalogadas',
                () => _csv(
                  context,
                  app.exportOffersCsv(),
                  'adspocket-mineracao.csv',
                ),
              ),
              _tile(
                Icons.table_rows_outlined,
                'Exportar favoritos (CSV)',
                'Anunciantes, pesquisas e links',
                () => _csv(
                  context,
                  app.exportBookmarksCsv(),
                  'adspocket-favoritos.csv',
                ),
              ),
              _tile(
                Icons.file_download_outlined,
                'Importar backup JSON',
                'Validação antes de mesclar, sem sobrescrever',
                () => _import(context),
              ),
              const SizedBox(height: 24),
              const SectionTitle('Sobre'),
              const SizedBox(height: 12),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AdsPocket',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text('Versão $appVersion · Uso pessoal'),
                      SizedBox(height: 12),
                      Text(
                        'Aplicativo independente, sem afiliação à Meta. O conteúdo dos anúncios pertence aos seus respectivos titulares. Sem conta própria, assinatura ou analytics.',
                      ),
                    ],
                  ),
                ),
              ),
              _tile(
                Icons.privacy_tip_outlined,
                'Privacidade local',
                'Como os dados são armazenados',
                () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Privacidade'),
                    content: const SingleChildScrollView(
                      child: Text(
                        'Pesquisas, favoritos, notas e imagens importadas ficam na área privada do aplicativo. Não há backend, anúncios ou analytics.\n\nAo visitar a Biblioteca, seu aparelho se conecta à Meta, sujeita às políticas dela. O WebView mantém os cookies normais da navegação; o AdsPocket não lê nem exporta cookies, senhas ou tokens. Login pode exigir o navegador externo.\n\nBackups JSON são arquivos legíveis com suas referências e notas. Imagens e dados do WebView não são incluídos. A importação mescla registros novos e preserva os existentes. O backup automático Android está desabilitado.\n\nPara excluir todos os dados, use Limpar armazenamento nas configurações Android ou desinstale o aplicativo.',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Entendi'),
                      ),
                    ],
                  ),
                ),
              ),
              _tile(
                Icons.description_outlined,
                'Licenças open source',
                'Dependências do aplicativo',
                () => showLicensePage(
                  context: context,
                  applicationName: 'AdsPocket',
                  applicationVersion: appVersion,
                ),
              ),
              _tile(
                Icons.open_in_new_rounded,
                'Biblioteca oficial da Meta',
                'facebook.com/ads/library',
                () => runGuarded(
                  context,
                  () => app.openExternal(MetaAdsLibraryUrlBuilder.home),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback action,
  ) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: action,
  );
  Widget _select<T>(
    BuildContext context,
    String title,
    T value,
    Map<T, String> values,
    Future<void> Function(T) onChanged,
  ) => DropdownButtonFormField<T>(
    key: ValueKey('$title:$value'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: title),
    items: values.entries
        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
        .toList(),
    onChanged: (v) {
      if (v != null) runGuarded(context, () => onChanged(v));
    },
  );
  Future<void> _csv(BuildContext context, String text, String name) =>
      runGuarded(context, () async {
        final saved = await NativeBridge.exportFile(text, name, 'text/csv');
        if (saved && context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('CSV exportado.')));
        }
      });

  Future<void> _editRange(BuildContext context) async {
    final r = app.settings.priceRange;
    String plain(int c) =>
        '${c ~/ 100},${(c % 100).toString().padLeft(2, '0')}';
    final min = TextEditingController(text: plain(r.minCents));
    final max = TextEditingController(text: plain(r.maxCents));
    var currency = r.currency;
    final result = await showDialog<PriceRange>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Faixa low ticket'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: min,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Mínimo'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: max,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Máximo'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: currency,
                decoration: const InputDecoration(labelText: 'Moeda'),
                items: [
                  for (final c in currencies.keys)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: (v) => setState(() => currency = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, PriceRange.lowTicket),
              child: const Text('Padrão'),
            ),
            FilledButton(
              onPressed: () {
                final a = parseMoneyToCents(min.text);
                final b = parseMoneyToCents(max.text);
                final range = a == null || b == null
                    ? null
                    : PriceRange(a, b, currency);
                if (range == null || !range.valid) return;
                Navigator.pop(context, range);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    min.dispose();
    max.dispose();
    if (result == null || !context.mounted) return;
    await runGuarded(
      context,
      () => app.updateSettings(app.settings.copyWith(priceRange: result)),
    );
  }

  Future<void> _import(BuildContext context) => runGuarded(context, () async {
    final text = await NativeBridge.importBackup();
    if (text == null) return;
    final backup = BackupService.decode(text);
    if (!context.mounted) return;
    final restore = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importar backup?'),
        content: Text(
          '${backup.bookmarks.length} favoritos, ${backup.offers.length} referências da Mineração e ${backup.history.length} pesquisas e ${backup.research.length} registros 360° serão mesclados. Registros existentes serão preservados.\n\nDeseja também restaurar as configurações?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Só referências'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Incluir configurações'),
          ),
        ],
      ),
    );
    if (restore == null) return;
    final count = await app.importBackup(backup, restoreSettings: restore);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$count novos registros importados. Duplicatas preservadas.',
          ),
        ),
      );
    }
  });
}
