// Choosing a section of the plot: a flat tint on the ground says which ones
// can be bought and which is picked, and a short flash marks a pick or a buy.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/diner_painter.dart';
import 'package:hex/diner/iso.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';
import 'support/office.dart';

void main() {
  const size = ui.Size(390, 560);
  const dpr = 3.0;

  /// The picture of [d], and a way to read the ground colour at a cell.
  Future<(Uint8List, int Function(Cell, int))> shot(
    DinerArt art,
    Diner d, {
    bool expanding = false,
    int? sel,
    int? flashPlot,
    int flash = 0,
  }) async {
    final fit = BoardFit.of(d, size, dpr, whole: expanding);
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec)..scale(dpr);
    DinerPainter(
      diner: d,
      art: art,
      fit: fit,
      expanding: expanding,
      plotSel: sel,
      flashPlot: flashPlot,
      flash: flash,
    ).paint(canvas, size);
    final image = await rec.endRecording().toImage(
      (size.width * dpr).round(),
      (size.height * dpr).round(),
    );
    final px = (await image.toByteData())!.buffer.asUint8List();
    final w = image.width;
    int at(Cell c, int channel) {
      final v = fit.view.vertex(c.x + 0.5, c.y + 0.5) * fit.s * dpr;
      return px[(v.dy.round() * w + v.dx.round()) * 4 + channel];
    }

    return (px, at);
  }

  /// How far the colour at [c] has moved from [base]'s.
  int shift(
    (Uint8List, int Function(Cell, int)) a,
    (Uint8List, int Function(Cell, int)) base,
    Cell c,
  ) {
    var d = 0;
    for (var ch = 0; ch < 3; ch++) {
      d += (a.$2(c, ch) - base.$2(c, ch)).abs();
    }
    return d;
  }

  group('the tint', () {
    testWidgets(
      'sections to buy are tinted, the one picked more, the rest not',
      (tester) async {
        await tester.runAsync(() async {
          final art = await DinerArt.load();
          final d = Diner(coins: 0);
          // The same view each time, so only the tint can differ.
          final plain = await shot(art, d, expanding: true);
          final picked = await shot(art, d, expanding: true, sel: 1);
          const next = Cell(3, 0); // room behind: can be bought next
          const picks = Cell(8, 5); // room to the right: picked below
          const later = Cell(8, 0); // room behind, right: not yet
          // Without a pick, both buyable sections are lightly tinted.
          final none = await shot(art, d, expanding: true, sel: 99);
          expect(shift(none, plain, next), 0);
          // Picking one makes it clearly stronger than the other.
          final strong = shift(picked, none, picks);
          expect(strong, greaterThan(0), reason: 'the pick is tinted more');
          expect(
            shift(picked, none, next),
            0,
            reason: 'the other is unchanged',
          );
          expect(shift(picked, none, later), 0, reason: 'later ones are plain');
          // A buyable section has its own tint even with nothing picked: a
          // fully bought plot has none, so the same cell is different.
          final bought = Diner(coins: 0, owned: {0, 1, 2, 3, 4, 5});
          final whole = await shot(art, bought, expanding: true);
          expect(whole.$1.isNotEmpty, isTrue);
        });
      },
    );

    testWidgets('a section that is not yet buyable is never tinted', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final art = await DinerArt.load();
        final d = Diner(coins: 0);
        final view = BoardFit.of(d, size, dpr, whole: true);
        expect(view.view.height, greaterThan(0));
        final expandedPlain = await shot(art, d, expanding: true, sel: 99);
        final expandedPick = await shot(art, d, expanding: true, sel: 3);
        // Section 3 is not next to buy, but a pick on it shows as picked.
        expect(
          shift(expandedPick, expandedPlain, const Cell(8, 0)),
          greaterThan(0),
          reason: 'a pick always shows',
        );
        // Outside any section, nothing changes.
        expect(shift(expandedPick, expandedPlain, const Cell(-5, 5)), 0);
      });
    });

    testWidgets('the tint is flat: one colour across the section', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final art = await DinerArt.load();
        final d = Diner(coins: 0);
        final base = await shot(art, d, expanding: true, sel: 99);
        final picked = await shot(art, d, expanding: true, sel: 1);
        final a = shift(picked, base, const Cell(8, 4));
        final b = shift(picked, base, const Cell(9, 6));
        expect((a - b).abs(), lessThanOrEqualTo(6), reason: 'no gradient');
      });
    });

    testWidgets('and the board does not tint outside the expand mode', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final art = await DinerArt.load();
        final d = Diner(coins: 0);
        final a = await shot(art, d, sel: 1);
        final b = await shot(art, d);
        expect(a.$1, b.$1, reason: 'a pick means nothing outside the mode');
      });
    });
  });

  group('the flash', () {
    testWidgets('it brightens the section in steps and ends back at the tint', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final art = await DinerArt.load();
        final d = Diner(coins: 0);
        const at = Cell(8, 5);
        final rest = await shot(art, d, expanding: true, sel: 1);
        final steps = <int>[];
        for (final f in [0, 1, 2, 3]) {
          final one = await shot(
            art,
            d,
            expanding: true,
            sel: 1,
            flashPlot: 1,
            flash: f,
          );
          steps.add(shift(one, rest, at));
        }
        expect(steps.first, 0, reason: 'step 0 is the plain tint');
        expect(steps[1], greaterThan(steps[0]));
        expect(steps[2], greaterThan(steps[1]));
        expect(steps[3], greaterThan(steps[2]));
      });
    });

    testWidgets('it only touches the section that flashed', (tester) async {
      await tester.runAsync(() async {
        final art = await DinerArt.load();
        final d = Diner(coins: 0);
        final rest = await shot(art, d, expanding: true, sel: 1);
        final lit = await shot(
          art,
          d,
          expanding: true,
          sel: 1,
          flashPlot: 1,
          flash: 3,
        );
        expect(shift(lit, rest, const Cell(3, 0)), 0);
        expect(shift(lit, rest, const Cell(3, 5)), 0);
      });
    });

    testWidgets('a bought section flashes too, over its new floor', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final art = await DinerArt.load();
        final d = Diner(coins: 0, owned: {0, 1});
        final rest = await shot(art, d, expanding: true);
        final lit = await shot(art, d, expanding: true, flashPlot: 1, flash: 3);
        expect(shift(lit, rest, const Cell(8, 5)), greaterThan(0));
      });
    });
  });

  group('on screen', () {
    final board = find.byKey(const ValueKey('diner-board'));

    Future<Diner> open(WidgetTester tester) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
      });
      Storage.clearMemory();
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final d = Diner.starter()
        ..coins = 5000
        ..progress.level = 9;
      await tester.pumpWidget(HexApp(home: BuildScreen(diner: d)));
      await tester.pump();
      return d;
    }

    DinerPainter painter(WidgetTester tester) =>
        tester.widget<CustomPaint>(board).painter! as DinerPainter;

    Offset onCell(WidgetTester tester, Cell c) {
      final f = painter(tester).fit;
      return tester.getTopLeft(board) +
          f.view.vertex(c.x + 0.5, c.y + 0.5) * f.s;
    }

    testWidgets('tapping a section lights it, then it settles in a moment', (
      tester,
    ) async {
      await open(tester);
      await openApp(tester, 'expand');
      await tester.tapAt(onCell(tester, const Cell(3, 0)));
      await tester.pump();
      expect(painter(tester).flashPlot, 2);
      expect(painter(tester).flash, 3);
      final seen = <int>[];
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        seen.add(painter(tester).flash);
      }
      expect(seen, [2, 1, 0, 0, 0, 0]);
      expect(painter(tester).plotSel, 2, reason: 'still picked, still tinted');
    });

    testWidgets('buying flashes the new floor, and only for a moment', (
      tester,
    ) async {
      await open(tester);
      await openApp(tester, 'expand');
      await tester.tap(find.byKey(const ValueKey('buy-plot')));
      await tester.pump();
      expect(painter(tester).flashPlot, 1);
      expect(painter(tester).flash, 3);
      await tester.pump(const Duration(milliseconds: 500));
      expect(painter(tester).flash, 0);
    });

    testWidgets('nothing flashes when the mode is left', (tester) async {
      await open(tester);
      await openApp(tester, 'expand');
      await tester.tap(find.byKey(const ValueKey('done-expanding')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(painter(tester).flash, 0);
      expect(painter(tester).expanding, isFalse);
    });
  });
}
