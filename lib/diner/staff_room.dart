import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../ui/pixel/palette.dart';
import 'diner.dart';
import 'diner_art.dart';
import 'iso.dart';
import 'room.dart';

/// What the computer in the staff room can open.
enum DeskApp {
  menu('Menu', 'What you sell, and what it costs', 1),
  staff('Staff', 'Your team, hiring and training', 1),
  stats('Stats', 'Who comes, what sells, how the days go', 1),
  goals('Goals', 'What to aim for next', 1),
  upgrades('Upgrades', 'A better kitchen and a bigger team', 1),
  expand('Expand', 'Buy more of the plot', 1),
  bank('Bank', 'Borrow coins, and pay them back', 2),

  /// Not a program: asks the build screen to start over, from Goals.
  reset('Start over', 'Wipes the restaurant', 1),

  /// Not a program: asks the build screen to pick the door up.
  moveDoor('Move the door', 'Hang it somewhere else on the back wall', 1);

  const DeskApp(this.label, this.blurb, this.level);

  final String label;
  final String blurb;

  /// Restaurant level at which it appears on the computer.
  final int level;
}

/// Someone resting in the staff room, for drawing.
class Rester {
  const Rester(this.sprite, this.name, this.energy);

  /// 'chef' or 'waiter'.
  final String sprite;
  final String name;
  final int energy;
}

/// Where a thing about to go in the staff room would stand, and whether it
/// may.
class RoomGhost {
  const RoomGhost(this.kind, this.at, this.facing, this.ok);

  final RoomKind kind;
  final Cell at;
  final Dir facing;
  final bool ok;
}

/// The staff room as a small isometric room, four tiles across and five deep,
/// drawn to fill its box: the box is the picture's own size, so the room is
/// always centred in it.
class StaffRoomPainter extends CustomPainter {
  StaffRoomPainter({
    required this.art,
    required this.room,
    required this.resters,
    required this.unit,
    this.selected,
    this.ghost,
    this.moving,
  });

  final DinerArt art;
  final StaffRoom room;
  final List<Rester> resters;

  /// Logical size of one art pixel, a whole number of device pixels.
  final double unit;
  final RoomItem? selected;
  final RoomGhost? ghost;

  /// A thing being picked up and put down again: not drawn where it was.
  final RoomItem? moving;

  static const _pad = 6;

  /// The sprites that make up the empty room, with the tile each stands on.
  static List<(String, Cell)> shell() => [
    for (var y = 0; y < StaffRoom.rows; y++)
      for (var x = 0; x < StaffRoom.cols; x++)
        ((x + y).isEven ? 'floor_a' : 'floor_b', Cell(x, y)),
    for (var x = 0; x < StaffRoom.cols; x++)
      ('edge_l', Cell(x, StaffRoom.rows - 1)),
    for (var y = 0; y < StaffRoom.rows; y++)
      ('edge_r', Cell(StaffRoom.cols - 1, y)),
    ('wall_corner', const Cell(-1, -1)),
    for (var x = 0; x < StaffRoom.cols; x++) ('wall_a', Cell(x, -1)),
    for (var y = 0; y < StaffRoom.rows; y++) ('wall_b', Cell(-1, y)),
  ];

  /// Where cell (x, y) has its top vertex, with the room's own origin.
  static Offset vertex(num x, num y) => Offset(
    (x - y) * IsoView.halfW.toDouble(),
    (x + y) * IsoView.halfH.toDouble(),
  );

  /// The picture's extent in art pixels, found from the sprites themselves:
  /// the shell and every sprite that could stand anywhere in the room.
  static ui.Rect bounds(DinerArt art) {
    ui.Rect? r;
    void add(String name, Offset at, [double lift = 0]) {
      final s = art.sprite(name);
      if (s.blank) return;
      final box = ui.Rect.fromLTWH(
        at.dx - s.ax,
        at.dy - lift - s.ay,
        s.width.toDouble(),
        s.height.toDouble(),
      );
      r = r == null ? box : r!.expandToInclude(box);
    }

    for (final (n, c) in shell()) {
      add(n, vertex(c.x, c.y));
    }
    for (var y = 0; y < StaffRoom.rows; y++) {
      for (var x = 0; x < StaffRoom.cols; x++) {
        for (final n in [
          'sofa_sw',
          'sofa_ne',
          'office_pc_sw',
          'office_pc_ne',
          'plant',
        ]) {
          add(n, vertex(x, y));
        }
      }
    }
    final b = r ?? ui.Rect.zero;
    return b.inflate(_pad.toDouble());
  }

  /// The picture's size in art pixels.
  static ui.Size size(DinerArt art) {
    final b = bounds(art);
    return ui.Size(b.width, b.height);
  }

  /// Where the room's origin sits in the picture, in art pixels.
  static Offset origin(DinerArt art) {
    final b = bounds(art);
    return Offset(-b.left, -b.top);
  }

  /// The tile under [p], a point in the picture's art pixels.
  static Cell cellAt(DinerArt art, Offset p) {
    final o = origin(art);
    final dx = (p.dx - o.dx) / IsoView.halfW;
    final dy = (p.dy - o.dy) / IsoView.halfH;
    return Cell(((dy + dx) / 2).floor(), ((dy - dx) / 2).floor());
  }

  /// The middle of tile [c] in the picture, for taps and for people.
  static Offset centre(DinerArt art, Cell c) =>
      origin(art) + vertex(c.x + 0.5, c.y + 0.5);

  Offset _v(num x, num y) => origin(art) + vertex(x, y);

  void _blit(
    Canvas canvas,
    String name,
    Offset at, {
    double lift = 0,
    bool flip = false,
  }) {
    final spr = art.sprite(name);
    if (spr.blank) return;
    final ax = flip ? spr.width - 1 - spr.ax : spr.ax;
    final x = (at.dx - ax).round();
    final y = (at.dy - lift - spr.ay).round();
    final paint = Paint()
      ..filterQuality = FilterQuality.none
      ..isAntiAlias = false;
    final src = Rect.fromLTWH(
      0,
      0,
      spr.width.toDouble(),
      spr.height.toDouble(),
    );
    final dst = Rect.fromLTWH(
      x * unit,
      y * unit,
      spr.width * unit,
      spr.height * unit,
    );
    if (!flip) {
      canvas.drawImageRect(spr.image, src, dst, paint);
      return;
    }
    canvas
      ..save()
      ..translate(dst.center.dx, 0)
      ..scale(-1, 1)
      ..translate(-dst.center.dx, 0)
      ..drawImageRect(spr.image, src, dst, paint)
      ..restore();
  }

  void _cell(Canvas canvas, String name, Cell c) =>
      _blit(canvas, name, _v(c.x, c.y));

  void _outline(Canvas canvas, Cell c, Color colour) {
    final a = _v(c.x, c.y);
    final b = _v(c.x + 1, c.y);
    final d = _v(c.x + 1, c.y + 1);
    final e = _v(c.x, c.y + 1);
    final path = Path()
      ..moveTo(a.dx * unit, a.dy * unit)
      ..lineTo(b.dx * unit, b.dy * unit)
      ..lineTo(d.dx * unit, d.dy * unit)
      ..lineTo(e.dx * unit, e.dy * unit)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = colour
        ..style = PaintingStyle.stroke
        ..strokeWidth = unit * 2
        ..isAntiAlias = false,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Pal.panelLo);
    for (final (n, c) in shell()) {
      _cell(canvas, n, c);
    }
    for (final i in room.items.where((i) => i.def.floor && i != moving)) {
      _cell(canvas, i.def.sprite(i.facing), i.at);
    }
    // Things stand in order of depth, back to front.
    final sofas = room.items.where((i) => i.kind == RoomKind.sofa).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final things = <(double, void Function())>[
      for (final i in room.items.where((i) => !i.def.floor && i != moving))
        (
          (i.at.x + i.at.y).toDouble(),
          () => _cell(canvas, i.def.sprite(i.facing), i.at),
        ),
      for (var k = 0; k < resters.length && k < sofas.length; k++)
        if (sofas[k] != moving)
          (
            sofas[k].at.x + sofas[k].at.y + 0.5,
            () {
              final f = sofas[k].facing;
              // Only two seated views are drawn; the others are mirrors.
              final back = f == Dir.nw || f == Dir.ne;
              final flip = f == Dir.se || f == Dir.ne;
              _blit(
                canvas,
                '${resters[k].sprite}_${back ? 'nw' : 'sw'}_sit',
                _v(sofas[k].at.x + 0.5, sofas[k].at.y + 0.5),
                lift: 9,
                flip: flip,
              );
            },
          ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    for (final t in things) {
      t.$2();
    }
    final sel = selected;
    if (sel != null) _outline(canvas, sel.at, Pal.gold);
    final g = ghost;
    if (g != null) {
      if (g.ok) _cell(canvas, roomDefs[g.kind]!.sprite(g.facing), g.at);
      _outline(canvas, g.at, g.ok ? Pal.green : Pal.red);
    }
  }

  @override
  bool shouldRepaint(StaffRoomPainter old) => true;
}
