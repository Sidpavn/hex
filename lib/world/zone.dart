import 'package:flutter/services.dart';

import '../game/hex.dart';
import '../game/models.dart';
import 'gen_zone.dart';
import 'lore.dart';

/// World position of a hex centre in art pixels (24 wide, rows 21 apart).
Offset hexWorld(Hex h) =>
    Offset(BoardLayout.hexW * (h.q + h.r / 2), BoardLayout.rowH * h.r);

/// The hex under a world position (art pixels).
Hex hexAtWorld(Offset w) {
  final r = w.dy / BoardLayout.rowH;
  final q = w.dx / BoardLayout.hexW - r / 2;
  return BoardLayout.roundHex(q, r);
}

/// How an enemy behaves until it notices the hero.
enum Behavior {
  /// Asleep: only wakes if you come very close or make a fuss.
  sleep,

  /// Stands its ground, returns to its post after a chase.
  guard,

  /// Walks a loop between waypoints.
  patrol,

  /// Drifts around near its home.
  wander,
}

class EnemySpawn {
  const EnemySpawn(this.type, this.hex, this.behavior, this.route);

  final UnitType type;
  final Hex hex;
  final Behavior behavior;

  /// Patrol waypoints (including the start).
  final List<Hex> route;
}

class NpcSpawn {
  const NpcSpawn(this.id, this.name, this.hex, this.unit);

  final String id;
  final String name;
  final Hex hex;

  /// Which unit sprite to draw them with.
  final UnitType unit;
}

/// Something lying on the ground to pick up. [id] is unique within the zone;
/// [itemId] says what it is (see `items.dart`).
class ItemSpawn {
  const ItemSpawn(this.id, this.hex, this.itemId, {this.chest = false});

  final String id;
  final Hex hex;
  final String itemId;

  /// Sits in a chest: stepping on it opens the chest and shows the item
  /// before it is taken.
  final bool chest;
}

class ZoneTile {
  const ZoneTile(
    this.terrain, {
    this.ford = false,
    this.broken = false,
    this.rubble = false,
    this.charge = false,
    this.door = false,
    this.plate,
    this.portal,
  });

  final Terrain terrain;

  /// Shallow water you can wade across (slow).
  final bool ford;

  /// Water where a bridge used to be. Wood mends it into a ford.
  final bool broken;

  /// Fallen rock across a passage. A connected run of rubble is cleared
  /// together when a nearby charge goes off.
  final bool rubble;

  /// A crate of blasting powder. It blocks the hex and only goes off when
  /// the hero's Fireball reaches it.
  final bool charge;

  /// A shut puzzle door. It blocks the hex until its plates are pressed in
  /// the right order (see [Zone.plateOrder]).
  final bool door;

  /// The colour of a pressure plate on this hex, or null.
  final String? plate;

  /// Id of the portal on this tile, if any.
  final String? portal;

  bool get walkable =>
      !charge &&
      !door &&
      (ford ||
          (terrain != Terrain.water &&
              terrain != Terrain.lava &&
              terrain != Terrain.mountain));

  int get cost => ford || terrain == Terrain.forest ? 2 : 1;
}

/// A doorway to another zone: a cave mouth, stairs, a gate.
class Portal {
  const Portal(this.id, this.toZone, this.toPortal, this.sprite);

  final String id;
  final String toZone;

  /// The portal id in [toZone] you arrive at.
  final String toPortal;
  final String sprite;
}

/// A portal that opens once [nodes] dark nodes are broken.
class NodeGate {
  const NodeGate(this.nodes, this.message);

  final int nodes;
  final String message;
}

/// One explorable area. Loaded from `assets/zones/<id>.txt`; see
/// `design/gen_zones.py` for the format.
class Zone {
  Zone({
    required this.id,
    required this.name,
    required this.tiles,
    required this.spawn,
    required this.portals,
    required this.portalHex,
    required this.dark,
    this.floor = Terrain.grass,
    this.enemies = const [],
    this.camps = const [],
    this.npcs = const [],
    this.items = const [],
    this.rockEvery = 0,
    this.rockCount = 0,
    this.nodeGates = const {},
    this.tier = 0,
    this.plateOrder = const [],
  }) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final h in tiles.keys) {
      final w = hexWorld(h);
      if (w.dx < minX) minX = w.dx;
      if (w.dx > maxX) maxX = w.dx;
      if (w.dy < minY) minY = w.dy;
      if (w.dy > maxY) maxY = w.dy;
    }
    bounds = Rect.fromLTRB(
      minX - BoardLayout.hexW / 2,
      minY - 14,
      maxX + BoardLayout.hexW / 2,
      maxY + 14,
    );
  }

  final String id;
  final String name;
  final Map<Hex, ZoneTile> tiles;
  final Hex spawn;
  final Map<String, Portal> portals;
  final Map<String, Hex> portalHex;

  /// Dark zones (caves) only light the hexes near the hero.
  final bool dark;

  /// What plain floor is made of: grass, or grey stone in a quarry.
  final Terrain floor;

  /// Creatures that live here.
  final List<EnemySpawn> enemies;

  /// Campsites: rest, save, upgrade.
  final List<Hex> camps;
  final List<NpcSpawn> npcs;
  final List<ItemSpawn> items;

  /// Falling rocks: every [rockEvery] turns, [rockCount] hexes are marked and
  /// a turn later rock lands on them. Zero means no rockfall.
  final int rockEvery;
  final int rockCount;

  /// Portals shut until enough dark nodes are broken. A generated zone's id
  /// changes, so its gates live in the zone itself (`gate` line).
  final Map<String, NodeGate> nodeGates;

  /// How tough the enemies here are (see `tiers.dart`). 0 is the base game.
  final int tier;

  /// The colours to step on, in order, to open the door. Empty means this
  /// zone has no puzzle door.
  final List<String> plateOrder;

  /// The door's hexes, and the plates by hex, as laid out in the file.
  late final List<Hex> doors = [
    for (final e in tiles.entries)
      if (e.value.door) e.key,
  ];
  late final Map<Hex, String> plates = {
    for (final e in tiles.entries)
      if (e.value.plate != null) e.key: e.value.plate!,
  };

  /// Stable id of the door, kept in saves once it has been opened.
  String get doorId => '$id#door';

  /// World-space bounds in art pixels.
  late final Rect bounds;

  /// The broken bridges as loaded: each is a connected run of broken tiles.
  late final List<Set<Hex>> bridges = _bridgeGroups();

  List<Set<Hex>> _bridgeGroups() {
    final left = {
      for (final e in tiles.entries)
        if (e.value.broken) e.key,
    };
    final out = <Set<Hex>>[];
    while (left.isNotEmpty) {
      final group = <Hex>{};
      final todo = [left.first];
      while (todo.isNotEmpty) {
        final h = todo.removeLast();
        if (!left.remove(h)) continue;
        group.add(h);
        todo.addAll(h.neighbors.where(left.contains));
      }
      out.add(group);
    }
    return out;
  }

  /// Stable id of a bridge (`zone#q,r` of its first tile), kept in saves.
  String bridgeId(Set<Hex> bridge) {
    final first = bridge.reduce(
      (a, b) => a.q < b.q || (a.q == b.q && a.r < b.r) ? a : b,
    );
    return '$id#${first.q},${first.r}';
  }

  /// Where the charges are as loaded.
  late final List<Hex> charges = [
    for (final e in tiles.entries)
      if (e.value.charge) e.key,
  ];

  /// Stable id of a charge (`zone#q,r`), kept in saves once it has gone off.
  String chargeId(Hex h) => '$id#${h.q},${h.r}';

  Portal? portalAt(Hex h) {
    final id = tiles[h]?.portal;
    return id == null ? null : portals[id];
  }

  static Zone parse(String text) {
    String id = '', name = '';
    var dark = false;
    var floor = Terrain.grass;
    final portals = <String, Portal>{};
    final tiles = <Hex, ZoneTile>{};
    final portalHex = <String, Hex>{};
    final enemies = <EnemySpawn>[];
    final camps = <Hex>[];
    final npcs = <NpcSpawn>[];
    final items = <ItemSpawn>[];
    var rockEvery = 0, rockCount = 0, tier = 0;
    var plateOrder = <String>[];
    final plateAt = <(String, int, int)>[];
    final nodeGates = <String, NodeGate>{};
    Hex? spawn;
    var inMap = false;
    var row = 0;
    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      if (inMap) {
        for (var c = 0; c < line.length; c++) {
          final ch = line[c];
          if (ch == ' ') continue;
          // "odd-r" offset rows to axial.
          final h = Hex(c - (row - (row & 1)) ~/ 2, row);
          if (ch == '@') spawn = h;
          final portal = RegExp(r'[1-9]').hasMatch(ch) ? ch : null;
          if (portal != null) portalHex[portal] = h;
          tiles[h] = switch (ch) {
            'f' => const ZoneTile(Terrain.forest),
            '~' => const ZoneTile(Terrain.water),
            'w' => const ZoneTile(Terrain.water, ford: true),
            'b' => const ZoneTile(Terrain.water, broken: true),
            '^' => const ZoneTile(Terrain.mountain),
            'X' => const ZoneTile(Terrain.mountain, rubble: true),
            'T' => ZoneTile(floor, charge: true),
            'L' => const ZoneTile(Terrain.lava),
            'c' => const ZoneTile(Terrain.crystal),
            'D' => ZoneTile(floor, door: true),
            _ => ZoneTile(floor, portal: portal),
          };
        }
        row++;
        continue;
      }
      final p = line.split(RegExp(r'\s+'));
      switch (p.first) {
        case 'zone':
          id = p[1];
        case 'name':
          name = line.substring(5);
        case 'dark':
          dark = p[1] == '1';
        case 'floor':
          floor = Terrain.values.byName(p[1]);
        case 'portal':
          portals[p[1]] = Portal(
            p[1],
            p[2],
            p[3],
            p.length > 4 ? p[4] : 'cave',
          );
        case 'enemy':
          // enemy <type> <col> <row> <behavior> [col,row ...]
          final type = UnitType.values.byName(p[1]);
          Hex at(String c, String r) {
            final row = int.parse(r);
            return Hex(int.parse(c) - (row - (row & 1)) ~/ 2, row);
          }

          final start = at(p[2], p[3]);
          final route = [
            start,
            for (final w in p.skip(5)) at(w.split(',')[0], w.split(',')[1]),
          ];
          enemies.add(
            EnemySpawn(type, start, Behavior.values.byName(p[4]), route),
          );
        case 'camp':
          // camp <col> <row>
          camps.add(_hexAt(int.parse(p[1]), int.parse(p[2])));
        case 'npc':
          // npc <id> <Name_With_Underscores> <col> <row> <unit>
          npcs.add(
            NpcSpawn(
              p[1],
              p[2].replaceAll('_', ' '),
              _hexAt(int.parse(p[3]), int.parse(p[4])),
              UnitType.values.byName(p[5]),
            ),
          );
        case 'item':
          // item <uid> <col> <row> <itemId>
          items.add(
            ItemSpawn(p[1], _hexAt(int.parse(p[2]), int.parse(p[3])), p[4]),
          );
        case 'chest':
          // chest <uid> <col> <row> <itemId>
          items.add(
            ItemSpawn(
              p[1],
              _hexAt(int.parse(p[2]), int.parse(p[3])),
              p[4],
              chest: true,
            ),
          );
        case 'gate':
          // gate <portal> nodes <count> <Message_With_Underscores>
          nodeGates[p[1]] = NodeGate(
            int.parse(p[3]),
            p.skip(4).join(' ').replaceAll('_', ' '),
          );
        case 'sequence':
          // sequence <colour> <colour> ...
          plateOrder = p.skip(1).toList();
        case 'plate':
          // plate <colour> <col> <row>
          plateAt.add((p[1], int.parse(p[2]), int.parse(p[3])));
        case 'tier':
          tier = int.parse(p[1]);
        case 'rockfall':
          // rockfall <every> <count>
          rockEvery = int.parse(p[1]);
          rockCount = int.parse(p[2]);
        case 'map':
          inMap = true;
      }
    }
    for (final (colour, col, row) in plateAt) {
      final h = _hexAt(col, row);
      final base = tiles[h];
      if (base != null) tiles[h] = ZoneTile(base.terrain, plate: colour);
    }
    if (spawn == null && portalHex.isNotEmpty) spawn = portalHex.values.first;
    if (spawn == null) throw FormatException('Zone $id has no spawn or portal');
    return Zone(
      id: id,
      name: name,
      tiles: tiles,
      spawn: spawn,
      portals: portals,
      portalHex: portalHex,
      dark: dark,
      floor: floor,
      enemies: enemies,
      camps: camps,
      npcs: npcs,
      items: items,
      rockEvery: rockEvery,
      rockCount: rockCount,
      nodeGates: nodeGates,
      tier: tier,
      plateOrder: plateOrder,
    );
  }

  /// Axial hex for "odd-r" offset coordinates.
  static Hex _hexAt(int col, int row) => Hex(col - (row - (row & 1)) ~/ 2, row);

  /// A copy with its own tile map, so a play session can burn forests down
  /// without touching the loaded zone.
  Zone copy() => Zone(
    id: id,
    name: name,
    tiles: Map.of(tiles),
    spawn: spawn,
    portals: portals,
    portalHex: portalHex,
    dark: dark,
    floor: floor,
    enemies: enemies,
    camps: camps,
    npcs: npcs,
    items: items,
    rockEvery: rockEvery,
    rockCount: rockCount,
    nodeGates: nodeGates,
    tier: tier,
    plateOrder: plateOrder,
  );
}

/// Loads and caches zones from the asset bundle.
class ZoneRepo {
  static final Map<String, Zone> _cache = {};

  /// Forgets loaded zones, so the next load re-reads the files.
  static void clear() => _cache.clear();

  /// Every zone that ships with the game.
  static const ids = [
    'training',
    'meadow',
    'mine',
    'cave',
    'quarry1',
    'quarry2',
    'quarry3',
    'sixways',
  ];

  static int _regionSeed = 1;

  /// Decides the layout of the generated rooms ([outerRooms]). Setting a new
  /// seed drops the old maps, so the next load builds the new ones.
  static int get regionSeed => _regionSeed;
  static set regionSeed(int seed) {
    if (seed == _regionSeed) return;
    _regionSeed = seed;
    outerRooms.forEach(_cache.remove);
  }

  /// Loads every zone, so quest markers can look across zones.
  static Future<Map<String, Zone>> loadAll([AssetBundle? bundle]) async {
    for (final id in [...ids, ...outerRooms]) {
      await load(id, bundle);
    }
    return Map.of(_cache);
  }

  static Future<Zone> load(String id, [AssetBundle? bundle]) async {
    final cached = _cache[id];
    if (cached != null) return cached;
    if (outerRooms.contains(id)) {
      final z = Zone.parse(outerRoom(id, _regionSeed));
      if (z.plateOrder.length == 3) {
        generatedLore['scroll_gate'] = gateLore(z.plateOrder);
      }
      return _cache[id] = z;
    }
    final text = await (bundle ?? rootBundle).loadString(
      'assets/zones/$id.txt',
    );
    return _cache[id] = Zone.parse(text);
  }
}
