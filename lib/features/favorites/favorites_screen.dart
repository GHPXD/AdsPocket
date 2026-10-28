import 'dart:io';
import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../core/meta_ads_library_url_builder.dart';
import '../../core/native_bridge.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import 'bookmark_editor.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key, required this.app});
  final AppController app;
  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  BookmarkKind? kind;
  String filter = '', sort = 'recent';
  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final items = app.bookmarks
        .where(
          (b) =>
              (kind == null || b.kind == kind) &&
              '${b.name} ${b.notes} ${b.tags.join(' ')} ${b.category}'
                  .toLowerCase()
                  .contains(filter.toLowerCase()),
        )
        .toList();
    items.sort(
      (a, b) => sort == 'name'
          ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
          : sort == 'added'
          ? b.addedAt.compareTo(a.addedAt)
          : (b.lastVisitedAt ?? b.addedAt).compareTo(
              a.lastVisitedAt ?? a.addedAt,
            ),
    );
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Seu repertório',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Adicionar referência',
                  icon: const Icon(Icons.add_rounded),
                  onSelected: (v) {
                    if (v == 'offer') {
                      editBookmark(context, app, kind: BookmarkKind.offer);
                    }
                    if (v == 'image') {
                      runGuarded(context, () async {
                        final file = await NativeBridge.pickImage();
                        if (file != null && context.mounted) {
                          await editBookmark(
                            context,
                            app,
                            kind: BookmarkKind.image,
                            localFile: file,
                            suggestedName: 'Imagem importada',
                          );
                        }
                      });
                    }
                    if (v == 'link') {
                      editBookmark(context, app, kind: BookmarkKind.ad);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'link',
                      child: Text('Salvar link da Biblioteca'),
                    ),
                    PopupMenuItem(
                      value: 'offer',
                      child: Text('Salvar loja ou oferta'),
                    ),
                    PopupMenuItem(
                      value: 'image',
                      child: Text('Importar imagem'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: TextField(
              onChanged: (v) => setState(() => filter = v),
              decoration: const InputDecoration(
                hintText: 'Buscar nome, tags ou notas',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          SizedBox(
            height: 56,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('Tudo'),
                    selected: kind == null,
                    onSelected: (_) => setState(() => kind = null),
                  ),
                ),
                ...BookmarkKind.values.map(
                  (k) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(k.label),
                      selected: k == kind,
                      onSelected: (_) => setState(() => kind = k),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${items.length} ${items.length == 1 ? 'referência salva' : 'referências salvas'}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Ordenar favoritos',
                  onSelected: (v) => setState(() => sort = v),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'recent',
                      child: Text('Última visita'),
                    ),
                    PopupMenuItem(
                      value: 'added',
                      child: Text('Data de adição'),
                    ),
                    PopupMenuItem(value: 'name', child: Text('Nome')),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.sort_rounded),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const SingleChildScrollView(
                    child: EmptyState(
                      icon: Icons.bookmarks_outlined,
                      title: 'Um lugar para suas descobertas',
                      message:
                          'Salve anunciantes, pesquisas e links enquanto explora. Suas referências ficam só neste aparelho.',
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    itemCount: items.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final b = items[index];
                      return Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () => _open(b),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: .12),
                                        borderRadius: BorderRadius.circular(13),
                                      ),
                                      child: Icon(
                                        switch (b.kind) {
                                          BookmarkKind.advertiser =>
                                            Icons.storefront_rounded,
                                          BookmarkKind.search =>
                                            Icons.search_rounded,
                                          BookmarkKind.ad =>
                                            Icons.ad_units_rounded,
                                          BookmarkKind.offer =>
                                            Icons.shopping_bag_outlined,
                                          BookmarkKind.image =>
                                            Icons.image_outlined,
                                        },
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            b.name,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            '${b.kind.label} · ${countries[b.country]}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      tooltip: 'Opções da referência',
                                      onSelected: (v) async {
                                        if (v == 'edit') {
                                          await editBookmark(
                                            context,
                                            app,
                                            existing: b,
                                          );
                                        }
                                        if (v == 'copy' && context.mounted) {
                                          await copyLink(context, b.url);
                                        }
                                        if (v == 'delete' &&
                                            context.mounted &&
                                            await confirm(
                                              context,
                                              'Remover referência?',
                                              b.name,
                                              action: 'Remover',
                                            ) &&
                                            context.mounted) {
                                          await runGuarded(
                                            context,
                                            () => app.remove(b),
                                          );
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: Text(
                                            'Editar nome, tags e notas',
                                          ),
                                        ),
                                        if (b.kind != BookmarkKind.image)
                                          const PopupMenuItem(
                                            value: 'copy',
                                            child: Text('Copiar link'),
                                          ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Remover'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                if (b.notes.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    b.notes,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                if (b.tags.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: b.tags
                                        .map(
                                          (t) => Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 9,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withValues(alpha: .10),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              t,
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                Text(
                                  'Última visita: ${dateLabel(b.lastVisitedAt)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
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

  Future<void> _open(Bookmark b) => runGuarded(context, () async {
    if (b.kind == BookmarkKind.image) {
      final path = await NativeBridge.imagePath(b.localFile!);
      if (path == null) {
        throw const FormatException('Imagem não encontrada neste aparelho.');
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(b.name)),
            body: Center(
              child: InteractiveViewer(
                minScale: .5,
                maxScale: 5,
                child: Image.file(
                  File(path),
                  errorBuilder: (_, error, stack) =>
                      const Text('Não foi possível abrir a imagem.'),
                ),
              ),
            ),
          ),
        ),
      );
    }
    await widget.app.visit(b);
  });
}
