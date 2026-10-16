// What is being moved stays where it was, drawn as a dither, so the ghost at
// the new place does not look like a second copy.
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/diner_painter.dart';
import 'package:hex/diner/iso.dart';
import 'package:hex/diner/recipes.dart';

void main() {
  const size = ui.Size(390, 560);
  const dpr = 6.0;

  Future<List<int>> draw(
    DinerArt art,
    Diner d,
    BoardFit fit, {
    Placed? moving,
    List<Placed> group = const [],
    bool groupMoving = false,
  }) async {
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec)..scale(dpr);
    DinerPainter(
      diner: d,
      art: art,
      fit: fit,
      moving: moving,
      group: group,
      groupMoving: groupMoving,
    ).paint(canvas, size);
    final img = await rec.endRecording().toImage(
      (size.width * dpr).round(),
      (size.height * dpr).round(),
    );
    return (await img.toByteData())!.buffer.asUint8List().toList();
  }

  /// How many pixels in the box around [c] differ between two pictures.
  int differing(List<int> a, List<int> b, BoardFit fit, Cell c) {
    final v = fit.view.vertex(c.x, c.y) * fit.s * dpr;
    final w = (size.width * dpr).round();
    var n = 0;
    for (
      var y = (v.dy - 40 * fit.s * dpr).round();
      y < (v.dy + 20 * fit.s * dpr).round();
      y++
    ) {
      for (
        var x = (v.dx - 16 * fit.s * dpr).round();
        x < (v.dx + 16 * fit.s * dpr).round();
        x++
      ) {
        final i = (y * w + x) * 4;
        if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) n++;
      }
    }
    return n;
  }

  testWidgets('the thing being moved is drawn broken up where it stood', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final art = await DinerArt.load();
      final d = Diner(coins: 1000, owned: {0, 1}, progress: Progress(level: 5));
      d.place(Kind.table, const Cell(5, 5));
      final table = d.objectAt(const Cell(5, 5))!;
      final fit = BoardFit.of(d, size, dpr);
      final solid = await draw(art, d, fit);
      final lifted = await draw(art, d, fit, moving: table);
      final changed = differing(solid, lifted, fit, table.at);
      expect(changed, greaterThan(500), reason: 'it is no longer solid');
      // Not gone either: the other half of the pixels are still the table's.
      final again = await draw(art, d, fit, moving: table);
      expect(again, lifted, reason: 'the same dither every frame');
      final empty = Diner(
        coins: 1000,
        owned: {0, 1},
        progress: Progress(level: 5),
      );
      final bare = await draw(art, empty, fit);
      final gone = differing(solid, bare, fit, table.at);
      expect(changed, lessThan(gone), reason: 'still partly there');
    });
  });

  testWidgets('a group being moved is faded, one being copied is not', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final art = await DinerArt.load();
      final d = Diner(coins: 1000, owned: {0, 1}, progress: Progress(level: 5));
      d.place(Kind.table, const Cell(5, 5));
      d.place(Kind.table, const Cell(7, 5));
      final group = d.items.toList();
      final fit = BoardFit.of(d, size, dpr);
      final solid = await draw(art, d, fit, group: group);
      final moved = await draw(art, d, fit, group: group, groupMoving: true);
      final copied = await draw(art, d, fit, group: group);
      expect(differing(solid, moved, fit, const Cell(5, 5)), greaterThan(500));
      expect(differing(solid, moved, fit, const Cell(7, 5)), greaterThan(500));
      expect(differing(solid, copied, fit, const Cell(5, 5)), 0);
    });
  });

  test('the painter knows when it should redraw for it', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final art = await DinerArt.load();
    final d = Diner(coins: 1000, owned: {0, 1});
    final fit = BoardFit.of(d, size, dpr);
    final a = DinerPainter(diner: d, art: art, fit: fit);
    final b = DinerPainter(diner: d, art: art, fit: fit, groupMoving: true);
    expect(b.shouldRepaint(a), isTrue);
  });
}
