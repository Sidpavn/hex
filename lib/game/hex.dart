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

/// Maps hexes to screen pixels. Hex (0,0) sits at [origin].
class BoardLayout {
  const BoardLayout(this.size, this.origin);

  final double size;
  final Offset origin;

  static const int radius = 4;

  factory BoardLayout.fit(Size area) {
    final byWidth = area.width / (sqrt3 * (2 * radius + 1) + 0.8);
    final byHeight = area.height / (1.5 * 2 * radius + 3.2);
    return BoardLayout(math.min(byWidth, byHeight), area.center(Offset.zero));
  }

  Offset toPixel(double q, double r) =>
      origin + Offset(size * sqrt3 * (q + r / 2), size * 1.5 * r);

  Offset hexCenter(Hex h) => toPixel(h.q.toDouble(), h.r.toDouble());

  Offset unitToPixel(Offset u) => origin + u * size;

  Hex fromPixel(Offset p) {
    final x = (p.dx - origin.dx) / size;
    final y = (p.dy - origin.dy) / size;
    final fq = (sqrt3 / 3 * x - 1 / 3 * y);
    final fr = (2 / 3 * y);
    return _round(fq, fr);
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
