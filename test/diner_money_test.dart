// What a day made and cost, over the days, and what to do about it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/crowd.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/goals.dart';
import 'package:hex/diner/money.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/diner/service.dart';
import 'package:hex/diner/stats_screen.dart';
import 'package:hex/diner/suppliers.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';
import 'package:hex/ui/pixel_lines.dart';

DayReport report({
  int earned = 140,
  int tips = 20,
  int ingredients = 60,
  int wages = 35,
  int spoiled = 0,
  int served = 20,
  int wasted = 0,
}) => DayReport(
  day: 4,
  served: served,
  walkouts: 0,
  earned: earned,
  tips: tips,
  wasted: wasted,
  avgWait: 10,
  stars: 2,
  xp: 10,
  levelsGained: 0,
  reputation: 70,
  reputationBefore: 68,
  tomorrow: 20,
  wages: wages,
  unpaid: 0,
  quit: const [],
  story: const [],
  moods: const [],
  ingredients: ingredients,
  spoiled: spoiled,
);

DayLog log(
  int day, {
  int income = 100,
  int ingredients = 30,
  int wages = 20,
  int leftover = 0,
  int spoiled = 0,
  String supplier = 'standard',
}) => DayLog(
  day: day,
  kept: income - ingredients - wages,
  served: 10,
  walkouts: 0,
  rating: 70,
  detailed: true,
  income: income,
  ingredients: ingredients,
  wages: wages,
  leftover: leftover,
  spoiled: spoiled,
  supplier: supplier,
);

void main() {
  group('a day in the books', () {
    test('keeps what came in and what went out', () {
      final back = DayLog.fromJson(
        log(3, income: 120, ingredients: 40, wages: 25, leftover: 6).toJson(),
      )!;
      expect(back.detailed, isTrue);
      expect(
        [back.income, back.ingredients, back.wages, back.leftover],
        [120, 40, 25, 6],
      );
      expect(back.costs, 65);
      expect(back.kept, 55);
      expect(back.supplier, 'standard');
    });

    test('a day from an older save has only what was kept', () {
      final back = DayLog.fromJson({'d': 2, 'k': 30, 's': 8, 'w': 1, 'r': 60})!;
      expect(back.detailed, isFalse);
      expect(back.kept, 30);
      expect(back.income, 0);
      expect(back.toJson().containsKey('i'), isFalse);
    });

    test('the line beside what was kept', () {
      expect(profitLine(report()), 'Took 140, costs 95');
    });
  });

  group('over the days', () {
    test('adds up, and leaves out days without figures', () {
      final v = MoneyView([
        DayLog(day: 1, kept: 99, served: 1, walkouts: 0, rating: 50),
        log(2, income: 100, ingredients: 30, wages: 20),
        log(3, income: 200, ingredients: 50, wages: 30),
      ]);
      expect(v.days.length, 2);
      expect(v.income, 300);
      expect(v.costsAvg, 65);
      expect(v.incomeAvg, 150);
      expect(v.kept, 170);
      expect(v.keptAvg, 85);
      expect(v.share(v.wages), 17);
    });

    test('nothing to show before a day has been run', () {
      expect(MoneyView(const []).isEmpty, isTrue);
      expect(MoneyView(const []).savings(), isEmpty);
    });

    test('wages that are most of the takings are named', () {
      final v = MoneyView([
        for (var i = 1; i <= 4; i++)
          log(i, income: 100, ingredients: 20, wages: 55),
      ]);
      expect(v.savings().single, contains('Wages are 55%'));
    });

    test('so is food, and food thrown away, biggest first', () {
      final v = MoneyView([
        for (var i = 1; i <= 4; i++)
          log(i, income: 100, ingredients: 50, wages: 10, leftover: 12),
      ]);
      final s = v.savings();
      expect(s.length, 2);
      expect(s.first, contains('Ingredients are 50%'));
      expect(s.last, contains('Food worth 48 was thrown away over 4 days'));
    });

    test('spoiled food points to the supplier', () {
      final v = MoneyView([
        for (var i = 1; i <= 3; i++)
          log(i, income: 200, ingredients: 30, wages: 20, spoiled: 3),
      ]);
      expect(v.savings().single, contains('9 portions arrived spoiled'));
    });

    test('costs in proportion say nothing', () {
      final v = MoneyView([for (var i = 1; i <= 4; i++) log(i)]);
      expect(v.savings(), isEmpty);
    });

    test('at most three tips', () {
      final v = MoneyView([
        for (var i = 1; i <= 4; i++)
          log(
            i,
            income: 100,
            ingredients: 50,
            wages: 50,
            leftover: 15,
            spoiled: 5,
          ),
      ]);
      expect(v.savings().length, 3);
      expect(v.savings(limit: 1).length, 1);
    });
  });

  group('a word about the supplier', () {
    test('spoiled budget food says what it cost and what else would have', () {
      final h = supplierHint(
        report(ingredients: 80, spoiled: 8, served: 30),
        Supplier.market,
        1,
        farmSeen: false,
      )!;
      expect(h, contains('8 portions arrived spoiled'));
      expect(h, contains('The usual supplier would have cost about 20 more'));
    });

    test('and says so when the cheap one is still ahead', () {
      final h = supplierHint(
        report(ingredients: 80, spoiled: 2, served: 60),
        Supplier.market,
        1,
        farmSeen: false,
      )!;
      expect(h, contains('Budget still comes out ahead'));
    });

    test('and when the usual one would have paid for itself', () {
      final h = supplierHint(
        report(ingredients: 80, spoiled: 20, served: 20),
        Supplier.market,
        1,
        farmSeen: false,
      )!;
      expect(h, contains('paid for itself'));
    });

    test('nothing to say about budget food that arrived fine', () {
      expect(
        supplierHint(report(spoiled: 1), Supplier.market, 5, farmSeen: false),
        isNull,
      );
    });

    test('the farm is announced once, at its level, with the numbers', () {
      final r = report(ingredients: 80, tips: 40);
      final h = supplierHint(r, Supplier.standard, 3, farmSeen: false)!;
      expect(h, startsWith('Farm delivery is open'));
      expect(h, contains('about 20 more and brings about 4 more in tips'));
      expect(supplierHint(r, Supplier.standard, 3, farmSeen: true), isNull);
      expect(supplierHint(r, Supplier.standard, 2, farmSeen: false), isNull);
    });

    test('a day that lost money points at the budget market', () {
      final h = supplierHint(
        report(earned: 50, ingredients: 60, wages: 30),
        Supplier.standard,
        1,
        farmSeen: true,
      )!;
      expect(h, contains('The day lost money'));
      expect(h, contains('cut ingredients by about 12'));
    });

    test('the farm says when it did not pay', () {
      final h = supplierHint(
        report(ingredients: 100, tips: 22),
        Supplier.farm,
        5,
        farmSeen: true,
      )!;
      expect(h, contains('about 20 more'));
      expect(h, contains('about 2 more in tips'));
      expect(
        supplierHint(
          report(ingredients: 100, tips: 400),
          Supplier.farm,
          5,
          farmSeen: true,
        ),
        isNull,
      );
    });

    test('a tip once shown is remembered across a save', () {
      final d = Diner.starter()..hintsSeen.add('farm');
      expect(Diner.fromJson(d.toJson()).hintsSeen, {'farm'});
    });
  });

  group('after a real day', () {
    Diner cafe() {
      final d = Diner.starter();
      d.progress.upgrades[Upgrade.staff] = 2;
      d.goalsDone.addAll([for (final g in goals) g.id]);
      return d;
    }

    test('the book has the money, and it adds up', () {
      final d = cafe();
      final sim = DinerSim(d, seed: 3);
      while (!sim.finished && sim.ticks < 2500) {
        sim.tick();
      }
      final r = sim.result ?? sim.finishDay();
      final l = d.history.last;
      expect(l.detailed, isTrue);
      expect(l.income, r.earned);
      expect(l.ingredients, r.ingredients);
      expect(l.wages, r.wages);
      expect(l.kept, l.income - l.ingredients - l.wages);
      expect(l.supplier, 'standard');
    });

    test('a day on another supplier is a goal done', () {
      final d = cafe();
      final goal = goals.firstWhere((g) => g.id == 'supplier');
      final facts = GoalFacts(d, null);
      expect(goal.done(facts), isFalse);
      d.history.add(log(1, supplier: 'standard'));
      expect(goal.done(facts), isFalse);
      d.history.add(log(2, supplier: 'market'));
      expect(goal.done(facts), isTrue);
    });
  });

  group('the lines', () {
    test('as wide as the days it covers', () {
      expect(PixelLines.widthFor(1, 12), 5);
      expect(PixelLines.widthFor(8, 12), 89);
    });

    test('repaint only when something changed', () {
      final a = [
        const PixelSeries([1, 2, 3], Colors.red),
      ];
      final p = LinesPainter(a, 40, 12, 2);
      expect(p.shouldRepaint(LinesPainter(a, 40, 12, 2)), isFalse);
      expect(p.shouldRepaint(LinesPainter(a, 40, 12, 3)), isTrue);
      expect(
        p.shouldRepaint(
          LinesPainter(
            [
              const PixelSeries([1, 2, 4], Colors.red),
            ],
            40,
            12,
            2,
          ),
        ),
        isTrue,
      );
    });
  });

  group('on screen', () {
    Future<void> show(WidgetTester tester, Widget page) async {
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

    Diner withDays(List<DayLog> days) {
      final d = Diner.starter();
      d.history.addAll(days);
      return d;
    }

    testWidgets('the money tab is empty before a day', (tester) async {
      await show(tester, StatsScreen(diner: Diner.starter()));
      await tester.tap(find.byKey(const ValueKey('tab-money')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('money-empty')), findsOneWidget);
    });

    testWidgets('and shows the figures and the charts after some', (
      tester,
    ) async {
      final d = withDays([
        for (var i = 1; i <= 6; i++)
          log(i, income: 90 + i * 10, ingredients: 40, wages: 30, leftover: 3),
      ]);
      await show(tester, StatsScreen(diner: d));
      await tester.tap(find.byKey(const ValueKey('tab-money')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('money-took')), findsOneWidget);
      expect(find.byKey(const ValueKey('money-costs')), findsOneWidget);
      expect(find.byKey(const ValueKey('money-kept')), findsOneWidget);
      expect(find.byKey(const ValueKey('money-lines')), findsOneWidget);
      expect(find.byType(PixelLines), findsOneWidget);
      expect(find.byKey(const ValueKey('money-kept-chart')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('money-savings')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const ValueKey('money-savings')), findsOneWidget);
    });

    testWidgets('days from an older save are left out, and it says so', (
      tester,
    ) async {
      final d = withDays([
        DayLog(day: 1, kept: 20, served: 5, walkouts: 0, rating: 50),
        log(2),
        log(3),
      ]);
      await show(tester, StatsScreen(diner: d));
      await tester.tap(find.byKey(const ValueKey('tab-money')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('note')), findsOneWidget);
    });

    Future<void> playDay(WidgetTester tester, Diner d) async {
      await show(tester, BuildScreen(diner: d));
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('speed-3')));
      await tester.pump();
      for (var i = 0; i < 1500; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byKey(const ValueKey('next-day')).evaluate().isNotEmpty) break;
      }
      expect(find.byKey(const ValueKey('next-day')), findsOneWidget);
    }

    testWidgets('the summary says what came in and what went out', (
      tester,
    ) async {
      final d = Diner.starter();
      d.goalsDone.addAll([for (final g in goals) g.id]);
      await playDay(tester, d);
      final r = d.history.last;
      await tester.ensureVisible(find.byKey(const ValueKey('profit-line')));
      expect(find.text('Took ${r.income}, costs ${r.costs}'), findsOneWidget);
    });

    testWidgets('and the farm is mentioned the first time it is open', (
      tester,
    ) async {
      final d = Diner.starter();
      d.progress.level = 3;
      d.goalsDone.addAll([for (final g in goals) g.id]);
      await playDay(tester, d);
      expect(find.byKey(const ValueKey('supplier-hint')), findsOneWidget);
      expect(d.hintsSeen, contains('farm'));
    });
  });
}
