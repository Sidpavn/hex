// Catering orders: an order for the day, cooked by a crew set aside for it
// (or by everyone, with the doors shut), out by closing time or lost.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/contracts.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/goals.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/diner/service.dart';
import 'package:hex/diner/staff.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';

Diner cafe({
  int level = 5,
  int day = 3,
  int cooks = 3,
  int coins = 100000,
  int rep = 70,
}) {
  final d = Diner(
    coins: coins,
    owned: {0, 1},
    progress: Progress(level: level, reputation: rep, day: day),
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

/// The first day from [from] with an offer (or without one) for [d].
int day({required bool offer, int level = 5, int from = 2}) {
  for (var n = from; n < 500; n++) {
    final d = cafe(level: level, day: n);
    if ((ContractBook.offerFor(n, d) != null) == offer) return n;
  }
  throw StateError('no such day');
}

DinerSim play(Diner d, {int seed = 1}) {
  final sim = DinerSim(d, seed: seed);
  while (!sim.finished && sim.ticks < 2500) {
    sim.tick();
  }
  return sim;
}

/// An order set by hand, so a test does not depend on the day's luck.
Contract order({
  required int day,
  Map<Dish, int>? lines,
  int reward = 200,
  String client = 'the office on Elm Street',
}) => Contract(
  day: day,
  client: client,
  lines: lines ?? {Dish.burger: 6, Dish.fries: 4},
  reward: reward,
);

void main() {
  group('the offers', () {
    test('none on day one, and none below three and a half stars', () {
      expect(ContractBook.offerFor(1, cafe(level: 6, day: 1)), isNull);
      for (var n = 2; n < 120; n++) {
        // 3.45 stars: just short.
        expect(ContractBook.offerFor(n, cafe(day: n, rep: 69)), isNull);
        expect(ContractBook.offerFor(n, cafe(day: n, rep: 40)), isNull);
      }
      expect(ContractBook.minRating, 3.5);
    });

    test('at three and a half stars and above they start to come', () {
      var at = 0;
      var above = 0;
      for (var n = 2; n < 200; n++) {
        if (ContractBook.offerFor(n, cafe(day: n, rep: 70)) != null) at++;
        if (ContractBook.offerFor(n, cafe(day: n, rep: 95)) != null) above++;
      }
      expect(at, greaterThan(40));
      expect(above, at, reason: 'the same days once past the line');
    });

    test('a level does not matter, only the rating', () {
      var n = 2;
      while (ContractBook.offerFor(n, cafe(level: 1, day: n)) == null) {
        n++;
      }
      expect(ContractBook.offerFor(n, cafe(level: 1, day: n)), isNotNull);
    });

    test('losing the rating takes the offer away until it is won back', () {
      final n = day(offer: true);
      final d = cafe(day: n);
      expect(d.offer, isNotNull);
      d.progress.reputation = 60;
      expect(d.offer, isNull);
      d.progress.reputation = 75;
      expect(d.offer, isNotNull);
    });

    test('an order already taken stays taken if the rating drops', () {
      final n = day(offer: true);
      final d = cafe(day: n);
      d.takeContract(d.offer!, {70});
      d.progress.reputation = 50;
      expect(d.takenContract, isNotNull);
      expect(d.contractState, ContractState.accepted);
    });

    test('about four days in ten have one, and which is no pattern', () {
      final days = [
        for (var n = 2; n < 400; n++)
          if (ContractBook.offerFor(n, cafe(day: n)) != null) n,
      ];
      expect(days.length / 398, inInclusiveRange(0.3, 0.5));
      final gaps = {
        for (var i = 1; i < days.length; i++) days[i] - days[i - 1],
      };
      expect(gaps.length, greaterThanOrEqualTo(5));
      expect(gaps, contains(1));
    });

    test('it is the same each time it is looked at', () {
      final n = day(offer: true);
      final a = ContractBook.offerFor(n, cafe(day: n))!;
      final b = ContractBook.offerFor(n, cafe(day: n))!;
      expect(a.toJson(), b.toJson());
    });

    test('it is for dishes on the menu, and pays more than it costs', () {
      var seen = 0;
      for (var n = 2; n < 200; n++) {
        final d = cafe(day: n);
        final c = ContractBook.offerFor(n, d);
        if (c == null) continue;
        seen++;
        expect(d.menu(), containsAll(c.lines.keys));
        expect(c.lines.values.every((v) => v >= 3), isTrue);
        expect(c.portions, greaterThanOrEqualTo(10));
        expect(c.reward, greaterThan(c.ingredients(d) * 1.8));
        expect(c.reward % 5, 0);
        expect(ContractBook.clients, contains(c.client));
      }
      expect(seen, greaterThan(20));
    });

    test('a bigger restaurant is asked for more', () {
      double avg(int level) {
        var t = 0;
        var k = 0;
        for (var n = 2; n < 300; n++) {
          final c = ContractBook.offerFor(n, cafe(level: level, day: n));
          if (c == null) continue;
          t += c.portions;
          k++;
        }
        return t / k;
      }

      expect(avg(9), greaterThan(avg(3) + 5));
    });

    test('it says what is in it', () {
      expect(order(day: 3).summary, '6 burger and 4 fries');
      expect(order(day: 3, lines: {Dish.burger: 5}).summary, '5 burger');
      expect(
        order(
          day: 3,
          lines: {Dish.burger: 5, Dish.fries: 4, Dish.coffee: 3},
        ).summary,
        '5 burger, 4 fries and 3 coffee',
      );
    });

    test('it is saved, and a bad one is ignored', () {
      final c = order(day: 3);
      final back = Contract.fromJson(c.toJson())!;
      expect(back.lines, c.lines);
      expect(back.client, c.client);
      expect(back.reward, c.reward);
      expect(Contract.fromJson('rubbish'), isNull);
      expect(
        Contract.fromJson({
          'lines': {'nonsense': 3},
        }),
        isNull,
      );
    });
  });

  group('taking it', () {
    test('it needs someone to cook it, who can', () {
      final d = cafe();
      final c = order(day: 3);
      expect(d.whyNotTake(c, {}), 'Choose who will cook it');
      expect(d.whyNotTake(c, {70}), isNull);
    });

    test('and enough coins for the ingredients', () {
      final d = cafe(coins: 3);
      expect(
        d.whyNotTake(order(day: 3), {70}),
        'Not enough coins for the ingredients',
      );
    });

    test('taken, it is kept for the day with its crew', () {
      final d = cafe();
      final c = order(day: 3);
      expect(d.takeContract(c, {70, 71}), isTrue);
      expect(d.contractState, ContractState.accepted);
      expect(d.takenContract, same(c));
      expect(d.crew.map((s) => s.id), [70, 71]);
      expect(d.offer, isNull, reason: 'no longer on offer');
      expect(d.closedForOrder, isFalse);
    });

    test('with the doors shut it is everyone', () {
      final d = cafe();
      d.takeContract(order(day: 3), {70}, closed: true);
      expect(d.crew.length, 3);
      expect(d.closedForOrder, isTrue);
    });

    test('only once, and not for a crew that cannot do it', () {
      final d = cafe();
      expect(d.takeContract(order(day: 3), {}), isFalse);
      expect(d.takeContract(order(day: 3), {70}), isTrue);
      expect(d.takeContract(order(day: 3, reward: 999), {71}), isFalse);
      expect(d.takenContract!.reward, 200);
    });

    test('turned down, it is gone for the day', () {
      final n = day(offer: true);
      final d = cafe(day: n);
      expect(d.offer, isNotNull);
      d.passContract();
      expect(d.contractState, ContractState.declined);
      expect(d.offer, isNull);
      expect(d.takeContract(order(day: n), {70}), isFalse);
    });

    test('changing your mind puts it back', () {
      final n = day(offer: true);
      final d = cafe(day: n);
      d.takeContract(d.offer!, {70});
      d.cancelContract();
      expect(d.contractState, ContractState.open);
      expect(d.takenContract, isNull);
      expect(d.offer, isNotNull);
      expect(d.crewIds, isEmpty);
    });

    test('tomorrow it is all forgotten', () {
      final n = day(offer: true);
      final d = cafe(day: n);
      d.takeContract(d.offer!, {70}, closed: true);
      d.progress.day = n + 1;
      expect(d.contractState, ContractState.open);
      expect(d.takenContract, isNull);
    });

    test('it survives a save', () {
      final d = cafe();
      d.takeContract(order(day: 3), {70, 72}, closed: true);
      final back = Diner.fromJson(d.toJson());
      expect(back.contractState, ContractState.accepted);
      expect(back.takenContract!.lines, order(day: 3).lines);
      expect(back.crewIds, {70, 72});
      expect(back.closedForOrder, isTrue);
      final plain = Diner.fromJson(cafe().toJson());
      expect(plain.takenContract, isNull);
      expect(plain.contractState, ContractState.open);
    });

    test('a damaged save does not leave an order with nothing in it', () {
      final j = cafe().toJson();
      j['contract'] = {
        'day': 3,
        'state': 'accepted',
        'order': {'lines': {}},
        'crew': [70],
      };
      final d = Diner.fromJson(j);
      expect(d.takenContract, isNull);
      expect(d.contractState, ContractState.open);
    });
  });

  group('cooking it', () {
    test('the crew cook it and send it out, and it pays', () {
      final d = cafe(day: 3);
      final before = d.coins;
      final c = order(day: 3, reward: 300);
      d.takeContract(c, {70});
      final cost = c.ingredients(d);
      final sim = play(d, seed: 2);
      final r = sim.result!;
      expect(sim.cateringState, ContractState.done);
      expect(sim.cateringMade, c.portions);
      expect(sim.cateringPaid, 300);
      expect(r.cateringState, ContractState.done);
      expect(r.cateringReward, 300);
      expect(r.catering, same(c));
      expect(r.closed, isFalse);
      expect(r.ingredients, greaterThanOrEqualTo(cost));
      expect(
        sim.story.any(
          (l) => l.text.startsWith('The order for ${c.client} went out'),
        ),
        isTrue,
      );
      expect(d.coins, greaterThan(before - cost + 250 - 600));
    });

    test('the ingredients are paid for when the day starts', () {
      final d = cafe(day: 3);
      final c = order(day: 3);
      d.takeContract(c, {70});
      final sim = DinerSim(d, seed: 2);
      final before = d.coins;
      sim.tick();
      final bought = before - d.coins;
      expect(bought, greaterThanOrEqualTo(c.ingredients(d)));
      expect(sim.ingredientCost, greaterThanOrEqualTo(c.ingredients(d)));
    });

    test('it is not a customer: nobody sees it, and it is not served', () {
      final d = cafe(day: 3);
      d.takeContract(order(day: 3), {70});
      final sim = DinerSim(d, seed: 2);
      for (var i = 0; i < 200; i++) {
        sim.tick();
        expect(sim.guests.any((g) => g.name == 'Catering'), isFalse);
      }
    });

    test(
      'only the crew cook it, and the crew serve no customers meanwhile',
      () {
        final d = cafe(day: 3);
        final c = order(day: 3, lines: {Dish.burger: 14, Dish.fries: 10});
        d.takeContract(c, {70});
        final sim = DinerSim(d, seed: 2);
        final crew = sim.workers.firstWhere((w) => w.staff.id == 70);
        var crewServedGuests = 0;
        var others = 0;
        for (var i = 0; i < 280 && sim.cateringOpen; i++) {
          sim.tick();
          for (final w in sim.workers) {
            // What a person carries while the order is open is the order's, or
            // a customer's: the crew carry only the order's.
            if (w == crew) {
              crewServedGuests += w.carrying
                  .where((x) => x.guest.name != 'Catering')
                  .length;
            } else {
              others += w.carrying
                  .where((x) => x.guest.name == 'Catering')
                  .length;
            }
          }
        }
        expect(crewServedGuests, 0);
        expect(others, 0);
      },
    );

    test('the rest of the team keep the restaurant going', () {
      final d = cafe(day: 3);
      d.takeContract(order(day: 3), {70});
      final sim = play(d, seed: 2);
      expect(sim.served, greaterThan(5));
      expect(
        sim.workers
            .where((w) => w.staff.id != 70)
            .any((w) => w.platesToday > 0),
        isTrue,
      );
    });

    test('when it is out the crew go back to work', () {
      final d = cafe(day: 3);
      final c = order(day: 3, lines: {Dish.burger: 4});
      d.takeContract(c, {70});
      final sim = DinerSim(d, seed: 2);
      final crew = sim.workers.firstWhere((w) => w.staff.id == 70);
      var out = 0;
      while (sim.cateringOpen && sim.ticks < 280) {
        sim.tick();
      }
      expect(sim.cateringState, ContractState.done);
      out = sim.ticks;
      expect(out, lessThan(Pace.dayTicks), reason: 'sent before closing');
      final made = crew.platesToday;
      while (!sim.finished && sim.ticks < 2000) {
        sim.tick();
      }
      expect(crew.platesToday, greaterThan(made), reason: 'serving again');
    });

    test('too big for the time: it is missed, and costs', () {
      final d = cafe(day: 3, cooks: 2);
      final c = order(day: 3, lines: {Dish.burger: 60}, reward: 500);
      d.takeContract(c, {70});
      final rating = d.progress.reputation;
      final sim = play(d, seed: 2);
      final r = sim.result!;
      expect(sim.cateringState, ContractState.missed);
      expect(r.cateringState, ContractState.missed);
      expect(r.cateringReward, 0);
      expect(sim.cateringPaid, 0);
      expect(sim.story.any((l) => l.text.contains('was not ready')), isTrue);
      // The rating drops by the two the miss costs, on top of the day's own.
      expect(r.reputation, lessThan(rating));
      expect(r.ingredients, greaterThanOrEqualTo(c.ingredients(d)));
    });

    test('a missed order is not carried into tomorrow', () {
      final d = cafe(day: 3, cooks: 2);
      d.takeContract(order(day: 3, lines: {Dish.burger: 60}), {70});
      play(d, seed: 2);
      expect(d.progress.day, 4);
      expect(d.takenContract, isNull);
      expect(d.contractState, ContractState.open);
    });

    test('the ingredients cannot be paid for: it is called off, free', () {
      final d = cafe(day: 3);
      final c = order(day: 3);
      d.takeContract(c, {70});
      d.coins = 2;
      final sim = DinerSim(d, seed: 2);
      sim.tick();
      expect(sim.cateringState, ContractState.voided);
      expect(sim.cateringOpen, isFalse);
      expect(sim.story.any((l) => l.text.contains('called off')), isTrue);
      final done = play(d, seed: 2).result!;
      expect(done.cateringState, ContractState.voided);
      // The same day with no order at all, and as little money.
      final bare = cafe(day: 3)..coins = 2;
      final same = play(bare, seed: 2).result!;
      expect(done.reputation, same.reputation, reason: 'no penalty');
    });

    test('a day with no order is as it was', () {
      final a = play(cafe(day: 3), seed: 2);
      final b = play(cafe(day: 3), seed: 2);
      expect(a.result!.served, b.result!.served);
      expect(a.contract, isNull);
      expect(a.result!.catering, isNull);
      expect(a.cateringOpen, isFalse);
    });

    test('the same order on the same day plays out the same', () {
      int run() {
        final d = cafe(day: 3);
        d.takeContract(order(day: 3), {70});
        return play(d, seed: 4).served;
      }

      expect(run(), run());
    });
  });

  group('closed for the day', () {
    test('nobody comes, and everyone works on it', () {
      final d = cafe(day: 3);
      final c = order(day: 3, lines: {Dish.burger: 12, Dish.fries: 8});
      d.takeContract(c, {70}, closed: true);
      final sim = DinerSim(d, seed: 2);
      var any = false;
      while (!sim.finished && sim.ticks < 400) {
        sim.tick();
        if (sim.guests.isNotEmpty) any = true;
      }
      expect(any, isFalse);
      expect(sim.served, 0);
      expect(sim.cateringState, ContractState.done);
      expect(sim.result!.closed, isTrue);
      expect(
        sim.workers.where((w) => w.platesToday > 0).length,
        greaterThan(1),
      );
    });

    test('the day ends as soon as the order is out', () {
      final d = cafe(day: 3);
      d.takeContract(order(day: 3, lines: {Dish.burger: 6}), {
        70,
      }, closed: true);
      final sim = play(d, seed: 2);
      expect(sim.ticks, lessThan(Pace.dayTicks));
      expect(sim.result!.cateringState, ContractState.done);
    });

    test('the rating is left alone, and the day counts as a fair one', () {
      final d = cafe(day: 3);
      d.takeContract(order(day: 3, lines: {Dish.burger: 6}), {
        70,
      }, closed: true);
      final rating = d.progress.reputation;
      final r = play(d, seed: 2).result!;
      expect(r.reputation, rating);
      expect(r.stars, 2);
      expect(r.walkouts, 0);
    });

    test('everyone is paid, and only the order brings money in', () {
      final d = cafe(day: 3);
      final c = order(day: 3, lines: {Dish.burger: 6}, reward: 260);
      d.takeContract(c, {70}, closed: true);
      final r = play(d, seed: 2).result!;
      expect(r.earned, 260);
      expect(r.wages, greaterThan(0));
    });

    test('too much for one day: it runs to closing and is missed', () {
      final d = cafe(day: 3, cooks: 1);
      d.takeContract(order(day: 3, lines: {Dish.burger: 80}), {
        70,
      }, closed: true);
      final rating = d.progress.reputation;
      final sim = play(d, seed: 2);
      expect(sim.result!.cateringState, ContractState.missed);
      expect(sim.ticks, greaterThanOrEqualTo(Pace.dayTicks));
      expect(sim.result!.reputation, rating - ContractBook.missedRating);
    });

    test('no stock is bought for customers who will not come', () {
      final d = cafe(day: 3);
      final c = order(day: 3, lines: {Dish.burger: 6});
      d.takeContract(c, {70}, closed: true);
      final r = play(d, seed: 2).result!;
      expect(r.ingredients, c.ingredients(d));
      expect(r.leftover, 0);
    });

    test('a quicker order with everyone than with one person', () {
      int finish(bool closed) {
        final d = cafe(day: 3);
        d.takeContract(
          order(day: 3, lines: {Dish.burger: 14, Dish.fries: 10}),
          {70},
          closed: closed,
        );
        final sim = DinerSim(d, seed: 2);
        while (sim.cateringOpen && sim.ticks < 600) {
          sim.tick();
        }
        return sim.ticks;
      }

      expect(finish(true), lessThan(finish(false)));
    });
  });

  group('the report', () {
    test('it counts toward what was kept, and the goal', () {
      final d = cafe(day: 3);
      d.takeContract(order(day: 3, lines: {Dish.burger: 6}), {
        70,
      }, closed: true);
      final r = play(d, seed: 2).result!;
      final met =
          (Diner.starter()
                ..goalsDone.addAll([
                  for (final g in goals)
                    if (g.id != 'catering') g.id,
                ]))
              .checkGoals(r)
              .map((g) => g.id);
      expect(met, contains('catering'));
      expect(d.history.last.kept, r.earned - r.ingredients - r.wages);
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

    Future<void> beat(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<void> reveal(WidgetTester tester, String key) async {
      await tester.scrollUntilVisible(find.byKey(ValueKey(key)), 200);
      await tester.pump();
    }

    testWidgets('a day with an offer shows a card, and one without does not', (
      tester,
    ) async {
      final yes = day(offer: true);
      await open(tester, cafe(day: yes));
      expect(find.byKey(const ValueKey('order-card')), findsOneWidget);
      expect(find.textContaining('Catering order from'), findsOneWidget);
    });

    testWidgets('no card on a quiet day', (tester) async {
      await open(tester, cafe(day: day(offer: false)));
      expect(find.byKey(const ValueKey('order-card')), findsNothing);
    });

    testWidgets('the card opens the order, with what it pays', (tester) async {
      final n = day(offer: true);
      final d = await open(tester, cafe(day: n));
      final c = d.offer!;
      await tester.tap(find.byKey(const ValueKey('order-card')));
      await beat(tester);
      expect(find.text('Catering order'), findsOneWidget);
      expect(find.text('Pays ${c.reward}'), findsOneWidget);
      for (final dish in c.lines.keys) {
        expect(find.byKey(ValueKey('line-${dish.name}')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('crew-70')), findsOneWidget);
    });

    testWidgets('taking it turns the card green, and the doors can be shut', (
      tester,
    ) async {
      final n = day(offer: true);
      final d = await open(tester, cafe(day: n));
      await tester.tap(find.byKey(const ValueKey('order-card')));
      await beat(tester);
      await reveal(tester, 'doors-shut');
      await tester.tap(find.byKey(const ValueKey('doors-shut')));
      await tester.pump();
      expect(find.text('Everyone is on it.'), findsOneWidget);
      await reveal(tester, 'take-order');
      await tester.tap(find.byKey(const ValueKey('take-order')));
      await beat(tester);
      expect(d.takenContract, isNotNull);
      expect(d.closedForOrder, isTrue);
      expect(find.textContaining('taken'), findsOneWidget);
      expect(find.text('Start catering day'), findsOneWidget);
    });

    testWidgets('someone has to be chosen, and it says so', (tester) async {
      final n = day(offer: true);
      final d = await open(tester, cafe(day: n));
      await tester.tap(find.byKey(const ValueKey('order-card')));
      await beat(tester);
      // Half the team is chosen to begin with: clear them.
      for (final id in d.roster.employees.map((s) => s.id).toList()) {
        await reveal(tester, 'crew-$id');
        final chosen = d.roster.employees.length;
        expect(chosen, 3);
      }
      for (final id in [70, 71]) {
        await tester.tap(find.byKey(ValueKey('crew-$id')));
        await tester.pump();
      }
      await reveal(tester, 'take-order');
      expect(find.byKey(const ValueKey('why-not')), findsOneWidget);
      expect(find.text('Choose who will cook it'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('take-order')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(d.takenContract, isNull);
    });

    testWidgets('Not today clears the card', (tester) async {
      final n = day(offer: true);
      final d = await open(tester, cafe(day: n));
      await tester.tap(find.byKey(const ValueKey('order-card')));
      await beat(tester);
      await reveal(tester, 'pass-order');
      await tester.tap(find.byKey(const ValueKey('pass-order')));
      await beat(tester);
      expect(d.contractState, ContractState.declined);
      expect(find.byKey(const ValueKey('order-card')), findsNothing);
    });

    testWidgets('Change my mind puts it back on offer', (tester) async {
      final n = day(offer: true);
      final d = await open(tester, cafe(day: n));
      d.takeContract(d.offer!, {70});
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('order-card')));
      await beat(tester);
      await reveal(tester, 'cancel-order');
      await tester.tap(find.byKey(const ValueKey('cancel-order')));
      await tester.pump();
      expect(d.contractState, ContractState.open);
      await reveal(tester, 'take-order');
      expect(find.byKey(const ValueKey('take-order')), findsOneWidget);
    });

    testWidgets('during the day it shows how many have gone out', (
      tester,
    ) async {
      final d = cafe(day: 3);
      await open(tester, d);
      d.takeContract(order(day: 3), {70});
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey('catering-progress')), findsOneWidget);
      expect(find.textContaining('Catering: 0 of 10 out'), findsOneWidget);
    });

    testWidgets('the end of the day says how the order went', (tester) async {
      final d = cafe(day: 3);
      await open(tester, d);
      d.takeContract(order(day: 3, lines: {Dish.burger: 4}), {
        70,
      }, closed: true);
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('speed-3')));
      await tester.pump();
      for (var i = 0; i < 900; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byKey(const ValueKey('next-day')).evaluate().isNotEmpty) break;
      }
      expect(find.byKey(const ValueKey('next-day')), findsOneWidget);
      expect(find.byKey(const ValueKey('catering-line')), findsOneWidget);
      expect(find.textContaining('Catering sent to'), findsOneWidget);
    });
  });
}
