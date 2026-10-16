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

void main() {
  group('BoardFit', () {
    const canvas = Size(390, 560);

    test('starts with the whole room centred and can only zoom in', () {
      final fit = BoardFit.of(Diner.starter(), canvas, 3);
      expect(fit.k, fit.kFit);
      expect(fit.zoomed, isFalse);
      expect(fit.kMax, greaterThan(fit.kFit));
      // Asking for less than the whole room is not allowed.
      expect(BoardFit.of(Diner.starter(), canvas, 3, k: 1).k, fit.kFit);
      expect(BoardFit.of(Diner.starter(), canvas, 3, k: 99).k, fit.kMax);
    });

    test('the scale is always a whole number of device pixels', () {
      for (var k = 1; k <= 12; k++) {
        final fit = BoardFit.of(Diner.starter(), canvas, 3, k: k);
        expect((fit.s * 3 - fit.s * 3.round()).abs() < 1e-9, isTrue);
        expect(fit.s * 3, closeTo(fit.k.toDouble(), 1e-9));
      }
    });

    test('the room cannot be dragged off the screen', () {
      final d = Diner.starter();
      final big = BoardFit.of(
        d,
        canvas,
        3,
        k: 12,
        focus: const Offset(-999, -999),
      );
      final far = BoardFit.of(
        d,
        canvas,
        3,
        k: 12,
        focus: const Offset(9999, 9999),
      );
      final room = IsoView(d);
      // At the extremes the view is within a little of the room's edge.
      expect(big.focus.dx, lessThan(room.width / 2));
      expect(far.focus.dx, greaterThan(room.width / 2));
      expect(big.focus.dx, greaterThan(-1));
      expect(far.focus.dx, lessThan(room.width + 1));
    });

    test('at full size the view stays centred whatever it is asked for', () {
      final d = Diner.starter();
      final a = BoardFit.of(d, canvas, 3);
      final b = BoardFit.of(d, canvas, 3, focus: const Offset(5, 5));
      expect(b.focus, a.focus);
      expect(b.view.shift, a.view.shift);
    });

    test('a tap lands on the right cell at any zoom', () {
      final d = Diner.starter();
      for (final k in [null, 6, 9, 12]) {
        final fit = BoardFit.of(d, canvas, 3, k: k);
        const c = Cell(3, 5);
        final p = fit.view.vertex(c.x + 0.5, c.y + 0.5);
        expect(fit.view.cellAt(p), c, reason: 'k=$k');
      }
    });

    test('zooming about a point keeps that point still', () {
      final d = Diner.starter();
      final a = BoardFit.of(d, canvas, 3);
      // The room point at the top-right of the middle of the screen.
      const dxy = Offset(10, -8);
      final anchor = a.focus + dxy / a.s;
      final b = BoardFit.of(
        d,
        canvas,
        3,
        k: a.k + 3,
        focus: anchor - dxy / ((a.k + 3) / 3),
      );
      final screenA =
          Offset(canvas.width / 2, canvas.height / 2) +
          (anchor - a.focus) * a.s;
      final screenB =
          Offset(canvas.width / 2, canvas.height / 2) +
          (anchor - b.focus) * b.s;
      expect((screenA - screenB).distance, lessThan(2));
    });
  });

  group('build screen', () {
    Future<Diner> open(WidgetTester tester) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
      });
      Storage.clearMemory();
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final diner = Diner.starter()..coins = 500;
      await tester.pumpWidget(HexApp(home: BuildScreen(diner: diner)));
      await tester.pump();
      return diner;
    }

    final board = find.byKey(const ValueKey('diner-board'));
    DinerPainter painter(WidgetTester tester) =>
        tester.widget<CustomPaint>(board).painter! as DinerPainter;
    BoardFit fit(WidgetTester tester) => painter(tester).fit;

    testWidgets('the zoom buttons step in and out', (tester) async {
      await open(tester);
      final start = fit(tester).k;
      // Nothing to zoom out to yet.
      await tester.tap(find.byKey(const ValueKey('zoom-out')));
      await tester.pump();
      expect(fit(tester).k, start);

      await tester.tap(find.byKey(const ValueKey('zoom-in')));
      await tester.pump();
      final once = fit(tester).k;
      expect(once, greaterThan(start));
      await tester.tap(find.byKey(const ValueKey('zoom-in')));
      await tester.pump();
      expect(fit(tester).k, greaterThan(once));

      for (var i = 0; i < 8; i++) {
        await tester.tap(find.byKey(const ValueKey('zoom-out')));
        await tester.pump();
      }
      expect(fit(tester).k, start, reason: 'back to the whole room');
    });

    testWidgets('pinching zooms and dragging moves the view', (tester) async {
      await open(tester);
      final start = fit(tester);
      final c = tester.getCenter(board);

      final a = await tester.startGesture(c - const Offset(20, 0), pointer: 1);
      final b = await tester.startGesture(c + const Offset(20, 0), pointer: 2);
      await a.moveBy(const Offset(-30, 0));
      await b.moveBy(const Offset(30, 0));
      await tester.pump();
      await a.moveBy(const Offset(-30, 0));
      await b.moveBy(const Offset(30, 0));
      await tester.pump();
      await a.up();
      await b.up();
      await tester.pump();
      final zoomed = fit(tester);
      expect(zoomed.k, greaterThan(start.k));

      await tester.dragFrom(c, const Offset(-80, 0));
      await tester.pump();
      expect(
        fit(tester).focus.dx,
        greaterThan(zoomed.focus.dx),
        reason: 'dragging left shows what is to the right',
      );
    });

    testWidgets('placing works while zoomed in', (tester) async {
      final diner = await open(tester);
      await tester.tap(find.byKey(const ValueKey('zoom-in')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('fixture-table')));
      await tester.tap(find.byKey(const ValueKey('fixture-table')));
      await tester.pump();

      final f = fit(tester);
      // Aim at the cell nearest the middle of the view.
      final mid = tester.getSize(board).center(Offset.zero);
      final target = f.view.cellAt(mid / f.s);
      final result = diner.check(Kind.table, target);
      final before = diner.items.length;
      await tester.tapAt(tester.getTopLeft(board) + mid);
      await tester.pump();
      expect(
        diner.items.length,
        result == PlaceResult.ok ? before + 1 : before,
      );
    });

    testWidgets('expanding the room goes back to the whole room', (
      tester,
    ) async {
      final d = await open(tester);
      d.coins = 5000;
      d.progress.level = 9;
      await tester.tap(find.byKey(const ValueKey('zoom-in')));
      await tester.pump();
      expect(fit(tester).zoomed, isTrue);
      await tester.tap(find.byKey(const ValueKey('expand')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plot-1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('buy-plot')));
      await tester.pump();
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pump(const Duration(milliseconds: 500));
      expect(fit(tester).zoomed, isFalse);
    });

    testWidgets('the ground is drawn once while the diner runs', (
      tester,
    ) async {
      await open(tester);
      final layer = painter(tester).layer;
      final before = layer.builds;
      // Half a minute of customers, payments and rebuilds.
      for (var i = 0; i < 300; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        layer.builds,
        before,
        reason: 'screen rebuilds must reuse the cached ground',
      );
    });
  });
}
