import 'package:flutter/material.dart';

/// AdsPocket's original 24px, rounded-stroke icon family. No font or network.
enum PocketGlyph {
  pocket,
  explore,
  library,
  saved,
  settings,
  search,
  arrow,
  grid,
  document,
  scan,
  layers,
  source,
  evidence,
  link,
}

class PocketIcon extends StatelessWidget {
  const PocketIcon(
    this.glyph, {
    super.key,
    this.size = 24,
    this.color,
    this.semanticLabel,
  });
  final PocketGlyph glyph;
  final double size;
  final Color? color;
  final String? semanticLabel;
  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    excludeSemantics: semanticLabel == null,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _PocketPainter(
          glyph,
          color ??
              IconTheme.of(context).color ??
              Theme.of(context).colorScheme.onSurface,
        ),
      ),
    ),
  );
}

class _PocketPainter extends CustomPainter {
  const _PocketPainter(this.glyph, this.color);
  final PocketGlyph glyph;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.65
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void line(double a, double b, double c, double d) =>
        canvas.drawLine(Offset(a, b), Offset(c, d), p);
    void box(double x, double y, double w, double h) => canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, h),
        const Radius.circular(2.5),
      ),
      p,
    );
    switch (glyph) {
      case PocketGlyph.pocket:
      case PocketGlyph.saved:
        canvas.drawPath(
          Path()
            ..moveTo(5, 4)
            ..lineTo(19, 4)
            ..lineTo(19, 15)
            ..quadraticBezierTo(12, 24, 5, 15)
            ..close(),
          p,
        );
        line(9, 10, 12, 13);
        line(12, 13, 15, 10);
      case PocketGlyph.explore:
        canvas.drawCircle(const Offset(12, 12), 9, p);
        canvas.drawPath(
          Path()
            ..moveTo(15.5, 8.5)
            ..lineTo(13.4, 13.4)
            ..lineTo(8.5, 15.5)
            ..lineTo(10.6, 10.6)
            ..close(),
          p,
        );
      case PocketGlyph.library:
        box(3, 4, 18, 16);
        line(3, 9, 21, 9);
        line(8, 9, 8, 20);
        line(11, 13, 17, 13);
        line(11, 16, 15, 16);
      case PocketGlyph.settings:
        for (final o in [
          const Offset(9, 6),
          const Offset(15, 12),
          const Offset(9, 18),
        ]) {
          line(4, o.dy, o.dx - 3, o.dy);
          line(o.dx + 3, o.dy, 20, o.dy);
          canvas.drawCircle(o, 2.2, p);
        }
      case PocketGlyph.search:
        canvas.drawCircle(const Offset(10.5, 10.5), 6.5, p);
        line(15.5, 15.5, 21, 21);
      case PocketGlyph.arrow:
        line(4, 12, 20, 12);
        line(14, 6, 20, 12);
        line(14, 18, 20, 12);
      case PocketGlyph.grid:
        box(3, 3, 7, 7);
        box(14, 3, 7, 7);
        box(3, 14, 7, 7);
        box(14, 14, 7, 7);
      case PocketGlyph.document:
        box(5, 3, 14, 18);
        line(9, 8, 15, 8);
        line(9, 12, 15, 12);
        line(9, 16, 12, 16);
      case PocketGlyph.scan:
        canvas.drawPath(
          Path()
            ..moveTo(3, 8)
            ..lineTo(3, 3)
            ..lineTo(8, 3)
            ..moveTo(16, 3)
            ..lineTo(21, 3)
            ..lineTo(21, 8)
            ..moveTo(21, 16)
            ..lineTo(21, 21)
            ..lineTo(16, 21)
            ..moveTo(8, 21)
            ..lineTo(3, 21)
            ..lineTo(3, 16),
          p,
        );
        line(7, 9, 17, 9);
        line(5, 12, 19, 12);
        line(7, 15, 14, 15);
      case PocketGlyph.layers:
        canvas.drawPath(
          Path()
            ..moveTo(3, 8)
            ..lineTo(12, 3)
            ..lineTo(21, 8)
            ..lineTo(12, 13)
            ..close()
            ..moveTo(3, 13)
            ..lineTo(12, 18)
            ..lineTo(21, 13)
            ..moveTo(3, 17)
            ..lineTo(12, 22)
            ..lineTo(21, 17),
          p,
        );
      case PocketGlyph.source:
        canvas.drawCircle(const Offset(12, 5), 2.5, p);
        canvas.drawCircle(const Offset(5, 18), 2.5, p);
        canvas.drawCircle(const Offset(19, 18), 2.5, p);
        line(10, 7, 6, 15);
        line(14, 7, 18, 15);
        line(8, 18, 16, 18);
      case PocketGlyph.evidence:
        box(5, 3, 14, 18);
        line(9, 8, 15, 8);
        line(8, 14, 11, 17);
        line(11, 17, 16, 12);
      case PocketGlyph.link:
        canvas.drawArc(const Rect.fromLTWH(3, 9, 12, 9), 1.57, 3.8, false, p);
        canvas.drawArc(const Rect.fromLTWH(9, 6, 12, 9), -1.57, 3.8, false, p);
        line(8, 14, 16, 10);
    }
  }

  @override
  bool shouldRepaint(_PocketPainter old) =>
      glyph != old.glyph || color != old.color;
}
