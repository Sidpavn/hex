import 'package:flutter/material.dart';

import 'pixel/palette.dart';
import 'pixel/pixel_ui.dart';

/// A row of hearts drawn in whole art pixels: [filled] of them red, the rest
/// empty outlines.
class PixelHearts extends StatelessWidget {
  const PixelHearts({super.key, required this.filled, this.of = 5});

  final int filled;
  final int of;

  /// The shape of one heart, seven pixels across and six down.
  static const shape = [
    '.##.##.',
    '#######',
    '#######',
    '.#####.',
    '..###..',
    '...#...',
  ];

  /// Pixels between hearts.
  static const gap = 2;

  static int get width => shape.first.length;
  static int get height => shape.length;

  @override
  Widget build(BuildContext context) {
    final u = PixelUi.unit(context);
    return CustomPaint(
      size: Size((of * (width + gap) - gap) * u, height * u),
      painter: HeartsPainter(filled.clamp(0, of), of, u),
    );
  }
}

class HeartsPainter extends CustomPainter {
  HeartsPainter(this.filled, this.of, this.unit);

  final int filled;
  final int of;
  final double unit;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = false;
    for (var i = 0; i < of; i++) {
      final x0 = i * (PixelHearts.width + PixelHearts.gap);
      final full = i < filled;
      for (var y = 0; y < PixelHearts.height; y++) {
        for (var x = 0; x < PixelHearts.width; x++) {
          if (PixelHearts.shape[y][x] != '#') continue;
          // A filled heart is red with a light spot at its top left; an empty
          // one is a dark heart with no light.
          paint.color = full
              ? (x == 1 && y == 1 ? Pal.goldLight : Pal.red)
              : Pal.dimmer;
          canvas.drawRect(
            Rect.fromLTWH((x0 + x) * unit, y * unit, unit, unit),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(HeartsPainter old) =>
      old.filled != filled || old.of != of || old.unit != unit;
}
