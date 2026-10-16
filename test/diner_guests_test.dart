// What guests are like: how much they will pay, how long they will wait, and
// the prices the player sets.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/guests.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/diner/service.dart';
import 'package:hex/diner/staff.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';
import 'support/office.dart';

Diner kitchen({int rep = 70, int staff = 3, Tier tier = Tier.standard}) {
  final d = Diner(
    coins: 100000,
    owned: {0, 1},
    progress: Progress(level: 4, reputation: rep),
  );
  d.declined.add(Dish.cheeseburger);
  d.roster.employees.clear();
  d.progress.upgrades[Upgrade.staff] = staff - 1;
  for (var i = 0; i < staff; i++) {
    d.roster.employees.add(
      Staff(
        id: 70 + i,
        name: 'S$i',
        stats: {Stat.cooking: 4, Stat.speed: 5, Stat.service: 4, Stat.charm: 4},
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
  d.tiers[Dish.burger] = tier;
  return d;
}

DinerSim play(Diner d, {int seed = 1}) {
  final sim = DinerSim(d, seed: seed);
  while (!sim.finished && sim.ticks < 2000) {
    sim.tick();
  }
  return sim;
}

void main() {
  group('wallets', () {
    test('thrifty guests pay the usual price, big spenders almost double', () {
      expect(Wallet.thrifty.accepts(1.0), isTrue);
      expect(Wallet.thrifty.accepts(1.05), isFalse);
      expect(Wallet.regular.accepts(1.3), isTrue);
      expect(Wallet.regular.accepts(1.31), isFalse);
      expect(Wallet.wealthy.accepts(1.8), isTrue);
      expect(Wallet.wealthy.accepts(2.0), isFalse);
      final tol = Wallet.values.map((w) => w.tolerance).toList();
      expect(tol, [...tol]..sort());
    });

    test('the richer the guest, the better the tip', () {
      final tips = Wallet.values.map((w) => w.tipMul).toList();
      expect(tips, [...tips]..sort());
      expect(Wallet.regular.tipMul, 1.0);
    });

    test('a better rating draws a richer crowd and fewer thrifty ones', () {
      Map<Wallet, double> share(double rating) {
        final rng = math.Random(4);
        final n = {for (final w in Wallet.values) w: 0};
        const total = 4000;
        for (var i = 0; i < total; i++) {
          final w = Wallet.roll(rating, rng.nextDouble());
          n[w] = n[w]! + 1;
        }
        return {for (final e in n.entries) e.key: e.value / total};
      }

      final low = share(0.5);
      final high = share(4.5);
      expect(high[Wallet.wealthy]!, greaterThan(low[Wallet.wealthy]! + 0.15));
      expect(high[Wallet.thrifty]!, lessThan(low[Wallet.thrifty]! - 0.15));
      for (final s in [low, high]) {
        expect(s.values.reduce((a, b) => a + b), closeTo(1, 1e-9));
        for (final w in Wallet.values) {
          expect(s[w]!, greaterThan(0.05), reason: 'every kind turns up');
        }
      }
    });

    test('a hasty guest waits less, an easygoing one more', () {
      expect(Temper.hasty.patienceMul, lessThan(1));
      expect(Temper.steady.patienceMul, 1);
      expect(Temper.easygoing.patienceMul, greaterThan(1));
      final rng = math.Random(9);
      final seen = {for (final t in Temper.values) t: 0};
      for (var i = 0; i < 2000; i++) {
        final t = Temper.roll(rng.nextDouble());
        seen[t] = seen[t]! + 1;
      }
      expect(seen[Temper.steady]!, greaterThan(seen[Temper.hasty]!));
      expect(seen[Temper.hasty]!, greaterThan(200));
      expect(seen[Temper.easygoing]!, greaterThan(200));
    });
  });

  group('the prices you set', () {
    test('a dish sells at the usual price until you change it', () {
      final d = Diner.starter();
      expect(d.markupOf(Dish.burger), 0);
      expect(d.priceRatio(Dish.burger), 1.0);
      expect(d.sellPrice(Dish.burger), 8);
    });

    test('each step is ten percent, within limits', () {
      final d = Diner.starter();
      d.nudgePrice(Dish.burger, 1);
      expect(d.markupOf(Dish.burger), 10);
      expect(d.sellPrice(Dish.burger), closeTo(8.8, 1e-9));
      for (var i = 0; i < 20; i++) {
        d.nudgePrice(Dish.burger, 1);
      }
      expect(d.markupOf(Dish.burger), Diner.markupMax);
      for (var i = 0; i < 20; i++) {
        d.nudgePrice(Dish.burger, -1);
      }
      expect(d.markupOf(Dish.burger), Diner.markupMin);
      expect(d.sellPrice(Dish.burger), closeTo(5.6, 1e-9));
    });

    test('back at the usual price, nothing is left to save', () {
      final d = Diner.starter();
      d.nudgePrice(Dish.burger, 2);
      d.nudgePrice(Dish.burger, -2);
      expect(d.markup, isEmpty);
    });

    test('ingredients and markup both count towards what guests see', () {
      final d = Diner.starter()..progress.recipeLevel[Dish.burger] = 3;
      d.tiers[Dish.burger] = Tier.premium;
      d.nudgePrice(Dish.burger, 1);
      expect(d.priceRatio(Dish.burger), closeTo(1.18 * 1.1, 1e-9));
    });

    test('the prices are saved, and a damaged one cannot go off the scale', () {
      final d = Diner.starter();
      d.nudgePrice(Dish.burger, 3);
      d.nudgePrice(Dish.fries, -2);
      final back = Diner.fromJson(d.toJson());
      expect(back.markupOf(Dish.burger), 30);
      expect(back.markupOf(Dish.fries), -20);
      final bad = Diner.fromJson({
        'coins': 1,
        'items': [],
        'markup': {'burger': 9000, 'fries': -9000, 'soda': 'x', 'nope': 5},
      });
      expect(bad.markupOf(Dish.burger), Diner.markupMax);
      expect(bad.markupOf(Dish.fries), Diner.markupMin);
      expect(bad.markupOf(Dish.soda), 0);
    });
  });

  group('in a day', () {
    test('every guest has a wallet and a temper, and the mix is varied', () {
      final sim = DinerSim(kitchen(rep: 90), seed: 3);
      final wallets = <Wallet>{};
      final tempers = <Temper>{};
      while (!sim.finished && sim.ticks < 2000) {
        sim.tick();
        for (final g in sim.guests) {
          wallets.add(g.wallet);
          tempers.add(g.temper);
        }
      }
      expect(wallets.length, greaterThanOrEqualTo(2));
      expect(tempers.length, greaterThanOrEqualTo(2));
    });

    test(
      'a hasty guest has less patience to start with than an easygoing one',
      () {
        final sim = DinerSim(kitchen(rep: 90), seed: 5);
        final byTemper = <Temper, int>{};
        while (!sim.finished && sim.ticks < 2000) {
          sim.tick();
          for (final g in sim.guests.where(
            (g) => g.state == GuestState.queued,
          )) {
            byTemper[g.temper] = g.patienceMax;
          }
        }
        final hasty = byTemper[Temper.hasty];
        final easy = byTemper[Temper.easygoing];
        if (hasty != null && easy != null) expect(hasty, lessThan(easy));
        final base = sim.progress.patience;
        if (hasty != null) expect(hasty, lessThan(base));
      },
    );

    test('who turns up, and when, does not depend on how they are made', () {
      final a = DinerSim(kitchen(), seed: 4);
      final b = DinerSim(kitchen(rep: 70), seed: 4);
      expect(a.arrivalSchedule, b.arrivalSchedule);
    });

    test('at the usual prices, nobody is put off', () {
      final sim = play(kitchen(), seed: 2);
      expect(sim.tooDear, 0);
    });

    test(
      'premium ingredients at the usual markup turn thrifty guests away',
      () {
        final d = kitchen(rep: 40, tier: Tier.premium)
          ..progress.recipeLevel[Dish.burger] = 3;
        final sim = play(d, seed: 2);
        expect(sim.tooDear, greaterThan(0));
        expect(sim.result!.tooDear, sim.tooDear);
        expect(
          sim.story.any(
            (l) =>
                l.text.contains('prices') ||
                l.text.contains('cheaper') ||
                l.text.contains('menu, winced'),
          ),
          isTrue,
        );
      },
    );

    test('a discount brings the thrifty back to premium', () {
      Diner premium(int markup) {
        final d = kitchen(rep: 40, tier: Tier.premium)
          ..progress.recipeLevel[Dish.burger] = 3;
        d.markup[Dish.burger] = markup;
        return d;
      }

      final dear = play(premium(0), seed: 2);
      final cheap = play(premium(-20), seed: 2);
      expect(dear.tooDear, greaterThan(0));
      expect(cheap.tooDear, 0);
    });

    test('a very high price loses more guests than it earns', () {
      int earned(int markup) {
        var total = 0;
        for (final seed in [1, 2, 3]) {
          final d = kitchen(rep: 60)..markup[Dish.burger] = markup;
          total += play(d, seed: seed).earned;
        }
        return total;
      }

      final usual = earned(0);
      final greedy = earned(60);
      expect(greedy, lessThan(usual), reason: 'most guests will not pay it');
    });

    test('a modest rise earns more from the guests who stay', () {
      double perGuest(int markup) {
        var total = 0.0;
        var n = 0;
        for (final seed in [1, 2, 3]) {
          final d = kitchen(rep: 60)..markup[Dish.burger] = markup;
          final s = play(d, seed: seed);
          total += s.earned;
          n += s.served;
        }
        return total / n;
      }

      expect(perGuest(30), greaterThan(perGuest(0)));
      expect(perGuest(-30), lessThan(perGuest(0)));
    });

    test('the markup shows in what the cook is paid', () {
      final cheap = kitchen()..markup[Dish.burger] = -30;
      final fine = kitchen()..markup[Dish.burger] = 30;
      final a = play(cheap, seed: 1);
      final b = play(fine, seed: 1);
      expect(b.earned / b.served, greaterThan(a.earned / a.served * 1.3));
    });

    test('big spenders tip more than thrifty guests, on the same meal', () {
      double fraction(Wallet w) {
        var tip = 0.0;
        var n = 0.0;
        for (final seed in [1, 2, 3, 4]) {
          final sim = DinerSim(kitchen(rep: 80), seed: seed);
          final seen = <int>{};
          while (!sim.finished && sim.ticks < 2000) {
            sim.tick();
            for (final g in sim.guests.where(
              (g) => g.wallet == w && g.state == GuestState.eating,
            )) {
              if (!seen.add(g.id)) continue;
              final price = g.items.fold(
                0.0,
                (a, i) => a + sim.progress.price(i.dish) * i.quality,
              );
              if (price == 0) continue;
              tip += g.tipExact / price;
              n++;
            }
          }
        }
        return n == 0 ? 0 : tip / n;
      }

      expect(fraction(Wallet.wealthy), greaterThan(fraction(Wallet.thrifty)));
    });
  });

  group('on screen', () {
    Future<Diner> open(WidgetTester tester) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
      });
      Storage.clearMemory();
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final d = kitchen();
      await tester.pumpWidget(HexApp(home: BuildScreen(diner: d)));
      await tester.pump();
      await openApp(tester, 'menu');
      await tester.tap(find.byKey(const ValueKey('dish-burger')));
      await tester.pumpAndSettle();
      return d;
    }

    testWidgets('the dish page has a price you can raise and lower', (
      tester,
    ) async {
      final d = await open(tester);
      expect(find.text('Usual price'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('price-plus')));
      await tester.pump();
      expect(d.markupOf(Dish.burger), 10);
      expect(find.text('+10%'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('price-minus')));
      await tester.tap(find.byKey(const ValueKey('price-minus')));
      await tester.pump();
      expect(find.text('-10%'), findsOneWidget);
    });

    testWidgets('and it says which guests will pay it', (tester) async {
      final d = await open(tester);
      expect(find.text('Thrifty buys'), findsOneWidget);
      expect(find.text('Regular buys'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('price-plus')));
      await tester.pump();
      expect(find.text('Thrifty walks out'), findsOneWidget);
      expect(find.text('Regular buys'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const ValueKey('price-plus')));
        await tester.pump();
      }
      expect(find.text('Regular walks out'), findsOneWidget);
      expect(find.text('Big spender buys'), findsOneWidget);
      expect(d.markupOf(Dish.burger), 40);
    });

    testWidgets('the buttons stop at the limits', (tester) async {
      final d = await open(tester);
      for (var i = 0; i < 12; i++) {
        await tester.tap(
          find.byKey(const ValueKey('price-plus')),
          warnIfMissed: false,
        );
        await tester.pump();
      }
      expect(d.markupOf(Dish.burger), Diner.markupMax);
      for (var i = 0; i < 12; i++) {
        await tester.tap(
          find.byKey(const ValueKey('price-minus')),
          warnIfMissed: false,
        );
        await tester.pump();
      }
      expect(d.markupOf(Dish.burger), Diner.markupMin);
    });

    testWidgets('the dish page shows the price as it stands', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('price-plus')));
      await tester.pump();
      expect(find.text('Price 8.8'), findsOneWidget);
    });
  });
}
