import 'dart:math' as math;
import 'dart:ui';

import 'diner.dart';

/// Isometric projection of the build grid. A cell is a 32 by 16 diamond;
/// `x` runs down-right and `y` runs down-left. All numbers are art pixels
/// from the board's top-left corner.
class IsoView {
  IsoView(Diner d, {this.shift = Offset.zero}) {
    // Frame the room itself: its diamond, the tall back walls above it, the
    // front edge below it, and a little ground all round.
    final minX = (Diner.left - (d.bottom + 1)) * halfW - pad;
    final maxX = ((d.rightCol + 1) - d.topRow) * halfW + pad;
    final minY = ((Diner.left - 1) + (d.topRow - 1)) * halfH - headroom;
    final maxY = ((d.rightCol + 1) + (d.bottom + 1)) * halfH + 20;
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

  /// How far the room has been moved from the top-left of the canvas.
  final Offset shift;

  late final double _ox;
  late final double _oy;
  late final double width;
  late final double height;

  /// The ground cells whose tiles touch a canvas of [w] by [h] art pixels.
  Iterable<Cell> ground(Diner d, double w, double h) sync* {
    for (var y = Diner.top - 22; y <= d.bottom + 22; y++) {
      for (var x = Diner.left - 22; x <= d.right + 22; x++) {
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

/// How the room sits on a canvas: an art scale of a whole number of device
/// pixels, and the point of the room at the middle of the screen.
///
/// At [kFit] the whole room is visible and centred. Zooming in raises the
/// scale in whole steps up to [kMax]; the view can then be moved about, but
/// never so far that the room leaves the screen.
class BoardFit {
  BoardFit._({
    required this.view,
    required this.k,
    required this.kFit,
    required this.kMax,
    required this.focus,
    required this.dpr,
  });

  factory BoardFit.of(
    Diner d,
    Size canvas,
    double dpr, {
    int? k,
    Offset? focus,
  }) {
    final room = IsoView(d);
    final kFit = math.max(
      1,
      (math.min(canvas.width / room.width, canvas.height / room.height) * dpr)
          .floor(),
    );
    final kMax = math.min(12, math.max(kFit + 2, kFit * 3));
    final kk = (k ?? kFit).clamp(kFit, kMax);
    final s = kk / dpr;
    final w = canvas.width / s;
    final h = canvas.height / s;

    // Keep the room on screen, with a little ground to spare.
    double clampAxis(double want, double view, double room) {
      final lo = view / 2 - _slack;
      final hi = room - view / 2 + _slack;
      return lo > hi ? room / 2 : want.clamp(lo, hi);
    }

    final middle = Offset(room.width / 2, room.height / 2);
    // The whole room is always dead centre; only a zoomed view can move.
    final f = kk == kFit ? middle : (focus ?? middle);
    final fx = clampAxis(f.dx, w, room.width);
    final fy = clampAxis(f.dy, h, room.height);
    final shift = Offset(
      (w / 2 - fx).floorToDouble(),
      (h / 2 - fy).floorToDouble(),
    );
    return BoardFit._(
      view: IsoView(d, shift: shift),
      k: kk,
      kFit: kFit,
      kMax: kMax,
      focus: Offset(fx, fy),
      dpr: dpr,
    );
  }

  /// How far past the room's edge the view may travel, in art pixels.
  static const _slack = 24.0;

  final IsoView view;

  /// Device pixels per art pixel.
  final int k;
  final int kFit;
  final int kMax;

  /// The room point at the middle of the canvas, in art pixels from the room's
  /// top-left.
  final Offset focus;

  /// Device pixels per logical pixel.
  final double dpr;

  /// Logical size of one art pixel.
  double get s => k / dpr;

  bool get zoomed => k > kFit;

  /// Changes whenever anything is drawn in a different place.
  Object get key => (k, view.shift);
}
