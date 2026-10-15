import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../ui/pixel/palette.dart';
import 'actor.dart';
import 'clock.dart';
import 'diner.dart';
import 'diner_art.dart';
import 'iso.dart';
import 'service.dart';

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
    this.grid = false,
    this.showProblems = true,
    this.revision = 0,
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

  /// Outline every cell while building.
  final bool grid;

  /// Mark fixtures that don't work.
  final bool showProblems;

  /// Bumped by the owner on every change, since [diner] is mutated in place.
  final int revision;

  /// The ground, floor and walls, drawn once and reused until something
  /// changes. The owner keeps it between painters so it survives rebuilds.
  final StaticLayer layer;

  late final Report _report = sim?.report ?? diner.report();
  late final bool _ghostOk =
      placing != null &&
      hover != null &&
      diner.check(placing!, hover!) == PlaceResult.ok;

  /// The ground colour, also used behind the board so it has no edge.
  static const grass = Color(0xFF8DCB6A);
  static const _gridLine = Color(0xFFB98F5E);
  static const _ok = Color(0xFF2F9E44);
  static const _bad = Color(0xFFD4301F);

  /// Images drawn so far, for measuring how much each frame asks of the GPU.
  @visibleForTesting
  int blits = 0;

  final Paint _paint = Paint()
    ..filterQuality = FilterQuality.none
    ..isAntiAlias = false;

  /// Draws [spr] with its origin at board point [at], [lift] art pixels up.
  void _blit(
    Canvas canvas,
    Spr spr,
    Offset at, {
    double lift = 0,
    bool flip = false,
  }) {
    if (spr.blank) return;
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
    if (!flip) {
      canvas.drawImageRect(spr.image, src, dst, _paint);
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
      _paint,
    );
    canvas.restore();
  }

  void _cell(Canvas canvas, String name, Cell c, {bool flip = false}) =>
      _blit(canvas, art.sprite(name), view.vertex(c.x, c.y), flip: flip);

  @override
  void paint(Canvas canvas, Size size) {
    // Everything that only changes when the layout does: one image.
    layer.paint(
      canvas,
      size,
      (revision, fit.s, size, grid),
      fit.dpr,
      (c) => _still(c, size),
    );

    final live = [...actors, ...?sim?.actors(clock?.alpha ?? 1)];
    final things = <_Drawn>[
      for (final p in diner.items.where((p) => !p.def.floor))
        _Drawn(
          (p.at.x + p.def.w - 1 + p.at.y + p.def.h - 1).toDouble(),
          true,
          () => _fixture(canvas, p),
        ),
      for (final a in live) _Drawn(a.depth, false, () => _actor(canvas, a)),
    ]..sort();
    for (final d in things) {
      d.draw();
    }

    _warnings(canvas);
    _cursor(canvas);
  }

  /// The parts of the picture that never move between layout changes.
  void _still(Canvas canvas, Size size) {
    canvas
      ..clipRect(Offset.zero & size)
      ..drawRect(Offset.zero & size, Paint()..color = grass);

    // Ground, lots and floor.
    for (final c in view.ground(diner, size.width / s, size.height / s)) {
      final String name;
      if (diner.isInside(c)) {
        name = (c.x + c.y).isEven ? 'floor_a' : 'floor_b';
      } else if (diner.isNextLot(c)) {
        name = 'lot';
      } else {
        name = (c.x * 7 + c.y * 13) % 5 == 0 ? 'grass_b' : 'grass_a';
      }
      _cell(canvas, name, c);
    }
    // The floor's front edges, so it has thickness.
    for (var x = Diner.left; x <= diner.right; x++) {
      _cell(canvas, 'edge_l', Cell(x, diner.bottom));
    }
    for (var y = Diner.top; y <= diner.bottom; y++) {
      _cell(canvas, 'edge_r', Cell(diner.right, y));
    }

    for (final p in diner.items.where((p) => p.def.floor)) {
      _cell(canvas, p.kind.name, p.at);
    }
    _cell(canvas, 'mat', diner.entrance);

    if (grid) _gridLines(canvas);
    _walls(canvas);
  }

  void _fixture(Canvas canvas, Placed p) {
    final name = p.kind == Kind.chair
        ? 'chair_${diner.chairFacing(p.at).name}'
        : p.kind.name;
    _cell(canvas, name, p.at);
  }

  void _actor(Canvas canvas, Actor a) {
    final spr = art.sprite(a.name);
    final feet = view.vertex(a.x, a.y);
    _blit(canvas, spr, feet, lift: a.lift, flip: a.flip);
    final badge = a.badge;
    if (badge != null && !spr.blank) {
      final head = spr.ay - spr.trim.top;
      _blit(
        canvas,
        art.sprite(badge),
        feet.translate(0, 0),
        lift: a.lift + head + 2,
      );
    }
  }

  void _walls(Canvas canvas) {
    final back = <_Drawn>[];
    for (var x = Diner.left; x <= diner.right; x++) {
      final i = x - Diner.left;
      final name = i % 3 == 1
          ? 'wall_a_window'
          : (i == 2 ? 'wall_a_board' : 'wall_a');
      back.add(
        _Drawn(
          (x + Diner.top - 1).toDouble(),
          true,
          () => _cell(canvas, name, Cell(x, Diner.top - 1)),
        ),
      );
    }
    for (var y = Diner.top; y <= diner.bottom; y++) {
      final j = y - Diner.top;
      final name = j % 3 == 1 ? 'wall_b_window' : 'wall_b';
      back.add(
        _Drawn(
          (Diner.left - 1 + y).toDouble(),
          true,
          () => _cell(canvas, name, Cell(Diner.left - 1, y)),
        ),
      );
    }
    back.add(
      _Drawn(
        (Diner.left + Diner.top - 2).toDouble(),
        true,
        () => _cell(canvas, 'wall_corner', Cell(Diner.left - 1, Diner.top - 1)),
      ),
    );
    back.sort();
    for (final d in back) {
      d.draw();
    }
  }

  /// A red mark over every fixture the layout check complains about.
  void _warnings(Canvas canvas) {
    if (!showProblems) return;
    final mark = art.sprite('warn');
    for (final p in _report.problems) {
      final spr = art.sprite(p.at.kind.name);
      final top = spr.ay - spr.trim.top;
      final centre = view.vertex(
        p.at.at.x + p.at.def.w / 2,
        p.at.at.y + p.at.def.h / 2,
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
    for (var y = Diner.top; y <= diner.bottom; y++) {
      for (var x = Diner.left; x <= diner.right; x++) {
        _outline(path, Cell(x, y), 1, 1, full: false);
      }
    }
    // Close the far two sides of the room.
    for (var x = Diner.left; x <= diner.right; x++) {
      _line(
        path,
        view.vertex(x, diner.bottom + 1),
        view.vertex(x + 1, diner.bottom + 1),
      );
    }
    for (var y = Diner.top; y <= diner.bottom; y++) {
      _line(
        path,
        view.vertex(diner.right + 1, y),
        view.vertex(diner.right + 1, y + 1),
      );
    }
    _stroke(canvas, path, _gridLine);
  }

  void _cursor(Canvas canvas) {
    final sel = selected;
    if (sel != null) {
      final path = Path();
      _outline(path, sel.at, sel.def.w, sel.def.h);
      // Two pixels thick so it reads over the floor pattern.
      _outlineShifted(path, sel.at, sel.def.w, sel.def.h);
      _stroke(canvas, path, Pal.gold);
    }
    final kind = placing;
    final at = hover;
    if (kind == null || at == null) return;
    final def = fixtureDefs[kind]!;
    final ok = _ghostOk;
    if (ok) {
      final name = kind == Kind.chair ? 'chair_${Dir.sw.name}' : kind.name;
      _cell(canvas, name, at);
    }
    final path = Path();
    _outline(path, at, def.w, def.h);
    _outlineShifted(path, at, def.w, def.h);
    if (!ok) {
      final c = view.vertex(at.x + def.w / 2, at.y + def.h / 2);
      _line(path, c.translate(-8, 0), c.translate(8, 0));
      _line(path, c.translate(0, -4), c.translate(0, 4));
    }
    _stroke(canvas, path, ok ? _ok : _bad);
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
      old.placing != placing ||
      old.hover != hover ||
      old.selected != selected ||
      old.grid != grid ||
      old.actors != actors ||
      old.sim != sim;
}

class _Drawn implements Comparable<_Drawn> {
  _Drawn(this.depth, this.fixture, this.draw);

  final double depth;

  /// Fixtures draw after people at the same depth: they are in front.
  final bool fixture;
  final VoidCallback draw;

  @override
  int compareTo(_Drawn o) {
    final r = depth.compareTo(o.depth);
    if (r != 0) return r;
    if (fixture == o.fixture) return 0;
    return fixture ? 1 : -1;
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
