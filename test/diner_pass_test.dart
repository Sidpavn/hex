// The pass: cooks leave finished dishes on it, servers carry them out.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/actor.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/person_screen.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';
import 'package:hex/ui/widgets.dart' show PxText;
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/goals.dart';
import 'package:hex/diner/guide.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/diner/service.dart';
import 'package:hex/diner/staff.dart';

Staff person(int id, String name, {required bool cook}) => Staff(
  id: id,
  name: name,
  stats: {
    Stat.cooking: cook ? 8 : 2,
    Stat.speed: 4,
    Stat.service: cook ? 2 : 8,
    Stat.charm: 5,
  },
  potential: {for (final s in Stat.values) s: 10},
);

/// A restaurant with a kitchen wall, a door in it, and a pass in the wall
/// beside the door. The cooks and servers are as given.
Diner kitchen({bool withPass = true, List<Staff>? team, int level = 5}) {
  final d = Diner(
    coins: 100000,
    owned: {0, 1},
    progress: Progress(level: level, reputation: 70, day: 4),
  );
  d.declined.addAll([
    Dish.cheeseburger,
    Dish.hotDog,
    Dish.onionRings,
    Dish.chickenSandwich,
    Dish.nuggets,
    Dish.milkshake,
    Dish.baconBurger,
    Dish.sundae,
  ]);
  d.goalsDone.addAll([for (final g in goals) g.id]);
  d.progress.upgrades[Upgrade.staff] = 2;
  d.roster.employees
    ..clear()
    ..addAll(
      team ??
          [person(70, 'Cook', cook: true), person(71, 'Server', cook: false)],
    );
  d.place(Kind.grill, const Cell(1, 3), Dir.sw);
  d.place(Kind.grill, const Cell(2, 3), Dir.sw);
  d.place(Kind.counter, const Cell(9, 7), Dir.nw);
  d.place(Kind.counter, const Cell(9, 6), Dir.nw);
  // A kitchen wall under the grills with a door at x = 4, and the pass set
  // in it at x = 5.
  for (var x = 1; x <= 6; x++) {
    if (x != 4) d.walls.add(Edge(x, 5, true));
  }
  if (withPass) d.hatches.add(const Edge(5, 5, true));
  for (final t in const [Cell(3, 7), Cell(6, 7), Cell(8, 4)]) {
    d.place(Kind.table, t);
    d.place(Kind.chair, Cell(t.x - 1, t.y), Dir.se);
    d.place(Kind.chair, Cell(t.x + 1, t.y), Dir.nw);
  }
  d.menu();
  return d;
}

DinerSim run(Diner d, {int seed = 3, void Function(DinerSim sim)? each}) {
  final sim = DinerSim(d, seed: seed);
  while (!sim.finished && sim.ticks < 2500) {
    sim.tick();
    each?.call(sim);
  }
  return sim;
}

void main() {
  _moveTests();
  group('the piece', () {
    const hatch = Edge(5, 5, true);

    test('is on the shelf from level 3, and sits in the kitchen wall', () {
      final def = fixtureDefs[Kind.pass]!;
      expect(def.role, Role.pass);
      expect(def.unlock, 3);
      expect(def.cost, 60);
      expect(def.info, contains('four dishes'));
      final d = kitchen();
      expect(d.hatches, {hatch});
      expect(d.walls, contains(hatch), reason: 'it is a hole in a wall');
    });

    test('is reached from either side, and not from inside a wall', () {
      final d = kitchen();
      expect(d.hatchSides(hatch), [const Cell(5, 4), const Cell(5, 5)]);
    });

    test('a side taken by a fixture is not a side', () {
      final d = kitchen();
      d.place(Kind.plant, const Cell(5, 5));
      expect(d.hatchSides(hatch), [const Cell(5, 4)]);
    });

    test('is refused where nobody could stand beside it', () {
      final d = Diner(
        coins: 10000,
        owned: {0, 1},
        progress: Progress(level: 4),
      );
      d.place(Kind.plant, const Cell(5, 4));
      d.place(Kind.plant, const Cell(5, 5));
      expect(d.checkHatch(hatch), PlaceResult.noRoom);
      expect(PlaceResult.noRoom.message, contains('free tile'));
    });

    test('nobody walks through it, like any wall', () {
      final d = kitchen();
      expect(d.canWalk(const Cell(5, 4), const Cell(5, 5)), isFalse);
      expect(
        d.canWalk(const Cell(4, 4), const Cell(4, 5)),
        isTrue,
        reason: 'the door',
      );
    });

    test('costs 60, and takes in a wall that was there, for its price', () {
      final d = Diner(coins: 1000, owned: {0, 1}, progress: Progress(level: 4));
      d.walls.add(hatch);
      final before = d.coins;
      expect(d.placeHatch(hatch), PlaceResult.ok);
      expect(before - d.coins, 60 - 3);
      expect(d.hatches, {hatch});
      expect(d.walls, {hatch});
      final bare = Diner(
        coins: 1000,
        owned: {0, 1},
        progress: Progress(level: 4),
      );
      expect(bare.placeHatch(const Edge(4, 6, true)), PlaceResult.ok);
      expect(1000 - bare.coins, 60);
    });

    test('is sold back for half, taking the wall with it', () {
      final d = kitchen();
      final before = d.coins;
      expect(d.sellWall(hatch), isTrue);
      expect(d.coins - before, 30);
      expect(d.hatches, isEmpty);
      expect(d.walls, isNot(contains(hatch)));
    });

    test('undo takes it out, and puts it back when sold', () {
      final d = Diner(coins: 1000, owned: {0, 1}, progress: Progress(level: 4));
      d.placeHatch(hatch);
      d.undo();
      expect(d.hatches, isEmpty);
      expect(d.walls, isEmpty);
      d.placeHatch(hatch);
      d.sellWall(hatch);
      d.undo();
      expect(d.hatches, {hatch});
    });

    test('is saved, and is not a hatch where there is no wall', () {
      final d = kitchen();
      final back = Diner.fromJson(d.toJson());
      expect(back.hatches, {hatch});
      final j = d.toJson();
      j['hatches'] = [
        [5, 5, 1],
        [9, 9, 1],
      ];
      expect(Diner.fromJson(j).hatches, {hatch});
    });
  });

  group('walls from an older save, which stood on tiles', () {
    Map<String, Object?> save(List<Map<String, Object?>> items) {
      final j = Diner(
        coins: 100,
        owned: {0, 1},
        progress: Progress(level: 4),
      ).toJson();
      j['items'] = items;
      return j;
    }

    Map<String, Object?> tile(String kind, int x, int y, String facing) => {
      'k': kind,
      'x': x,
      'y': y,
      'f': facing,
    };

    test('a row becomes a wall along the north side of its tiles', () {
      final d = Diner.fromJson(
        save([
          tile('wall', 3, 5, 'sw'),
          tile('wall', 4, 5, 'sw'),
          tile('wall', 5, 5, 'sw'),
        ]),
      );
      expect(d.walls, {
        const Edge(3, 5, true),
        const Edge(4, 5, true),
        const Edge(5, 5, true),
      });
      expect(d.items, isEmpty, reason: 'the tiles are free again');
    });

    test('a column becomes a wall along the west side', () {
      final d = Diner.fromJson(
        save([tile('wall', 4, 4, 'se'), tile('wall', 4, 5, 'se')]),
      );
      expect(d.walls, {const Edge(4, 4, false), const Edge(4, 5, false)});
    });

    test('a corner keeps both arms', () {
      final d = Diner.fromJson(
        save([
          tile('wall', 3, 5, 'sw'),
          tile('wall', 4, 5, 'sw'),
          tile('wall', 5, 5, 'sw'),
          tile('wall', 5, 6, 'se'),
          tile('wall', 5, 7, 'se'),
        ]),
      );
      // The corner tile has a neighbour along x and one along y.
      expect(d.walls, contains(const Edge(5, 5, true)));
      expect(d.walls, contains(const Edge(5, 5, false)));
      expect(d.walls, contains(const Edge(5, 6, false)));
      expect(d.walls, contains(const Edge(5, 7, false)));
    });

    test('a lone piece runs the way it faced', () {
      expect(Diner.fromJson(save([tile('wall', 4, 4, 'sw')])).walls, {
        const Edge(4, 4, true),
      });
      expect(Diner.fromJson(save([tile('wall', 4, 4, 'nw')])).walls, {
        const Edge(4, 4, false),
      });
    });

    test('a pass becomes a hatch in the wall beside it', () {
      final d = Diner.fromJson(
        save([
          tile('wall', 4, 5, 'sw'),
          tile('pass', 5, 5, 'sw'),
          tile('wall', 6, 5, 'sw'),
        ]),
      );
      expect(d.hatches, {const Edge(5, 5, true)});
      expect(d.walls, {
        const Edge(4, 5, true),
        const Edge(5, 5, true),
        const Edge(6, 5, true),
      });
    });

    test(
      'fixtures are not touched, and edges outside the room are dropped',
      () {
        final d = Diner.fromJson(
          save([tile('grill', 1, 3, 'sw'), tile('wall', 30, 30, 'sw')]),
        );
        expect(d.items.map((p) => p.kind), [Kind.grill]);
        expect(d.walls, isEmpty);
      },
    );

    test('and saving it again keeps the edges, not the tiles', () {
      final d = Diner.fromJson(save([tile('wall', 4, 5, 'sw')]));
      final j = d.toJson();
      expect(
        (j['items'] as List).where((i) => (i as Map)['k'] == 'wall'),
        isEmpty,
      );
      expect(Diner.fromJson(j).walls, {const Edge(4, 5, true)});
    });
  });

  group('who goes where', () {
    test('cooks stand in the kitchen, servers in the dining room', () {
      // The grills are north of the wall, so the kitchen side is y = 4.
      final sim = DinerSim(kitchen(), seed: 3);
      final seen = <String, int>{};
      final prev = <int, WorkState>{};
      while (!sim.finished && sim.ticks < 2500) {
        sim.tick();
        for (final w in sim.workers) {
          if (prev[w.staff.id] != w.state &&
              (w.state == WorkState.toShelf ||
                  w.state == WorkState.fromShelf)) {
            final end = w.path.isEmpty ? w.cell : w.path.last;
            final who = w.staff.id == 70 ? 'cook' : 'server';
            final side = end.y <= 4 ? 'kitchen' : 'dining';
            seen['$who $side'] = (seen['$who $side'] ?? 0) + 1;
          }
          prev[w.staff.id] = w.state;
        }
      }
      expect(seen['cook kitchen'], greaterThan(0));
      expect(seen['server dining'], greaterThan(0));
      expect(seen['cook dining'], isNull, reason: '$seen');
      expect(seen['server kitchen'], isNull, reason: '$seen');
    });

    test('a server fetches from the pass, not the machine', () {
      var atMachine = 0;
      var fromPass = 0;
      final prev = <int, WorkState>{};
      final sim = DinerSim(kitchen(), seed: 4);
      while (!sim.finished && sim.ticks < 2500) {
        sim.tick();
        for (final w in sim.workers) {
          if (w.staff.id == 71 && prev[71] != w.state) {
            if (w.state == WorkState.toPickup) atMachine++;
            if (w.state == WorkState.fromShelf) fromPass++;
          }
          prev[w.staff.id] = w.state;
        }
      }
      expect(fromPass, greaterThan(atMachine * 5));
    });
  });

  group('with no pass, the day is as it was', () {
    test('nothing is ever left on one', () {
      var onPass = 0;
      run(
        kitchen(withPass: false),
        each: (sim) {
          for (final g in sim.guests) {
            onPass += g.items.where((i) => i.state == ItemState.onPass).length;
          }
        },
      );
      expect(onPass, 0);
    });

    test('and the cook carries food out when nobody else will', () {
      final d = kitchen(withPass: false);
      final sim = run(d);
      expect(sim.served, greaterThan(0));
    });
  });

  group('with a pass', () {
    test('cooks leave dishes on it, and servers carry them out', () {
      final d = kitchen();
      var seenOnPass = 0;
      final sim = run(
        d,
        each: (sim) {
          seenOnPass += sim.passes.fold(0, (a, p) => a + p.plates.length);
        },
      );
      expect(seenOnPass, greaterThan(0), reason: 'dishes went on the pass');
      final cook = sim.workers.firstWhere((w) => w.staff.name == 'Cook');
      final server = sim.workers.firstWhere((w) => w.staff.name == 'Server');
      expect(server.platesToday, greaterThan(0));
      expect(
        cook.platesToday,
        lessThan(server.platesToday),
        reason: 'the cook stays at the machines',
      );
    });

    test('it holds no more than four, and nothing for someone who left', () {
      var most = 0;
      run(
        kitchen(),
        each: (sim) {
          for (final p in sim.passes) {
            most = most < p.plates.length ? p.plates.length : most;
            expect(p.plates.length, lessThanOrEqualTo(p.capacity));
            expect(p.reserved, greaterThanOrEqualTo(0));
            for (final i in p.plates) {
              expect(i.state, ItemState.onPass);
              expect(i.guest.gone, isFalse);
            }
          }
        },
      );
      expect(most, greaterThan(0));
    });

    test('a bigger pass upgrade holds one more plate per level', () {
      final d = kitchen()..progress.upgrades[Upgrade.pass] = 2;
      final sim = DinerSim(d, seed: 3);
      expect(sim.passes, isNotEmpty);
      for (final p in sim.passes) {
        expect(p.capacity, 6);
      }
    });

    test(
      'a cook and a server never both stand at the hatch to use it at once',
      () {
        // One cook, one server: both reach for the pass constantly, so this
        // is the scenario most likely to stack them on its one-tile sides.
        // Crossing paths on the way to deliver elsewhere is fine; both
        // being there *for the pass* on the same tile is the deadlock.
        const hatch = Edge(5, 5, true);
        for (final seed in [1, 2, 3, 4, 5, 6]) {
          final d = kitchen();
          final sim = DinerSim(d, seed: seed);
          while (!sim.finished && sim.ticks < 2500) {
            sim.tick();
            final atHatch = sim.workers.where(
              (w) =>
                  (w.state == WorkState.toShelf ||
                      w.state == WorkState.fromShelf) &&
                  d.hatchSides(hatch).contains(w.cell),
            );
            final byCell = <Cell, int>{};
            for (final w in atHatch) {
              byCell[w.cell] = (byCell[w.cell] ?? 0) + 1;
            }
            for (final n in byCell.values) {
              expect(n, 1, reason: 'seed $seed: two workers using one tile');
            }
          }
        }
      },
    );

    List<Staff> crew() => [
      person(70, 'CookA', cook: true),
      person(73, 'CookB', cook: true),
      person(71, 'ServerA', cook: false),
      person(72, 'ServerB', cook: false),
    ];

    test('with servers to carry, guests are served as well as without', () {
      var withPass = 0;
      var without = 0;
      for (var seed = 1; seed <= 6; seed++) {
        withPass += run(kitchen(team: crew()), seed: seed).served;
        without += run(
          kitchen(withPass: false, team: crew()),
          seed: seed,
        ).served;
      }
      // A one-tile hatch side now makes a cook and a server queue for their
      // turn rather than overlap on it, which costs a few percent.
      expect(withPass, greaterThanOrEqualTo((without * 0.9).floor()));
    });

    test('with a cook and one server it still works, if a little slower', () {
      var withPass = 0;
      var without = 0;
      for (var seed = 1; seed <= 6; seed++) {
        withPass += run(kitchen(), seed: seed).served;
        without += run(kitchen(withPass: false), seed: seed).served;
      }
      expect(withPass, greaterThan(without * 0.7));
    });

    test('the cooks carry less when there are servers and a pass', () {
      var cooks = 0;
      var cooksWithout = 0;
      for (var seed = 1; seed <= 4; seed++) {
        final a = run(kitchen(team: crew()), seed: seed);
        final b = run(kitchen(withPass: false, team: crew()), seed: seed);
        int plates(DinerSim s) => s.workers
            .where((w) => w.staff.kitchen)
            .fold(0, (n, w) => n + w.platesToday);
        cooks += plates(a);
        cooksWithout += plates(b);
      }
      expect(cooks, lessThan(cooksWithout));
    });

    test('with only cooks the food still reaches the tables', () {
      final d = kitchen(
        team: [
          person(70, 'CookA', cook: true),
          person(71, 'CookB', cook: true),
        ],
      );
      final sim = run(d);
      expect(sim.served, greaterThan(0));
      // Nobody is stuck holding a dish at the end.
      for (final p in sim.passes) {
        expect(p.plates.where((i) => !i.guest.gone), isEmpty);
      }
    });

    test('a dish nobody has fetched is still fetched after a while', () {
      // One cook who is also the only one free: the pass cannot be a dead end.
      final d = kitchen(team: [person(70, 'Solo', cook: true)]);
      final sim = run(d);
      expect(sim.served, greaterThan(0));
    });

    test('plates on the pass are drawn', () {
      final d = kitchen();
      final sim = DinerSim(d, seed: 3);
      var drawn = 0;
      for (var i = 0; i < 500 && !sim.finished; i++) {
        sim.tick();
        final onPass = sim.passes.fold(0, (a, p) => a + p.plates.length);
        if (onPass == 0) continue;
        final plates = sim
            .actors(0)
            .where((a) => a.sprite.startsWith('plate_') && a.lift == 9)
            .length;
        expect(plates, onPass);
        drawn++;
      }
      expect(drawn, greaterThan(0));
    });
  });

  group('kept to serve food', () {
    /// A kitchen where [server] is kept to serve and cooks are everyone else.
    Diner serving({bool withPass = true, List<Staff>? team}) {
      final d = kitchen(
        withPass: withPass,
        team:
            team ??
            [
              person(70, 'Cook', cook: true),
              person(71, 'Runner', cook: true),
              person(72, 'Server', cook: false),
            ],
      );
      d.roster.employees.firstWhere((e) => e.name == 'Runner').duty = Kind.pass;
      return d;
    }

    test('they never go to a machine to cook', () {
      var loads = 0;
      var delivered = 0;
      run(
        serving(),
        each: (sim) {
          final w = sim.workers.firstWhere((w) => w.staff.name == 'Runner');
          if (w.state == WorkState.toLoad) loads++;
          delivered = w.platesToday;
        },
      );
      expect(loads, 0, reason: 'a runner does not cook');
      expect(delivered, greaterThan(0), reason: 'a runner carries food out');
    });

    test('even a cook by trade carries instead of cooking', () {
      final d = serving();
      final runner = d.roster.employees.firstWhere((e) => e.name == 'Runner');
      expect(runner.kitchen, isTrue);
      final sim = run(d);
      final w = sim.workers.firstWhere((w) => w.staff.name == 'Runner');
      expect(w.platesToday, greaterThan(0));
    });

    test('the cooks stay at the machines, and leave the carrying to them', () {
      var cooks = 0;
      var cooksPlain = 0;
      for (var seed = 1; seed <= 4; seed++) {
        int plates(DinerSim s) => s.workers
            .where((w) => w.staff.name == 'Cook')
            .fold(0, (n, w) => n + w.platesToday);
        cooks += plates(run(serving(), seed: seed));
        final plain = kitchen(
          team: [
            person(70, 'Cook', cook: true),
            person(71, 'Runner', cook: true),
            person(72, 'Server', cook: false),
          ],
        );
        cooksPlain += plates(run(plain, seed: seed));
      }
      expect(cooks, lessThanOrEqualTo(cooksPlain));
    });

    test('works with no pass too: they carry from the machines', () {
      final sim = run(serving(withPass: false));
      expect(sim.served, greaterThan(0));
      final w = sim.workers.firstWhere((w) => w.staff.name == 'Runner');
      expect(w.platesToday, greaterThan(0));
    });

    test('if everyone is kept to serve, someone cooks anyway', () {
      final team = [person(70, 'A', cook: true), person(71, 'B', cook: false)];
      final d = kitchen(team: team);
      for (final e in d.roster.employees) {
        e.duty = Kind.pass;
      }
      final sim = run(d);
      expect(sim.served, greaterThan(0), reason: 'nobody was left to cook');
    });
  });

  group('the choice on a person page', () {
    Future<void> open(WidgetTester tester, Diner d, Staff s) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
      });
      Storage.clearMemory();
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        HexApp(
          home: PersonScreen(diner: d, staff: s),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('Serves food is a switch, on to start with', (tester) async {
      final d = kitchen();
      final s = d.roster.employees.first;
      await open(tester, d, s);
      final chip = find.byKey(ValueKey('task-${s.id}-serve'));
      await tester.scrollUntilVisible(
        chip,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Serves food'), findsOneWidget);
      expect(s.does(Task.serve), isTrue);
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pump();
      expect(s.does(Task.serve), isFalse);
      await tester.tap(chip);
      await tester.pump();
      expect(s.does(Task.serve), isTrue);
      expect(
        tester.widget<PxText>(find.byKey(ValueKey('duty-help-${s.id}'))).text,
        contains('carries food out'),
      );
    });

    testWidgets('with no machines there is nothing to choose to cook at', (
      tester,
    ) async {
      final d = Diner(coins: 100, progress: Progress(level: 3));
      d.roster.employees
        ..clear()
        ..add(person(70, 'Solo', cook: false));
      await open(tester, d, d.roster.employees.first);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('task-70-serve')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const ValueKey('cook-70-all')), findsNothing);
    });
  });

  test('the guide tells players about the pass', () {
    final all = guidePages.expand((p) => p.lines).join(' ');
    expect(all, contains('pass'));
  });

  test('actors still draw without one', () {
    final sim = DinerSim(kitchen(withPass: false), seed: 1);
    for (var i = 0; i < 100; i++) {
      sim.tick();
    }
    expect(sim.actors(0), isA<List<Actor>>());
    expect(sim.passes, isEmpty);
  });
}

void _moveTests() {
  group('moving and turning a wall', () {
    Diner room() =>
        Diner(coins: 1000, owned: {0, 1}, progress: Progress(level: 4));

    test('a wall moves to a free edge for nothing, and undoes', () {
      final d = room();
      d.walls.add(const Edge(3, 5, true));
      final coins = d.coins;
      expect(
        d.moveWall(const Edge(3, 5, true), const Edge(6, 6, false)),
        PlaceResult.ok,
      );
      expect(d.walls, {const Edge(6, 6, false)});
      expect(d.coins, coins);
      d.undo();
      expect(d.walls, {const Edge(3, 5, true)});
    });

    test('a hatch takes its hatch with it', () {
      final d = room();
      d.walls.add(const Edge(3, 5, true));
      d.hatches.add(const Edge(3, 5, true));
      d.moveWall(const Edge(3, 5, true), const Edge(4, 5, true));
      expect(d.hatches, {const Edge(4, 5, true)});
      expect(d.walls, {const Edge(4, 5, true)});
    });

    test('it will not go onto another wall or outside', () {
      final d = room();
      d.walls.addAll([const Edge(3, 5, true), const Edge(4, 5, true)]);
      expect(
        d.moveWall(const Edge(3, 5, true), const Edge(4, 5, true)),
        PlaceResult.taken,
      );
      expect(
        d.moveWall(const Edge(3, 5, true), const Edge(-9, 5, true)),
        PlaceResult.outside,
      );
      expect(d.walls, hasLength(2));
    });

    test('checking a move changes nothing', () {
      final d = room();
      d.walls.add(const Edge(3, 5, true));
      for (var i = 0; i < 3; i++) {
        expect(
          d.checkMove(const Edge(3, 5, true), const Edge(5, 5, true)),
          PlaceResult.ok,
        );
      }
      expect(d.walls, {const Edge(3, 5, true)});
    });

    test('turning is a move to the other side of the same tile', () {
      final d = room();
      d.walls.add(const Edge(3, 5, true));
      expect(
        d.moveWall(const Edge(3, 5, true), const Edge(3, 5, false)),
        PlaceResult.ok,
      );
      expect(d.walls, {const Edge(3, 5, false)});
    });
  });
}
