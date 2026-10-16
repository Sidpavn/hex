// The board outside with a special on it, where the ingredients come from, a
// food blogger who wants a fair price, and the line that says what to fix.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/advice.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/city.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/events.dart';
import 'package:hex/diner/goals.dart';
import 'package:hex/diner/guests.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/diner/service.dart';
import 'package:hex/diner/staff.dart';
import 'package:hex/diner/suppliers.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';

int dayWith(DayEvent event, {int level = 5}) {
  for (var d = 2; d < 600; d++) {
    if (DayEvent.forDay(d, level) == event) return d;
  }
  throw StateError('no $event day');
}

int plainDay() => dayWith(DayEvent.none);

Diner cafe({int day = 1, int level = 5, int rep = 60, int cooks = 3}) {
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

DayReport report({
  int served = 20,
  int walkouts = 0,
  int earned = 400,
  int ingredients = 100,
  int wages = 50,
  int unpaid = 0,
  int soldOut = 0,
  int tooDear = 0,
  int gaveUp = 0,
  int queueFull = 0,
  int spoiled = 0,
  int leftover = 0,
}) => DayReport(
  day: 3,
  served: served,
  walkouts: walkouts,
  earned: earned,
  tips: 0,
  wasted: 0,
  avgWait: 5,
  stars: 2,
  xp: 10,
  levelsGained: 0,
  reputation: 50,
  reputationBefore: 50,
  tomorrow: 20,
  wages: wages,
  unpaid: unpaid,
  quit: const [],
  story: const [],
  moods: const [],
  ingredients: ingredients,
  soldOut: soldOut,
  tooDear: tooDear,
  gaveUp: gaveUp,
  queueFull: queueFull,
  spoiled: spoiled,
  leftover: leftover,
);

void main() {
  group('the special', () {
    test('only something on the menu can go on the board', () {
      final d = cafe();
      expect(d.specialActive, isFalse);
      expect(d.toggleSpecial(Dish.pizza), isFalse, reason: 'no oven');
      expect(d.special, isNull);
      expect(d.toggleSpecial(Dish.burger), isTrue);
      expect(d.isSpecial(Dish.burger), isTrue);
      expect(d.specialActive, isTrue);
    });

    test('again takes it off, and another replaces it', () {
      final d = cafe();
      d.toggleSpecial(Dish.burger);
      expect(d.toggleSpecial(Dish.burger), isFalse);
      expect(d.special, isNull);
      d.toggleSpecial(Dish.burger);
      expect(d.toggleSpecial(Dish.fries), isTrue);
      expect(d.isSpecial(Dish.burger), isFalse);
      expect(d.isSpecial(Dish.fries), isTrue);
    });

    test('a dish that leaves the menu leaves the board', () {
      final d = cafe();
      d.toggleSpecial(Dish.burger);
      d.toggleOffer(Dish.burger);
      expect(d.specialActive, isFalse);
      expect(d.priceRatio(Dish.burger), 1);
    });

    test('it sells for a fifth less, and shows in the price', () {
      final d = cafe();
      final before = d.sellPrice(Dish.burger);
      d.toggleSpecial(Dish.burger);
      expect(d.sellPrice(Dish.burger), closeTo(before * 0.8, 1e-9));
      expect(
        d.sellPrice(Dish.fries),
        closeTo(cafe().sellPrice(Dish.fries), 1e-9),
      );
    });

    test('a few more people come, and it counts in the forecast', () {
      final plain = cafe(day: plainDay());
      final board = cafe(day: plainDay())..toggleSpecial(Dish.burger);
      expect(board.expectedToday, greaterThan(plain.expectedToday));
      expect(
        DinerSim(board, seed: 2).arrivalSchedule.length,
        greaterThan(DinerSim(plain, seed: 2).arrivalSchedule.length),
      );
    });

    test('guests ask for it more often', () {
      double share(Dish dish, bool board) {
        var mine = 0;
        var all = 0;
        for (final seed in [1, 2, 3, 4]) {
          final d = cafe(day: plainDay());
          d.declined.remove(Dish.cheeseburger);
          d.menu();
          if (board) d.toggleSpecial(dish);
          final sim = DinerSim(d, seed: seed);
          final counted = <int>{};
          while (!sim.finished && sim.ticks < 2500) {
            sim.tick();
            for (final g in sim.guests) {
              if (g.items.isEmpty || !counted.add(g.id)) continue;
              for (final i in g.items) {
                if (recipes[i.dish]!.course != recipes[dish]!.course) continue;
                all++;
                if (i.dish == dish) mine++;
              }
            }
          }
        }
        return mine / all;
      }

      final mains = recipes.values.where((r) => r.course == Course.main);
      expect(mains.length, greaterThan(1));
      expect(
        share(Dish.cheeseburger, true),
        greaterThan(share(Dish.cheeseburger, false)),
      );
    });

    test('it is saved', () {
      final d = cafe()..toggleSpecial(Dish.burger);
      final back = Diner.fromJson(d.toJson());
      expect(back.special, Dish.burger);
      expect(Diner.fromJson(cafe().toJson()).special, isNull);
    });

    test('the board stands outside the door only while there is one', () {
      final d = cafe();
      expect(streetProps(d).map((p) => p.$1), isNot(contains('special_board')));
      d.toggleSpecial(Dish.burger);
      final board = streetProps(d).firstWhere((p) => p.$1 == 'special_board');
      expect(board.$2.x, d.entrance.x - 1, reason: 'next to the door');
      expect(board.$2.y, greaterThan(d.entrance.y), reason: 'outside it');
    });

    test('the board has a picture', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final art = await DinerArt.load();
      expect(art.sprite('special_board').blank, isFalse);
    });
  });

  group('suppliers', () {
    test('the usual one changes nothing', () {
      final d = cafe();
      expect(d.supplier, Supplier.standard);
      expect(Supplier.standard.costMul, 1);
      expect(Supplier.standard.spoiledShare(5), 0);
    });

    test('the market is cheaper and the farm dearer', () {
      final d = cafe();
      final usual = d.unitCost(Dish.burger);
      d.supplier = Supplier.market;
      expect(d.unitCost(Dish.burger), closeTo(usual * 0.8, 1e-9));
      d.supplier = Supplier.farm;
      expect(d.unitCost(Dish.burger), closeTo(usual * 1.25, 1e-9));
      expect(d.prepCost(), greaterThan(cafe().prepCost()));
    });

    test('the farm opens at level 3', () {
      expect(Supplier.farm.unlock, 3);
      final d = cafe(level: 2)..supplier = Supplier.farm;
      expect(Diner.fromJson(d.toJson()).supplier, Supplier.standard);
      final ok = cafe()..supplier = Supplier.farm;
      expect(Diner.fromJson(ok.toJson()).supplier, Supplier.farm);
    });

    test('the market loses a tenth, and a bad day a third', () {
      var bad = 0;
      var ordinary = 0;
      for (var day = 1; day < 200; day++) {
        final s = Supplier.market.spoiledShare(day);
        expect(s, anyOf(0.1, 0.35));
        s == 0.35 ? bad++ : ordinary++;
      }
      expect(bad, inInclusiveRange(15, 70));
      expect(ordinary, greaterThan(bad));
    });

    test('spoiled portions are paid for and never served', () {
      final usual = play(cafe(day: plainDay()), seed: 3);
      final market = cafe(day: plainDay())..supplier = Supplier.market;
      final sim = DinerSim(market, seed: 3);
      while (!sim.finished && sim.ticks < 2500) {
        sim.tick();
      }
      expect(sim.spoiled, greaterThan(0));
      expect(sim.result!.spoiled, sim.spoiled);
      expect(usual.spoiled, 0);
      final left = sim.stock.values.fold(0, (a, b) => a + b);
      expect(left, greaterThanOrEqualTo(0));
    });

    test('the farm earns bigger tips', () {
      double tips(Supplier s) {
        var t = 0.0;
        for (final seed in [1, 2, 3, 4]) {
          final d = cafe(day: plainDay())..supplier = s;
          final sim = play(d, seed: seed);
          t += sim.tips / (sim.earned - sim.tips).clamp(1, 1 << 30);
        }
        return t;
      }

      expect(tips(Supplier.farm), greaterThan(tips(Supplier.standard)));
    });
  });

  group('the food blogger', () {
    DinerSim blogger(int seed, {int markup = 0}) {
      final d = cafe(day: dayWith(DayEvent.blogger));
      d.markup[Dish.burger] = markup;
      return DinerSim(d, seed: seed);
    }

    test('comes from level 3, on a day of their own', () {
      for (var day = 2; day < 600; day++) {
        for (var level = 1; level < DayEvent.bloggerLevel; level++) {
          expect(DayEvent.forDay(day, level), isNot(DayEvent.blogger));
        }
      }
      expect(DayEvent.blogger.reviewed, isTrue);
      expect(DayEvent.rain.reviewed, isFalse);
      expect(DayEvent.blogger.blurb, contains('fair prices'));
    });

    test('is thrifty and patient, and arrives once, mid-day', () {
      final sim = blogger(2);
      Guest? seen;
      var at = 0;
      while (!sim.finished && sim.ticks < 2500) {
        sim.tick();
        final g = sim.guests.where((g) => g.blogger).firstOrNull;
        if (g != null && seen == null) {
          seen = g;
          at = sim.ticks;
        }
      }
      expect(seen, isNotNull);
      expect(at, inInclusiveRange(Pace.dayTicks * 0.4, Pace.dayTicks * 0.62));
      expect(seen!.name, 'The blogger');
      expect(seen.wallet, Wallet.thrifty);
      expect(seen.critic, isFalse);
      expect(seen.reviewer, isTrue);
    });

    test('a fair price and a quick meal earn a good write-up', () {
      var raved = 0;
      for (final seed in [1, 2, 3, 4]) {
        final sim = blogger(seed, markup: -10);
        while (!sim.finished && sim.ticks < 2500) {
          sim.tick();
        }
        if (sim.reviewDelta == 6) {
          raved++;
          expect(
            sim.story.any((l) => l.text.contains('prices are fair')),
            isTrue,
          );
          expect(sim.result!.reviewDelta, 6);
        }
      }
      expect(raved, greaterThan(0));
    });

    test('a high price loses them, and costs', () {
      var lost = 0;
      for (final seed in [1, 2, 3]) {
        final sim = blogger(seed, markup: 30);
        while (!sim.finished && sim.ticks < 2500) {
          sim.tick();
        }
        // Everything dear: the thrifty blogger walks out of the door.
        if (sim.reviewDelta < 0) lost++;
        expect(sim.reviewDelta, lessThanOrEqualTo(0));
      }
      expect(lost, greaterThan(0));
    });

    test('they judge the rating on top of the day', () {
      final sim = blogger(1, markup: -10);
      final before = sim.progress.reputation;
      while (!sim.finished && sim.ticks < 2500) {
        sim.tick();
      }
      expect(sim.result!.reputationBefore, before);
      expect(sim.result!.event, DayEvent.blogger);
    });

    test('and there is a goal for it', () {
      final d = Diner.starter();
      d.goalsDone.addAll([
        for (final g in goals)
          if (g.id != 'blogger') g.id,
      ]);
      expect(d.checkGoals(report()).any((g) => g.id == 'blogger'), isFalse);
      final good = DayReport(
        day: 3,
        served: 5,
        walkouts: 0,
        earned: 1,
        tips: 0,
        wasted: 0,
        avgWait: 1,
        stars: 3,
        xp: 1,
        levelsGained: 0,
        reputation: 50,
        reputationBefore: 40,
        tomorrow: 1,
        wages: 0,
        unpaid: 0,
        quit: const [],
        story: const [],
        moods: const [],
        event: DayEvent.blogger,
        reviewDelta: 6,
      );
      expect(d.checkGoals(good).any((g) => g.id == 'blogger'), isTrue);
    });
  });

  group('what to fix', () {
    test('a good day has nothing to fix', () {
      expect(fixFirst(report()), isNull);
    });

    test('unpaid wages come first, whatever else went wrong', () {
      expect(
        fixFirst(report(unpaid: 20, soldOut: 9, tooDear: 9)),
        startsWith('Wages went unpaid'),
      );
    });

    test('it names the biggest loss and what to do about it', () {
      expect(
        fixFirst(report(soldOut: 4)),
        '4 guests found their dish sold out. Raise the portions in '
        "Today's portions.",
      );
      expect(fixFirst(report(tooDear: 5)), contains('Lower a price'));
      expect(fixFirst(report(gaveUp: 5)), contains('Add a cook'));
      expect(fixFirst(report(queueFull: 5)), contains('More tables'));
      expect(fixFirst(report(spoiled: 6)), contains('Change supplier'));
      expect(
        fixFirst(report(leftover: 60, ingredients: 100)),
        contains('thrown away'),
      );
      expect(
        fixFirst(report(earned: 100, ingredients: 100, wages: 50)),
        contains('lost money'),
      );
    });

    test('the larger problem wins', () {
      expect(
        fixFirst(report(soldOut: 2, gaveUp: 6)),
        contains('gave up waiting'),
      );
      expect(fixFirst(report(soldOut: 6, gaveUp: 2)), contains('sold out'));
    });

    test('one or two lost guests are not worth a lecture', () {
      expect(fixFirst(report(soldOut: 1, tooDear: 1, gaveUp: 1)), isNull);
    });

    test('a real day fills the counts', () {
      final d = cafe(day: plainDay(), cooks: 1);
      d.supplier = Supplier.market;
      final r = play(d, seed: 2).result!;
      expect(r.gaveUp, greaterThanOrEqualTo(0));
      expect(r.spoiled, greaterThan(0));
      expect(r.queueFull, greaterThanOrEqualTo(0));
      expect(
        r.gaveUp + r.queueFull + r.tooDear + r.soldOut,
        lessThanOrEqualTo(r.walkouts),
      );
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

    testWidgets('the dish page puts it on the board, and takes it off', (
      tester,
    ) async {
      final d = await open(tester, cafe());
      await tester.tap(find.byKey(const ValueKey('menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dish-burger')));
      await tester.pumpAndSettle();
      final btn = find.byKey(const ValueKey('special'));
      await tester.scrollUntilVisible(btn, 200);
      expect(find.text('Make it the special'), findsOneWidget);
      await tester.tap(btn);
      await tester.pump();
      expect(d.special, Dish.burger);
      expect(find.text('Take off the board'), findsOneWidget);
      expect(find.byKey(const ValueKey('special-help')), findsOneWidget);
      await tester.tap(btn);
      await tester.pump();
      expect(d.special, isNull);
    });

    testWidgets('the menu says which dish is the special', (tester) async {
      final d = cafe()..toggleSpecial(Dish.burger);
      await open(tester, d);
      await tester.tap(find.byKey(const ValueKey('menu')));
      await tester.pumpAndSettle();
      expect(find.textContaining('special'), findsOneWidget);
    });

    testWidgets(
      'the portions page chooses the supplier, and says what it means',
      (tester) async {
        final d = await open(tester, cafe());
        await tester.tap(find.byKey(const ValueKey('menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('open-prep')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('suppliers')), findsOneWidget);
        expect(find.text(Supplier.standard.blurb), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('supplier-farm')));
        await tester.pump();
        expect(d.supplier, Supplier.farm);
        expect(find.text(Supplier.farm.blurb), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('supplier-market')));
        await tester.pump();
        expect(d.supplier, Supplier.market);
        expect(find.text(Supplier.market.blurb), findsOneWidget);
      },
    );

    testWidgets('the farm is locked until level 3', (tester) async {
      final d = await open(tester, cafe(level: 2));
      await tester.tap(find.byKey(const ValueKey('menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-prep')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('supplier-farm')));
      await tester.pump();
      expect(d.supplier, Supplier.standard);
      expect(find.textContaining('opens at level 3'), findsOneWidget);
    });

    testWidgets('the end of the day says what to fix first', (tester) async {
      final d = cafe(day: plainDay(), cooks: 1, rep: 90);
      d.supplier = Supplier.market;
      await open(tester, d);
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('speed-3')));
      await tester.pump();
      for (var i = 0; i < 900; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byKey(const ValueKey('next-day')).evaluate().isNotEmpty) break;
      }
      expect(find.byKey(const ValueKey('next-day')), findsOneWidget);
      final fix = find.byKey(const ValueKey('fix-first'));
      if (fix.evaluate().isNotEmpty) {
        expect(find.textContaining('Fix first: '), findsOneWidget);
        expect(find.byKey(const ValueKey('story-line')), findsNothing);
      } else {
        expect(find.byKey(const ValueKey('story-line')), findsOneWidget);
      }
    });
  });
}
