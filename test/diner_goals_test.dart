// Goals to aim for, with a reward each, and the first few as a tutorial.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/goals.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/diner/service.dart';
import 'package:hex/diner/staff.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';

DayReport report({
  int served = 5,
  int walkouts = 2,
  int earned = 100,
  int cars = 0,
  int cleaned = 0,
  int reviewDelta = 0,
  int ingredients = 20,
  int wages = 20,
}) => DayReport(
  day: 1,
  served: served,
  walkouts: walkouts,
  earned: earned,
  tips: 0,
  wasted: 0,
  avgWait: 5,
  stars: 2,
  xp: 10,
  levelsGained: 0,
  reputation: 30,
  reputationBefore: 25,
  tomorrow: 10,
  wages: wages,
  unpaid: 0,
  quit: const [],
  story: const [],
  moods: const [],
  ingredients: ingredients,
  cars: cars,
  cleaned: cleaned,
  reviewDelta: reviewDelta,
);

/// A restaurant with every goal but [id] already done, so only that one can
/// be met, and a way to see whether it was.
bool meets(String id, void Function(Diner d) setUp, [DayReport? day]) {
  final d = Diner.starter()..coins = 5000;
  d.goalsDone.addAll([
    for (final g in goals)
      if (g.id != id) g.id,
  ]);
  setUp(d);
  return d.checkGoals(day).any((g) => g.id == id);
}

void main() {
  group('the goals', () {
    test('there is a list, each with its own name, a reward and words', () {
      expect(goals.length, greaterThanOrEqualTo(12));
      expect(goals.map((g) => g.id).toSet().length, goals.length);
      for (final g in goals) {
        expect(g.title, isNotEmpty);
        expect(g.title, isNot(endsWith('.')), reason: g.id);
        expect(g.reward, greaterThan(0), reason: g.id);
      }
    });

    test('the first ones teach: each says how', () {
      for (final g in goals.take(10)) {
        expect(g.hint, isNotNull, reason: g.id);
        expect(g.hint, endsWith('.'), reason: g.id);
      }
      expect(goals.first.id, 'open');
    });

    test('they get worth more as they get harder', () {
      final first = goals.take(4).map((g) => g.reward).reduce((a, b) => a + b);
      final last = goals.reversed
          .take(4)
          .map((g) => g.reward)
          .reduce((a, b) => a + b);
      expect(last, greaterThan(first));
    });

    test('the next three are the first three not done', () {
      final d = Diner.starter();
      expect(d.activeGoals.map((g) => g.id), ['open', 'serve10', 'level2']);
      d.goalsDone.add('open');
      expect(d.activeGoals.map((g) => g.id), ['serve10', 'level2', 'rating2']);
      expect(d.currentGoal!.id, 'serve10');
    });

    test('when they are all done there is nothing to point at', () {
      final d = Diner.starter();
      d.goalsDone.addAll([for (final g in goals) g.id]);
      expect(d.activeGoals, isEmpty);
      expect(d.currentGoal, isNull);
      expect(d.hint, isNull);
    });

    test('the hint names the goal and how to do it', () {
      final d = Diner.starter();
      expect(
        d.hint,
        'Goal: Open the doors. Press Start day when you are ready. Guests '
        'come to the door.',
      );
    });
  });

  group('meeting them', () {
    test('open the doors: a day has been played', () {
      expect(meets('open', (d) {}), isFalse);
      expect(meets('open', (d) => d.progress.day = 2), isTrue);
    });

    test('serve ten in a day: only when a day ends with ten', () {
      expect(meets('serve10', (d) {}), isFalse);
      expect(meets('serve10', (d) {}, report(served: 9)), isFalse);
      expect(meets('serve10', (d) {}, report(served: 10)), isTrue);
    });

    test('level two, and two stars, as soon as they are true', () {
      expect(meets('level2', (d) {}), isFalse);
      expect(meets('level2', (d) => d.progress.level = 2), isTrue);
      expect(meets('rating2', (d) => d.progress.reputation = 39), isFalse);
      expect(meets('rating2', (d) => d.progress.reputation = 40), isTrue);
    });

    test('fries on the menu needs the fryer to be there', () {
      expect(meets('fries', (d) => d.progress.level = 2), isFalse);
      expect(
        meets('fries', (d) {
          d.progress.level = 2;
          d.place(Kind.fryer, const Cell(4, 3), Dir.sw);
        }),
        isTrue,
      );
    });

    test('setting a price, hiring, buying the room, the TV, the window', () {
      expect(meets('price', (d) {}), isFalse);
      expect(meets('price', (d) => d.nudgePrice(Dish.burger, 1)), isTrue);
      expect(meets('hire', (d) {}), isFalse);
      expect(
        meets('hire', (d) {
          d.progress.upgrades[Upgrade.staff] = 1;
          d.roster.employees.add(
            Staff(
              id: 9,
              name: 'Z',
              stats: {for (final s in Stat.values) s: 3},
              potential: {for (final s in Stat.values) s: 6},
            ),
          );
        }),
        isTrue,
      );
      expect(meets('right', (d) {}), isFalse);
      expect(
        meets('right', (d) {
          d.progress.level = 9;
          d.unlock(1);
        }),
        isTrue,
      );
      expect(meets('tv', (d) {}), isFalse);
      expect(
        meets('tv', (d) {
          d.progress.level = 5;
          d.place(Kind.tv, const Cell(1, 6));
        }),
        isTrue,
      );
      expect(meets('window', (d) {}), isFalse);
      expect(
        meets('window', (d) {
          d.progress.level = 5;
          d.owned.add(1);
          d.place(Kind.window, Cell(d.right, 3));
        }),
        isTrue,
      );
    });

    test('a day of cars, tables cleared, and nobody angry', () {
      expect(meets('cars5', (d) {}, report(cars: 4)), isFalse);
      expect(meets('cars5', (d) {}, report(cars: 5)), isTrue);
      expect(meets('clean5', (d) {}, report(cleaned: 4)), isFalse);
      expect(meets('clean5', (d) {}, report(cleaned: 5)), isTrue);
      expect(meets('happy', (d) {}, report(served: 12, walkouts: 1)), isFalse);
      expect(meets('happy', (d) {}, report(served: 3, walkouts: 0)), isFalse);
      expect(meets('happy', (d) {}, report(served: 12, walkouts: 0)), isTrue);
    });

    test('keeping 300 counts what is left after costs', () {
      expect(
        meets(
          'kept300',
          (d) {},
          report(earned: 340, ingredients: 30, wages: 30),
        ),
        isFalse,
      );
      expect(
        meets(
          'kept300',
          (d) {},
          report(earned: 400, ingredients: 50, wages: 50),
        ),
        isTrue,
      );
    });

    test('the critic is won over with a good review', () {
      expect(meets('critic', (d) {}, report(reviewDelta: 2)), isFalse);
      expect(meets('critic', (d) {}, report(reviewDelta: 8)), isTrue);
    });

    test('the whole plot means every section', () {
      expect(meets('plot', (d) => d.owned.addAll({1, 2, 3, 4})), isFalse);
      expect(meets('plot', (d) => d.owned.addAll({1, 2, 3, 4, 5})), isFalse);
      expect(
        meets('plot', (d) => d.owned.addAll({1, 2, 3, 4, 5, 6, 7, 8, 9})),
        isFalse,
        reason: 'the wings on the left count too',
      );
      expect(
        meets('plot', (d) => d.owned.addAll({for (var i = 1; i <= 12; i++) i})),
        isTrue,
      );
    });

    test('a goal about a day only counts when a day has ended', () {
      for (final id in [
        'serve10',
        'clean5',
        'cars5',
        'kept300',
        'critic',
        'happy',
      ]) {
        expect(meets(id, (d) {}), isFalse, reason: id);
      }
    });
  });

  group('the reward', () {
    test('it is paid when the goal is met, and only once', () {
      final d = Diner.starter()..coins = 100;
      d.progress.day = 2;
      final met = d.checkGoals();
      expect(met.map((g) => g.id), contains('open'));
      final paid = met.fold(0, (a, g) => a + g.reward);
      expect(d.coins, 100 + paid);
      expect(d.goalsDone, contains('open'));
      final again = d.checkGoals();
      expect(again.where((g) => g.id == 'open'), isEmpty);
      expect(d.coins, 100 + paid);
    });

    test('several can be met at once, and all are paid', () {
      final d = Diner.starter()..coins = 0;
      d.progress
        ..day = 2
        ..level = 2
        ..reputation = 50;
      final met = d.checkGoals(report(served: 12));
      final ids = met.map((g) => g.id).toSet();
      expect(ids, containsAll(['open', 'serve10', 'level2', 'rating2']));
      expect(d.coins, met.fold(0, (a, g) => a + g.reward));
    });

    test('a goal that is not met pays nothing', () {
      final d = Diner.starter()..coins = 100;
      d.goalsDone.addAll([for (final g in goals) g.id]);
      expect(d.checkGoals(report()), isEmpty);
      expect(d.coins, 100);
    });
  });

  group('saving', () {
    test('what is done is saved, and not paid again', () {
      final d = Diner.starter()..coins = 100;
      d.progress.day = 2;
      d.checkGoals();
      final back = Diner.fromJson(d.toJson());
      expect(back.goalsDone, d.goalsDone);
      final coins = back.coins;
      back.checkGoals();
      expect(back.coins, coins);
    });

    test(
      'an old save with no goals starts clean, and a bad one is ignored',
      () {
        expect(Diner.fromJson({'coins': 1, 'items': []}).goalsDone, isEmpty);
        final odd = Diner.fromJson({
          'coins': 1,
          'items': [],
          'goals': ['open', 3, null, 'nonsense'],
        });
        expect(odd.goalsDone, containsAll(['open', 'nonsense']));
        expect(odd.activeGoals.first.id, 'serve10');
      },
    );
  });

  group('on screen', () {
    Future<Diner> open(WidgetTester tester, {Diner? diner}) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
      });
      Storage.clearMemory();
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final d = diner ?? Diner.starter();
      await tester.pumpWidget(HexApp(home: BuildScreen(diner: d)));
      await tester.pump();
      return d;
    }

    testWidgets('a new restaurant says what to do first', (tester) async {
      await open(tester);
      expect(
        find.textContaining('Goal: Open the doors. Press Start day'),
        findsOneWidget,
      );
    });

    testWidgets('the goals page lists the next three, with how and what for', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('goals')));
      await tester.pumpAndSettle();
      expect(find.text('0 of ${goals.length} done'), findsOneWidget);
      for (final id in ['open', 'serve10', 'level2']) {
        expect(find.byKey(ValueKey('goal-$id')), findsOneWidget);
      }
      expect(find.textContaining('Press Start day'), findsOneWidget);
      expect(find.text('Open the doors'), findsOneWidget);
    });

    testWidgets('done goals move to the bottom, marked', (tester) async {
      final d = Diner.starter()..goalsDone.add('open');
      await open(tester, diner: d);
      await tester.tap(find.byKey(const ValueKey('goals')));
      await tester.pumpAndSettle();
      expect(find.text('1 of ${goals.length} done'), findsOneWidget);
      // The next three have moved on.
      expect(find.byKey(const ValueKey('goal-rating2')), findsOneWidget);
    });

    testWidgets('finishing a day tells you the goal you have just met', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('speed-3')));
      await tester.pump();
      for (var i = 0; i < 900; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byKey(const ValueKey('next-day')).evaluate().isNotEmpty) break;
      }
      expect(find.byKey(const ValueKey('goal-line')), findsOneWidget);
    });

    testWidgets('and the reward is in the till', (tester) async {
      final d = await open(tester);
      final before = d.coins;
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('speed-3')));
      await tester.pump();
      for (var i = 0; i < 900; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byKey(const ValueKey('next-day')).evaluate().isNotEmpty) break;
      }
      expect(d.goalsDone, contains('open'));
      expect(d.coins, greaterThan(before));
    });

    testWidgets('doing something that is a goal says so straight away', (
      tester,
    ) async {
      final d = await open(tester);
      d.goalsDone.addAll(['open', 'serve10', 'level2', 'rating2', 'fries']);
      await tester.tap(find.byKey(const ValueKey('menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dish-burger')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('price-plus')));
      await tester.pump();
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pump(const Duration(milliseconds: 500));
      expect(d.goalsDone, contains('price'));
      expect(
        find.textContaining('Goal done: Set your own price'),
        findsOneWidget,
      );
    });

    testWidgets('with every goal done, the page says so', (tester) async {
      final d = Diner.starter()
        ..goalsDone.addAll([for (final g in goals) g.id]);
      await open(tester, diner: d);
      await tester.tap(find.byKey(const ValueKey('goals')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('all-done')), findsOneWidget);
    });
  });
}
