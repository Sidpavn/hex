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
import 'package:hex/diner/recipes.dart';
import 'package:hex/diner/staff.dart';
import 'package:hex/diner/traits.dart';

Diner _full() {
  final d = Diner(
    coins: 9999,
    owned: {0, 1},
    progress: Progress(level: 7, reputation: 75),
  );
  d.progress.upgrades[Upgrade.staff] = 2;
  d.roster.employees
    ..clear()
    ..addAll([
      Staff(
        id: 1,
        name: 'Sam',
        stats: {Stat.cooking: 6, Stat.speed: 6, Stat.service: 5, Stat.charm: 4},
        potential: {for (final s in Stat.values) s: 9},
        specialty: Dish.pizza,
        mastery: {Dish.burger: 30},
        traits: [Trait.loyal],
        known: {Trait.loyal},
      ),
      Staff(
        id: 2,
        name: 'Cleo',
        stats: {Stat.cooking: 3, Stat.speed: 7, Stat.service: 7, Stat.charm: 6},
        potential: {for (final s in Stat.values) s: 9},
        duty: Kind.window,
      ),
      Staff(
        id: 3,
        name: 'Gio',
        stats: {Stat.cooking: 5, Stat.speed: 5, Stat.service: 5, Stat.charm: 5},
        potential: {for (final s in Stat.values) s: 9},
        specialty: Dish.coffee,
      ),
    ]);
  d
    ..place(Kind.grill, const Cell(1, 3), Dir.sw)
    ..place(Kind.fryer, const Cell(2, 3), Dir.sw)
    ..place(Kind.soda, const Cell(3, 3), Dir.sw)
    ..place(Kind.espresso, const Cell(4, 3), Dir.sw)
    ..place(Kind.oven, const Cell(5, 3), Dir.sw)
    ..place(Kind.freezer, const Cell(6, 3), Dir.sw)
    ..place(Kind.counter, const Cell(8, 6), Dir.nw)
    ..place(Kind.counter, const Cell(8, 7), Dir.nw);
  d.place(Kind.window, Cell(d.right, 4));
  for (final t in const [Cell(3, 5), Cell(6, 5), Cell(5, 7), Cell(9, 7)]) {
    d
      ..place(Kind.table, t)
      ..place(Kind.chair, Cell(t.x - 1, t.y), Dir.se)
      ..place(Kind.chair, Cell(t.x + 1, t.y), Dir.nw);
  }
  if (const ['hiring', 'hired'].contains(Platform.environment['STAFF'])) {
    d.progress.upgrades[Upgrade.staff] = 3;
  }
  d.menu();
  d.declined.add(Dish.cheeseburger);
  d.offered
    ..clear()
    ..addAll([Dish.burger, Dish.pizza, Dish.fries, Dish.coffee, Dish.iceCream]);
  return d;
}

Diner _story() {
  final d = Diner.starter()..progress.reputation = 85;
  d.roster.employees
    ..clear()
    ..add(
      Staff(
        id: 3,
        name: 'Ben',
        stats: {Stat.cooking: 5, Stat.speed: 5, Stat.service: 4, Stat.charm: 6},
        potential: {for (final s in Stat.values) s: 8},
        traits: [Trait.cheerful, Trait.clumsy],
        known: {Trait.cheerful},
        memories: ['Day 2: dropped Marge\'s burger', 'Day 1: Joe tipped 4'],
        morale: Platform.environment['SAD'] != null ? 1 : 2,
        lastPay: Platform.environment['SAD'] != null ? Pay.missed : Pay.paid,
      ),
    );
  d.progress.upgrades[Upgrade.staff] = 1;
  d.roster.employees.add(
    Staff(
      id: 4,
      name: 'Cleo',
      stats: {Stat.cooking: 3, Stat.speed: 6, Stat.service: 6, Stat.charm: 5},
      potential: {for (final s in Stat.values) s: 8},
      traits: [Trait.quickHands],
      known: {Trait.quickHands},
      lastPay: Pay.paid,
    ),
  );
  if (Platform.environment['SAD'] != null) d.coins = 6;
  d.progress.day = 3;
  return d;
}

Diner _big() {
  if (Platform.environment['STORY'] != null) return _story();
  if (Platform.environment['FULL'] != null) return _full();
  final d = Diner.starter();
  final rep = int.tryParse(Platform.environment['REP'] ?? '');
  if (rep != null) d.progress.reputation = rep;
  if (Platform.environment['BIG'] != null) {
    d.coins = 100000;
    d.progress.level = 9;
    d.owned.addAll({1, 2, 3, 4, 5});
    d
      ..place(Kind.table, const Cell(3, -3))
      ..place(Kind.chair, const Cell(2, -3), Dir.se)
      ..place(Kind.chair, const Cell(4, -3), Dir.nw)
      ..place(Kind.table, const Cell(7, -5))
      ..place(Kind.chair, const Cell(6, -5), Dir.se)
      ..place(Kind.chair, const Cell(8, -5), Dir.nw)
      ..place(Kind.jukebox, const Cell(9, 0))
      ..place(Kind.plant, const Cell(1, 0));
  }
  return d;
}

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
        child: HexApp(home: BuildScreen(diner: _big())),
      ),
    );
    await tester.pump();
    if (Platform.environment['START'] != null) {
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump();
    }
    if (Platform.environment['SPEED'] != null) {
      await tester.tap(
        find.byKey(ValueKey('speed-${Platform.environment['SPEED']}')),
      );
      await tester.pump();
    }
    final secs = int.tryParse(Platform.environment['SECONDS'] ?? '') ?? 0;
    for (var i = 0; i < secs * 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    for (
      var i = 0;
      i < (int.tryParse(Platform.environment['ZOOM'] ?? '') ?? 0);
      i++
    ) {
      await tester.tap(find.byKey(const ValueKey('zoom-in')));
      await tester.pump();
    }
    final move = Platform.environment['MOVE'];
    if (move != null) {
      final b = find.byKey(const ValueKey('diner-board'));
      final f = (tester.widget<CustomPaint>(b).painter! as DinerPainter).fit;
      Offset at(Cell c) =>
          tester.getTopLeft(b) + f.view.vertex(c.x + 0.5, c.y + 0.5) * f.s;
      await tester.tapAt(at(const Cell(1, 3)));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('move')));
      await tester.pump();
      final parts = move.split(',');
      final g = await tester.startGesture(
        at(Cell(int.parse(parts[0]), int.parse(parts[1]))),
      );
      await g.moveBy(const Offset(0, 30));
      await tester.pump();
      await g.moveBy(const Offset(0, -30));
      await tester.pump();
    }
    if (Platform.environment['STAFF'] != null) {
      await tester.tap(find.byKey(const ValueKey('staff')));
      await tester.pumpAndSettle();
      final scroll = int.tryParse(Platform.environment['STAFF']!) ?? 0;
      if (scroll > 0) {
        await tester.drag(find.byType(ListView), Offset(0, -scroll.toDouble()));
        await tester.pumpAndSettle();
      }
    }
    final deeper = Platform.environment['STAFF'];
    if (const ['person', 'training', 'hiring', 'hired'].contains(deeper)) {
      // STAFF=person, training, hiring, hired (after placing an advert)
      if (deeper == 'hiring' || deeper == 'hired') {
        await tester.tap(find.byKey(const ValueKey('hire')));
        await tester.pumpAndSettle();
        if (deeper == 'hired') {
          await tester.tap(find.byKey(const ValueKey('advertise-paper')));
          await tester.pumpAndSettle();
        }
      } else {
        await tester.tap(find.byKey(const ValueKey('team-1')));
        await tester.pumpAndSettle();
        if (deeper == 'training') {
          await tester.tap(find.byKey(const ValueKey('open-training-1')));
          await tester.pumpAndSettle();
        }
      }
    }
    if (Platform.environment['MENU'] != null) {
      await tester.tap(find.byKey(const ValueKey('menu')));
      await tester.pumpAndSettle();
      final scroll = int.tryParse(Platform.environment['MENU']!) ?? 0;
      if (scroll > 0) {
        await tester.drag(find.byType(ListView), Offset(0, -scroll.toDouble()));
        await tester.pumpAndSettle();
      }
      if (Platform.environment['MENU'] == 'dish') {
        await tester.tap(find.byKey(const ValueKey('dish-pizza')));
        await tester.pumpAndSettle();
      }
      if (Platform.environment['MENU'] == 'prep') {
        await tester.tap(find.byKey(const ValueKey('open-prep')));
        await tester.pumpAndSettle();
      }
    }
    if (Platform.environment['EXPAND'] != null) {
      await tester.tap(find.byKey(const ValueKey('expand')));
      await tester.pumpAndSettle();
    }
    if (Platform.environment['UPGRADES'] != null) {
      await tester.tap(find.byKey(const ValueKey('upgrades')));
      await tester.pumpAndSettle();
    }
    if (Platform.environment['PLACE'] != null) {
      final k = ValueKey('fixture-${Platform.environment['PLACE']}');
      await tester.ensureVisible(find.byKey(k));
      await tester.tap(find.byKey(k));
      await tester.pump();
      final board = find.byKey(const ValueKey('diner-board'));
      final g = await tester.startGesture(tester.getCenter(board));
      await g.moveBy(const Offset(4, 6));
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
