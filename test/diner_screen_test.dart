import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/diner_painter.dart';
import 'package:hex/diner/goals.dart';
import 'package:hex/diner/iso.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';
import 'support/office.dart';

void main() {
  final board = find.byKey(const ValueKey('diner-board'));

  Future<Diner> open(WidgetTester tester, {Diner? diner}) async {
    await tester.runAsync(() async {
      await PixelAssets.load();
      await DinerArt.load();
    });
    Storage.clearMemory();
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final d = diner ?? (Diner.starter()..coins = 500);
    await tester.pumpWidget(HexApp(home: BuildScreen(diner: d)));
    await tester.pump();
    return d;
  }

  BoardFit fit(WidgetTester tester) =>
      (tester.widget<CustomPaint>(board).painter! as DinerPainter).fit;

  Offset onCell(WidgetTester tester, Cell c) {
    final f = fit(tester);
    return tester.getTopLeft(board) + f.view.vertex(c.x + 0.5, c.y + 0.5) * f.s;
  }

  Future<void> runDay(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('start-day')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('speed-3')));
    await tester.pump();
    for (var i = 0; i < 900; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byKey(const ValueKey('next-day')).evaluate().isNotEmpty) break;
    }
  }

  testWidgets('a day runs from the build screen to the summary and back', (
    tester,
  ) async {
    final d = await open(tester);
    expect(find.text('Start day 1'), findsOneWidget);
    await runDay(tester);
    expect(find.byKey(const ValueKey('next-day')), findsOneWidget);
    expect(find.byKey(const ValueKey('verdict')), findsOneWidget);
    expect(find.byKey(const ValueKey('kept')), findsOneWidget);
    expect(find.byKey(const ValueKey('serve-bar')), findsOneWidget);
    expect(d.progress.day, 2);
    expect(d.progress.xp, greaterThan(0));

    await tester.tap(find.byKey(const ValueKey('next-day')));
    await tester.pump();
    expect(find.text('Start day 2'), findsOneWidget);
  });

  testWidgets('the layout is locked while the diner is open', (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey('fixture-grill')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('start-day')));
    await tester.pump();
    expect(find.byKey(const ValueKey('fixture-grill')), findsNothing);
    expect(find.byKey(const ValueKey('rotate')), findsNothing);
    expect(find.byKey(const ValueKey('expand')), findsNothing);
    expect(find.byKey(const ValueKey('start-day')), findsNothing);
    // Tapping the grill does not select it.
    await tester.tapAt(onCell(tester, const Cell(Diner.left, Diner.top)));
    await tester.pump();
    expect(find.byKey(const ValueKey('sell')), findsNothing);
  });

  testWidgets('you cannot open a diner that is not ready', (tester) async {
    final d = await open(tester, diner: Diner(coins: 100));
    expect(d.report().ready, isFalse);
    await tester.tap(
      find.byKey(const ValueKey('start-day')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('fixture-grill')), findsOneWidget);
    expect(find.textContaining('Closed:'), findsOneWidget);
  });

  testWidgets('selecting a fixture shows what it does, and rotate turns it', (
    tester,
  ) async {
    final d = await open(tester);
    final grill = d.items.firstWhere((p) => p.kind == Kind.grill);
    await tester.tapAt(onCell(tester, grill.at));
    await tester.pump();
    expect(find.textContaining('Cooks burgers'), findsOneWidget);
    final before = grill.facing;
    await tester.tap(find.byKey(const ValueKey('rotate')));
    await tester.pump();
    expect(grill.facing, before.cw);
  });

  testWidgets('a fixture can be moved and sold', (tester) async {
    final d = await open(tester);
    final grill = d.items.firstWhere((p) => p.kind == Kind.grill);
    await tester.tapAt(onCell(tester, grill.at));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('move')));
    await tester.pump();
    await tester.tapAt(onCell(tester, const Cell(4, 6)));
    await tester.pump();
    expect(grill.at, isNot(const Cell(4, 6)), reason: 'only aimed so far');
    await tester.tap(find.byKey(const ValueKey('place')));
    await tester.pump();
    expect(grill.at, const Cell(4, 6));

    final coins = d.coins;
    await tester.tapAt(onCell(tester, grill.at));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sell')));
    await tester.pump();
    expect(d.items.contains(grill), isFalse);
    expect(d.coins, coins + 30);
  });

  testWidgets('locked fixtures say what level unlocks them', (tester) async {
    final d = await open(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('fixture-fryer')));
    await tester.tap(find.byKey(const ValueKey('fixture-fryer')));
    await tester.pump();
    expect(find.textContaining('unlocks at level 2'), findsOneWidget);
    expect(d.items.any((p) => p.kind == Kind.fryer), isFalse);
  });

  testWidgets('upgrades can be bought between days', (tester) async {
    final d = await open(tester);
    d.coins = 1000;
    await openApp(tester, 'upgrades');
    expect(find.text('Upgrades'), findsWidgets);
    final cost = d.progress.upgradeCost(Upgrade.kitchen)!;
    final before = d.coins;
    await tester.scrollUntilVisible(
      find.textContaining('Faster kitchen'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.textContaining('Faster kitchen'));
    // The row's button is the only thing that spends coins.
    expect(d.coins, before);
    expect(d.progress.upgradeLvl(Upgrade.kitchen), 0);
    expect(cost, greaterThan(0));
  });

  testWidgets('a fixture being moved stays visible', (tester) async {
    final d = await open(tester);
    final grill = d.items.firstWhere((p) => p.kind == Kind.grill);

    // Draw the board the way the screen does and count what is drawn.
    int drawn({Placed? moving, Cell? hover}) {
      final f = fit(tester);
      final art = DinerArt.instance!;
      final p = DinerPainter(
        diner: d,
        art: art,
        fit: f,
        moving: moving,
        placing: moving?.kind,
        hover: hover,
        facing: moving?.facing ?? Dir.sw,
      );
      final rec = PictureRecorder();
      p.paint(Canvas(rec), tester.getSize(board));
      rec.endRecording().dispose();
      return p.blits;
    }

    final normal = drawn();
    expect(
      drawn(moving: grill),
      normal,
      reason: 'picked up, but still drawn where it stood',
    );
    // Dragged over a tile it cannot go on: still drawn.
    expect(drawn(moving: grill, hover: const Cell(2, 3)), normal);

    // And on the real screen, pressing Move changes nothing visible at first.
    await tester.tapAt(onCell(tester, grill.at));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('move')));
    await tester.pump();
    final painter = tester.widget<CustomPaint>(board).painter! as DinerPainter;
    expect(painter.moving, grill);
    expect(d.items.contains(grill), isTrue);
  });

  /// Pumps for a moment: the build screen never settles, as its ticker runs.
  Future<void> beat(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 100));

  Future<void> expand(WidgetTester tester) async {
    await openApp(tester, 'expand');
    await beat(tester);
  }

  testWidgets('expanding happens on the board, not on another page', (
    tester,
  ) async {
    final d = await open(tester);
    d.coins = 5000;
    d.progress.level = 9;
    await tester.pump();
    final before = fit(tester);
    await expand(tester);
    // Still the same screen, with the board, and a panel about the plot.
    expect(board, findsOneWidget);
    expect(find.byKey(const ValueKey('plot-detail')), findsOneWidget);
    expect(find.byKey(const ValueKey('done-expanding')), findsOneWidget);
    expect(find.byKey(const ValueKey('start-day')), findsNothing);
    // The view pulls back to take in the whole plot.
    final painter = tester.widget<CustomPaint>(board).painter! as DinerPainter;
    expect(painter.expanding, isTrue);
    expect(fit(tester).view.height, greaterThan(before.view.height));
    await tester.tap(find.byKey(const ValueKey('done-expanding')));
    await beat(tester);
    expect(find.byKey(const ValueKey('start-day')), findsOneWidget);
    expect(fit(tester).view.height, before.view.height);
  });

  testWidgets('tapping a section on the board picks it, and Buy buys it', (
    tester,
  ) async {
    final d = await open(tester);
    d.coins = 5000;
    d.progress.level = 9;
    // Goals pay as things happen: leave them out of the sums here.
    d.goalsDone.addAll([for (final g in goals) g.id]);
    await tester.pump();
    await expand(tester);
    // Pick the room behind, by tapping the ground where it will be.
    await tester.tapAt(onCell(tester, const Cell(3, 0)));
    await beat(tester);
    final painter = tester.widget<CustomPaint>(board).painter! as DinerPainter;
    expect(painter.plotSel, 2);
    expect(find.text('Room behind'), findsOneWidget);
    expect(find.textContaining('24 more tiles'), findsOneWidget);
    final cost = d.unlockCost(2);
    await tester.tap(find.byKey(const ValueKey('buy-plot')));
    await beat(tester);
    expect(d.owned, {0, 2});
    expect(d.coins, 5000 - cost);
    expect(find.textContaining('is yours'), findsOneWidget);
    // Still choosing, and the view takes in the new room.
    expect(find.byKey(const ValueKey('done-expanding')), findsOneWidget);
  });

  testWidgets(
    'the sections that can be bought now are the ones outlined gold',
    (tester) async {
      final d = await open(tester);
      d.progress.level = 9;
      await tester.pump();
      await expand(tester);
      final painter =
          tester.widget<CustomPaint>(board).painter! as DinerPainter;
      expect(painter.expanding, isTrue);
      expect(d.nextPlots, [1, 2]);
      // A section that is already yours cannot be picked.
      await tester.tapAt(onCell(tester, const Cell(3, 5)));
      await beat(tester);
      expect(
        (tester.widget<CustomPaint>(board).painter! as DinerPainter).plotSel,
        1,
        reason: 'the first one to buy stays chosen',
      );
    },
  );

  testWidgets('a section behind cannot be bought before the one in front', (
    tester,
  ) async {
    final d = await open(tester);
    d.coins = 50000;
    d.progress.level = 9;
    // Goals pay as things happen: leave them out of the sums here.
    d.goalsDone.addAll([for (final g in goals) g.id]);
    await expand(tester);
    await tester.tapAt(onCell(tester, const Cell(9, -4)));
    await beat(tester);
    expect(find.textContaining('first'), findsWidgets);
    await tester.tap(
      find.byKey(const ValueKey('buy-plot')),
      warnIfMissed: false,
    );
    await beat(tester);
    expect(d.owned, {0});
    expect(d.coins, 50000);
  });

  testWidgets('a section needing a higher level says which', (tester) async {
    final d = await open(tester);
    d.coins = 50000;
    await expand(tester);
    await tester.tapAt(onCell(tester, const Cell(3, 0)));
    await beat(tester);
    expect(find.text('Needs restaurant level 3'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('buy-plot')),
      warnIfMissed: false,
    );
    await beat(tester);
    expect(d.owned, {0});
  });

  testWidgets(
    'with everything bought, it says so and no word is a bare label',
    (tester) async {
      final d = await open(tester);
      d.coins = 500000;
      d.progress.level = 9;
      for (var i = 1; i < Diner.plots.length; i++) {
        d.owned.add(i);
      }
      await expand(tester);
      expect(find.text('All of the plot is yours.'), findsOneWidget);
      expect(find.byKey(const ValueKey('buy-plot')), findsNothing);
      final banned = RegExp(r'\b(yard|lot|max|owned)\b', caseSensitive: false);
      expect(find.textContaining(banned), findsNothing);
    },
  );

  testWidgets('building tools are put away while choosing what to buy', (
    tester,
  ) async {
    await open(tester);
    expect(find.byKey(const ValueKey('fixture-grill')), findsOneWidget);
    await expand(tester);
    final painter = tester.widget<CustomPaint>(board).painter! as DinerPainter;
    expect(painter.placing, isNull);
    expect(find.byKey(const ValueKey('fixture-grill')), findsNothing);
    expect(find.byKey(const ValueKey('rotate')), findsNothing);
  });

  /// Start over is on the goals page, out of the way.
  Future<void> openReset(WidgetTester tester) async {
    await openApp(tester, 'goals');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('reset')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('reset')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('reset')));
    // Goals, the computer and the staff room each close in turn, then it asks.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  testWidgets('reset wipes the saved restaurant, after asking', (tester) async {
    final d = await open(tester);
    d.coins = 7;
    d.progress.level = 4;
    d.progress.day = 9;
    d.items.clear();
    d.ensureDoor();
    Storage.saveDiner(d);
    expect(Storage.diner, isNotNull);

    // Asked, then declined: nothing changes.
    await openReset(tester);
    expect(find.text('Start over?'), findsOneWidget);
    await tester.tap(find.text('Keep it'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(Storage.diner, isNotNull);
    expect(
      (tester.widget<CustomPaint>(board).painter! as DinerPainter).diner,
      same(d),
    );

    await openReset(tester);
    await tester.tap(find.byKey(const ValueKey('confirm-reset')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(Storage.diner, isNull);
    final fresh =
        (tester.widget<CustomPaint>(board).painter! as DinerPainter).diner;
    expect(fresh, isNot(same(d)));
    expect(fresh.coins, 120);
    expect(fresh.progress.day, 1);
    expect(fresh.progress.level, 1);
    expect(fresh.progress.reputation, Progress.startReputation);
    expect(fresh.report().ready, isTrue);
    expect(find.text('Start day 1'), findsOneWidget);
  });

  testWidgets('the menu and the rest are on the computer, not on buttons', (
    tester,
  ) async {
    await open(tester);
    for (final k in ['menu', 'staff', 'stats', 'upgrades', 'goals', 'expand']) {
      expect(find.byKey(ValueKey(k)), findsNothing, reason: k);
    }
    expect(find.byKey(const ValueKey('start-day')), findsOneWidget);
    expect(find.byKey(const ValueKey('undo')), findsOneWidget);
  });
}
