import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/ui/chop_overlay.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';

void main() {
  test('the gold cells are five wide around each swing\'s centre', () {
    for (var swing = 0; swing < ChopOverlay.swings; swing++) {
      final c = ChopOverlay.centers[swing];
      expect(ChopOverlay.hits(swing, c), isTrue);
      expect(ChopOverlay.hits(swing, c - 2), isTrue);
      expect(ChopOverlay.hits(swing, c + 2), isTrue);
      expect(ChopOverlay.hits(swing, c - 3), isFalse);
      expect(ChopOverlay.hits(swing, c + 3), isFalse);
      // Every zone fits on the bar.
      expect(c - 2, greaterThanOrEqualTo(0));
      expect(c + 2, lessThan(ChopOverlay.cells));
    }
  });

  Future<List<int>> play(
    WidgetTester tester,
    List<int> strikeAtCell, {
    bool quick = false,
  }) async {
    await tester.runAsync(() => PixelAssets.load());
    final done = <int>[];
    var quickCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            ChopOverlay(
              onDone: done.add,
              onQuick: () => quickCalls++,
              onCancel: () {},
            ),
          ],
        ),
      ),
    );
    if (quick) {
      await tester.tap(find.text('Quick chop (1 wood)'));
      expect(quickCalls, 1);
      expect(done, isEmpty);
      return [];
    }
    for (var swing = 0; swing < ChopOverlay.swings; swing++) {
      // The marker starts on cell 0 and moves one cell per step.
      await tester.pump(
        Duration(milliseconds: ChopOverlay.stepMs[swing] * strikeAtCell[swing]),
      );
      await tester.tap(find.text('Strike'));
      await tester.pump(const Duration(milliseconds: 450));
    }
    await tester.pump(const Duration(milliseconds: 900));
    return done;
  }

  testWidgets('three well-timed strikes give three hits', (tester) async {
    final got = await play(tester, [10, 4, 16]);
    expect(got, [3]);
  });

  testWidgets('strikes off the gold are misses', (tester) async {
    final got = await play(tester, [10, 0, 0]);
    expect(got, [1]);
  });

  testWidgets('quick chop skips the game', (tester) async {
    await play(tester, const [], quick: true);
  });
}
