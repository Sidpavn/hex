// Dev tool: renders each screen at phone size so the pixel UI can be eyeballed.
// Run with UI_PREVIEW=/some/dir flutter test test/ui_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/game/campaign.dart';
import 'package:hex/game/config.dart';
import 'package:hex/game/hex.dart';
import 'package:hex/game/models.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/campaign_screen.dart';
import 'package:hex/ui/game_screen.dart';
import 'package:hex/ui/menu_screen.dart';
import 'package:hex/ui/inventory_ui.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';
import 'package:hex/ui/setup_screen.dart';
import 'package:hex/ui/stats_screen.dart';
import 'package:hex/ui/chop_overlay.dart';
import 'package:hex/ui/zone_screen.dart';
import 'package:hex/world/quests.dart';
import 'package:hex/world/sim.dart';
import 'package:hex/world/world_state.dart';
import 'package:hex/world/zone.dart';

void main() {
  final dir = Platform.environment['UI_PREVIEW'];

  testWidgets('render screens', (tester) async {
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
    Storage.clearMemory();
    Storage.skipTutorial();
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    Future<void> shot(String name, Widget screen, {int settle = 3}) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: HexApp(home: screen),
        ),
      );
      for (var i = 0; i < settle; i++) {
        await tester.pump(const Duration(milliseconds: 900));
      }
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final img = await boundary.toImage(pixelRatio: 3);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }

    await tester.runAsync(() async {
      await ZoneRepo.load('training');
      await ZoneRepo.load('meadow');
      await ZoneRepo.load('cave');
    });
    await shot('zone_training', const ZoneScreen(), settle: 2);
    // The training post, in reach of a sword.
    {
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: const HexApp(home: ZoneScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      final dynamic st = tester.state(find.byType(ZoneScreen));
      final z = st.zone as Zone;
      final post = z.enemies.firstWhere((e) => e.type == UnitType.post);
      (st.world as WorldState)
        ..addItem('sword')
        ..equipped = 'sword';
      final spot = post.hex.neighbors.firstWhere((h) => z.tiles[h]!.walkable);
      st.sim.hero = spot;
      st.heroWorld = hexWorld(spot);
      st.cam = st.heroWorld;
      st.setState(() {});
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final img = await boundary.toImage(pixelRatio: 3);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File(
          '$dir/zone_post.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
    // A full quick bar, with the quest pointing at the bow.
    {
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: const HexApp(home: ZoneScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      final dynamic st = tester.state(find.byType(ZoneScreen));
      (st.world as WorldState)
        ..quests['training'] = 2
        ..addItem('sword')
        ..autoEquip('sword')
        ..addItem('bow')
        ..autoEquip('bow')
        ..learn('fireball')
        ..learn('mend')
        ..addItem('potion', 2)
        ..addItem('ether');
      st.setState(() {});
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final img = await boundary.toImage(pixelRatio: 3);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$dir/zone_bar.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
    // The cave boss has aimed at the hero.
    {
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: const HexApp(home: ZoneScreen(startZone: 'cave')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      final dynamic st = tester.state(find.byType(ZoneScreen));
      final sim = st.sim as ZoneSim;
      final boss = sim.enemies.firstWhere((e) => e.type == UnitType.pyromancer);
      final spot = [
        for (final h in sim.zone.tiles.keys)
          if (sim.zone.tiles[h]!.walkable &&
              h.distanceTo(boss.hex) == 4 &&
              sim.lineOfSight(h, boss.hex))
            h,
      ].first;
      sim.hero = spot;
      for (var i = 0; i < 8 && boss.telegraph.isEmpty; i++) {
        sim.wait();
      }
      st.heroWorld = hexWorld(sim.hero);
      st.cam = st.heroWorld;
      st.afterTurn(sim);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 130));
      }
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final img = await boundary.toImage(pixelRatio: 3);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File(
          '$dir/zone_boss.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
    await shot('zone_meadow', const ZoneScreen(startZone: 'meadow'), settle: 2);
    await shot(
      'zone_chop',
      Scaffold(
        body: Stack(
          children: [ChopOverlay(onDone: (_) {}, onCancel: () {})],
        ),
      ),
      settle: 1,
    );
    // Beside the first broken bridge with the hatchet and some wood.
    {
      final key = GlobalKey();
      final w = WorldState()
        ..addItem('hatchet')
        ..addItem('wood', 3);
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: HexApp(
            home: ZoneScreen(startZone: 'meadow', world: w),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      final dynamic st = tester.state(find.byType(ZoneScreen));
      final sim = st.sim as ZoneSim;
      sim.enemies.clear();
      final bridge = sim.source.bridges.first;
      final stand = bridge.first.neighbors.firstWhere(
        (h) => sim.zone.tiles[h]?.walkable ?? false,
      );
      sim.hero = stand;
      st.heroWorld = hexWorld(stand);
      st.cam = st.heroWorld;
      st.afterTurn(sim);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 130));
      }
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final img = await boundary.toImage(pixelRatio: 3);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File(
          '$dir/zone_bridge.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
    // An enemy has just noticed the hero.
    {
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: const HexApp(home: ZoneScreen(startZone: 'meadow')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      final dynamic st = tester.state(find.byType(ZoneScreen));
      final z = st.zone as Zone;
      final archer = z.enemies.firstWhere((e) => e.type == UnitType.archer);
      final spot = Hex(archer.hex.q - 3, archer.hex.r);
      st.sim.hero = spot;
      st.heroWorld = hexWorld(spot);
      st.cam = st.heroWorld;
      st.sim.wait();
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final img = await boundary.toImage(pixelRatio: 3);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File(
          '$dir/zone_alert.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
    // Mara, the camp, the HUD, a dialogue, the camp menu and spell targeting.
    {
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: const HexApp(home: ZoneScreen(startZone: 'meadow')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      final dynamic st = tester.state(find.byType(ZoneScreen));
      final z = st.zone as Zone;
      final camp = z.camps.first;
      final mara = z.npcs.first;
      Future<void> grab(String name) async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final img = await boundary.toImage(pixelRatio: 3);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }

      st.sim.hero = Hex(camp.q + 1, camp.r);
      st.heroWorld = hexWorld(st.sim.hero as Hex);
      st.cam = st.heroWorld;
      st.setState(() {});
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      await grab('zone_camp');
      st.dialogue = talkTo(mara, st.world as WorldState);
      st.talking = mara;
      st.setState(() {});
      await tester.pump(const Duration(milliseconds: 300));
      await grab('zone_dialogue');
      st.dialogue = null;
      st.talking = null;
      (st.world as WorldState).quests['lantern'] = 1;
      st.campOpen = true;
      st.world.tokens = 2;
      st.setState(() {});
      await tester.pump(const Duration(milliseconds: 300));
      await grab('zone_campmenu');
      st.campOpen = false;
      st.targeting = true;
      st.setState(() {});
      await tester.pump(const Duration(milliseconds: 300));
      await grab('zone_spell');
      st.targeting = false;
      // The pack: give the hero some gear, then look at a weapon.
      final world = st.world as WorldState;
      world.tokens = 3;
      world.addItem('axe');
      world.addItem('spear');
      world.addItem('dagger');
      world.addItem('ether', 2);
      world.addItem('lantern');
      world.learn('mend');
      world.hp = 5;
      st.packOpen = true;
      st.packAtCamp = true;
      st.setState(() {});
      await tester.pump(const Duration(milliseconds: 300));
      await grab('pack_empty');
      await tester.tap(find.byType(ItemSlot).at(10)); // first bag slot (potion)
      await tester.pump(const Duration(milliseconds: 200));
      await grab('pack_potion');
      await tester.tap(find.byType(ItemSlot).at(11)); // the axe
      await tester.pump(const Duration(milliseconds: 200));
      await grab('pack_weapon');
      await tester.tap(find.byType(ItemSlot).at(8)); // spell slot 1
      await tester.pump(const Duration(milliseconds: 200));
      await grab('pack_spell');
    }
    // Combat feedback: a sword swing, an archer's aim, a fireball in flight.
    {
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: const HexApp(home: ZoneScreen(startZone: 'meadow')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      final dynamic st = tester.state(find.byType(ZoneScreen));
      final z = st.zone as Zone;
      final knight = z.enemies.firstWhere((e) => e.type == UnitType.knight);
      final archer = z.enemies.firstWhere((e) => e.type == UnitType.archer);
      Future<void> grab(String name) async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final img = await boundary.toImage(pixelRatio: 3);
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }

      void place(Hex h) {
        st.sim.hero = h;
        st.heroWorld = hexWorld(h);
        st.cam = st.heroWorld;
      }

      // 1) the archer has noticed us and has us in range: aim line + reticle.
      for (final e in st.sim.enemies) {
        if (e.type == UnitType.archer) {
          e.awareness = Awareness.alert;
          place(Hex(e.hex.q - 3, e.hex.r));
        }
      }
      await tester.pump(const Duration(milliseconds: 250));
      await grab('fx_aim');

      // 2) a bow shot in flight.
      st.world.equipped = 'bow';
      final foe = (st.sim.enemies as List).firstWhere(
        (e) => e.type == UnitType.archer,
      );
      st.sim.attack(foe);
      st.afterTurn(st.sim);
      await tester.pump(const Duration(milliseconds: 100));
      await grab('fx_arrow');
      await tester.pump(const Duration(milliseconds: 900));

      // 3) a sword swing at the knight.
      st.world.equipped = 'sword';
      for (final e in st.sim.enemies) {
        if (e.type == UnitType.knight && e.hex == knight.hex) {
          e.awareness = Awareness.alert;
          place(Hex(e.hex.q - 1, e.hex.r));
          await tester.pump(const Duration(milliseconds: 100));
          st.sim.attack(e);
          st.afterTurn(st.sim);
          await tester.pump(const Duration(milliseconds: 70));
          await grab('fx_swing');
          break;
        }
      }
      await tester.pump(const Duration(milliseconds: 900));

      // 4) a fireball in flight and then exploding.
      place(Hex(archer.hex.q - 6, archer.hex.r + 3));
      st.sim.world.mana = 4;
      final target = Hex(archer.hex.q - 3, archer.hex.r + 3);
      st.sim.castFireball(target);
      st.afterTurn(st.sim);
      await tester.pump(const Duration(milliseconds: 180));
      await grab('fx_fireball');
      await tester.pump(const Duration(milliseconds: 250));
      await grab('fx_explosion');
    }
    await shot('zone_cave', const ZoneScreen(startZone: 'cave'), settle: 2);
    await shot('menu', const MenuScreen());
    await shot('campaign', const CampaignScreen());
    await shot('setup', const SetupScreen(mode: GameMode.skirmish));
    await shot('stats', const StatsScreen());
    await shot(
      'game',
      GameScreen(config: Storage.configFor(campaignLevels[2])),
      settle: 4,
    );
    // A full six-card hand overlaps instead of shrinking.
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: HexApp(
          home: GameScreen(config: Storage.configFor(campaignLevels[2])),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 900));
    final dynamic game =
        (tester.state(find.byType(GameScreen)) as dynamic).game;
    final base = game.hand.length as int;
    final types = CardType.values;
    for (var i = base; i < 6; i++) {
      game.hand.add(GameCard(100 + i, types[i + 2]));
    }
    game.selectedCard = game.hand[2];
    game.notifyListeners();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 900));
    }
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final img = await boundary.toImage(pixelRatio: 3);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/hand.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    await tester.pumpWidget(const SizedBox());
  }, skip: dir == null);
}
