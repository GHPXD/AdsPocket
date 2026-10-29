import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/app_controller.dart';
import '../../core/meta_ads_library_url_builder.dart';
import '../../core/native_bridge.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';

/// Entry point of the "Salvar" action in the Library. Only a URL with a valid
/// `view_all_page_id` becomes an identified advertiser.
Future<void> saveCurrentReference(
  BuildContext context,
  AppController app,
  Uri uri,
) async {
  final pageId = MetaAdsLibraryUrlBuilder.pageId(uri);
  if (pageId != null) {
    final existing = app.savedAdvertiser(pageId);
    await editBookmark(
      context,
      app,
      existing: existing,
      uri: existing == null ? uri : null,
      kind: BookmarkKind.advertiser,
      warning: app.unverifiedPageIds.contains(pageId)
          ? 'Este ID veio de um link de perfil e pode não ser o Page ID da Biblioteca. Salve apenas se a Biblioteca exibiu anúncios deste anunciante.'
          : null,
    );
    return;
  }
  final choice = await showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Não foi possível identificar uma Página nesta URL.'),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(
            'Nenhum anunciante será presumido a partir da pesquisa.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final (value, icon, label) in [
          ('search', Icons.search_rounded, 'Salvar como pesquisa'),
          (
            'unidentified',
            Icons.help_outline_rounded,
            'Salvar como referência não identificada',
          ),
          ('manual', Icons.pin_outlined, 'Informar Page ID manualmente'),
          ('cancel', Icons.close_rounded, 'Cancelar'),
        ])
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, value),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 16),
                Expanded(child: Text(label)),
              ],
            ),
          ),
      ],
    ),
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'search':
      await editBookmark(
        context,
        app,
        uri: uri,
        kind: BookmarkKind.search,
        suggestedName: uri.queryParameters['q'],
      );
    case 'unidentified':
      await editBookmark(
        context,
        app,
        uri: uri,
        kind: BookmarkKind.unidentified,
        suggestedName: uri.queryParameters['q'],
      );
    case 'manual':
      final page = await askPageIdUrl(context, app, from: uri);
      if (page != null && context.mounted) {
        await editBookmark(
          context,
          app,
          uri: page,
          kind: BookmarkKind.advertiser,
          sourceUrl: uri.toString(),
        );
      }
  }
}

/// Asks for a numeric Page ID, builds the Library URL and asks for explicit
/// confirmation. The ID is never assumed to belong to the searched name.
Future<Uri?> askPageIdUrl(
  BuildContext context,
  AppController app, {
  Uri? from,
}) async {
  final form = GlobalKey<FormState>();
  final input = TextEditingController();
  final id = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Informar Page ID'),
      content: Form(
        key: form,
        child: TextFormField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 40,
          decoration: const InputDecoration(
            labelText: 'Page ID numérico',
            helperText: 'Disponível na URL da Página na Biblioteca.',
          ),
          validator: (v) => RegExp(r'^\d{1,40}$').hasMatch(v?.trim() ?? '')
              ? null
              : 'Use apenas números.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(context, input.text.trim());
            }
          },
          child: const Text('Continuar'),
        ),
      ],
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 300));
  input.dispose();
  if (id == null || !context.mounted) return null;
  final country = from?.queryParameters['country'];
  final status = from?.queryParameters['active_status'];
  final url = MetaAdsLibraryUrlBuilder().build(
    text: id,
    type: SearchType.pageId,
    country: countries.containsKey(country) ? country! : app.settings.country,
    status: {'active', 'all'}.contains(status) ? status! : app.settings.status,
  );
  final ok = await confirm(
    context,
    'Usar o Page ID $id?',
    'O AdsPocket não verifica a quem este ID pertence. Confirme na Biblioteca antes de associá-lo a um anunciante.\n\n$url',
    action: 'Confirmar',
  );
  return ok ? url : null;
}

Future<void> editBookmark(
  BuildContext context,
  AppController app, {
  Bookmark? existing,
  Uri? uri,
  BookmarkKind? kind,
  String? suggestedName,
  String? localFile,
  String? sourceUrl,
  String? warning,
}) async {
  final selected =
      kind ??
      existing?.kind ??
      (uri != null && MetaAdsLibraryUrlBuilder.pageId(uri) != null
          ? BookmarkKind.advertiser
          : BookmarkKind.ad);
  final saved =
      existing ??
      (uri == null
          ? null
          : app.bookmarks
                .where(
                  (b) =>
                      b.kind == selected &&
                      b.kind != BookmarkKind.image &&
                      MetaAdsLibraryUrlBuilder.canonical(Uri.parse(b.url)) ==
                          MetaAdsLibraryUrlBuilder.canonical(uri),
                )
                .firstOrNull);
  final result = await showDialog<Bookmark>(
    context: context,
    builder: (_) => _BookmarkDialog(
      existing: saved,
      uri: uri,
      kind: selected,
      name: suggestedName,
      country: app.settings.country,
      localFile: localFile,
      sourceUrl: sourceUrl,
      warning: warning,
    ),
  );
  if (result == null && localFile != null) {
    await NativeBridge.deleteImage(localFile);
  }
  if (result == null || !context.mounted) return;
  await runGuarded(context, () async {
    final ok = await app.save(result);
    await HapticFeedback.lightImpact();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !ok
                ? 'Esta referência já está nos favoritos.'
                : result.kind == BookmarkKind.advertiser
                ? 'Anunciante identificado salvo.'
                : 'Referência salva nos favoritos.',
          ),
        ),
      );
    }
  });
}

class _BookmarkDialog extends StatefulWidget {
  const _BookmarkDialog({
    this.existing,
    this.uri,
    required this.kind,
    this.name,
    required this.country,
    this.localFile,
    this.sourceUrl,
    this.warning,
  });
  final Bookmark? existing;
  final Uri? uri;
  final BookmarkKind kind;
  final String? name, localFile, sourceUrl, warning;
  final String country;
  @override
  State<_BookmarkDialog> createState() => _BookmarkDialogState();
}

class _BookmarkDialogState extends State<_BookmarkDialog> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(
    text: widget.existing?.name ?? widget.name ?? '',
  );
  late final url = TextEditingController(
    text: widget.existing?.url ?? widget.uri?.toString() ?? '',
  );
  late final notes = TextEditingController(text: widget.existing?.notes ?? '');
  late final tags = TextEditingController(
    text: widget.existing?.tags.join(', ') ?? '',
  );
  late final category = TextEditingController(
    text: widget.existing?.category ?? '',
  );
  late final niche = TextEditingController(text: widget.existing?.niche ?? '');
  bool get advertiser => widget.kind == BookmarkKind.advertiser;

  @override
  void dispose() {
    for (final c in [name, url, notes, tags, category, niche]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pageId = MetaAdsLibraryUrlBuilder.pageId(
      Uri.tryParse(url.text) ?? Uri(),
    );
    return AlertDialog(
      title: Text(
        widget.existing != null
            ? 'Editar referência'
            : advertiser
            ? 'Salvar anunciante'
            : widget.kind == BookmarkKind.unidentified
            ? 'Referência não identificada'
            : widget.kind == BookmarkKind.search
            ? 'Salvar pesquisa'
            : 'Salvar referência',
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.warning != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      widget.warning!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (advertiser && pageId != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Anunciante identificado · Page ID $pageId',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                TextFormField(
                  controller: name,
                  autofocus: true,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: 'Nome amigável'),
                  validator: (v) =>
                      v!.trim().isEmpty ? 'Informe um nome.' : null,
                ),
                const SizedBox(height: 12),
                if (widget.kind != BookmarkKind.image)
                  TextFormField(
                    controller: url,
                    readOnly: widget.existing != null || widget.uri != null,
                    maxLength: 8192,
                    maxLines: 2,
                    keyboardType: TextInputType.url,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'URL HTTPS'),
                    validator: (v) {
                      if (widget.kind == BookmarkKind.offer) {
                        return MetaAdsLibraryUrlBuilder.safeHttps(v!.trim()) ==
                                null
                            ? 'Use uma URL HTTPS válida.'
                            : null;
                      }
                      try {
                        final uri = MetaAdsLibraryUrlBuilder.validateLibrary(
                          v!,
                        );
                        if (advertiser &&
                            MetaAdsLibraryUrlBuilder.pageId(uri) == null) {
                          return 'Não foi possível identificar uma Página nesta URL.';
                        }
                        return null;
                      } on FormatException catch (e) {
                        return e.message;
                      }
                    },
                  ),
                if (advertiser) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: niche,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: 'Nicho'),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: tags,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Tags separadas por vírgula',
                  ),
                  validator: (v) =>
                      v!.split(',').length > 30 ||
                          v.split(',').any((t) => t.trim().length > 80)
                      ? 'Máximo 30 tags de até 80 caracteres.'
                      : null,
                ),
                if (widget.kind == BookmarkKind.offer) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: category,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: 'Categoria'),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: notes,
                  maxLength: 10000,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Notas pessoais',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (!form.currentState!.validate()) return;
            final edited = widget.existing;
            final link = Uri.tryParse(url.text.trim()) ?? Uri();
            final b =
                edited?.copyWith(
                  name: name.text.trim(),
                  notes: notes.text.trim(),
                  tags: _tags(),
                  category: category.text.trim(),
                  niche: niche.text.trim(),
                ) ??
                Bookmark(
                  id: localId(),
                  name: name.text.trim(),
                  kind: widget.kind,
                  url: url.text.trim(),
                  country:
                      countries.containsKey(link.queryParameters['country'])
                      ? link.queryParameters['country']!
                      : widget.country,
                  addedAt: DateTime.now().toUtc(),
                  pageId: MetaAdsLibraryUrlBuilder.pageId(link),
                  lastVisitedAt: advertiser ? DateTime.now().toUtc() : null,
                  tags: _tags(),
                  notes: notes.text.trim(),
                  category: category.text.trim(),
                  niche: niche.text.trim(),
                  localFile: widget.localFile,
                  sourceUrl: widget.sourceUrl,
                );
            Navigator.pop(context, b);
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }

  List<String> _tags() => tags.text
      .split(',')
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .toSet()
      .toList();
}
