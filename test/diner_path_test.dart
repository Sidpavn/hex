// A fixture that would shut a tile in is refused, and the tile is shown.
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/diner_painter.dart';
import 'package:hex/diner/iso.dart';

Diner start() {
  final d = Diner.starter()
    ..coins = 5000
    ..progress.level = 9;
  d.owned
    ..clear()
    ..add(0);
  return d;
}

void main() {
  group('which tiles would be shut in', () {
    test('a grill beside the wall can cut off the tile next to it', () {
      final d = start();
      // The starter has a grill and counters along the back row and a table
      // and chair below: the tile at (1, 4) is a pocket if (2, 4) is filled.
      expect(d.check(Kind.grill, const Cell(2, 4)), PlaceResult.blocksWay);
      expect(d.cutOff(Kind.grill, const Cell(2, 4)), [const Cell(1, 4)]);
    });

    test('a longer pocket lists every tile in it', () {
      final d = start();
      expect(d.cutOff(Kind.grill, const Cell(3, 4)).toSet(), {
        const Cell(1, 4),
        const Cell(2, 4),
      });
    });

    test('a place that leaves a way through shuts in nothing', () {
      final d = start();
      expect(d.check(Kind.grill, const Cell(4, 3)), PlaceResult.ok);
      expect(d.cutOff(Kind.grill, const Cell(4, 3)), isEmpty);
    });

    test('it agrees with the check, everywhere in the room', () {
      final d = start();
      for (final c in d.insideCells()) {
        final r = d.check(Kind.grill, c);
        if (r == PlaceResult.ok) {
          expect(d.cutOff(Kind.grill, c), isEmpty, reason: '$c');
        } else if (r == PlaceResult.blocksWay) {
          expect(d.cutOff(Kind.grill, c), isNotEmpty, reason: '$c');
        }
      }
    });

    test('moving something, its old place does not count', () {
      final d = start();
      final counter = d.objectAt(const Cell(3, 3))!;
      // Slid one tile along the wall: nothing is shut in.
      expect(
        d.cutOff(Kind.counter, const Cell(4, 3), ignore: counter),
        isEmpty,
      );
    });

    test('floor things and wall things shut in nothing', () {
      final d = start();
      expect(d.cutOff(Kind.rug, const Cell(2, 4)), isEmpty);
      expect(d.cutOff(Kind.tv, const Cell(2, 3)), isEmpty);
    });

    test('and nothing is cut off with the room as it is', () {
      final d = start();
      expect(d.reachable().length, d.insideCells().where(d.walkable).length);
    });
  });

  testWidgets('the shut-in tile is marked on the board', (tester) async {
    await tester.runAsync(() async {
      final art = await DinerArt.load();
      final d = start();
      const size = ui.Size(390, 560);
      const dpr = 6.0;
      final fit = BoardFit.of(d, size, dpr);

      Future<List<int>> draw({Kind? placing, Cell? at}) async {
        final rec = ui.PictureRecorder();
        final canvas = ui.Canvas(rec)..scale(dpr);
        DinerPainter(
          diner: d,
          art: art,
          fit: fit,
          placing: placing,
          hover: at,
          placeOk: false,
        ).paint(canvas, size);
        final img = await rec.endRecording().toImage(
          (size.width * dpr).round(),
          (size.height * dpr).round(),
        );
        return (await img.toByteData())!.buffer.asUint8List().toList();
      }

      // The ghost is refused at (2, 4); the pocket is (1, 4).
      final plain = await draw();
      final refused = await draw(placing: Kind.grill, at: const Cell(2, 4));
      final fine = await draw(placing: Kind.grill, at: const Cell(4, 3));
      final v = fit.view.vertex(1, 4) * fit.s * dpr;
      final w = (size.width * dpr).round();
      int changed(List<int> a, List<int> b) {
        var n = 0;
        for (
          var y = (v.dy).round();
          y < (v.dy + 16 * fit.s * dpr).round();
          y++
        ) {
          for (
            var x = (v.dx - 16 * fit.s * dpr).round();
            x < (v.dx + 16 * fit.s * dpr).round();
            x++
          ) {
            final i = (y * w + x) * 4;
            if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) {
              n++;
            }
          }
        }
        return n;
      }

      expect(changed(plain, refused), greaterThan(100), reason: 'marked red');
      expect(
        changed(plain, fine),
        0,
        reason: 'nothing is marked when a way is left',
      );
    });
  });
}
