import 'dart:math' as math;
import 'dart:ui';

import 'diner.dart';

/// Isometric projection of the build grid. A cell is a 32 by 16 diamond;
/// `x` runs down-right and `y` runs down-left. All numbers are art pixels
/// from the board's top-left corner.
class IsoView {
  IsoView(Diner d, {Offset shift = Offset.zero}) {
    // Frame the room itself: its diamond, the tall back walls above it, the
    // front edge below it, and a little ground all round.
    final minX = (Diner.left - (d.bottom + 1)) * halfW - pad;
    final maxX = ((d.right + 1) - Diner.top) * halfW + pad;
    final minY = ((Diner.left - 1) + (Diner.top - 1)) * halfH - headroom;
    final maxY = ((d.right + 1) + (d.bottom + 1)) * halfH + 20;
    _ox = -minX + shift.dx;
    _oy = -minY + shift.dy;
    width = (maxX - minX).toDouble();
    height = (maxY - minY).toDouble();
  }

  static const halfW = 16;
  static const halfH = 8;

  /// Room above the corner post for the back walls.
  static const headroom = 52;

  /// Ground shown beyond the room's left and right corners.
  static const pad = 28;

  late final double _ox;
  late final double _oy;
  late final double width;
  late final double height;

  /// The ground cells whose tiles touch a canvas of [w] by [h] art pixels.
  Iterable<Cell> ground(Diner d, double w, double h) sync* {
    for (var y = Diner.top - 14; y <= d.bottom + 14; y++) {
      for (var x = Diner.left - 14; x <= d.right + 14; x++) {
        final v = vertex(x, y);
        if (v.dx > -halfW - 2 &&
            v.dx < w + halfW + 2 &&
            v.dy > -2 * halfH - 2 &&
            v.dy < h + 2 * halfH + 2) {
          yield Cell(x, y);
        }
      }
    }
  }

  /// Where the top vertex of grid point ([x], [y]) lands. Fractions work, so
  /// people can stand between cells.
  Offset vertex(num x, num y) =>
      Offset(_ox + (x - y) * halfW, _oy + (x + y) * halfH);

  /// The cell under a point on the board.
  Cell cellAt(Offset p) {
    final dx = (p.dx - _ox) / halfW;
    final dy = (p.dy - _oy) / halfH;
    return Cell(((dy + dx) / 2).floor(), ((dy - dx) / 2).floor());
  }
}

/// How the room sits on a canvas: the biggest whole-device-pixel art scale
/// that fits it, centred.
class BoardFit {
  BoardFit._(this.view, this.s, this.dpr);

  factory BoardFit.of(Diner d, Size canvas, double dpr) {
    final room = IsoView(d);
    final k = math.max(
      1,
      (math.min(canvas.width / room.width, canvas.height / room.height) * dpr)
          .floor(),
    );
    final s = k / dpr;
    final shift = Offset(
      ((canvas.width / s - room.width) / 2).floorToDouble(),
      ((canvas.height / s - room.height) / 2).floorToDouble(),
    );
    return BoardFit._(IsoView(d, shift: shift), s, dpr);
  }

  final IsoView view;

  /// Logical size of one art pixel.
  final double s;

  /// Device pixels per logical pixel.
  final double dpr;
}
