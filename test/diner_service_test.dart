import 'package:flutter_test/flutter_test.dart';
import 'package:hex/diner/city.dart';
import 'package:hex/diner/clock.dart';
import 'package:hex/diner/nav.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/diner/service.dart';
import 'package:hex/diner/staff.dart';

const _l = Diner.left;
const _t = Diner.top;

/// A room with a back wall of machines and tables of two seats each:
/// [tables] of them, one or two grills and counters.
Diner roomWith({
  int tables = 3,
  int grills = 1,
  int counters = 2,
  int level = 1,
  int rep = 70,
}) {
  final d = Diner(
    coins: 100000,
    owned: {0, 1},
    progress: Progress(level: level, reputation: rep),
  );
  void ok(PlaceResult r) => expect(r, PlaceResult.ok);
  ok(d.place(Kind.grill, const Cell(_l, _t), Dir.sw));
  if (grills > 1) ok(d.place(Kind.grill, const Cell(_l + 1, _t), Dir.sw));
  ok(d.place(Kind.counter, const Cell(_l + 6, _t), Dir.sw));
  if (counters > 1) ok(d.place(Kind.counter, const Cell(_l + 7, _t), Dir.sw));
  const spots = [Cell(3, 5), Cell(6, 5), Cell(6, 7), Cell(9, 5), Cell(9, 7)];
  for (var i = 0; i < tables; i++) {
    final t = spots[i];
    ok(d.place(Kind.table, t));
    ok(d.place(Kind.chair, Cell(t.x - 1, t.y), Dir.se));
    ok(d.place(Kind.chair, Cell(t.x + 1, t.y), Dir.nw));
  }
  return d;
}

/// Adds a member of staff with the given stats (3 where not given).
Staff addStaff(
  Diner d, {
  int cooking = 3,
  int speed = 5,
  int service = 3,
  int charm = 3,
  String name = 'Extra',
}) {
  final stats = {
    Stat.cooking: cooking,
    Stat.speed: speed,
    Stat.service: service,
    Stat.charm: charm,
  };
  final s = Staff(
    id: 50 + d.roster.employees.length,
    name: name,
    stats: stats,
    potential: {for (final e in stats.entries) e.key: 10},
  );
  d.roster.employees.add(s);
  return s;
}

/// The starting diner, but already known around town.
Diner starterAt(int rep) => Diner.starter()..progress.reputation = rep;

DinerSim play(Diner d, {int seed = 1}) {
  final sim = DinerSim(d, seed: seed);
  while (!sim.finished && sim.ticks < 2000) {
    sim.tick();
  }
  return sim;
}

void main() {
  group('a day', () {
    test('guests arrive, order, are served and pay', () {
      final d = starterAt(50);
      final before = d.coins;
      final sim = play(d);
      expect(sim.finished, isTrue);
      expect(sim.served, greaterThan(8));
      expect(
        d.coins,
        before + sim.earned - sim.result!.wages - sim.result!.ingredients,
      );
      expect(sim.result!.wages, 11, reason: 'Sam, paid at day end');
      expect(sim.earned, greaterThanOrEqualTo(sim.served * 8));
    });

    test('it ends after closing, with nobody left inside', () {
      final sim = play(Diner.starter());
      expect(sim.ticks, lessThanOrEqualTo(Pace.dayTicks + Pace.lastCall));
      expect(sim.guests, isEmpty);
      expect(sim.result, isNotNull);
    });

    test('doors shut at closing time: no new arrivals after it', () {
      final sim = DinerSim(Diner.starter());
      while (sim.open) {
        sim.tick();
      }
      final seen = <int>{for (final g in sim.guests) g.id};
      while (!sim.finished) {
        sim.tick();
        for (final g in sim.guests) {
          expect(seen.contains(g.id), isTrue, reason: 'guest ${g.id} is new');
        }
      }
    });

    test('same seed, same day', () {
      final a = play(Diner.starter(), seed: 5);
      final b = play(Diner.starter(), seed: 5);
      expect(a.served, b.served);
      expect(a.walkouts, b.walkouts);
      expect(a.earned, b.earned);
    });

    test('a closed diner gets no guests', () {
      final d = Diner(coins: 100)..place(Kind.grill, const Cell(_l, _t));
      final sim = play(d);
      expect(sim.served, 0);
      expect(sim.result!.stars, 0);
    });

    test('finishing the day moves the calendar on and pays out experience', () {
      final d = Diner.starter();
      final sim = play(d);
      expect(d.progress.day, 2);
      expect(sim.result!.day, 1);
      expect(sim.result!.xp, sim.xp);
      expect(sim.xp, greaterThan(0));
      expect(
        d.progress.xp + (d.progress.level - 1) * 0,
        lessThanOrEqualTo(d.progress.xpToNext),
      );
      // Asking again does not count the day twice.
      sim.finishDay();
      expect(d.progress.day, 2);
    });

    test('nobody ever stands inside a fixture', () {
      final d = roomWith(tables: 3);
      final sim = DinerSim(d);
      while (!sim.finished) {
        sim.tick();
        for (final p in [...sim.workers, ...sim.guests]) {
          // Guests may be on a seat (sitting, or just getting up).
          final onSeat = p is Guest && sim.seats.any((s) => s.cell == p.cell);
          final ok = d.walkable(p.cell) || d.isSidewalk(p.cell) || onSeat;
          expect(ok, isTrue, reason: 'tick ${sim.ticks}: ${p.cell}');
        }
      }
    });
  });

  group('orders', () {
    test('every guest orders something the kitchen can make', () {
      final d = roomWith(level: 3)
        ..place(Kind.fryer, const Cell(_l + 2, _t), Dir.sw)
        ..place(Kind.soda, const Cell(_l + 3, _t), Dir.sw);
      d.declined.add(Dish.cheeseburger);
      final sim = DinerSim(d);
      final seen = <Dish>{};
      while (!sim.finished) {
        sim.tick();
        for (final g in sim.guests) {
          for (final i in g.items) {
            seen.add(i.dish);
            expect(sim.menu, contains(i.dish));
          }
        }
      }
      expect(seen, containsAll([Dish.burger, Dish.fries, Dish.soda]));
    });

    test('with only a grill, everyone wants a burger', () {
      final sim = DinerSim(Diner.starter());
      final seen = <Dish>{};
      while (!sim.finished) {
        sim.tick();
        for (final g in sim.guests) {
          seen.addAll(g.items.map((i) => i.dish));
        }
      }
      expect(seen, {Dish.burger});
    });

    test('a machine cooks for as long as the recipe and upgrades say', () {
      final d = Diner.starter();
      d.progress.upgrades[Upgrade.kitchen] = 3;
      d.progress.recipeLevel[Dish.burger] = 2;
      final sim = DinerSim(d);
      int? seen;
      while (seen == null && sim.ticks < 200) {
        sim.tick();
        final m = sim.machines.first;
        if (m.item != null && !m.ready) seen = m.total;
      }
      expect(seen, d.progress.cookTicks(Dish.burger));
      expect(seen, lessThan(recipes[Dish.burger]!.cook));
    });

    test('a better recipe sells for more', () {
      final p = Progress();
      final base = p.price(Dish.burger);
      p.recipeLevel[Dish.burger] = 3;
      expect(p.price(Dish.burger), greaterThan(base));
    });
  });

  group('patience', () {
    test('guests lose patience while they wait, and leave angry at none', () {
      // A kitchen that cannot keep up: eight seats, one grill, one worker.
      final sim = play(roomWith(tables: 4));
      expect(sim.walkouts, greaterThan(10));
      expect(sim.result!.walkouts, sim.walkouts);
    });

    test('an angry guest pays nothing and gives up their seat', () {
      final d = roomWith(tables: 3);
      final sim = DinerSim(d);
      final paid = <int>{};
      var wasAngry = 0;
      while (!sim.finished) {
        sim.tick();
        for (final g in sim.guests.where((g) => g.angry)) {
          wasAngry++;
          expect(g.state, GuestState.leaving);
          expect(g.counter, isNull);
        }
        paid.add(sim.served);
      }
      expect(wasAngry, greaterThan(0));
      // Only guests who were served and paid are counted as served.
      expect(sim.earned, greaterThanOrEqualTo(sim.served * 8));
    });

    test('a meter reports how much patience is left', () {
      final sim = DinerSim(Diner.starter());
      while (!sim.guests.any((g) => g.state == GuestState.waiting)) {
        sim.tick();
      }
      final g = sim.guests.firstWhere((g) => g.state == GuestState.waiting);
      final before = g.mood;
      expect(before, closeTo(1, 0.1));
      for (var i = 0; i < 6 && g.state == GuestState.waiting; i++) {
        sim.tick();
      }
      expect(g.mood, lessThan(before));
      final meters = sim.actors(0).where((a) => a.meter != null);
      expect(meters, isNotEmpty);
    });

    test('cosy seating makes guests wait longer', () {
      final d = Diner.starter();
      final base = d.progress.patience;
      d.progress.upgrades[Upgrade.cosy] = 4;
      expect(d.progress.patience, greaterThan(base));
    });

    test('quick service earns tips', () {
      final sim = play(Diner.starter());
      expect(sim.tips, greaterThan(0));
      expect(sim.tips, lessThan(sim.earned));
    });
  });

  group('the challenge', () {
    test('a crowd bigger than the diner can feed sends people away', () {
      final quiet = play(starterAt(10));
      final famous = play(starterAt(90));
      expect(quiet.walkouts, 0);
      expect(famous.walkouts, greaterThan(8));
      expect(famous.result!.stars, lessThan(quiet.result!.stars));
    });

    test('seats beyond what the kitchen can feed do not help', () {
      final four = play(roomWith(tables: 2, rep: 90));
      final eight = play(roomWith(tables: 4, rep: 90));
      // Twice the seats, one grill and one worker: barely more served.
      expect(eight.served, lessThan(four.served * 1.25));
    });

    test('a few more seats do earn more, up to what the kitchen can do', () {
      var two = 0;
      var four = 0;
      for (final seed in [1, 2, 3, 4]) {
        // A kitchen that can feed more than one table's worth.
        Diner kitchen(int tables) {
          final d = roomWith(tables: tables, grills: 2);
          addStaff(d, cooking: 4, speed: 5, service: 4);
          d.progress.upgrades[Upgrade.staff] = 1;
          return d;
        }

        two += play(kitchen(1), seed: seed).served;
        four += play(kitchen(3), seed: seed).served;
      }
      expect(four, greaterThan(two));
    });

    test('a second grill and a waiter cope with the crowd', () {
      final overloaded = play(roomWith(tables: 4));
      final d = roomWith(tables: 4, grills: 2);
      addStaff(d, cooking: 4, speed: 5, service: 4);
      final helped = play(d);
      expect(helped.workers.length, 2);
      expect(helped.served, greaterThan(overloaded.served * 1.3));
      expect(helped.walkouts, lessThan(overloaded.walkouts));
    });

    test('a bigger tray carries more dishes at a time', () {
      final d = roomWith(tables: 3, grills: 2);
      d.progress.upgrades[Upgrade.tray] = 1;
      final sim = DinerSim(d);
      var most = 0;
      while (!sim.finished) {
        sim.tick();
        for (final w in sim.workers) {
          if (w.carrying.length > most) most = w.carrying.length;
        }
      }
      // With the default tray nobody carries more than three.
      final plain = DinerSim(roomWith(tables: 3, grills: 2));
      var plainMost = 0;
      while (!plain.finished) {
        plain.tick();
        for (final w in plain.workers) {
          if (w.carrying.length > plainMost) plainMost = w.carrying.length;
        }
      }
      expect(plainMost, lessThanOrEqualTo(3));
      expect(most, greaterThan(plainMost));
      expect(most, lessThanOrEqualTo(5));
    });

    test('the layout matters: a grill near the tables beats one far away', () {
      final near = Diner(
        coins: 100000,
        owned: {0, 1},
        progress: Progress(reputation: 70),
      );
      near.place(Kind.grill, const Cell(_l + 3, _t + 1), Dir.nw);
      near.place(Kind.counter, const Cell(_l + 6, _t), Dir.sw);
      final far = Diner(
        coins: 100000,
        owned: {0, 1},
        progress: Progress(reputation: 70),
      );
      far.place(Kind.grill, const Cell(_l, _t), Dir.sw);
      far.place(Kind.counter, const Cell(_l + 6, _t), Dir.sw);
      for (final d in [near, far]) {
        for (final t in const [Cell(6, 5), Cell(6, 7)]) {
          d.place(Kind.table, t);
          d.place(Kind.chair, Cell(t.x - 1, t.y), Dir.se);
          d.place(Kind.chair, Cell(t.x + 1, t.y), Dir.nw);
        }
      }
      expect(near.report().ready, isTrue);
      expect(far.report().ready, isTrue);
      expect(play(near).served, greaterThanOrEqualTo(play(far).served));
    });

    test('a queue forms on the pavement and never overflows', () {
      final d = Diner.starter();
      d.progress.reputation = 100;
      final sim = DinerSim(d);
      var longest = 0;
      while (!sim.finished) {
        sim.tick();
        final waiting = sim.guests.where((g) => g.inQueue).length;
        if (waiting > longest) longest = waiting;
        expect(waiting, lessThanOrEqualTo(d.queueLength));
      }
      expect(longest, greaterThan(0));
    });

    test('two counters take payment faster than one', () {
      final one = roomWith(tables: 3, counters: 1);
      final two = roomWith(tables: 3, counters: 2);
      var most1 = 0;
      var most2 = 0;
      for (final (d, set) in [(one, 1), (two, 2)]) {
        final sim = DinerSim(d);
        var line = 0;
        while (!sim.finished) {
          sim.tick();
          final n = sim.counters.fold<int>(0, (a, c) => a + c.line.length);
          if (n > line) line = n;
        }
        if (set == 1) most1 = line;
        if (set == 2) most2 = line;
      }
      expect(most1, greaterThanOrEqualTo(most2));
    });

    test('counters take one guest at a time', () {
      final d = roomWith(tables: 3, counters: 1);
      final sim = DinerSim(d);
      var last = 0;
      while (!sim.finished) {
        sim.tick();
        expect(sim.served - last, lessThanOrEqualTo(sim.counters.length));
        last = sim.served;
      }
    });
  });

  group('the door', () {
    /// Every step anyone takes, over several busy days.
    void everyStep(void Function(Diner d, Cell from, Cell to, Person who) f) {
      for (final seed in [1, 2, 3]) {
        final d = roomWith(tables: 3, rep: 95);
        final sim = DinerSim(d, seed: seed);
        while (!sim.finished) {
          sim.tick();
          for (final p in [...sim.workers, ...sim.guests]) {
            if (p.prev != p.cell) f(d, p.prev, p.cell, p);
          }
        }
      }
    }

    test(
      'nobody gets between the pavement and the room except at the door',
      () {
        var crossings = 0;
        everyStep((d, from, to, who) {
          if (d.isSidewalk(from) != d.isSidewalk(to)) {
            crossings++;
            final inside = d.isSidewalk(from) ? to : from;
            final outside = d.isSidewalk(from) ? from : to;
            expect(inside, d.entrance, reason: '$from to $to');
            expect(outside, d.street, reason: '$from to $to');
          }
        });
        expect(crossings, greaterThan(20), reason: 'guests did come and go');
      },
    );

    test('steps are always to a touching cell, never jumps or diagonals', () {
      everyStep((d, from, to, who) {
        expect((from.x - to.x).abs() + (from.y - to.y).abs(), 1);
      });
    });

    test('staff never leave the room', () {
      final d = roomWith(tables: 3, grills: 2, rep: 95);
      addStaff(d);
      addStaff(d);
      final sim = DinerSim(d, seed: 4);
      while (!sim.finished) {
        sim.tick();
        for (final w in sim.workers) {
          expect(d.isInside(w.cell), isTrue, reason: 'tick ${sim.ticks}');
        }
      }
    });

    test('the only way in or out is the door, for the route finder too', () {
      final d = Diner.starter();
      // From the pavement beside the door, to a seat: the path goes via the
      // pavement cell outside the door, then the entrance.
      final seat = Diner.starter().seats().first.cell;
      final from = Cell(d.entrance.x + 2, d.bottom + 1);
      final path = route(d, from, seat)!;
      expect(path, containsAllInOrder([d.street, d.entrance]));
      // No route across the front edge anywhere else.
      for (var x = Diner.left; x <= d.right; x++) {
        if (x == d.entrance.x) continue;
        expect(canStep(d, Cell(x, d.bottom + 1), Cell(x, d.bottom)), isFalse);
        expect(canStep(d, Cell(x, d.bottom), Cell(x, d.bottom + 1)), isFalse);
      }
      expect(canStep(d, d.street, d.entrance), isTrue);
      expect(canStep(d, d.entrance, d.street), isTrue);
    });
  });

  group('the street', () {
    test('guests walk in from off the screen, from either end', () {
      final sim = DinerSim(starterAt(100), seed: 6);
      final d = sim.diner;
      final from = <Cell>{};
      final seen = <int>{};
      while (!sim.finished) {
        sim.tick();
        for (final g in sim.guests) {
          if (seen.add(g.id)) from.add(g.cell);
        }
      }
      // They have taken their first step by the time anyone sees them.
      final left = from.where((c) => (c.x - d.arrivalLeft.x).abs() <= 1);
      final right = from.where((c) => (c.x - d.arrivalRight.x).abs() <= 1);
      expect(left, isNotEmpty);
      expect(right, isNotEmpty);
      expect(left.length + right.length, from.length);
    });

    test('arriving does not use up patience, waiting in the queue does', () {
      final sim = DinerSim(starterAt(100), seed: 6);
      var sawArriving = false;
      var sawQueued = false;
      while (!sim.finished) {
        sim.tick();
        for (final g in sim.guests) {
          if (g.state == GuestState.arriving) {
            sawArriving = true;
            expect(g.patience, g.patienceMax, reason: 'still walking up');
          }
          if (g.state == GuestState.queued && g.patience < g.patienceMax) {
            sawQueued = true;
          }
        }
      }
      expect(sawArriving, isTrue);
      expect(sawQueued, isTrue);
    });

    test('the queue stands on the pavement in front of the door', () {
      final sim = DinerSim(starterAt(100), seed: 6);
      final d = sim.diner;
      while (!sim.finished) {
        sim.tick();
        for (final g in sim.guests.where(
          (g) => g.state == GuestState.queued || g.state == GuestState.arriving,
        )) {
          expect(g.cell.y, d.bottom + 1, reason: 'on the pavement');
        }
        final queued = sim.guests
            .where((g) => g.state == GuestState.queued)
            .toList();
        for (final g in queued) {
          expect(g.cell.x, greaterThanOrEqualTo(d.entrance.x));
        }
      }
    });

    test('when the queue is full people walk straight past', () {
      final sim = DinerSim(starterAt(100), seed: 6);
      final d = sim.diner;
      var passed = 0;
      final seen = <int>{};
      while (!sim.finished) {
        sim.tick();
        for (final g in sim.guests.where((g) => g.passerby)) {
          expect(g.cell.y, d.bottom + 1, reason: 'never comes inside');
          expect(g.state, GuestState.leaving);
          if (seen.add(g.id)) passed++;
        }
      }
      expect(passed, greaterThan(0));
      expect(sim.walkouts, greaterThanOrEqualTo(passed));
    });

    test('people leave along the pavement and vanish at the edge', () {
      final sim = DinerSim(Diner.starter(), seed: 2);
      final d = sim.diner;
      final exits = <Cell>{};
      while (!sim.finished) {
        sim.tick();
        for (final g in sim.guests) {
          if (g.state == GuestState.leaving && g.path.isEmpty) {
            exits.add(g.cell);
          }
        }
      }
      expect(exits.difference({d.arrivalLeft, d.arrivalRight}), isEmpty);
      expect(sim.guests, isEmpty);
    });

    test(
      'the ground is pavement, kerb and two lanes of road, in that order',
      () {
        final d = Diner.starter();
        final x = d.entrance.x;
        expect(groundTile(d, Cell(x, d.bottom)), startsWith('floor'));
        expect(groundTile(d, Cell(x, d.bottom + 1)), startsWith('sidewalk'));
        expect(groundTile(d, Cell(x, d.bottom + 2)), 'curb');
        expect(groundTile(d, Cell(x, d.bottom + 3)), 'road_a');
        expect(groundTile(d, Cell(x, d.bottom + 4)), 'road_b');
        expect(groundTile(d, Cell(x, d.bottom + 5)), startsWith('sidewalk'));
        expect(
          groundTile(d, Cell(Diner.plotRight + 2, d.bottom + 1)),
          'crosswalk_h',
        );
      },
    );

    test('the pavement stays put, now that the front never moves', () {
      final d = Diner.starter()
        ..progress.level = 9
        ..coins = 100000;
      final before = streetProps(d).first.$2.y;
      d.unlock(1);
      d.unlock(2);
      expect(streetProps(d).first.$2.y, before);
      expect(
        groundTile(d, Cell(d.entrance.x, d.bottom + 1)),
        startsWith('sidewalk'),
      );
    });
  });

  group('growing the restaurant', () {
    test('experience levels the restaurant up and rolls over', () {
      final p = Progress();
      expect(p.xpToNext, 120);
      expect(p.gain(100), 0);
      expect(p.gain(30), 1);
      expect(p.level, 2);
      expect(p.xp, 10);
      expect(p.gain(1000), greaterThan(1));
    });

    test('levels unlock recipes', () {
      final p = Progress();
      expect(p.unlocked(Dish.burger), isTrue);
      expect(p.unlocked(Dish.fries), isFalse);
      p.level = 3;
      expect(p.unlocked(Dish.soda), isTrue);
    });

    test(
      'recipe levels and upgrades cost more each time and stop at a cap',
      () {
        final p = Progress();
        expect(p.recipeUpgradeCost(Dish.burger), 40);
        p.recipeLevel[Dish.burger] = 3;
        expect(p.recipeUpgradeCost(Dish.burger), 120);
        p.recipeLevel[Dish.burger] = Progress.maxRecipeLevel;
        expect(p.canLevelRecipe(Dish.burger), isFalse);
        final first = p.upgradeCost(Upgrade.kitchen)!;
        p.upgrades[Upgrade.kitchen] = 1;
        expect(p.upgradeCost(Upgrade.kitchen)!, greaterThan(first));
        p.upgrades[Upgrade.kitchen] = upgradeDefs[Upgrade.kitchen]!.max;
        expect(p.upgradeCost(Upgrade.kitchen), isNull);
      },
    );

    test('the staff room and tray upgrades change the team size and tray', () {
      final p = Progress();
      expect(p.staffLimit, 1);
      expect(p.carry, 3);
      p.upgrades[Upgrade.staff] = 2;
      p.upgrades[Upgrade.tray] = 1;
      expect(p.staffLimit, 3);
      expect(p.carry, 5);
    });

    test('a good day builds reputation; a bad one loses it', () {
      final good = starterAt(50);
      play(good);
      expect(good.progress.reputation, greaterThan(50));
      final bad = roomWith(tables: 4, rep: 90);
      play(bad);
      expect(bad.progress.reputation, lessThan(90));
      expect(bad.progress.reputation, inInclusiveRange(0, 100));
    });

    test('a new restaurant is quiet and a famous one is packed', () {
      final p = Progress();
      expect(p.reputation, Progress.startReputation);
      expect(p.expectedGuests, lessThan(12));
      p.reputation = 100;
      expect(p.expectedGuests, greaterThan(30));
      var last = 0;
      for (var rep = 0; rep <= 100; rep += 10) {
        p.reputation = rep;
        expect(p.expectedGuests, greaterThanOrEqualTo(last));
        last = p.expectedGuests;
      }
    });

    test('day one is a handful of guests that a small diner copes with', () {
      final d = Diner.starter();
      expect(d.progress.day, 1);
      final sim = play(d);
      expect(sim.arrived, lessThanOrEqualTo(12));
      expect(sim.walkouts, 0);
      expect(sim.served, sim.arrived);
      expect(sim.result!.stars, 3);
      expect(
        d.progress.level,
        1,
        reason: 'one quiet day is not enough to level',
      );
    });

    test('the crowd follows the rating, not the number of seats', () {
      final quiet = DinerSim(roomWith(tables: 4, rep: 10));
      final busy = DinerSim(roomWith(tables: 4, rep: 90));
      expect(
        busy.arrivalSchedule.length,
        greaterThan(quiet.arrivalSchedule.length * 2),
      );
      // The same rating draws the same crowd to a big room and a small one.
      final small = DinerSim(starterAt(60), seed: 4);
      final large = DinerSim(roomWith(tables: 4, rep: 60), seed: 4);
      expect(small.arrivalSchedule, large.arrivalSchedule);
    });

    test('guests come in rushes, not evenly', () {
      final sim = DinerSim(starterAt(100), seed: 2);
      final at = sim.arrivalSchedule;
      int inside(double from, double to) => at
          .where((t) => t >= from * Pace.dayTicks && t < to * Pace.dayTicks)
          .length;
      // The lunch and dinner windows are busier than the early morning.
      expect(inside(0.2, 0.4), greaterThan(inside(0, 0.1) * 2));
      expect(inside(0.62, 0.82), greaterThan(inside(0, 0.1) * 2));
      expect(at.last, lessThan(Pace.dayTicks));
    });

    test('as many guests turn up as were planned', () {
      final d = starterAt(60);
      final sim = DinerSim(d, seed: 3);
      final planned = sim.arrivalSchedule.length;
      while (!sim.finished) {
        sim.tick();
      }
      expect(sim.arrived, planned);
    });

    test('the rating moves a step at a time, not in a jump', () {
      final d = starterAt(10);
      final sim = play(d);
      final change = d.progress.reputation - 10;
      expect(change, greaterThan(0));
      expect(change, lessThanOrEqualTo(30));
      expect(sim.result!.reputationBefore, 10);
      expect(sim.result!.tomorrow, d.progress.expectedGuests);
      // A quiet, well run few days build a following.
      for (var i = 0; i < 4; i++) {
        play(d, seed: 10 + i);
      }
      expect(d.progress.reputation, greaterThan(40));
    });

    test('a day with no guests leaves the rating alone', () {
      final d = Diner(coins: 100)..place(Kind.grill, const Cell(_l, _t));
      d.progress.reputation = 33;
      play(d);
      expect(d.progress.reputation, 33);
    });

    test('a save from before the rating system starts as an unknown place', () {
      final old = Progress.fromJson({'level': 3, 'day': 5, 'rep': 80});
      expect(old.reputation, Progress.startReputation);
      expect(old.level, 3);
      final now = Progress.fromJson(Progress(reputation: 80).toJson());
      expect(now.reputation, 80);
    });
  });

  group('tick clock', () {
    test('runs whole ticks and keeps the remainder', () {
      var n = 0;
      final c = TickClock(() => n++, step: 0.4);
      c.advance(1.0);
      expect(n, 2);
      expect(c.alpha, closeTo(0.5, 1e-9));
    });

    test('drops ticks past the catch-up cap', () {
      var n = 0;
      final c = TickClock(() => n++, step: 0.4, maxCatchUp: 3);
      c.advance(100);
      expect(n, 3);
    });
  });
}
