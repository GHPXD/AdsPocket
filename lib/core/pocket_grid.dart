import 'package:flutter/material.dart';
import 'pocket_icon.dart';

class PocketCollectionGrid extends StatelessWidget {
  const PocketCollectionGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      final columns =
          ((constraints.maxWidth - 48) / (145 * (scale > 1.4 ? 1.8 : 1)))
              .floor()
              .clamp(1, 3);
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 96),
        itemCount: itemCount,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          mainAxisExtent: 252 * (scale < 1 ? 1 : scale),
        ),
        itemBuilder: itemBuilder,
      );
    },
  );
}

/// Rows share their natural height; large fonts can grow without clipping.
class PocketGrid extends StatelessWidget {
  const PocketGrid({super.key, required this.children, this.minWidth = 145});
  final List<Widget> children;
  final double minWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final columns =
          (constraints.maxWidth / (minWidth * (scale > 1.4 ? 1.4 : 1)))
              .floor()
              .clamp(1, 3);
      return Column(
        children: [
          for (var i = 0; i < children.length; i += columns)
            Padding(
              padding: EdgeInsets.only(
                bottom: i + columns < children.length ? 12 : 0,
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = 0; j < columns; j++) ...[
                      if (j > 0) const SizedBox(width: 12),
                      Expanded(
                        child: i + j < children.length
                            ? children[i + j]
                            : const SizedBox(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}

class PocketTile extends StatelessWidget {
  const PocketTile({
    super.key,
    required this.title,
    required this.glyph,
    required this.onTap,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final PocketGlyph glyph;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              PocketIcon(glyph, color: c.primary, size: 23),
              const SizedBox(height: 14),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: TextStyle(fontSize: 12, color: c.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
