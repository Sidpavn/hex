// What each person is set to do: which machines to cook at, and whether to
// carry food out, clear tables or run the window.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/goals.dart';
import 'package:hex/diner/person_screen.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/diner/service.dart';
import 'package:hex/diner/staff.dart';
import 'package:hex/diner/staff_screen.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';
import 'package:hex/ui/widgets.dart' show PxText;

Staff person(
  int id,
  String name, {
  Set<Task>? tasks,
  Set<Kind>? cooksAt,
  bool cook = true,
}) => Staff(
  id: id,
  name: name,
  stats: {
    Stat.cooking: cook ? 8 : 2,
    Stat.speed: 5,
    Stat.service: cook ? 2 : 8,
    Stat.charm: 5,
  },
  potential: {for (final s in Stat.values) s: 10},
  tasks: tasks,
  cooksAt: cooksAt,
);

/// A kitchen with a grill and a fryer, two counters and three tables.
Diner cafe(List<Staff> team) {
  final d = Diner(
    coins: 100000,
    owned: {0, 1},
    progress: Progress(level: 5, reputation: 70, day: 4),
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
  d.progress.upgrades[Upgrade.staff] = 3;
  d.roster.employees
    ..clear()
    ..addAll(team);
  d.place(Kind.grill, const Cell(1, 3), Dir.sw);
  d.place(Kind.grill, const Cell(2, 3), Dir.sw);
  d.place(Kind.fryer, const Cell(4, 3), Dir.sw);
  d.place(Kind.counter, const Cell(9, 7), Dir.nw);
  d.place(Kind.counter, const Cell(9, 6), Dir.nw);
  for (final t in const [Cell(3, 6), Cell(6, 6), Cell(8, 4)]) {
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
  group('the model', () {
    test('everyone starts cooking anywhere and carrying food out', () {
      final s = person(1, 'Sam');
      expect(s.tasks, {Task.serve});
      expect(s.cooksAt, isNull);
      expect(s.cooks, isTrue);
      expect(s.cooksAtKind(Kind.fryer), isTrue);
      expect(s.duty, isNull);
    });

    test('machines are chosen one by one, and none means no cooking', () {
      final s = person(1, 'Sam', cooksAt: {Kind.grill});
      expect(s.cooksAtKind(Kind.grill), isTrue);
      expect(s.cooksAtKind(Kind.fryer), isFalse);
      expect(person(2, 'Al', cooksAt: {}).cooks, isFalse);
    });

    test('it is all saved', () {
      final s = person(
        1,
        'Sam',
        tasks: {Task.serve, Task.clear},
        cooksAt: {Kind.grill, Kind.fryer},
      );
      final back = Staff.fromJson(s.toJson())!;
      expect(back.tasks, {Task.serve, Task.clear});
      expect(back.cooksAt, {Kind.grill, Kind.fryer});
      final none = Staff.fromJson(person(2, 'Al', cooksAt: {}).toJson())!;
      expect(none.cooksAt, isEmpty, reason: 'empty is not the same as all');
      final all = Staff.fromJson(person(3, 'Bo').toJson())!;
      expect(all.cooksAt, isNull);
    });

    Staff old(String? duty) {
      final j = person(1, 'Sam').toJson()
        ..remove('tasks')
        ..remove('cooks')
        ..remove('focus');
      if (duty != null) j['duty'] = duty;
      return Staff.fromJson(j)!;
    }

    test('a save with no duty works anywhere', () {
      final s = old(null);
      expect(s.tasks, {Task.serve});
      expect(s.cooksAt, isNull);
    });

    test('a save with a machine duty keeps looking after it first', () {
      final s = old('grill');
      expect(s.focus, Kind.grill);
      expect(s.cooksAt, isNull, reason: 'they still help at every machine');
      expect(s.tasks, {Task.serve});
    });

    test('a save kept for the tables only clears them', () {
      final s = old('table');
      expect(s.tasks, {Task.clear});
      expect(s.cooks, isFalse);
    });

    test('a save kept for the window only runs it', () {
      final s = old('window');
      expect(s.tasks, {Task.window});
      expect(s.cooks, isFalse);
    });

    test('a save kept to serve food only carries it', () {
      final s = old('pass');
      expect(s.tasks, {Task.serve});
      expect(s.cooks, isFalse);
    });

    test('an old duty survives being saved and loaded again', () {
      for (final k in [Kind.table, Kind.window, Kind.pass, Kind.grill, null]) {
        final s = person(1, 'Sam')..duty = k;
        expect(Staff.fromJson(s.toJson())!.duty, k, reason: '$k');
      }
    });
  });

  group('cooking at chosen machines', () {
    test('someone set to the fryer never cooks at the grill', () {
      final cooked = <String, Set<Kind>>{};
      final team = [
        person(70, 'GrillCook', cooksAt: {Kind.grill}),
        person(71, 'FryCook', cooksAt: {Kind.fryer}),
        person(72, 'Server', cooksAt: {}, cook: false),
      ];
      run(
        cafe(team),
        each: (sim) {
          for (final w in sim.workers) {
            final m = w.machine;
            if (w.state == WorkState.toLoad && m != null) {
              (cooked[w.staff.name] ??= {}).add(m.kind);
            }
          }
        },
      );
      expect(cooked['FryCook'] ?? {}, isNot(contains(Kind.grill)));
      expect(cooked['GrillCook'] ?? {}, isNot(contains(Kind.fryer)));
      expect(cooked['Server'] ?? {}, isEmpty);
      expect(cooked['GrillCook'], contains(Kind.grill));
      expect(cooked['FryCook'], contains(Kind.fryer));
    });

    test('a machine nobody is set to is still cooked at', () {
      var fried = 0;
      final team = [
        person(70, 'A', cooksAt: {Kind.grill}),
        person(71, 'B', cooksAt: {Kind.grill}),
        person(72, 'Server', cooksAt: {}, cook: false),
      ];
      final d = cafe(team);
      expect(d.uncoveredMachines, [Kind.fryer]);
      run(
        d,
        each: (sim) {
          for (final w in sim.workers) {
            final m = w.machine;
            if (w.state == WorkState.toLoad && m?.kind == Kind.fryer) fried++;
          }
        },
      );
      expect(fried, greaterThan(0), reason: 'fries were made by someone');
    });

    test('with everyone covering their machine nothing is uncovered', () {
      final d = cafe([
        person(70, 'A', cooksAt: {Kind.grill}),
        person(71, 'B', cooksAt: {Kind.fryer}),
      ]);
      expect(d.uncoveredMachines, isEmpty);
      expect(cafe([person(70, 'A')]).uncoveredMachines, isEmpty);
    });

    test('a restricted cook still serves a day as well as an open one', () {
      var open = 0;
      var split = 0;
      for (var seed = 1; seed <= 4; seed++) {
        open += run(
          cafe([
            person(70, 'A'),
            person(71, 'B'),
            person(72, 'S', cook: false),
          ]),
          seed: seed,
        ).served;
        split += run(
          cafe([
            person(70, 'A', cooksAt: {Kind.grill}),
            person(71, 'B', cooksAt: {Kind.fryer}),
            person(72, 'S', cook: false),
          ]),
          seed: seed,
        ).served;
      }
      expect(split, greaterThan(open * 0.8));
    });
  });

  group('carrying food out', () {
    test('someone not set to carry food leaves it to those who are', () {
      final team = [
        person(70, 'Cook', tasks: {}),
        person(71, 'Server', tasks: {Task.serve}, cooksAt: {}, cook: false),
      ];
      final sim = run(cafe(team));
      final cook = sim.workers.firstWhere((w) => w.staff.name == 'Cook');
      final server = sim.workers.firstWhere((w) => w.staff.name == 'Server');
      expect(server.platesToday, greaterThan(0));
      expect(
        cook.platesToday,
        lessThan(server.platesToday),
        reason: 'the cook only carries what has gone cold',
      );
    });

    test('if nobody is set to carry food, everyone does', () {
      final team = [person(70, 'A', tasks: {}), person(71, 'B', tasks: {})];
      final sim = run(cafe(team));
      expect(sim.served, greaterThan(0));
    });

    test('if nobody is set to cook, someone does', () {
      final team = [person(70, 'A', cooksAt: {}), person(71, 'B', cooksAt: {})];
      final sim = run(cafe(team));
      expect(sim.served, greaterThan(0));
    });
  });

  group('clearing tables', () {
    test('someone who clears and carries does both', () {
      final team = [
        person(70, 'Cook'),
        person(
          71,
          'Waiter',
          tasks: {Task.serve, Task.clear},
          cooksAt: {},
          cook: false,
        ),
      ];
      final sim = run(cafe(team));
      final waiter = sim.workers.firstWhere((w) => w.staff.name == 'Waiter');
      expect(waiter.platesToday, greaterThan(0));
      expect(sim.cleaned, greaterThan(0));
    });

    test('someone who only clears waits for a mess, and is not in the way', () {
      final team = [
        person(70, 'Cook'),
        person(71, 'Cleaner', tasks: {Task.clear}, cooksAt: {}, cook: false),
      ];
      final sim = run(cafe(team));
      final c = sim.workers.firstWhere((w) => w.staff.name == 'Cleaner');
      expect(c.platesToday, 0);
      expect(sim.served, greaterThan(0));
    });

    test('a cleaner on their own works like anyone, so food gets made', () {
      final team = [
        person(70, 'Only', tasks: {Task.clear}, cooksAt: {}),
      ];
      final sim = run(cafe(team));
      expect(sim.served, greaterThan(0));
    });
  });

  group('on screen', () {
    Future<void> show(WidgetTester tester, Diner d, Widget page) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
      });
      Storage.clearMemory();
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(HexApp(home: page));
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      final f = find.byKey(ValueKey(key));
      await tester.scrollUntilVisible(
        f,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(f);
      await tester.tap(f);
      await tester.pump();
    }

    String help(WidgetTester tester, Staff s) =>
        tester.widget<PxText>(find.byKey(ValueKey('duty-help-${s.id}'))).text;

    testWidgets('there is a switch for each machine, and for all of them', (
      tester,
    ) async {
      final d = cafe([person(70, 'Sam')]);
      final s = d.roster.employees.first;
      await show(tester, d, PersonScreen(diner: d, staff: s));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('cook-70-all')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const ValueKey('cook-70-grill')), findsOneWidget);
      expect(find.byKey(const ValueKey('cook-70-fryer')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('cook-70-oven')),
        findsNothing,
        reason: 'there is no oven',
      );
      expect(help(tester, s), contains('cooks at every machine'));
    });

    testWidgets('turning one off limits them, and says so', (tester) async {
      final d = cafe([person(70, 'Sam')]);
      final s = d.roster.employees.first;
      await show(tester, d, PersonScreen(diner: d, staff: s));
      await tapKey(tester, 'cook-70-fryer');
      expect(s.cooksAt, {Kind.grill});
      expect(help(tester, s), contains('cooks at the grill'));
      await tapKey(tester, 'cook-70-fryer');
      expect(s.cooksAt, isNull, reason: 'every machine is just all again');
    });

    testWidgets('all machines off means no cooking', (tester) async {
      final d = cafe([person(70, 'Sam')]);
      final s = d.roster.employees.first;
      await show(tester, d, PersonScreen(diner: d, staff: s));
      await tapKey(tester, 'cook-70-all');
      expect(s.cooksAt, isEmpty);
      expect(s.cooks, isFalse);
      await tapKey(tester, 'cook-70-all');
      expect(s.cooksAt, isNull);
    });

    testWidgets('the last thing cannot be turned off', (tester) async {
      final d = cafe([person(70, 'Sam', cooksAt: {})]);
      final s = d.roster.employees.first;
      await show(tester, d, PersonScreen(diner: d, staff: s));
      await tapKey(tester, 'task-70-serve');
      expect(s.does(Task.serve), isTrue, reason: 'it would do nothing');
      expect(find.text('Keep at least one thing on'), findsOneWidget);
    });

    testWidgets('clearing tables is a switch that goes with the others', (
      tester,
    ) async {
      final d = cafe([person(70, 'Sam')]);
      final s = d.roster.employees.first;
      await show(tester, d, PersonScreen(diner: d, staff: s));
      await tapKey(tester, 'task-70-clear');
      expect(s.tasks, {Task.serve, Task.clear});
      expect(s.cooksAt, isNull);
      expect(help(tester, s), contains('clears the tables'));
    });

    testWidgets('the staff page says when a machine has nobody', (
      tester,
    ) async {
      final d = cafe([
        person(70, 'Sam', cooksAt: {Kind.grill}),
      ]);
      await show(tester, d, StaffScreen(diner: d));
      expect(find.byKey(const ValueKey('uncovered')), findsOneWidget);
      expect(
        tester.widget<PxText>(find.byKey(const ValueKey('uncovered'))).text,
        contains('Nobody is set to the fryer'),
      );
    });

    testWidgets('and says nothing when all are covered', (tester) async {
      final d = cafe([person(70, 'Sam')]);
      await show(tester, d, StaffScreen(diner: d));
      expect(find.byKey(const ValueKey('uncovered')), findsNothing);
    });
  });
}
