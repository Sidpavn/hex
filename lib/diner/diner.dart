/// The restaurant's build grid: which cells are open, what stands on them,
/// and the rules for placing, selling and expanding. Pure Dart, no Flutter, so
/// it can be tested and later driven by the idle clock.
library;

/// Size of one cell in art pixels.
const cellPx = 16;

/// The four ways to face on the grid. On screen `x` runs down-right and `y`
/// runs down-left, so these are the four diagonals.
enum Dir {
  se(1, 0),
  sw(0, 1),
  nw(-1, 0),
  ne(0, -1);

  const Dir(this.dx, this.dy);

  final int dx;
  final int dy;

  /// The direction of the one step from [from] to [to], if they touch.
  static Dir? between(Cell from, Cell to) {
    for (final d in values) {
      if (from.x + d.dx == to.x && from.y + d.dy == to.y) return d;
    }
    return null;
  }

  /// Sprites are drawn facing `sw` and `nw`; the other two are mirrors.
  bool get mirrored => this == se || this == ne;

  /// The drawn facing: `sw` or `nw`.
  String get art => (this == sw || this == se) ? 'sw' : 'nw';
}

/// A square cell on the build grid. `x` runs right, `y` runs down.
class Cell {
  const Cell(this.x, this.y);

  final int x;
  final int y;

  Cell operator +(Cell o) => Cell(x + o.x, y + o.y);

  /// The four orthogonal neighbours: customers and staff walk in these steps.
  List<Cell> get neighbors => [
    Cell(x + 1, y),
    Cell(x - 1, y),
    Cell(x, y + 1),
    Cell(x, y - 1),
  ];

  @override
  bool operator ==(Object other) =>
      other is Cell && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x,$y)';
}

enum Kind { counter, grill, table, chair, plant, jukebox, rug, bench }

/// What a fixture is. The sprite has the same name as the [Kind].
class FixtureDef {
  const FixtureDef(
    this.kind,
    this.name,
    this.cost, {
    this.w = 1,
    this.h = 1,
    this.floor = false,
  });

  final Kind kind;
  final String name;
  final int cost;

  /// Footprint in cells.
  final int w;
  final int h;

  /// Floor decoration: sits under everything and never blocks walking.
  final bool floor;

  int get refund => cost ~/ 2;
}

const Map<Kind, FixtureDef> fixtureDefs = {
  Kind.counter: FixtureDef(Kind.counter, 'Counter', 20),
  Kind.grill: FixtureDef(Kind.grill, 'Grill', 60),
  Kind.table: FixtureDef(Kind.table, 'Table', 30),
  Kind.chair: FixtureDef(Kind.chair, 'Chair', 10),
  Kind.bench: FixtureDef(Kind.bench, 'Bench', 40, w: 2),
  Kind.plant: FixtureDef(Kind.plant, 'Plant', 15),
  Kind.rug: FixtureDef(Kind.rug, 'Rug', 12, floor: true),
  Kind.jukebox: FixtureDef(Kind.jukebox, 'Jukebox', 120),
};

/// One fixture standing on the grid. [at] is its top-left cell.
class Placed {
  Placed(this.id, this.kind, this.at);

  final int id;
  final Kind kind;
  final Cell at;

  FixtureDef get def => fixtureDefs[kind]!;

  Iterable<Cell> get cells sync* {
    for (var dy = 0; dy < def.h; dy++) {
      for (var dx = 0; dx < def.w; dx++) {
        yield Cell(at.x + dx, at.y + dy);
      }
    }
  }
}

/// One size of the room and what it costs to grow into it.
class Stage {
  const Stage(this.width, this.height, this.cost);

  final int width;
  final int height;
  final int cost;
}

/// A spot a customer can sit, and the table cell they eat at.
class Seat {
  const Seat(this.cell, this.table);

  final Cell cell;
  final Cell table;
}

class Problem {
  const Problem(this.at, this.text);

  final Placed at;
  final String text;
}

/// The outcome of checking a layout.
class Report {
  const Report(this.problems, this.missing, this.seats);

  /// Fixtures that don't work, each with why.
  final List<Problem> problems;

  /// Things the diner needs before it can open.
  final List<String> missing;
  final int seats;

  bool get ready => missing.isEmpty;

  Problem? problemFor(Placed p) {
    for (final x in problems) {
      if (x.at == p) return x;
    }
    return null;
  }
}

enum PlaceResult {
  ok,
  outside,
  taken,
  entrance,
  broke,
  blocksWay,
  occupied;

  /// What to tell the player when a placement is refused.
  String get message => switch (this) {
    ok => '',
    outside => 'Outside the room',
    taken => 'That spot is taken',
    entrance => 'Keep the door clear',
    broke => 'Not enough coins',
    blocksWay => 'Leave a path to the door',
    occupied => 'Someone is standing there',
  };
}

class Diner {
  Diner({this.coins = 200, this.stage = 0});

  /// A small working diner: grill and counter along the back wall, two tables
  /// with chairs, a plant.
  factory Diner.starter() {
    final d = Diner(coins: 120);
    d._put(Kind.grill, const Cell(left, top));
    d._put(Kind.counter, const Cell(left + 1, top));
    d._put(Kind.counter, const Cell(left + 2, top));
    d._put(Kind.plant, const Cell(left + 5, top));
    d._put(Kind.rug, const Cell(left + 2, top + 2));
    d._put(Kind.table, const Cell(left + 1, top + 2));
    d._put(Kind.chair, const Cell(left, top + 2));
    d._put(Kind.table, const Cell(left + 4, top + 2));
    d._put(Kind.chair, const Cell(left + 5, top + 2));
    return d;
  }

  /// The grid is 12 wide and 14 tall. The back wall is row [wallY]; the
  /// dining room starts one row below it and only ever grows right and down.
  static const cols = 12;
  static const rows = 14;
  static const left = 1;
  static const wallY = 2;
  static const top = wallY + 1;

  static const stages = [
    Stage(6, 5, 0),
    Stage(8, 5, 80),
    Stage(8, 7, 160),
    Stage(10, 7, 300),
    Stage(10, 9, 500),
  ];

  int coins;
  int stage;
  final List<Placed> items = [];
  int _nextId = 1;

  int get width => stages[stage].width;
  int get height => stages[stage].height;
  int get right => left + width - 1;
  int get bottom => top + height - 1;

  /// The door is in the bottom row, two cells in from the left wall, and it
  /// never moves sideways so growing the room can't put it under a fixture.
  Cell get entrance => Cell(left + 2, bottom);

  Stage? get nextStage => stage + 1 < stages.length ? stages[stage + 1] : null;

  /// Inside the dining room as it is now.
  bool isInside(Cell c) =>
      c.x >= left && c.x <= right && c.y >= top && c.y <= bottom;

  /// Inside the biggest the room can get. Cells in here but not yet inside are
  /// lots waiting to be unlocked.
  static bool inLot(Cell c) =>
      c.x >= left &&
      c.x <= left + stages.last.width - 1 &&
      c.y >= top &&
      c.y <= top + stages.last.height - 1;

  /// Ground that the next expansion will open up.
  bool isNextLot(Cell c) {
    final n = nextStage;
    if (n == null || isInside(c)) return false;
    return c.x >= left &&
        c.x <= left + n.width - 1 &&
        c.y >= top &&
        c.y <= top + n.height - 1;
  }

  Placed? objectAt(Cell c) {
    for (final p in items) {
      if (!p.def.floor && p.cells.contains(c)) return p;
    }
    return null;
  }

  Placed? floorAt(Cell c) {
    for (final p in items) {
      if (p.def.floor && p.cells.contains(c)) return p;
    }
    return null;
  }

  /// Whatever the player would pick on tapping [c]: a fixture over a rug.
  Placed? pickAt(Cell c) => objectAt(c) ?? floorAt(c);

  bool walkable(Cell c) => isInside(c) && objectAt(c) == null;

  /// Every walkable cell reachable from the door.
  Set<Cell> reachable() {
    final seen = <Cell>{entrance};
    final todo = [entrance];
    while (todo.isNotEmpty) {
      final c = todo.removeLast();
      for (final n in c.neighbors) {
        if (walkable(n) && seen.add(n)) todo.add(n);
      }
    }
    return seen;
  }

  /// Which way a chair at [c] faces: toward the table beside it.
  Dir chairFacing(Cell c) {
    for (final d in Dir.values) {
      if (objectAt(Cell(c.x + d.dx, c.y + d.dy))?.kind == Kind.table) return d;
    }
    return Dir.sw;
  }

  /// The pavement cell outside the door, where customers come from and go.
  Cell get street => Cell(entrance.x, bottom + 1);

  /// Cells next to [c] a person can stand on.
  List<Cell> approaches(Cell c) => [
    for (final n in c.neighbors)
      if (walkable(n)) n,
  ];

  /// Every cell of [kind] fixtures.
  Iterable<Cell> cellsOf(Kind kind) sync* {
    for (final p in items) {
      if (p.kind == kind) yield* p.cells;
    }
  }

  /// A place a customer can sit: a chair or bench cell with a table beside
  /// it and somewhere to walk up from.
  List<Seat> seats() {
    final out = <Seat>[];
    for (final p in items) {
      if (p.kind != Kind.chair && p.kind != Kind.bench) continue;
      for (final c in p.cells) {
        final table = [
          for (final n in c.neighbors)
            if (objectAt(n)?.kind == Kind.table) n,
        ];
        if (table.isEmpty || approaches(c).isEmpty) continue;
        out.add(Seat(c, table.first));
      }
    }
    return out;
  }

  /// What is wrong with the layout, and whether the diner can open.
  Report report() {
    final problems = <Problem>[];
    final seatCells = {for (final s in seats()) s.cell};
    for (final p in items) {
      switch (p.kind) {
        case Kind.table:
          final hasSeat = p.cells.any(
            (c) => c.neighbors.any(seatCells.contains),
          );
          if (!hasSeat) problems.add(Problem(p, 'Table has no seat'));
        case Kind.chair || Kind.bench:
          final usable = p.cells.any(seatCells.contains);
          if (!usable) {
            final nextToTable = p.cells.any(
              (c) => c.neighbors.any((n) => objectAt(n)?.kind == Kind.table),
            );
            problems.add(
              Problem(
                p,
                nextToTable
                    ? '${p.def.name} is boxed in'
                    : '${p.def.name} needs a table beside it',
              ),
            );
          }
        case Kind.grill || Kind.counter:
          if (!p.cells.any((c) => approaches(c).isNotEmpty)) {
            problems.add(Problem(p, '${p.def.name} is boxed in'));
          }
        default:
      }
    }
    bool usable(Kind k) => items.any(
      (p) => p.kind == k && p.cells.any((c) => approaches(c).isNotEmpty),
    );
    final missing = [
      if (!usable(Kind.grill)) 'Needs a grill',
      if (!usable(Kind.counter)) 'Needs a counter',
      if (seatCells.isEmpty) 'Needs a chair beside a table',
    ];
    return Report(problems, missing, seatCells.length);
  }

  PlaceResult check(Kind kind, Cell at) {
    final def = fixtureDefs[kind]!;
    final probe = Placed(0, kind, at);
    for (final c in probe.cells) {
      if (!isInside(c)) return PlaceResult.outside;
    }
    for (final c in probe.cells) {
      if (def.floor ? floorAt(c) != null : objectAt(c) != null) {
        return PlaceResult.taken;
      }
      if (!def.floor && c == entrance) return PlaceResult.entrance;
    }
    if (coins < def.cost) return PlaceResult.broke;
    if (!def.floor) {
      // No pocket of floor may be cut off from the door.
      items.add(probe);
      final open = reachable();
      var all = 0;
      for (var y = top; y <= bottom; y++) {
        for (var x = left; x <= right; x++) {
          if (walkable(Cell(x, y))) all++;
        }
      }
      items.remove(probe);
      if (open.length != all) return PlaceResult.blocksWay;
    }
    return PlaceResult.ok;
  }

  PlaceResult place(Kind kind, Cell at) {
    final r = check(kind, at);
    if (r != PlaceResult.ok) return r;
    coins -= fixtureDefs[kind]!.cost;
    _put(kind, at);
    return r;
  }

  void _put(Kind kind, Cell at) => items.add(Placed(_nextId++, kind, at));

  /// Sells [p] back for half its price.
  void sell(Placed p) {
    if (items.remove(p)) coins += p.def.refund;
  }

  bool get canExpand => nextStage != null && coins >= nextStage!.cost;

  bool expand() {
    if (!canExpand) return false;
    coins -= nextStage!.cost;
    stage++;
    return true;
  }

  Map<String, Object?> toJson() => {
    'coins': coins,
    'stage': stage,
    'items': [
      for (final p in items) {'k': p.kind.name, 'x': p.at.x, 'y': p.at.y},
    ],
  };

  static Diner fromJson(Map<String, Object?> j) {
    final d = Diner(
      coins: (j['coins'] as int?) ?? 0,
      stage: ((j['stage'] as int?) ?? 0).clamp(0, stages.length - 1),
    );
    for (final raw in (j['items'] as List?) ?? const []) {
      final m = raw as Map;
      final kind = Kind.values.where((k) => k.name == m['k']).firstOrNull;
      if (kind == null) continue;
      final at = Cell(m['x'] as int, m['y'] as int);
      // Re-validate so a bad save can't put things outside the room.
      final probe = Placed(0, kind, at);
      if (probe.cells.every(d.isInside)) d._put(kind, at);
    }
    return d;
  }
}
