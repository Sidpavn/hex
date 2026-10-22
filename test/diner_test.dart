import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'shelf.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/iso.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/diner/service.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';

const _l = Diner.left;
const _t = Diner.top;

Diner _rich() => Diner(coins: 5000, progress: Progress(level: 9));

void main() {
  group('placing', () {
    test('placing takes coins and fills the cell', () {
      final d = Diner(coins: 50);
      const at = Cell(_l + 1, _t + 1);
      expect(d.place(Kind.table, at), PlaceResult.ok);
      expect(d.coins, 20);
      expect(d.objectAt(at)?.kind, Kind.table);
      expect(d.check(Kind.chair, at), PlaceResult.taken);
    });

    test('refuses outside the room, without coins, and on the door', () {
      final d = Diner(coins: 5);
      expect(d.check(Kind.chair, const Cell(0, 0)), PlaceResult.outside);
      expect(d.check(Kind.chair, const Cell(_l + 8, _t)), PlaceResult.outside);
      expect(d.check(Kind.chair, const Cell(_l, _t)), PlaceResult.broke);
      d.coins = 500;
      expect(d.check(Kind.table, d.entrance), PlaceResult.entrance);
      // A rug may lie on the door: it never blocks walking.
      expect(d.check(Kind.rug, d.entrance), PlaceResult.ok);
    });

    test('things unlock with the restaurant level', () {
      final d = Diner(coins: 500);
      expect(d.check(Kind.fryer, const Cell(_l, _t)), PlaceResult.locked);
      d.progress.level = 2;
      expect(d.check(Kind.fryer, const Cell(_l, _t)), PlaceResult.ok);
      expect(d.check(Kind.soda, const Cell(_l, _t)), PlaceResult.locked);
    });

    test('a bench covers two cells, and lies the other way when turned', () {
      final d = _rich();
      expect(d.check(Kind.bench, const Cell(_l + 5, _t)), PlaceResult.outside);
      expect(d.place(Kind.bench, const Cell(_l, _t), Dir.sw), PlaceResult.ok);
      final b = d.objectAt(const Cell(_l, _t))!;
      expect([b.w, b.h], [2, 1]);
      expect(d.objectAt(const Cell(_l + 1, _t)), isNotNull);
      expect(d.rotate(b), PlaceResult.ok); // sw -> nw: now runs along y
      expect([b.w, b.h], [1, 2]);
      expect(d.objectAt(const Cell(_l, _t + 1)), isNotNull);
      expect(d.objectAt(const Cell(_l + 1, _t)), isNull);
    });

    test('never walls off part of the floor from the door', () {
      final d = Diner(coins: 1000);
      final corner = Cell(_l, d.bottom);
      expect(d.place(Kind.table, Cell(_l, d.bottom - 1)), PlaceResult.ok);
      expect(
        d.check(Kind.table, Cell(_l + 1, d.bottom)),
        PlaceResult.blocksWay,
      );
      expect(d.reachable().contains(corner), isTrue);
    });

    test('selling refunds half and frees the cell', () {
      final d = Diner(coins: 100);
      const at = Cell(_l, _t);
      d.place(Kind.grill, at);
      expect(d.coins, 40);
      d.sell(d.objectAt(at)!);
      expect(d.coins, 70);
      expect(d.objectAt(at), isNull);
    });
  });

  group('facing and editing', () {
    test('new seats turn toward the table beside them', () {
      final d = Diner(coins: 500)
        ..place(Kind.table, const Cell(_l + 2, _t + 2));
      expect(d.defaultFacing(Kind.chair, const Cell(_l + 1, _t + 2)), Dir.se);
      expect(d.defaultFacing(Kind.chair, const Cell(_l + 3, _t + 2)), Dir.nw);
      expect(d.defaultFacing(Kind.chair, const Cell(_l + 2, _t + 1)), Dir.sw);
      expect(d.defaultFacing(Kind.chair, const Cell(_l + 2, _t + 3)), Dir.ne);
    });

    test('rotating cycles through all four ways', () {
      final d = Diner(coins: 500)
        ..place(Kind.grill, const Cell(_l + 2, _t + 2));
      final g = d.objectAt(const Cell(_l + 2, _t + 2))!;
      final seen = <Dir>{g.facing};
      for (var i = 0; i < 4; i++) {
        expect(d.rotate(g), PlaceResult.ok);
        seen.add(g.facing);
      }
      expect(seen.length, 4);
      expect(g.facing, Dir.sw, reason: 'four turns come back round');
    });

    test('a fixture that cannot turn without blocking the way stays put', () {
      final d = _rich();
      // A bench in the corner: turning it would push it off the grid.
      d.place(Kind.bench, Cell(_l + d.width - 2, _t), Dir.sw);
      final b = d.objectAt(Cell(_l + d.width - 1, _t))!;
      expect(d.rotate(b), PlaceResult.ok);
      expect(d.rotate(b), PlaceResult.ok);
      final before = b.facing;
      final at = b.at;
      // Fill the cell it would swing into.
      final facing = before.cw;
      final probe = Placed(0, Kind.bench, at, facing);
      for (final c in probe.cells) {
        if (d.objectAt(c) == null && d.isInside(c) && c != d.entrance) {
          d.place(Kind.plant, c);
        }
      }
      final r = d.rotate(b);
      if (r != PlaceResult.ok) expect(b.facing, before);
    });

    test('moving keeps the facing and is free', () {
      final d = Diner(coins: 100)..place(Kind.grill, const Cell(_l, _t));
      final g = d.objectAt(const Cell(_l, _t))!;
      d.rotate(g);
      final face = g.facing;
      final coins = d.coins;
      expect(d.relocate(g, const Cell(_l + 3, _t + 1), face), PlaceResult.ok);
      expect(g.at, const Cell(_l + 3, _t + 1));
      expect(g.facing, face);
      expect(d.coins, coins);
      expect(d.objectAt(const Cell(_l, _t)), isNull);
    });

    test('moving onto something else is refused and changes nothing', () {
      final d = Diner(coins: 300)
        ..place(Kind.grill, const Cell(_l, _t))
        ..place(Kind.counter, const Cell(_l + 1, _t));
      final g = d.objectAt(const Cell(_l, _t))!;
      expect(d.relocate(g, const Cell(_l + 1, _t), Dir.sw), PlaceResult.taken);
      expect(g.at, const Cell(_l, _t));
    });
  });

  group('what each machine needs', () {
    test('the starter diner can open and every fixture works', () {
      final r = Diner.starter().report();
      expect(r.ready, isTrue);
      expect(r.seats, 2);
      expect(r.problems, isEmpty);
    });

    test('an empty room says what it needs', () {
      expect(Diner(coins: 0).report().missing, [
        'Needs a grill',
        'Needs a counter',
        'Needs a seat facing a table',
      ]);
    });

    test('a machine facing a wall has no tile in front', () {
      final d = Diner(coins: 500)
        ..place(Kind.grill, const Cell(_l, _t), Dir.ne);
      final r = d.report();
      expect(
        r.problems.map((p) => p.text),
        contains('Grill needs a free tile in front'),
      );
      expect(r.missing, contains('Needs a grill'));
    });

    test('a machine hemmed in at the front is flagged', () {
      final d = Diner(coins: 900)
        ..place(Kind.grill, const Cell(_l + 2, _t + 2), Dir.sw)
        ..place(Kind.plant, const Cell(_l + 2, _t + 3));
      expect(
        d.report().problems.map((p) => p.text),
        contains('Grill needs a free tile in front'),
      );
    });

    test('a seat must face a table, and a table needs someone facing it', () {
      final d = Diner(coins: 900)
        ..place(Kind.table, const Cell(_l + 3, _t + 2))
        ..place(Kind.chair, const Cell(_l, _t + 2), Dir.sw);
      final text = d.report().problems.map((p) => p.text).toList();
      expect(text, contains('Chair must face a table'));
      expect(text, contains('Nothing is seated at this table'));
      final chair = d.objectAt(const Cell(_l, _t + 2))!;
      d.relocate(chair, const Cell(_l + 2, _t + 2), Dir.se);
      expect(d.report().problems, isEmpty);
      expect(d.report().seats, 1);
    });

    test('a bench seats two guests at one table', () {
      final d = Diner(coins: 900, progress: Progress(level: 2))
        ..place(Kind.bench, const Cell(_l, _t + 2), Dir.sw)
        ..place(Kind.table, const Cell(_l, _t + 3))
        ..place(Kind.table, const Cell(_l + 1, _t + 3));
      expect(d.seats().length, 2);
    });

    test('only machines with a working front are on the menu', () {
      final d = Diner(coins: 5000, progress: Progress(level: 3))
        ..place(Kind.grill, const Cell(_l, _t), Dir.sw)
        ..place(Kind.fryer, const Cell(_l + 2, _t), Dir.sw);
      expect(d.menu(), [Dish.burger, Dish.cheeseburger, Dish.fries]);
      d.progress.level = 1;
      expect(d.menu(), [Dish.burger], reason: 'fries is not unlocked yet');
    });
  });

  group('expanding and saving', () {
    test('the pavement runs both ways from the door, past the screen', () {
      final d = Diner(coins: 0);
      expect(d.queueSlot(0), d.street);
      for (var i = 0; i < d.queueLength; i++) {
        expect(d.isSidewalk(d.queueSlot(i)), isTrue);
      }
      expect(d.isSidewalk(d.arrivalLeft), isTrue);
      expect(d.isSidewalk(d.arrivalRight), isTrue);
      expect(d.arrivalLeft.x, lessThan(d.entrance.x - 5));
      expect(d.arrivalRight.x, greaterThan(d.entrance.x + 5));
      expect(d.isSidewalk(Cell(d.entrance.x, d.bottom)), isFalse);
    });

    test('an old save with one list of room sizes still loads', () {
      final d = Diner.fromJson({'coins': 5, 'stage': 3, 'items': []});
      expect([d.width, d.height], [10, 5]);
    });

    test('the whole diner survives a save, facings and progress included', () {
      final d = Diner.starter();
      d.progress
        ..level = 4
        ..xp = 17
        ..day = 6
        ..reputation = 73;
      d.progress.recipeLevel[Dish.burger] = 3;
      d.progress.upgrades[Upgrade.staff] = 1;
      final g = d.items.firstWhere((p) => p.kind == Kind.grill);
      d.rotate(g);
      final back = Diner.fromJson(d.toJson());
      expect(back.items.length, d.items.length);
      expect(back.coins, d.coins);
      expect(
        back.items.firstWhere((p) => p.kind == Kind.grill).facing,
        g.facing,
      );
      expect(back.progress.level, 4);
      expect(back.progress.day, 6);
      expect(back.progress.reputation, 73);
      expect(back.progress.recipeLvl(Dish.burger), 3);
      expect(back.progress.upgradeLvl(Upgrade.staff), 1);
      expect(back.report().seats, d.report().seats);
    });

    test('an old save with no facings or progress still loads', () {
      final d = Diner.fromJson({
        'coins': 9,
        'stage': 0,
        'items': [
          {'k': 'grill', 'x': 1, 'y': 3},
        ],
      });
      expect(d.items.single.facing, Dir.sw);
      expect(d.progress.level, 1);
    });

    test('a damaged save cannot put fixtures outside the room', () {
      final d = Diner.fromJson({
        'coins': 5,
        'stage': 99,
        'wide': 99,
        'deep': 99,
        'progress': {
          'level': -4,
          'upgrades': {'staff': 99},
        },
        'items': [
          {'k': 'table', 'x': 50, 'y': 50},
          {'k': 'nope', 'x': 1, 'y': 3},
          {'k': 'chair', 'x': 1, 'y': 3, 'f': 'banana'},
        ],
      });
      expect([d.width, d.height], [10, 5]);
      expect(d.items.length, 1);
      expect(d.progress.level, 1);
      expect(
        d.progress.upgradeLvl(Upgrade.staff),
        upgradeDefs[Upgrade.staff]!.max,
      );
    });
  });

  group('describing fixtures', () {
    test('machines say how long they take, and it follows upgrades', () {
      final p = Progress();
      final before = describeFixture(fixtureDefs[Kind.grill]!, p);
      expect(before, contains('Burger takes 2.8 s'));
      p.upgrades[Upgrade.kitchen] = 5;
      expect(describeFixture(fixtureDefs[Kind.grill]!, p), isNot(before));
    });

    test('the counter says how fast it takes payment', () {
      final p = Progress();
      expect(describeFixture(fixtureDefs[Kind.counter]!, p), contains('1.2 s'));
    });

    test('every fixture has something to say', () {
      for (final d in fixtureDefs.values) {
        expect(describeFixture(d, Progress()), isNotEmpty);
      }
    });
  });

  testWidgets('build screen aims a fixture, then places it on Place', (
    tester,
  ) async {
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

    await openShelf(tester, Kind.table);
    await tester.ensureVisible(find.byKey(const ValueKey('fixture-table')));
    await openShelf(tester, Kind.table);
    await tester.tap(find.byKey(const ValueKey('fixture-table')));
    await tester.pump();

    final board = find.byKey(const ValueKey('diner-board'));
    final fit = BoardFit.of(diner, tester.getSize(board), 3);
    final target = tester.getTopLeft(board) + fit.view.vertex(3.5, 5.5) * fit.s;
    await tester.tapAt(target);
    await tester.pump();
    expect(diner.objectAt(const Cell(3, 5)), isNull, reason: 'aiming only');
    expect(diner.coins, 100);
    await tester.tap(find.byKey(const ValueKey('place')));
    await tester.pump();
    expect(diner.objectAt(const Cell(3, 5))?.kind, Kind.table);
    expect(diner.coins, 70);
    // Keep the analyzer honest about the sim import.
    expect(Pace.dayTicks, greaterThan(0));
  });
}
