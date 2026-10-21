// Frame cost of the diner painter, recorded without a GPU. It prints the
// numbers; the assertions only guard the caching that makes them small.
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:hex/diner/clock.dart';
import 'package:hex/diner/city.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/diner_painter.dart';
import 'package:hex/diner/iso.dart';
import 'package:hex/diner/service.dart';

void main() {
  testWidgets('painter frame cost', (tester) async {
    await tester.runAsync(() async {
      final art = await DinerArt.load();
      final diner = Diner.starter();
      final sim = DinerSim(diner);
      for (var i = 0; i < 120; i++) {
        sim.tick();
      }
      const size = ui.Size(390, 560);
      const dpr = 3.0;
      final fit = BoardFit.of(diner, size, dpr);
      final clock = TickClock(sim.tick);
      final painter = DinerPainter(
        diner: diner,
        art: art,
        fit: fit,
        sim: sim,
        clock: clock,
      );

      void frame() {
        final rec = ui.PictureRecorder();
        painter.paint(ui.Canvas(rec), size);
        rec.endRecording().dispose();
      }

      for (var i = 0; i < 20; i++) {
        frame(); // warm up
      }
      final before = painter.blits;
      frame();
      final perFrame = painter.blits - before;
      final watch = Stopwatch()..start();
      const n = 300;
      for (var i = 0; i < n; i++) {
        frame();
      }
      watch.stop();
      final ms = watch.elapsedMicroseconds / n / 1000;
      // ignore: avoid_print
      print(
        'painter: ${ms.toStringAsFixed(3)} ms per frame '
        '(${diner.items.length} fixtures, ${sim.guests.length} guests), '
        '$perFrame images drawn per frame',
      );
    });
  });

  testWidgets('the still layer is built once and rebuilt only on change', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final art = await DinerArt.load();
      final diner = Diner.starter();
      const size = ui.Size(390, 560);
      final fit = BoardFit.of(diner, size, 3);
      final layer = StaticLayer();

      DinerPainter make(int revision, {bool grid = false}) => DinerPainter(
        diner: diner,
        art: art,
        fit: fit,
        layer: layer,
        revision: revision,
        grid: grid,
      );

      void frame(DinerPainter p) {
        final rec = ui.PictureRecorder();
        p.paint(ui.Canvas(rec), size);
        rec.endRecording().dispose();
      }

      // Rebuilding the widget makes a new painter every time; the layer
      // must survive that.
      for (var i = 0; i < 40; i++) {
        frame(make(0));
      }
      expect(layer.builds, 1);
      frame(make(1));
      expect(layer.builds, 2, reason: 'a layout change redraws it');
      frame(make(1, grid: true));
      expect(layer.builds, 3, reason: 'so does showing the grid');
      layer.dispose();
    });
  });

  test('the clock only wakes the painter when something changes', () {
    var moving = false;
    var woken = 0;
    final clock = TickClock(() {}, step: 0.4, animating: () => moving)
      ..addListener(() => woken++);
    clock.advance(0.1);
    clock.advance(0.1);
    expect(woken, 0, reason: 'nothing moving and no tick: no repaint');
    clock.advance(0.3);
    expect(woken, 1, reason: 'a tick is a change');
    moving = true;
    clock.advance(0.05);
    clock.advance(0.05);
    expect(woken, 3, reason: 'while someone walks, every frame');
  });

  testWidgets('sim and loading cost', (tester) async {
    await tester.runAsync(() async {
      final load = Stopwatch()..start();
      await DinerArt.load();
      load.stop();
      final sim = DinerSim(Diner.starter());
      final run = Stopwatch()..start();
      for (var i = 0; i < 5000; i++) {
        sim.tick();
      }
      run.stop();
      // ignore: avoid_print
      print(
        'art load: ${load.elapsedMilliseconds} ms; '
        'sim: ${(run.elapsedMicroseconds / 5000).toStringAsFixed(1)} us per tick',
      );
    });
  });

  testWidgets('the whole town is drawn once, not every frame', (tester) async {
    await tester.runAsync(() async {
      final art = await DinerArt.load();
      final diner = Diner.starter();
      const size = ui.Size(390, 780);
      final fit = BoardFit.of(diner, size, 3);
      final layer = StaticLayer();

      int frame() {
        final p = DinerPainter(
          diner: diner,
          art: art,
          fit: fit,
          layer: layer,
          revision: 1,
        );
        final rec = ui.PictureRecorder();
        p.paint(ui.Canvas(rec), size);
        rec.endRecording().dispose();
        return p.blits;
      }

      final first = frame();
      final next = frame();
      // The first frame draws the ground, every building and everything
      // small; the next only draws what moves.
      expect(
        first - next,
        greaterThanOrEqualTo(buildings.length + scenery.length ~/ 2),
        reason: 'the town is in the cached picture',
      );
      expect(next, lessThan(60), reason: 'a quiet frame draws few images');
      // And another frame costs the same as that one.
      expect(frame(), next);
    });
  });
}
