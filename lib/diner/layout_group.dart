part of 'diner.dart';

/// A way of moving a group of fixtures as one piece: turn it a quarter turn
/// clockwise [turns] times about [pivot], then slide it by ([dx], [dy]).
class GroupMove {
  const GroupMove({
    this.dx = 0,
    this.dy = 0,
    this.turns = 0,
    this.pivot = const Cell(0, 0),
  });

  final int dx;
  final int dy;
  final int turns;
  final Cell pivot;

  /// Where the cell [c] ends up.
  Cell cell(Cell c) {
    var rx = c.x - pivot.x;
    var ry = c.y - pivot.y;
    for (var i = 0; i < turns % 4; i++) {
      // A quarter turn clockwise on screen: the step `sw` becomes `nw`.
      final t = rx;
      rx = -ry;
      ry = t;
    }
    return Cell(pivot.x + rx + dx, pivot.y + ry + dy);
  }

  /// The way something facing [d] faces afterwards.
  Dir face(Dir d) {
    var f = d;
    for (var i = 0; i < turns % 4; i++) {
      f = f.cw;
    }
    return f;
  }

  GroupMove copyWith({int? dx, int? dy, int? turns, Cell? pivot}) => GroupMove(
    dx: dx ?? this.dx,
    dy: dy ?? this.dy,
    turns: turns ?? this.turns,
    pivot: pivot ?? this.pivot,
  );
}

/// Where one fixture of a group ends up.
class Moved {
  const Moved(this.from, this.at, this.facing, this.cells);

  final Placed from;
  final Cell at;
  final Dir facing;
  final List<Cell> cells;
}

/// Moving, turning, copying and selling several fixtures at once.
extension GroupEditing on Diner {
  /// The middle of [group], as a cell: what it turns about.
  Cell groupPivot(Iterable<Placed> group) {
    final cells = [for (final p in group) ...p.cells];
    if (cells.isEmpty) return const Cell(0, 0);
    final xs = cells.map((c) => c.x);
    final ys = cells.map((c) => c.y);
    return Cell(
      (xs.reduce(math.min) + xs.reduce(math.max)) ~/ 2,
      (ys.reduce(math.min) + ys.reduce(math.max)) ~/ 2,
    );
  }

  /// What each fixture of [group] would be after [m].
  List<Moved> movedBy(Iterable<Placed> group, GroupMove m) => [
    for (final p in group)
      () {
        final cells = [for (final c in p.cells) m.cell(c)];
        final at = Cell(
          cells.map((c) => c.x).reduce(math.min),
          cells.map((c) => c.y).reduce(math.min),
        );
        final facing = p.def.rotates ? m.face(p.facing) : p.facing;
        return Moved(p, at, facing, cells);
      }(),
  ];

  /// The fixtures of [group] as they would stand after [m], as ghosts.
  List<Placed> ghostsOf(Iterable<Placed> group, GroupMove m) => [
    for (final mv in movedBy(group, m))
      Placed(0, mv.from.kind, mv.at, mv.facing),
  ];

  /// What it costs to copy [group].
  int groupCost(Iterable<Placed> group) =>
      group.fold(0, (a, p) => a + p.def.cost);

  /// What selling [group] pays back.
  int groupRefund(Iterable<Placed> group) =>
      group.fold(0, (a, p) => a + p.def.refund);

  /// Whether [group] can stand as [m] puts it: every piece inside, none on
  /// another fixture or the door, and a way still open to everywhere. With
  /// [copy] the group stays where it is and the pieces are new, so they must
  /// also be paid for and may not overlap the originals.
  PlaceResult checkGroup(
    Iterable<Placed> group,
    GroupMove m, {
    bool copy = false,
  }) {
    final list = group.toList();
    if (list.any((p) => p.kind == Kind.window)) return PlaceResult.wall;
    final moved = movedBy(list, m);
    final own = list.toSet();
    final taken = <Cell>{};
    final floors = <Cell>{};
    for (final mv in moved) {
      if (mv.from.def.hung) {
        if (!hangsKind(mv.from.kind, mv.at, mv.facing)) {
          return PlaceResult.hang;
        }
        continue;
      }
      final floor = mv.from.def.floor;
      for (final c in mv.cells) {
        if (!isInside(c)) return PlaceResult.outside;
        if (!floor && c == entrance) return PlaceResult.entrance;
        final other = floor ? floorAt(c) : objectAt(c);
        if (other != null && (copy || !own.contains(other))) {
          return PlaceResult.taken;
        }
        if (!(floor ? floors : taken).add(c)) return PlaceResult.taken;
      }
    }
    if (copy && coins < groupCost(list)) return PlaceResult.broke;
    // The way to everywhere must stay open with the group where it would be.
    final saved = List<Placed>.of(items);
    if (!copy) items.removeWhere(own.contains);
    for (final mv in moved) {
      items.add(Placed(0, mv.from.kind, mv.at, mv.facing));
    }
    final open = reachable().length;
    final all = insideCells().where(walkable).length;
    items
      ..clear()
      ..addAll(saved);
    return open == all ? PlaceResult.ok : PlaceResult.blocksWay;
  }

  /// Moves [group] as [m] says, if it fits. One undo takes it all back.
  PlaceResult moveGroup(Iterable<Placed> group, GroupMove m) {
    final list = group.toList();
    final r = checkGroup(list, m);
    if (r != PlaceResult.ok) return r;
    final moved = movedBy(list, m);
    remember(
      list.length == 1
          ? 'Moved ${list.first.def.name.toLowerCase()}'
          : 'Moved ${list.length} fixtures',
    );
    for (final mv in moved) {
      mv.from
        ..at = mv.at
        ..facing = mv.facing;
    }
    return r;
  }

  /// Makes new copies of [group] as [m] says, and pays for them.
  List<Placed> copyGroup(Iterable<Placed> group, GroupMove m) {
    final list = group.toList();
    if (checkGroup(list, m, copy: true) != PlaceResult.ok) return const [];
    final moved = movedBy(list, m);
    remember(
      list.length == 1
          ? 'Placed ${list.first.def.name.toLowerCase()}'
          : 'Copied ${list.length} fixtures',
    );
    coins -= groupCost(list);
    return [for (final mv in moved) _put(mv.from.kind, mv.at, mv.facing)];
  }

  /// Sells every fixture of [group] for its refund.
  void sellGroup(Iterable<Placed> group) {
    final list = [
      for (final p in group)
        if (items.contains(p)) p,
    ];
    if (list.isEmpty) return;
    remember(
      list.length == 1
          ? 'Sold ${list.first.def.name.toLowerCase()}'
          : 'Sold ${list.length} fixtures',
    );
    for (final p in list) {
      items.remove(p);
      coins += p.def.refund;
    }
  }
}
