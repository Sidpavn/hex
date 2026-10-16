import 'diner.dart';

/// What can stand in the staff room.
enum RoomKind { computer, sofa, plant, rug }

/// What one kind of thing in the staff room is, costs and does.
class RoomDef {
  const RoomDef(
    this.kind,
    this.name,
    this.cost,
    this.info, {
    this.turns = false,
    this.floor = false,
  });

  final RoomKind kind;
  final String name;
  final int cost;
  final String info;

  /// Whether it has a front that matters.
  final bool turns;

  /// Lies on the floor, so things can stand on it.
  final bool floor;

  /// What selling it pays back. A sofa is not sold: its place in the room is
  /// part of the staff room upgrade.
  int get refund => switch (kind) {
    RoomKind.computer || RoomKind.sofa => 0,
    _ => cost ~/ 2,
  };

  /// The sprite for it facing [facing].
  String sprite(Dir facing) => switch (kind) {
    RoomKind.computer => 'office_pc_${facing.name}',
    RoomKind.sofa => 'sofa_${facing.name}',
    RoomKind.plant => 'plant',
    RoomKind.rug => 'rug',
  };
}

const Map<RoomKind, RoomDef> roomDefs = {
  RoomKind.computer: RoomDef(
    RoomKind.computer,
    'Computer',
    0,
    'Tap it to run the restaurant: menu, staff, stats and more.',
    turns: true,
  ),
  RoomKind.sofa: RoomDef(
    RoomKind.sofa,
    'Sofa',
    0,
    'A seat for a tired person to rest on. One per level of the Staff sofas '
        'upgrade.',
    turns: true,
  ),
  RoomKind.plant: RoomDef(
    RoomKind.plant,
    'Plant',
    15,
    'Something green. Just for looks.',
  ),
  RoomKind.rug: RoomDef(
    RoomKind.rug,
    'Rug',
    12,
    'Just for looks.',
    floor: true,
  ),
};

/// One thing in the staff room. [at] is its tile.
class RoomItem {
  RoomItem(this.id, this.kind, this.at, [this.facing = Dir.sw]);

  final int id;
  final RoomKind kind;
  Cell at;
  Dir facing;

  RoomDef get def => roomDefs[kind]!;
}

/// Why something cannot go where it was aimed.
enum RoomResult {
  ok,
  outside,
  taken,
  full,
  broke,
  onlyOne;

  String get message => switch (this) {
    ok => '',
    outside => 'Outside the room',
    taken => 'That spot is taken',
    full => 'Every sofa you have is in the room already',
    broke => 'Not enough coins',
    onlyOne => 'There is only one computer',
  };
}

/// The staff room: a small room four tiles across and five deep, with a
/// computer, and whatever else the player puts in it.
class StaffRoom {
  StaffRoom([List<RoomItem>? items]) : items = items ?? [] {
    _next = this.items.fold(0, (a, i) => i.id > a ? i.id : a) + 1;
  }

  /// A new room: the computer against the back wall, a plant and a rug.
  factory StaffRoom.starter() {
    final r = StaffRoom();
    r.put(RoomKind.computer, const Cell(3, 0), Dir.sw);
    r.put(RoomKind.plant, const Cell(0, 0));
    r.put(RoomKind.rug, const Cell(1, 3));
    return r;
  }

  static const cols = 4;
  static const rows = 5;

  final List<RoomItem> items;
  int _next = 1;

  bool inside(Cell c) => c.x >= 0 && c.x < cols && c.y >= 0 && c.y < rows;

  int get sofaCount => items.where((i) => i.kind == RoomKind.sofa).length;

  RoomItem? get computer {
    for (final i in items) {
      if (i.kind == RoomKind.computer) return i;
    }
    return null;
  }

  /// The thing standing on [c], and the rug under it, separately.
  RoomItem? objectAt(Cell c) {
    for (final i in items) {
      if (!i.def.floor && i.at == c) return i;
    }
    return null;
  }

  RoomItem? rugAt(Cell c) {
    for (final i in items) {
      if (i.def.floor && i.at == c) return i;
    }
    return null;
  }

  /// What a tap on [c] picks: what stands there, else the rug.
  RoomItem? pickAt(Cell c) => objectAt(c) ?? rugAt(c);

  /// Whether [kind] fits at [at]. [sofas] is how many sofas the room may
  /// hold; [ignore] is a thing being moved, counted as not there.
  RoomResult check(
    RoomKind kind,
    Cell at, {
    required int sofas,
    RoomItem? ignore,
  }) {
    if (!inside(at)) return RoomResult.outside;
    final def = roomDefs[kind]!;
    final other = def.floor ? rugAt(at) : objectAt(at);
    if (other != null && other != ignore) return RoomResult.taken;
    if (kind == RoomKind.computer &&
        items.any((i) => i.kind == kind && i != ignore)) {
      return RoomResult.onlyOne;
    }
    if (kind == RoomKind.sofa &&
        items.where((i) => i.kind == kind && i != ignore).length >= sofas) {
      return RoomResult.full;
    }
    return RoomResult.ok;
  }

  RoomItem put(RoomKind kind, Cell at, [Dir facing = Dir.sw]) {
    final i = RoomItem(_next++, kind, at, facing);
    items.add(i);
    return i;
  }

  /// The first free tile, front to back, that a [kind] could go on.
  Cell? freeSpot(RoomKind kind, {required int sofas}) {
    for (var y = rows - 1; y >= 0; y--) {
      for (var x = 0; x < cols; x++) {
        final c = Cell(x, y);
        if (check(kind, c, sofas: sofas) == RoomResult.ok) return c;
      }
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'items': [
      for (final i in items)
        {'k': i.kind.name, 'x': i.at.x, 'y': i.at.y, 'f': i.facing.name},
    ],
  };

  /// Reads a saved room, dropping whatever no longer fits. A room with no
  /// computer gets one back.
  static StaffRoom fromJson(Object? raw, {required int sofas}) {
    final r = StaffRoom();
    final list = raw is Map ? raw['items'] : null;
    if (list is! List) return StaffRoom.starter();
    for (final e in list) {
      if (e is! Map) continue;
      final kind = RoomKind.values.where((k) => k.name == e['k']).firstOrNull;
      if (kind == null || e['x'] is! int || e['y'] is! int) continue;
      final at = Cell(e['x'] as int, e['y'] as int);
      final facing =
          Dir.values.where((d) => d.name == e['f']).firstOrNull ?? Dir.sw;
      if (r.check(kind, at, sofas: sofas) == RoomResult.ok) {
        r.put(kind, at, facing);
      }
    }
    if (r.computer == null) {
      final spot = r.freeSpot(RoomKind.computer, sofas: sofas);
      r.put(RoomKind.computer, spot ?? const Cell(3, 0), Dir.sw);
    }
    return r;
  }
}
