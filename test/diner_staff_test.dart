import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/diner/service.dart';
import 'package:hex/diner/staff.dart';
import 'package:hex/diner/traits.dart';
import 'package:hex/ui/widgets.dart' show Pal;
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';

Staff person({
  int id = 70,
  String name = 'Test',
  int cooking = 3,
  int speed = 5,
  int service = 3,
  int charm = 3,
  int cap = 10,
  int morale = Staff.maxMorale,
  List<Trait> traits = const [],
}) {
  final stats = {
    Stat.cooking: cooking,
    Stat.speed: speed,
    Stat.service: service,
    Stat.charm: charm,
  };
  return Staff(
    id: id,
    name: name,
    stats: stats,
    potential: {for (final s in Stat.values) s: cap},
    morale: morale,
    traits: [...traits],
    known: {...traits},
  );
}

/// A diner whose only employee is [who].
Diner dinerWith(Staff who, {int rep = 50}) {
  final d = Diner.starter()..progress.reputation = rep;
  d.roster.employees
    ..clear()
    ..add(who);
  return d;
}

/// Scrolls the staff list until [f] is on screen.
Future<void> show(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(
    f,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

/// Closes the day straight away, as if it had run.
DayReport closeNowDay(Diner d, {int seed = 1}) {
  final sim = DinerSim(d, seed: seed);
  sim.ticks = Pace.dayTicks + Pace.lastCall;
  sim.tick();
  return sim.result!;
}

DinerSim play(Diner d, {int seed = 1}) {
  final sim = DinerSim(d, seed: seed);
  while (!sim.finished && sim.ticks < 2000) {
    sim.tick();
  }
  return sim;
}

void main() {
  group('what staff are like', () {
    test('the starter team is one ordinary person', () {
      final r = Roster.starter();
      expect(r.employees.length, 1);
      expect(r.employees.single.total, lessThan(16));
    });

    test('wages follow skill and what is left to learn', () {
      final plain = person(cooking: 3, speed: 3, service: 3, charm: 3, cap: 3);
      final skilled = person(
        cooking: 8,
        speed: 8,
        service: 8,
        charm: 8,
        cap: 8,
      );
      final gifted = person(cooking: 3, speed: 3, service: 3, charm: 3, cap: 9);
      expect(skilled.salary, greaterThan(plain.salary));
      expect(
        gifted.salary,
        greaterThan(plain.salary),
        reason: 'a high ceiling costs more than none',
      );
      expect(plain.fee, plain.salary * 4);
      expect(plain.severance, plain.salary);
    });

    test('every point of every stat changes something', () {
      // No dead zones: each step up is strictly better than the one before.
      for (var v = 1; v < Staff.maxStat; v++) {
        expect(person(speed: v + 1).pace, greaterThan(person(speed: v).pace));
        expect(
          person(service: v + 1).handlingTicks,
          lessThan(person(service: v).handlingTicks),
          reason: 'service $v to ${v + 1}',
        );
        expect(
          person(cooking: v + 1).priceFactor,
          greaterThan(person(cooking: v).priceFactor),
        );
        expect(person(charm: v + 1).calm, greaterThan(person(charm: v).calm));
        expect(
          person(charm: v + 1).tipBonus,
          greaterThan(person(charm: v).tipBonus),
        );
      }
    });

    test('the middle of every scale is the baseline', () {
      expect(person(speed: 5).pace, closeTo(1.0, 1e-9));
      expect(person(cooking: 3).priceFactor, 1);
      expect(person(charm: 3).calm, 0);
      expect(person(charm: 3).tipBonus, 0);
    });

    test('speed is a gentle slope, never a jump', () {
      for (var v = 1; v < Staff.maxStat; v++) {
        final step = person(speed: v + 1).pace - person(speed: v).pace;
        expect(step, closeTo(0.08, 1e-9));
      }
      expect(person(speed: 10).pace, lessThan(1.5));
    });

    test('plate handling averages out to the fraction, tick by tick', () {
      // A fast hand hands over in under a tick, but never in a negative one.
      for (final v in [1, 4, 7, 10]) {
        final who = person(service: v);
        final sim = DinerSim(dinerWith(who));
        final w = sim.workers.single;
        var total = 0;
        for (var i = 0; i < 200; i++) {
          total += w.takeHandling();
        }
        expect(
          total / 200,
          closeTo(who.handlingTicks, 0.02),
          reason: 'service $v',
        );
      }
    });

    test('a slower cook is not slower at cooking, just worse at it', () {
      // Cooking time depends on the recipe and the kitchen, not the cook.
      for (final who in [person(cooking: 1), person(cooking: 10)]) {
        final sim = DinerSim(dinerWith(who));
        int? seen;
        while (seen == null && sim.ticks < 300) {
          sim.tick();
          final m = sim.machines.first;
          if (m.item != null && !m.ready) seen = m.total;
        }
        expect(seen, Progress().cookTicks(Dish.burger));
      }
    });

    test('cooks work the kitchen and the rest work the floor', () {
      expect(person(cooking: 7, speed: 4, service: 4).kitchen, isTrue);
      expect(person(cooking: 3, speed: 4, service: 8).kitchen, isFalse);
      expect(person(cooking: 7, speed: 4, service: 4).role, 'Kitchen');
    });
  });

  group('candidates', () {
    Diner richStarter() => Diner.starter()
      ..coins = 100000
      ..progress.upgrades[Upgrade.staff] = 1;

    test('nobody answers until an advert has been paid for', () {
      final d = richStarter();
      d.lookForStaff();
      expect(d.roster.candidates, isEmpty);
      d.progress.day = 9;
      d.lookForStaff();
      expect(d.roster.candidates, isEmpty);
    });

    test('an advert brings people, the same all day, gone by morning', () {
      final d = richStarter();
      expect(d.advertise(Ad.paper), StaffResult.ok);
      final today = d.roster.candidates.map((c) => c.name).toList();
      expect(today.length, adDefs[Ad.paper]!.count);
      expect(today.toSet().length, today.length, reason: 'no doubles');
      d.lookForStaff();
      expect(d.roster.candidates.map((c) => c.name), today);
      d.progress.day++;
      d.lookForStaff();
      expect(d.roster.candidates, isEmpty);
    });

    test('nobody applies who already works here', () {
      final d = richStarter();
      for (var day = 1; day < 40; day++) {
        d.progress.day = day;
        d.advertise(Ad.paper);
        for (final c in d.roster.candidates) {
          expect(
            d.roster.employees.map((e) => e.name),
            isNot(contains(c.name)),
          );
        }
      }
    });

    test('a famous restaurant draws better people', () {
      double mean(int level, double rating) {
        var sum = 0.0;
        var n = 0;
        for (var day = 1; day <= 60; day++) {
          final r = Roster.starter()
            ..rollCandidates(day, level, rating, Ad.paper);
          for (final c in r.candidates) {
            sum += c.total;
            n++;
          }
        }
        return sum / n;
      }

      expect(mean(8, 4.5), greaterThan(mean(1, 0.5) + 4));
    });

    test('a dearer advert reaches better people', () {
      double mean(Ad ad) {
        var sum = 0.0;
        var n = 0;
        for (var day = 1; day <= 80; day++) {
          final r = Roster.starter()..rollCandidates(day, 4, 2.5, ad);
          for (final c in r.candidates) {
            sum += c.total;
            n++;
          }
        }
        return sum / n;
      }

      expect(mean(Ad.agency), greaterThan(mean(Ad.paper) + 2));
      expect(mean(Ad.paper), greaterThan(mean(Ad.notice) + 1));
      expect(adDefs[Ad.agency]!.cost, greaterThan(adDefs[Ad.paper]!.cost));
      expect(adDefs[Ad.paper]!.cost, greaterThan(adDefs[Ad.notice]!.cost));
    });

    test('and more of them come knowing a hard dish', () {
      double specialists(Ad ad) {
        var with_ = 0;
        var n = 0;
        for (var day = 1; day <= 200; day++) {
          final r = Roster.starter()..rollCandidates(day, 6, 3, ad);
          for (final c in r.candidates) {
            n++;
            if (c.specialty != null) with_++;
          }
        }
        return with_ / n;
      }

      expect(specialists(Ad.agency), greaterThan(specialists(Ad.paper)));
      expect(specialists(Ad.paper), greaterThan(specialists(Ad.notice)));
    });

    test('the cheap advert brings fewer people', () {
      expect(adDefs[Ad.notice]!.count, lessThan(adDefs[Ad.paper]!.count));
      final r = Roster.starter()..rollCandidates(3, 3, 2, Ad.notice);
      expect(r.candidates.length, adDefs[Ad.notice]!.count);
    });

    test('everyone on offer is believable', () {
      for (var day = 1; day <= 80; day++) {
        for (final ad in Ad.values) {
          final r = Roster.starter()
            ..rollCandidates(day, 1 + day % 9, day % 6.0, ad);
          for (final c in r.candidates) {
            for (final s in Stat.values) {
              expect(c.stat(s), inInclusiveRange(1, Staff.maxStat));
              expect(c.cap(s), inInclusiveRange(c.stat(s), Staff.maxStat));
            }
            expect(c.salary, greaterThan(0));
          }
        }
      }
    });

    test('paying again finds different people, and costs the price', () {
      final d = richStarter();
      d.advertise(Ad.paper);
      final before = d.roster.candidates.map((c) => c.name).toList();
      final coins = d.coins;
      expect(d.advertise(Ad.paper), StaffResult.ok);
      expect(d.coins, coins - adDefs[Ad.paper]!.cost);
      expect(d.roster.candidates.map((c) => c.name), isNot(before));
    });

    test('you cannot advertise without the money, or with a full team', () {
      final d = richStarter()..coins = 20;
      expect(d.advertise(Ad.notice), StaffResult.broke);
      expect(d.coins, 20);
      expect(d.roster.candidates, isEmpty);
      final full = Diner.starter()..coins = 5000;
      expect(full.advertise(Ad.paper), StaffResult.noRoom);
      expect(full.coins, 5000, reason: 'no money wasted on a full team');
    });
  });

  group('hiring, training and firing', () {
    test('hiring costs the fee and needs a place on the team', () {
      final d = Diner.starter()..coins = 500;
      d.roster.rollCandidates(
        d.progress.day,
        d.progress.level,
        d.progress.rating,
        Ad.paper,
      );
      final c = d.roster.candidates.first;
      expect(d.hire(c), StaffResult.noRoom, reason: 'one place, one person');
      expect(d.coins, 500);

      d.progress.upgrades[Upgrade.staff] = 1;
      expect(d.hire(c), StaffResult.ok);
      expect(d.coins, 500 - c.fee);
      expect(d.roster.employees, contains(c));
      expect(d.roster.candidates, isNot(contains(c)));
      expect(d.hire(c), StaffResult.gone, reason: 'already taken on');
    });

    test('you cannot hire without the money', () {
      final d = Diner.starter()..coins = 5;
      d.progress.upgrades[Upgrade.staff] = 1;
      d.roster.rollCandidates(
        d.progress.day,
        d.progress.level,
        d.progress.rating,
        Ad.paper,
      );
      expect(d.hire(d.roster.candidates.first), StaffResult.broke);
      expect(d.roster.employees.length, 1);
    });

    test('training raises a stat for a price, once a day', () {
      final d = Diner.starter()..coins = 500;
      final sam = d.roster.employees.single;
      final cost = sam.trainCost(Stat.cooking);
      expect(d.train(sam, Stat.cooking), StaffResult.ok);
      expect(sam.stat(Stat.cooking), 5);
      expect(d.coins, 500 - cost);
      expect(d.train(sam, Stat.speed), StaffResult.tired);
      sam.trainedToday = false;
      expect(d.train(sam, Stat.speed), StaffResult.ok);
    });

    test('training stops at what the person can become', () {
      final d = Diner.starter()..coins = 5000;
      final p = person(cooking: 5, cap: 5);
      d.roster.employees.add(p);
      expect(d.train(p, Stat.cooking), StaffResult.maxed);
      expect(p.stat(Stat.cooking), 5);
    });

    test('training costs more the better they already are', () {
      expect(
        person(cooking: 8).trainCost(Stat.cooking),
        greaterThan(person(cooking: 3).trainCost(Stat.cooking)),
      );
    });

    test('a trained person costs more to keep', () {
      final d = Diner.starter()..coins = 500;
      final sam = d.roster.employees.single;
      final before = sam.salary;
      d.train(sam, Stat.cooking);
      expect(sam.salary, greaterThanOrEqualTo(before));
    });

    test('firing pays a day\'s wages and the person leaves', () {
      final d = Diner.starter()..coins = 100;
      final sam = d.roster.employees.single;
      final pay = sam.severance;
      expect(d.fire(sam), StaffResult.ok);
      expect(d.coins, 100 - pay);
      expect(d.roster.employees, isEmpty);
      expect(d.fire(sam), StaffResult.gone);
    });

    test('firing someone you cannot pay costs what you have', () {
      final d = Diner.starter()..coins = 3;
      d.fire(d.roster.employees.single);
      expect(d.coins, 0);
    });

    test('with nobody working, the diner cannot open', () {
      final d = Diner.starter();
      d.fire(d.roster.employees.single);
      expect(d.report().ready, isFalse);
      expect(d.report().missing, contains('Needs someone to work'));
    });
  });

  group('how stats play out in a day', () {
    test('a good cook\'s food sells for more', () {
      final good = play(dinerWith(person(cooking: 10, speed: 6, service: 5)));
      final poor = play(dinerWith(person(cooking: 1, speed: 6, service: 5)));
      expect(good.served, closeTo(poor.served, 1));
      expect(good.earned, greaterThan(poor.earned));
      // Not one customer paid the menu price for a master cook's food.
      final perMeal = (good.earned - good.tips) / good.served;
      expect(perMeal, greaterThan(8 * 1.15));
    });

    test('guests pay what the person who cooked it earned', () {
      final d = dinerWith(person(cooking: 10), rep: 30);
      final sim = DinerSim(d);
      final seen = <double>[];
      while (!sim.finished) {
        sim.tick();
        for (final g in sim.guests) {
          for (final i in g.items.where(
            (i) => i.state == ItemState.cooking && i.quality != 1,
          )) {
            seen.add(i.quality);
          }
        }
      }
      expect(seen, isNotEmpty);
      // At least the cook's own price factor; more as they master the dish.
      for (final q in seen) {
        expect(q, greaterThanOrEqualTo(person(cooking: 10).priceFactor - 1e-9));
      }
      expect(seen.first, closeTo(person(cooking: 10).priceFactor, 1e-9));
    });

    test('a quick walker gets more done than a slow one', () {
      final quick = play(dinerWith(person(speed: 10), rep: 80));
      final slow = play(dinerWith(person(speed: 1), rep: 80));
      expect(quick.served, greaterThan(slow.served));
    });

    test('nobody ever moves more than two tiles in a tick', () {
      final sim = DinerSim(dinerWith(person(speed: 10), rep: 90), seed: 3);
      while (!sim.finished) {
        sim.tick();
        final w = sim.workers.single;
        expect(
          (w.prev.x - w.cell.x).abs() + (w.prev.y - w.cell.y).abs(),
          lessThanOrEqualTo(2),
        );
      }
    });

    test('a charming waiter earns bigger tips', () {
      final charming = play(dinerWith(person(charm: 10, speed: 6, cooking: 5)));
      final cold = play(dinerWith(person(charm: 1, speed: 6, cooking: 5)));
      expect(charming.tips, greaterThan(cold.tips));
    });

    test('a charming team keeps guests from giving up as soon', () {
      // A slow team, so guests really do wait.
      final charming = DinerSim(
        dinerWith(person(charm: 10, speed: 2, service: 2), rep: 70),
      );
      final cold = DinerSim(
        dinerWith(person(charm: 1, speed: 2, service: 2), rep: 70),
      );
      int left(DinerSim s) {
        while (!s.finished) {
          s.tick();
        }
        return s.gaveUp;
      }

      expect(left(charming), lessThan(left(cold)));
    });

    test('patience drains more slowly with charm, and by a steady amount', () {
      int ticksToLose(DinerSim sim, int patience) {
        // Seated and already being cooked for, so staff leave it be.
        final g = Guest(1, 'cust_a', 100, sim.seats.first.cell)
          ..seat = sim.seats.first
          ..state = GuestState.waiting;
        g.items.add(
          OrderItem(g, Dish.burger, Tier.standard)..state = ItemState.cooking,
        );
        sim.guests.add(g);
        var n = 0;
        while (g.patience > 100 - patience && n < 1000) {
          // The sim drains each waiting guest once a tick.
          sim.tick();
          n++;
        }
        sim.guests.remove(g);
        return n;
      }

      // Same guest, same wait, but a charming team and a cold one.
      final calm = DinerSim(dinerWith(person(charm: 10), rep: 0));
      final cold = DinerSim(dinerWith(person(charm: 1), rep: 0));
      expect(ticksToLose(calm, 20), greaterThan(ticksToLose(cold, 20)));
    });

    test('charm is judged across the whole team', () {
      final d = dinerWith(person(charm: 10))
        ..progress.upgrades[Upgrade.staff] = 1;
      d.roster.employees.add(person(id: 71, name: 'B', charm: 4));
      final both = DinerSim(d);
      final alone = DinerSim(dinerWith(person(charm: 10)));
      final cold = DinerSim(dinerWith(person(charm: 4)));
      // A charming person among a cool team calms guests less than alone.
      expect(both.calmness, lessThan(alone.calmness));
      expect(both.calmness, greaterThan(cold.calmness));
    });

    test('a skilled team copes with a crowd that beats a beginner', () {
      final beginner = play(
        dinerWith(person(cooking: 2, speed: 2, service: 2), rep: 80),
      );
      final expert = play(
        dinerWith(person(cooking: 8, speed: 8, service: 8), rep: 80),
      );
      expect(expert.served, greaterThan(beginner.served));
    });

    test('a second person adds their own stats to the work', () {
      final d = dinerWith(person(cooking: 5), rep: 90)
        ..progress.upgrades[Upgrade.staff] = 1;
      d.roster.employees.add(person(id: 71, name: 'Other', service: 7));
      final sim = DinerSim(d);
      expect(sim.workers.map((w) => w.staff.name), ['Test', 'Other']);
      expect(sim.workers.first.sprite, 'chef');
    });
  });

  group('balance', () {
    /// A bigger room under a busy crowd, with the given person working it.
    Diner busy(Staff who) {
      final d = Diner(
        coins: 100000,
        owned: {0, 1},
        progress: Progress(reputation: 80),
      );
      d.roster.employees
        ..clear()
        ..add(who);
      d.place(Kind.grill, const Cell(1, 3), Dir.sw);
      d.place(Kind.grill, const Cell(2, 3), Dir.sw);
      d.place(Kind.counter, const Cell(7, 3), Dir.sw);
      d.place(Kind.counter, const Cell(8, 3), Dir.sw);
      for (final t in const [Cell(3, 5), Cell(6, 5), Cell(6, 7)]) {
        d.place(Kind.table, t);
        d.place(Kind.chair, Cell(t.x - 1, t.y), Dir.se);
        d.place(Kind.chair, Cell(t.x + 1, t.y), Dir.nw);
      }
      return d;
    }

    double earned(Staff who) {
      var sum = 0.0;
      for (final seed in [1, 2, 3]) {
        sum += play(busy(who), seed: seed).earned;
      }
      return sum / 3;
    }

    Staff with_(Stat stat, int value) {
      final stats = {
        Stat.cooking: 4,
        Stat.speed: 5,
        Stat.service: 4,
        Stat.charm: 4,
        stat: value,
      };
      return Staff(
        id: 80,
        name: 'B',
        stats: stats,
        potential: {for (final s in Stat.values) s: 10},
      );
    }

    for (final stat in Stat.values) {
      test('${stat.name} is worth training: top marks beat bottom by 25%', () {
        final low = earned(with_(stat, 1));
        final high = earned(with_(stat, 10));
        expect(high, greaterThan(low * 1.25), reason: '$low to $high');
      });
    }

    test('cooking pays a little more at every step, rounding or not', () {
      var last = 0.0;
      for (final v in [1, 3, 5, 8, 10]) {
        final e = earned(with_(Stat.cooking, v));
        expect(e, greaterThan(last), reason: 'cooking $v');
        last = e;
      }
    });
  });

  group('wages and morale', () {
    test('wages come out of the takings at the end of the day', () {
      final d = Diner.starter();
      final sam = d.roster.employees.single;
      final sim = play(d);
      expect(sim.result!.wages, sam.salary);
      expect(sim.result!.unpaid, 0);
      expect(sam.daysWorked, 1);
      expect(sam.morale, Staff.maxMorale);
    });

    test('training happens once a day, so it resets overnight', () {
      final d = Diner.starter()..coins = 500;
      final sam = d.roster.employees.single;
      d.train(sam, Stat.speed);
      expect(sam.trainedToday, isTrue);
      play(d);
      expect(sam.trainedToday, isFalse);
    });

    test('unpaid people lose heart, and quit when they have none left', () {
      final d = Diner.starter()..coins = 0;
      // A day with no takings and no money in the till.
      d.roster.employees.single.traits.clear();
      d.roster.employees.single.morale = 2;
      d.progress.reputation = 0;
      final sim = DinerSim(d);
      // Close without anyone paying: end the day immediately.
      sim.ticks = Pace.dayTicks + Pace.lastCall;
      sim.tick();
      var report = sim.result;
      expect(report, isNotNull);
      expect(report!.unpaid, greaterThan(0));
      expect(d.roster.employees.single.morale, 1);
      expect(report.quit, isEmpty);

      final second = DinerSim(d);
      second.ticks = Pace.dayTicks + Pace.lastCall;
      second.tick();
      report = second.result!;
      expect(report.quit, ['Sam']);
      expect(d.roster.employees, isEmpty);
    });

    test('paying again restores morale', () {
      final d = Diner.starter()..coins = 500;
      final sam = d.roster.employees.single..morale = 1;
      final sim = DinerSim(d);
      sim.ticks = Pace.dayTicks + Pace.lastCall;
      sim.tick();
      expect(sam.morale, 2);
    });
  });

  group('saving', () {
    test('the whole team and the candidates survive a save', () {
      final d = Diner.starter()
        ..coins = 5000
        ..progress.upgrades[Upgrade.staff] = 1;
      d.advertise(Ad.paper);
      d.train(d.roster.employees.single, Stat.charm);
      final back = Diner.fromJson(d.toJson());
      expect(back.roster.employees.length, 1);
      final sam = back.roster.employees.single;
      expect(sam.name, 'Sam');
      expect(sam.stat(Stat.charm), 4);
      expect(sam.trainedToday, isTrue);
      expect(
        back.roster.candidates.map((c) => c.name),
        d.roster.candidates.map((c) => c.name),
      );
      expect(back.roster.candidateDay, d.roster.candidateDay);
    });

    test('an old save with no team gets the starter', () {
      final d = Diner.fromJson({'coins': 4, 'items': []});
      expect(d.roster.employees.length, 1);
    });

    test('a damaged save cannot make an impossible person', () {
      final d = Diner.fromJson({
        'staff': {
          'employees': [
            {
              'id': 1,
              'name': 'Odd',
              'stats': {'cooking': 99, 'speed': -5},
              'cap': {'cooking': 2},
              'morale': 40,
            },
            'not a person',
          ],
        },
      });
      final odd = d.roster.employees.single;
      expect(odd.stat(Stat.cooking), Staff.maxStat);
      expect(odd.stat(Stat.speed), 1);
      expect(
        odd.cap(Stat.cooking),
        greaterThanOrEqualTo(odd.stat(Stat.cooking)),
      );
      expect(odd.morale, Staff.maxMorale);
    });
  });

  group('the staff pages', () {
    Future<Diner> open(WidgetTester tester, {Diner? diner}) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
      });
      Storage.clearMemory();
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final d = diner ?? (Diner.starter()..coins = 900);
      await tester.pumpWidget(HexApp(home: BuildScreen(diner: d)));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('staff')));
      await tester.pumpAndSettle();
      return d;
    }

    Future<void> openPerson(WidgetTester tester, Staff s) async {
      await tester.tap(find.byKey(ValueKey('team-${s.id}')));
      await tester.pumpAndSettle();
    }

    Diner roomy() => Diner.starter()
      ..coins = 2000
      ..progress.upgrades[Upgrade.staff] = 1;

    testWidgets('the team is one short line each, nothing more', (
      tester,
    ) async {
      final d = await open(tester);
      final sam = d.roster.employees.single;
      expect(find.byKey(ValueKey('team-${sam.id}')), findsOneWidget);
      expect(find.textContaining('Sam'), findsOneWidget);
      // No stats, tags, lessons or applicants on this page.
      expect(find.byKey(ValueKey('stat-${sam.id}-cooking')), findsNothing);
      expect(find.byKey(ValueKey('train-${sam.id}-cooking')), findsNothing);
      expect(find.byKey(ValueKey('trait-${sam.id}-loyal')), findsNothing);
      expect(find.byKey(ValueKey('fire-${sam.id}')), findsNothing);
      expect(find.byKey(const ValueKey('hire')), findsOneWidget);
    });

    testWidgets('tapping a person opens their page', (tester) async {
      final d = await open(tester);
      await openPerson(tester, d.roster.employees.single);
      expect(find.text('Skills'), findsOneWidget);
      expect(find.text('Works'), findsOneWidget);
    });

    testWidgets('a stat explains itself right under itself', (tester) async {
      final d = await open(tester);
      final sam = d.roster.employees.single;
      await openPerson(tester, sam);
      double? last;
      for (final stat in Stat.values) {
        await tester.tap(find.byKey(ValueKey('stat-${sam.id}-${stat.name}')));
        await tester.pump();
        final help = find.byKey(ValueKey('help-${sam.id}-${stat.name}'));
        expect(help, findsOneWidget);
        expect(find.textContaining(statInfo[stat]!.info), findsOneWidget);
        // Right below its own row, and on screen without scrolling.
        final row = tester.getRect(
          find.byKey(ValueKey('stat-${sam.id}-${stat.name}')),
        );
        final box = tester.getRect(help);
        expect(box.top, greaterThanOrEqualTo(row.bottom));
        expect(box.top - row.bottom, lessThan(12));
        expect(box.bottom, lessThan(tester.view.physicalSize.height / 3));
        last = box.top;
      }
      expect(last, isNotNull);
      // Tapping again closes it.
      await tester.tap(find.byKey(ValueKey('stat-${sam.id}-charm')));
      await tester.pump();
      expect(find.textContaining(statInfo[Stat.charm]!.info), findsNothing);
      expect(statInfo[Stat.cooking]!.info, contains('sells for more'));
      expect(statInfo[Stat.charm]!.info, contains('wait longer'));
    });

    testWidgets('hiring is its own page, and starts with nobody there', (
      tester,
    ) async {
      final d = await open(tester, diner: roomy());
      await tester.tap(find.byKey(const ValueKey('hire')));
      await tester.pumpAndSettle();
      expect(find.text('Hiring'), findsOneWidget);
      expect(d.roster.candidates, isEmpty);
      for (final ad in Ad.values) {
        expect(find.byKey(ValueKey('ad-${ad.name}')), findsOneWidget);
      }
      expect(find.textContaining('Answered today'), findsNothing);
    });

    testWidgets('an advert costs money and brings applicants', (tester) async {
      final d = await open(tester, diner: roomy());
      await tester.tap(find.byKey(const ValueKey('hire')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('advertise-paper')));
      await tester.pump();
      expect(d.coins, 2000 - adDefs[Ad.paper]!.cost);
      expect(d.roster.candidates.length, adDefs[Ad.paper]!.count);
      for (final c in d.roster.candidates) {
        expect(find.byKey(ValueKey('cand-${c.id}')), findsOneWidget);
        // A line each: no stats or hire button on this page.
        expect(find.byKey(ValueKey('hire-${c.id}')), findsNothing);
      }
    });

    testWidgets('a cheap advert is cheap and a dear one is dear', (
      tester,
    ) async {
      final d = await open(tester, diner: roomy());
      await tester.tap(find.byKey(const ValueKey('hire')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('advertise-notice')));
      await tester.pump();
      expect(d.roster.candidates.length, adDefs[Ad.notice]!.count);
      expect(d.coins, 2000 - adDefs[Ad.notice]!.cost);
      await tester.tap(find.byKey(const ValueKey('advertise-agency')));
      await tester.pump();
      expect(d.roster.candidates.length, adDefs[Ad.agency]!.count);
    });

    testWidgets('an advert you cannot afford cannot be placed', (tester) async {
      final d = await open(
        tester,
        diner: roomy()..coins = adDefs[Ad.paper]!.cost - 1,
      );
      await tester.tap(find.byKey(const ValueKey('hire')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('advertise-paper')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(d.roster.candidates, isEmpty);
      expect(d.coins, adDefs[Ad.paper]!.cost - 1);
    });

    testWidgets('an applicant is looked over on their own page, then hired', (
      tester,
    ) async {
      final d = await open(tester, diner: roomy());
      await tester.tap(find.byKey(const ValueKey('hire')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('advertise-paper')));
      await tester.pump();
      final c = d.roster.candidates.first;
      final coins = d.coins;
      await tester.tap(find.byKey(ValueKey('cand-${c.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('stat-${c.id}-cooking')), findsOneWidget);
      expect(find.byKey(ValueKey('fire-${c.id}')), findsNothing);
      await tester.tap(find.byKey(ValueKey('hire-${c.id}')));
      await tester.pumpAndSettle();
      expect(d.roster.employees, contains(c));
      expect(d.coins, coins - c.fee);
      expect(d.roster.candidates, isNot(contains(c)));
    });

    testWidgets('a full team cannot place an advert, and is told why', (
      tester,
    ) async {
      final d = await open(tester);
      await tester.tap(find.byKey(const ValueKey('hire')));
      await tester.pumpAndSettle();
      expect(find.textContaining('team is full'), findsOneWidget);
      expect(find.byKey(const ValueKey('advertise-paper')), findsNothing);
      expect(d.coins, 900);
    });

    testWidgets('training and lessons are on their own page', (tester) async {
      final d = await open(tester);
      final sam = d.roster.employees.single;
      await openPerson(tester, sam);
      expect(find.byKey(ValueKey('train-${sam.id}-cooking')), findsNothing);
      await tester.tap(find.byKey(ValueKey('open-training-${sam.id}')));
      await tester.pumpAndSettle();
      final before = sam.stat(Stat.cooking);
      await tester.tap(find.byKey(ValueKey('train-${sam.id}-cooking')));
      await tester.pump();
      expect(sam.stat(Stat.cooking), before + 1);
      await tester.tap(
        find.byKey(ValueKey('train-${sam.id}-speed')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(sam.stat(Stat.speed), 4, reason: 'one lesson a day');
      expect(find.byKey(const ValueKey('training-note')), findsOneWidget);
    });

    testWidgets('firing asks first', (tester) async {
      final d = await open(tester);
      final sam = d.roster.employees.single;
      await openPerson(tester, sam);
      await tester.ensureVisible(find.byKey(ValueKey('fire-${sam.id}')));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey('fire-${sam.id}')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Let Sam go?'), findsOneWidget);
      await tester.tap(find.text('Keep them'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(d.roster.employees, contains(sam));

      await tester.tap(find.byKey(ValueKey('fire-${sam.id}')));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('confirm-fire')));
      await tester.pumpAndSettle();
      expect(d.roster.employees, isEmpty);
      expect(find.byKey(ValueKey('team-${sam.id}')), findsNothing);
    });

    testWidgets('where someone works is chosen from buttons, not cycled', (
      tester,
    ) async {
      final d = await open(tester);
      final sam = d.roster.employees.single;
      await openPerson(tester, sam);
      expect(find.byKey(ValueKey('duty-${sam.id}-anywhere')), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('duty-${sam.id}-grill')));
      await tester.pump();
      expect(sam.duty, Kind.grill);
      expect(find.textContaining('looks after the grill'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('duty-${sam.id}-anywhere')));
      await tester.pump();
      expect(sam.duty, isNull);
    });

    testWidgets('the day opens only with someone to work', (tester) async {
      final d = Diner.starter()..coins = 900;
      d.fire(d.roster.employees.single);
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
      expect(find.textContaining('Needs someone to work'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('start-day')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('start-day')), findsOneWidget);
    });
  });

  group('payday', () {
    test('wages are paid once, at the end of the day, and not before', () {
      final d = Diner.starter();
      final sam = d.roster.employees.single;
      final sim = DinerSim(d, seed: 2);
      sim.tick(); // the ingredients are bought as the doors open
      var coins = d.coins;
      while (!sim.finished) {
        sim.tick();
        // All through the day the till only goes up.
        expect(
          d.coins,
          greaterThanOrEqualTo(coins),
          reason: 'tick ${sim.ticks}: nobody is paid mid-shift',
        );
        coins = d.coins;
        if (sim.ticks > Pace.dayTicks + Pace.lastCall) break;
      }
      expect(sim.result!.wages, sam.salary);
      // And not paid again if the day is closed a second time.
      final after = d.coins;
      sim.finishDay();
      expect(d.coins, after);
    });

    test('the takings come first, so a good day pays for itself', () {
      final d = Diner.starter()..coins = 60;
      final sim = play(d, seed: 2);
      expect(sim.earned, greaterThan(d.roster.wages));
      expect(sim.result!.unpaid, 0);
      expect(d.roster.employees.single.lastPay, Pay.paid);
    });

    test('whoever the till cannot cover goes unpaid, in team order', () {
      final d = Diner.starter()..coins = 0;
      d.progress.upgrades[Upgrade.staff] = 1;
      final first = d.roster.employees.single;
      final second = person(id: 71, name: 'Second', speed: 4);
      d.roster.employees.add(second);
      d.coins = first.salary; // exactly enough for the first, none left
      final sim = DinerSim(d);
      sim.ticks = Pace.dayTicks + Pace.lastCall;
      sim.tick();
      expect(first.lastPay, Pay.paid);
      expect(second.lastPay, Pay.missed);
      expect(sim.result!.unpaid, second.salary);
    });

    test('a missed payday is remembered until the next one', () {
      final d = Diner.starter()..coins = 0;
      final who = person(morale: 3);
      d.roster.employees
        ..clear()
        ..add(who);
      closeNowDay(d);
      expect(who.lastPay, Pay.missed);
      d.coins = 500;
      closeNowDay(d);
      expect(who.lastPay, Pay.paid);
    });
  });

  group('mood', () {
    test('four moods, one for each morale', () {
      expect(person(morale: 3).mood, 'Happy');
      expect(person(morale: 2).mood, 'Content');
      expect(person(morale: 1).mood, 'Fed up');
      expect(person(morale: 0).mood, 'Leaving');
    });

    test('the note says what happens next', () {
      expect(person(morale: 1).moodNote, contains('quit'));
      final loyal = person(morale: 1, traits: [Trait.loyal]);
      expect(loyal.moodNote, contains('put up with one more'));
      final hot = person(morale: 1, traits: [Trait.hotHeaded]);
      expect(hot.moodNote, contains('walk out'));
      final paid = person(morale: 3)..lastPay = Pay.paid;
      expect(paid.moodNote, contains('Paid on time'));
      final missed = person(morale: 2)..lastPay = Pay.missed;
      expect(missed.moodNote, contains('Missed a payday'));
    });

    test('the last payday is saved', () {
      final who = person()..lastPay = Pay.missed;
      final back = Staff.fromJson(who.toJson())!;
      expect(back.lastPay, Pay.missed);
      expect(Staff.fromJson({'id': 1, 'name': 'Old'})!.lastPay, Pay.none);
    });

    test('the day report says how everyone\'s mood moved', () {
      final d = Diner.starter()..coins = 0;
      final a = person(id: 80, name: 'A', morale: 2);
      d.progress.upgrades[Upgrade.staff] = 1;
      d.roster.employees
        ..clear()
        ..add(a);
      final r1 = closeNowDay(d);
      expect(r1.moods.single.name, 'A');
      expect(r1.moods.single.before, 2);
      expect(r1.moods.single.after, 1);
      expect(r1.moods.single.worse, isTrue);
      d.coins = 900;
      final r2 = closeNowDay(d);
      expect(r2.moods.single.better, isTrue);
    });
  });

  group('payday and mood on screen', () {
    Future<Diner> open(
      WidgetTester tester,
      Diner d, {
      bool staff = true,
    }) async {
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
      if (staff) {
        await tester.tap(find.byKey(const ValueKey('staff')));
        await tester.pumpAndSettle();
      }
      return d;
    }

    testWidgets('the staff screen says when wages are paid and what is due', (
      tester,
    ) async {
      final d = Diner.starter()..coins = 300;
      await open(tester, d);
      expect(find.byKey(const ValueKey('payroll')), findsOneWidget);
      expect(find.textContaining('end of each day'), findsOneWidget);
    });

    testWidgets('and warns when the till cannot cover it', (tester) async {
      final d = Diner.starter()..coins = 3;
      await open(tester, d);
      expect(find.textContaining('only 3 in the till'), findsOneWidget);
    });

    testWidgets('the Staff button flags it before the day starts', (
      tester,
    ) async {
      final short = Diner.starter()..coins = 3;
      await open(tester, short, staff: false);
      expect(find.text('Staff !'), findsOneWidget);
    });

    testWidgets('and is calm when the till is fine', (tester) async {
      final fine = Diner.starter()..coins = 500;
      await open(tester, fine, staff: false);
      expect(find.text('Staff'), findsOneWidget);
      expect(find.text('Staff !'), findsNothing);
    });

    testWidgets('no warning when there is plenty', (tester) async {
      final d = Diner.starter()..coins = 500;
      await open(tester, d);
      expect(find.textContaining('in the till'), findsNothing);
    });

    testWidgets(
      'the team shows a face for each; the page adds pips and a note',
      (tester) async {
        final d = Diner.starter()..coins = 500;
        final sam = d.roster.employees.single..morale = 2;
        await open(tester, d);
        expect(find.byKey(ValueKey('mood-${sam.id}')), findsOneWidget);
        expect(find.byKey(ValueKey('mood-note-${sam.id}')), findsNothing);
        await tester.tap(find.byKey(ValueKey('team-${sam.id}')));
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('mood-${sam.id}')), findsOneWidget);
        expect(find.byKey(ValueKey('mood-note-${sam.id}')), findsOneWidget);
        expect(find.textContaining('Content'), findsWidgets);
        for (var i = 0; i < 3; i++) {
          expect(find.byKey(ValueKey('pip-${sam.id}-$i')), findsOneWidget);
        }
        final lit = [
          for (var i = 0; i < 3; i++)
            (tester
                    .widget<Container>(find.byKey(ValueKey('pip-${sam.id}-$i')))
                    .color !=
                Pal.panelLo),
        ];
        expect(lit, [true, true, false], reason: 'two of three pips lit');
      },
    );

    testWidgets('an unhappy person is flagged in red', (tester) async {
      final d = Diner.starter()..coins = 500;
      final sam = d.roster.employees.single
        ..morale = 1
        ..lastPay = Pay.missed;
      await open(tester, d);
      expect(find.textContaining('missed a payday'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('team-${sam.id}')));
      await tester.pumpAndSettle();
      final note = tester.widget(find.byKey(ValueKey('mood-note-${sam.id}')));
      expect((note as dynamic).style.color, Pal.red);
      expect(find.textContaining('Missed a payday'), findsOneWidget);
    });

    testWidgets('the live panel stays light: no wages line, no ticker', (
      tester,
    ) async {
      final d = Diner.starter()..coins = 500;
      await open(tester, d, staff: false);
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump();
      expect(find.byKey(const ValueKey('wages-tonight')), findsNothing);
      expect(find.byKey(const ValueKey('ticker')), findsNothing);
    });

    testWidgets('the summary shows how each person feels now', (tester) async {
      final d = Diner.starter()..coins = 500;
      final sam = d.roster.employees.single;
      await open(tester, d, staff: false);
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('speed-3')));
      await tester.pump();
      for (var i = 0; i < 900; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byKey(const ValueKey('next-day')).evaluate().isNotEmpty) break;
      }
      expect(find.byKey(ValueKey('mood-${sam.name}')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('details')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('mood-${sam.name}')), findsOneWidget);
    });
  });
}
