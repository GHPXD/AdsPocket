import 'package:flutter/material.dart';
import '../../app/app_controller.dart';
import '../../core/native_bridge.dart';
import '../../core/widgets.dart';
import '../../data/models.dart';
import '../favorites/bookmark_editor.dart';
import '../favorites/favorites_screen.dart';
import '../mining/mining_screen.dart';
import '../mining/ocr_screen.dart';
import '../mining/offer_editor.dart';

/// Everything saved while browsing: ads (one tap from the Library cards),
/// advertisers and other references.
class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key, required this.app});
  final AppController app;
  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  int section = 0;
  static const advertisers = {BookmarkKind.advertiser};
  static const others = {
    BookmarkKind.search,
    BookmarkKind.ad,
    BookmarkKind.offer,
    BookmarkKind.image,
    BookmarkKind.unidentified,
  };

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Salvos',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Adicionar',
                  icon: const Icon(Icons.add_rounded),
                  onSelected: _add,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'ocr',
                      child: Text('Analisar print (OCR)'),
                    ),
                    PopupMenuItem(
                      value: 'manual',
                      child: Text('Anúncio manualmente'),
                    ),
                    PopupMenuItem(
                      value: 'page',
                      child: Text('Anunciante por Page ID'),
                    ),
                    PopupMenuItem(
                      value: 'link',
                      child: Text('Link da Biblioteca'),
                    ),
                    PopupMenuItem(
                      value: 'offer',
                      child: Text('Loja ou oferta'),
                    ),
                    PopupMenuItem(value: 'image', child: Text('Imagem')),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: 0,
                    label: Text('Anúncios · ${app.offers.length}'),
                  ),
                  const ButtonSegment(value: 1, label: Text('Anunciantes')),
                  const ButtonSegment(value: 2, label: Text('Outros')),
                ],
                selected: {section},
                onSelectionChanged: (v) => setState(() => section = v.single),
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: section,
              children: [
                MiningScreen(app: app, embedded: true),
                FavoritesScreen(app: app, kinds: advertisers),
                FavoritesScreen(app: app, kinds: others),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _add(String v) async {
    final app = widget.app;
    switch (v) {
      case 'ocr':
        await analyzeImportedImage(context, app);
      case 'manual':
        await openOfferEditor(context, app);
      case 'page':
        await runGuarded(context, () async {
          final url = await askPageIdUrl(context, app);
          if (url != null && mounted) {
            await editBookmark(
              context,
              app,
              uri: url,
              kind: BookmarkKind.advertiser,
            );
          }
        });
      case 'link':
        await editBookmark(context, app, kind: BookmarkKind.ad);
      case 'offer':
        await editBookmark(context, app, kind: BookmarkKind.offer);
      case 'image':
        await runGuarded(context, () async {
          final file = await NativeBridge.pickImage();
          if (file != null && mounted) {
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
  }
}
