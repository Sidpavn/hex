import 'dart:math' as math;

import '../game/hex.dart';

/// The generated land past the quarry, in the order you walk it. Each id is a
/// zone; [outerRoom] builds its file text from the region seed.
const outerRooms = ['outer_a', 'outer_b', 'outer_c'];

/// What one room is for. The layout comes from the seed; this is the part
/// that stays the same: where the doors lead, who lives here, the floor.
class _Spec {
  const _Spec({
    required this.name,
    required this.floor,
    required this.w,
    required this.h,
    required this.back,
    required this.forward,
    this.guards = const [],
    this.node = false,
    this.hermit = false,
    this.puzzle = false,
    this.tier = 0,
  });

  final String name;
  final String floor;

  /// The canvas the room is carved from, in hexes.
  final int w, h;

  /// `zone portal` the entry door leads back to, and the exit door onward.
  final String back, forward;

  final List<String> guards;
  final bool node;
  final bool hermit;

  /// A door that opens when plates are pressed in order, with a maze that
  /// holds the note telling you the order.
  final bool puzzle;

  /// How tough the enemies are; see `tiers.dart`.
  final int tier;
}

const _specs = {
  // A wayside camp where the quarry opens out. Nothing here bites.
  'outer_a': _Spec(
    name: 'Wayside',
    floor: 'grass',
    w: 28,
    h: 20,
    back: 'quarry3 2',
    forward: 'outer_b 1',
    hermit: true,
  ),
  // A shut gate, four plates before it, and a maze off to one side.
  'outer_b': _Spec(
    name: 'Broken Road',
    floor: 'stone',
    w: 46,
    h: 33,
    back: 'outer_a 2',
    forward: 'outer_c 1',
    puzzle: true,
  ),
  // The first dark node, and the road to the city behind it.
  'outer_c': _Spec(
    name: 'Node Crossing',
    floor: 'stone',
    w: 38,
    h: 26,
    back: 'outer_b 2',
    forward: 'sixways 1',
    guards: ['knight', 'archer'],
    node: true,
    tier: 1,
  ),
};

const _colours = ['red', 'blue', 'yellow', 'green'];

/// Builds the zone file text for [id], one of [outerRooms].
///
/// The same seed always gives the same text, on every platform: it uses its
/// own small generator, not `dart:math`'s `Random`. Every obstacle is only
/// kept if the hero can still walk from the entry to the exit (and to the
/// node or the scroll), so a seed can never produce an unwinnable room.
String outerRoom(String id, int seed) {
  final spec = _specs[id]!;
  final w = spec.w, h = spec.h;
  final rng = _Rng(seed * 31 + outerRooms.indexOf(id));

  bool inside(Hex a) {
    final c = _col(a);
    return c >= 1 && c <= w - 2 && a.r >= 1 && a.r <= h - 2;
  }

  final open = <Hex>{};
  void carve(Iterable<Hex> cells) => open.addAll(cells.where(inside));
  void carveDisc(Hex c, int r) => carve(_disc(c, r));

  // Hexes the scatter of pillars, forest and pond must leave alone.
  final keep = <Hex>{};

  late final Hex entry, exit;
  Hex? node, doorAt, scrollAt, centreE;
  var plates = <(String, Hex)>[];
  var order = <String>[];
  final fixedGuards = <(String, Hex, String)>[]; // type, hex, behaviour

  if (spec.puzzle) {
    // Two big rooms joined by a one-hex corridor with the door in it, and a
    // maze off the first room.
    final mid = h ~/ 2;
    final centreA = _hex(9, mid);
    centreE = _hex(w - 10, mid);
    entry = _hex(4, mid);
    exit = _hex(w - 5, mid);
    carveDisc(centreA, 5);
    carveDisc(centreE, 5);
    final kink = _hex(w ~/ 2, mid + rng.next(5) - 2);
    final neck = [..._line(centreA, kink), ..._line(kink, centreE)];
    carve(neck);
    doorAt = kink;
    keep
      ..addAll(neck)
      ..add(kink);

    // The maze: grown on a disc to the north or south of the first room.
    final north = rng.next(2) == 0;
    final lobe = _hex(16 + rng.next(5), north ? 6 : h - 7);
    final domain = {
      for (final a in _disc(lobe, 6))
        if (inside(a) && a.distanceTo(centreA) > 6) a,
    };
    var start = domain.first;
    for (final a in domain) {
      if (a.distanceTo(centreA) < start.distanceTo(centreA)) start = a;
    }
    final carved = {start};
    final parent = <Hex, Hex>{};
    final depth = {start: 0};
    final stack = [start];
    while (stack.isNotEmpty) {
      final cur = stack.last;
      final next = [
        for (final n in cur.neighbors)
          if (domain.contains(n) &&
              !carved.contains(n) &&
              n.neighbors.where(carved.contains).length == 1)
            n,
      ];
      if (next.isEmpty) {
        stack.removeLast();
        continue;
      }
      final n = next[rng.next(next.length)];
      carved.add(n);
      parent[n] = cur;
      depth[n] = depth[cur]! + 1;
      stack.add(n);
    }
    carve(carved);
    // A one-hex tunnel from the first room to the mouth of the maze.
    final tunnel = _line(centreA, start);
    carve(tunnel);
    keep
      ..addAll(carved)
      ..addAll(tunnel);

    // The note lies at the end of the longest way in; the guards stand along
    // the way to it, so you cannot skip them.
    scrollAt = carved.reduce((a, b) => depth[a]! >= depth[b]! ? a : b);
    final route = <Hex>[];
    for (Hex? a = scrollAt; a != null; a = parent[a]) {
      route.add(a);
    }
    final way = route.reversed.toList(); // the mouth .. the scroll
    Hex along(double f) =>
        way[(way.length * f).floor().clamp(1, way.length - 2)];
    fixedGuards
      ..add(('knight', along(0.3), 'sleep'))
      ..add(('knight', along(0.6), 'sleep'))
      ..add(('archer', along(0.88), 'guard'));

    // Plates in the first room, off the line to the door, well apart.
    final spawnHint = _hex(5, mid);
    final line = _line(_hex(10, mid), kink);
    final spots = [
      for (final a in _disc(centreA, 4))
        if (line.every((l) => l.distanceTo(a) >= 2) &&
            a.distanceTo(spawnHint) >= 3)
          a,
    ];
    rng.shuffle(spots);
    final chosen = <Hex>[];
    for (final a in spots) {
      if (chosen.every((b) => b.distanceTo(a) >= 2)) chosen.add(a);
      if (chosen.length == 4) break;
    }
    final colours = [..._colours];
    rng.shuffleStrings(colours);
    plates = [
      for (var i = 0; i < chosen.length && i < 4; i++) (colours[i], chosen[i]),
    ];
    order = [...colours.take(3)];
    rng.shuffleStrings(order);
    keep.addAll(chosen);
  } else {
    // A winding path from the entry to the exit, wide in places and narrow
    // in others, so no two seeds give the same outline.
    entry = _hex(1, 3 + rng.next(h - 6));
    exit = _hex(w - 2, 3 + rng.next(h - 6));
    final bends = spec.node ? 1 : 2;
    final points = [
      entry,
      for (var i = 1; i <= bends; i++)
        _hex(1 + ((w - 3) * i) ~/ (bends + 1), 4 + rng.next(h - 8)),
      exit,
    ];
    for (var i = 0; i + 1 < points.length; i++) {
      for (final a in _line(points[i], points[i + 1])) {
        carveDisc(a, math.max(1, 3 - rng.next(3)));
      }
    }
    carveDisc(entry, 2);
    carveDisc(exit, 2);
    if (spec.node) {
      node = points[1];
      carveDisc(node, 6);
    }
  }

  final spawn = Hex(entry.q + 1, entry.r);
  open.add(spawn);
  final t = <Hex, String>{for (final a in open) a: '.'};
  for (final a in open) {
    for (final n in a.neighbors) {
      t.putIfAbsent(n, () => '^');
    }
  }
  t[entry] = '1';
  t[spawn] = '@';
  t[exit] = '2';
  if (doorAt != null) t[doorAt] = 'D';

  final ring = [?node, ...?node?.neighbors];
  bool passable(Hex a) => const {'.', 'f', 'D', '@', '1', '2'}.contains(t[a]);

  bool connected(Hex a, Hex b) {
    final seen = {a};
    final todo = [a];
    while (todo.isNotEmpty) {
      final at = todo.removeLast();
      if (at == b) return true;
      for (final n in at.neighbors) {
        if (n != node && !seen.contains(n) && passable(n)) {
          seen.add(n);
          todo.add(n);
        }
      }
    }
    return false;
  }

  bool winnable() =>
      connected(spawn, exit) &&
      (node == null || connected(spawn, node.neighbors.first)) &&
      (scrollAt == null || connected(spawn, scrollAt));

  bool free(Hex a) =>
      t[a] == '.' &&
      !keep.contains(a) &&
      !ring.contains(a) &&
      a.distanceTo(spawn) > 2 &&
      a.distanceTo(entry) > 2 &&
      a.distanceTo(exit) > 2;

  void place(Iterable<Hex> cells, String ch) {
    final spots = [
      for (final a in cells)
        if (free(a)) a,
    ];
    final was = {for (final a in spots) a: t[a]!};
    for (final a in spots) {
      t[a] = ch;
    }
    if (!winnable()) t.addAll(was);
  }

  final cells = open.toList();
  Hex anywhere() => cells[rng.next(cells.length)];

  Iterable<Hex> blob(Hex centre, int radius) => [
    for (final a in _disc(centre, radius))
      if (a.distanceTo(centre) < radius || rng.next(2) == 0) a,
  ];

  // Pillars give cover; forest and a pond break up the floor.
  for (var i = 0, n = cells.length ~/ 22 + rng.next(5); i < n; i++) {
    place([anywhere()], '^');
  }
  for (var i = 0, n = 1 + cells.length ~/ 160; i < n; i++) {
    place(blob(anywhere(), 1 + rng.next(2)), 'f');
  }
  if (cells.length > 500) place(blob(anywhere(), 2), '~');

  // Camp, potion, hermit and guards go on whatever floor is left.
  final floor = [
    for (final a in t.keys)
      if (t[a] == '.' &&
          !keep.contains(a) &&
          !ring.contains(a) &&
          (node == null || a.distanceTo(node) >= 2))
        a,
  ];
  rng.shuffle(floor);
  final taken = <Hex>[];

  Hex? pick(bool Function(Hex) ok, {bool blocks = false}) {
    for (final a in floor) {
      if (taken.contains(a) || !ok(a)) continue;
      if (blocks) {
        // Someone standing here must not seal off the room.
        t[a] = '^';
        final fine = winnable();
        t[a] = '.';
        if (!fine) continue;
      }
      taken.add(a);
      return a;
    }
    return null;
  }

  final camp = pick(
    (a) => a.distanceTo(spawn) >= 2 && a.distanceTo(spawn) <= 5,
    blocks: true,
  );
  final hermit = spec.hermit
      ? pick(
          (a) => a.distanceTo(spawn) >= 3 && a.distanceTo(spawn) <= 5,
          blocks: true,
        )
      : null;
  final potion = pick((a) => a.distanceTo(spawn) >= 4);
  final guards = <(String, Hex, String)>[...fixedGuards];
  for (final type in spec.guards) {
    final at = pick(
      (a) =>
          a.distanceTo(spawn) >= 6 &&
          (node == null || a.distanceTo(node) >= 3) &&
          a.distanceTo(exit) >= 4 &&
          guards.every((g) => g.$2.distanceTo(a) >= 3),
    );
    if (at != null) guards.add((type, at, 'guard'));
  }
  if (spec.puzzle) {
    // Past the door: a knight and an archer between you and the exit.
    for (final type in const ['knight', 'archer']) {
      final at = pick(
        (a) =>
            centreE != null &&
            a.distanceTo(centreE) <= 4 &&
            a.distanceTo(exit) >= 3 &&
            guards.every((g) => g.$2.distanceTo(a) >= 3),
      );
      if (at != null) guards.add((type, at, 'guard'));
    }
  }

  String at(Hex a) => '${_col(a)} ${a.r}';
  final rows = [
    for (var r = 0; r < h; r++)
      [for (var c = 0; c < w; c++) t[_hex(c, r)] ?? ' '].join(),
  ];
  return [
    'zone $id',
    'name ${spec.name}',
    'dark 0',
    'floor ${spec.floor}',
    if (spec.tier > 0) 'tier ${spec.tier}',
    'portal 1 ${spec.back} cave_exit',
    'portal 2 ${spec.forward} cave',
    if (spec.node) 'gate 2 nodes 1 A_dark_pulse_holds_the_road.',
    if (order.isNotEmpty) 'sequence ${order.join(' ')}',
    for (final (colour, a) in plates) 'plate $colour ${at(a)}',
    if (camp != null) 'camp ${at(camp)}',
    if (hermit != null) 'npc hermit Hermit ${at(hermit)} mage',
    if (potion != null) 'item potion1 ${at(potion)} potion',
    if (scrollAt != null) 'item gate ${at(scrollAt)} scroll_gate',
    if (node != null) 'enemy node ${at(node)} guard',
    for (final (type, a, how) in guards) 'enemy $type ${at(a)} $how',
    'map',
    ...rows,
  ].join('\n');
}

/// Axial hex for "odd-r" offset coordinates, as the zone parser reads them.
Hex _hex(int col, int row) => Hex(col - (row - (row & 1)) ~/ 2, row);

int _col(Hex a) => a.q + (a.r - (a.r & 1)) ~/ 2;

/// Every hex within [r] of [c].
Iterable<Hex> _disc(Hex c, int r) sync* {
  for (var dq = -r; dq <= r; dq++) {
    for (var dr = math.max(-r, -dq - r); dr <= math.min(r, -dq + r); dr++) {
      yield Hex(c.q + dq, c.r + dr);
    }
  }
}

/// The hexes on the straight line from [a] to [b], both ends included.
List<Hex> _line(Hex a, Hex b) {
  final n = a.distanceTo(b);
  if (n == 0) return [a];
  return [
    for (var i = 0; i <= n; i++)
      () {
        final t = i / n;
        final fq = a.q + (b.q - a.q) * t + 1e-6;
        final fr = a.r + (b.r - a.r) * t + 1e-6;
        final fs = -fq - fr;
        var rq = fq.round(), rr = fr.round();
        final rs = fs.round();
        final dq = (rq - fq).abs(), dr = (rr - fr).abs(), ds = (rs - fs).abs();
        if (dq > dr && dq > ds) {
          rq = -rr - rs;
        } else if (dr > ds) {
          rr = -rq - rs;
        }
        return Hex(rq, rr);
      }(),
  ];
}

/// A 32-bit xorshift. Same seed, same numbers, on every platform.
class _Rng {
  _Rng(int seed) : _s = ((seed ^ 0x9E3779B9) & 0xFFFFFFFF) | 1 {
    for (var i = 0; i < 4; i++) {
      _step();
    }
  }

  int _s;

  int _step() {
    var x = _s;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    return _s = x;
  }

  /// 0 up to but not including [n].
  int next(int n) => _step() % n;

  void shuffle(List<Hex> list) {
    for (var i = list.length - 1; i > 0; i--) {
      final j = next(i + 1);
      final a = list[i];
      list[i] = list[j];
      list[j] = a;
    }
  }

  void shuffleStrings(List<String> list) {
    for (var i = list.length - 1; i > 0; i--) {
      final j = next(i + 1);
      final a = list[i];
      list[i] = list[j];
      list[j] = a;
    }
  }
}
