import 'dart:io';
import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../core/meta_ads_library_url_builder.dart';
import '../../core/native_bridge.dart';
import '../../core/widgets.dart';
import '../../core/pocket_grid.dart';
import '../../data/models.dart';
import '../../data/offer.dart';
import '../mining/offer_widgets.dart';
import 'advertiser_screen.dart';
import 'bookmark_editor.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key, required this.app, required this.kinds});
  final AppController app;

  /// Kinds shown in this section of Salvos.
  final Set<BookmarkKind> kinds;
  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  BookmarkKind? kind;
  bool watchlist = false;
  String filter = '', sort = 'recent';

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final colors = Theme.of(context).colorScheme;
    final items = app.bookmarks
        .where(
          (b) =>
              widget.kinds.contains(b.kind) &&
              (kind == null || b.kind == kind) &&
              (!watchlist || b.watchlist) &&
              '${b.name} ${b.notes} ${b.tags.join(' ')} ${b.category} ${b.niche} ${b.pageId ?? ''}'
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
    final review = app.bookmarks.where((b) => b.needsReview).length;
    final kinds = widget.kinds.length < 2
        ? const <BookmarkKind>[]
        : BookmarkKind.values
              .where(
                (k) =>
                    widget.kinds.contains(k) &&
                    (k != BookmarkKind.unidentified ||
                        app.bookmarks.any((b) => b.kind == k)),
              )
              .toList();
    final forAdvertisers = widget.kinds.contains(BookmarkKind.advertiser);
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
            child: TextField(
              onChanged: (v) => setState(() => filter = v),
              decoration: const InputDecoration(
                hintText: 'Buscar nome, Page ID, tags ou notas',
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
                if (kinds.isNotEmpty || forAdvertisers)
                  _chip('Tudo', kind == null && !watchlist, () {
                    kind = null;
                    watchlist = false;
                  }),
                if (forAdvertisers)
                  _chip('Observação', watchlist, () => watchlist = !watchlist),
                for (final k in kinds)
                  _chip(k.label, k == kind, () => kind = k == kind ? null : k),
              ],
            ),
          ),
          if (review > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
              child: Text(
                '$review ${review == 1 ? 'favorito antigo precisa' : 'favoritos antigos precisam'} de revisão: salvos como anunciante sem Page ID.',
                style: TextStyle(fontSize: 13, color: colors.tertiary),
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
                      fontSize: 13,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Ordenar favoritos',
                  initialValue: sort,
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
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                    child: PocketGrid(
                      minWidth: 220,
                      children: [for (final item in items) _card(item, colors)],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool on, VoidCallback toggle) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: FilterChip(
      label: Text(label),
      selected: on,
      showCheckmark: false,
      onSelected: (_) => setState(toggle),
    ),
  );

  Widget _card(Bookmark b, ColorScheme colors) {
    final app = widget.app;
    final local = app.offersForPage(b.pageId);
    final interesting = local
        .where((o) => o.analysis == Analysis.interesting)
        .length;
    final muted = TextStyle(fontSize: 12, color: colors.onSurfaceVariant);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _open(b),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 6, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(switch (b.kind) {
                    BookmarkKind.advertiser => Icons.storefront_rounded,
                    BookmarkKind.search => Icons.search_rounded,
                    BookmarkKind.ad => Icons.ad_units_rounded,
                    BookmarkKind.offer => Icons.shopping_bag_outlined,
                    BookmarkKind.image => Icons.image_outlined,
                    BookmarkKind.unidentified => Icons.help_outline_rounded,
                  }, color: colors.primary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          b.kind == BookmarkKind.advertiser
                              ? 'Page ID ${b.pageId}${b.metaAdCount == null ? '' : ' · ${b.metaAdCount} anúncios na Meta em ${dateLabel(b.metaAdCountAt)}'}'
                              : '${b.kind.label} · ${countries[b.country]}',
                          style: muted,
                        ),
                      ],
                    ),
                  ),
                  if (b.watchlist)
                    Icon(
                      Icons.visibility_rounded,
                      size: 18,
                      color: colors.primary,
                      semanticLabel: 'Em observação',
                    ),
                  _menu(b),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (b.needsReview)
                    Pill(
                      'Revisar',
                      icon: Icons.flag_outlined,
                      color: colors.tertiary,
                    ),
                  if (b.niche.isNotEmpty) Pill(b.niche),
                  if (b.kind == BookmarkKind.advertiser)
                    Pill(
                      '${local.length} salvos no AdsPocket${interesting > 0 ? ' · $interesting interessantes' : ''}',
                    ),
                  for (final t in b.tags.take(2)) Pill(t),
                ],
              ),
              if (b.notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(b.notes, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 8),
              Text(
                'Última visita: ${dateLabel(b.lastVisitedAt)}',
                style: muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menu(Bookmark b) {
    final app = widget.app;
    final identifiable =
        b.kind == BookmarkKind.unidentified ||
        (b.kind == BookmarkKind.search && b.pageId == null);
    return PopupMenuButton<String>(
      tooltip: 'Opções da referência',
      onSelected: (v) async {
        switch (v) {
          case 'edit':
            await editBookmark(context, app, existing: b);
          case 'copy':
            await copyLink(context, b.url);
          case 'watch':
            await runGuarded(
              context,
              () => app.save(b.copyWith(watchlist: !b.watchlist)),
            );
          case 'identify':
            await _identify(b);
          case 'delete':
            if (await confirm(
                  context,
                  'Remover referência?',
                  b.name,
                  action: 'Remover',
                ) &&
                mounted) {
              await runGuarded(context, () => app.remove(b));
            }
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: Text('Editar')),
        if (b.kind != BookmarkKind.image)
          const PopupMenuItem(value: 'copy', child: Text('Copiar link')),
        if (b.kind == BookmarkKind.advertiser)
          PopupMenuItem(
            value: 'watch',
            child: Text(
              b.watchlist ? 'Tirar da observação' : 'Adicionar à observação',
            ),
          ),
        if (identifiable)
          const PopupMenuItem(
            value: 'identify',
            child: Text('Informar Page ID'),
          ),
        const PopupMenuItem(value: 'delete', child: Text('Remover')),
      ],
    );
  }

  /// Manual correction for unidentified and legacy records.
  Future<void> _identify(Bookmark b) => runGuarded(context, () async {
    final url = await askPageIdUrl(
      context,
      widget.app,
      from: Uri.tryParse(b.url),
    );
    if (url == null) return;
    final ok = await widget.app.save(b.identifyAs(url));
    widget.app.showNotice(
      ok
          ? 'Referência identificada como anunciante.'
          : 'Já existe um anunciante salvo com este Page ID.',
    );
  });

  Future<void> _open(Bookmark b) => runGuarded(context, () async {
    if (b.kind == BookmarkKind.advertiser) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => AdvertiserScreen(app: widget.app, id: b.id),
        ),
      );
      return;
    }
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
    if (b.kind != BookmarkKind.offer &&
        b.kind != BookmarkKind.image &&
        !MetaAdsLibraryUrlBuilder.isLibrary(Uri.parse(b.url))) {
      throw const FormatException('Link inválido.');
    }
    await widget.app.visit(b);
  });
}
