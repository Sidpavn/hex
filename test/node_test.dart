import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hex/game/models.dart';
import 'package:hex/world/boss.dart';
import 'package:hex/world/gen_zone.dart';
import 'package:hex/world/pathfinding.dart';
import 'package:hex/world/quests.dart';
import 'package:hex/world/sim.dart';
import 'package:hex/world/world_state.dart';
import 'package:hex/world/zone.dart';

Zone room(String id, int seed) => Zone.parse(outerRoom(id, seed));

/// [z] with its puzzle door opened, for tests that only care about layout.
Zone opened(Zone z) {
  final c = z.copy();
  for (final h in z.doors) {
    c.tiles[h] = ZoneTile(z.floor);
  }
  return c;
}

Map<String, Zone> region(int seed) => {
  for (final id in outerRooms) id: room(id, seed),
};

void main() {
  test('the same seed gives the same rooms', () {
    for (final id in outerRooms) {
      expect(outerRoom(id, 7), outerRoom(id, 7));
      expect(outerRoom(id, 7), isNot(outerRoom(id, 8)));
    }
  });

  test('every seed gives rooms you can cross, joined end to end', () {
    for (var seed = 1; seed <= 500; seed++) {
      final zones = region(seed);
      final reason = 'seed $seed';
      for (final z in zones.values) {
        final entry = z.portalHex['1']!;
        final exit = z.portalHex['2']!;
        expect(
          findPath(opened(z), z.spawn, exit),
          isNotNull,
          reason: '$reason ${z.id}',
        );
        expect(entry.distanceTo(exit), greaterThan(10), reason: reason);
        for (final e in z.enemies) {
          expect(z.tiles[e.hex]!.walkable, isTrue, reason: '$reason ${z.id}');
          if (e.type != UnitType.node) {
            expect(
              e.hex.distanceTo(z.spawn),
              greaterThanOrEqualTo(6),
              reason: '$reason ${z.id}',
            );
          }
        }
        expect(z.camps, hasLength(1), reason: '$reason ${z.id}');
        expect(
          z.camps.single.distanceTo(z.spawn),
          lessThanOrEqualTo(5),
          reason: '$reason ${z.id}',
        );
      }

      // Each door leads to the room the chain says, and back again.
      expect(zones['outer_a']!.portals['1']!.toZone, 'quarry3');
      expect(zones['outer_a']!.portals['2']!.toZone, 'outer_b');
      expect(zones['outer_b']!.portals['2']!.toZone, 'outer_c');
      expect(zones['outer_c']!.portals['2']!.toZone, 'sixways');

      // One node, in the last room only, well away from both doors, and you
      // can walk up to it without crossing it.
      expect(
        zones.values
            .expand((z) => z.enemies)
            .where((e) => e.type == UnitType.node),
        hasLength(1),
        reason: reason,
      );
      final c = zones['outer_c']!;
      final node = c.enemies.singleWhere((e) => e.type == UnitType.node);
      expect(node.hex.distanceTo(c.portalHex['1']!), greaterThanOrEqualTo(8));
      expect(node.hex.distanceTo(c.portalHex['2']!), greaterThanOrEqualTo(8));
      expect(
        node.hex.neighbors.any((n) => findPath(c, c.spawn, n) != null),
        isTrue,
        reason: reason,
      );

      // The hermit waits in the first room, beside the camp, off the path.
      final a = zones['outer_a']!;
      expect(a.npcs.map((n) => n.id), ['hermit'], reason: reason);
      expect(a.enemies, isEmpty, reason: reason);
      expect(findPath(a, a.spawn, a.npcs.single.hex), isNotNull);
    }
  });

  test('a node is a boss that teaches nothing and never moves', () {
    expect(bossKits[UnitType.node]!.spell, isNull);
    final s = ZoneSim(
      room('outer_c', 3),
      world: WorldState(),
      rng: math.Random(1),
    );
    final node = s.enemies.singleWhere((e) => e.type == UnitType.node);
    expect(node.maxHp, bossKits[UnitType.node]!.hp);
    final home = node.hex;
    for (var i = 0; i < 12; i++) {
      s.wait();
    }
    expect(node.hex, home);
  });

  test('breaking the node counts, and opens the road', () {
    final z = room('outer_c', 3);
    final w = WorldState();
    final known = Set.of(w.knownSpells);
    expect(closedGate('outer_c', '2', w, z), isNotNull);
    expect(closedGate('outer_c', '1', w, z), isNull);

    final s = ZoneSim(z, world: w, rng: math.Random(1));
    final node = s.enemies.singleWhere((e) => e.type == UnitType.node);
    s.hero = node.hex.neighbors.firstWhere((h) => z.tiles[h]!.walkable);
    for (var i = 0; i < 20 && node.alive && !s.heroDown; i++) {
      s.attack(node);
    }
    expect(node.alive, isFalse);
    expect(w.knownSpells, known);
    expect(w.count(Counts.kill(UnitType.node)), 1);
    expect(closedGate('outer_c', '2', w, z), isNull);
  });

  test('the shut road stops you when you walk into it', () {
    final z = room('outer_c', 5);
    final door = z.portalHex['2']!;
    final from = door.neighbors.firstWhere(
      (h) => z.tiles[h]?.walkable ?? false,
    );
    final s = ZoneSim(z, world: WorldState(), heroAt: from);
    expect(s.moveHero(door), isFalse);
    expect(s.events.any((e) => e.kind == SimEventKind.gateClosed), isTrue);
  });

  group('the hermit', () {
    final hermit = room('outer_a', 1).npcs.single;

    test('tells you about the node and starts the quest', () {
      final w = WorldState()..learn('shield');
      expect(npcMark(hermit, w), 'alert');
      final d = talkTo(hermit, w);
      expect(d.choices.map((c) => c.text), ['I will break it', 'Not now']);
      d.choices.first.apply(w);
      expect(w.quests['node'], 1);
      expect(npcMark(hermit, w), isNull);
      expect(talkTo(hermit, w).choices, isEmpty);
    });

    test('points at the node, and the quest ends when it breaks', () {
      final w = WorldState()
        ..learn('shield')
        ..quests['node'] = 1;
      final zones = region(1);
      final goal = currentObjective(w)!;
      expect(goal.zone, 'outer_c');
      final c = zones['outer_c']!;
      expect(
        markerHex(c, goal, zones),
        c.enemies.singleWhere((e) => e.type == UnitType.node).hex,
      );
      // From the first room the marker points at the way on.
      final a = zones['outer_a']!;
      expect(markerHex(a, goal, zones), a.portalHex['2']);

      w.bump(Counts.kill(UnitType.node));
      expect(questById('node')!.isDone(w), isTrue);
      expect(talkTo(hermit, w).lines.first, contains('steadier'));
    });
  });

  test('the seed is saved, and older saves load without one', () {
    final w = WorldState()..regionSeed = 4242;
    final json = jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>;
    expect(WorldState.fromJson(json).regionSeed, 4242);
    json
      ..remove('regionSeed')
      ..['v'] = 4;
    expect(WorldState.fromJson(json).regionSeed, 0);
  });
}
