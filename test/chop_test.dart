import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/ui/chop_overlay.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';

void main() {
  test('the zones get narrower with each swing', () {
    expect(ChopOverlay.zoneHalf, [3, 2, 1]);
    final c = [10, 4, 16];
    expect(ChopOverlay.hits(c, 0, 13), isTrue);
    expect(ChopOverlay.hits(c, 0, 14), isFalse);
    expect(ChopOverlay.hits(c, 1, 2), isTrue);
    expect(ChopOverlay.hits(c, 1, 1), isFalse);
    expect(ChopOverlay.hits(c, 2, 17), isTrue);
    expect(ChopOverlay.hits(c, 2, 18), isFalse);
  });

  test('random zones fit the bar, move each swing, and vary between trees', () {
    final seen = <String>{};
    for (var seed = 0; seed < 200; seed++) {
      final c = ChopOverlay.pickCenters(Random(seed));
      seen.add(c.join(','));
      for (var i = 0; i < ChopOverlay.swings; i++) {
        final half = ChopOverlay.zoneHalf[i];
        expect(c[i] - half, greaterThanOrEqualTo(0));
        expect(c[i] + half, lessThan(ChopOverlay.cells));
        if (i > 0) {
          expect(
            (c[i] - c[i - 1]).abs(),
            greaterThanOrEqualTo(ChopOverlay.minGap),
          );
        }
      }
    }
    expect(seen.length, greaterThan(50));
  });

  Future<List<int>> play(
    WidgetTester tester,
    List<int> Function(List<int> centers) strikeAt,
  ) async {
    await tester.runAsync(() => PixelAssets.load());
    final centers = ChopOverlay.pickCenters(Random(7));
    final cells = strikeAt(centers);
    final done = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            ChopOverlay(onDone: done.add, onCancel: () {}, random: Random(7)),
          ],
        ),
      ),
    );
    for (var swing = 0; swing < ChopOverlay.swings; swing++) {
      // The marker starts on cell 0 and moves one cell per step.
      await tester.pump(
        Duration(milliseconds: ChopOverlay.stepMs[swing] * cells[swing]),
      );
      await tester.tap(find.text('Strike'));
      await tester.pump(const Duration(milliseconds: 450));
    }
    await tester.pump(const Duration(milliseconds: 900));
    return done;
  }

  testWidgets('three well-timed strikes give three hits', (tester) async {
    expect(await play(tester, (c) => c), [3]);
  });

  testWidgets('strikes off the gold are misses', (tester) async {
    // Cell 0 is never inside a zone: the lowest zone edge is cell 0 only for
    // half == centre, which pickCenters cannot place after the first swing.
    final got = await play(tester, (c) => [c[0], 0, 0]);
    expect(got, [1]);
  });

  testWidgets('missing every swing gives no hits', (tester) async {
    final got = await play(tester, (c) => [0, 0, 0]);
    expect(got, [0]);
  });
}
