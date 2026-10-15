// Dev tool: renders the diner to a PNG so the pixel art can be eyeballed.
// Run with DINER_PREVIEW=/path/out.png flutter test test/diner_preview_test.dart
// DINER_SCREEN=/path/out.png renders the whole build screen.
// SECONDS=n lets the diner run n seconds first.
// Add GRID=1 for the build-mode grid, PLACE=1 for a placement ghost, PLACE=bad for a refused one.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/diner/actor.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/diner_painter.dart';
import 'package:hex/diner/iso.dart';

void main() {
  final out = Platform.environment['DINER_PREVIEW'];

  testWidgets('render diner preview', (tester) async {
    await tester.runAsync(() async {
      final art = await DinerArt.load();
      final empty = Platform.environment['EMPTY'] != null;
      final diner = empty ? Diner(coins: 0) : Diner.starter();
      const dpr = 3.0;
      const size = ui.Size(232, 176);
      final fit = BoardFit.of(diner, size, dpr);
      final rec = ui.PictureRecorder();
      final canvas = ui.Canvas(rec)..scale(dpr);
      DinerPainter(
        diner: diner,
        art: art,
        fit: fit,
        grid: Platform.environment['GRID'] != null,
        placing: Platform.environment['PLACE'] == null ? null : Kind.jukebox,
        hover: Platform.environment['PLACE'] == 'bad'
            ? const Cell(4, 4)
            : const Cell(5, 7),
        selected: diner.objectAt(const Cell(2, 3)),
        actors: empty
            ? []
            : [
                Actor.at('chef', const Cell(2, 4), dir: Dir.ne, frame: 's0'),
                Actor.at('cust_a', const Cell(3, 6), dir: Dir.se, frame: '0'),
                Actor.at('cust_b', const Cell(4, 4), dir: Dir.nw, frame: '1'),
                Actor.at('cust_c', const Cell(5, 6), dir: Dir.sw, frame: 's0'),
              ],
      ).paint(canvas, size);
      final img = await rec.endRecording().toImage(
        (size.width * dpr).round(),
        (size.height * dpr).round(),
      );
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File(out!).writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }, skip: out == null);

  final screen = Platform.environment['DINER_SCREEN'];

  testWidgets('render build screen', (tester) async {
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
      await DinerArt.load();
    });
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: HexApp(home: BuildScreen(diner: Diner.starter())),
      ),
    );
    await tester.pump();
    final secs = int.tryParse(Platform.environment['SECONDS'] ?? '') ?? 0;
    for (var i = 0; i < secs * 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (Platform.environment['PLACE'] != null) {
      await tester.tap(find.byKey(const ValueKey('fixture-jukebox')));
      await tester.pump();
    }
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await boundary.toImage(pixelRatio: 1);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File(screen!).writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }, skip: screen == null);
}
