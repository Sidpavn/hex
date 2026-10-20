// Now and then, someone walks in off the street asking for work.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/contracts.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/goals.dart';
import 'package:hex/diner/hiring_screen.dart';
import 'package:hex/diner/person_screen.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/diner/service.dart';
import 'package:hex/diner/staff.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';
import 'package:hex/ui/widgets.dart' show GoldButton;

const newDishes = [
  Dish.hotDog,
  Dish.onionRings,
  Dish.chickenSandwich,
  Dish.nuggets,
  Dish.milkshake,
  Dish.baconBurger,
  Dish.sundae,
];

/// A restaurant with room for one more person.
Diner cafe({int day = 3, int level = 5, int cooks = 2, int places = 3}) {
  final d = Diner(
    coins: 100000,
    owned: {0, 1},
    progress: Progress(level: level, reputation: 70, day: day),
  );
  d.declined.addAll([Dish.cheeseburger, ...newDishes]);
  d.progress.upgrades[Upgrade.staff] = places - 1;
  d.roster.employees.clear();
  for (var i = 0; i < cooks; i++) {
    d.roster.employees.add(
      Staff(
        id: 70 + i,
        name: 'S$i',
        stats: {Stat.cooking: 5, Stat.speed: 5, Stat.service: 5, Stat.charm: 5},
        potential: {for (final s in Stat.values) s: 10},
      ),
    );
  }
  d.place(Kind.grill, const Cell(1, 3), Dir.sw);
  d.place(Kind.grill, const Cell(2, 3), Dir.sw);
  d.place(Kind.counter, const Cell(10, 7), Dir.nw);
  d.place(Kind.counter, const Cell(10, 6), Dir.nw);
  for (final t in const [Cell(3, 5), Cell(6, 5)]) {
    d.place(Kind.table, t);
    d.place(Kind.chair, Cell(t.x - 1, t.y), Dir.se);
    d.place(Kind.chair, Cell(t.x + 1, t.y), Dir.nw);
  }
  d.menu();
  return d;
}

/// The first day from [from] on which someone walks in.
int walkInDay({int from = 3}) {
  for (var n = from; n < 600; n++) {
    if (DinerSim(cafe(day: n), seed: 1).walkInDue != null) return n;
  }
  throw StateError('never');
}

int quietDay({int from = 3}) {
  for (var n = from; n < 600; n++) {
    if (DinerSim(cafe(day: n), seed: 1).walkInDue == null) return n;
  }
  throw StateError('always');
}

DinerSim play(Diner d, {int seed = 1}) {
  final sim = DinerSim(d, seed: seed);
  while (!sim.finished && sim.ticks < 2500) {
    sim.tick();
  }
  return sim;
}

void main() {
  group('who walks in, and when', () {
    test('about one day in seven, and not on a pattern', () {
      final days = [
        for (var n = 3; n < 403; n++)
          if (DinerSim(cafe(day: n), seed: 1).walkInDue != null) n,
      ];
      expect(days.length / 400, closeTo(DinerSim.walkInChance, 0.06));
      final gaps = {
        for (var i = 1; i < days.length; i++) days[i] - days[i - 1],
      };
      expect(gaps.length, greaterThanOrEqualTo(5));
    });

    test('it is the same each time for a day', () {
      final n = walkInDay();
      expect(
        DinerSim(cafe(day: n), seed: 1).walkInDue,
        DinerSim(cafe(day: n), seed: 9).walkInDue,
      );
    });

    test('in the middle of the day, not at the doors opening or closing', () {
      for (var n = 3; n < 300; n++) {
        final t = DinerSim(cafe(day: n), seed: 1).walkInDue;
        if (t == null) continue;
        expect(t, inInclusiveRange(Pace.dayTicks * 0.14, Pace.dayTicks * 0.76));
      }
    });

    test('not at level 1', () {
      for (var n = 3; n < 200; n++) {
        expect(DinerSim(cafe(day: n, level: 1), seed: 1).walkInDue, isNull);
      }
    });

    test('only when there is a place for them', () {
      final n = walkInDay();
      expect(
        DinerSim(cafe(day: n, cooks: 3, places: 3), seed: 1).walkInDue,
        isNull,
      );
      expect(
        DinerSim(cafe(day: n, cooks: 2, places: 3), seed: 1).walkInDue,
        isNotNull,
      );
    });

    test('not while an earlier one is still waiting to be hired', () {
      final n = walkInDay();
      final d = cafe(day: n);
      d.roster.candidates = [d.roster.walkInApplicant(n, 5, 3.5)];
      expect(DinerSim(d, seed: 1).walkInDue, isNull);
    });

    test('not on a day the doors are shut', () {
      final n = walkInDay();
      final d = cafe(day: n);
      expect(DinerSim(d, seed: 1).walkInDue, isNotNull);
      d.takeContract(
        Contract(day: n, client: 'a', lines: {Dish.burger: 4}, reward: 100),
        {70},
        closed: true,
      );
      expect(DinerSim(d, seed: 1).walkInDue, isNull);
    });
  });

  group('the applicant', () {
    test('they are a real person, who has come asking for less', () {
      final p = cafe().roster.walkInApplicant(7, 5, 3.5);
      expect(p.walkIn, isTrue);
      expect(p.name, isNotEmpty);
      expect(p.fee, p.salary * 2);
      final ordinary = Staff(
        id: 1,
        name: 'X',
        stats: p.stats,
        potential: p.potential,
        traits: p.traits,
      );
      expect(p.fee, ordinary.fee ~/ 2);
    });

    test('not named like anyone already on the team', () {
      final d = cafe();
      for (var n = 3; n < 80; n++) {
        final p = d.roster.walkInApplicant(n, 5, 3.5);
        expect(d.roster.employees.map((s) => s.name), isNot(contains(p.name)));
      }
    });

    test('they are saved, with what they came for', () {
      final p = cafe().roster.walkInApplicant(7, 5, 3.5);
      final back = Staff.fromJson(p.toJson())!;
      expect(back.walkIn, isTrue);
      expect(back.fee, p.fee);
      expect(
        Staff.fromJson(cafe().roster.employees.first.toJson())!.walkIn,
        isFalse,
      );
    });
  });

  group('in the day', () {
    test('someone walks in, stands at the door a moment, and leaves', () {
      final n = walkInDay();
      final d = cafe(day: n);
      final sim = DinerSim(d, seed: 2);
      Guest? seen;
      final cells = <Cell>[];
      var gone = false;
      while (!sim.finished && sim.ticks < 2500) {
        sim.tick();
        final w = sim.walkIn;
        if (w == null) continue;
        final g = sim.guests.where((g) => g.name == w.name).firstOrNull;
        if (g != null) {
          seen ??= g;
          cells.add(g.cell);
        } else if (seen != null) {
          gone = true;
        }
      }
      expect(seen, isNotNull);
      expect(cells, contains(d.entrance));
      expect(gone, isTrue, reason: 'they left');
    });

    test('they are not a customer: no queue, no walkout, not counted', () {
      final n = walkInDay();
      final withIt = play(cafe(day: n), seed: 2);
      final base = play(cafe(day: n, cooks: 3, places: 3), seed: 2);
      expect(withIt.walkIn, isNotNull);
      expect(base.walkIn, isNull);
      // The same guests came, and were treated the same way.
      expect(withIt.result!.crowd!.total, base.result!.crowd!.total);
      expect(withIt.walkouts, base.walkouts);
    });

    test('the day says so', () {
      final n = walkInDay();
      final sim = play(cafe(day: n), seed: 2);
      expect(
        sim.story.any(
          (l) =>
              l.text.contains('walked in asking for work') &&
              l.text.contains(sim.walkIn!.name),
        ),
        isTrue,
      );
    });

    test('nobody walks in on an ordinary day', () {
      final sim = play(cafe(day: quietDay()), seed: 2);
      expect(sim.walkIn, isNull);
      expect(sim.story.any((l) => l.text.contains('asking for work')), isFalse);
    });
  });

  group('afterwards', () {
    test('they are among the applicants the next day, at half the fee', () {
      final n = walkInDay();
      final d = cafe(day: n);
      final sim = play(d, seed: 2);
      final who = sim.walkIn!;
      expect(d.progress.day, n + 1);
      final waiting = d.roster.candidates.where((s) => s.walkIn).toList();
      expect(waiting.length, 1);
      expect(waiting.single.name, who.name);
      expect(waiting.single.fee, waiting.single.salary * 2);
      d.lookForStaff();
      expect(d.roster.candidates.where((s) => s.walkIn), isNotEmpty);
    });

    test('and gone the day after, like anyone else who answered', () {
      final n = walkInDay();
      final d = cafe(day: n);
      play(d, seed: 2);
      d.progress.day = n + 2;
      d.lookForStaff();
      expect(d.roster.candidates.where((s) => s.walkIn), isEmpty);
    });

    test('an advert does not send them away', () {
      final n = walkInDay();
      final d = cafe(day: n);
      play(d, seed: 2);
      final name = d.roster.candidates.firstWhere((s) => s.walkIn).name;
      d.advertise(Ad.values.first);
      expect(d.roster.candidates.map((s) => s.name), contains(name));
      expect(d.roster.candidates.where((s) => !s.walkIn), isNotEmpty);
    });

    test('they can be hired for the half fee', () {
      final n = walkInDay();
      final d = cafe(day: n);
      play(d, seed: 2);
      final c = d.roster.candidates.firstWhere((s) => s.walkIn);
      final before = d.coins;
      expect(d.hire(c), StaffResult.ok);
      expect(before - d.coins, c.salary * 2);
      expect(d.roster.employees.map((s) => s.name), contains(c.name));
    });

    test('they are saved overnight', () {
      final n = walkInDay();
      final d = cafe(day: n);
      play(d, seed: 2);
      final back = Diner.fromJson(d.toJson());
      expect(back.roster.candidates.where((s) => s.walkIn).length, 1);
    });
  });

  group('on screen', () {
    Future<Diner> open(WidgetTester tester, Diner d, Widget page) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
      });
      Storage.clearMemory();
      d.goalsDone.addAll([for (final g in goals) g.id]);
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(HexApp(home: page));
      await tester.pump(const Duration(milliseconds: 500));
      return d;
    }

    testWidgets('they are in the hiring list, marked', (tester) async {
      final n = walkInDay();
      final d = cafe(day: n);
      play(d, seed: 2);
      final c = d.roster.candidates.firstWhere((s) => s.walkIn);
      await open(tester, d, HiringScreen(diner: d));
      expect(find.byKey(ValueKey('cand-${c.id}')), findsOneWidget);
      expect(find.text('walked in, fee ${c.fee}'), findsOneWidget);
    });

    testWidgets('their page says why the fee is lower', (tester) async {
      final n = walkInDay();
      final d = cafe(day: n);
      play(d, seed: 2);
      final c = d.roster.candidates.firstWhere((s) => s.walkIn);
      await open(tester, d, PersonScreen(diner: d, staff: c, applicant: true));
      expect(find.byKey(ValueKey('walk-in-${c.id}')), findsOneWidget);
      expect(
        tester.widget<GoldButton>(find.byKey(ValueKey('hire-${c.id}'))).label,
        'Hire  :coin: ${c.fee}',
      );
    });

    testWidgets('an ordinary applicant has no such note', (tester) async {
      final d = cafe();
      d.advertise(Ad.values.first);
      final c = d.roster.candidates.first;
      await open(tester, d, PersonScreen(diner: d, staff: c, applicant: true));
      expect(find.byKey(ValueKey('walk-in-${c.id}')), findsNothing);
    });
  });
}
