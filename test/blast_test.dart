import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hex/game/hex.dart';
import 'package:hex/world/pathfinding.dart';
import 'package:hex/world/sim.dart';
import 'package:hex/world/world_state.dart';
import 'package:hex/world/zone.dart';

Hex at(int col, int row) => Hex(col - (row - (row & 1)) ~/ 2, row);

/// A flat room with a charge at col 7 and two hexes of rubble behind it,
/// then a corridor on the far side.
Zone room() => Zone.parse(
  [
    'zone t',
    'name Test',
    'dark 0',
    'map',
    '^^^^^^^^^^^^^^^^',
    '^^^^^^^^^^^^^^^^',
    '^@.........TXX..',
    '^^^^^^^^^^^^^^^^',
  ].join('\n'),
);

ZoneSim sim(Zone z, int col, WorldState w) =>
    ZoneSim(z, world: w, heroAt: at(col, 2));

void main() {
  final z = room();
  final charge = at(11, 2);
  final rubble = at(12, 2);

  test('the charge and the rubble block the way', () {
    expect(z.tiles[charge]!.walkable, isFalse);
    expect(z.tiles[rubble]!.walkable, isFalse);
    expect(z.charges, [charge]);
    expect(findPath(z, at(1, 2), at(15, 2)), isNull);
  });

  test('a Fireball at the charge sets it off and clears the rubble', () {
    final w = WorldState();
    final s = sim(z, 8, w);
    final hp = s.heroHp;
    expect(s.castFireball(charge), isTrue);
    expect(s.heroHp, hp);
    final blast = s.events.singleWhere((e) => e.kind == SimEventKind.blasted);
    expect(blast.hex, charge);
    expect(blast.amount, 2);
    expect(s.zone.tiles[charge]!.walkable, isTrue);
    expect(s.zone.tiles[rubble]!.walkable, isTrue);
    expect(s.zone.tiles[at(13, 2)]!.walkable, isTrue);
    expect(findPath(s.zone, at(1, 2), at(15, 2)), isNotNull);
    expect(w.blasted, {z.chargeId(charge)});
  });

  test('a Fireball landing beside it also sets it off', () {
    final s = sim(z, 8, WorldState());
    expect(s.castFireball(at(10, 2)), isTrue);
    expect(s.events.any((e) => e.kind == SimEventKind.blasted), isTrue);
  });

  test('a Fireball two hexes away leaves it alone', () {
    final w = WorldState();
    final s = sim(z, 5, w);
    expect(s.castFireball(at(9, 2)), isTrue);
    expect(s.events.any((e) => e.kind == SimEventKind.blasted), isFalse);
    expect(s.zone.tiles[charge]!.charge, isTrue);
    expect(w.blasted, isEmpty);
  });

  test('standing beside the charge hurts', () {
    final s = sim(z, 10, WorldState());
    final hp = s.heroHp;
    expect(s.castFireball(charge), isTrue);
    // 3 from the blast, and the Fireball's own ring.
    expect(s.heroHp, lessThan(hp - ZoneSim.chargeDamage + 1));
  });

  test('a blasted rockfall stays open after a rest and a reload', () {
    final w = WorldState();
    sim(z, 8, w).castFireball(charge);
    final back = WorldState.fromJson(
      jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
    );
    expect(back.blasted, w.blasted);
    final again = sim(z, 1, back);
    expect(again.zone.tiles[charge]!.walkable, isTrue);
    expect(again.zone.tiles[rubble]!.walkable, isTrue);
    expect(
      z.tiles[charge]!.charge,
      isTrue,
      reason: 'the loaded zone is intact',
    );
  });

  test('the Hollow Deep rockfall is closed until the charge is blasted', () {
    final cave = Zone.parse(File('assets/zones/cave.txt').readAsStringSync());
    expect(cave.charges, hasLength(1));
    final beyond = cave.tiles.entries
        .where((e) => e.value.walkable && e.key.q + e.key.r ~/ 2 > 26)
        .map((e) => e.key);
    expect(beyond, isNotEmpty);
    for (final h in beyond) {
      expect(findPath(cave, cave.spawn, h), isNull);
    }
    final w = WorldState();
    final s = ZoneSim(cave, world: w);
    // Stand three hexes west of it, out of the blast, and light it.
    s.hero = Hex(cave.charges.first.q - 3, cave.charges.first.r);
    expect(s.castFireball(cave.charges.first), isTrue);
    for (final h in beyond) {
      expect(findPath(s.zone, s.hero, h), isNotNull);
    }
  });
}
