import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../app/app_controller.dart';
import '../../core/meta_ads_library_url_builder.dart';
import '../../core/native_bridge.dart';
import '../../core/widgets.dart';
import '../../data/backup_service.dart';
import '../../data/models.dart';
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
                'Do seu jeito',
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
                () => app.selectTab(2),
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
                'Favoritos, pesquisas e configurações',
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
                      Text('Versão 1.0.0 · Uso pessoal'),
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
                  applicationVersion: '1.0.0',
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
          '${backup.bookmarks.length} favoritos e ${backup.history.length} pesquisas serão mesclados. Registros existentes serão preservados.\n\nDeseja também restaurar as configurações?',
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
            '$count novos favoritos importados. Duplicatas preservadas.',
          ),
        ),
      );
    }
  });
}
