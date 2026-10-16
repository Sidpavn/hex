// The vending machines out front: bought as an upgrade, earning from people
// walking by, less what they cost to stock.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/city.dart';
import 'package:hex/diner/contracts.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/diner_painter.dart';
import 'package:hex/diner/events.dart';
import 'package:hex/diner/goals.dart';
import 'package:hex/diner/luck.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/diner/report_screen.dart';
import 'package:hex/diner/service.dart';
import 'package:hex/diner/staff.dart';
import 'package:hex/diner/upgrade_screen.dart';
import 'package:hex/diner/vending.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';

Diner cafe({int machines = 0, int day = 3, int coins = 100000}) {
  final d = Diner(
    coins: coins,
    owned: {0, 1},
    progress: Progress(level: 5, reputation: 70, day: day),
  );
  d.progress.upgrades[Upgrade.vending] = machines;
  d.roster.employees.clear();
  d.progress.upgrades[Upgrade.staff] = 1;
  for (var i = 0; i < 2; i++) {
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

VendingDay run(
  int day, {
  int machines = 1,
  Vend product = Vend.drinks,
  double rating = 3.5,
  DayEvent event = DayEvent.none,
}) => Vending.run(
  day: day,
  machines: machines,
  product: product,
  rating: rating,
  event: event,
);

int brokenDay() {
  for (var d = 2; d < 600; d++) {
    if (run(d).broken) return d;
  }
  throw StateError('none');
}

int workingDay() {
  for (var d = 2; d < 600; d++) {
    if (!run(d).broken) return d;
  }
  throw StateError('none');
}

DinerSim play(Diner d, {int seed = 1}) {
  final sim = DinerSim(d, seed: seed);
  while (!sim.finished && sim.ticks < 2500) {
    sim.tick();
  }
  return sim;
}

void main() {
  group('what they sell', () {
    test('three things, each with a price, a cost and a following', () {
      expect(Vend.values.length, 3);
      for (final v in Vend.values) {
        expect(v.price, greaterThan(v.cost), reason: v.label);
        expect(v.appeal, inInclusiveRange(0.05, 0.25));
        expect(v.blurb, endsWith('.'));
      }
    });

    test('ice cream hates the rain and loves a festival', () {
      expect(Vend.iceCream.weather(DayEvent.rain), lessThan(0.5));
      expect(Vend.iceCream.weather(DayEvent.festival), greaterThan(1));
      expect(Vend.drinks.weather(DayEvent.rain), greaterThan(0.7));
      expect(Vend.snacks.weather(DayEvent.rain), 1);
      expect(Vend.drinks.weather(DayEvent.none), 1);
    });
  });

  group('a day at the machines', () {
    test('none out front, nothing happens', () {
      final d = run(5, machines: 0);
      expect((d.sold, d.income, d.restock, d.repair), (0, 0, 0, 0));
      expect(d.broken, isFalse);
    });

    test('what is sold is paid at the price, and the stock is paid for', () {
      final n = workingDay();
      final d = run(n);
      expect(d.sold, greaterThan(0));
      expect(d.sold, lessThanOrEqualTo(Vending.stockPerMachine));
      expect(d.income, d.sold * Vend.drinks.price);
      expect(d.restock, Vending.stockPerMachine * Vend.drinks.cost);
      expect(d.net, d.income - d.restock);
    });

    test('about one day in fourteen it breaks, and sells nothing', () {
      var broke = 0;
      for (var n = 2; n < 1002; n++) {
        final d = run(n);
        if (!d.broken) continue;
        broke++;
        expect(d.sold, 0);
        expect(d.income, 0);
        expect(d.restock, 0);
        expect(d.repair, Vending.repairCost);
        expect(d.net, -Vending.repairCost);
      }
      expect(broke / 1000, inInclusiveRange(0.04, 0.11));
    });

    test('it never sells more than it holds', () {
      for (var n = 2; n < 300; n++) {
        for (final v in Vend.values) {
          final d = run(n, product: v, rating: 5, event: DayEvent.festival);
          expect(d.sold, lessThanOrEqualTo(Vending.stockPerMachine));
        }
      }
    });

    test('a second machine sells more, but not twice as much', () {
      var one = 0;
      var two = 0;
      for (var n = 2; n < 200; n++) {
        if (run(n).broken) continue;
        one += run(n).sold;
        two += run(n, machines: 2).sold;
      }
      expect(two, greaterThan(one));
      expect(two, lessThan(one * 2));
    });

    test('a better rating brings more people by', () {
      var low = 0.0;
      var high = 0.0;
      for (var n = 2; n < 200; n++) {
        low += Vending.walkers(n, 2.0, DayEvent.none);
        high += Vending.walkers(n, 4.5, DayEvent.none);
      }
      expect(high, greaterThan(low * 1.1));
    });

    test('rain keeps people in, and a festival brings them out', () {
      final n = workingDay();
      expect(
        Vending.walkers(n, 3.5, DayEvent.rain),
        lessThan(Vending.walkers(n, 3.5, DayEvent.none)),
      );
      expect(
        Vending.walkers(n, 3.5, DayEvent.festival),
        greaterThan(Vending.walkers(n, 3.5, DayEvent.none)),
      );
    });

    test('ice cream earns little in the rain, and much on a festival day', () {
      var rain = 0;
      var fete = 0;
      var plain = 0;
      for (var n = 2; n < 100; n++) {
        if (run(n).broken) continue;
        rain += run(n, product: Vend.iceCream, event: DayEvent.rain).net;
        fete += run(n, product: Vend.iceCream, event: DayEvent.festival).net;
        plain += run(n, product: Vend.iceCream).net;
      }
      expect(rain, lessThan(plain ~/ 2));
      expect(fete, greaterThan(plain));
    });

    test('drinks are steadier than ice cream', () {
      double spread(Vend v) {
        final nets = <int>[];
        for (var n = 2; n < 300; n++) {
          final e = DayEvent.forDay(n, 5);
          final d = run(n, product: v, event: e);
          if (!d.broken) nets.add(d.net);
        }
        final mean = nets.reduce((a, b) => a + b) / nets.length;
        return nets.map((x) => (x - mean).abs()).reduce((a, b) => a + b) /
            nets.length;
      }

      expect(spread(Vend.drinks), lessThan(spread(Vend.iceCream)));
    });

    test('it is the same each time for a day', () {
      final a = run(17, machines: 2, product: Vend.snacks);
      final b = run(17, machines: 2, product: Vend.snacks);
      expect((a.sold, a.net, a.broken), (b.sold, b.net, b.broken));
    });

    test('days are not all alike', () {
      final sold = {for (var n = 2; n < 60; n++) run(n).sold};
      expect(sold.length, greaterThan(4));
    });

    test(
      'a usual day is worth having, but is a small share of the takings',
      () {
        for (final v in Vend.values) {
          final f = Vending.forecast(machines: 1, product: v, rating: 3.5);
          expect(f.net, inInclusiveRange(10, 60), reason: v.label);
          final two = Vending.forecast(machines: 2, product: v, rating: 3.5);
          expect(two.net, greaterThan(f.net), reason: v.label);
        }
      },
    );
  });

  group('the upgrade', () {
    test('it has two levels, dearer the second time', () {
      final def = upgradeDefs[Upgrade.vending]!;
      expect(def.name, 'Vending machine');
      expect(def.max, 2);
      final p = Progress();
      expect(p.upgradeCost(Upgrade.vending), 150);
      p.upgrades[Upgrade.vending] = 1;
      expect(p.upgradeCost(Upgrade.vending), 300);
      p.upgrades[Upgrade.vending] = 2;
      expect(p.upgradeCost(Upgrade.vending), isNull);
    });

    test('it can be switched off, and that is saved', () {
      final d = cafe(machines: 2);
      expect(d.vendingOn, isTrue);
      expect(d.vendingActive, 2);
      d.vendingOn = false;
      expect(d.vendingActive, 0);
      expect(d.vendingMachines, 2, reason: 'still owned');
      expect(Diner.fromJson(d.toJson()).vendingOn, isFalse);
      expect(Diner.fromJson(cafe().toJson()).vendingOn, isTrue);
    });

    test('what it sells is saved', () {
      final d = cafe(machines: 1)..vend = Vend.iceCream;
      expect(Diner.fromJson(d.toJson()).vend, Vend.iceCream);
      expect(Diner.fromJson(cafe().toJson()).vend, Vend.drinks);
      final j = cafe().toJson()..['vend'] = 'nonsense';
      expect(Diner.fromJson(j).vend, Vend.drinks);
    });
  });

  group('the machines on the street', () {
    test('one beside the door, two spaced along the kerb', () {
      expect(streetProps(cafe()).where((p) => p.$1 == 'vending'), isEmpty);
      final one = streetProps(
        cafe(machines: 1),
      ).where((p) => p.$1 == 'vending');
      expect(one.length, 1);
      final d = cafe(machines: 2);
      final two = streetProps(d).where((p) => p.$1 == 'vending').toList();
      expect(two.length, 2);
      expect(two[0].$2.x, d.entrance.x + 2);
      expect(two[1].$2.x, d.entrance.x + 4);
      expect(two[0].$2.y, d.bottom + 2, reason: 'on the kerb, not the queue');
    });

    test('switched off they are drawn grey', () {
      final d = cafe(machines: 2)..vendingOn = false;
      final names = streetProps(
        d,
      ).map((p) => p.$1).where((n) => n.startsWith('vending'));
      expect(names, ['vending_off', 'vending_off']);
      d.vendingOn = true;
      expect(
        streetProps(d).map((p) => p.$1).where((n) => n.startsWith('vending')),
        ['vending', 'vending'],
      );
    });

    test('they are drawn', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final art = await DinerArt.load();
      expect(art.sprite('vending').blank, isFalse);
      expect(art.sprite('vending_off').blank, isFalse);
    });
  });

  group('in a day', () {
    test('no machines, and the books are as they were', () {
      final r = play(cafe(day: 3), seed: 2).result!;
      expect(r.vending, isNull);
    });

    test('the takings go in the till, less the stock', () {
      final n = workingDay();
      final d = cafe(machines: 1, day: n);
      final base = cafe(day: n);
      final sim = play(d, seed: 2);
      final plain = play(base, seed: 2);
      final v = sim.result!.vending!;
      expect(v.sold, greaterThan(0));
      // Everything else is the same day: what the machine made is the
      // difference in the till.
      expect(d.coins - base.coins, v.net);
      expect(sim.result!.earned - plain.result!.earned, v.income);
      expect(
        sim.result!.ingredients - plain.result!.ingredients,
        v.restock + v.repair,
      );
    });

    test('the day tells how it went', () {
      final n = workingDay();
      final sim = play(cafe(machines: 1, day: n), seed: 2);
      final line = sim.story.firstWhere(
        (l) => l.text.startsWith('The vending machine sold'),
      );
      expect(line.text, contains('cold drinks'));
    });

    test('a breakdown costs the repair, and says so', () {
      final n = brokenDay();
      final d = cafe(machines: 1, day: n);
      final base = cafe(day: n);
      final sim = play(d, seed: 2);
      play(base, seed: 2);
      expect(sim.result!.vending!.broken, isTrue);
      expect(d.coins - base.coins, -Vending.repairCost);
      expect(
        sim.story.any(
          (l) => l.text.startsWith('The vending machine broke down'),
        ),
        isTrue,
      );
    });

    test('switched off, it costs nothing and earns nothing', () {
      final n = workingDay();
      final d = cafe(machines: 2, day: n)..vendingOn = false;
      final base = cafe(day: n);
      final sim = play(d, seed: 2);
      play(base, seed: 2);
      expect(sim.result!.vending, isNull);
      expect(d.coins, base.coins);
      expect(sim.story.any((l) => l.text.contains('vending')), isFalse);
    });

    test('even a day it would have broken down costs nothing when off', () {
      final n = brokenDay();
      final d = cafe(machines: 1, day: n)..vendingOn = false;
      final base = cafe(day: n);
      play(d, seed: 2);
      play(base, seed: 2);
      expect(d.coins, base.coins);
    });

    test('it earns with the doors shut too', () {
      final n = workingDay();
      final d = cafe(machines: 1, day: n);
      d.takeContract(
        Contract(day: n, client: 'a', lines: {Dish.burger: 4}, reward: 100),
        {70},
        closed: true,
      );
      final r = play(d, seed: 2).result!;
      expect(r.closed, isTrue);
      expect(r.vending!.sold, greaterThan(0));
    });

    test('what it makes helps pay the wages', () {
      final n = workingDay();
      final d = cafe(machines: 2, day: n, coins: 0);
      final sim = DinerSim(d, seed: 2);
      // No customers and no money: only the machines have anything.
      sim.finishDay();
      expect(sim.result!.vending!.income, greaterThan(0));
      expect(sim.result!.wages, greaterThan(0));
    });

    test('the same machines on the same day give the same result', () {
      int net() =>
          play(cafe(machines: 1, day: 9), seed: 3).result!.vending!.net;
      expect(net(), net());
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

    testWidgets('Upgrades only sells the machine: no chooser there', (
      tester,
    ) async {
      final d = cafe(machines: 1);
      await open(tester, d, UpgradeScreen(diner: d));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('buy-vending')),
        200,
      );
      expect(find.text('Vending machine'), findsOneWidget);
      expect(
        find.textContaining('Tap it to choose what it sells'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('vending-panel')), findsNothing);
      expect(find.byKey(const ValueKey('vend-drinks')), findsNothing);
    });

    testWidgets('buying one adds it to the street', (tester) async {
      final d = cafe();
      await open(tester, d, UpgradeScreen(diner: d));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('buy-vending')),
        200,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('buy-vending')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('buy-vending')));
      await tester.pump();
      expect(d.vendingMachines, 1);
      expect(streetProps(d).any((p) => p.$1 == 'vending'), isTrue);
    });

    /// Taps the middle of the first vending machine on the street.
    Future<void> tapMachine(WidgetTester tester, Diner d, {int up = 0}) async {
      final paint = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .firstWhere((w) => w.painter is DinerPainter);
      final painter = paint.painter! as DinerPainter;
      final at = streetProps(
        d,
      ).firstWhere((p) => p.$1.startsWith('vending')).$2;
      final v =
          painter.fit.view.vertex(at.x + 0.5 - up, at.y + 0.5 - up) *
          painter.fit.s;
      await tester.tapAt(tester.getTopLeft(find.byWidget(paint)) + v);
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('tapping a machine opens what it sells', (tester) async {
      final d = cafe(machines: 1);
      await open(tester, d, BuildScreen(diner: d));
      await tapMachine(tester, d);
      expect(find.byKey(const ValueKey('vending-dialog')), findsOneWidget);
      expect(find.text('Vending machine'), findsOneWidget);
      for (final v in Vend.values) {
        expect(find.byKey(ValueKey('vend-${v.name}')), findsOneWidget);
      }
      final f = Vending.forecast(
        machines: 1,
        product: Vend.drinks,
        rating: d.progress.rating,
      );
      expect(
        find.textContaining('about ${f.sold} sold at 3 each'),
        findsOneWidget,
      );
    });

    testWidgets('and so does a tap on the upper part of it', (tester) async {
      final d = cafe(machines: 1);
      await open(tester, d, BuildScreen(diner: d));
      await tapMachine(tester, d, up: 2);
      expect(find.byKey(const ValueKey('vending-dialog')), findsOneWidget);
    });

    testWidgets('two machines share the one setting', (tester) async {
      final d = cafe(machines: 2);
      await open(tester, d, BuildScreen(diner: d));
      await tapMachine(tester, d);
      expect(find.text('Vending machines'), findsOneWidget);
    });

    testWidgets('choosing what to sell changes the forecast', (tester) async {
      final d = cafe(machines: 1);
      await open(tester, d, BuildScreen(diner: d));
      await tapMachine(tester, d);
      await tester.tap(find.byKey(const ValueKey('vend-iceCream')));
      await tester.pump();
      expect(d.vend, Vend.iceCream);
      expect(find.text(Vend.iceCream.blurb), findsOneWidget);
      expect(find.textContaining('at 5 each'), findsOneWidget);
    });

    testWidgets('it can be switched off, and on again', (tester) async {
      final d = cafe(machines: 1);
      await open(tester, d, BuildScreen(diner: d));
      await tapMachine(tester, d);
      expect(find.text('Switch off'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('vend-power')));
      await tester.pump();
      expect(d.vendingOn, isFalse);
      expect(find.text('Off'), findsOneWidget);
      expect(find.text('Switch on'), findsOneWidget);
      expect(
        find.textContaining('Switched off. Nothing is stocked'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('vend-power')));
      await tester.pump();
      expect(d.vendingOn, isTrue);
      expect(find.text('On'), findsOneWidget);
    });

    testWidgets(
      'closing it goes back to the street, and the machine shows it',
      (tester) async {
        final d = cafe(machines: 1);
        await open(tester, d, BuildScreen(diner: d));
        await tapMachine(tester, d);
        await tester.tap(find.byKey(const ValueKey('vend-power')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('vend-close')));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byKey(const ValueKey('vending-dialog')), findsNothing);
        expect(streetProps(d).any((p) => p.$1 == 'vending_off'), isTrue);
      },
    );

    testWidgets('a street with no machine opens nothing', (tester) async {
      final d = cafe();
      await open(tester, d, BuildScreen(diner: d));
      final paint = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .firstWhere((w) => w.painter is DinerPainter);
      final painter = paint.painter! as DinerPainter;
      final c = d.entrance;
      final v = painter.fit.view.vertex(c.x + 2.5, c.y + 3.5) * painter.fit.s;
      await tester.tapAt(tester.getTopLeft(find.byWidget(paint)) + v);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('vending-dialog')), findsNothing);
    });

    testWidgets('during a day it stays shut', (tester) async {
      final d = cafe(machines: 1);
      await open(tester, d, BuildScreen(diner: d));
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump(const Duration(milliseconds: 600));
      await tapMachine(tester, d);
      expect(find.byKey(const ValueKey('vending-dialog')), findsNothing);
    });

    testWidgets('the day report has a line for it', (tester) async {
      final n = workingDay();
      final d = cafe(machines: 1, day: n);
      final r = play(d, seed: 2).result!;
      await open(tester, d, DayReportScreen(report: r, progress: d.progress));
      expect(find.byKey(const ValueKey('vending-row')), findsOneWidget);
    });

    testWidgets('the street has a machine, drawn beside the door', (
      tester,
    ) async {
      final d = cafe(machines: 1);
      await open(tester, d, BuildScreen(diner: d));
      expect(find.byKey(const ValueKey('start-day')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  test('the goal is met by buying one', () {
    final d = Diner.starter();
    d.goalsDone.addAll([
      for (final g in goals)
        if (g.id != 'vending') g.id,
    ]);
    expect(d.checkGoals().any((g) => g.id == 'vending'), isFalse);
    d.progress.upgrades[Upgrade.vending] = 1;
    expect(d.checkGoals().any((g) => g.id == 'vending'), isTrue);
  });

  test('the luck for breakdowns is its own, not the events', () {
    // A day's breakdown does not follow from its event or its walkers.
    final days = [
      for (var n = 2; n < 400; n++)
        if (dayLuck(n, 61) < 0.07) n,
    ];
    final events = {for (final n in days) DayEvent.forDay(n, 5)};
    expect(events.length, greaterThan(2));
  });
}
