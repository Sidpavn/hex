import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/game/hex.dart';
import 'package:hex/game/models.dart';
import 'package:hex/world/pathfinding.dart';
import 'package:hex/world/quests.dart';
import 'package:hex/world/sim.dart';
import 'package:hex/world/world_state.dart';
import 'package:hex/world/zone.dart';

Map<String, Zone> _zones() => {
  for (final id in ZoneRepo.ids)
    id: Zone.parse(File('assets/zones/$id.txt').readAsStringSync()),
};

void main() {
  final zones = _zones();
  final mara = zones['meadow']!.npcs.firstWhere((n) => n.id == 'mara');

  group('training', () {
    final yard = zones['training']!;
    final tobin = yard.npcs.firstWhere((n) => n.id == 'trainer');

    test('a new game starts with bare hands and no spells', () {
      final w = WorldState.newGame();
      expect(w.weaponId, 'fists');
      expect(w.knownSpells, isEmpty);
      expect(w.spellSlots, everyElement(isNull));
    });

    test('walking over a weapon equips it, the first one is held', () {
      final w = WorldState.newGame();
      w.addItem('sword');
      w.autoEquip('sword');
      expect(w.weaponId, 'sword');
      w.addItem('bow');
      w.autoEquip('bow');
      expect(w.weaponSlots, ['sword', 'bow']);
      expect(w.weaponId, 'sword');
      // Slots full: a third weapon stays in the bag.
      w.addItem('axe');
      w.autoEquip('axe');
      expect(w.weaponSlots, ['sword', 'bow']);
      expect(w.countOf('axe'), 1);
    });

    test('Tobin takes you from sword to bow to Mend', () {
      final w = WorldState.newGame();
      final s = ZoneSim(yard, world: w, rng: math.Random(1));
      final post = s.enemies.single;
      expect(post.type, UnitType.post);
      expect(npcMark(tobin, w), 'alert');
      talkTo(tobin, w).choices.first.apply(w);
      expect(w.quests['training'], 1);
      expect(currentObjective(w)?.item, 'sword');

      // Not carrying it yet: only a hint.
      expect(talkTo(tobin, w).choices, isEmpty);
      w.addItem('sword');
      w.autoEquip('sword');
      expect(currentObjective(w)?.unit, UnitType.post);
      expect(npcMark(tobin, w), isNull);

      // Three swings at the post, standing next to it.
      s.hero = post.hex.neighbors.firstWhere((h) => yard.tiles[h]!.walkable);
      for (var i = 0; i < 3; i++) {
        expect(s.attack(post), isTrue);
      }
      expect(w.count(Counts.postMelee), 3);
      expect(npcMark(tobin, w), 'search');
      expect(currentObjective(w)?.npc, 'trainer');
      talkTo(tobin, w).choices.single.apply(w);
      expect(w.quests['training'], 2);
      expect(currentObjective(w)?.item, 'bow');

      w.addItem('bow');
      w.autoEquip('bow');
      w.activeWeapon = w.weaponSlots.indexOf('bow');
      expect(currentObjective(w)?.unit, UnitType.post);
      s.hero = [
        for (final h in yard.tiles.keys)
          if (yard.tiles[h]!.walkable &&
              h.distanceTo(post.hex) == 3 &&
              s.lineOfSight(h, post.hex))
            h,
      ].first;
      for (var i = 0; i < 3; i++) {
        expect(s.attack(post), isTrue);
      }
      expect(w.count(Counts.postRanged), 3);
      talkTo(tobin, w).choices.single.apply(w);
      expect(w.quests['training'], 3);
      expect(w.knownSpells, isEmpty);

      // Tobin hurts you and teaches Mend; healing yourself finishes it.
      talkTo(tobin, w).choices.single.apply(w);
      expect(w.quests['training'], 4);
      expect(w.knownSpells, {'mend'});
      expect(w.hp, WorldState.maxHp - 4);
      expect(currentObjective(w)?.text, contains('Cast Mend'));
      expect(s.castMend(), isTrue);
      expect(npcMark(tobin, w), 'search');
      talkTo(tobin, w).choices.single.apply(w);
      expect(w.quests['training'], 5);
      expect(npcMark(tobin, w), isNull);
      expect(currentObjective(w), isNull);
    });

    test(
      'with the bow in the bag but the sword in hand, Tobin says to switch',
      () {
        final w = WorldState.newGame()
          ..quests['training'] = 2
          ..addItem('sword');
        w.autoEquip('sword');
        w.addItem('bow');
        w.autoEquip('bow');
        expect(w.weaponId, 'sword');
        expect(currentObjective(w)?.hint, 'bow');
        expect(talkTo(tobin, w).lines.join(' '), contains('quick bar'));
        w.activeWeapon = w.weaponSlots.indexOf('bow');
        expect(currentObjective(w)?.hint, isNull);
        expect(currentObjective(w)?.unit, UnitType.post);
      },
    );

    test('the Mend step points at the Mend slot', () {
      final w = WorldState.newGame()
        ..quests['training'] = 4
        ..learn('mend');
      expect(currentObjective(w)?.hint, 'mend');
      w.bump(Counts.castMend);
      expect(currentObjective(w)?.hint, isNull);
    });

    test('hits before the lesson starts do not count', () {
      final w = WorldState.newGame()..bump(Counts.postMelee);
      talkTo(tobin, w).choices.first.apply(w);
      expect(w.count(Counts.postMelee), 0);
    });

    test('if you heal before casting Mend, Tobin hurts you again', () {
      final w = WorldState.newGame()
        ..quests['training'] = 4
        ..learn('mend');
      final d = talkTo(tobin, w);
      expect(d.choices.single.label, 'Hold still');
      d.choices.single.apply(w);
      expect(w.hp, WorldState.maxHp - 4);
      // Hurt: now he only reminds you where the spell is.
      expect(talkTo(tobin, w).choices, isEmpty);
    });

    test('the post never fights back, dies or wakes up', () {
      final w = WorldState.newGame()
        ..addItem('sword')
        ..equipped = 'sword';
      final s = ZoneSim(yard, world: w, rng: math.Random(1));
      final post = s.enemies.single;
      s.hero = post.hex.neighbors.firstWhere((h) => yard.tiles[h]!.walkable);
      for (var i = 0; i < 40; i++) {
        s.attack(post);
      }
      expect(post.hp, post.stats.maxHp);
      expect(post.alive, isTrue);
      expect(post.hostile, isFalse);
      expect(w.hp, WorldState.maxHp);
      expect(s.danger, isFalse);
      expect(w.slain, isEmpty);
    });

    test('the gate to the meadow stays shut until training is done', () {
      final w = WorldState.newGame();
      final gate = yard.portalHex['1']!;
      final s = ZoneSim(
        yard,
        world: w,
        heroAt: gate.neighbors.firstWhere((h) => yard.tiles[h]!.walkable),
        rng: math.Random(1),
      );
      expect(s.moveHero(gate), isFalse);
      expect(s.events.single.kind, SimEventKind.gateClosed);
      expect(closedGate('training', '1', w)?.message, isNotEmpty);
      w.quests['training'] = 4;
      expect(s.moveHero(gate), isFalse);
      w.quests['training'] = 5;
      s.events.clear();
      expect(s.moveHero(gate), isTrue);
      expect(closedGate('training', '1', w), isNull);
    });

    test('Tobin hands out a spare if you lost the sword or the bow', () {
      final w = WorldState.newGame()
        ..quests['training'] = 1
        ..collected.add('training#sword');
      expect(npcMark(tobin, w), 'search');
      expect(currentObjective(w)?.npc, 'trainer');
      talkTo(tobin, w).choices.single.apply(w);
      expect(w.weaponId, 'sword');

      w
        ..quests['training'] = 2
        ..collected.add('training#bow');
      talkTo(tobin, w).choices.single.apply(w);
      expect(w.weaponSlots, ['sword', 'bow']);
    });

    test('the unit counter keys match the constants', () {
      expect(Counts.hit(UnitType.post, ranged: false), Counts.postMelee);
      expect(Counts.hit(UnitType.post, ranged: true), Counts.postRanged);
      expect(Counts.cast('mend'), Counts.castMend);
    });

    test('the sword and bow can be reached from the spawn', () {
      for (final id in ['sword', 'bow']) {
        final item = yard.items.firstWhere((i) => i.id == id);
        expect(findPath(yard, yard.spawn, item.hex), isNotNull, reason: id);
      }
      final gate = yard.portalHex['1']!;
      expect(findPath(yard, yard.spawn, gate), isNotNull);
      expect(zones['meadow']!.portals['2']?.toZone, 'training');
    });
  });

  test('Mara offers the quest, accepts it, then takes the lantern', () {
    final w = WorldState();
    expect(npcMark(mara, w), 'alert');
    var d = talkTo(mara, w);
    expect(d.choices.map((c) => c.label), contains('I will find it'));
    d.choices.first.apply(w);
    expect(questStage(w, 'lantern'), 1);
    expect(npcMark(mara, w), isNull);
    // The hatchet comes first, then the bridges, then the cave.
    expect(currentObjective(w)?.item, 'hatchet');
    expect(currentObjective(w)?.zone, 'mine');
    w.addItem('hatchet');
    expect(currentObjective(w)?.zone, 'meadow');
    w.repaired.add('meadow#a');
    expect(currentObjective(w)?.zone, 'cave');

    // Talking again before finding it only gives a hint.
    d = talkTo(mara, w);
    expect(d.choices, isEmpty);

    // Pick the lantern up: she is now waiting for it.
    w.addItem('lantern');
    expect(npcMark(mara, w), 'search');
    expect(currentObjective(w)?.zone, 'meadow');
    d = talkTo(mara, w);
    d.choices.single.apply(w);
    expect(questStage(w, 'lantern'), 2);
    expect(w.tokens, 3);
    expect(w.hasItem('lantern'), isFalse);
    expect(currentObjective(w), isNull);
    expect(npcMark(mara, w), isNull);
  });

  group('saving', () {
    tearDown(Storage.clearMemory);

    test('a world survives a round trip through JSON', () {
      final w = WorldState.newGame()
        ..hp = 5
        ..mana = 1
        ..tokens = 7
        ..addItem('potion', 3)
        ..addItem('lantern')
        ..addItem('sword')
        ..autoEquip('sword')
        ..learn('mend')
        ..upgrades['sword'] = 2
        ..quests['training'] = 4
        ..collected.add('training#bow')
        ..slain.add('meadow#1')
        ..bump(Counts.castMend)
        ..camp = (zone: 'meadow', hex: const Hex(3, 4))
        ..resume = (zone: 'cave', hex: const Hex(-2, 9));
      final back = WorldState.fromJson(
        jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>,
      );
      expect(back.toJson(), w.toJson());
      expect(back.hp, 5);
      expect(back.weaponId, 'sword');
      expect(back.countOf('potion'), 3);
      expect(back.knownSpells, {'mend'});
      expect(back.camp, w.camp);
      expect(back.resume, w.resume);
      expect(back.count(Counts.castMend), 1);
    });

    test('Storage keeps the explore game, and ignores a damaged one', () {
      expect(Storage.exploreWorld, isNull);
      final w = WorldState.newGame()
        ..quests['training'] = 5
        ..resume = (zone: 'meadow', hex: const Hex(1, 1));
      Storage.saveExplore(w);
      expect(Storage.exploreWorld?.quests['training'], 5);
      Storage.clearExplore();
      expect(Storage.exploreWorld, isNull);
    });
  });

  test('reward labels are generated from the effects', () {
    final w = WorldState()..addItem('lantern');
    expect(
      talkTo(mara, w).choices.single.label,
      'Hand it over (3 tokens, 2 healing potions)',
    );
  });

  test('a quest is listed once its requirement holds, and stays listed', () {
    const next = Quest(
      id: 'well',
      title: 'Well',
      giver: 'Mara',
      summary: '',
      objectives: [],
      requires: QuestFrom('lantern', 2),
    );
    final w = WorldState();
    expect(next.isListed(w), isFalse);
    w.quests['lantern'] = 2;
    expect(next.isListed(w), isTrue);
    w.quests['lantern'] = 0;
    w.quests['well'] = 1;
    expect(next.isListed(w), isTrue);
  });

  test('conditions combine', () {
    final w = WorldState();
    expect(
      const All([HasItem('potion'), Not(HasItem('lantern'))]).test(w),
      isTrue,
    );
    expect(
      const Any([HasItem('lantern'), QuestAt('lantern', 0)]).test(w),
      isTrue,
    );
    expect(const QuestFrom('lantern', 1).test(w), isFalse);
  });

  test('finding the lantern before accepting still lets you hand it in', () {
    final w = WorldState()..addItem('lantern');
    final d = talkTo(mara, w);
    d.choices.single.apply(w);
    expect(w.quests['lantern'], 2);
    expect(w.tokens, 3);
  });

  test('the cave boss guards the lantern', () {
    final cave = zones['cave']!;
    expect(cave.enemies.any((e) => e.type == UnitType.pyromancer), isTrue);
  });

  test('markers point at the target, or at the portal that leads there', () {
    final w = WorldState()..quests['lantern'] = 1;
    final meadow = zones['meadow']!;
    final cave = zones['cave']!;
    // First the hatchet: the meadow marker is the old mine's mouth.
    final mine = zones['mine']!;
    final first = currentObjective(w)!;
    expect(markerHex(meadow, first, zones), meadow.portalHex['3']);
    final hatchet = mine.items.firstWhere((i) => i.id == 'hatchet');
    expect(markerHex(mine, first, zones), hatchet.hex);
    w.repaired.add('meadow#a');
    final goal = currentObjective(w)!;
    // In the meadow the marker is the cave mouth.
    expect(markerHex(meadow, goal, zones), meadow.portalHex['1']);
    // In the cave it is the lantern itself.
    final lantern = cave.items.firstWhere((i) => i.id == 'lantern');
    expect(markerHex(cave, goal, zones), lantern.hex);
    // Carrying it back, the cave's marker is its exit.
    w.addItem('lantern');
    final back = currentObjective(w)!;
    expect(markerHex(cave, back, zones), cave.portalHex['1']);
    expect(markerHex(meadow, back, zones), mara.hex);
  });

  test('every item, camp and NPC stands on walkable ground', () {
    for (final z in zones.values) {
      for (final h in z.camps) {
        expect(z.tiles[h]?.walkable, isTrue, reason: '${z.id} camp');
      }
      for (final n in z.npcs) {
        expect(z.tiles[n.hex]?.walkable, isTrue, reason: '${z.id} ${n.id}');
      }
      for (final i in z.items) {
        expect(z.tiles[i.hex]?.walkable, isTrue, reason: '${z.id} ${i.id}');
      }
    }
  });

  test('the lantern can be reached from the cave entrance', () {
    final cave = zones['cave']!;
    final lantern = cave.items.firstWhere((i) => i.id == 'lantern');
    expect(findPath(cave, cave.spawn, lantern.hex), isNotNull);
    // And Mara and the camp are reachable from the meadow's spawn.
    final meadow = zones['meadow']!;
    expect(findPath(meadow, meadow.spawn, meadow.camps.first), isNotNull);
    expect(findPath(meadow, meadow.spawn, mara.hex), isNotNull);
  });

  group('save format', () {
    test('statuses and the version survive a round trip', () {
      final w = WorldState()
        ..shield = 2
        ..shieldTurns = 4
        ..burn = 1;
      final json = jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>;
      expect(json['v'], WorldState.saveVersion);
      final back = WorldState.fromJson(json);
      expect([back.shield, back.shieldTurns, back.burn], [2, 4, 1]);
    });

    test('a save from before statuses still loads', () {
      final json =
          jsonDecode(jsonEncode(WorldState().toJson())) as Map<String, dynamic>
            ..remove('v')
            ..remove('shield')
            ..remove('shieldTurns')
            ..remove('burn');
      final back = WorldState.fromJson(json);
      expect([back.shield, back.shieldTurns, back.burn], [0, 0, 0]);
    });
  });
}
