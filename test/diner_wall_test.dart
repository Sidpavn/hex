// The low wall: a piece that blocks walking, turns to run either way, and
// leaves a gap for a door.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/diner_painter.dart';
import 'package:hex/diner/goals.dart';
import 'package:hex/diner/guide.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';

Diner room({int level = 3}) => Diner(
  coins: 10000,
  owned: {0, 1},
  progress: Progress(level: level),
);

void main() {
  group('the piece', () {
    test('is cheap, comes early, and stands between tiles', () {
      final def = fixtureDefs[Kind.wall]!;
      expect(def.cost, 6);
      expect(def.refund, 3);
      expect(def.unlock, 2);
      expect(def.rotates, isFalse);
    });

    test('is not placed on a tile any more', () {
      final d = room();
      expect(d.place(Kind.wall, const Cell(4, 5)), isNot(PlaceResult.ok));
      expect(d.items, isEmpty);
    });
  });

  group('the picture', () {
    test('every wall sprite exists', () async {
      await DinerArt.load();
      final art = DinerArt.instance!;
      for (final n in const [
        'wall_edge_x',
        'wall_edge_y',
        'wall_post',
        'pass_edge_x',
        'pass_edge_y',
      ]) {
        expect(art.sprite(n), isNotNull, reason: n);
      }
    });
  });

  group('on screen', () {
    Future<Diner> open(WidgetTester tester) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
      });
      Storage.clearMemory();
      final d = Diner.starter();
      d.progress.level = 3;
      d.coins = 5000;
      d.goalsDone.addAll([for (final g in goals) g.id]);
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(HexApp(home: BuildScreen(diner: d)));
      await tester.pump();
      return d;
    }

    testWidgets('it is on the shelf, and aims at an edge', (tester) async {
      await open(tester);
      final tile = find.byKey(const ValueKey('fixture-wall'));
      await tester.scrollUntilVisible(
        tile,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(tile);
      await tester.pump();
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('diner-board')),
                  )
                  .painter!
              as DinerPainter;
      expect(painter.placing, Kind.wall);
      expect(painter.hoverEdge, isNotNull);
    });
  });

  testWidgets('a tapped wall can be rotated, moved and sold', (tester) async {
    await tester.runAsync(() async {
      await PixelAssets.load();
      await DinerArt.load();
    });
    Storage.clearMemory();
    final d = Diner.starter();
    d.progress.level = 3;
    d.coins = 5000;
    d.goalsDone.addAll([for (final g in goals) g.id]);
    d.walls.add(const Edge(4, 5, true));
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(HexApp(home: BuildScreen(diner: d)));
    await tester.pump();
    // Select it as the tap would.
    final state = tester.state(find.byType(BuildScreen)) as dynamic;
    state.debugSelectWall(const Edge(4, 5, true));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('turn-wall')));
    await tester.pump();
    expect(d.walls, {const Edge(4, 5, false)});
    await tester.tap(find.byKey(const ValueKey('move-wall')));
    await tester.pump();
    // Picked up: the button says Put down, and putting it back is fine.
    expect(find.text('Put down'), findsOneWidget);
    final coins = d.coins;
    await tester.tap(find.byKey(const ValueKey('place')));
    await tester.pump();
    expect(d.walls, {const Edge(4, 5, false)});
    // Pick up again, nudge along, and put down: free.
    await tester.tap(find.byKey(const ValueKey('move-wall')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('nudge-se')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('place')));
    await tester.pump();
    expect(d.walls.length, 1);
    expect(d.walls.single, isNot(const Edge(4, 5, false)));
    expect(d.coins, coins);
  });

  testWidgets('moving a wall by tapping the board', (tester) async {
    await tester.runAsync(() async {
      await PixelAssets.load();
      await DinerArt.load();
    });
    Storage.clearMemory();
    final d = Diner.starter();
    d.progress.level = 3;
    d.coins = 5000;
    d.goalsDone.addAll([for (final g in goals) g.id]);
    d.walls.add(const Edge(4, 5, true));
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(HexApp(home: BuildScreen(diner: d)));
    await tester.pump();
    final board = find.byKey(const ValueKey('diner-board'));
    Offset at(Edge e) {
      final painter =
          tester.widget<CustomPaint>(board).painter! as DinerPainter;
      final a = painter.fit.view.vertex(e.x, e.y);
      final b = painter.fit.view.vertex(
        e.alongX ? e.x + 1 : e.x,
        e.alongX ? e.y : e.y + 1,
      );
      return tester.getTopLeft(board) + (a + b) / 2 * painter.fit.s;
    }

    await tester.tapAt(at(const Edge(4, 5, true)));
    await tester.pump();
    expect(find.byKey(const ValueKey('move-wall')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('move-wall')));
    await tester.pump();
    await tester.tapAt(at(const Edge(5, 6, true)));
    await tester.pump();
    // Aiming only looks: the wall has not moved yet, and the ghost is green.
    expect(d.walls, {const Edge(4, 5, true)});
    final pt = tester.widget<CustomPaint>(board).painter! as DinerPainter;
    expect(pt.placeOk, isTrue);
    await tester.tap(find.byKey(const ValueKey('place')));
    await tester.pump();
    expect(d.walls, {const Edge(5, 6, true)});
  });

  testWidgets('the pass is placed on an edge too', (tester) async {
    await tester.runAsync(() async {
      await PixelAssets.load();
      await DinerArt.load();
    });
    Storage.clearMemory();
    final d = Diner.starter();
    d.progress.level = 3;
    d.coins = 5000;
    d.goalsDone.addAll([for (final g in goals) g.id]);
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(HexApp(home: BuildScreen(diner: d)));
    await tester.pump();
    final tile = find.byKey(const ValueKey('fixture-pass'));
    await tester.scrollUntilVisible(
      tile,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(tile);
    await tester.pump();
    final before = d.coins;
    await tester.tap(find.byKey(const ValueKey('place')));
    await tester.pump();
    expect(d.hatches, hasLength(1));
    expect(d.coins, before - 60);
  });

  test('the guide tells players about low walls', () {
    final all = guidePages.expand((p) => p.lines).join(' ');
    expect(all, contains('Low walls'));
    expect(all, contains('gap'));
  });
}
