// Days that are not all alike: a lunch rush, rain, a festival, a quiet day, a
// shortage, and a food critic who is only impressed by the best.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/events.dart';
import 'package:hex/diner/guests.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/diner/service.dart';
import 'package:hex/diner/staff.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';

/// The first day from [from] with [event] at [level].
int dayWith(DayEvent event, {int level = 5, int from = 2}) {
  for (var d = from; d < 400; d++) {
    if (DayEvent.forDay(d, level) == event) return d;
  }
  throw StateError('no $event day');
}

int plainDay({int level = 5}) => dayWith(DayEvent.none, level: level);

Diner cafe({
  required int day,
  int level = 5,
  int rep = 60,
  int cooks = 3,
  bool premium = false,
}) {
  final d = Diner(
    coins: 100000,
    owned: {0, 1},
    progress: Progress(level: level, reputation: rep, day: day),
  );
  d.declined.add(Dish.cheeseburger);
  d.roster.employees.clear();
  d.progress.upgrades[Upgrade.staff] = cooks - 1;
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
  d.place(Kind.fryer, const Cell(3, 3), Dir.sw);
  d.place(Kind.counter, const Cell(10, 7), Dir.nw);
  d.place(Kind.counter, const Cell(10, 6), Dir.nw);
  for (final t in const [Cell(3, 5), Cell(6, 5), Cell(7, 7), Cell(9, 5)]) {
    d.place(Kind.table, t);
    d.place(Kind.chair, Cell(t.x - 1, t.y), Dir.se);
    d.place(Kind.chair, Cell(t.x + 1, t.y), Dir.nw);
  }
  if (premium) {
    d.progress.recipeLevel[Dish.burger] = Diner.premiumLevel;
    d.tiers[Dish.burger] = Tier.premium;
    // Cheap enough that the critic, who has money, and everyone else, buys.
    d.markup[Dish.burger] = -10;
  }
  return d;
}

DinerSim play(Diner d, {int seed = 1}) {
  final sim = DinerSim(d, seed: seed);
  while (!sim.finished && sim.ticks < 2500) {
    sim.tick();
  }
  return sim;
}

void main() {
  group('which day is which', () {
    test('the first day is always an ordinary one', () {
      for (var level = 1; level <= 9; level++) {
        expect(DayEvent.forDay(1, level), DayEvent.none);
      }
    });

    test('it is fixed by the day and the level, so the notice is right', () {
      for (var day = 2; day < 60; day++) {
        expect(DayEvent.forDay(day, 5), DayEvent.forDay(day, 5));
      }
    });

    test('about four days in ten are special, and the rest plain', () {
      var special = 0;
      const days = 600;
      for (var day = 2; day < days; day++) {
        if (DayEvent.forDay(day, 6) != DayEvent.none) special++;
      }
      expect(special / days, inInclusiveRange(0.35, 0.55));
    });

    test('every kind comes round', () {
      final seen = {
        for (var day = 2; day < 600; day++) DayEvent.forDay(day, 6),
      };
      expect(seen, containsAll(DayEvent.values));
    });

    test('they do not come at regular gaps', () {
      final days = [
        for (var d = 2; d < 400; d++)
          if (DayEvent.forDay(d, 6) != DayEvent.none) d,
      ];
      final gaps = {
        for (var i = 1; i < days.length; i++) days[i] - days[i - 1],
      };
      // Next day, and a handful of different waits: nothing like every third
      // or fourth day.
      expect(gaps, contains(1));
      expect(gaps.length, greaterThanOrEqualTo(5));
      expect(gaps.reduce((a, b) => a > b ? a : b), greaterThanOrEqualTo(5));
      final counts = <int, int>{};
      for (var i = 1; i < days.length; i++) {
        final g = days[i] - days[i - 1];
        counts[g] = (counts[g] ?? 0) + 1;
      }
      // No one gap makes up most of them.
      final common = counts.values.reduce((a, b) => a > b ? a : b);
      expect(common / (days.length - 1), lessThan(0.45));
    });

    test('a run of special days, and a run of plain ones, both happen', () {
      var special = 0;
      var plain = 0;
      var bestSpecial = 0;
      var bestPlain = 0;
      for (var d = 2; d < 500; d++) {
        if (DayEvent.forDay(d, 6) == DayEvent.none) {
          plain++;
          special = 0;
          bestPlain = plain > bestPlain ? plain : bestPlain;
        } else {
          special++;
          plain = 0;
          bestSpecial = special > bestSpecial ? special : bestSpecial;
        }
      }
      expect(bestSpecial, greaterThanOrEqualTo(3));
      expect(bestPlain, greaterThanOrEqualTo(5));
    });

    test('the same kind does not fall on every Nth day', () {
      for (final kind in [DayEvent.rain, DayEvent.lunchRush, DayEvent.quiet]) {
        final days = [
          for (var d = 2; d < 600; d++)
            if (DayEvent.forDay(d, 6) == kind) d,
        ];
        final gaps = {
          for (var i = 1; i < days.length; i++) days[i] - days[i - 1],
        };
        expect(gaps.length, greaterThan(6), reason: kind.name);
      }
    });

    test('two reviewers never come on back-to-back days', () {
      for (var d = 3; d < 800; d++) {
        final a = DayEvent.forDay(d - 1, 9);
        final b = DayEvent.forDay(d, 9);
        expect(a.reviewed && b.reviewed, isFalse, reason: 'day $d');
      }
    });

    test('there is no critic until the restaurant is worth reviewing', () {
      for (var day = 2; day < 600; day++) {
        for (var level = 1; level < DayEvent.criticLevel; level++) {
          expect(DayEvent.forDay(day, level), isNot(DayEvent.critic));
        }
      }
      expect(DayEvent.criticLevel, 4);
    });

    test('each says what it is in plain words', () {
      for (final e in DayEvent.values.where((e) => e != DayEvent.none)) {
        expect(e.label, isNotEmpty);
        expect(e.blurb, endsWith('.'));
      }
      expect(DayEvent.critic.blurb, contains('premium'));
    });

    test('what each does to the numbers', () {
      expect(DayEvent.festival.guestMul, greaterThan(1));
      expect(DayEvent.quiet.guestMul, lessThan(1));
      expect(DayEvent.rain.guestMul, lessThan(1));
      expect(DayEvent.rain.carMul, greaterThan(1));
      expect(DayEvent.shortage.costMul, greaterThan(1));
      expect(DayEvent.lunchRush.peakShare, greaterThan(0));
      expect(DayEvent.festival.thriftyShift, greaterThan(0));
      expect(DayEvent.none.guestMul, 1);
      expect(DayEvent.none.costMul, 1);
    });
  });

  group('what the day does to the plan', () {
    test('a shortage makes ingredients dearer, and the plan costs more', () {
      final plain = cafe(day: plainDay());
      final short = cafe(day: dayWith(DayEvent.shortage));
      expect(
        short.unitCost(Dish.burger),
        closeTo(plain.unitCost(Dish.burger) * 1.35, 1e-9),
      );
      expect(short.prepCost(), greaterThan(plain.prepCost()));
    });

    test('guests expected follows the day, and so does the forecast', () {
      final plain = cafe(day: plainDay());
      final quiet = cafe(day: dayWith(DayEvent.quiet));
      final fest = cafe(day: dayWith(DayEvent.festival));
      expect(quiet.expectedToday, lessThan(plain.expectedToday));
      expect(fest.expectedToday, greaterThan(plain.expectedToday));
      expect(
        quiet.portions(Dish.burger),
        lessThan(plain.portions(Dish.burger)),
      );
      expect(
        fest.portions(Dish.burger),
        greaterThan(plain.portions(Dish.burger)),
      );
    });
  });

  group('in the day', () {
    int pedestrians(DinerSim s) => s.arrivalSchedule.length;

    test('a quiet day brings fewer, a festival more', () {
      final plain = DinerSim(cafe(day: plainDay()), seed: 2);
      final quiet = DinerSim(cafe(day: dayWith(DayEvent.quiet)), seed: 2);
      final fest = DinerSim(cafe(day: dayWith(DayEvent.festival)), seed: 2);
      expect(pedestrians(quiet), lessThan(pedestrians(plain)));
      expect(pedestrians(fest), greaterThan(pedestrians(plain)));
    });

    test('a lunch rush bunches extra guests round midday', () {
      int inWindow(DinerSim s) => s.arrivalSchedule
          .where((t) => t >= Pace.dayTicks * 0.38 && t <= Pace.dayTicks * 0.52)
          .length;

      final plain = DinerSim(cafe(day: plainDay()), seed: 2);
      final rush = DinerSim(cafe(day: dayWith(DayEvent.lunchRush)), seed: 2);
      expect(inWindow(rush), greaterThan(inWindow(plain) + 4));
      expect(pedestrians(rush), greaterThan(pedestrians(plain)));
    });

    test('the usual arrivals are the same with or without the rush', () {
      final plain = DinerSim(cafe(day: plainDay()), seed: 2);
      final rush = DinerSim(cafe(day: dayWith(DayEvent.lunchRush)), seed: 2);
      // The rush only adds: everything else is drawn the same way.
      expect(
        rush.arrivalSchedule.length - plain.arrivalSchedule.length,
        greaterThan(0),
      );
    });

    test('rain sends fewer on foot, and more by car', () {
      Diner withWindow(int day) {
        final d = cafe(day: day);
        d.place(Kind.window, Cell(d.right, 3));
        return d;
      }

      final plain = DinerSim(withWindow(plainDay()), seed: 2);
      final rain = DinerSim(withWindow(dayWith(DayEvent.rain)), seed: 2);
      expect(pedestrians(rain), lessThan(pedestrians(plain)));
      expect(rain.carSchedule.length, greaterThan(plain.carSchedule.length));
    });

    test('a festival crowd is more thrifty', () {
      double thrifty(int day) {
        var t = 0;
        var n = 0;
        for (final seed in [1, 2, 3, 4, 5, 6]) {
          final sim = DinerSim(cafe(day: day, rep: 80), seed: seed);
          final seen = <int>{};
          while (!sim.finished && sim.ticks < 2500) {
            sim.tick();
            for (final g in sim.guests) {
              if (!seen.add(g.id)) continue;
              n++;
              if (g.wallet == Wallet.thrifty) t++;
            }
          }
        }
        return t / n;
      }

      expect(
        thrifty(dayWith(DayEvent.festival)),
        greaterThan(thrifty(plainDay()) + 0.05),
      );
    });

    test('a shortage eats into the day\'s profit', () {
      final plain = play(cafe(day: plainDay()), seed: 2);
      final short = play(cafe(day: dayWith(DayEvent.shortage)), seed: 2);
      expect(
        short.ingredientCost / short.itemsServed.clamp(1, 999),
        greaterThan(plain.ingredientCost / plain.itemsServed.clamp(1, 999)),
      );
    });

    test('the report remembers the day, and the story tells it once', () {
      final r = play(cafe(day: dayWith(DayEvent.quiet)), seed: 2).result!;
      expect(r.event, DayEvent.quiet);
      expect(play(cafe(day: plainDay()), seed: 2).result!.event, DayEvent.none);
      for (final e in [DayEvent.rain, DayEvent.lunchRush, DayEvent.quiet]) {
        final sim = DinerSim(cafe(day: dayWith(e)), seed: 2)
          ..tick()
          ..tick();
        expect(
          sim.story.where((l) => l.text == 'Today: ${e.label}. ${e.blurb}'),
          hasLength(1),
          reason: e.label,
        );
      }
      final plain = DinerSim(cafe(day: plainDay()), seed: 2)..tick();
      expect(plain.story.any((l) => l.text.startsWith('Today')), isFalse);
    });
  });

  group('the food critic', () {
    DinerSim critic(int seed, {bool premium = true, int cooks = 3}) {
      final d = cafe(
        day: dayWith(DayEvent.critic),
        premium: premium,
        cooks: cooks,
      );
      return DinerSim(d, seed: seed);
    }

    Guest? find(DinerSim sim) => sim.guests.where((g) => g.critic).firstOrNull;

    test('they arrive once, in the middle of the day, and are somebody', () {
      final sim = critic(2);
      Guest? seen;
      var arrivedAt = 0;
      while (!sim.finished && sim.ticks < 2500) {
        sim.tick();
        final g = find(sim);
        if (g != null && seen == null) {
          seen = g;
          arrivedAt = sim.ticks;
        }
      }
      expect(seen, isNotNull);
      expect(
        arrivedAt,
        inInclusiveRange(Pace.dayTicks * 0.4, Pace.dayTicks * 0.62),
      );
      expect(seen!.name, 'The critic');
      expect(seen.wallet, Wallet.wealthy);
      expect(seen.temper, Temper.steady);
      expect(seen.sprite, 'cust_d');
    });

    test('only on a critic day', () {
      final sim = DinerSim(cafe(day: plainDay(), premium: true), seed: 2);
      while (!sim.finished && sim.ticks < 2500) {
        sim.tick();
        expect(find(sim), isNull);
      }
    });

    test('they will only order a main made with the best', () {
      final d = cafe(day: dayWith(DayEvent.critic), premium: true);
      // A second, ordinary main on the menu: not for them.
      d.progress.level = 6;
      d.declined.remove(Dish.cheeseburger);
      d.place(Kind.fryer, const Cell(4, 3), Dir.sw);
      d.offered
        ..clear()
        ..addAll([Dish.burger, Dish.cheeseburger, Dish.fries]);
      final sim = DinerSim(d, seed: 3);
      while (!sim.finished && sim.ticks < 2500) {
        sim.tick();
        final g = find(sim);
        if (g != null && g.items.isNotEmpty) {
          final mains = g.items.where(
            (i) => recipes[i.dish]!.course == Course.main,
          );
          expect(mains.every((i) => i.tier == Tier.premium), isTrue);
        }
      }
    });

    test('served a premium dish promptly, they rave and the rating rises', () {
      var raved = 0;
      for (final seed in [1, 2, 3, 4]) {
        final sim = critic(seed);
        final before = sim.progress.reputation;
        while (!sim.finished && sim.ticks < 2500) {
          sim.tick();
        }
        if (sim.reviewDelta == 8) {
          raved++;
          expect(sim.result!.reviewDelta, 8);
          expect(sim.story.any((l) => l.text.contains('raved')), isTrue);
          // A day on top of the critic's word: at least their eight points,
          // less whatever the ordinary day took off.
          expect(sim.progress.reputation, greaterThanOrEqualTo(before - 6));
        }
      }
      expect(raved, greaterThan(0));
    });

    test('the critic\'s verdict is on top of how the day went', () {
      final sim = critic(1);
      final before = sim.progress.reputation;
      while (!sim.finished && sim.ticks < 2500) {
        sim.tick();
      }
      final withoutCritic = DinerSim(
        cafe(day: dayWith(DayEvent.critic), premium: true),
        seed: 1,
      );
      expect(sim.result!.reputationBefore, before);
      expect(sim.result!.reviewDelta, sim.reviewDelta);
      expect(withoutCritic.reviewDelta, 0);
    });

    test('with no premium main on the menu, they leave, and it costs', () {
      var left = 0;
      for (final seed in [1, 2, 3]) {
        final sim = critic(seed, premium: false);
        final before = sim.progress.reputation;
        while (!sim.finished && sim.ticks < 2500) {
          sim.tick();
        }
        expect(sim.reviewDelta, lessThan(0), reason: 'seed $seed');
        expect(sim.reviewDelta, anyOf(-4, -6));
        left++;
        expect(sim.story.any((l) => l.text.contains('critic')), isTrue);
        expect(sim.result!.reviewDelta, sim.reviewDelta);
        expect(before, isNonNegative);
      }
      expect(left, 3);
    });

    test('the report says what the critic did', () {
      final r = play(
        cafe(day: dayWith(DayEvent.critic), premium: true),
        seed: 1,
      ).result!;
      expect(r.event, DayEvent.critic);
    });
  });

  group('on screen', () {
    Future<void> open(WidgetTester tester, Diner d) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
      });
      Storage.clearMemory();
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(HexApp(home: BuildScreen(diner: d)));
      await tester.pump();
    }

    testWidgets('the morning says what is special about the day', (
      tester,
    ) async {
      final e = DayEvent.quiet;
      await open(tester, cafe(day: dayWith(e)));
      expect(find.text('Today: ${e.label}. ${e.blurb}'), findsOneWidget);
    });

    testWidgets('an ordinary day says nothing', (tester) async {
      await open(tester, cafe(day: plainDay()));
      expect(find.textContaining('Today:'), findsNothing);
    });

    testWidgets('the critic is announced with what to do about it', (
      tester,
    ) async {
      await open(tester, cafe(day: dayWith(DayEvent.critic)));
      expect(find.textContaining('premium'), findsWidgets);
      expect(find.textContaining('Food critic'), findsOneWidget);
    });

    testWidgets('an event day starts at once, with a note in the corner', (
      tester,
    ) async {
      final e = DayEvent.rain;
      await open(tester, cafe(day: dayWith(e)));
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump(const Duration(milliseconds: 300));
      // No alert in the middle of the screen: the day is already running.
      expect(find.byKey(const ValueKey('event-ok')), findsNothing);
      expect(find.byKey(const ValueKey('pause')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      final note = find.textContaining('Today: ${e.label}');
      expect(note, findsOneWidget);
      // Small, and at the top left.
      final box = tester.getRect(note);
      expect(box.left, lessThan(tester.view.physicalSize.width / 6));
      expect(box.top, lessThan(tester.view.physicalSize.height / 3 / 4));
    });

    testWidgets('an ordinary day starts straight away', (tester) async {
      await open(tester, cafe(day: plainDay()));
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('event-ok')), findsNothing);
      expect(find.byKey(const ValueKey('pause')), findsOneWidget);
    });

    testWidgets('the portions page knows how many to expect', (tester) async {
      final d = cafe(day: dayWith(DayEvent.festival));
      await open(tester, d);
      await tester.tap(find.byKey(const ValueKey('menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-prep')));
      await tester.pumpAndSettle();
      expect(find.textContaining('street festival'), findsOneWidget);
      expect(find.textContaining('${d.expectedToday}'), findsWidgets);
    });
  });
}
