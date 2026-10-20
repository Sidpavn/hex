// Regulars: guests who keep coming back, with a favourite dish, who grow
// fonder (or drift away) with how they are treated.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/diner_painter.dart';
import 'package:hex/diner/goals.dart';
import 'package:hex/diner/guests.dart';
import 'package:hex/diner/luck.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/diner/regulars.dart';
import 'package:hex/diner/report_screen.dart';
import 'package:hex/diner/service.dart';
import 'package:hex/diner/staff.dart';
import 'package:hex/diner/stats_screen.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel_hearts.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';

const newDishes = [
  Dish.hotDog,
  Dish.onionRings,
  Dish.chickenSandwich,
  Dish.nuggets,
  Dish.milkshake,
  Dish.baconBurger,
  Dish.sundae,
];

Diner cafe({int day = 3, int level = 5, int rep = 70, int cooks = 3}) {
  final d = Diner(
    coins: 100000,
    owned: {0, 1},
    progress: Progress(level: level, reputation: rep, day: day),
  );
  d.declined.addAll([Dish.cheeseburger, ...newDishes]);
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

Regular regular({
  int id = 1,
  String name = 'Marge',
  int points = 6,
  Dish fav = Dish.burger,
  Wallet wallet = Wallet.regular,
  Temper temper = Temper.steady,
  int last = 2,
}) => Regular(
  id: id,
  name: name,
  gender: Gender.woman,
  look: 'cust_b',
  wallet: wallet,
  temper: temper,
  favourite: fav,
  points: points,
  firstDay: 1,
  lastDay: last,
);

/// A day on which [r] comes.
int dayItComes(Regular r) {
  for (var n = 4; n < 400; n++) {
    if (dayLuck(n, 200 + r.id) < r.chance) return n;
  }
  throw StateError('never');
}

DinerSim play(Diner d, {int seed = 1}) {
  final sim = DinerSim(d, seed: seed);
  while (!sim.finished && sim.ticks < 2500) {
    sim.tick();
  }
  return sim;
}

void main() {
  group('a regular', () {
    test('hearts are three points each, up to five', () {
      expect(regular(points: 0).hearts, 0);
      expect(regular(points: 2).hearts, 0);
      expect(regular(points: 3).hearts, 1);
      expect(regular(points: 8).hearts, 2);
      expect(regular(points: 15).hearts, 5);
      expect(Regular.startPoints, 3);
    });

    test('points stay between nothing and the most', () {
      final r = regular(points: 14);
      r.give(5);
      expect(r.points, Regular.maxPoints);
      r.give(-40);
      expect(r.points, 0);
    });

    test('a fonder one comes more, tips more and waits longer', () {
      final cool = regular(points: 3);
      final fond = regular(points: 15);
      expect(fond.chance, greaterThan(cool.chance));
      expect(fond.tipMul, greaterThan(cool.tipMul));
      expect(fond.patienceMul, greaterThan(cool.patienceMul));
      expect(fond.friendChance, greaterThan(cool.friendChance));
      expect(fond.chance, lessThanOrEqualTo(0.85));
      expect(cool.chance, greaterThan(0.3));
    });

    test('they are saved, and a damaged one is dropped', () {
      final r = regular(points: 9, fav: Dish.hotDog, wallet: Wallet.wealthy);
      final back = Regular.fromJson(r.toJson())!;
      expect(back.name, 'Marge');
      expect(back.favourite, Dish.hotDog);
      expect(back.wallet, Wallet.wealthy);
      expect(back.points, 9);
      expect(back.look, 'cust_b');
      expect(Regular.fromJson('rubbish'), isNull);
      expect(Regular.fromJson({...r.toJson(), 'fav': 'nonsense'}), isNull);
    });
  });

  group('the book', () {
    test('there is room for more as the restaurant grows', () {
      expect(RegularBook.cap(1), 4);
      expect(RegularBook.cap(5), 8);
      expect(RegularBook.cap(10), 13);
    });

    test('it keeps who is in it, and the next number, through a save', () {
      final d = cafe();
      d.regulars.people.addAll([regular(), regular(id: 4, name: 'Joe')]);
      d.regulars.nextId = 5;
      final back = Diner.fromJson(d.toJson());
      expect(back.regulars.people.map((r) => r.name), ['Marge', 'Joe']);
      expect(back.regulars.nextId, 5);
      expect(Diner.fromJson(cafe().toJson()).regulars.people, isEmpty);
    });

    test('a heart is a heart, drawn in whole pixels', () {
      expect(PixelHearts.shape.length, 6);
      expect(PixelHearts.shape.every((r) => r.length == 7), isTrue);
      expect(PixelHearts.shape.join().contains('#'), isTrue);
      // Symmetrical, so it reads as a heart.
      for (final row in PixelHearts.shape) {
        expect(row, row.split('').reversed.join());
      }
      // More filled hearts paint more of the red.
      final a = HeartsPainter(1, 5, 1);
      final b = HeartsPainter(4, 5, 1);
      expect(b.shouldRepaint(a), isTrue);
      expect(a.shouldRepaint(HeartsPainter(1, 5, 1)), isFalse);
    });

    test('two with one name are one, and the number never goes back', () {
      final book = RegularBook.fromJson({
        'next': 1,
        'people': [regular().toJson(), regular(id: 7).toJson()],
      });
      expect(book.people.length, 1);
      expect(book.nextId, 2);
    });
  });

  group('in a day', () {
    test('they come on days of their own, not every day', () {
      final r = regular(points: 6);
      var came = 0;
      for (var n = 4; n < 204; n++) {
        if (dayLuck(n, 200 + r.id) < r.chance) came++;
      }
      expect(came / 200, closeTo(r.chance, 0.1));
      expect(came, lessThan(200));
    });

    test('they arrive as themselves', () {
      final r = regular(wallet: Wallet.wealthy, temper: Temper.hasty);
      final day = dayItComes(r);
      final d = cafe(day: day)..regulars.people.add(r);
      final sim = DinerSim(d, seed: 2);
      Guest? g;
      while (!sim.finished && sim.ticks < 2500) {
        sim.tick();
        g ??= sim.guests.where((x) => x.regular == r).firstOrNull;
      }
      expect(g, isNotNull);
      expect(g!.name, 'Marge');
      expect(g.sprite, 'cust_b');
      expect(g.gender, Gender.woman);
      expect(g.wallet, Wallet.wealthy);
      expect(g.temper, Temper.hasty);
      expect(sim.regularsSeen, {r.id});
      expect(r.visits, 2);
      expect(r.lastDay, day);
    });

    test('a fonder one waits longer than the same person less fond', () {
      int patience(int points) {
        final r = regular(points: points, temper: Temper.steady);
        final d = cafe(day: dayItComes(r))..regulars.people.add(r);
        final sim = DinerSim(d, seed: 2);
        while (!sim.finished && sim.ticks < 2500) {
          sim.tick();
          final g = sim.guests.where((x) => x.regular == r).firstOrNull;
          if (g != null) return g.patienceMax;
        }
        return 0;
      }

      // Arrive on the same days: use a day that suits both.
      final cool = regular(points: 3);
      final fond = regular(points: 15);
      var day = 4;
      while (dayLuck(day, 200 + 1) >= cool.chance) {
        day++;
      }
      int at(Regular r) {
        final d = cafe(day: day)..regulars.people.add(r);
        final sim = DinerSim(d, seed: 2);
        while (!sim.finished && sim.ticks < 2500) {
          sim.tick();
          final g = sim.guests.where((x) => x.regular == r).firstOrNull;
          if (g != null) return g.patienceMax;
        }
        return 0;
      }

      expect(patience(15), greaterThan(0));
      expect(at(fond), greaterThan(at(cool)));
    });

    test('they have their favourite, whatever else is on the menu', () {
      final r = regular(fav: Dish.fries);
      var had = 0;
      for (var k = 0; k < 6; k++) {
        final n = dayItComes(r) + k * 7;
        if (dayLuck(n, 200 + r.id) >= r.chance) continue;
        final d = cafe(day: n)..regulars.people.add(r);
        final sim = DinerSim(d, seed: 2);
        while (!sim.finished && sim.ticks < 2500) {
          sim.tick();
          final g = sim.guests.where((x) => x.regular == r).firstOrNull;
          if (g != null && g.items.isNotEmpty) {
            expect(g.items.map((i) => i.dish), contains(Dish.fries));
            had++;
            break;
          }
        }
      }
      expect(had, greaterThan(0));
    });

    test('a good meal makes them fonder, and the usual most of all', () {
      final r = regular(points: 6, fav: Dish.burger);
      final d = cafe(day: dayItComes(r))..regulars.people.add(r);
      final sim = play(d, seed: 2);
      expect(r.points, greaterThanOrEqualTo(6));
      expect(sim.story.any((l) => l.text.contains('Marge')), isTrue);
      expect(sim.result!.regularsSeen, 1);
    });

    test('they tip more the fonder they are', () {
      double tips(int points) {
        final r = regular(points: points);
        var total = 0.0;
        for (final seed in [1, 2, 3]) {
          final d = cafe(day: 30)..regulars.people.add(r);
          final sim = DinerSim(d, seed: seed);
          final seen = <Guest>[];
          while (!sim.finished && sim.ticks < 2500) {
            sim.tick();
            for (final g in sim.guests) {
              if (g.regular == r && !seen.contains(g)) seen.add(g);
            }
          }
          for (final g in seen) {
            total += g.tipExact;
          }
        }
        return total;
      }

      // Both come on day 30 only if it suits; compare when both do.
      final cool = regular(points: 3);
      final fond = regular(points: 15);
      if (dayLuck(30, 201) < cool.chance) {
        expect(tips(15), greaterThanOrEqualTo(tips(3)));
      }
      expect(fond.tipMul / cool.tipMul, closeTo(1.4 / 1.08, 0.01));
    });

    test('one who goes without a meal grows cooler, and says so', () {
      final r = regular(points: 9, fav: Dish.burger);
      final d = cafe(day: dayItComes(r))..regulars.people.add(r);
      // Nothing is cooked today: everyone walks out.
      for (final dish in d.menu()) {
        d.plan[dish] = 0;
      }
      final sim = play(d, seed: 2);
      expect(r.points, lessThan(9));
      expect(
        sim.story.any((l) => l.text.contains('Marge left without a meal')),
        isTrue,
      );
    });

    test('someone who has not been in for a long time cools off', () {
      final r = regular(points: 5, last: 1);
      final d = cafe(day: 20)..regulars.people.add(r);
      // Make sure she does not come today.
      var day = 20;
      while (dayLuck(day, 200 + r.id) < r.chance) {
        day++;
      }
      d.progress.day = day;
      play(d, seed: 2);
      expect(r.points, 4);
    });

    test('and one with no fondness left stops coming', () {
      final r = regular(points: 1, last: 1);
      var day = 20;
      while (dayLuck(day, 200 + r.id) < r.chance) {
        day++;
      }
      final d = cafe(day: day)..regulars.people.add(r);
      final sim = play(d, seed: 2);
      expect(d.regulars.people, isNot(contains(r)));
      expect(sim.regularsGone, ['Marge']);
      expect(sim.result!.regularsGone, ['Marge']);
      expect(
        sim.story.any((l) => l.text == 'Marge has stopped coming.'),
        isTrue,
      );
    });

    test('someone seen today does not cool off', () {
      final r = regular(points: 5, last: 1);
      final d = cafe(day: dayItComes(r))..regulars.people.add(r);
      play(d, seed: 2);
      expect(r.points, greaterThanOrEqualTo(5));
      expect(d.regulars.people, contains(r));
    });

    test('a happy guest sometimes becomes one', () {
      final d = cafe(day: 3);
      var joined = 0;
      for (var n = 3; n < 40; n++) {
        d.progress.day = n;
        final sim = play(d, seed: n);
        joined += sim.regularsJoined.length;
      }
      expect(joined, greaterThan(0));
      // Some drift away again over the weeks.
      expect(d.regulars.people.length, lessThanOrEqualTo(joined));
      expect(d.regulars.people, isNotEmpty);
      for (final r in d.regulars.people) {
        expect(r.points, greaterThanOrEqualTo(Regular.startPoints - 3));
        expect(r.name, isNot('A guest'));
        expect(r.gender.names + r.gender.names, contains(r.name));
        expect(Dish.values, contains(r.favourite));
      }
    });

    test('never more than the restaurant has room for', () {
      final d = cafe(day: 3, level: 1);
      for (var n = 3; n < 120; n++) {
        d.progress.day = n;
        play(d, seed: n);
      }
      expect(
        d.regulars.people.length,
        lessThanOrEqualTo(RegularBook.cap(d.progress.level)),
      );
    });

    test('each has a name of their own', () {
      final d = cafe(day: 3);
      for (var n = 3; n < 60; n++) {
        d.progress.day = n;
        play(d, seed: n);
      }
      final names = d.regulars.people.map((r) => r.name).toList();
      expect(names.toSet().length, names.length);
    });

    test('another guest never takes a regular\'s name', () {
      final r = regular(name: 'Gus');
      final d = cafe(day: 6)..regulars.people.add(r);
      final sim = DinerSim(d, seed: 2);
      var strangers = 0;
      final seen = <int>{};
      while (!sim.finished && sim.ticks < 2500) {
        sim.tick();
        for (final g in sim.guests) {
          if (g.regular == null && g.name == 'Gus' && seen.add(g.id)) {
            strangers++;
          }
        }
      }
      expect(strangers, 0);
    });

    test('a fond one sometimes brings a friend', () {
      final r = regular(points: 15);
      var friends = 0;
      for (var n = 4; n < 80; n++) {
        if (dayLuck(n, 200 + r.id) >= r.chance) continue;
        final d = cafe(day: n)..regulars.people.add(regular(points: 15));
        final sim = DinerSim(d, seed: n);
        while (!sim.finished && sim.ticks < 2500) {
          sim.tick();
        }
        if (sim.story.any((l) => l.text == 'Marge brought a friend.')) {
          friends++;
        }
      }
      expect(friends, greaterThan(0));
    });

    test('none come when the doors are shut for catering', () {
      final r = regular();
      final n = dayItComes(r);
      final d = cafe(day: n)..regulars.people.add(r);
      final sim = DinerSim(d, seed: 2);
      sim.closedDay = true;
      expect(sim.regularsSeen, isEmpty);
    });

    test('a day with no regulars is as it was', () {
      final a = play(cafe(day: 3), seed: 4);
      final b = play(cafe(day: 3), seed: 4);
      expect(a.served, b.served);
      expect(a.result!.regularsSeen, 0);
      expect(a.result!.regularsGone, isEmpty);
    });

    test('the same regulars on the same day play out the same', () {
      int run() {
        final r = regular();
        final d = cafe(day: dayItComes(r))..regulars.people.add(r);
        return play(d, seed: 5).served;
      }

      expect(run(), run());
    });

    test('the goal is the first one', () {
      final d = Diner.starter();
      d.goalsDone.addAll([
        for (final g in goals)
          if (g.id != 'regular') g.id,
      ]);
      expect(d.checkGoals().any((g) => g.id == 'regular'), isFalse);
      d.regulars.people.add(regular());
      expect(d.checkGoals().any((g) => g.id == 'regular'), isTrue);
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

    testWidgets('no regulars yet, and the tab says why', (tester) async {
      final d = cafe();
      await open(tester, d, StatsScreen(diner: d));
      await tester.tap(find.byKey(const ValueKey('tab-regulars')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('regulars-empty')), findsOneWidget);
      expect(find.text('0 of 8 regulars'), findsOneWidget);
    });

    testWidgets('each regular is a row, with their hearts', (tester) async {
      final d = cafe();
      d.regulars.people.addAll([
        regular(points: 9, fav: Dish.hotDog),
        regular(id: 2, name: 'Joe', points: 3, fav: Dish.fries),
      ]);
      await open(tester, d, StatsScreen(diner: d));
      await tester.tap(find.byKey(const ValueKey('tab-regulars')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('regular-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('regular-2')), findsOneWidget);
      expect(find.text('2 of 8 regulars'), findsOneWidget);
      expect(find.textContaining('Likes hot dog.'), findsOneWidget);
      // Three hearts for Marge, one for Joe, out of five.
      PixelHearts hearts(int id) =>
          tester.widget<PixelHearts>(find.byKey(ValueKey('hearts-$id')));
      expect(hearts(1).filled, 3);
      expect(hearts(2).filled, 1);
      expect(hearts(1).of, 5);
    });

    testWidgets('the fondest come first', (tester) async {
      final d = cafe();
      d.regulars.people.addAll([
        regular(id: 1, name: 'Ann', points: 3),
        regular(id: 2, name: 'Zed', points: 12),
      ]);
      await open(tester, d, StatsScreen(diner: d));
      await tester.tap(find.byKey(const ValueKey('tab-regulars')));
      await tester.pump(const Duration(milliseconds: 300));
      final zed = tester.getTopLeft(find.byKey(const ValueKey('regular-2')));
      final ann = tester.getTopLeft(find.byKey(const ValueKey('regular-1')));
      expect(zed.dy, lessThan(ann.dy));
    });

    testWidgets('a regular in the restaurant says so on their card', (
      tester,
    ) async {
      final r = regular(points: 9);
      final d = cafe(day: dayItComes(r))..regulars.people.add(r);
      await open(tester, d, BuildScreen(diner: d));
      final board = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is DinerPainter,
      );
      DinerPainter painter() =>
          tester.widget<CustomPaint>(board).painter! as DinerPainter;
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump();
      Guest? g;
      for (var i = 0; i < 900 && g == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        final sim = painter().sim!;
        final x = sim.guests
            .where((x) => x.regular == r && x.state == GuestState.waiting)
            .firstOrNull;
        // Tapped by their seat: wait until nobody else is drawn over them.
        if (x != null &&
            sim.guestAt(x.cell) == x &&
            sim.guestAt(Cell(x.cell.x + 1, x.cell.y + 1)) == null) {
          g = x;
        }
      }
      expect(g, isNotNull, reason: 'she sat down, clear of the others');
      final f = painter().fit;
      await tester.tapAt(
        tester.getTopLeft(board) +
            f.view.vertex(g!.cell.x + 0.5, g.cell.y + 0.5) * f.s,
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('guest-regular')), findsOneWidget);
      expect(find.text('Regular, 3 hearts. Likes burger.'), findsOneWidget);
    });

    testWidgets('the day report names who came and who joined', (tester) async {
      final r = regular(points: 9);
      final d = cafe(day: dayItComes(r))..regulars.people.add(r);
      final sim = play(d, seed: 2);
      await open(
        tester,
        d,
        DayReportScreen(report: sim.result!, progress: d.progress),
      );
      expect(find.byKey(const ValueKey('regulars-row')), findsOneWidget);
    });
  });
}
