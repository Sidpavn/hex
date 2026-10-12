import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hex/game/hex.dart';
import 'package:hex/game/models.dart';
import 'package:hex/world/pathfinding.dart';
import 'package:hex/world/quests.dart';
import 'package:hex/world/sim.dart';
import 'package:hex/world/world_state.dart';
import 'package:hex/world/zone.dart';

void main() {
  final zones = {
    for (final id in ZoneRepo.ids)
      id: Zone.parse(File('assets/zones/$id.txt').readAsStringSync()),
  };
  final quarry = ['quarry1', 'quarry2', 'quarry3'];

  test('every portal leads somewhere and the way back leads here', () {
    for (final z in zones.values) {
      for (final p in z.portals.values) {
        final to = zones[p.toZone];
        expect(to, isNotNull, reason: '${z.id}#${p.id} -> ${p.toZone}');
        final back = to!.portals[p.toPortal];
        expect(back, isNotNull, reason: '${p.toZone}#${p.toPortal}');
        expect(back!.toZone, z.id, reason: '${z.id}#${p.id} returns');
        expect(back.toPortal, p.id, reason: '${z.id}#${p.id} returns');
        expect(z.portalHex[p.id], isNotNull, reason: '${z.id}#${p.id} tile');
      }
    }
  });

  test('each level is open ground with only golems, the last has the boss', () {
    for (final id in quarry) {
      final z = zones[id]!;
      expect(z.dark, isFalse, reason: id);
      for (final e in z.enemies) {
        if (id == 'quarry3' && e.type == UnitType.warlord) continue;
        expect(e.type, UnitType.golem, reason: id);
      }
    }
    final top = zones['quarry3']!;
    expect(top.enemies.map((e) => e.type), [UnitType.warlord]);
    expect(
      quarry
          .expand((id) => zones[id]!.enemies)
          .where((e) => e.type == UnitType.warlord),
      hasLength(1),
    );
  });

  test('from each arrival you can reach the ladder up and a camp', () {
    for (final id in quarry) {
      final z = zones[id]!;
      expect(z.camps, isNotEmpty, reason: id);
      for (final c in z.camps) {
        expect(findPath(z, z.spawn, c), isNotNull, reason: '$id camp');
      }
      for (final p in z.portalHex.entries) {
        expect(
          findPath(z, z.spawn, p.value),
          isNotNull,
          reason: '$id#${p.key}',
        );
      }
      for (final i in z.items) {
        expect(findPath(z, z.spawn, i.hex), isNotNull, reason: '$id ${i.id}');
      }
      for (final e in z.enemies) {
        expect(findPath(z, z.spawn, e.hex), isNotNull, reason: '$id enemy');
      }
    }
  });

  test('the Warlord stands well away from both doors', () {
    final z = zones['quarry3']!;
    final boss = z.enemies.single.hex;
    for (final h in z.portalHex.values) {
      expect(boss.distanceTo(h), greaterThanOrEqualTo(8));
    }
  });

  test('the cave leads to the quarry only through the blasted rockfall', () {
    final cave = zones['cave']!;
    final door = cave.portalHex['2']!;
    expect(findPath(cave, cave.spawn, door), isNull);
    final w = WorldState();
    final s = ZoneSim(cave, world: w);
    final c = cave.charges.first;
    s.hero = Hex(c.q - 3, c.r);
    expect(s.castFireball(c), isTrue);
    expect(findPath(s.zone, s.hero, door), isNotNull);
  });

  test('the gate past the Warlord opens once Shield is learned', () {
    final w = WorldState();
    expect(closedGate('quarry3', '2', w), isNotNull);
    w.learn('shield');
    expect(closedGate('quarry3', '2', w), isNull);
  });

  test('walking into the shut gate says so and does not move you', () {
    final z = zones['quarry3']!;
    final gate = z.portalHex['2']!;
    final from = gate.neighbors.firstWhere(
      (h) => z.tiles[h]?.walkable ?? false,
    );
    final s = ZoneSim(z, world: WorldState(), heroAt: from);
    expect(s.moveHero(gate), isFalse);
    expect(s.events.any((e) => e.kind == SimEventKind.gateClosed), isTrue);
    expect(s.hero, from);
  });

  test('the quarry floor is grey stone, the cave and meadow stay grass', () {
    for (final id in quarry) {
      final z = zones[id]!;
      expect(z.floor, Terrain.stone, reason: id);
      for (final h in z.portalHex.values) {
        expect(z.tiles[h]!.terrain, Terrain.stone, reason: '$id portal');
      }
      expect(z.tiles[z.spawn]!.terrain, Terrain.stone, reason: '$id spawn');
    }
    expect(zones['cave']!.floor, Terrain.grass);
    expect(zones['meadow']!.floor, Terrain.grass);
  });

  test('stone does not burn, and a blasted rockfall leaves the zone floor', () {
    final z = Zone.parse(
      [
        'zone t',
        'name Test',
        'dark 0',
        'floor stone',
        'map',
        '^^^^^^^^^^^^^^',
        '^@.....TXX...^',
        '^^^^^^^^^^^^^^',
      ].join('\n'),
    );
    final s = ZoneSim(z, world: WorldState(), heroAt: Hex(1, 1));
    final target = z.charges.single;
    s.hero = Hex(target.q - 3, target.r);
    expect(s.castFireball(target), isTrue);
    expect(s.fire, isEmpty);
    for (final h in [target, Hex(target.q + 1, target.r)]) {
      expect(s.zone.tiles[h]!.terrain, Terrain.stone);
      expect(s.zone.tiles[h]!.walkable, isTrue);
    }
  });
}
