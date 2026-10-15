import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/iso.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';

void main() {
  group('Diner grid', () {
    test('placing takes coins and fills the cell', () {
      final d = Diner(coins: 50);
      const at = Cell(Diner.left + 1, Diner.top + 1);
      expect(d.place(Kind.table, at), PlaceResult.ok);
      expect(d.coins, 20);
      expect(d.objectAt(at)?.kind, Kind.table);
      expect(d.check(Kind.chair, at), PlaceResult.taken);
    });

    test('refuses outside the room, without coins, and on the door', () {
      final d = Diner(coins: 5);
      expect(d.check(Kind.chair, const Cell(0, 0)), PlaceResult.outside);
      expect(
        d.check(Kind.chair, const Cell(Diner.left + 8, Diner.top)),
        PlaceResult.outside,
      );
      expect(
        d.check(Kind.chair, const Cell(Diner.left, Diner.top)),
        PlaceResult.broke,
      );
      d.coins = 500;
      expect(d.check(Kind.table, d.entrance), PlaceResult.entrance);
      // A rug may lie on the door mat's cell: it never blocks walking.
      expect(d.check(Kind.rug, d.entrance), PlaceResult.ok);
    });

    test('a 2 by 1 fixture needs both cells', () {
      final d = Diner(coins: 500);
      expect(
        d.check(Kind.bench, const Cell(Diner.left + 5, Diner.top)),
        PlaceResult.outside,
      );
      expect(
        d.place(Kind.bench, const Cell(Diner.left, Diner.top)),
        PlaceResult.ok,
      );
      expect(d.objectAt(const Cell(Diner.left + 1, Diner.top)), isNotNull);
      expect(
        d.check(Kind.chair, const Cell(Diner.left + 1, Diner.top)),
        PlaceResult.taken,
      );
    });

    test('never walls off part of the floor from the door', () {
      final d = Diner(coins: 1000);
      // Close the room's bottom-left corner pocket one cell at a time.
      final corner = Cell(Diner.left, d.bottom);
      expect(
        d.place(Kind.counter, Cell(Diner.left, d.bottom - 1)),
        PlaceResult.ok,
      );
      // Now the corner has one open neighbour, the cell beside it.
      expect(
        d.check(Kind.counter, Cell(Diner.left + 1, d.bottom)),
        PlaceResult.blocksWay,
      );
      expect(d.walkable(corner), isTrue);
      expect(d.reachable().contains(corner), isTrue);
    });

    test('selling refunds half and frees the cell', () {
      final d = Diner(coins: 100);
      const at = Cell(Diner.left, Diner.top);
      d.place(Kind.grill, at);
      expect(d.coins, 40);
      d.sell(d.objectAt(at)!);
      expect(d.coins, 70);
      expect(d.objectAt(at), isNull);
    });

    test('expanding costs coins and grows right and down only', () {
      final d = Diner(coins: 100);
      final entrance = d.entrance;
      expect(d.expand(), isTrue);
      expect(d.coins, 20);
      expect(d.width, 8);
      expect(d.isInside(const Cell(Diner.left + 7, Diner.top)), isTrue);
      expect(d.entrance, entrance);
      expect(d.expand(), isFalse);
      d.coins = 10000;
      while (d.expand()) {}
      expect(d.nextStage, isNull);
      expect(d.right, lessThan(Diner.cols - 1));
      expect(d.bottom, lessThan(Diner.rows - 1));
      expect(d.entrance.y, d.bottom);
    });

    test('starter layout is valid and survives a save', () {
      final d = Diner.starter();
      final open = d.reachable().length;
      final back = Diner.fromJson(d.toJson());
      expect(back.items.length, d.items.length);
      expect(back.coins, d.coins);
      expect(back.reachable().length, open);
    });

    test('a damaged save cannot put fixtures outside the room', () {
      final d = Diner.fromJson({
        'coins': 5,
        'stage': 99,
        'items': [
          {'k': 'table', 'x': 50, 'y': 50},
          {'k': 'nope', 'x': 1, 'y': 3},
          {'k': 'chair', 'x': 1, 'y': 3},
        ],
      });
      expect(d.stage, Diner.stages.length - 1);
      expect(d.items.length, 1);
    });
  });

  testWidgets('build screen places a fixture by dragging', (tester) async {
    await tester.runAsync(() async {
      await PixelAssets.load();
      await DinerArt.load();
    });
    Storage.clearMemory();
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final diner = Diner(coins: 100);
    await tester.pumpWidget(HexApp(home: BuildScreen(diner: diner)));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('fixture-table')));
    await tester.pump();

    final board = find.byKey(const ValueKey('diner-board'));
    final fit = BoardFit.of(diner, tester.getSize(board), 3);
    final target = tester.getTopLeft(board) + fit.view.vertex(3.5, 5.5) * fit.s;
    await tester.tapAt(target);
    await tester.pump();
    expect(diner.objectAt(const Cell(3, 5))?.kind, Kind.table);
    expect(diner.coins, 70);
  });
}
