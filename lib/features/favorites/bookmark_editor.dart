import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/app_controller.dart';
import '../../core/meta_ads_library_url_builder.dart';
import '../../core/native_bridge.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';

Future<void> editBookmark(
  BuildContext context,
  AppController app, {
  Bookmark? existing,
  Uri? uri,
  BookmarkKind? kind,
  String? suggestedName,
  String? localFile,
}) async {
  final selected =
      kind ??
      existing?.kind ??
      (MetaAdsLibraryUrlBuilder.pageId(uri!) != null
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
    ),
  );
  if (result == null && localFile != null) {
    await NativeBridge.deleteImage(localFile);
  }
  if (result == null || !context.mounted) return;
  await runGuarded(context, () async {
    await app.save(result);
    await HapticFeedback.lightImpact();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Referência salva nos favoritos.')),
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
  });
  final Bookmark? existing;
  final Uri? uri;
  final BookmarkKind kind;
  final String? name, localFile;
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
  @override
  void dispose() {
    for (final c in [name, url, notes, tags, category]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.existing != null
          ? 'Editar referência'
          : widget.kind == BookmarkKind.advertiser
          ? 'Salvar anunciante'
          : 'Salvar referência',
    ),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: name,
                autofocus: true,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Nome amigável'),
                validator: (v) => v!.trim().isEmpty ? 'Informe um nome.' : null,
              ),
              const SizedBox(height: 12),
              if (widget.kind != BookmarkKind.image)
                TextFormField(
                  controller: url,
                  readOnly: widget.existing != null || widget.uri != null,
                  maxLength: 8192,
                  maxLines: 2,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(labelText: 'URL HTTPS'),
                  validator: (v) {
                    if (widget.kind == BookmarkKind.offer) {
                      return MetaAdsLibraryUrlBuilder.safeHttps(v!.trim()) ==
                              null
                          ? 'Use uma URL HTTPS válida.'
                          : null;
                    }
                    try {
                      MetaAdsLibraryUrlBuilder.validateLibrary(v!);
                      return null;
                    } on FormatException catch (e) {
                      return e.message;
                    }
                  },
                ),
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
                decoration: const InputDecoration(labelText: 'Notas pessoais'),
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
          final b =
              edited?.copyWith(
                name: name.text.trim(),
                notes: notes.text.trim(),
                tags: _tags(),
                category: category.text.trim(),
              ) ??
              Bookmark(
                id: localId(),
                name: name.text.trim(),
                kind: widget.kind,
                url: url.text.trim(),
                country:
                    widget.uri?.queryParameters['country'] != null &&
                        countries.containsKey(
                          widget.uri!.queryParameters['country'],
                        )
                    ? widget.uri!.queryParameters['country']!
                    : widget.country,
                addedAt: DateTime.now().toUtc(),
                pageId: MetaAdsLibraryUrlBuilder.pageId(
                  Uri.tryParse(url.text) ?? Uri(),
                ),
                tags: _tags(),
                notes: notes.text.trim(),
                category: category.text.trim(),
                localFile: widget.localFile,
              );
          Navigator.pop(context, b);
        },
        child: const Text('Salvar'),
      ),
    ],
  );
  List<String> _tags() => tags.text
      .split(',')
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .toSet()
      .toList();
}
