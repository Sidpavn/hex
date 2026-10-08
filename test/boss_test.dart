import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hex/game/hex.dart';
import 'package:hex/game/models.dart';
import 'package:hex/world/boss.dart';
import 'package:hex/world/items.dart';
import 'package:hex/world/sim.dart';
import 'package:hex/world/world_state.dart';
import 'package:hex/world/zone.dart';

Hex at(int col, int row) => Hex(col - (row - (row & 1)) ~/ 2, row);

Zone arena() => Zone.parse(
  [
    'zone t',
    'name Test',
    'dark 0',
    'enemy pyromancer 12 3 guard',
    'map',
    for (var r = 0; r < 7; r++) (r == 3 ? '@' : '.') + '.' * 19,
  ].join('\n'),
);

/// Waits until the boss has aimed. Returns the sim and the boss.
(ZoneSim, Enemy) aimed(WorldState w, {Hex? hero}) {
  final s = ZoneSim(arena(), world: w, heroAt: hero, rng: math.Random(1));
  final boss = s.enemies.single;
  for (var i = 0; i < 6 && boss.telegraph.isEmpty; i++) {
    s.wait();
  }
  return (s, boss);
}

void main() {
  test('a boss has its own hit points and a spell to teach', () {
    final boss = ZoneSim(arena(), world: WorldState()).enemies.single;
    expect(boss.maxHp, bossKits[UnitType.pyromancer]!.hp);
    expect(bossKits[UnitType.pyromancer]!.spell, 'fireball');
  });

  test('it shows where the blast will land before it fires', () {
    final (s, boss) = aimed(WorldState(), hero: at(7, 3));
    expect(boss.telegraph, hasLength(7));
    expect(boss.telegraph, contains(boss.aim));
    expect(boss.aim, s.hero);
    expect(boss.charge, 2);
    expect(s.events.any((e) => e.kind == SimEventKind.telegraph), isTrue);
    expect(s.heroHp, WorldState.maxHp);
  });

  test('two steps away is enough to dodge it', () {
    final w = WorldState();
    final (s, boss) = aimed(w, hero: at(7, 3));
    final start = s.hero;
    s.events.clear();
    expect(s.moveHero(Hex(start.q - 1, start.r)), isTrue);
    expect(boss.telegraph, isNotEmpty); // still charging
    expect(s.moveHero(Hex(start.q - 2, start.r)), isTrue);
    expect(boss.telegraph, isEmpty); // it fired
    expect(s.events.any((e) => e.kind == SimEventKind.spell), isTrue);
    expect(w.hp, WorldState.maxHp);
    expect(s.fire, isNotEmpty);
  });

  test('standing still takes the hit', () {
    final w = WorldState();
    final (s, boss) = aimed(w, hero: at(7, 3));
    s.wait();
    s.wait();
    expect(boss.telegraph, isEmpty);
    expect(w.hp, lessThanOrEqualTo(WorldState.maxHp - 2));
    expect(boss.cool, bossKits[UnitType.pyromancer]!.cooldown);
  });

  test('beating the boss teaches its spell, once', () {
    final w = WorldState.newGame()
      ..addItem('sword')
      ..autoEquip('sword');
    expect(w.knownSpells, isEmpty);
    final s = ZoneSim(
      arena(),
      world: w,
      heroAt: at(11, 3),
      rng: math.Random(1),
    );
    final boss = s.enemies.single..hp = 1;
    s.hero = boss.hex.neighbors.firstWhere((h) => s.zone.tiles[h]!.walkable);
    s.events.clear();
    expect(s.attack(boss), isTrue);
    expect(boss.alive, isFalse);
    final learned = s.events.where((e) => e.kind == SimEventKind.learned);
    expect(learned.single.note, 'fireball');
    expect(w.knownSpells, {'fireball'});
    expect(w.spellSlots, contains('fireball'));

    // A second kill (after resting) does not teach it again.
    s.rest(s.hero);
    final again = s.enemies.single..hp = 1;
    s.hero = again.hex.neighbors.firstWhere((h) => s.zone.tiles[h]!.walkable);
    s.events.clear();
    s.attack(again);
    expect(s.events.any((e) => e.kind == SimEventKind.learned), isFalse);
  });

  test('the warlord teaches Shield and its blast leaves no fire', () {
    final kit = bossKits[UnitType.warlord]!;
    expect(kit.spell, 'shield');
    expect(spellDefs.containsKey(kit.spell), isTrue);
    expect(kit.fire, isFalse);
    final z = Zone.parse(
      [
        'zone t',
        'name Test',
        'dark 0',
        'enemy warlord 12 3 guard',
        'map',
        for (var r = 0; r < 7; r++) (r == 3 ? '@' : '.') + '.' * 19,
      ].join('\n'),
    );
    final s = ZoneSim(
      z,
      world: WorldState(),
      heroAt: at(7, 3),
      rng: math.Random(1),
    );
    final boss = s.enemies.single;
    for (var i = 0; i < 6 && boss.telegraph.isEmpty; i++) {
      s.wait();
    }
    for (var i = 0; i < 4 && boss.telegraph.isNotEmpty; i++) {
      s.wait();
    }
    expect(s.fire, isEmpty);
  });
}
