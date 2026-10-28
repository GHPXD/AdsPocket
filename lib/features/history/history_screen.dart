import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../core/meta_ads_library_url_builder.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../favorites/bookmark_editor.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.app});
  final AppController app;
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String filter = '';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.app,
    builder: (context, _) {
      final app = widget.app;
      final items = app.history
          .where((h) => h.query.toLowerCase().contains(filter.toLowerCase()))
          .toList();
      return Scaffold(
        appBar: AppBar(
          title: const Text('Histórico'),
          actions: [
            IconButton(
              tooltip: 'Limpar histórico',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                if (await confirm(
                      context,
                      'Limpar histórico?',
                      'Seus favoritos serão preservados.',
                      action: 'Limpar',
                    ) &&
                    context.mounted) {
                  await runGuarded(context, app.clearHistory);
                }
              },
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                onChanged: (v) => setState(() => filter = v),
                decoration: const InputDecoration(
                  hintText: 'Buscar no histórico',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? const SingleChildScrollView(
                      child: EmptyState(
                        icon: Icons.history_rounded,
                        title: 'Nenhuma pesquisa encontrada',
                        message:
                            'As pesquisas feitas no Explorar são salvas automaticamente.',
                      ),
                    )
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final h = items[index];
                        return ListTile(
                          leading: const Icon(Icons.history),
                          title: Text(
                            h.query,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${h.type.label} · ${countries[h.country]}\n${dateLabel(h.visitedAt)} · ${h.status == 'active' ? 'Ativos' : 'Todos disponíveis'}',
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            runGuarded(context, () => app.repeat(h));
                          },
                          trailing: PopupMenuButton<String>(
                            tooltip: 'Opções da pesquisa',
                            onSelected: (v) {
                              if (v == 'delete') {
                                runGuarded(context, () => app.deleteHistory(h));
                              }
                              if (v == 'save') {
                                editBookmark(
                                  context,
                                  app,
                                  uri: Uri.parse(h.url),
                                  kind: BookmarkKind.search,
                                  suggestedName: h.query,
                                );
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'save',
                                child: Text('Salvar pesquisa'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Excluir'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}
