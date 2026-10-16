import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'pixel/palette.dart';
import 'pixel/pixel_ui.dart';

/// A round chart drawn the way the rest of the game is: a disc of whole art
/// pixels, flat colours, a one-pixel outline and one-pixel dividers between
/// slices. No smoothing and no gradient.
class PixelPie extends StatelessWidget {
  const PixelPie({
    super.key,
    required this.values,
    required this.colors,
    this.radius = 24,
  }) : assert(values.length == colors.length);

  /// Size of each slice, in any unit. Zero slices are left out.
  final List<num> values;
  final List<Color> colors;

  /// Radius in art pixels.
  final int radius;

  @override
  Widget build(BuildContext context) {
    final u = PixelUi.unit(context);
    final side = (radius * 2 + 3) * u;
    return CustomPaint(
      size: Size(side, side),
      painter: PiePainter(values, colors, radius, u),
    );
  }
}

class PiePainter extends CustomPainter {
  PiePainter(this.values, this.colors, this.radius, this.unit);

  final List<num> values;
  final List<Color> colors;
  final int radius;

  /// Logical size of one art pixel.
  final double unit;

  /// Which slice the art pixel at (x, y), counted from the middle, is in, or
  /// -1 if it is outside the disc. Slices run clockwise from the top.
  int sliceAt(int x, int y, List<double> edges) {
    final dx = x + 0.5;
    final dy = y + 0.5;
    if (dx * dx + dy * dy > radius * radius) return -1;
    var a = math.atan2(dx, -dy) / (2 * math.pi);
    if (a < 0) a += 1;
    for (var i = 0; i < edges.length; i++) {
      if (a < edges[i]) return i;
    }
    return edges.length - 1;
  }

  /// Where each slice ends, as a fraction of the way round. Empty slices end
  /// where they begin.
  List<double> get edges {
    final total = values.fold<double>(0, (a, v) => a + v);
    if (total <= 0) return const [];
    var run = 0.0;
    return [for (final v in values) run += v / total];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final e = edges;
    final c = radius + 1;
    final fill = Paint()..isAntiAlias = false;

    void px(int x, int y, Color col) {
      canvas.drawRect(
        Rect.fromLTWH((x + c) * unit, (y + c) * unit, unit, unit),
        fill..color = col,
      );
    }

    int at(int x, int y) {
      final s = sliceAt(x, y, e);
      if (s < 0) return -1;
      return e.isEmpty ? -2 : s;
    }

    for (var y = -radius - 1; y <= radius; y++) {
      for (var x = -radius - 1; x <= radius; x++) {
        final here = at(x, y);
        if (here == -1) {
          // Just outside the disc: the outline.
          final touches = [
            at(x - 1, y),
            at(x + 1, y),
            at(x, y - 1),
            at(x, y + 1),
          ].any((s) => s != -1);
          if (touches) px(x, y, Pal.ink);
          continue;
        }
        if (here == -2) {
          px(x, y, Pal.panelLo);
          continue;
        }
        // A one-pixel divider where this slice meets the next.
        final divide =
            at(x + 1, y) >= 0 && at(x + 1, y) != here ||
            at(x, y + 1) >= 0 && at(x, y + 1) != here;
        px(x, y, divide ? Pal.ink : colors[here]);
      }
    }
  }

  @override
  bool shouldRepaint(PiePainter old) =>
      old.values != values || old.colors != colors || old.unit != unit;
}

/// A row of columns in whole art pixels, for a count over time. Columns above
/// the line are [up] coloured, those below it [down]. With no negative values
/// the line is the bottom.
class PixelColumns extends StatelessWidget {
  const PixelColumns({
    super.key,
    required this.values,
    this.up = Pal.gold,
    this.down = Pal.red,
    this.height = 32,
    this.width = 6,
    this.gap = 2,
  });

  final List<num> values;
  final Color up;
  final Color down;

  /// Height of the tallest column, in art pixels, and of each column's width
  /// and the gap between them.
  final int height;
  final int width;
  final int gap;

  @override
  Widget build(BuildContext context) {
    final u = PixelUi.unit(context);
    final low = values.any((v) => v < 0);
    final rows = low ? height * 2 : height;
    return CustomPaint(
      size: Size((values.length * (width + gap) - gap) * u, (rows + 1) * u),
      painter: ColumnsPainter(values, up, down, height, width, gap, u),
    );
  }
}

class ColumnsPainter extends CustomPainter {
  ColumnsPainter(
    this.values,
    this.up,
    this.down,
    this.height,
    this.width,
    this.gap,
    this.unit,
  );

  final List<num> values;
  final Color up;
  final Color down;
  final int height;
  final int width;
  final int gap;
  final double unit;

  /// How tall column [i] is, in art pixels, negative for below the line.
  List<int> get heights {
    final big = values.fold<double>(
      0,
      (a, v) => math.max(a, v.abs().toDouble()),
    );
    if (big == 0) return [for (final _ in values) 0];
    return [
      for (final v in values)
        v == 0
            ? 0
            : (v * height / big)
                  .round()
                  .clamp(-height, height)
                  .clamp(v > 0 ? 1 : -height, v > 0 ? height : -1),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final low = values.any((v) => v < 0);
    final base = low ? height : height; // the line, from the top
    final paint = Paint()..isAntiAlias = false;
    final hs = heights;
    for (var i = 0; i < hs.length; i++) {
      final x = i * (width + gap);
      final h = hs[i];
      final top = h >= 0 ? base - h : base;
      canvas.drawRect(
        Rect.fromLTWH(x * unit, top * unit, width * unit, h.abs() * unit),
        paint..color = h >= 0 ? up : down,
      );
    }
    // The line the columns stand on.
    canvas.drawRect(
      Rect.fromLTWH(0, base * unit, size.width, unit),
      paint..color = Pal.dimmer,
    );
  }

  @override
  bool shouldRepaint(ColumnsPainter old) =>
      old.values != values || old.unit != unit;
}
