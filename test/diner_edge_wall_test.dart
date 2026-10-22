// Walls between tiles: the rule that nobody crosses one, and how one is put
// up, taken down, undone and saved.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'shelf.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/diner_painter.dart';
import 'package:hex/diner/iso.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/goals.dart';
import 'package:hex/diner/nav.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/diner/service.dart';
import 'package:hex/diner/staff.dart';

Diner room({int level = 3, int coins = 10000}) => Diner(
  coins: coins,
  owned: {0, 1},
  progress: Progress(level: level),
);

/// A wall along x on the north side of every tile in row [y], from [x0] to
/// [x1]: it runs between rows y - 1 and y.
Iterable<Edge> across(int y, int x0, int x1) => [
  for (var x = x0; x <= x1; x++) Edge(x, y, true),
];

void main() {
  group('an edge', () {
    test('is named for the two tiles it lies between', () {
      const north = Edge(4, 5, true);
      expect(north.a, const Cell(4, 4));
      expect(north.b, const Cell(4, 5));
      const west = Edge(4, 5, false);
      expect(west.a, const Cell(3, 5));
      expect(west.b, const Cell(4, 5));
    });

    test('between two touching tiles is the same either way round', () {
      final one = Edge.between(const Cell(4, 4), const Cell(4, 5));
      final two = Edge.between(const Cell(4, 5), const Cell(4, 4));
      expect(one, two);
      expect(one, const Edge(4, 5, true));
      expect(
        Edge.between(const Cell(3, 5), const Cell(4, 5)),
        const Edge(4, 5, false),
      );
    });

    test('there is none between tiles that do not touch', () {
      expect(Edge.between(const Cell(1, 1), const Cell(3, 1)), isNull);
      expect(Edge.between(const Cell(1, 1), const Cell(2, 2)), isNull);
      expect(Edge.between(const Cell(1, 1), const Cell(1, 1)), isNull);
    });

    test('equal edges are one thing in a set, and it is saved as numbers', () {
      final seen = <Edge>{};
      expect(seen.add(const Edge(1, 2, true)), isTrue);
      expect(seen.add(const Edge(1, 2, true)), isFalse);
      expect(const Edge(1, 2, true), isNot(const Edge(1, 2, false)));
      expect(
        Edge.fromJson(const Edge(7, -3, false).toJson()),
        const Edge(7, -3, false),
      );
      expect(Edge.fromJson([1, 2]), isNull);
      expect(Edge.fromJson([1, 2, 5]), isNull);
      expect(Edge.fromJson('no'), isNull);
    });
  });

  group('walking', () {
    test('nobody steps across a wall, and both tiles stay open', () {
      final d = room();
      d.walls.add(const Edge(4, 5, true));
      expect(d.wallBetween(const Cell(4, 4), const Cell(4, 5)), isTrue);
      expect(d.wallBetween(const Cell(4, 5), const Cell(4, 4)), isTrue);
      expect(d.canWalk(const Cell(4, 4), const Cell(4, 5)), isFalse);
      expect(d.canWalk(const Cell(4, 5), const Cell(4, 4)), isFalse);
      // A wall takes no tile: both are somewhere to stand, and the sides
      // next to it are still open.
      expect(d.walkable(const Cell(4, 4)), isTrue);
      expect(d.walkable(const Cell(4, 5)), isTrue);
      expect(d.canWalk(const Cell(4, 4), const Cell(5, 4)), isTrue);
      expect(d.approaches(const Cell(4, 5)), isNot(contains(const Cell(4, 4))));
    });

    test('a route goes round a wall, through the gap', () {
      final d = room();
      d.walls.addAll(across(5, 1, 6).where((e) => e.x != 4));
      final r = route(d, const Cell(2, 4), const Cell(2, 6))!;
      expect(r, contains(const Cell(4, 5)));
      // And it is longer than the straight way.
      expect(r.length, greaterThan(2));
    });

    test('with no gap there is no route', () {
      final d = room();
      d.walls.addAll(across(5, 1, 10));
      expect(route(d, const Cell(2, 4), const Cell(2, 6)), isNull);
    });

    test('the far side is not reached from the door', () {
      final d = room();
      d.walls.addAll(across(5, 1, 10));
      final open = d.reachable();
      expect(open, contains(const Cell(2, 6)));
      expect(open, isNot(contains(const Cell(2, 4))));
    });

    test('a corner of wall shuts in nothing by itself', () {
      final d = room();
      d.walls.addAll([const Edge(3, 5, true), const Edge(3, 5, false)]);
      expect(d.reachable(), contains(const Cell(2, 4)));
    });
  });

  group('beside fixtures', () {
    test('a machine cannot be used through a wall', () {
      final d = room();
      d.place(Kind.grill, const Cell(2, 3), Dir.sw);
      final grill = d.objectAt(const Cell(2, 3))!;
      expect(d.useCells(grill), [const Cell(2, 4)]);
      // The wall stands between the grill and the tile in front of it.
      d.walls.add(const Edge(2, 4, true));
      expect(d.useCells(grill), isEmpty);
      expect(
        d.report().problems.map((p) => p.text),
        contains('Grill needs a free tile in front'),
      );
    });

    test('a wall beside a machine, not in front, changes nothing', () {
      final d = room();
      d.place(Kind.grill, const Cell(2, 3), Dir.sw);
      d.walls.add(const Edge(3, 3, false));
      expect(d.useCells(d.objectAt(const Cell(2, 3))!), [const Cell(2, 4)]);
    });

    test('a seat is cut off from its table by a wall between them', () {
      final d = room();
      d.place(Kind.table, const Cell(5, 5));
      d.place(Kind.chair, const Cell(4, 5), Dir.se);
      expect(d.seats().length, 1);
      d.walls.add(const Edge(5, 5, false));
      expect(d.seats(), isEmpty);
    });

    test('a seat is still a seat with a wall behind it', () {
      final d = room();
      d.place(Kind.table, const Cell(5, 5));
      d.place(Kind.chair, const Cell(4, 5), Dir.se);
      d.walls.add(const Edge(4, 5, false));
      expect(d.seats().length, 1);
    });

    test('a seat with a wall on every side but the table has nowhere to come '
        'from', () {
      final d = room();
      d.place(Kind.table, const Cell(5, 5));
      d.place(Kind.chair, const Cell(4, 5), Dir.se);
      d.walls.addAll([
        const Edge(4, 5, false),
        const Edge(4, 5, true),
        const Edge(4, 6, true),
      ]);
      expect(d.seats(), isEmpty);
    });
  });

  group('putting one up', () {
    test('costs 6, and takes no tile', () {
      final d = room();
      final before = d.coins;
      expect(d.placeWall(const Edge(4, 5, true)), PlaceResult.ok);
      expect(before - d.coins, 6);
      expect(d.walls, {const Edge(4, 5, true)});
      expect(d.items, isEmpty);
    });

    test('is sold back for half', () {
      final d = room();
      d.placeWall(const Edge(4, 5, true));
      final before = d.coins;
      expect(d.sellWall(const Edge(4, 5, true)), isTrue);
      expect(d.coins - before, 3);
      expect(d.walls, isEmpty);
      expect(d.sellWall(const Edge(4, 5, true)), isFalse);
    });

    test('is not there before level 2, and needs the coins', () {
      expect(
        room(level: 1).checkWall(const Edge(4, 5, true)),
        PlaceResult.locked,
      );
      expect(
        room(coins: 5).checkWall(const Edge(4, 5, true)),
        PlaceResult.broke,
      );
      expect(
        room(coins: 5).checkWall(const Edge(4, 5, true), free: true),
        PlaceResult.ok,
      );
    });

    test('goes only between two tiles of the restaurant', () {
      final d = room();
      // The back wall of the room: the tile behind is outside.
      expect(
        d.checkWall(Edge(Diner.left + 1, Diner.top, true)),
        PlaceResult.outside,
      );
      // The left wall.
      expect(d.checkWall(Edge(Diner.left, 5, false)), PlaceResult.outside);
      // A tile in a section not bought.
      expect(d.checkWall(const Edge(5, -1, true)), PlaceResult.outside);
    });

    test('is not put on top of another', () {
      final d = room();
      d.placeWall(const Edge(4, 5, true));
      expect(d.checkWall(const Edge(4, 5, true)), PlaceResult.taken);
    });

    test('is refused if it would shut part of the room off from the door', () {
      final d = room();
      d.walls.addAll(across(5, 1, 9));
      const last = Edge(10, 5, true);
      expect(d.checkWall(last), PlaceResult.blocksWay);
      expect(d.cutOffByWall(last), isNotEmpty);
      expect(d.placeWall(last), PlaceResult.blocksWay);
      expect(d.walls.contains(last), isFalse);
    });

    test('is not blamed for what was already shut in', () {
      final d = room();
      // A pocket in the corner, shut in before.
      d.walls.addAll([const Edge(1, 4, true), const Edge(2, 3, false)]);
      d.walls.addAll([const Edge(1, 3, true)]);
      expect(d.reachable(), isNot(contains(const Cell(1, 3))));
      // A wall elsewhere is fine.
      expect(d.checkWall(const Edge(5, 6, true)), PlaceResult.ok);
    });
  });

  group('undo and saving', () {
    test('undo takes a wall down, and the coins come back', () {
      final d = room();
      final before = d.coins;
      d.placeWall(const Edge(4, 5, true));
      expect(d.undo(), 'Placed wall');
      expect(d.walls, isEmpty);
      expect(d.coins, before);
    });

    test('undo puts back a wall that was sold', () {
      final d = room();
      d.placeWall(const Edge(4, 5, true));
      d.sellWall(const Edge(4, 5, true));
      d.undo();
      expect(d.walls, {const Edge(4, 5, true)});
    });

    test('walls are saved and come back', () {
      final d = room();
      d.placeWall(const Edge(4, 5, true));
      d.placeWall(const Edge(6, 5, false));
      final back = Diner.fromJson(d.toJson());
      expect(back.walls, d.walls);
    });

    test('a game with none saves no list, and an old save loads', () {
      final j = room().toJson();
      expect(j.containsKey('walls'), isFalse);
      expect(Diner.fromJson(j).walls, isEmpty);
    });

    test('a wall that is no longer between two tiles is dropped', () {
      final d = Diner(coins: 100, owned: {0}, progress: Progress(level: 3));
      final j = d.toJson();
      j['walls'] = [
        [4, 5, 1], // fine
        [4, 5], // not a wall
        [20, 5, 1], // far outside
        ['x', 1, 1],
      ];
      expect(Diner.fromJson(j).walls, {const Edge(4, 5, true)});
    });
  });

  group('the picture', () {
    test('the posts stand at the ends and turns, once each', () {
      // One wall: a post at each end.
      expect(wallPosts([const Edge(3, 5, true)]), {
        const Cell(3, 5),
        const Cell(4, 5),
      });
      // A run of three: four posts, not six.
      expect(wallPosts(across(5, 3, 5)), {
        const Cell(3, 5),
        const Cell(4, 5),
        const Cell(5, 5),
        const Cell(6, 5),
      });
      // A corner: one post is shared.
      expect(wallPosts([const Edge(3, 5, true), const Edge(3, 5, false)]), {
        const Cell(3, 5),
        const Cell(4, 5),
        const Cell(3, 6),
      });
      // A cross: its four arms and the middle.
      expect(
        wallPosts([
          const Edge(4, 5, true),
          const Edge(3, 5, true),
          const Edge(4, 5, false),
          const Edge(4, 4, false),
        ]).length,
        5,
      );
      expect(wallPosts(const []), isEmpty);
    });

    test('every picture exists and is not blank', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final art = await DinerArt.load(_Assets());
      for (final n in ['wall_edge_x', 'wall_edge_y', 'wall_post']) {
        expect(art.has(n), isTrue, reason: n);
        expect(art.sprite(n).blank, isFalse, reason: n);
      }
      // Low enough to see over, like the tile wall.
      expect(
        art.sprite('wall_edge_x').trim.height,
        lessThan(art.sprite('grill_sw').trim.height),
      );
    });

    testWidgets('a wall is drawn as slabs and posts, and nothing without one', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final art = await DinerArt.load(_Assets());
        final d = room();
        const size = ui.Size(390, 560);
        final fit = BoardFit.of(d, size, 3);
        final layer = StaticLayer();

        int blits() {
          final p = DinerPainter(
            diner: d,
            art: art,
            fit: fit,
            layer: layer,
            revision: 1,
            showProblems: false,
          );
          final rec = ui.PictureRecorder();
          p.paint(ui.Canvas(rec), size);
          rec.endRecording().dispose();
          return p.blits;
        }

        blits();
        final bare = blits();
        d.walls.addAll(across(5, 3, 5));
        final walled = blits();
        // Three slabs and four posts.
        expect(walled - bare, 7);
      });
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

    final boardKey = find.byKey(const ValueKey('diner-board'));

    DinerPainter painter(WidgetTester tester) =>
        tester.widget<CustomPaint>(boardKey).painter! as DinerPainter;

    Future<void> pickWall(WidgetTester tester) async {
      await openShelf(tester, Kind.wall);
      final tile = find.byKey(const ValueKey('fixture-wall'));
      await tester.scrollUntilVisible(
        tile,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(tile);
      await tester.pump();
    }

    /// Where on screen the middle of [e] is.
    Offset onEdge(WidgetTester tester, Edge e) {
      final p = painter(tester);
      final a = p.fit.view.vertex(e.x, e.y);
      final b = p.fit.view.vertex(
        e.alongX ? e.x + 1 : e.x,
        e.alongX ? e.y : e.y + 1,
      );
      return tester.getTopLeft(boardKey) + (a + b) / 2 * p.fit.s;
    }

    /// Picks the wall and taps near [e] to aim at it.
    Future<void> aimAt(WidgetTester tester, Edge e) async {
      await pickWall(tester);
      await tester.tapAt(onEdge(tester, e));
      await tester.pump();
    }

    testWidgets('picking it aims at a free edge, and says what to do', (
      tester,
    ) async {
      final d = await open(tester);
      await pickWall(tester);
      final e = painter(tester).hoverEdge!;
      expect(d.checkWall(e, free: true), PlaceResult.ok);
      expect(find.byKey(const ValueKey('place')), findsOneWidget);
      expect(find.textContaining('Tap Place'), findsOneWidget);
    });

    testWidgets('Place puts it up, and aims at the next edge along', (
      tester,
    ) async {
      final d = await open(tester);
      await aimAt(tester, const Edge(4, 7, true));
      final first = painter(tester).hoverEdge!;
      expect(first, const Edge(4, 7, true));
      final coins = d.coins;
      await tester.tap(find.byKey(const ValueKey('place')));
      await tester.pump();
      expect(d.walls, {first});
      expect(coins - d.coins, 6);
      final next = painter(tester).hoverEdge!;
      expect(next.alongX, first.alongX);
      expect(next.x + next.y, first.x + first.y + 1);
      expect(find.text('Wall placed'), findsOneWidget);
    });

    testWidgets('a long wall is a run of Place', (tester) async {
      final d = await open(tester);
      await aimAt(tester, const Edge(4, 7, true));
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const ValueKey('place')));
        await tester.pump();
      }
      expect(d.walls, {
        const Edge(4, 7, true),
        const Edge(5, 7, true),
        const Edge(6, 7, true),
      });
    });

    testWidgets('Rotate puts the ghost on the other side of the tile', (
      tester,
    ) async {
      await open(tester);
      await pickWall(tester);
      final first = painter(tester).hoverEdge!;
      await tester.tap(find.byKey(const ValueKey('rotate')));
      await tester.pump();
      final second = painter(tester).hoverEdge!;
      expect((second.x, second.y), (first.x, first.y));
      expect(second.alongX, isNot(first.alongX));
    });

    testWidgets('the arrows move it a tile at a time', (tester) async {
      await open(tester);
      await pickWall(tester);
      final first = painter(tester).hoverEdge!;
      await tester.tap(find.byKey(const ValueKey('nudge-se')));
      await tester.pump();
      final moved = painter(tester).hoverEdge!;
      expect((moved.x, moved.y), (first.x + 1, first.y));
      expect(moved.alongX, first.alongX);
    });

    testWidgets('a tap near an edge aims at it', (tester) async {
      await open(tester);
      await pickWall(tester);
      const target = Edge(4, 5, true);
      await tester.tapAt(onEdge(tester, target));
      await tester.pump();
      expect(painter(tester).hoverEdge, target);
      await tester.tapAt(onEdge(tester, const Edge(5, 5, false)));
      await tester.pump();
      expect(painter(tester).hoverEdge, const Edge(5, 5, false));
    });

    testWidgets('an edge it cannot go on is refused, with the reason', (
      tester,
    ) async {
      final d = await open(tester);
      await pickWall(tester);
      // The back wall of the room: nothing behind it to put a wall against.
      await tester.tapAt(onEdge(tester, Edge(Diner.left + 1, Diner.top, true)));
      await tester.pump();
      expect(find.text('Outside the room'), findsOneWidget);
      final coins = d.coins;
      await tester.tap(
        find.byKey(const ValueKey('place')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(d.walls, isEmpty);
      expect(d.coins, coins);
    });

    testWidgets('one that would shut the way says which tiles', (tester) async {
      final d = await open(tester);
      // The corner tile (6, 7) already has a wall on its north side; one on
      // its west side as well would shut it in.
      d.walls.add(const Edge(6, 7, true));
      await aimAt(tester, const Edge(6, 7, false));
      expect(find.textContaining('block off the red tiles'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('place')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(d.walls.contains(const Edge(6, 7, false)), isFalse);
    });

    testWidgets('a placed wall can be tapped, and sold', (tester) async {
      final d = await open(tester);
      d.placeWall(const Edge(4, 5, true));
      await tester.pump();
      final coins = d.coins;
      await tester.tapAt(onEdge(tester, const Edge(4, 5, true)));
      await tester.pump();
      expect(painter(tester).selectedEdge, const Edge(4, 5, true));
      expect(find.byKey(const ValueKey('sell-wall')), findsOneWidget);
      expect(find.textContaining('Sell it for 3'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sell-wall')));
      await tester.pump();
      expect(d.walls, isEmpty);
      expect(d.coins - coins, 3);
      expect(painter(tester).selectedEdge, isNull);
    });

    testWidgets('Done lets go of it without selling', (tester) async {
      final d = await open(tester);
      d.placeWall(const Edge(4, 5, true));
      await tester.pump();
      await tester.tapAt(onEdge(tester, const Edge(4, 5, true)));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('wall-done')));
      await tester.pump();
      expect(d.walls, {const Edge(4, 5, true)});
      expect(painter(tester).selectedEdge, isNull);
    });

    testWidgets('undo takes a placed wall down again', (tester) async {
      final d = await open(tester);
      await aimAt(tester, const Edge(4, 7, true));
      await tester.tap(find.byKey(const ValueKey('place')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('cancel-edit')));
      await tester.pump();
      expect(d.walls, hasLength(1));
      await tester.tap(find.byKey(const ValueKey('undo')));
      await tester.pump();
      expect(d.walls, isEmpty);
    });

    testWidgets('a tap in the middle of a fixture still picks the fixture', (
      tester,
    ) async {
      final d = await open(tester);
      d.placeWall(const Edge(4, 5, true));
      await tester.pump();
      final table = d.items.firstWhere((p) => p.kind == Kind.table);
      final p = painter(tester);
      final at =
          tester.getTopLeft(boardKey) +
          p.fit.view.vertex(table.at.x + 0.5, table.at.y + 0.5) * p.fit.s;
      await tester.tapAt(at);
      await tester.pump();
      expect(painter(tester).selectedEdge, isNull);
      expect(painter(tester).selected, table);
    });
  });

  group('in a day', () {
    Staff person(int id, String name, {required bool cook}) => Staff(
      id: id,
      name: name,
      stats: {
        Stat.cooking: cook ? 8 : 2,
        Stat.speed: 5,
        Stat.service: cook ? 2 : 8,
        Stat.charm: 5,
      },
      potential: {for (final s in Stat.values) s: 10},
    );

    test('nobody ever crosses a wall, and the day goes on', () {
      final d = room(level: 5);
      d.progress
        ..reputation = 70
        ..day = 4;
      d.goalsDone.addAll([for (final g in goals) g.id]);
      d.progress.upgrades[Upgrade.staff] = 2;
      d.roster.employees
        ..clear()
        ..addAll([
          person(70, 'Cook', cook: true),
          person(71, 'S', cook: false),
        ]);
      d.place(Kind.grill, const Cell(1, 3), Dir.sw);
      d.place(Kind.grill, const Cell(2, 3), Dir.sw);
      d.place(Kind.counter, const Cell(9, 7), Dir.nw);
      d.place(Kind.counter, const Cell(9, 6), Dir.nw);
      for (final t in const [Cell(3, 6), Cell(6, 6), Cell(8, 4)]) {
        d.place(Kind.table, t);
        d.place(Kind.chair, Cell(t.x - 1, t.y), Dir.se);
        d.place(Kind.chair, Cell(t.x + 1, t.y), Dir.nw);
      }
      // A kitchen wall under the grills, with a gap at x = 4.
      d.walls.addAll(across(5, 1, 6).where((e) => e.x != 4));
      d.menu();
      var crossed = 0;
      final sim = DinerSim(d, seed: 3);
      while (!sim.finished && sim.ticks < 2500) {
        sim.tick();
        for (final p in <Person>[...sim.guests, ...sim.workers]) {
          final from = p.prev;
          final to = p.cell;
          if (from == to) continue;
          var last = from;
          for (final c in [if (p.mid != null) p.mid!, to]) {
            if (d.wallBetween(last, c)) crossed++;
            last = c;
          }
        }
      }
      expect(crossed, 0, reason: 'someone walked through a wall');
      expect(sim.served, greaterThan(0));
    });
  });
}

/// Loads sprites from the real files, for tests that run without a bundle.
class _Assets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = await File(key).readAsBytes();
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}
