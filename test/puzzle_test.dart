import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hex/game/hex.dart';
import 'package:hex/game/models.dart';
import 'package:hex/world/gen_zone.dart';
import 'package:hex/world/lore.dart';
import 'package:hex/world/pathfinding.dart';
import 'package:hex/world/sim.dart';
import 'package:hex/world/world_state.dart';
import 'package:hex/world/zone.dart';

Zone road(int seed) => Zone.parse(outerRoom('outer_b', seed));

/// Steps onto [plate] from a free neighbour, as a player would.
bool step(ZoneSim s, Hex plate) {
  s.hero = plate.neighbors.firstWhere(
    (h) =>
        (s.zone.tiles[h]?.walkable ?? false) &&
        s.zone.tiles[h]!.plate == null &&
        s.enemyAt(h) == null,
  );
  return s.moveHero(plate);
}

Hex plateOf(Zone z, String colour) =>
    z.plates.entries.firstWhere((e) => e.value == colour).key;

void main() {
  test('the road has a door, four plates and an order of three', () {
    for (var seed = 1; seed <= 300; seed++) {
      final z = road(seed);
      final reason = 'seed $seed';
      expect(z.doors, hasLength(1), reason: reason);
      expect(z.plates.length, 4, reason: reason);
      expect(z.plates.values.toSet().length, 4, reason: reason);
      expect(z.plateOrder.length, 3, reason: reason);
      expect(z.plateOrder.toSet().length, 3, reason: reason);
      expect(z.plateOrder.every(z.plates.containsValue), isTrue);
      // The plates are off the way to the door, so you never step on one by
      // accident, and they are in the first room.
      for (final p in z.plates.keys) {
        expect(findPath(z, z.spawn, p), isNotNull, reason: reason);
        expect(p.distanceTo(z.spawn), lessThan(14), reason: reason);
      }
    }
  });

  test('the door really blocks the road, and the maze does not need it', () {
    for (var seed = 1; seed <= 300; seed++) {
      final z = road(seed);
      final reason = 'seed $seed';
      final exit = z.portalHex['2']!;
      expect(findPath(z, z.spawn, exit), isNull, reason: reason);
      final scroll = z.items.singleWhere((i) => i.itemId == 'scroll_gate');
      expect(findPath(z, z.spawn, scroll.hex), isNotNull, reason: reason);
    }
  });

  test('the maze is long, winding and guarded all the way in', () {
    for (var seed = 1; seed <= 300; seed++) {
      final z = road(seed);
      final reason = 'seed $seed';
      final scroll = z.items.singleWhere((i) => i.itemId == 'scroll_gate');
      final way = findPath(z, z.spawn, scroll.hex)!;
      expect(way.length, greaterThan(24), reason: reason);
      // The maze is a tree, so its one way in passes these guards.
      final onWay = z.enemies.where((e) => way.contains(e.hex)).toList();
      expect(
        onWay.where((e) => e.type == UnitType.knight),
        hasLength(greaterThanOrEqualTo(2)),
        reason: reason,
      );
      expect(onWay.any((e) => e.type == UnitType.archer), isTrue);
    }
  });

  test('the outline is not a rectangle', () {
    for (final id in outerRooms) {
      final z = Zone.parse(outerRoom(id, 5));
      final rows = {for (final h in z.tiles.keys) h.r};
      final cols = {for (final h in z.tiles.keys) h.q + (h.r - (h.r & 1)) ~/ 2};
      final box = rows.length * cols.length;
      // Plenty of the bounding box is empty void.
      expect(z.tiles.length, lessThan(box * 0.7), reason: id);
    }
  });

  group('pressing the plates', () {
    ZoneSim fresh(WorldState w, [int seed = 4]) =>
        ZoneSim(road(seed), world: w, rng: math.Random(1))..enemies.clear();

    test('in order opens the gate, and it stays open', () {
      final w = WorldState();
      final s = fresh(w);
      final z = s.source;
      final door = z.doors.single;
      expect(s.zone.tiles[door]!.walkable, isFalse);
      for (final colour in z.plateOrder.take(2)) {
        expect(step(s, plateOf(z, colour)), isTrue);
        expect(s.events.last.kind, SimEventKind.plateDown);
      }
      expect(s.zone.tiles[door]!.walkable, isFalse);
      step(s, plateOf(z, z.plateOrder.last));
      expect(s.events.any((e) => e.kind == SimEventKind.doorOpened), isTrue);
      expect(s.zone.tiles[door]!.walkable, isTrue);
      expect(w.opened, contains(z.doorId));
      // Later visits, and a rest, find it open.
      expect(ZoneSim(z, world: w).zone.tiles[door]!.walkable, isTrue);
      s.rest(z.spawn);
      expect(s.zone.tiles[door]!.walkable, isTrue);
    });

    test('a press says nothing about whether it was right', () {
      // The first plate pressed gives the same answer, right or wrong.
      SimEventKind firstPress(bool right) {
        final s = fresh(WorldState());
        final z = s.source;
        final plate = right
            ? plateOf(z, z.plateOrder.first)
            : z.plates.entries
                  .firstWhere((e) => e.value != z.plateOrder.first)
                  .key;
        step(s, plate);
        return s.events.last.kind;
      }

      expect(firstPress(true), SimEventKind.plateDown);
      expect(firstPress(false), SimEventKind.plateDown);
    });

    test('only a full wrong order stings, and springs every plate back', () {
      final w = WorldState();
      final s = fresh(w);
      final z = s.source;
      final wrong = [
        for (final c in z.plateOrder.reversed) plateOf(z, c),
      ]; // the right plates, the wrong way round
      final hp = w.hp;
      step(s, wrong[0]);
      step(s, wrong[1]);
      expect(w.hp, hp);
      expect(s.pressed, hasLength(2));
      expect(s.events.any((e) => e.kind == SimEventKind.plateReset), isFalse);
      step(s, wrong[2]);
      expect(s.events.any((e) => e.kind == SimEventKind.plateReset), isTrue);
      expect(s.pressed, isEmpty);
      expect(w.hp, hp - 1);
      expect(w.opened, isEmpty);
      // You can still do it properly afterwards.
      for (final colour in z.plateOrder) {
        step(s, plateOf(z, colour));
      }
      expect(w.opened, contains(z.doorId));
    });

    test('the decoy plate spoils an attempt like any other wrong plate', () {
      final w = WorldState();
      final s = fresh(w);
      final z = s.source;
      final decoy = z.plates.entries
          .firstWhere((e) => !z.plateOrder.contains(e.value))
          .key;
      step(s, decoy);
      step(s, plateOf(z, z.plateOrder[0]));
      step(s, plateOf(z, z.plateOrder[1]));
      expect(w.opened, isEmpty);
      expect(s.pressed, isEmpty);
    });

    test('a shield soaks the sting', () {
      final w = WorldState()
        ..shield = 3
        ..shieldTurns = 5;
      final s = fresh(w);
      final z = s.source;
      final hp = w.hp;
      for (final c in z.plateOrder.reversed) {
        step(s, plateOf(z, c));
      }
      expect(w.hp, hp);
      expect(s.pressed, isEmpty);
    });

    test('a plate that is already down does nothing', () {
      final w = WorldState();
      final s = fresh(w);
      final z = s.source;
      final first = plateOf(z, z.plateOrder.first);
      step(s, first);
      final hp = w.hp;
      step(s, first);
      expect(s.pressed, [first]);
      expect(w.hp, hp);
    });
  });

  test('the note tells the order, in the order it opens', () {
    for (var seed = 1; seed <= 50; seed++) {
      final z = road(seed);
      final text = gateLore(z.plateOrder).lines.join(' ');
      const phrase = {
        'red': 'embers',
        'blue': 'deep water',
        'yellow': 'old gold',
        'green': 'moss',
      };
      final at = [for (final c in z.plateOrder) text.indexOf(phrase[c]!)];
      expect(at.every((i) => i >= 0), isTrue);
      expect(at, [...at]..sort());
    }
    // Until a zone has been built, the journal shows the fixed text.
    expect(loreDefs['scroll_gate'], isNotNull);
  });

  test('an opened door survives a save, and old saves load', () {
    final w = WorldState()..opened.add('outer_b#door');
    final json = jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>;
    expect(WorldState.fromJson(json).opened, {'outer_b#door'});
    json
      ..remove('opened')
      ..['v'] = 5;
    expect(WorldState.fromJson(json).opened, isEmpty);
  });
}
