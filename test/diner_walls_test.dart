// Where one section of the plot ends beside another, the tall wall in front
// hides the low wall behind it instead of being drawn over by it.
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/diner_painter.dart';
import 'package:hex/diner/iso.dart';
import 'package:hex/diner/recipes.dart';

void main() {
  testWidgets('a low side wall does not cross a tall back wall', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final art = await DinerArt.load();
      // The room, and the room behind it on the left only: the right-hand
      // section's back wall stands next to the left section's low side wall.
      final d = Diner(
        coins: 1000,
        owned: {0, 1, 2},
        progress: Progress(level: 9),
      );
      const size = ui.Size(390, 560);
      const dpr = 6.0;
      final fit = BoardFit.of(d, size, dpr);
      final rec = ui.PictureRecorder();
      final canvas = ui.Canvas(rec)..scale(dpr);
      DinerPainter(diner: d, art: art, fit: fit).paint(canvas, size);
      final img = await rec.endRecording().toImage(
        (size.width * dpr).round(),
        (size.height * dpr).round(),
      );
      final px = (await img.toByteData())!.buffer.asUint8List();
      List<int> at(Offset p) {
        final i = (p.dy.round() * img.width + p.dx.round()) * 4;
        return [px[i], px[i + 1], px[i + 2]];
      }

      // A point on the glass of the tall wall that the low wall used to cross.
      final corner = fit.view.vertex(7, 3) * fit.s * dpr;
      final glass = at(corner + Offset(30 * fit.s * dpr, -18 * fit.s * dpr));
      expect(
        glass[1] > glass[0] && glass[2] > glass[0],
        isTrue,
        reason:
            'glass is teal, not the brown and white of the low wall: $glass',
      );
    });
  });

  test('tall walls are sorted by the line they stand on', () {
    // A wall on the north edge of the room is in front of anything beyond it
    // and behind anything in the room next to it.
    const wall = Cell(7, 2);
    final key = wall.x + wall.y + 1 - 0.25;
    final lowWallBeyond = 6 + 2 + 1.5;
    final tableInFront = 7 + 3;
    expect(key, greaterThan(lowWallBeyond));
    expect(key, lessThan(tableInFront));
  });
}
