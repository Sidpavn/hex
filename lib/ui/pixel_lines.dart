import 'package:flutter/material.dart';

import 'pixel/palette.dart';
import 'pixel/pixel_ui.dart';

/// One line on a [PixelLines] chart.
class PixelSeries {
  const PixelSeries(this.values, this.color);

  final List<num> values;
  final Color color;
}

/// A line chart drawn in whole art pixels: each series is a stepped pixel
/// line with a square at every day, on a scale shared by all of them, with a
/// dim line along the bottom (and at zero, if anything is below it).
class PixelLines extends StatelessWidget {
  const PixelLines({
    super.key,
    required this.series,
    this.height = 40,
    this.step = 12,
  });

  final List<PixelSeries> series;

  /// Chart height in art pixels, and the width between days.
  final int height;
  final int step;

  /// The chart's width in art pixels for [days] days.
  static int widthFor(int days, int step) => (days - 1) * step + 5;

  @override
  Widget build(BuildContext context) {
    final u = PixelUi.unit(context);
    final days = series.fold(
      0,
      (a, s) => s.values.length > a ? s.values.length : a,
    );
    return CustomPaint(
      size: Size(widthFor(days < 2 ? 2 : days, step) * u, (height + 5) * u),
      painter: LinesPainter(series, height, step, u),
    );
  }
}

class LinesPainter extends CustomPainter {
  LinesPainter(this.series, this.height, this.step, this.unit);

  final List<PixelSeries> series;
  final int height;
  final int step;
  final double unit;

  /// The art-pixel row for [v], 0 at the top.
  int _row(num v, num lo, num hi) {
    if (hi == lo) return height;
    return 2 + ((hi - v) / (hi - lo) * (height - 1)).round();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final all = [for (final s in series) ...s.values];
    if (all.isEmpty) return;
    var lo = all.reduce((a, b) => a < b ? a : b);
    var hi = all.reduce((a, b) => a > b ? a : b);
    if (lo > 0) lo = 0;
    if (hi < 0) hi = 0;
    final paint = Paint()..isAntiAlias = false;
    void dot(int x, int y, int w, Color c) {
      paint.color = c;
      canvas.drawRect(Rect.fromLTWH(x * unit, y * unit, w * unit, unit), paint);
    }

    final width = PixelLines.widthFor(
      series.fold(0, (a, s) => s.values.length > a ? s.values.length : a),
      step,
    );
    // The floor, and zero when anything dips below it.
    final base = _row(lo, lo, hi) + 1;
    dot(0, base + 1, width, Pal.dimmer);
    if (lo < 0) dot(0, _row(0, lo, hi), width, Pal.dimmer);

    for (final s in series) {
      final pts = <(int, int)>[
        for (var i = 0; i < s.values.length; i++)
          (2 + i * step, _row(s.values[i], lo, hi)),
      ];
      // Join the points with pixel lines.
      for (var i = 1; i < pts.length; i++) {
        var (x0, y0) = pts[i - 1];
        final (x1, y1) = pts[i];
        final dx = (x1 - x0).abs();
        final dy = -(y1 - y0).abs();
        final sx = x0 < x1 ? 1 : -1;
        final sy = y0 < y1 ? 1 : -1;
        var err = dx + dy;
        while (true) {
          dot(x0, y0, 1, s.color);
          if (x0 == x1 && y0 == y1) break;
          final e2 = 2 * err;
          if (e2 >= dy) {
            err += dy;
            x0 += sx;
          }
          if (e2 <= dx) {
            err += dx;
            y0 += sy;
          }
        }
      }
      // A square at every day, three art pixels across.
      for (final (x, y) in pts) {
        for (var k = -1; k <= 1; k++) {
          dot(x - 1, y + k, 3, s.color);
        }
      }
    }
  }

  @override
  bool shouldRepaint(LinesPainter old) =>
      old.series != series ||
      old.height != height ||
      old.step != step ||
      old.unit != unit;
}
