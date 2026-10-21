import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../ui/pixel/palette.dart';
import 'actor.dart';
import 'city.dart';
import 'clock.dart';
import 'diner.dart';
import 'diner_art.dart';
import 'iso.dart';
import 'service.dart';

/// The sprite for a [kind] turned to [facing]. Only things with a front have
/// four.
String spriteName(Kind kind, Dir facing) => switch (kind) {
  Kind.counter ||
  Kind.grill ||
  Kind.fryer ||
  Kind.soda ||
  Kind.espresso ||
  Kind.oven ||
  Kind.freezer ||
  Kind.chair ||
  Kind.bench => '${kind.name}_${facing.name}',
  Kind.window => 'window_se',
  Kind.tv => 'tv_${facing == Dir.se ? 'se' : 'sw'}',
  _ => kind.name,
};

/// Draws the diner in isometric. [s] is the logical size of one art pixel and
/// must be a whole number of device pixels, so every sprite lands on the pixel
/// grid.
class DinerPainter extends CustomPainter {
  DinerPainter({
    required this.diner,
    required this.art,
    required this.fit,
    this.actors = const [],
    this.sim,
    this.clock,
    this.placing,
    this.hover,
    this.selected,
    this.facing = Dir.sw,
    this.moving,
    this.grid = false,
    this.placeOk,
    this.guestSel,
    this.group = const [],
    this.groupMoving = false,
    this.ghostGroup = const [],
    this.expanding = false,
    this.plotSel,
    this.flashPlot,
    this.flash = 0,
    this.showProblems = true,
    this.revision = 0,
    this.gesturing = false,
    this.doorOpen = _closed,
    StaticLayer? layer,
  }) : layer = layer ?? StaticLayer(),
       super(repaint: clock);

  final Diner diner;
  final DinerArt art;
  final BoardFit fit;
  double get s => fit.s;
  IsoView get view => fit.view;
  final List<Actor> actors;

  /// A running restaurant to draw people from, and the clock that says how far
  /// through the tick they are.
  final DinerSim? sim;
  final TickClock? clock;

  /// The fixture the player is about to put down, and the cell under their
  /// finger.
  final Kind? placing;
  final Cell? hover;
  final Placed? selected;

  /// Which way the fixture being placed will face.
  final Dir facing;

  /// A fixture being picked up and moved. It stays where it stood, outlined,
  /// until it is put down, so it never disappears.
  final Placed? moving;

  /// Outline every cell while building.
  final bool grid;

  /// Looking at what to buy: every section not yet owned is outlined on the
  /// ground, gold if it could be bought now, grey if not, and [plotSel] is the
  /// one the player has picked.
  final bool expanding;

  /// Whether the ghost can be put down where it is, if the screen has worked
  /// that out (it knows the facing and what is being moved).
  final bool? placeOk;

  /// The guest the player has tapped during service: outlined where they are.
  final Guest? guestSel;

  /// The fixtures chosen to be moved, turned, copied or sold together.
  final List<Placed> group;

  /// The group is being moved (not copied): it is lifted from where it is.
  final bool groupMoving;

  /// Where a group being moved or copied would stand, as ghosts. They show
  /// whole when [placeOk], and in red when not.
  final List<Placed> ghostGroup;
  final int? plotSel;

  /// A section that has just been picked or bought lights up for a moment: the
  /// step it is at, 3 down to 0 where it is gone.
  final int? flashPlot;
  final int flash;

  /// Mark fixtures that don't work.
  final bool showProblems;

  /// Bumped by the owner on every change, since [diner] is mutated in place.
  final int revision;

  /// The view is being dragged or pinched: draw the still parts directly, as
  /// caching an image that changes every frame would cost more than it saves.
  final bool gesturing;

  /// Whether the door sign says open. Asked every frame, since the day can
  /// end between rebuilds.
  final bool Function() doorOpen;
  static bool _closed() => false;

  /// The ground, floor and walls, drawn once and reused until something
  /// changes. The owner keeps it between painters so it survives rebuilds.
  final StaticLayer layer;

  late final Report _report = sim?.report ?? diner.report();
  late final bool _ghostOk =
      placeOk ??
      (placing != null &&
          hover != null &&
          diner.check(placing!, hover!) == PlaceResult.ok);

  /// The ground colour, dimmed like everything beyond the plot, so the
  /// restaurant is what the eye goes to. It is also used behind the board so
  /// it has no edge.
  static const _dim = Color(0x73141E1A);
  static final grass = Color.alphaBlend(_dim, const Color(0xFF8DCB6A));
  static const _gridLine = Color(0xFFB98F5E);
  static const _ok = Color(0xFF2F9E44);
  static const _bad = Color(0xFFD4301F);

  /// Images drawn so far, for measuring how much each frame asks of the GPU.
  @visibleForTesting
  int blits = 0;

  final Paint _paint = Paint()
    ..filterQuality = FilterQuality.none
    ..isAntiAlias = false;

  /// Like [_paint], but darker: for the ground beyond the plot.
  final Paint _dimPaint = Paint()
    ..filterQuality = FilterQuality.none
    ..isAntiAlias = false
    ..colorFilter = const ColorFilter.mode(_dim, BlendMode.srcATop);

  /// Draws [spr] with its origin at board point [at], [lift] art pixels up.
  void _blit(
    Canvas canvas,
    Spr spr,
    Offset at, {
    double lift = 0,
    bool flip = false,
    bool dim = false,
    bool faded = false,
  }) {
    if (spr.blank) return;
    final paint = dim ? _dimPaint : _paint;
    blits++;
    final ax = flip ? spr.width - 1 - spr.ax : spr.ax;
    final x = (at.dx - ax).round();
    final y = (at.dy - lift - spr.ay).round();
    final src = Rect.fromLTWH(
      0,
      0,
      spr.width.toDouble(),
      spr.height.toDouble(),
    );
    final dst = Rect.fromLTWH(x * s, y * s, spr.width * s, spr.height * s);
    if (faded) {
      // Every other art pixel, like a dither: the thing is still there, but
      // plainly not solid. (No fading: the pixel grid stays crisp.)
      canvas.saveLayer(dst, Paint());
      canvas.drawImageRect(spr.image, src, dst, paint);
      final holes = Path();
      for (var iy = 0; iy < spr.height; iy++) {
        for (var ix = 0; ix < spr.width; ix++) {
          if ((x + ix + y + iy).isOdd) {
            holes.addRect(Rect.fromLTWH((x + ix) * s, (y + iy) * s, s, s));
          }
        }
      }
      canvas.drawPath(
        holes,
        Paint()
          ..blendMode = BlendMode.dstOut
          ..isAntiAlias = false,
      );
      canvas.restore();
      return;
    }
    if (!flip) {
      canvas.drawImageRect(spr.image, src, dst, paint);
      return;
    }
    canvas
      ..save()
      ..translate(dst.right, dst.top)
      ..scale(-1, 1);
    canvas.drawImageRect(
      spr.image,
      src,
      Rect.fromLTWH(0, 0, dst.width, dst.height),
      paint,
    );
    canvas.restore();
  }

  void _cell(
    Canvas canvas,
    String name,
    Cell c, {
    bool flip = false,
    bool dim = false,
    bool faded = false,
  }) => _blit(
    canvas,
    art.sprite(name),
    view.vertex(c.x, c.y),
    flip: flip,
    dim: dim,
    faded: faded,
  );

  @override
  void paint(Canvas canvas, Size size) {
    // Everything that only changes when the layout does: one image.
    if (gesturing) {
      canvas
        ..save()
        ..clipRect(Offset.zero & size);
      _still(canvas, size);
      canvas.restore();
    } else {
      layer.paint(
        canvas,
        size,
        (revision, fit.key, size, grid, expanding, plotSel),
        fit.dpr,
        (c) => _still(c, size),
      );
    }

    // Everything below moves about, and some of it (a car driving out, the
    // building across the street) reaches past the board: keep it on it.
    canvas
      ..save()
      ..clipRect(Offset.zero & size);
    final live = [...actors, ...?sim?.actors(clock?.alpha ?? 1)];
    final things = <_Drawn>[
      for (final p in diner.items.where((p) => !p.def.floor))
        _Drawn(
          // Hung things are on the wall behind whatever stands in the cell.
          (p.at.x + p.def.w - 1 + p.at.y + p.def.h - 1) -
              (p.def.hung ? 0.1 : 0),
          true,
          () => _fixture(canvas, p),
        ),
      ..._walls(canvas),
      ..._front(canvas),
      for (final (name, c) in streetProps(diner))
        _Drawn((c.x + c.y).toDouble(), true, () => _cell(canvas, name, c)),
      for (final a in live) _Drawn(a.depth, false, () => _actor(canvas, a)),
    ];
    // Equal depths keep the order they were added in, whatever the sort does.
    for (var i = 0; i < things.length; i++) {
      things[i].seq = i;
    }
    things.sort();
    for (final d in things) {
      d.draw();
    }

    _warnings(canvas);
    final gs = guestSel;
    if (gs != null && !gs.gone) {
      final path = Path();
      _outline(path, gs.cell, 1, 1);
      _outlineShifted(path, gs.cell, 1, 1);
      _stroke(canvas, path, Pal.gold);
    }
    if (expanding) _plotOutlines(canvas);
    if (flash > 0 && flashPlot != null) _flashOn(canvas, flashPlot!);
    _cursor(canvas);
    canvas.restore();
  }

  /// The parts of the picture that never move between layout changes.
  void _still(Canvas canvas, Size size) {
    canvas
      ..clipRect(Offset.zero & size)
      ..drawRect(Offset.zero & size, Paint()..color = grass);

    // The street, the plot and the floor. Everything off the plot is dimmed.
    for (final c in view.ground(diner, size.width / s, size.height / s)) {
      _cell(canvas, groundTile(diner, c), c, dim: !onPlot(c));
    }
    if (expanding) _plotTints(canvas);
    // The neighbours and everything small in the town, back to front, dimmed
    // with the rest. All of it is in this one cached picture.
    final town = <(double, VoidCallback)>[
      for (final b in buildings)
        (
          (b.x0 + b.y0 + b.w + b.d).toDouble(),
          () => _cell(canvas, b.sprite, Cell(b.x0, b.y0), dim: true),
        ),
      for (final t in scenery)
        (
          (t.x + t.y + 1).toDouble() + (t.isCar ? 1 : 0),
          () => t.isCar
              ? _blit(
                  canvas,
                  art.sprite(t.sprite),
                  view.vertex(t.x + 0.5, t.y + 0.5),
                  dim: true,
                )
              : _cell(canvas, t.sprite, Cell(t.x, t.y), dim: true),
        ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    for (final piece in town) {
      piece.$2();
    }
    // The floor's front and right-hand edges, so it has thickness.
    for (final c in diner.insideCells()) {
      if (!diner.isInside(Cell(c.x, c.y + 1))) _cell(canvas, 'edge_l', c);
      if (!diner.isInside(Cell(c.x + 1, c.y))) _cell(canvas, 'edge_r', c);
    }

    for (final p in diner.items.where((p) => p.def.floor)) {
      _cell(canvas, p.kind.name, p.at);
    }
    _cell(canvas, 'mat', diner.entrance);

    if (grid) _gridLines(canvas);
  }

  /// The low wall along the front and down the right of whatever is owned,
  /// and the doorway in it. They stand in front of the people inside, and
  /// behind those on the pavement.
  List<_Drawn> _front(Canvas canvas) => [
    for (final c in diner.insideCells())
      if (!diner.isInside(Cell(c.x, c.y + 1)))
        _Drawn((c.x + c.y + 1.5), true, () {
          if (c == diner.entrance) {
            _cell(canvas, doorOpen() ? 'door_open' : 'door_closed', c);
          } else {
            _cell(canvas, 'front_l', c);
          }
        }),
    for (final c in diner.insideCells())
      // Where a section's side meets the back wall of the one in front of it,
      // the tall wall hides the end of the low one: leave that piece out.
      if (!diner.isInside(Cell(c.x + 1, c.y)) &&
          !diner.isInside(Cell(c.x + 1, c.y + 1)))
        _Drawn(c.x + c.y + 1.5, true, () => _cell(canvas, _rightWall(c), c)),
  ];

  /// The right-hand wall at row [y]: plain, or the two halves of the window.
  String _rightWall(Cell c) {
    final w = diner.window;
    if (w == null || c.x != w.at.x || c.y < w.at.y || c.y >= w.at.y + w.h) {
      return 'front_r';
    }
    return c.y == w.at.y ? 'front_win_r0' : 'front_win_r1';
  }

  void _fixture(Canvas canvas, Placed p) {
    // Whatever is being picked up stays where it was, faded, so the ghost
    // does not look like a second one.
    final lifted = p == moving || (groupMoving && group.contains(p));
    _cell(canvas, spriteName(p.kind, p.facing), p.at, faded: lifted);
  }

  void _actor(Canvas canvas, Actor a) {
    final feet = view.vertex(a.x, a.y);
    var top = a.lift;
    if (a.hasSprite) {
      final spr = art.sprite(a.name);
      _blit(canvas, spr, feet, lift: a.lift, flip: a.flip);
      if (!spr.blank) top += spr.ay - spr.trim.top;
    }
    final meter = a.meter;
    if (meter != null) {
      _meter(canvas, feet, top + 3, meter, a.meterKind);
      top += 6;
    }
    final badge = a.badge;
    if (badge != null) {
      _blit(canvas, art.sprite(badge), feet, lift: top + 3);
    }
    if (a.items.isNotEmpty) _order(canvas, feet, top + 3, a.items);
  }

  static const _white = Color(0xFFFFFFFF);

  /// A speech bubble with a picture of everything a guest is waiting for.
  void _order(Canvas canvas, Offset feet, double lift, List<String> items) {
    final n = items.length;
    final w = 5 + n * 11;
    const h = 15;
    final x = (feet.dx - w / 2).round();
    final y = (feet.dy - lift).round() - h - 3;
    void bar(int bx, int by, int bw, int bh, Color c) => canvas.drawRect(
      Rect.fromLTWH(bx * s, by * s, bw * s, bh * s),
      Paint()
        ..color = c
        ..isAntiAlias = false,
    );
    // Outline, then the white inside, with the corners cut.
    bar(x + 1, y, w - 2, h, _meterEdge);
    bar(x, y + 1, w, h - 2, _meterEdge);
    bar(x + 2, y + 1, w - 4, h - 2, _white);
    bar(x + 1, y + 2, w - 2, h - 4, _white);
    // The tail pointing down at them.
    final mid = (x + w / 2).round();
    bar(mid - 2, y + h, 4, 1, _meterEdge);
    bar(mid - 1, y + h + 1, 2, 1, _meterEdge);
    bar(mid - 1, y + h - 1, 2, 1, _white);
    for (var i = 0; i < n; i++) {
      final ico = art.sprite('ico_${items[i]}');
      _blit(canvas, ico, Offset(x + 2 + 6 + i * 11 + 0.0, y + 7.5), lift: 0);
    }
  }

  static const _meterW = 14;
  static const _meterEdge = Color(0xFF2A2036);
  static const _meterBack = Color(0xFF5A4F6B);
  static const _meterOk = Color(0xFF5CB85A);
  static const _meterMid = Color(0xFFF2C338);
  static const _meterLow = Color(0xFFE2493F);

  /// A small bar over someone's head: green, then yellow, then red as
  /// patience runs out; gold while something cooks.
  void _meter(Canvas canvas, Offset at, double lift, double v, Meter kind) {
    final x = (at.dx - _meterW / 2).round();
    final y = (at.dy - lift).round() - 3;
    final fill = kind == Meter.cooking
        ? _meterMid
        : v > 0.66
        ? _meterOk
        : v > 0.33
        ? _meterMid
        : _meterLow;
    void bar(int bx, int by, int w, int h, Color c) => canvas.drawRect(
      Rect.fromLTWH(bx * s, by * s, w * s, h * s),
      Paint()
        ..color = c
        ..isAntiAlias = false,
    );
    bar(x, y, _meterW, 4, _meterEdge);
    bar(x + 1, y + 1, _meterW - 2, 2, _meterBack);
    final w = ((_meterW - 2) * v.clamp(0.0, 1.0)).round();
    if (w > 0) bar(x + 1, y + 1, w, 2, fill);
  }

  /// The tall walls: along the back of whatever is owned, and down its left.
  /// Wherever a section ends, its edge gets a wall.
  ///
  /// They are sorted in with everything else. A wall stands on the line just
  /// in front of its own tile, so whatever is north or west of that line is
  /// behind it, and whatever is on the room's side is in front: a low wall
  /// across the gap beside a section is hidden by the tall wall in front of
  /// it, not drawn over it.
  List<_Drawn> _walls(Canvas canvas) {
    final out = <_Drawn>[];
    void wall(String name, Cell c) => out.add(
      _Drawn(c.x + c.y + 1 - 0.25, true, () => _cell(canvas, name, c)),
    );
    String across(int x) {
      final i = x - Diner.left;
      return i % 3 == 1
          ? 'wall_a_window'
          : (i == 2 ? 'wall_a_board' : 'wall_a');
    }

    for (final c in diner.insideCells()) {
      final north = !diner.isInside(Cell(c.x, c.y - 1));
      final west = !diner.isInside(Cell(c.x - 1, c.y));
      if (north) wall(across(c.x), Cell(c.x, c.y - 1));
      if (west) {
        final j = c.y - Diner.top;
        wall(j % 3 == 1 ? 'wall_b_window' : 'wall_b', Cell(c.x - 1, c.y));
      }
      if (north && west) wall('wall_corner', Cell(c.x - 1, c.y - 1));
    }
    return out;
  }

  /// A red mark over every fixture the layout check complains about.
  void _warnings(Canvas canvas) {
    if (!showProblems) return;
    final mark = art.sprite('warn');
    for (final p in _report.problems) {
      final spr = art.sprite(spriteName(p.at.kind, p.at.facing));
      final top = spr.ay - spr.trim.top;
      final centre = view.vertex(
        p.at.at.x + p.at.w / 2,
        p.at.at.y + p.at.h / 2,
      );
      _blit(canvas, mark, centre, lift: top - 2);
    }
  }

  // ------------------------------------------------------------- outlines

  void _pixel(Path path, int x, int y) =>
      path.addRect(Rect.fromLTWH(x * s, y * s, s, s));

  /// A one pixel line between whole-pixel points.
  void _line(Path path, Offset a, Offset b) {
    var x0 = a.dx.round(), y0 = a.dy.round();
    final x1 = b.dx.round(), y1 = b.dy.round();
    final dx = (x1 - x0).abs(), dy = -(y1 - y0).abs();
    final sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1;
    var err = dx + dy;
    while (true) {
      _pixel(path, x0, y0);
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

  void _outline(Path path, Cell at, int w, int h, {bool full = true}) {
    final top = view.vertex(at.x, at.y);
    final right = view.vertex(at.x + w, at.y);
    final bottom = view.vertex(at.x + w, at.y + h);
    final left = view.vertex(at.x, at.y + h);
    _line(path, left, top);
    _line(path, top, right);
    if (full) {
      _line(path, right, bottom);
      _line(path, bottom, left);
    }
  }

  void _stroke(Canvas canvas, Path path, Color c) => canvas.drawPath(
    path,
    Paint()
      ..color = c
      ..isAntiAlias = false,
  );

  void _gridLines(Canvas canvas) {
    final path = Path();
    for (final c in diner.insideCells()) {
      _outline(path, c, 1, 1, full: false);
      // Close the far sides wherever the restaurant ends.
      if (!diner.isInside(Cell(c.x, c.y + 1))) {
        _line(path, view.vertex(c.x, c.y + 1), view.vertex(c.x + 1, c.y + 1));
      }
      if (!diner.isInside(Cell(c.x + 1, c.y))) {
        _line(path, view.vertex(c.x + 1, c.y), view.vertex(c.x + 1, c.y + 1));
      }
    }
    _stroke(canvas, path, _gridLine);
  }

  /// The ground of [p] as a flat shape, for tinting.
  Path _ground(Plot p) {
    final path = Path()
      ..moveTo(view.vertex(p.x0, p.y0).dx * s, view.vertex(p.x0, p.y0).dy * s);
    for (final c in [
      (p.x1 + 1, p.y0),
      (p.x1 + 1, p.y1 + 1),
      (p.x0, p.y1 + 1),
    ]) {
      final v = view.vertex(c.$1, c.$2);
      path.lineTo(v.dx * s, v.dy * s);
    }
    return path..close();
  }

  /// A flat tint over each section that is not yet owned: gold on those that
  /// could be bought now, and a stronger gold on the one picked. Sections
  /// further back are left plain.
  void _plotTints(Canvas canvas) {
    for (var i = 0; i < Diner.plots.length; i++) {
      if (diner.owned.contains(i)) continue;
      final picked = plotSel == i;
      final next = diner.nextPlots.contains(i);
      if (!picked && !next) continue;
      canvas.drawPath(
        _ground(Diner.plots[i]),
        Paint()
          ..color = Pal.gold.withAlpha(picked ? 0x70 : 0x30)
          ..isAntiAlias = false,
      );
    }
  }

  /// The brief brightening of a section just picked or bought, in steps.
  void _flashOn(Canvas canvas, int i) {
    canvas.drawPath(
      _ground(Diner.plots[i]),
      Paint()
        ..color = Pal.goldLight.withAlpha(flash * 0x30)
        ..isAntiAlias = false,
    );
  }

  /// The sections of the plot still to buy, drawn on the ground.
  void _plotOutlines(Canvas canvas) {
    for (var i = 0; i < Diner.plots.length; i++) {
      if (diner.owned.contains(i)) continue;
      final p = Diner.plots[i];
      final path = Path();
      _outline(path, Cell(p.x0, p.y0), p.width, p.height);
      final picked = plotSel == i;
      if (picked) _outlineShifted(path, Cell(p.x0, p.y0), p.width, p.height);
      _stroke(
        canvas,
        path,
        picked || diner.nextPlots.contains(i) ? Pal.gold : Pal.dimmer,
      );
    }
  }

  /// A group being moved or copied, drawn where it would stand.
  void _groupGhost(Canvas canvas) {
    final ok = _ghostOk;
    final path = Path();
    for (final g in ghostGroup) {
      if (ok) _cell(canvas, spriteName(g.kind, g.facing), g.at);
      _outline(path, g.at, g.w, g.h);
      _outlineShifted(path, g.at, g.w, g.h);
      if (!ok) {
        final c = view.vertex(g.at.x + g.w / 2, g.at.y + g.h / 2);
        _line(path, c.translate(-6, 0), c.translate(6, 0));
        _line(path, c.translate(0, -3), c.translate(0, 3));
      }
    }
    _stroke(canvas, path, ok ? _ok : _bad);
  }

  /// Tints the tiles a piece of decor reaches, so it is clear where a TV or a
  /// plant would help before it is put down.
  void _auraTint(Canvas canvas, Placed p) {
    final cells = diner.auraCells(p);
    if (cells.isEmpty) return;
    final path = Path();
    for (final c in cells) {
      final a = view.vertex(c.x, c.y);
      final b = view.vertex(c.x + 1, c.y);
      final d = view.vertex(c.x + 1, c.y + 1);
      final e = view.vertex(c.x, c.y + 1);
      path
        ..moveTo(a.dx * s, a.dy * s)
        ..lineTo(b.dx * s, b.dy * s)
        ..lineTo(d.dx * s, d.dy * s)
        ..lineTo(e.dx * s, e.dy * s)
        ..close();
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Pal.blue.withAlpha(0x40)
        ..isAntiAlias = false,
    );
  }

  void _cursor(Canvas canvas) {
    final sel = selected ?? moving;
    if (sel != null && sel.def.aura != null) _auraTint(canvas, sel);
    final aimed = placing;
    final aimAt = hover;
    if (aimed != null && aimAt != null && fixtureDefs[aimed]!.aura != null) {
      _auraTint(canvas, Placed(0, aimed, aimAt, facing));
    }
    if (sel != null) {
      final path = Path();
      _outline(path, sel.at, sel.w, sel.h);
      // Two pixels thick so it reads over the floor pattern.
      _outlineShifted(path, sel.at, sel.w, sel.h);
      _stroke(canvas, path, Pal.gold);
    }
    for (final p in group) {
      final path = Path();
      _outline(path, p.at, p.w, p.h);
      _outlineShifted(path, p.at, p.w, p.h);
      _stroke(canvas, path, Pal.gold);
    }
    if (ghostGroup.isNotEmpty) _groupGhost(canvas);
    final kind = placing;
    final at = hover;
    if (kind == Kind.window) _windowSpots(canvas, at);
    if (kind == null || at == null) return;
    final ghost = Placed(0, kind, at, kind == Kind.window ? Dir.se : facing);
    final ok = _ghostOk;
    if (ok) _cell(canvas, spriteName(kind, facing), at);
    final path = Path();
    _outline(path, at, ghost.w, ghost.h);
    _outlineShifted(path, at, ghost.w, ghost.h);
    if (!ok) {
      final c = view.vertex(at.x + ghost.w / 2, at.y + ghost.h / 2);
      _line(path, c.translate(-8, 0), c.translate(8, 0));
      _line(path, c.translate(0, -4), c.translate(0, 4));
    }
    _stroke(canvas, path, ok ? _ok : _bad);
    if (ok) {
      _frontMarker(canvas, ghost);
    } else {
      _shutInTiles(canvas, kind, at);
    }
  }

  /// When a fixture would shut a tile in, the tile is marked, so it is clear
  /// where the way is blocked.
  void _shutInTiles(Canvas canvas, Kind kind, Cell at) {
    final shut = diner.cutOff(kind, at, facing: facing, ignore: moving);
    if (shut.isEmpty) return;
    final path = Path();
    for (final c in shut) {
      _outline(path, c, 1, 1);
      final m = view.vertex(c.x + 0.5, c.y + 0.5);
      _line(path, m.translate(-6, 0), m.translate(6, 0));
      _line(path, m.translate(0, -3), m.translate(0, 3));
    }
    _stroke(canvas, path, _bad);
  }

  /// While a window is being placed: every place on the right-hand wall it
  /// could go, and, for the one chosen, the tiles behind it where staff stand
  /// and the spot in the side street where a car will pull up.
  void _windowSpots(Canvas canvas, Cell? at) {
    final spots = Path();
    for (var y = Diner.top; y <= diner.bottom; y++) {
      if (diner.windowFits(y, ignore: moving)) {
        _outline(spots, Cell(diner.right, y), 1, 1);
      }
    }
    _stroke(canvas, spots, Pal.gold);
    if (at == null ||
        at.x != diner.right ||
        !diner.windowFits(at.y, ignore: moving)) {
      return;
    }
    final marks = Path();
    for (var dy = 0; dy < 2; dy++) {
      final inside = view.vertex(at.x - 0.5, at.y + dy + 0.5);
      _line(marks, inside.translate(-3, 0), inside.translate(3, 0));
      _line(marks, inside.translate(0, -1), inside.translate(0, 1));
    }
    _outline(marks, Cell(diner.inLane, at.y), 1, 2);
    _stroke(canvas, marks, _ok);
  }

  /// A small chevron on the tile in front of a fixture being placed, so it is
  /// clear which way it faces.
  void _frontMarker(Canvas canvas, Placed g) {
    if (!g.def.turns) return;
    final path = Path();
    for (final f in g.fronts) {
      final c = view.vertex(f.x + 0.5, f.y + 0.5);
      _line(path, c.translate(-3, 0), c.translate(3, 0));
      _line(path, c.translate(0, -1), c.translate(0, 1));
    }
    _stroke(canvas, path, Pal.gold);
  }

  void _outlineShifted(Path path, Cell at, int w, int h) {
    final top = view.vertex(at.x, at.y).translate(0, 1);
    final right = view.vertex(at.x + w, at.y).translate(0, 1);
    final bottom = view.vertex(at.x + w, at.y + h).translate(0, 1);
    final left = view.vertex(at.x, at.y + h).translate(0, 1);
    _line(path, left, top);
    _line(path, top, right);
    _line(path, right, bottom);
    _line(path, bottom, left);
  }

  @override
  bool shouldRepaint(covariant DinerPainter old) =>
      old.revision != revision ||
      old.fit != fit ||
      old.gesturing != gesturing ||
      old.placing != placing ||
      old.hover != hover ||
      old.selected != selected ||
      old.facing != facing ||
      old.moving != moving ||
      old.grid != grid ||
      old.expanding != expanding ||
      old.placeOk != placeOk ||
      old.guestSel != guestSel ||
      old.group != group ||
      old.groupMoving != groupMoving ||
      old.ghostGroup != ghostGroup ||
      old.plotSel != plotSel ||
      old.flashPlot != flashPlot ||
      old.flash != flash ||
      old.actors != actors ||
      old.sim != sim;
}

class _Drawn implements Comparable<_Drawn> {
  _Drawn(this.depth, this.fixture, this.draw);

  final double depth;

  /// Fixtures draw after people at the same depth: they are in front.
  final bool fixture;
  final VoidCallback draw;

  /// Where it was added, to settle ties.
  int seq = 0;

  @override
  int compareTo(_Drawn o) {
    final r = depth.compareTo(o.depth);
    if (r != 0) return r;
    if (fixture != o.fixture) return fixture ? 1 : -1;
    return seq.compareTo(o.seq);
  }
}

/// Draws something once into an image and replays it until [key] changes.
/// The diner's ground, floor and walls are hundreds of tiles that never move,
/// so a frame is one image plus the few things that do.
class StaticLayer {
  ui.Image? _image;
  ui.Picture? _picture;
  Object? _key;

  /// How many times it has been drawn from scratch.
  @visibleForTesting
  int builds = 0;

  void paint(
    Canvas canvas,
    Size size,
    Object key,
    double dpr,
    void Function(Canvas) draw,
  ) {
    if (key != _key) {
      dispose();
      final rec = ui.PictureRecorder();
      // Recorded at device resolution so it is replayed 1:1, never rescaled.
      draw(Canvas(rec)..scale(dpr));
      final pic = rec.endRecording();
      try {
        _image = pic.toImageSync(
          (size.width * dpr).ceil(),
          (size.height * dpr).ceil(),
        );
        pic.dispose();
      } catch (_) {
        _picture = pic;
      }
      _key = key;
      builds++;
    }
    final image = _image;
    if (image != null) {
      canvas
        ..save()
        ..scale(1 / dpr)
        ..drawImage(
          image,
          Offset.zero,
          Paint()
            ..filterQuality = FilterQuality.none
            ..isAntiAlias = false,
        )
        ..restore();
    } else if (_picture != null) {
      canvas.drawPicture(_picture!);
    }
  }

  void dispose() {
    _image?.dispose();
    _picture?.dispose();
    _image = null;
    _picture = null;
    _key = null;
  }
}
