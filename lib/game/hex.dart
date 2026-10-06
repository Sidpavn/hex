import 'dart:math' as math;
import 'dart:ui';

final double sqrt3 = math.sqrt(3);

/// Axial hex coordinate (pointy-top orientation).
class Hex {
  const Hex(this.q, this.r);

  final int q;
  final int r;

  int get s => -q - r;

  Hex operator +(Hex o) => Hex(q + o.q, r + o.r);
  Hex operator -(Hex o) => Hex(q - o.q, r - o.r);

  @override
  bool operator ==(Object other) =>
      other is Hex && other.q == q && other.r == r;

  @override
  int get hashCode => Object.hash(q, r);

  @override
  String toString() => 'Hex($q,$r)';

  static const List<Hex> dirs = [
    Hex(1, 0),
    Hex(1, -1),
    Hex(0, -1),
    Hex(-1, 0),
    Hex(-1, 1),
    Hex(0, 1),
  ];

  Hex neighbor(int dir) => this + dirs[dir % 6];

  Iterable<Hex> get neighbors sync* {
    for (final d in dirs) {
      yield this + d;
    }
  }

  int distanceTo(Hex o) {
    final d = this - o;
    return (d.q.abs() + d.r.abs() + d.s.abs()) ~/ 2;
  }

  /// Position in "unit space" where the hex circumradius is 1.
  Offset toUnit() => Offset(sqrt3 * (q + r / 2), 1.5 * r);

  /// Index into [dirs] that points most directly from this hex toward [target].
  int directionToward(Hex target) {
    final v = target.toUnit() - toUnit();
    var best = 0;
    var bestDot = -double.infinity;
    for (var i = 0; i < 6; i++) {
      final dv = dirs[i].toUnit();
      final dot = v.dx * dv.dx + v.dy * dv.dy;
      if (dot > bestDot) {
        bestDot = dot;
        best = i;
      }
    }
    return best;
  }
}

/// Maps hexes to screen pixels on a pixel-art grid.
///
/// One art pixel is [scale] logical pixels, always a whole number of device
/// pixels, so sprites stay crisp. A hex is 24 art pixels wide and rows step by
/// 21 (a 28-pixel-tall hex tessellates at 3/4 of its height). Hex (0,0) sits at
/// [origin].
class BoardLayout {
  const BoardLayout(this.scale, this.origin);

  /// Logical pixels per art pixel.
  final double scale;
  final Offset origin;

  static const int radius = 4;
  static const double hexW = 24;
  static const double rowH = 21;

  /// Hex circumradius in logical pixels, for effects specified in unit space.
  double get size => scale * hexW / sqrt3;

  factory BoardLayout.fit(Size area) {
    final views = PlatformDispatcher.instance.views;
    final dpr = views.isEmpty ? 1.0 : views.first.devicePixelRatio;
    const artW = hexW * (2 * radius + 1) + 8;
    const artH = rowH * 2 * radius + 28 + 24;
    final fit = math.min(area.width * dpr / artW, area.height * dpr / artH);
    final deviceScale = math.max(1.0, fit.floorToDouble());
    final c = area.center(Offset.zero);
    return BoardLayout(
      deviceScale / dpr,
      Offset(
        (c.dx * dpr).roundToDouble() / dpr,
        (c.dy * dpr).roundToDouble() / dpr,
      ),
    );
  }

  Offset toPixel(double q, double r) =>
      origin + Offset(scale * hexW * (q + r / 2), scale * rowH * r);

  Offset hexCenter(Hex h) => toPixel(h.q.toDouble(), h.r.toDouble());

  /// Effects live in unit space (circumradius 1); x maps 1:1 to [size], y is
  /// stretched slightly to match the 21px row step.
  Offset unitToPixel(Offset u) =>
      origin + Offset(u.dx * size, u.dy * scale * 14);

  /// Rounds [p] to the nearest art pixel so sprites never straddle a pixel.
  Offset snap(Offset p) =>
      origin +
      Offset(
        ((p.dx - origin.dx) / scale).roundToDouble() * scale,
        ((p.dy - origin.dy) / scale).roundToDouble() * scale,
      );

  Hex fromPixel(Offset p) {
    final r = (p.dy - origin.dy) / (scale * rowH);
    final q = (p.dx - origin.dx) / (scale * hexW) - r / 2;
    return _round(q, r);
  }

  static Hex _round(double fq, double fr) {
    final fs = -fq - fr;
    var q = fq.round();
    var r = fr.round();
    final s = fs.round();
    final dq = (q - fq).abs();
    final dr = (r - fr).abs();
    final ds = (s - fs).abs();
    if (dq > dr && dq > ds) {
      q = -r - s;
    } else if (dr > ds) {
      r = -q - s;
    }
    return Hex(q, r);
  }
}
