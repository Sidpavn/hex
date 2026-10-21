import 'package:flutter/material.dart';

import '../ui/widgets.dart';

/// The game's name on a diner's sign: a striped awning over a dark board with
/// a gold edge. Drawn on the pixel grid, flat colours only.
class TitleSign extends StatelessWidget {
  const TitleSign({super.key, required this.title, this.line});

  final String title;

  /// A short line under the name.
  final String? line;

  @override
  Widget build(BuildContext context) {
    final u = PixelUi.unit(context);
    return Stack(
      children: [
        Container(
          width: double.infinity,
          child: PixelBox(
            color: Pal.panelLo,
            border: Pal.goldDark,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PxText(
                  title,
                  key: const ValueKey('title'),
                  style: const TextStyle(
                    color: Pal.gold,
                    fontSize: 36,
                    height: 1,
                  ),
                ),
                if (line != null) ...[
                  PxText(
                    line!,
                    style: const TextStyle(color: Pal.dim, fontSize: 14),
                  ),
                ],
              ],
            ),
          ),
        ),
        CustomPaint(size: Size.fromHeight(9 * u), painter: _AwningPainter(u)),
      ],
    );
  }
}

/// Alternating gold and cream stripes, with the bottom edge scalloped.
class _AwningPainter extends CustomPainter {
  _AwningPainter(this.u);

  final double u;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..isAntiAlias = false;
    final stripe = 12 * u;
    final n = (size.width / stripe).ceil();
    for (var i = 0; i < n; i++) {
      final x = i * stripe;
      final w = (x + stripe > size.width) ? size.width - x : stripe;
      final gold = i.isEven;
      final body = gold ? Pal.gold : Pal.text;
      final edge = gold ? Pal.goldDark : Pal.dim;
      // The stripe, with a darker band along the top edge for depth.
      p.color = body;
      canvas.drawRect(Rect.fromLTWH(x, 0, w, 6 * u), p);
      p.color = edge;
      canvas.drawRect(Rect.fromLTWH(x, 0, w, 2 * u), p);
      // The scallop: two rows, each narrower, hanging below.
      p.color = body;
      canvas.drawRect(Rect.fromLTWH(x + 2 * u, 6 * u, w - 4 * u, 2 * u), p);
      canvas.drawRect(Rect.fromLTWH(x + 4 * u, 8 * u, w - 8 * u, u), p);
    }
  }

  @override
  bool shouldRepaint(_AwningPainter old) => old.u != u;
}
