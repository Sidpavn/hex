// Who comes: gender, how much they spend, and what sells best.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/crowd.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/goals.dart';
import 'package:hex/diner/guests.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/diner/service.dart';
import 'package:hex/diner/staff.dart';
import 'package:hex/diner/stats_screen.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';
import 'package:hex/ui/pixel/pixel_ui.dart' show PxText;
import 'package:hex/ui/pixel_pie.dart';
import 'support/office.dart';

Diner cafe({int day = 1, int rep = 70, int cooks = 3}) {
  final d = Diner(
    coins: 100000,
    owned: {0, 1},
    progress: Progress(level: 5, reputation: rep, day: day),
  );
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
  d.menu();
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
  group('gender', () {
    test('three, and most are women or men', () {
      expect(Gender.values.length, 3);
      expect(Gender.values.fold(0.0, (a, g) => a + g.share), closeTo(1, 1e-9));
      expect(Gender.nonbinary.share, lessThan(Gender.man.share));
    });

    test('a roll lands on each in proportion', () {
      final n = {for (final g in Gender.values) g: 0};
      for (var i = 0; i < 10000; i++) {
        final g = Gender.roll(i / 10000);
        n[g] = n[g]! + 1;
      }
      expect(n[Gender.woman]! / 10000, closeTo(0.47, 0.01));
      expect(n[Gender.man]! / 10000, closeTo(0.47, 0.01));
      expect(n[Gender.nonbinary]! / 10000, closeTo(0.06, 0.01));
    });

    test('each has names and figures of its own, enough to go round', () {
      for (final g in Gender.values) {
        expect(g.names.length, greaterThanOrEqualTo(8), reason: g.name);
        expect(g.names.toSet().length, g.names.length);
        expect(g.looks, isNotEmpty);
      }
      final all = [for (final g in Gender.values) ...g.names];
      expect(all.toSet().length, all.length, reason: 'no name in two lists');
    });

    test('a guest is drawn and named to match', () {
      for (final seed in [1, 2, 3]) {
        final sim = DinerSim(cafe(day: 3 + seed), seed: seed);
        final seen = <int>{};
        while (!sim.finished && sim.ticks < 2500) {
          sim.tick();
          for (final g in sim.guests) {
            if (g.car || !seen.add(g.id) || g.reviewer) continue;
            expect(g.gender.looks, contains(g.sprite));
            expect(
              g.gender.names.contains(g.name) || g.name == 'A guest',
              isTrue,
              reason: '${g.name} is not a ${g.gender.name} name',
            );
          }
        }
      }
    });

    test('who turns up does not change what they will spend or wait', () {
      // Gender has a stream of its own: wallets and tempers are as before.
      final a = DinerSim(cafe(day: 4), seed: 1);
      final b = DinerSim(cafe(day: 4), seed: 1);
      final wa = <Wallet>[];
      final wb = <Wallet>[];
      for (final (sim, out) in [(a, wa), (b, wb)]) {
        final seen = <int>{};
        while (!sim.finished && sim.ticks < 2500) {
          sim.tick();
          for (final g in sim.guests) {
            if (seen.add(g.id)) out.add(g.wallet);
          }
        }
      }
      expect(wa, wb);
      expect(wa, isNotEmpty);
    });

    test('over a day all three turn up', () {
      final seen = <Gender>{};
      for (final seed in [1, 2, 3, 4]) {
        for (final day in [2, 3, 4]) {
          final sim = DinerSim(cafe(day: day), seed: seed);
          while (!sim.finished && sim.ticks < 2500) {
            sim.tick();
            for (final g in sim.guests) {
              seen.add(g.gender);
            }
          }
        }
      }
      expect(seen, containsAll(Gender.values));
    });
  });

  group('the books', () {
    test('a fed guest is counted, with what they spent', () {
      final c = Crowd();
      c.fed(Gender.woman, Wallet.regular, 14, {
        Dish.burger: (1, 10),
        Dish.fries: (1, 4),
      });
      expect(c.ofGender(Gender.woman).served, 1);
      expect(c.ofGender(Gender.woman).spent, 14);
      expect(c.ofWallet(Wallet.regular).average, 14);
      expect(c.ofDish(Dish.burger).served, 1);
      expect(c.ofDish(Dish.burger).spent, 10);
      expect(c.ofGender(Gender.man).total, 0);
      expect(c.served, 1);
    });

    test('a guest who left is counted as missed, not fed', () {
      final c = Crowd();
      c.missed(Gender.nonbinary, Wallet.thrifty);
      expect(c.ofGender(Gender.nonbinary).lost, 1);
      expect(c.ofWallet(Wallet.thrifty).lost, 1);
      expect(c.ofWallet(Wallet.thrifty).average, 0);
      expect(c.lost, 1);
      expect(c.served, 0);
      expect(c.isEmpty, isFalse);
      expect(Crowd().isEmpty, isTrue);
    });

    test('best sellers are by portions, then by takings', () {
      final c = Crowd();
      c.fed(Gender.man, Wallet.regular, 1, {
        Dish.burger: (3, 30),
        Dish.fries: (3, 12),
        Dish.coffee: (1, 5),
      });
      expect(c.bestSellers(), [Dish.burger, Dish.fries, Dish.coffee]);
    });

    test('days add up', () {
      final a = Crowd()
        ..fed(Gender.man, Wallet.thrifty, 5, {Dish.burger: (1, 5)});
      final b = Crowd()
        ..fed(Gender.man, Wallet.thrifty, 7, {Dish.burger: (1, 7)})
        ..missed(Gender.woman, Wallet.wealthy);
      a.add(b);
      expect(a.ofGender(Gender.man).served, 2);
      expect(a.ofGender(Gender.man).spent, 12);
      expect(a.ofDish(Dish.burger).served, 2);
      expect(a.lost, 1);
      expect(
        b.ofGender(Gender.man).served,
        1,
        reason: 'the other is untouched',
      );
    });

    test('they survive being saved', () {
      final c = Crowd()
        ..fed(Gender.woman, Wallet.wealthy, 20, {Dish.pizza: (1, 18)})
        ..missed(Gender.man, Wallet.thrifty);
      final back = Crowd.fromJson(c.toJson());
      expect(back.ofGender(Gender.woman).spent, 20);
      expect(back.ofWallet(Wallet.wealthy).served, 1);
      expect(back.ofDish(Dish.pizza).spent, 18);
      expect(back.lost, 1);
      expect(Crowd.fromJson('rubbish').isEmpty, isTrue);
      expect(
        Crowd.fromJson({
          'g': {'nonsense': {}},
        }).isEmpty,
        isTrue,
      );
    });

    test('a real day fills them in, and every guest is counted once', () {
      final d = cafe(day: 3);
      final sim = play(d, seed: 2);
      final r = sim.result!;
      expect(r.crowd, isNotNull);
      expect(r.crowd!.served, r.served);
      expect(r.crowd!.lost, r.walkouts);
      expect(r.crowd!.total, r.served + r.walkouts);
      final bySpend = r.crowd!.wallet.values.fold(0, (a, t) => a + t.spent);
      final byGender = r.crowd!.gender.values.fold(0, (a, t) => a + t.spent);
      expect(bySpend, byGender);
      expect(byGender, lessThanOrEqualTo(r.earned));
      final portions = r.crowd!.dishes.values.fold(0, (a, t) => a + t.served);
      expect(portions, r.items);
    });

    test('the restaurant keeps the lot, and the last day apart', () {
      final d = cafe(day: 3);
      final first = play(d, seed: 2).result!;
      expect(d.crowd.served, first.served);
      expect(d.lastCrowd!.served, first.served);
      d.progress.day = 4;
      final second = play(d, seed: 3).result!;
      expect(d.crowd.served, first.served + second.served);
      expect(d.lastCrowd!.served, second.served);
      final back = Diner.fromJson(d.toJson());
      expect(back.crowd.served, d.crowd.served);
      expect(back.lastCrowd!.served, second.served);
      expect(Diner.fromJson(cafe().toJson()).lastCrowd, isNull);
    });

    test('finishing a day twice does not count it twice', () {
      final d = cafe(day: 3);
      final sim = play(d, seed: 2);
      final served = d.crowd.served;
      sim.finishDay();
      expect(d.crowd.served, served);
    });
  });

  group('the note', () {
    Crowd of(Map<Wallet, (int, int)> m) {
      final c = Crowd();
      for (final e in m.entries) {
        for (var i = 0; i < e.value.$1; i++) {
          c.fed(Gender.man, e.key, 10, {});
        }
        for (var i = 0; i < e.value.$2; i++) {
          c.missed(Gender.man, e.key);
        }
      }
      return c;
    }

    test('nothing to say about a handful of guests', () {
      expect(crowdNote(of({Wallet.regular: (5, 0)})), isNull);
    });

    test('it says who most of them are', () {
      expect(
        crowdNote(of({Wallet.regular: (14, 0), Wallet.thrifty: (6, 0)})),
        'Most of your guests are regular spenders (70%).',
      );
    });

    test('and who leaves hungry, when it is a real difference', () {
      final n = crowdNote(
        of({Wallet.regular: (12, 0), Wallet.thrifty: (3, 5)}),
      )!;
      expect(n, contains('Thrifty guests leave without eating most often'));
      expect(n, contains('(63%)'));
    });
  });

  group('dishes', () {
    test('portions, takings, ingredients and what is thrown away are kept', () {
      final c = Crowd();
      c.fed(
        Gender.man,
        Wallet.regular,
        14,
        {Dish.burger: (2, 20)},
        costs: {Dish.burger: 6},
      );
      c.thrownAway(Dish.burger, 3);
      final t = c.ofDish(Dish.burger);
      expect((t.served, t.spent, t.cost, t.lost), (2, 20, 6, 3));
      expect(t.profit, 14);
      final back = Crowd.fromJson(c.toJson());
      expect(back.ofDish(Dish.burger).cost, 6);
      expect(back.ofDish(Dish.burger).lost, 3);
    });

    test('a real day costs what the dishes cost, and counts the waste', () {
      final d = cafe(day: 3);
      final sim = play(d, seed: 2);
      final c = sim.result!.crowd!;
      final cost = c.dishes.values.fold(0, (a, t) => a + t.cost);
      expect(cost, greaterThan(0));
      expect(cost, lessThanOrEqualTo(sim.result!.ingredients));
      final waste = c.dishes.values.fold(0, (a, t) => a + t.lost);
      expect(waste, greaterThanOrEqualTo(0));
    });

    test('the note says what sells and what earns', () {
      final c = Crowd()
        ..fed(
          Gender.man,
          Wallet.regular,
          1,
          {Dish.burger: (20, 200), Dish.fries: (8, 120)},
          costs: {Dish.burger: 160, Dish.fries: 24},
        );
      final note = dishNote(c, (_) => 0)!;
      expect(note, contains('Burger sells most'));
      expect(note, contains('Fries earns the most a portion'));
    });

    test('and when they are the same dish, says so', () {
      final c = Crowd()
        ..fed(
          Gender.man,
          Wallet.regular,
          1,
          {Dish.burger: (20, 300), Dish.fries: (8, 40)},
          costs: {Dish.burger: 100, Dish.fries: 24},
        );
      expect(dishNote(c, (_) => 0), contains('best seller and best earner'));
    });

    test('and what is being thrown away', () {
      final c = Crowd()
        ..fed(Gender.man, Wallet.regular, 1, {Dish.burger: (12, 100)})
        ..thrownAway(Dish.burger, 9);
      expect(dishNote(c, (_) => 0), contains('9 burger were thrown away'));
    });

    test('too few sales, nothing to say', () {
      final c = Crowd()
        ..fed(Gender.man, Wallet.regular, 1, {Dish.burger: (3, 9)});
      expect(dishNote(c, (_) => 0), isNull);
    });
  });

  group('when they come', () {
    test('arrivals are counted into eighths of the day', () {
      final c = Crowd();
      c.fed(Gender.man, Wallet.regular, 5, {}, hour: 0);
      c.fed(Gender.man, Wallet.regular, 5, {}, hour: 3);
      c.missed(Gender.man, Wallet.regular, hour: 3);
      c.missed(Gender.man, Wallet.regular, hour: 99);
      expect(c.hours, [1, 0, 0, 2, 0, 0, 0, 1]);
      final back = Crowd.fromJson(c.toJson());
      expect(back.hours, c.hours);
      final more = Crowd()..add(c);
      more.add(c);
      expect(more.hours[3], 4);
    });

    test('a real day puts everyone somewhere, midday busiest', () {
      final sim = play(cafe(day: 3), seed: 2);
      final c = sim.result!.crowd!;
      expect(c.hours.fold(0, (a, b) => a + b), c.total);
      final mid = c.hours.sublist(2, 6).fold(0, (a, b) => a + b);
      expect(mid, greaterThan(c.total ~/ 2));
    });

    test('it says when in words', () {
      Crowd at(int slot) => Crowd()..hours[slot] = 5;
      expect(busiestTime(at(1)), 'Busiest early in the day.');
      expect(busiestTime(at(3)), 'Busiest around midday.');
      expect(busiestTime(at(7)), 'Busiest late in the day.');
      expect(busiestTime(Crowd()), 'No arrivals counted yet.');
    });
  });

  group('the days', () {
    test('each finished day is logged, with what was kept', () {
      final d = cafe(day: 3);
      final r = play(d, seed: 2).result!;
      expect(d.history.length, 1);
      final h = d.history.single;
      expect(h.day, 3);
      expect(h.kept, r.earned - r.ingredients - r.wages);
      expect(h.served, r.served);
      expect(h.rating, r.reputation);
    });

    test('an event is noted by name, and a day is logged once', () {
      final d = cafe(day: 3);
      final sim = play(d, seed: 2);
      sim.finishDay();
      expect(d.history.length, 1);
    });

    test('only the last sixty are kept, and they are saved', () {
      final d = cafe();
      for (var i = 0; i < 70; i++) {
        d.history.add(
          DayLog(day: i + 1, kept: i, served: 1, walkouts: 0, rating: 50),
        );
      }
      d.history.removeRange(0, d.history.length - DayLog.keep);
      expect(d.history.length, 60);
      final back = Diner.fromJson(d.toJson());
      expect(back.history.length, 60);
      expect(back.history.first.day, 11);
      expect(back.history.last.kept, 69);
      expect(Diner.fromJson(cafe().toJson()).history, isEmpty);
    });

    test('the note gives best, worst and average, and event against plain', () {
      List<DayLog> log(List<(int, String)> days) => [
        for (final (i, d) in days.indexed)
          DayLog(
            day: i + 1,
            kept: d.$1,
            served: 5,
            walkouts: 0,
            rating: 50,
            event: d.$2,
          ),
      ];
      expect(daysNote(log([(10, ''), (20, '')])), isNull);
      final n = daysNote(
        log([(100, ''), (80, ''), (30, 'rain'), (10, 'quiet'), (60, '')]),
      )!;
      expect(n, contains('Best day +100, worst 10, average 56.'));
      expect(n, contains('Event days kept 20, plain days 80.'));
    });
  });

  group('the charts', () {
    test('a pie is a disc of flat pixels, split in proportion', () async {
      final painter = PiePainter(
        const [1, 1, 2],
        const [Color(0xFFFF0000), Color(0xFF00FF00), Color(0xFF0000FF)],
        24,
        1,
      );
      final edges = painter.edges;
      expect(edges, [0.25, 0.5, 1.0]);
      final n = [0, 0, 0];
      var outside = 0;
      for (var y = -25; y <= 24; y++) {
        for (var x = -25; x <= 24; x++) {
          final s = painter.sliceAt(x, y, edges);
          s < 0 ? outside++ : n[s]++;
        }
      }
      final inside = n.fold(0, (a, b) => a + b);
      expect(inside, closeTo(3.14159 * 24 * 24, 40));
      expect(n[0] / inside, closeTo(0.25, 0.02));
      expect(n[1] / inside, closeTo(0.25, 0.02));
      expect(n[2] / inside, closeTo(0.50, 0.02));
      expect(outside, greaterThan(0));
    });

    test('slices run clockwise from the top', () {
      final p = PiePainter(
        const [1, 1],
        const [Colors.red, Colors.blue],
        10,
        1,
      );
      final e = p.edges;
      expect(p.sliceAt(5, 0, e), 0, reason: 'right is the first half');
      expect(p.sliceAt(-6, 0, e), 1, reason: 'left is the second');
    });

    test('an empty pie is one flat disc, and nothing divides by zero', () {
      final p = PiePainter(const [0, 0], const [Colors.red, Colors.blue], 8, 1);
      expect(p.edges, isEmpty);
    });

    test('columns are as tall as their share of the largest', () {
      final p = ColumnsPainter(
        const [10, 5, 0, 1],
        Colors.green,
        Colors.red,
        20,
        6,
        2,
        1,
      );
      expect(p.heights, [20, 10, 0, 2]);
      final neg = ColumnsPainter(
        const [10, -5],
        Colors.green,
        Colors.red,
        20,
        6,
        2,
        1,
      );
      expect(neg.heights, [20, -10]);
      expect(
        ColumnsPainter(
          const [0, 0],
          Colors.green,
          Colors.red,
          20,
          6,
          2,
          1,
        ).heights,
        [0, 0],
      );
    });

    testWidgets('a pie paints without smoothing or a gradient', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PixelPie(
              values: [3, 2, 1],
              colors: [Colors.red, Colors.green, Colors.blue],
            ),
          ),
        ),
      );
      expect(find.byType(PixelPie), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('on screen', () {
    Future<Diner> open(WidgetTester tester, Diner d) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
      });
      Storage.clearMemory();
      d.goalsDone.addAll([for (final g in goals) g.id]);
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(HexApp(home: BuildScreen(diner: d)));
      await tester.pump();
      return d;
    }

    testWidgets('a restaurant with no guests says so', (tester) async {
      await open(tester, cafe());
      await openApp(tester, 'stats');
      expect(find.byKey(const ValueKey('crowd-empty')), findsOneWidget);
      expect(find.text('Nobody yet'), findsOneWidget);
      expect(find.byKey(const ValueKey('by-gender')), findsNothing);
    });

    testWidgets('the guests tab has two pies and when they come', (
      tester,
    ) async {
      final d = cafe(day: 3);
      play(d, seed: 2);
      await open(tester, d);
      await openApp(tester, 'stats');
      for (final k in ['by-gender', 'by-wallet']) {
        expect(find.byKey(ValueKey(k)), findsOneWidget);
        expect(find.byKey(ValueKey('$k-pie')), findsOneWidget);
      }
      for (final g in Gender.values) {
        expect(find.text(g.label), findsOneWidget);
      }
      for (final w in Wallet.values) {
        expect(find.text(w.label), findsOneWidget);
      }
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('by-time')),
        200,
      );
      expect(find.byKey(const ValueKey('busiest')), findsOneWidget);
      expect(
        find.text(
          '${d.crowd.total} guests, ${d.crowd.served} fed, '
          '${d.crowd.lost} left without eating',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the dishes tab shows what sells and what each earns', (
      tester,
    ) async {
      final d = cafe(day: 3);
      play(d, seed: 2);
      await open(tester, d);
      await openApp(tester, 'stats');
      await tester.tap(find.byKey(const ValueKey('tab-dishes')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('by-dish-pie')), findsOneWidget);
      final best = d.crowd.bestSellers().first;
      expect(find.byKey(ValueKey('share-${best.name}')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('best-sellers')),
        200,
      );
      final t = d.crowd.ofDish(best);
      expect(
        tester
            .widget<PxText>(find.byKey(ValueKey('seller-${best.name}-profit')))
            .text,
        '${t.profit >= 0 ? '+' : ''}${t.profit}',
      );
      expect(t.cost, greaterThan(0), reason: 'ingredients are counted');
    });

    testWidgets('the days tab charts what was kept', (tester) async {
      final d = cafe(day: 3);
      play(d, seed: 2);
      d.progress.day = 4;
      play(d, seed: 3);
      await open(tester, d);
      await openApp(tester, 'stats');
      await tester.tap(find.byKey(const ValueKey('tab-days')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('by-day')), findsOneWidget);
      expect(find.byKey(const ValueKey('rating-trend')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('recent-days')),
        200,
      );
      expect(find.byKey(const ValueKey('day-4')), findsOneWidget);
      expect(find.byKey(const ValueKey('day-3')), findsOneWidget);
    });

    testWidgets('an empty restaurant says so on every tab', (tester) async {
      await open(tester, cafe());
      await openApp(tester, 'stats');
      await tester.tap(find.byKey(const ValueKey('tab-dishes')));
      await tester.pump();
      expect(find.byKey(const ValueKey('dishes-empty')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tab-days')));
      await tester.pump();
      expect(find.byKey(const ValueKey('days-empty')), findsOneWidget);
    });

    testWidgets('counts add up to the whole crowd', (tester) async {
      final d = cafe(day: 3);
      play(d, seed: 2);
      await open(tester, d);
      await openApp(tester, 'stats');
      var sum = 0;
      for (final g in Gender.values) {
        final t = tester.widget<PxText>(
          find.byKey(ValueKey('gender-${g.name}-detail')),
        );
        sum += int.parse(t.text.split(' ').first);
      }
      expect(sum, d.crowd.total);
    });

    testWidgets('last day and all days can be told apart', (tester) async {
      final d = cafe(day: 3);
      play(d, seed: 2);
      d.progress.day = 4;
      final second = play(d, seed: 3).result!;
      await open(tester, d);
      await openApp(tester, 'stats');
      expect(find.textContaining('${d.crowd.total} guests'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('crowd-last')));
      await tester.pump();
      expect(
        find.textContaining('${second.crowd!.total} guests'),
        findsOneWidget,
      );
    });
  });
}
