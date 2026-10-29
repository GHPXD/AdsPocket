import 'dart:io';
import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../core/longevity.dart';
import '../../core/native_bridge.dart';
import '../../core/ocr_engine.dart';
import '../../core/text_extraction.dart';
import '../../core/widgets.dart';
import '../../data/offer.dart';
import 'offer_editor.dart';

/// What the user explicitly confirmed on the analysis screen.
class OcrResult {
  const OcrResult({required this.text, this.date, this.price});
  final String text;
  final CivilDate? date;
  final PriceCandidate? price;
}

Future<void> analyzeImportedImage(BuildContext context, AppController app) =>
    runGuarded(context, () async {
      final file = await NativeBridge.pickImage();
      if (file != null && context.mounted) {
        await analyzeImage(context, app, file);
      }
    });

/// OCR → confirmation → prefilled catalog form. The image is removed again
/// when the user cancels and nothing references it.
Future<void> analyzeImage(
  BuildContext context,
  AppController app,
  String file, {
  DateTime? capturedAt,
  Uri? url,
}) async {
  final path = await NativeBridge.imagePath(file);
  if (path == null) {
    throw const FormatException('Imagem não encontrada neste aparelho.');
  }
  if (!context.mounted) return;
  final result = await Navigator.push<OcrResult>(
    context,
    MaterialPageRoute(
      builder: (_) => OcrScreen(app: app, path: path),
    ),
  );
  if (!context.mounted) return;
  if (result == null) {
    await discardUnusedImage(app, file);
    return;
  }
  await openOfferEditor(
    context,
    app,
    fromUrl: url,
    draft: OfferDraft(
      imageFile: file,
      ocrText: result.text,
      startDate: result.date,
      price: result.price,
      capturedAt: capturedAt ?? DateTime.now().toUtc(),
    ),
  );
}

Future<void> discardUnusedImage(AppController app, String file) async {
  if (!app.offers.any((o) => o.imageFile == file) &&
      !app.bookmarks.any((b) => b.localFile == file)) {
    await NativeBridge.deleteImage(file);
  }
}

class OcrScreen extends StatefulWidget {
  const OcrScreen({super.key, required this.app, required this.path});
  final AppController app;
  final String path;
  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  List<OcrLine>? lines;
  Size? imageSize;
  String? error;
  Rect? region;
  Offset? dragStart;

  /// While selecting, the list stops scrolling so drags draw the region.
  bool selecting = false;
  int? selected;
  bool noDate = false;
  PriceCandidate? price;

  String get text => linesText(lines ?? const [], region);
  late DateSuggestion suggestion = const DateSuggestion([]);
  List<PriceCandidate> prices = const [];

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final bytes = await File(widget.path).readAsBytes();
      final image = await decodeImageFromList(bytes);
      final size = Size(image.width.toDouble(), image.height.toDouble());
      image.dispose();
      final found = await widget.app.ocr.recognize(widget.path);
      if (!mounted) return;
      setState(() {
        imageSize = size;
        lines = found;
        _recompute();
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Não foi possível reconhecer o texto desta imagem. Tente outro print.',
        );
      }
    }
  }

  void _recompute() {
    suggestion = DateSuggestion(findDateCandidates(text));
    prices = findPriceCandidates(text);
    final pre = suggestion.preselected;
    selected = pre == null ? null : suggestion.candidates.indexOf(pre);
    noDate = false;
    if (price != null && !prices.contains(price)) price = null;
  }

  Future<void> _finish() async {
    final candidate = selected == null
        ? null
        : suggestion.candidates[selected!];
    if (candidate != null) {
      final today = CivilDate.today();
      if (candidate.date.compareTo(today) > 0) {
        await _info(
          'A data selecionada está no futuro e não pode ser a data de início.',
        );
        return;
      }
      final warnings = [
        if (candidate.evidence == DateEvidence.generic)
          'Esta data não aparece junto a uma frase de início ("Iniciado em", "Started running on").',
        if (suggestion.multipleAds && region == null)
          'A imagem parece conter mais de um anúncio. Confirme que esta data pertence ao anúncio que você vai catalogar.',
        if (candidate.ambiguousOrder)
          'O formato numérico é ambíguo (dia/mês ou mês/dia). Confirme a leitura ${candidate.date.label}.',
      ];
      if (warnings.isNotEmpty &&
          !await confirm(
            context,
            'Confirmar data de início?',
            '${warnings.join('\n\n')}\n\nData: ${candidate.date.label}',
            action: 'Usar esta data',
          )) {
        return;
      }
    }
    if (!mounted) return;
    Navigator.pop(
      context,
      OcrResult(text: text, date: candidate?.date, price: price),
    );
  }

  Future<void> _info(String message) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Entendi'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final today = CivilDate.today();
    final ready = lines != null;
    final canFinish = ready && (selected != null || noDate);
    return Scaffold(
      appBar: AppBar(title: const Text('Analisar imagem')),
      body: error != null
          ? Center(
              child: EmptyState(
                icon: Icons.image_not_supported_outlined,
                title: 'Texto não reconhecido',
                message: error!,
              ),
            )
          : ListView(
              physics: selecting ? const NeverScrollableScrollPhysics() : null,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                _image(colors),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        selecting
                            ? 'Arraste sobre o anúncio que deseja analisar.'
                            : region == null
                            ? 'Imagem inteira analisada.'
                            : 'Analisando apenas a área selecionada.',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (ready && !selecting)
                      TextButton.icon(
                        onPressed: () => setState(() => selecting = true),
                        icon: const Icon(Icons.crop_rounded, size: 18),
                        label: const Text('Selecionar área'),
                      ),
                    if (region != null && !selecting)
                      TextButton(
                        onPressed: () => setState(() {
                          region = null;
                          _recompute();
                        }),
                        child: const Text('Imagem inteira'),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (!ready)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Reconhecendo texto no aparelho…'),
                      ],
                    ),
                  )
                else ...[
                  const SectionTitle('Data de início'),
                  const SizedBox(height: 4),
                  if (suggestion.multipleAds)
                    _note(
                      colors,
                      Icons.layers_outlined,
                      'Há ${suggestion.startCandidates.length} datas de início. Selecione a área de um anúncio ou escolha a data correspondente.',
                    ),
                  if (suggestion.candidates.isEmpty)
                    _note(
                      colors,
                      Icons.event_busy_outlined,
                      'Nenhuma data encontrada no texto reconhecido.',
                    ),
                  for (var i = 0; i < suggestion.candidates.length; i++)
                    _candidate(i, suggestion.candidates[i], today, colors),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sem data de início'),
                    leading: Icon(
                      noDate
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: noDate ? colors.primary : null,
                    ),
                    onTap: () => setState(() {
                      noDate = true;
                      selected = null;
                    }),
                  ),
                  if (prices.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const SectionTitle('Preço sugerido'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final p in prices)
                          ChoiceChip(
                            label: Text(formatMoney(p.cents, p.currency)),
                            selected: price == p,
                            onSelected: (v) =>
                                setState(() => price = v ? p : null),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Registrado como "${PriceSource.ocr.label}".',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Texto reconhecido'),
                    trailing: IconButton(
                      tooltip: 'Copiar texto',
                      onPressed: text.isEmpty
                          ? null
                          : () => copyLink(
                              context,
                              text,
                              message: 'Texto copiado.',
                            ),
                      icon: const Icon(Icons.copy_rounded),
                    ),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SelectableText(
                          text.isEmpty ? 'Nenhum texto.' : text,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FilledButton(
            onPressed: canFinish ? _finish : null,
            child: Text(
              selected != null ? 'Confirmar e catalogar' : 'Continuar sem data',
            ),
          ),
        ),
      ),
    );
  }

  Widget _note(ColorScheme colors, IconData icon, String message) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: colors.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ),
      ],
    ),
  );

  Widget _candidate(
    int i,
    DateCandidate c,
    CivilDate today,
    ColorScheme colors,
  ) {
    final active = selected == i;
    final age = ageInDays(c.date, today);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        active ? Icons.radio_button_checked : Icons.radio_button_off,
        color: active ? colors.primary : null,
      ),
      title: Text('${c.date.label} · ${ageLabel(age)}'),
      subtitle: Text(
        '${c.evidence.label}${c.ambiguousOrder ? ' · formato ambíguo' : ''}\n“${c.excerpt}”',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      onTap: () => setState(() {
        selected = i;
        noDate = false;
      }),
    );
  }

  Widget _image(ColorScheme colors) {
    final size = imageSize;
    final image = Image.file(
      File(widget.path),
      fit: BoxFit.fill,
      errorBuilder: (_, e, s) => const SizedBox(height: 120),
    );
    if (size == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: image,
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // Keep tall screenshots readable without filling the whole screen.
        final width = constraints.maxWidth;
        final height = (width * size.height / size.width).clamp(0.0, 420.0);
        final shown = Size(height * size.width / size.height, height);
        final scale = shown.width / size.width;
        Offset toImage(Offset p) => Offset(
          (p.dx / scale).clamp(0, size.width),
          (p.dy / scale).clamp(0, size.height),
        );
        return Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox.fromSize(
              size: shown,
              child: GestureDetector(
                onPanStart: selecting
                    ? (d) => dragStart = toImage(d.localPosition)
                    : null,
                onPanUpdate: !selecting
                    ? null
                    : (d) => setState(
                        () => region = Rect.fromPoints(
                          dragStart!,
                          toImage(d.localPosition),
                        ),
                      ),
                onPanEnd: !selecting
                    ? null
                    : (_) => setState(() {
                        selecting = false;
                        if (region != null &&
                            (region!.width < 20 || region!.height < 20)) {
                          region = null;
                        }
                        _recompute();
                      }),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    image,
                    if (selecting)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: colors.primary, width: 2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    if (region != null)
                      CustomPaint(
                        painter: _RegionPainter(
                          Rect.fromLTRB(
                            region!.left * scale,
                            region!.top * scale,
                            region!.right * scale,
                            region!.bottom * scale,
                          ),
                          colors.primary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RegionPainter extends CustomPainter {
  _RegionPainter(this.rect, this.color);
  final Rect rect;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path()
      ..addRect(Offset.zero & size)
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(outside, Paint()..color = const Color(0x88000000));
    canvas.drawRect(
      rect,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_RegionPainter old) => old.rect != rect;
}
