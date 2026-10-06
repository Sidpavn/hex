import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hex/game/hex.dart';
import 'package:hex/game/models.dart';
import 'package:hex/world/sim.dart';
import 'package:hex/world/world_state.dart';
import 'package:hex/world/zone.dart';

/// Builds a zone from ASCII rows (odd-r layout, see design/gen_zones.py).
Zone zoneOf(List<String> rows, {List<String> enemies = const []}) => Zone.parse(
  [
    'zone t',
    'name Test',
    'dark 0',
    ...enemies.map((e) => 'enemy $e'),
    'map',
    // The player spawns in the top-left corner unless the map says otherwise.
    if (rows.any((r) => r.contains('@')))
      ...rows
    else ...[
      '@${rows.first.substring(1)}',
      ...rows.skip(1),
    ],
  ].join('\n'),
);

String open(int w, int h) => '.' * w;

Hex at(int col, int row) => Hex(col - (row - (row & 1)) ~/ 2, row);

void main() {
  final grass = List.generate(7, (_) => open(20, 7));

  ZoneSim sim(Zone z, {Hex? hero, int? hp, WorldState? world}) {
    final w = world ?? WorldState();
    if (hp != null) w.hp = hp;
    return ZoneSim(z, world: w, heroAt: hero, rng: math.Random(1));
  }

  test('a far-away enemy does not notice the hero', () {
    final z = zoneOf(grass, enemies: ['knight 15 3 guard']);
    final s = sim(z, hero: at(2, 3));
    s.wait();
    expect(s.enemies.single.awareness, Awareness.idle);
  });

  test('an enemy that can see the hero becomes alert and says so', () {
    final z = zoneOf(grass, enemies: ['knight 8 3 guard']);
    final s = sim(z, hero: at(4, 3));
    s.wait();
    expect(s.enemies.single.awareness, Awareness.alert);
    expect(s.events.any((e) => e.kind == SimEventKind.noticed), isTrue);
  });

  test('a mountain blocks line of sight', () {
    final rows = [...grass];
    // Wall of mountains between col 6 and 7 on every row.
    for (var r = 0; r < rows.length; r++) {
      rows[r] = '${rows[r].substring(0, 6)}^${rows[r].substring(7)}';
    }
    final z = zoneOf(rows, enemies: ['knight 9 3 guard']);
    final s = sim(z, hero: at(4, 3));
    s.wait();
    expect(s.enemies.single.awareness, Awareness.idle);
  });

  test('hiding in a forest shortens how far enemies can see', () {
    final rows = [...grass];
    // The hero at (4,3) stands in forest; the knight is 4 hexes away.
    rows[3] = '....f${rows[3].substring(5)}';
    final z = zoneOf(rows, enemies: ['knight 8 3 guard']);
    expect(at(4, 3).distanceTo(at(8, 3)), 4);
    final hidden = sim(z, hero: at(4, 3));
    hidden.wait();
    expect(hidden.enemies.single.awareness, Awareness.idle);

    // The same distance on open grass is spotted.
    final z2 = zoneOf(grass, enemies: ['knight 8 3 guard']);
    final seen = sim(z2, hero: at(4, 3));
    seen.wait();
    expect(seen.enemies.single.awareness, Awareness.alert);
  });

  test('sleepers only wake when you get very close', () {
    final z = zoneOf(grass, enemies: ['golem 8 3 sleep']);
    final far = sim(z, hero: at(5, 3));
    far.wait();
    expect(far.enemies.single.awareness, Awareness.asleep);
    final near = sim(z, hero: at(6, 3));
    near.wait();
    expect(near.enemies.single.awareness, Awareness.alert);
  });

  test('an alert enemy closes in and hits the hero', () {
    final z = zoneOf(grass, enemies: ['knight 9 3 guard']);
    final s = sim(z, hero: at(5, 3));
    final start = s.heroHp;
    for (var i = 0; i < 6; i++) {
      s.wait();
    }
    expect(s.enemies.single.hex.distanceTo(s.hero), 1);
    expect(s.heroHp, lessThan(start));
  });

  test('an archer shoots from range instead of closing in', () {
    final z = zoneOf(grass, enemies: ['archer 8 3 guard']);
    final s = sim(z, hero: at(5, 3));
    final start = s.heroHp;
    s.wait();
    expect(s.heroHp, lessThan(start));
    expect(s.enemies.single.hex, at(8, 3));
  });

  test('pack members alert each other', () {
    final z = zoneOf(grass, enemies: ['knight 8 3 guard', 'knight 8 5 sleep']);
    final s = sim(z, hero: at(4, 3));
    s.wait();
    expect(s.enemies.every((e) => e.awareness == Awareness.alert), isTrue);
  });

  test('losing sight leads to searching, then going home', () {
    final rows = [...grass];
    final z = zoneOf(rows, enemies: ['knight 8 3 guard']);
    final s = sim(z, hero: at(5, 3));
    s.wait();
    expect(s.enemies.single.awareness, Awareness.alert);
    // The hero vanishes far away (teleport in the test).
    s.hero = at(19, 0);
    var sawSearch = false;
    for (var i = 0; i < 40; i++) {
      s.wait();
      if (s.enemies.single.awareness == Awareness.search) sawSearch = true;
      if (s.enemies.single.awareness == Awareness.idle) break;
    }
    expect(sawSearch, isTrue);
    expect(s.enemies.single.awareness, Awareness.idle);
    expect(s.enemies.single.hex, at(8, 3));
  });

  test('a patrol walks its route', () {
    final z = zoneOf(grass, enemies: ['knight 2 1 patrol 6,1']);
    final s = sim(z, hero: at(18, 6));
    final seen = <Hex>{};
    for (var i = 0; i < 20; i++) {
      s.wait();
      seen.add(s.enemies.single.hex);
    }
    expect(seen, contains(at(6, 1)));
    expect(seen, contains(at(2, 1)));
  });

  test('sneak attacks hit twice as hard; fair fights do not', () {
    final z = zoneOf(grass, enemies: ['archer 5 3 sleep']);
    final s = sim(z, hero: at(4, 3));
    // Archer: 3 HP. A sneak attack does 4.
    final e = s.enemies.single;
    expect(s.attack(e), isTrue);
    expect(s.enemies, isEmpty);
    expect(s.events.last.kind, SimEventKind.killedEnemy);
    expect(s.events.last.sneak, isTrue);

    final z2 = zoneOf(grass, enemies: ['knight 5 3 guard']);
    final s2 = sim(z2, hero: at(4, 3));
    s2.wait(); // it notices
    final k = s2.enemies.single;
    final before = k.hp;
    s2.attack(k);
    expect(before - k.hp, WorldState().damageOf(WeaponKind.sword));
  });

  test('the hero cannot walk through enemies and can fall', () {
    final z = zoneOf(grass, enemies: ['golem 5 3 guard']);
    final s = sim(z, hero: at(4, 3), hp: 2);
    expect(s.moveHero(at(5, 3)), isFalse);
    s.wait(); // the golem hits for 3
    expect(s.heroDown, isTrue);
    expect(s.events.any((e) => e.kind == SimEventKind.heroDown), isTrue);
    s.respawn();
    expect(s.heroDown, isFalse);
    expect(s.hero, z.spawn);
    expect(s.enemies.single.awareness, Awareness.idle);
  });

  test('calm turns heal the hero slowly', () {
    final z = zoneOf(grass);
    final s = sim(z, hero: at(2, 2), hp: 4);
    for (var i = 0; i < ZoneSim.regenEvery; i++) {
      s.wait();
    }
    expect(s.heroHp, 5);
  });

  test('every enemy in the shipped zones stands on walkable ground', () {
    for (final f in Directory('assets/zones').listSync().whereType<File>()) {
      if (!f.path.endsWith('.txt')) continue;
      final z = Zone.parse(f.readAsStringSync());
      for (final e in z.enemies) {
        expect(z.tiles[e.hex]?.walkable, isTrue, reason: '${z.id} ${e.type}');
        for (final w in e.route) {
          expect(z.tiles[w]?.walkable, isTrue, reason: '${z.id} route $w');
        }
      }
    }
  });

  group('weapons', () {
    test('the sword needs adjacency, the bow needs range and clear sight', () {
      final z = zoneOf(grass, enemies: ['knight 8 3 guard']);
      final world = WorldState();
      final s = sim(z, hero: at(5, 3), world: world);
      final k = s.enemies.single;
      expect(s.reaches(k), isFalse); // sword, 3 hexes away
      world.equipped = WeaponKind.bow;
      expect(s.reaches(k), isTrue); // bow, 3 hexes away
      s.hero = at(7, 3);
      expect(s.reaches(k), isFalse); // too close for the bow
    });

    test('the bow does not shoot through mountains', () {
      final rows = [...grass];
      rows[3] = '${rows[3].substring(0, 6)}^${rows[3].substring(7)}';
      final z = zoneOf(rows, enemies: ['knight 8 3 guard']);
      final world = WorldState()..equipped = WeaponKind.bow;
      final s = sim(z, hero: at(4, 3), world: world);
      expect(s.reaches(s.enemies.single), isFalse);
    });

    test('upgrades add damage and cost tokens', () {
      final w = WorldState()..tokens = 3;
      expect(w.damageOf(WeaponKind.sword), 3);
      expect(w.upgrade(WeaponKind.sword), isTrue); // costs 1
      expect(w.upgrade(WeaponKind.sword), isTrue); // costs 2
      expect(w.damageOf(WeaponKind.sword), 5);
      expect(w.tokens, 0);
      expect(w.upgrade(WeaponKind.sword), isFalse); // maxed
    });

    test('kills are remembered until a rest', () {
      final z = zoneOf(grass, enemies: ['archer 5 3 sleep']);
      final world = WorldState();
      final s = sim(z, hero: at(4, 3), world: world);
      s.attack(s.enemies.single);
      expect(s.enemies, isEmpty);
      // Re-entering the zone: the kill sticks.
      expect(sim(z, world: world).enemies, isEmpty);
      s.rest(z.spawn);
      expect(s.enemies, hasLength(1));
      expect(world.hp, WorldState.maxHp);
    });
  });

  group('fireball', () {
    test('costs mana, hurts the centre for 2 and the ring for 1', () {
      final z = zoneOf(grass, enemies: ['golem 8 3 sleep', 'knight 9 3 sleep']);
      final world = WorldState();
      final s = sim(z, hero: at(4, 3), world: world);
      final golem = s.enemies.firstWhere((e) => e.type == UnitType.golem);
      final knight = s.enemies.firstWhere((e) => e.type == UnitType.knight);
      final g0 = golem.hp, k0 = knight.hp;
      expect(s.castFireball(golem.hex), isTrue);
      expect(world.mana, WorldState.maxMana - ZoneSim.fireballCost + 0);
      // 2 / 1 from the blast, plus 1 more for anyone still standing in the
      // flames when they go out (the knight runs out of them).
      expect(g0 - golem.hp, greaterThanOrEqualTo(2));
      expect(k0 - knight.hp, inInclusiveRange(1, 2));
      // Hit enemies notice the hero.
      expect(golem.awareness, Awareness.alert);
    });

    test('needs mana and range', () {
      final z = zoneOf(grass);
      final world = WorldState()..mana = 1;
      final s = sim(z, hero: at(4, 3), world: world);
      expect(s.canCastFireball(at(7, 3)), isFalse); // not enough mana
      world.mana = 4;
      expect(s.canCastFireball(at(7, 3)), isTrue);
      expect(s.canCastFireball(at(12, 3)), isFalse); // too far
      expect(s.canCastFireball(at(4, 3)), isFalse); // not on yourself
    });

    test('a fireball arcs over trees but not through mountains', () {
      final rows = [...grass];
      rows[3] = '${rows[3].substring(0, 5)}ff${rows[3].substring(7)}';
      final z = zoneOf(rows);
      final s = sim(z, hero: at(3, 3));
      expect(s.canCastFireball(at(7, 3)), isTrue); // over the trees
      rows[3] = '${rows[3].substring(0, 5)}^f${rows[3].substring(7)}';
      final blocked = sim(zoneOf(rows), hero: at(3, 3));
      expect(blocked.canCastFireball(at(7, 3)), isFalse);
    });

    test('mana comes back as turns pass', () {
      final z = zoneOf(grass);
      final world = WorldState()..mana = 0;
      final s = sim(z, hero: at(2, 2), world: world);
      for (var i = 0; i < ZoneSim.manaEvery * 2; i++) {
        s.wait();
      }
      expect(world.mana, 2);
    });

    test('forests burn, spread, and turn to grass', () {
      final rows = [...grass];
      for (var r = 2; r <= 4; r++) {
        rows[r] = '${rows[r].substring(0, 6)}ffffff${rows[r].substring(12)}';
      }
      final z = zoneOf(rows);
      final world = WorldState();
      final s = sim(z, hero: at(3, 3), world: world);
      expect(s.castFireball(at(6, 3)), isTrue);
      expect(s.fire, isNotEmpty);
      for (var i = 0; i < 12; i++) {
        s.wait();
      }
      expect(s.fire, isEmpty);
      // Burnt forest is now grass in the session copy, not in the source.
      expect(s.zone.tiles[at(6, 3)]!.terrain, Terrain.grass);
      expect(z.tiles[at(6, 3)]!.terrain, Terrain.forest);
    });

    test('burning ground hurts the hero standing in it', () {
      final z = zoneOf(grass);
      final world = WorldState();
      final s = sim(z, hero: at(4, 3), world: world);
      s.fire[at(4, 3)] = 2;
      final before = world.hp;
      s.wait();
      expect(world.hp, before - 1);
    });

    test('enemies refuse to path through fire', () {
      final z = zoneOf(grass, enemies: ['knight 9 3 guard']);
      final s = sim(z, hero: at(2, 3));
      final k = s.enemies.single;
      k.awareness = Awareness.alert;
      k.lastSeen = s.hero;
      // A wall of fire between the two.
      for (var r = 0; r < 7; r++) {
        s.fire[at(5, r)] = 5;
        s.fire[at(6, r)] = 5;
      }
      for (var i = 0; i < 3; i++) {
        s.wait();
      }
      expect(s.fire.containsKey(k.hex), isFalse);
      expect(k.hex.q + k.hex.r ~/ 2, greaterThan(6));
    });
  });

  test('items are picked up once and NPCs block the way', () {
    final z = Zone.parse(
      [
        'zone t',
        'name Test',
        'dark 0',
        'npc mara Mara 3 2 healer',
        'item lantern 5 2 star Lantern',
        'camp 1 1',
        'map',
        '@......',
        '.......',
        '.......',
      ].join('\n'),
    );
    final world = WorldState();
    final s = sim(z, hero: at(4, 2), world: world);
    expect(s.npcAt(at(3, 2))?.name, 'Mara');
    expect(s.moveHero(at(3, 2)), isFalse);
    expect(s.isCamp(at(1, 1)), isTrue);
    expect(s.moveHero(at(5, 2)), isTrue);
    expect(world.inventory, contains('lantern'));
    expect(s.events.any((e) => e.kind == SimEventKind.pickup), isTrue);
    expect(s.groundItems, isEmpty);
    expect(sim(z, world: world).groundItems, isEmpty);
  });

  test('water, lava and mountains block the hero; bridges do not', () {
    final z = zoneOf(['@.~w^L.', '.......']);
    final s = sim(z, hero: at(1, 0));
    expect(s.moveHero(at(2, 0)), isFalse); // water
    expect(z.tiles[at(2, 0)]!.walkable, isFalse);
    expect(z.tiles[at(4, 0)]!.walkable, isFalse); // mountain
    expect(z.tiles[at(5, 0)]!.walkable, isFalse); // lava
    expect(z.tiles[at(3, 0)]!.walkable, isTrue); // bridge
  });

  test('in the shipped zones only bridge tiles over water can be crossed', () {
    for (final f in Directory('assets/zones').listSync().whereType<File>()) {
      if (!f.path.endsWith('.txt')) continue;
      final z = Zone.parse(f.readAsStringSync());
      for (final e in z.tiles.entries) {
        final isWater = e.value.terrain == Terrain.water;
        if (isWater && !e.value.ford) {
          expect(e.value.walkable, isFalse, reason: '${z.id} ${e.key}');
        }
      }
      // Every bridge sits in a river, never on its own.
      for (final e in z.tiles.entries.where((e) => e.value.ford)) {
        final waterNear = e.key.neighbors.any(
          (n) => z.tiles[n]?.terrain == Terrain.water,
        );
        expect(waterNear, isTrue, reason: '${z.id} ${e.key}');
      }
    }
  });

  group('combat events', () {
    test('a swing is reported before its hit, with where it came from', () {
      final z = zoneOf(grass, enemies: ['knight 5 3 guard']);
      final s = sim(z, hero: at(4, 3));
      s.attack(s.enemies.single);
      final kinds = s.events.map((e) => e.kind).toList();
      expect(kinds.indexOf(SimEventKind.heroSwing), 0);
      final swing = s.events.first;
      expect(swing.from, at(4, 3));
      expect(swing.hex, at(5, 3));
      expect(swing.ranged, isFalse);
      expect(
        kinds.indexWhere(
          (k) => k == SimEventKind.hitEnemy || k == SimEventKind.killedEnemy,
        ),
        greaterThan(0),
      );
    });

    test('the bow is a ranged swing', () {
      final z = zoneOf(grass, enemies: ['knight 7 3 guard']);
      final world = WorldState()..equipped = WeaponKind.bow;
      final s = sim(z, hero: at(4, 3), world: world);
      s.attack(s.enemies.single);
      expect(s.events.first.kind, SimEventKind.heroSwing);
      expect(s.events.first.ranged, isTrue);
    });

    test('an enemy attack is reported with its attacker and type', () {
      final z = zoneOf(grass, enemies: ['archer 8 3 guard']);
      final s = sim(z, hero: at(5, 3));
      s.wait();
      final swing = s.events.firstWhere(
        (e) => e.kind == SimEventKind.enemySwing,
      );
      expect(swing.from, at(8, 3));
      expect(swing.unit, UnitType.archer);
      expect(swing.ranged, isTrue);
      final order = s.events.map((e) => e.kind).toList();
      expect(
        order.indexOf(SimEventKind.enemySwing),
        lessThan(order.indexOf(SimEventKind.hitHero)),
      );
    });

    test('threatens() tells the screen who will strike this turn', () {
      final z = zoneOf(
        grass,
        enemies: ['knight 6 3 guard', 'archer 10 3 guard'],
      );
      final s = sim(z, hero: at(5, 3));
      final knight = s.enemies.firstWhere((e) => e.type == UnitType.knight);
      final archer = s.enemies.firstWhere((e) => e.type == UnitType.archer);
      expect(s.threatens(knight), isFalse); // not alert yet
      knight.awareness = Awareness.alert;
      archer.awareness = Awareness.alert;
      expect(s.threatens(knight), isTrue); // adjacent
      expect(s.threatens(archer), isFalse); // 5 away, out of range
      s.hero = at(8, 3);
      expect(s.threatens(archer), isTrue); // 2 away, in range
    });

    test('a kill reports who died', () {
      final z = zoneOf(grass, enemies: ['archer 5 3 sleep']);
      final s = sim(z, hero: at(4, 3));
      s.attack(s.enemies.single);
      final kill = s.events.firstWhere(
        (e) => e.kind == SimEventKind.killedEnemy,
      );
      expect(kill.unit, UnitType.archer);
    });
  });
}
