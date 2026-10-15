import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hex/game/models.dart';
import 'package:hex/world/boss.dart';
import 'package:hex/world/gen_zone.dart';
import 'package:hex/world/sim.dart';
import 'package:hex/world/tiers.dart';
import 'package:hex/world/world_state.dart';
import 'package:hex/world/zone.dart';

/// A bare arena with a knight, a golem and (optionally) a boss, at [tier].
Zone arena(int tier, {String extra = ''}) => Zone.parse(
  [
    'zone t',
    'name Test',
    'dark 0',
    if (tier > 0) 'tier $tier',
    'enemy knight 8 3 guard',
    'enemy golem 10 3 guard',
    if (extra.isNotEmpty) extra,
    'map',
    for (var r = 0; r < 7; r++) (r == 3 ? '@' : '.') + '.' * 15,
  ].join('\n'),
);

Enemy first(Zone z, UnitType t) => ZoneSim(
  z,
  world: WorldState(),
  rng: math.Random(1),
).enemies.firstWhere((e) => e.type == t);

void main() {
  test('tier 0 is the base game', () {
    final k = first(arena(0), UnitType.knight);
    expect(k.maxHp, unitStats[UnitType.knight]!.maxHp);
    expect(k.damage, unitStats[UnitType.knight]!.damage);
  });

  test('a higher tier gives more hit points and harder hits', () {
    final base = first(arena(0), UnitType.knight);
    for (var t = 1; t < tiers.length; t++) {
      final k = first(arena(t), UnitType.knight);
      expect(k.maxHp, greaterThan(base.maxHp), reason: 'tier $t hp');
      expect(k.hp, k.maxHp);
      expect(k.damage, base.damage + tiers[t].damage, reason: 'tier $t hit');
    }
    final g = first(arena(1), UnitType.golem);
    expect(g.maxHp, 10); // 8 at 125%
    expect(g.damage, 4);
  });

  test('past the last tier the last one holds', () {
    expect(
      first(arena(99), UnitType.knight).maxHp,
      first(arena(tiers.length - 1), UnitType.knight).maxHp,
    );
  });

  test('a tier hit really costs the hero more', () {
    int taken(int tier) {
      final z = arena(tier);
      final w = WorldState();
      final s = ZoneSim(z, world: w, heroAt: z.spawn, rng: math.Random(1));
      final k = s.enemies.firstWhere((e) => e.type == UnitType.knight);
      s.enemies.removeWhere((e) => e != k); // only the knight swings
      s.hero = k.hex.neighbors.firstWhere((h) => z.tiles[h]!.walkable);
      k.awareness = Awareness.alert;
      final before = w.hp;
      s.wait();
      return before - w.hp;
    }

    expect(taken(1), taken(0) + 1);
  });

  test('bosses and nodes ignore the tier', () {
    final z = Zone.parse(
      [
        'zone t',
        'name Test',
        'dark 0',
        'tier 3',
        'enemy warlord 8 3 guard',
        'enemy node 10 3 guard',
        'map',
        for (var r = 0; r < 7; r++) (r == 3 ? '@' : '.') + '.' * 15,
      ].join('\n'),
    );
    for (final t in [UnitType.warlord, UnitType.node]) {
      final e = first(z, t);
      expect(e.maxHp, bossKits[t]!.hp);
      expect(e.damage, unitStats[t]!.damage);
    }
  });

  test('the hand-made zones stay at the base tier', () {
    for (final f in Directory('assets/zones').listSync().whereType<File>()) {
      if (!f.path.endsWith('.txt')) continue;
      expect(Zone.parse(f.readAsStringSync()).tier, 0, reason: f.path);
    }
  });

  test('the generated road rises to tier 1 at the node', () {
    expect(room('outer_a').tier, 0);
    expect(room('outer_b').tier, 0);
    expect(room('outer_c').tier, 1);
    expect(
      first(room('outer_c'), UnitType.knight).maxHp,
      greaterThan(unitStats[UnitType.knight]!.maxHp),
    );
  });
}

Zone room(String id) => Zone.parse(outerRoom(id, 1));
