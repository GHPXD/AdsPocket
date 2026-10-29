import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/app_controller.dart';
import '../../core/longevity.dart';
import '../../core/meta_ads_library_url_builder.dart';
import '../../core/native_bridge.dart';
import '../../core/text_extraction.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../../data/offer.dart';
import 'ocr_screen.dart';

/// Values confirmed on the OCR screen, applied to a new or existing offer.
class OfferDraft {
  const OfferDraft({
    this.imageFile,
    this.ocrText = '',
    this.startDate,
    this.price,
    this.capturedAt,
  });
  final String? imageFile;
  final String ocrText;
  final CivilDate? startDate;
  final PriceCandidate? price;
  final DateTime? capturedAt;
}

Future<Offer?> openOfferEditor(
  BuildContext context,
  AppController app, {
  Offer? existing,
  Uri? fromUrl,
  OfferDraft? draft,
  String? advertiser,
  String? pageId,
}) async {
  final saved = await Navigator.push<Offer>(
    context,
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => OfferEditorScreen(
        app: app,
        existing: existing,
        fromUrl: fromUrl,
        draft: draft,
        advertiser: advertiser,
        pageId: pageId,
      ),
    ),
  );
  if (saved == null && draft?.imageFile != null) {
    await discardUnusedImage(app, draft!.imageFile!);
  }
  return saved;
}

class OfferEditorScreen extends StatefulWidget {
  const OfferEditorScreen({
    super.key,
    required this.app,
    this.existing,
    this.fromUrl,
    this.draft,
    this.advertiser,
    this.pageId,
  });
  final AppController app;
  final Offer? existing;
  final Uri? fromUrl;
  final OfferDraft? draft;
  final String? advertiser, pageId;
  @override
  State<OfferEditorScreen> createState() => _OfferEditorScreenState();
}

class _OfferEditorScreenState extends State<OfferEditorScreen> {
  final form = GlobalKey<FormState>();
  late final Offer? e = widget.existing;
  late final name = TextEditingController(text: e?.name);
  late final advertiser = TextEditingController();
  late final pageId = TextEditingController();
  late final adId = TextEditingController();
  late final url = TextEditingController();
  late final salesUrl = TextEditingController(text: e?.salesUrl);
  late final niche = TextEditingController(text: e?.niche);
  late final category = TextEditingController(text: e?.category);
  late final price = TextEditingController();
  late final hook = TextEditingController(text: e?.hook);
  late final headline = TextEditingController(text: e?.headline);
  late final cta = TextEditingController(text: e?.cta);
  late final angle = TextEditingController(text: e?.angle);
  late final variations = TextEditingController(
    text: e?.variations?.toString(),
  );
  late final tags = TextEditingController(text: e?.tags.join(', '));
  late final notes = TextEditingController(text: e?.notes);
  late String currency = e?.currency ?? widget.app.settings.priceRange.currency;
  late PriceSource priceSource = e?.priceSource ?? PriceSource.unknown;
  late CivilDate? startDate = e?.startDate;
  late DateSource? dateSource = e?.dateSource;
  late AdStatus status = e?.status ?? AdStatus.unknown;
  late MediaType media = e?.mediaType ?? MediaType.unknown;
  late Analysis analysis = e?.analysis ?? Analysis.notAnalyzed;
  late int? clarity = e?.clarity;
  late int? salesQuality = e?.salesPageQuality;
  late int? rating = e?.manualRating;
  late String? imageFile = e?.imageFile;
  late String ocrText = e?.ocrText ?? '';
  late DateTime? capturedAt = e?.capturedAt;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    advertiser.text = e?.advertiser ?? widget.advertiser ?? '';
    pageId.text = e?.pageId ?? widget.pageId ?? '';
    adId.text = e?.adId ?? '';
    url.text = e?.url ?? '';
    if (e?.priceCents != null) {
      price.text = _plain(e!.priceCents!);
    }
    final from = widget.fromUrl;
    if (e == null && from != null && MetaAdsLibraryUrlBuilder.isLibrary(from)) {
      final page = MetaAdsLibraryUrlBuilder.pageId(from);
      if (page != null) {
        pageId.text = page;
        advertiser.text = widget.app.savedAdvertiser(page)?.name ?? '';
      }
      final ad = from.queryParameters['id'];
      if (ad != null && RegExp(r'^\d{1,40}$').hasMatch(ad)) {
        adId.text = ad;
        url.text = from.toString();
      }
    }
    final d = widget.draft;
    if (d != null) _applyDraft(d);
  }

  void _applyDraft(OfferDraft d) {
    imageFile = d.imageFile ?? imageFile;
    ocrText = d.ocrText.isEmpty ? ocrText : d.ocrText;
    capturedAt = d.capturedAt ?? capturedAt;
    if (d.startDate != null) {
      startDate = d.startDate;
      dateSource = DateSource.ocr;
    }
    if (d.price != null) {
      price.text = _plain(d.price!.cents);
      currency = d.price!.currency;
      priceSource = PriceSource.ocr;
    }
  }

  static String _plain(int cents) =>
      '${cents ~/ 100},${(cents % 100).toString().padLeft(2, '0')}';

  @override
  void dispose() {
    for (final c in [
      name,
      advertiser,
      pageId,
      adId,
      url,
      salesUrl,
      niche,
      category,
      price,
      hook,
      headline,
      cta,
      angle,
      variations,
      tags,
      notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opt(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (!form.currentState!.validate()) return;
    final cents = price.text.trim().isEmpty
        ? null
        : parseMoneyToCents(price.text);
    final now = DateTime.now().toUtc();
    final previous = e;
    var checks = previous?.checks ?? const <StatusCheck>[];
    // Changing the status records a dated verification.
    if (status != (previous?.status ?? AdStatus.unknown)) {
      checks = [...checks, StatusCheck(status, now)];
      if (checks.length > 50) checks = checks.sublist(checks.length - 50);
    }
    final offer = Offer(
      id: previous?.id ?? localId(),
      name: name.text.trim(),
      createdAt: previous?.createdAt ?? now,
      updatedAt: now,
      advertiser: advertiser.text.trim(),
      pageId: _opt(pageId),
      adId: _opt(adId),
      url: _opt(url),
      niche: niche.text.trim(),
      category: category.text.trim(),
      priceCents: cents,
      currency: currency,
      priceSource: cents == null
          ? PriceSource.unknown
          : priceSource == PriceSource.unknown
          ? PriceSource.informed
          : priceSource,
      startDate: startDate,
      dateSource: startDate == null ? null : dateSource ?? DateSource.manual,
      status: status,
      checks: checks,
      mediaType: media,
      salesUrl: _opt(salesUrl),
      tags: tags.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toSet()
          .toList(),
      notes: notes.text.trim(),
      imageFile: imageFile,
      ocrText: ocrText,
      capturedAt: capturedAt,
      hook: hook.text.trim(),
      headline: headline.text.trim(),
      cta: cta.text.trim(),
      angle: angle.text.trim(),
      variations: int.tryParse(variations.text.trim()),
      clarity: clarity,
      salesPageQuality: salesQuality,
      manualRating: rating,
      analysis: analysis,
    );
    setState(() => busy = true);
    await runGuarded(context, () async {
      await widget.app.saveOffer(offer);
      final old = previous?.imageFile;
      if (old != null && old != offer.imageFile) {
        await discardUnusedImage(widget.app, old);
      }
      await HapticFeedback.lightImpact();
      if (mounted) Navigator.pop(context, offer);
    });
    if (mounted) setState(() => busy = false);
  }

  Future<void> _pickDate() async {
    final today = CivilDate.today();
    final picked = await showDatePicker(
      context: context,
      initialDate: (startDate ?? today).toLocalDateTime(),
      firstDate: DateTime(2018),
      lastDate: today.toLocalDateTime(),
      helpText: 'Data de início do anúncio',
    );
    if (picked != null) {
      setState(() {
        startDate = CivilDate.fromDateTime(picked);
        dateSource = DateSource.manual;
      });
    }
  }

  Future<void> _attachImage() async {
    await runGuarded(context, () async {
      final file = await NativeBridge.pickImage();
      if (file == null || !mounted) return;
      final path = await NativeBridge.imagePath(file);
      if (path == null || !mounted) return;
      final result = await Navigator.push<OcrResult>(
        context,
        MaterialPageRoute(
          builder: (_) => OcrScreen(app: widget.app, path: path),
        ),
      );
      if (!mounted) return;
      if (result == null) {
        await discardUnusedImage(widget.app, file);
        return;
      }
      setState(
        () => _applyDraft(
          OfferDraft(
            imageFile: file,
            ocrText: result.text,
            startDate: result.date,
            price: result.price,
            capturedAt: DateTime.now().toUtc(),
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final today = CivilDate.today();
    String? digits(String? v, String label) =>
        v == null ||
            v.trim().isEmpty ||
            RegExp(r'^\d{1,40}$').hasMatch(v.trim())
        ? null
        : '$label deve conter apenas números.';
    Widget field(
      TextEditingController c,
      String label, {
      int max = 500,
      int lines = 1,
      TextInputType? keyboard,
      String? Function(String?)? validator,
      String? helper,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        maxLength: max,
        minLines: lines,
        maxLines: lines == 1 ? 1 : lines + 2,
        keyboardType: keyboard,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          counterText: '',
          helperText: helper,
        ),
      ),
    );
    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
      child: Text(
        title,
        style: TextStyle(
          color: colors.primary,
          fontWeight: FontWeight.w700,
          fontSize: 13,
          letterSpacing: .4,
        ),
      ),
    );
    Widget dropdown<T>(
      String label,
      T value,
      Map<T, String> items,
      ValueChanged<T> onChanged,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<T>(
        key: ValueKey('$label:$value'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final e in items.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) => setState(() => onChanged(v as T)),
      ),
    );
    final ratingItems = <int?, String>{
      null: 'Não avaliado',
      for (var i = 0; i <= 5; i++) i: '$i de 5',
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(e == null ? 'Catalogar referência' : 'Editar referência'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: busy ? null : _save,
              child: const Text('Salvar'),
            ),
          ),
        ],
      ),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            field(
              name,
              'Nome da oferta',
              max: 200,
              validator: (v) =>
                  v!.trim().isEmpty ? 'Informe o nome da oferta.' : null,
            ),
            field(notes, 'Comentário', max: 10000, lines: 2),
            field(tags, 'Tags separadas por vírgula'),
            dropdown<Analysis>('Situação', analysis, {
              for (final a in Analysis.values) a: a.label,
            }, (v) => analysis = v),
            // Saved from a Library card, these come filled in already.
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              initiallyExpanded:
                  e == null &&
                  widget.draft == null &&
                  widget.fromUrl == null &&
                  widget.pageId == null,
              title: const Text('Mais detalhes'),
              subtitle: Text(
                'Data, status, preço, links, criativo e score',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
              ),
              expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                field(advertiser, 'Anunciante'),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: field(
                        pageId,
                        'Page ID',
                        max: 40,
                        keyboard: TextInputType.number,
                        validator: (v) => digits(v, 'Page ID'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: field(
                        adId,
                        'ID do anúncio',
                        max: 40,
                        keyboard: TextInputType.number,
                        validator: (v) => digits(v, 'ID do anúncio'),
                      ),
                    ),
                  ],
                ),
                field(
                  url,
                  'Link do anúncio na Biblioteca',
                  max: 8192,
                  keyboard: TextInputType.url,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    try {
                      MetaAdsLibraryUrlBuilder.validateLibrary(v);
                      return null;
                    } on FormatException catch (e) {
                      return e.message;
                    }
                  },
                ),
                field(
                  salesUrl,
                  'Página de vendas ou checkout',
                  max: 8192,
                  keyboard: TextInputType.url,
                  validator: (v) =>
                      v == null ||
                          v.trim().isEmpty ||
                          MetaAdsLibraryUrlBuilder.safeHttps(v.trim()) != null
                      ? null
                      : 'Use uma URL HTTPS.',
                ),
                section('LONGEVIDADE'),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text(
                    startDate == null
                        ? 'Data de início não informada'
                        : '${startDate!.label} · ${ageLabel(ageInDays(startDate, today))}',
                  ),
                  subtitle: Text(
                    startDate == null
                        ? 'Use a data exibida pela Biblioteca ou um print.'
                        : (dateSource ?? DateSource.manual).label,
                  ),
                  onTap: _pickDate,
                  trailing: startDate == null
                      ? null
                      : IconButton(
                          tooltip: 'Remover data',
                          onPressed: () => setState(() {
                            startDate = null;
                            dateSource = null;
                          }),
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
                dropdown<AdStatus>('Status', status, {
                  for (final s in AdStatus.values) s: s.label,
                }, (v) => status = v),
                if (e?.lastCheckedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Última verificação: ${dateLabel(e!.lastCheckedAt)}. Alterar o status registra uma nova verificação.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                section('CLASSIFICAÇÃO'),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: field(niche, 'Nicho', max: 200)),
                    const SizedBox(width: 12),
                    Expanded(child: field(category, 'Categoria', max: 200)),
                  ],
                ),
                dropdown<MediaType>('Tipo de mídia', media, {
                  for (final m in MediaType.values) m: m.label,
                }, (v) => media = v),
                section('PREÇO'),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: field(
                        price,
                        'Valor',
                        max: 15,
                        keyboard: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (v) =>
                            v == null ||
                                v.trim().isEmpty ||
                                parseMoneyToCents(v) != null
                            ? null
                            : 'Valor inválido.',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: dropdown<String>('Moeda', currency, {
                        for (final c in currencies.keys) c: c,
                      }, (v) => currency = v),
                    ),
                  ],
                ),
                dropdown<PriceSource>(
                  'Origem do preço',
                  priceSource == PriceSource.unknown
                      ? PriceSource.informed
                      : priceSource,
                  {
                    for (final p in PriceSource.values.where(
                      (p) => p != PriceSource.unknown,
                    ))
                      p: p.label,
                  },
                  (v) => priceSource = v,
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Criativo'),
                  childrenPadding: const EdgeInsets.only(top: 8),
                  children: [
                    field(hook, 'Hook'),
                    field(headline, 'Headline'),
                    field(cta, 'CTA'),
                    field(angle, 'Ângulo de venda'),
                    field(
                      variations,
                      'Variações conhecidas de criativos',
                      max: 5,
                      keyboard: TextInputType.number,
                      helper:
                          'Apenas as que você viu. Deixe vazio se não souber.',
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final n = int.tryParse(v.trim());
                        return n == null || n < 1 || n > 10000
                            ? 'Use um número de 1 a 10.000.'
                            : null;
                      },
                    ),
                  ],
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Avaliação para o score'),
                  childrenPadding: const EdgeInsets.only(top: 8),
                  children: [
                    dropdown<int?>(
                      'Clareza da oferta',
                      clarity,
                      ratingItems,
                      (v) => clarity = v,
                    ),
                    dropdown<int?>(
                      'Qualidade da página de vendas',
                      salesQuality,
                      ratingItems,
                      (v) => salesQuality = v,
                    ),
                    dropdown<int?>(
                      'Sua avaliação',
                      rating,
                      ratingItems,
                      (v) => rating = v,
                    ),
                  ],
                ),
                section('IMAGEM'),
                if (imageFile != null)
                  _Thumb(
                    file: imageFile!,
                    onRemove: () {
                      setState(() => imageFile = null);
                    },
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _attachImage,
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: const Text('Adicionar print e analisar'),
                  ),
                if (ocrText.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Texto reconhecido salvo (${ocrText.length} caracteres)',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ),
                      TextButton(
                        onPressed: () => copyLink(
                          context,
                          ocrText,
                          message: 'Texto copiado.',
                        ),
                        child: const Text('Copiar'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.file, required this.onRemove});
  final String file;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: NativeBridge.imagePath(file),
    builder: (context, snap) => Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 72,
            height: 72,
            child: snap.data == null
                ? const ColoredBox(color: Colors.black12)
                : Image.file(File(snap.data!), fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(child: Text('Imagem anexada')),
        TextButton(onPressed: onRemove, child: const Text('Remover')),
      ],
    ),
  );
}
