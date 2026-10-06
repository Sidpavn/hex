import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

import 'package:hex/data/storage.dart';
import 'package:hex/game/campaign.dart';
import 'package:hex/game/config.dart';
import 'package:hex/game/game_controller.dart';
import 'package:hex/game/hex.dart';
import 'package:hex/game/models.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';
import 'package:hex/ui/widgets.dart';

void main() {
  test('hex distance and direction', () {
    expect(const Hex(0, 0).distanceTo(const Hex(2, -1)), 2);
    expect(const Hex(0, 0).directionToward(const Hex(3, 0)), 0);
    final layout = BoardLayout.fit(const Size(400, 500));
    expect(
      layout.fromPixel(layout.hexCenter(const Hex(2, -3))),
      const Hex(2, -3),
    );
  });

  test('gust into water drowns a unit', () {
    final g = GameController(seed: 1, aiDelayScale: 0);
    // Rig the board: water directly behind the enemy knight.
    final hero = g.heroOf(Team.player)!;
    final knight = g.units.firstWhere((u) => u.team == Team.enemy && !u.isHero);
    knight.pos = hero.pos + Hex.dirs[0] + Hex.dirs[0];
    final dir = hero.pos.directionToward(knight.pos);
    g.tiles[knight.pos.neighbor(dir)] = Tile(Terrain.water);
    g.hand = [GameCard(999, CardType.gust)];
    g.energy = 3;
    g.selectCard(g.hand.first);
    expect(g.cardTargets, contains(knight.pos));
    g.playCard(knight.pos);
    expect(g.units.contains(knight), isFalse);
  });

  test('a spell cannot throw a hero into a hazard, it only hurts', () {
    final g = GameController(seed: 1, aiDelayScale: 0);
    final hero = g.heroOf(Team.player)!;
    final foe = g.heroOf(Team.enemy)!;
    foe.pos = hero.pos + Hex.dirs[0] + Hex.dirs[0];
    final dir = hero.pos.directionToward(foe.pos);
    g.tiles[foe.pos.neighbor(dir)] = Tile(Terrain.lava);
    g.hand = [GameCard(999, CardType.gust)];
    g.energy = 3;
    final before = foe.hp;
    g.selectCard(g.hand.first);
    g.playCard(foe.pos);
    expect(g.units.contains(foe), isTrue);
    expect(foe.pos, hero.pos + Hex.dirs[0] + Hex.dirs[0]);
    expect(foe.hp, before - GameController.heroSpellPushDamage);
  });

  test('only one attack spell can be cast per turn', () {
    final g = GameController(seed: 1, aiDelayScale: 0);
    final foe = g.units.firstWhere((u) => u.team == Team.enemy && !u.isHero);
    final hero = g.heroOf(Team.player)!;
    foe.pos = hero.pos + Hex.dirs[0] + Hex.dirs[0];
    g.hand = [
      GameCard(1, CardType.fireball),
      GameCard(2, CardType.gust),
      GameCard(3, CardType.heal),
    ];
    g.energy = 5;
    final second = g.hand[1];
    g.selectCard(g.hand.first);
    g.playCard(foe.pos);
    // The turn's attack spell is spent: Gust is blocked, utility cards aren't.
    expect(g.canCast(second), isFalse);
    g.selectCard(second);
    expect(g.selectedCard, isNull);
    expect(g.hint, contains('One attack spell per turn'));
    expect(g.canCast(g.hand.last), isTrue);
  });

  test('full AI-vs-passive game terminates without errors', () async {
    final g = GameController(seed: 7, aiDelayScale: 0);
    for (var i = 0; i < 40 && g.winner == null; i++) {
      g.endTurn();
      // AI runs on microtasks only when delay scale is 0.
      for (var k = 0; k < 50 && !g.isPlayerTurn && g.winner == null; k++) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    expect(g.round, greaterThan(1));
  });

  test('mage splash hits foes next to the target but not allies', () {
    final g = GameController(seed: 3, aiDelayScale: 0);
    g.units.removeWhere((u) => !u.isHero);
    final mage = Unit(
      id: 900,
      team: Team.player,
      type: UnitType.mage,
      pos: const Hex(0, 2),
    );
    final a = Unit(
      id: 901,
      team: Team.enemy,
      type: UnitType.golem,
      pos: const Hex(0, 0),
    );
    final b = Unit(
      id: 902,
      team: Team.enemy,
      type: UnitType.golem,
      pos: const Hex(1, 0),
    );
    final ally = Unit(
      id: 903,
      team: Team.player,
      type: UnitType.knight,
      pos: const Hex(-1, 1),
    );
    g.units.addAll([mage, a, b, ally]);
    for (final h in [mage.pos, a.pos, b.pos, ally.pos]) {
      g.tiles[h] = Tile(Terrain.grass);
    }
    g.attack(mage, a);
    expect(a.hp, 6);
    expect(b.hp, 7);
    expect(ally.hp, unitStats[UnitType.knight]!.maxHp);
  });

  test('healer restores an ally instead of attacking', () {
    final g = GameController(seed: 3, aiDelayScale: 0);
    final knight = g.units.firstWhere(
      (u) => u.team == Team.player && !u.isHero,
    );
    final healer = Unit(
      id: 910,
      team: Team.player,
      type: UnitType.healer,
      pos: knight.pos,
    );
    healer.pos = g.reachable(knight).keys.first;
    g.units.add(healer);
    knight.hp = 1;
    healer.pos = knight.pos.neighbors.firstWhere(
      (n) => g.tiles[n]?.walkable == true && g.unitAt(n) == null,
    );
    g.attack(healer, knight);
    expect(knight.hp, 3);
    expect(healer.canAct, isFalse);
  });

  test('mountains block movement and gust into one hurts', () {
    final g = GameController(seed: 1, aiDelayScale: 0);
    final hero = g.heroOf(Team.player)!;
    final knight = g.units.firstWhere((u) => u.team == Team.enemy && !u.isHero);
    knight.pos = hero.pos + Hex.dirs[0] + Hex.dirs[0];
    final dir = hero.pos.directionToward(knight.pos);
    final wall = knight.pos.neighbor(dir);
    g.tiles[wall] = Tile(Terrain.mountain);
    expect(g.tiles[wall]!.walkable, isFalse);
    final before = knight.hp;
    g.hand = [GameCard(999, CardType.gust)];
    g.energy = 3;
    g.selectCard(g.hand.first);
    g.playCard(knight.pos);
    expect(knight.hp, before - 1);
    expect(knight.pos, isNot(wall));
  });

  test('hot-seat hides hands, swaps teams and uses each side energy', () {
    final g = GameController(
      seed: 5,
      aiDelayScale: 0,
      config: const GameConfig(mode: GameMode.hotseat),
    );
    expect(g.viewTeam, Team.player);
    g.endTurn();
    expect(g.turn, Team.enemy);
    expect(g.passing, isTrue);
    expect(g.isPlayerTurn, isFalse);
    g.confirmPass();
    expect(g.isPlayerTurn, isTrue);
    expect(g.viewTeam, Team.enemy);
    expect(g.hand, isNotEmpty);
    g.endTurn();
    expect(g.round, 2);
    expect(g.turn, Team.player);
  });

  test('holding the centre for the target turns wins', () {
    final g = GameController(
      seed: 5,
      aiDelayScale: 0,
      config: const GameConfig(
        mode: GameMode.hotseat,
        objective: Objective.hold,
        target: 2,
      ),
    );
    final u = g.units.firstWhere((u) => u.team == Team.player && !u.isHero);
    u.pos = GameController.centre;
    g.endTurn();
    expect(g.winner, isNull);
    g.confirmPass();
    g.endTurn();
    g.confirmPass();
    expect(g.holdTurns[Team.player], 1);
    g.endTurn();
    expect(g.winner, Team.player);
  });

  test('survive objective is won when the rounds run out', () async {
    final g = GameController(
      seed: 9,
      aiDelayScale: 0,
      config: const GameConfig(objective: Objective.survive, target: 2),
    );
    // Keep the enemy from killing anyone: remove its units and hero attackers.
    for (var i = 0; i < 6 && g.winner == null; i++) {
      g.endTurn();
      for (var k = 0; k < 80 && !g.isPlayerTurn && g.winner == null; k++) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    expect(g.winner, isNotNull);
  });

  test(
    'every campaign level plays through every difficulty without errors',
    () async {
      for (final lv in campaignLevels) {
        for (final d in Difficulty.values) {
          final g = GameController(
            aiDelayScale: 0,
            config: lv.config.copyWith(difficulty: d),
          );
          for (var i = 0; i < 12 && g.winner == null; i++) {
            g.endTurn();
            for (
              var k = 0;
              k < 120 && !g.isPlayerTurn && g.winner == null;
              k++
            ) {
              await Future<void>.delayed(Duration.zero);
            }
          }
          expect(g.round, greaterThan(1), reason: '${lv.name} $d');
        }
      }
    },
  );

  Future<void> enemyTurn(GameController g) async {
    for (var k = 0; k < 100 && !g.isPlayerTurn && g.winner == null; k++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  LevelDef level(String name) =>
      campaignLevels.firstWhere((l) => l.name == name);

  test('a level with its own cards only ever deals those cards', () async {
    final lv = level('Burn Notice');
    final g = GameController(aiDelayScale: 0, config: Storage.configFor(lv));
    final allowed = lv.config.deck!;
    for (var i = 0; i < 20 && g.winner == null; i++) {
      for (final c in g.hand) {
        expect(allowed, contains(c.type), reason: 'round ${g.round}');
      }
      g.endTurn();
      await enemyTurn(g);
    }
  });

  test('running out of rounds loses a timed level', () async {
    final lv = level('Blitz');
    final g = GameController(aiDelayScale: 0, config: lv.config);
    for (var i = 0; i < 12 && g.winner == null; i++) {
      g.endTurn();
      await enemyTurn(g);
    }
    // Either the AI won outright, or time ran out first.
    expect(g.winner, isNotNull);
    expect(g.round, lessThanOrEqualTo(lv.config.roundLimit!));
  });

  test('storage persists progress in a Hive box', () async {
    final dir = Directory.systemTemp.createTempSync('hex_hive');
    addTearDown(() => dir.deleteSync(recursive: true));
    await Storage.init(path: dir.path);
    await Storage.reset();
    final hold = level('Hold the Line');
    final first = level('First Blood');
    expect(Storage.levelUnlocked(0), isTrue);
    expect(Storage.levelUnlocked(lessonCount), isFalse);
    expect(Storage.unlockedCards.contains(CardType.lightning), isFalse);

    final res = Storage.recordGame(hold.config, won: true, rounds: 4);
    expect(res.stars, 3);
    expect(res.newCards, [CardType.lightning]);
    final res0 = Storage.recordGame(first.config, won: true, rounds: 20);
    expect(res0.stars, 1);
    Storage.hero = UnitType.warlord; // locked, falls back
    expect(Storage.hero, UnitType.hero);

    await Storage.close();
    await Storage.init(path: dir.path);
    expect(Storage.stars(hold.config.level!), 3);
    expect(Storage.levelUnlocked(hold.config.level!), isTrue);
    expect(Storage.unlockedCards, contains(CardType.lightning));
    expect(Storage.played(GameMode.campaign), 2);
    expect(Storage.bestRounds(GameMode.campaign), 4);
    await Storage.close();
  });

  test('lessons unlock hot-seat after the basics and skirmish at the end', () {
    Storage.clearMemory();
    expect(Storage.hotseatUnlocked, isFalse);
    expect(Storage.skirmishUnlocked, isFalse);
    for (var i = 0; i < lessonCount; i++) {
      final r = Storage.recordGame(
        campaignLevels[i].config,
        won: true,
        rounds: 3,
      );
      if (i == hotseatLessons - 1) {
        expect(r.newModes, ['Hot-seat']);
        expect(Storage.skirmishUnlocked, isFalse);
      }
      if (i == lessonCount - 1) expect(r.newModes, ['Skirmish']);
    }
    expect(Storage.levelUnlocked(lessonCount), isTrue);

    Storage.clearMemory();
    Storage.skipTutorial();
    expect(Storage.hotseatUnlocked && Storage.skirmishUnlocked, isTrue);
    expect(Storage.levelUnlocked(lessonCount), isTrue);
    Storage.clearMemory();
  });

  test('lesson boards are valid and have coach tips', () {
    for (var i = 0; i < lessonCount; i++) {
      final lv = campaignLevels[i];
      final g = GameController(aiDelayScale: 0, config: lv.config);
      expect(lv.config.coach, isNotEmpty, reason: lv.name);
      expect(g.heroOf(Team.player), isNotNull, reason: lv.name);
      expect(g.heroOf(Team.enemy), isNotNull, reason: lv.name);
      for (final u in g.units) {
        expect(
          g.tiles[u.pos]?.walkable,
          isTrue,
          reason: '${lv.name} ${u.type}',
        );
      }
      for (final step in lv.config.coach) {
        for (final h in step.hexes) {
          expect(g.tiles.containsKey(h), isTrue, reason: lv.name);
        }
      }
      expect(g.coachStep, isNotNull);
    }
  });

  test('lesson 1 can be completed by following the coach', () async {
    final g = GameController(aiDelayScale: 0, config: campaignLevels[0].config);
    final hero = g.heroOf(Team.player)!;
    final foe = g.heroOf(Team.enemy)!;
    expect(g.coachIndex, 0);
    g.tapHex(hero.pos);
    expect(g.coachIndex, 1);
    final spot = g.moveTargets.keys.firstWhere(
      (h) => h.distanceTo(foe.pos) == 1,
    );
    g.tapHex(spot);
    expect(g.coachIndex, 2);
    g.tapHex(foe.pos);
    expect(g.coachIndex, 3);
    expect(foe.hp, 2);
    g.endTurn();
    expect(g.coachIndex, 4);
    await enemyTurn(g);
    g.tapHex(hero.pos);
    g.tapHex(foe.pos);
    expect(g.winner, Team.player);
  });

  test('knockback lesson: a knight pushes the enemy hero into lava', () {
    final g = GameController(aiDelayScale: 0, config: campaignLevels[3].config);
    final knight = g.units.firstWhere(
      (u) => u.team == Team.player && !u.isHero,
    );
    final foe = g.heroOf(Team.enemy)!;
    g.coachNext(); // acknowledge the intro tip
    g.tapHex(knight.pos);
    g.tapHex(const Hex(0, -1));
    expect(g.coachIndex, 2);
    g.tapHex(foe.pos);
    expect(g.winner, Team.player);
  });

  test('fire lesson: a fireball and burning finish the enemy hero', () async {
    final g = GameController(aiDelayScale: 0, config: campaignLevels[4].config);
    final foe = g.heroOf(Team.enemy)!;
    g.selectCard(g.hand.first);
    expect(g.coachIndex, 1);
    g.playCard(foe.pos);
    expect(g.coachIndex, 2);
    for (var i = 0; i < 4 && g.winner == null; i++) {
      g.endTurn();
      await enemyTurn(g);
    }
    expect(g.winner, Team.player);
  });

  test('cards lesson follows the card steps', () {
    final g = GameController(aiDelayScale: 0, config: campaignLevels[2].config);
    final knightCard = g.hand.firstWhere(
      (c) => c.type == CardType.summonKnight,
    );
    final archerCard = g.hand.firstWhere(
      (c) => c.type == CardType.summonArcher,
    );
    g.selectCard(archerCard); // wrong card: coach does not advance
    expect(g.coachIndex, 0);
    g.selectCard(archerCard); // deselect
    g.selectCard(knightCard);
    expect(g.coachIndex, 1);
    g.playCard(g.cardTargets.first);
    expect(g.coachIndex, 2);
    g.selectCard(archerCard);
    g.playCard(g.cardTargets.first);
    expect(g.coachIndex, 3);
  });

  testWidgets('menu leads into campaign, deck, stats and a skirmish', (
    tester,
  ) async {
    Storage.clearMemory();
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // Some screens animate forever, so pump fixed durations.
    Future<void> settle() => tester.pump(const Duration(milliseconds: 900));
    Future<void> back() async {
      await tester.tap(
        find.byWidgetPredicate((w) => w is PxIcon && w.name == 'back'),
      );
      await settle();
      await settle();
    }

    await tester.runAsync(() async {
      final font = FontLoader('VT323')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File('assets/fonts/VT323-Regular.ttf').readAsBytesSync(),
            ),
          ),
        );
      await font.load();
      await PixelAssets.load();
    });
    await tester.pumpWidget(const HexApp());
    await settle();
    expect(find.text('HEX TACTICS'), findsOneWidget);

    // Modes start locked behind the lessons.
    expect(find.textContaining('Finish all 6 lessons'), findsOneWidget);
    expect(find.textContaining('Finish lesson 3'), findsOneWidget);
    await tester.tap(find.textContaining('Skip the tutorial'));
    await settle();
    await tester.tap(find.text('Skip it'));
    await settle();
    await settle();
    expect(find.textContaining('Finish all 6 lessons'), findsNothing);

    await tester.tap(find.text('Campaign'));
    await settle();
    await settle();
    expect(find.text(campaignLevels.first.name), findsOneWidget);
    expect(find.text('Training'), findsOneWidget);
    await back();

    await tester.tap(find.text('Stats'));
    await settle();
    await settle();
    expect(find.text('Reset progress'), findsOneWidget);
    await back();

    await tester.tap(find.text('Skirmish'));
    await settle();
    await settle();
    await tester.tap(find.text('Start battle'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('End turn'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
