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
import 'package:hex/game/models.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/campaign_screen.dart';
import 'package:hex/ui/game_screen.dart';
import 'package:hex/ui/menu_screen.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';
import 'package:hex/ui/setup_screen.dart';
import 'package:hex/ui/stats_screen.dart';

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
