import 'package:flutter/services.dart';

import '../game/hex.dart';
import '../game/models.dart';

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
  const ItemSpawn(this.id, this.hex, this.itemId);

  final String id;
  final Hex hex;
  final String itemId;
}

class ZoneTile {
  const ZoneTile(this.terrain, {this.ford = false, this.portal});

  final Terrain terrain;

  /// Shallow water you can wade across (slow).
  final bool ford;

  /// Id of the portal on this tile, if any.
  final String? portal;

  bool get walkable =>
      ford ||
      (terrain != Terrain.water &&
          terrain != Terrain.lava &&
          terrain != Terrain.mountain);

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
    this.enemies = const [],
    this.camps = const [],
    this.npcs = const [],
    this.items = const [],
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

  /// Creatures that live here.
  final List<EnemySpawn> enemies;

  /// Campsites: rest, save, upgrade.
  final List<Hex> camps;
  final List<NpcSpawn> npcs;
  final List<ItemSpawn> items;

  /// World-space bounds in art pixels.
  late final Rect bounds;

  Portal? portalAt(Hex h) {
    final id = tiles[h]?.portal;
    return id == null ? null : portals[id];
  }

  static Zone parse(String text) {
    String id = '', name = '';
    var dark = false;
    final portals = <String, Portal>{};
    final tiles = <Hex, ZoneTile>{};
    final portalHex = <String, Hex>{};
    final enemies = <EnemySpawn>[];
    final camps = <Hex>[];
    final npcs = <NpcSpawn>[];
    final items = <ItemSpawn>[];
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
            '^' => const ZoneTile(Terrain.mountain),
            'L' => const ZoneTile(Terrain.lava),
            'c' => const ZoneTile(Terrain.crystal),
            _ => ZoneTile(Terrain.grass, portal: portal),
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
        case 'map':
          inMap = true;
      }
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
      enemies: enemies,
      camps: camps,
      npcs: npcs,
      items: items,
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
    enemies: enemies,
    camps: camps,
    npcs: npcs,
    items: items,
  );
}

/// Loads and caches zones from the asset bundle.
class ZoneRepo {
  static final Map<String, Zone> _cache = {};

  /// Forgets loaded zones, so the next load re-reads the files.
  static void clear() => _cache.clear();

  /// Every zone that ships with the game.
  static const ids = ['meadow', 'cave'];

  /// Loads every zone, so quest markers can look across zones.
  static Future<Map<String, Zone>> loadAll([AssetBundle? bundle]) async {
    for (final id in ids) {
      await load(id, bundle);
    }
    return Map.of(_cache);
  }

  static Future<Zone> load(String id, [AssetBundle? bundle]) async {
    final cached = _cache[id];
    if (cached != null) return cached;
    final text = await (bundle ?? rootBundle).loadString(
      'assets/zones/$id.txt',
    );
    return _cache[id] = Zone.parse(text);
  }
}
