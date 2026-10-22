// Kitchen floor: staff walk on it, guests never do.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/city.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/diner_painter.dart';
import 'package:hex/diner/goals.dart';
import 'package:hex/diner/nav.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/diner/service.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';
import 'shelf.dart';

Diner room({int level = 3, int coins = 1000}) => Diner(
  coins: coins,
  owned: {0, 1},
  progress: Progress(level: level),
);

void main() {
  group('the floor', () {
    test('costs 4 a tile, gives back 2, and unlocks at level 3', () {
      final def = fixtureDefs[Kind.kitchenFloor]!;
      expect(def.cost, 4);
      expect(def.refund, 2);
      expect(def.unlock, 3);
      expect(room(level: 2).checkKitchen(const Cell(3, 4)), PlaceResult.locked);
    });

    test('is laid tile by tile, and erased', () {
      final d = room();
      expect(d.paintKitchen(const Cell(3, 4)), PlaceResult.ok);
      expect(d.coins, 996);
      expect(d.kitchen, {const Cell(3, 4)});
      expect(d.paintKitchen(const Cell(3, 4)), PlaceResult.taken);
      expect(d.eraseKitchen(const Cell(3, 4)), isTrue);
      expect(d.coins, 998);
      expect(d.eraseKitchen(const Cell(3, 4)), isFalse);
    });

    test('is refused outside the room, on the door, and with no money', () {
      final d = room();
      expect(d.checkKitchen(const Cell(30, 30)), PlaceResult.outside);
      expect(d.checkKitchen(d.entrance), PlaceResult.taken);
      expect(room(coins: 3).checkKitchen(const Cell(3, 4)), PlaceResult.broke);
    });

    test('can lie under a fixture', () {
      final d = room();
      d.place(Kind.grill, const Cell(3, 4), Dir.sw);
      expect(d.paintKitchen(const Cell(3, 4)), PlaceResult.ok);
    });

    test('shows as its own tile', () {
      final d = room();
      d.paintKitchen(const Cell(3, 4));
      expect(groundTile(d, const Cell(3, 4)), startsWith('kitchen'));
      expect(groundTile(d, const Cell(4, 4)), startsWith('floor'));
    });

    test('is undone as one step per stroke, coins and all', () {
      final d = room();
      d.remember('Kitchen floor');
      d.paintKitchen(const Cell(3, 4));
      d.paintKitchen(const Cell(4, 4));
      expect(d.undo(), 'Kitchen floor');
      expect(d.kitchen, isEmpty);
      expect(d.coins, 1000);
    });

    test('is saved, and a tile that is not in the room is dropped', () {
      final d = room();
      d.paintKitchen(const Cell(3, 4));
      d.paintKitchen(const Cell(4, 4));
      final j = d.toJson();
      expect(Diner.fromJson(j).kitchen, d.kitchen);
      (j['kitchen'] as List).add([99, 99]);
      expect(Diner.fromJson(j).kitchen, d.kitchen);
      expect(room().toJson().containsKey('kitchen'), isFalse);
    });
  });

  group('walking', () {
    test('guests go round it, staff go across', () {
      final d = room();
      // A strip across the room with a gap at the door side.
      for (var x = 1; x <= 6; x++) {
        d.kitchen.add(Cell(x, 5));
      }
      final from = const Cell(3, 4);
      const to = Cell(3, 6);
      final guest = route(d, from, to, guest: true);
      final staff = route(d, from, to);
      expect(staff, isNotNull);
      expect(staff!.length, 2);
      expect(guest, isNotNull, reason: 'round the end of the strip');
      expect(guest!.length, greaterThan(2));
      expect(guest.any(d.kitchen.contains), isFalse);
    });

    test('a guest cannot go to a kitchen tile at all', () {
      final d = room();
      d.kitchen.add(const Cell(3, 5));
      expect(route(d, const Cell(3, 4), const Cell(3, 5), guest: true), isNull);
      expect(route(d, const Cell(3, 4), const Cell(3, 5)), isNotNull);
    });

    test('a seat only the kitchen leads to is not a seat', () {
      final d = room();
      d.place(Kind.table, const Cell(3, 4));
      d.place(Kind.chair, const Cell(2, 4), Dir.se);
      expect(d.seats(), hasLength(1));
      // Wall the chair in on the other sides, leaving only a kitchen tile.
      d.walls
        ..add(const Edge(2, 4, true))
        ..add(const Edge(2, 5, true))
        ..add(const Edge(2, 4, false));
      d.kitchen.add(const Cell(1, 4));
      expect(d.reachable().contains(const Cell(1, 4)), isTrue);
      expect(d.reachable(guest: true).contains(const Cell(1, 4)), isFalse);
      expect(d.seats(), isEmpty);
    });
  });

  group('the day', () {
    test('guests are never on kitchen floor', () {
      final d = Diner.starter();
      d.progress
        ..level = 4
        ..reputation = 70;
      d.goalsDone.addAll([for (final g in goals) g.id]);
      // The back row, by the grill and counters, is the kitchen.
      for (var x = Diner.left; x < Diner.left + 6; x++) {
        d.kitchen.add(Cell(x, Diner.top));
      }
      final sim = DinerSim(d, seed: 3);
      var guestsSeen = 0;
      while (!sim.finished && sim.ticks < 2000) {
        sim.tick();
        for (final g in sim.guests) {
          if (g.gone) continue;
          guestsSeen++;
          expect(
            d.kitchen.contains(g.cell),
            isFalse,
            reason: 'tick ${sim.ticks}',
          );
        }
      }
      expect(guestsSeen, greaterThan(0));
    });

    test('the hatch has its kitchen side where the floor is', () {
      final d = room();
      d.walls.add(const Edge(5, 5, true));
      d.hatches.add(const Edge(5, 5, true));
      d.kitchen.add(const Cell(5, 4));
      final sim = DinerSim(d, seed: 1);
      expect(sim.passes, hasLength(1));
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
      d.coins = 500;
      d.goalsDone.addAll([for (final g in goals) g.id]);
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(HexApp(home: BuildScreen(diner: d)));
      await tester.pump();
      return d;
    }

    testWidgets('it is on the shelf, and painting shows Paint, Erase, Done', (
      tester,
    ) async {
      await open(tester);
      await openShelf(tester, Kind.kitchenFloor);
      final tile = find.byKey(const ValueKey('fixture-kitchenFloor'));
      await tester.scrollUntilVisible(
        tile,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(tile);
      await tester.pump();
      expect(find.byKey(const ValueKey('paint-on')), findsOneWidget);
      expect(find.byKey(const ValueKey('paint-off')), findsOneWidget);
      expect(find.textContaining('lay kitchen floor'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('paint-off')));
      await tester.pump();
      expect(find.textContaining('take them off'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cancel-edit')));
      await tester.pump();
      expect(find.byKey(const ValueKey('paint-on')), findsNothing);
    });

    testWidgets(
      'tapping the board paints a tile, once, and Undo takes it off',
      (tester) async {
        final d = await open(tester);
        await openShelf(tester, Kind.kitchenFloor);
        final tile = find.byKey(const ValueKey('fixture-kitchenFloor'));
        await tester.scrollUntilVisible(
          tile,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(tile);
        await tester.pump();
        final board = find.byKey(const ValueKey('diner-board'));
        final painter =
            tester.widget<CustomPaint>(board).painter! as DinerPainter;
        Offset at(Cell c) =>
            tester.getTopLeft(board) +
            painter.fit.view.vertex(c.x + 0.5, c.y + 0.5) * painter.fit.s;
        final before = d.coins;
        await tester.tapAt(at(const Cell(3, 5)));
        await tester.pump();
        expect(d.kitchen, {const Cell(3, 5)});
        expect(d.coins, before - 4);
        await tester.tapAt(at(const Cell(3, 5)));
        await tester.pump();
        expect(d.coins, before - 4, reason: 'painted already: nothing more');
        await tester.tap(find.byKey(const ValueKey('cancel-edit')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('undo')));
        await tester.pump();
        expect(d.kitchen, isEmpty);
        expect(d.coins, before);
      },
    );
  });
}
