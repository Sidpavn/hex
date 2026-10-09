import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hex/game/hex.dart';
import 'package:hex/game/models.dart';
import 'package:hex/world/pathfinding.dart';
import 'package:hex/world/sim.dart';
import 'package:hex/world/world_state.dart';
import 'package:hex/world/zone.dart';

Zone load(String id) =>
    Zone.parse(File('assets/zones/$id.txt').readAsStringSync());

ZoneSim sim(Zone z, WorldState w, {Hex? hero}) =>
    ZoneSim(z, world: w, heroAt: hero, rng: math.Random(3));

/// A walkable hex next to [tile].
Hex bankOf(ZoneSim s, Hex tile) =>
    tile.neighbors.firstWhere((h) => s.zone.tiles[h]?.walkable ?? false);

void main() {
  final meadow = load('meadow');

  bool reaches(WorldState w, String portal) {
    final s = sim(meadow, w);
    return findPath(s.zone, s.hero, meadow.portalHex[portal]!) != null;
  }

  group('the meadow river', () {
    test('has one broken bridge', () {
      expect(meadow.bridges, hasLength(1));
    });

    test('the old mine is on your side, the cave is not', () {
      final w = WorldState();
      expect(reaches(w, '3'), isTrue);
      expect(reaches(w, '1'), isFalse);
    });

    test('mending the bridge opens the way to the cave', () {
      final w = WorldState()..repaired.add(meadow.bridgeId(meadow.bridges[0]));
      expect(reaches(w, '1'), isTrue);
    });

    test('the left side has only knights, the right has both', () {
      Set<UnitType> kinds(bool Function(Hex) side) => {
        for (final e in meadow.enemies)
          if (side(e.hex)) e.type,
      };
      // The river runs down the middle; col = q + r/2 for odd-r rows.
      bool left(Hex h) => h.q + (h.r - (h.r & 1)) ~/ 2 < 13;
      bool right(Hex h) => h.q + (h.r - (h.r & 1)) ~/ 2 > 22;
      expect(kinds(left), {UnitType.knight});
      expect(kinds(right), {UnitType.knight, UnitType.archer});
      expect(
        meadow.enemies.map((e) => e.type),
        isNot(anyOf(contains(UnitType.golem), contains(UnitType.cavalry))),
      );
    });
  });

  group('the old mine', () {
    final mine = load('mine');

    test('the hatchet can be reached from the entrance', () {
      final hatchet = mine.items.firstWhere((i) => i.itemId == 'hatchet');
      expect(findPath(mine, mine.spawn, hatchet.hex), isNotNull);
    });

    test('it is dark and links back to the meadow', () {
      expect(mine.dark, isTrue);
      expect(mine.portals['1']!.toZone, 'meadow');
      expect(meadow.portals['3']!.toZone, 'mine');
    });
  });

  group('chopping', () {
    Hex? treeBeside(ZoneSim s) {
      for (final e in s.zone.tiles.entries) {
        if (e.value.terrain != Terrain.forest) continue;
        final bank = e.key.neighbors.where(
          (h) => s.zone.tiles[h]?.terrain == Terrain.grass,
        );
        if (bank.isNotEmpty) return e.key;
      }
      return null;
    }

    (ZoneSim, Hex) beside(WorldState w) {
      final probe = sim(meadow, w);
      final tree = treeBeside(probe)!;
      final stand = tree.neighbors.firstWhere(
        (h) => probe.zone.tiles[h]?.terrain == Terrain.grass,
      );
      return (sim(meadow, w, hero: stand), tree);
    }

    test('needs the hatchet', () {
      final w = WorldState();
      final (s, tree) = beside(w);
      expect(s.treeNear(), isNull);
      expect(s.chop(tree), isFalse);
      expect(w.hasItem('wood'), isFalse);
    });

    test('gives one wood by default and leaves grass', () {
      final w = WorldState()..addItem('hatchet');
      final (s, tree) = beside(w);
      expect(s.treeNear(), isNotNull);
      expect(s.chop(tree), isTrue);
      expect(w.countOf('wood'), 1);
      expect(s.zone.tiles[tree]!.terrain, Terrain.grass);
      expect(
        s.events.where((e) => e.kind == SimEventKind.chopped),
        hasLength(1),
      );
    });

    test('each hit from the timing game is one wood', () {
      final got = <int>[];
      for (final hits in [0, 1, 2, 3]) {
        final w = WorldState()..addItem('hatchet');
        final (s, tree) = beside(w);
        s.chop(tree, hits: hits);
        got.add(w.countOf('wood'));
      }
      expect(got, [0, 1, 2, 3]);
    });

    test('no hits leaves the tree standing', () {
      final w = WorldState()..addItem('hatchet');
      final (s, tree) = beside(w);
      expect(s.chop(tree, hits: 0), isTrue);
      expect(s.zone.tiles[tree]!.terrain, Terrain.forest);
      expect(w.chopped, isEmpty);
      expect(s.treeNear(), isNotNull);
    });

    test('a felled tree stays felled, even after a rest', () {
      final w = WorldState()..addItem('hatchet');
      final (s, tree) = beside(w);
      s.chop(tree);
      s.rest(s.hero);
      expect(s.zone.tiles[tree]!.terrain, Terrain.grass);
      expect(sim(meadow, w).zone.tiles[tree]!.terrain, Terrain.grass);
    });

    test('a full bag stops you', () {
      final w = WorldState()..addItem('hatchet');
      for (var i = 0; i < w.bag.length; i++) {
        w.bag[i] ??= ItemStack('lantern', 1);
      }
      final (s, tree) = beside(w);
      expect(s.chop(tree), isFalse);
      expect(s.zone.tiles[tree]!.terrain, Terrain.forest);
      expect(s.events.any((e) => e.kind == SimEventKind.bagFull), isTrue);
    });

    test('wood stacks to ten, so eleven takes two slots', () {
      final w = WorldState();
      final before = w.bag.where((s) => s != null).length;
      w.addItem('wood', 11);
      expect(w.bag.where((s) => s != null).length, before + 2);
      expect(w.countOf('wood'), 11);
    });

    test('tools cannot be dropped', () {
      final w = WorldState()..addItem('hatchet');
      final i = w.bag.indexWhere((s) => s?.id == 'hatchet');
      expect(w.drop(i), isFalse);
      expect(w.hasItem('hatchet'), isTrue);
    });
  });

  group('repairing', () {
    (ZoneSim, Set<Hex>) atBridge(WorldState w, int which) {
      final bridge = meadow.bridges.toList()[which];
      final probe = sim(meadow, w);
      final stand = bankOf(probe, bridge.first);
      return (sim(meadow, w, hero: stand), bridge);
    }

    test('takes thirty wood and turns the planks into a ford', () {
      final w = WorldState()..addItem('wood', 30);
      final (s, bridge) = atBridge(w, 0);
      expect(s.bridgeNear(), isNotNull);
      expect(s.repair(), isTrue);
      expect(w.hasItem('wood'), isFalse);
      for (final h in bridge) {
        expect(s.zone.tiles[h]!.ford, isTrue);
        expect(s.zone.tiles[h]!.walkable, isTrue);
      }
      expect(w.repaired, contains(meadow.bridgeId(bridge)));
    });

    test('twenty-nine wood is not enough', () {
      final w = WorldState()..addItem('wood', 29);
      final (s, bridge) = atBridge(w, 0);
      expect(s.repair(), isFalse);
      expect(w.countOf('wood'), 29);
      expect(s.zone.tiles[bridge.first]!.walkable, isFalse);
    });

    test('a mended bridge stays mended', () {
      final w = WorldState()..addItem('wood', 30);
      final (s, bridge) = atBridge(w, 0);
      s.repair();
      s.rest(s.hero);
      expect(s.zone.tiles[bridge.first]!.walkable, isTrue);
      expect(sim(meadow, w).zone.tiles[bridge.first]!.walkable, isTrue);
    });

    test('nothing to mend away from a bridge', () {
      final w = WorldState()..addItem('wood', 30);
      final s = sim(meadow, w);
      expect(s.bridgeNear(), isNull);
      expect(s.repair(), isFalse);
    });

    test('mended bridges and felled trees survive a save', () {
      final w = WorldState()
        ..repaired.add('meadow#14,17')
        ..chopped.add('meadow#3,4');
      final back = WorldState.fromJson(w.toJson());
      expect(back.repaired, w.repaired);
      expect(back.chopped, w.chopped);
    });
  });

  test('after mending, the hero can walk across the bridge', () {
    final bridge = meadow.bridges.first;
    final w = WorldState()..addItem('wood', 30);
    final probe = sim(meadow, w);
    final stand = bankOf(probe, bridge.first);
    final s = sim(meadow, w, hero: stand);
    s.repair();
    // Every hex of the bridge can be stepped onto, one after another.
    final far = bridge.map((h) => h).toList();
    final goal = far
        .expand((h) => h.neighbors)
        .firstWhere(
          (h) =>
              !bridge.contains(h) &&
              h != stand &&
              (s.zone.tiles[h]?.walkable ?? false) &&
              findPath(s.zone, stand, h) != null,
        );
    final path = findPath(s.zone, stand, goal)!;
    for (final h in path) {
      expect(s.moveHero(h), isTrue, reason: 'stepping onto $h');
    }
    expect(s.hero, goal);
  });
}
