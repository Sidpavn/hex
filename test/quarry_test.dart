import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hex/game/hex.dart';
import 'package:hex/game/models.dart';
import 'package:hex/world/items.dart';
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

  test('the longbow sits in a chest on the terrace, guarded by golems', () {
    final z = zones['quarry2']!;
    final chest = z.items.singleWhere((i) => i.chest);
    expect(chest.itemId, 'longbow');
    final guards = z.enemies.where((e) => e.hex.distanceTo(chest.hex) <= 4);
    expect(guards.length, greaterThanOrEqualTo(2));
    for (final id in zones.keys) {
      for (final i in zones[id]!.items) {
        if (id == 'training') continue;
        expect(
          itemOf(i.itemId).isWeapon,
          i.chest,
          reason: '$id ${i.id}: only chests hold weapons outside training',
        );
      }
    }
  });

  test('stepping on the chest shows it; taking it adds the weapon once', () {
    final z = zones['quarry2']!;
    final chest = z.items.singleWhere((i) => i.chest);
    final from = chest.hex.neighbors.firstWhere(
      (h) => z.tiles[h]?.walkable ?? false,
    );
    final w = WorldState();
    final s = ZoneSim(z, world: w, heroAt: from);
    s.enemies.clear();
    expect(s.moveHero(chest.hex), isTrue);
    expect(s.events.any((e) => e.kind == SimEventKind.chestOpened), isTrue);
    expect(w.countOf('longbow'), 0);
    expect(s.takeChest(), isTrue);
    expect(w.countOf('longbow'), 1);
    expect(s.takeChest(), isFalse);
    expect(s.itemAt(chest.hex), isNull);
  });

  test('a full bag leaves the chest closed', () {
    final z = zones['quarry2']!;
    final chest = z.items.singleWhere((i) => i.chest);
    final w = WorldState();
    while (w.canAdd('axe')) {
      w.addItem('axe');
    }
    final s = ZoneSim(z, world: w, heroAt: chest.hex);
    expect(s.takeChest(), isFalse);
    expect(s.itemAt(chest.hex), isNotNull);
  });

  test('rock is marked one turn, then lands and hurts what is under it', () {
    final z = zones['quarry2']!;
    expect(z.rockEvery, greaterThan(0));
    final s = ZoneSim(z, world: WorldState(), heroAt: z.spawn);
    s.enemies.clear();
    while (s.rockWarn.isEmpty) {
      s.wait();
    }
    final marked = s.rockWarn.toSet();
    expect(marked, hasLength(z.rockCount));
    // Stand on a marked hex and the rock finds the hero.
    s.events.clear();
    final before = s.heroHp;
    s.hero = marked.first;
    s.wait();
    expect(s.events.where((e) => e.kind == SimEventKind.rockLand), isNotEmpty);
    expect(s.heroHp, before - ZoneSim.rockDamage);
  });

  test('stepping off a marked hex dodges the rock', () {
    final z = zones['quarry2']!;
    final s = ZoneSim(z, world: WorldState(), heroAt: z.spawn);
    s.enemies.clear();
    while (s.rockWarn.isEmpty) {
      s.wait();
    }
    final marked = s.rockWarn.toSet();
    final spot = marked.first;
    s.hero = spot;
    final out = spot.neighbors.firstWhere(
      (h) => (s.zone.tiles[h]?.walkable ?? false) && !marked.contains(h),
    );
    final before = s.heroHp;
    expect(s.moveHero(out), isTrue);
    expect(s.heroHp, before);
  });

  test('the lift joins the floor and the rim but has no power yet', () {
    final low = zones['quarry1']!;
    final high = zones['quarry3']!;
    expect(low.portals['3']!.toZone, 'quarry3');
    expect(high.portals['3']!.toZone, 'quarry1');
    final w = WorldState();
    expect(closedGate('quarry1', '3', w), isNotNull);
    expect(closedGate('quarry3', '3', w), isNotNull);
  });

  test('the cave no longer holds weapons', () {
    for (final i in zones['cave']!.items) {
      expect(itemOf(i.itemId).isWeapon, isFalse, reason: i.id);
    }
  });
}
