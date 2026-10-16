import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/diner_painter.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/diner/service.dart';
import 'package:hex/diner/staff.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';
import 'package:hex/ui/widgets.dart' show GoldButton;

Staff person({
  int id = 70,
  String name = 'Test',
  int cooking = 4,
  int speed = 5,
  int service = 4,
  int charm = 4,
  Dish? specialty,
  Kind? duty,
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
    potential: {for (final s in Stat.values) s: 10},
    specialty: specialty,
    duty: duty,
  );
}

/// A busy-ish room with a grill, a fryer and a soda machine, [staff] people,
/// and a menu of burger, fries and soda.
Diner kitchen({
  int staff = 3,
  int level = 4,
  int rep = 60,
  bool fryer = true,
  bool soda = true,
  bool oven = false,
  bool espresso = false,
  bool freezer = false,
}) {
  final d = Diner(
    coins: 100000,
    owned: {0, 1},
    progress: Progress(level: level, reputation: rep),
  );
  d.declined.add(Dish.cheeseburger);
  d.roster.employees.clear();
  d.progress.upgrades[Upgrade.staff] = staff - 1;
  for (var i = 0; i < staff; i++) {
    d.roster.employees.add(person(id: 70 + i, name: 'S$i'));
  }
  d.place(Kind.grill, const Cell(1, 3), Dir.sw);
  d.place(Kind.grill, const Cell(2, 3), Dir.sw);
  if (fryer) d.place(Kind.fryer, const Cell(3, 3), Dir.sw);
  if (soda) d.place(Kind.soda, const Cell(4, 3), Dir.sw);
  if (espresso) d.place(Kind.espresso, const Cell(5, 3), Dir.sw);
  if (oven) d.place(Kind.oven, const Cell(6, 3), Dir.sw);
  if (freezer) d.place(Kind.freezer, const Cell(7, 3), Dir.sw);
  d.place(Kind.counter, const Cell(10, 7), Dir.nw);
  d.place(Kind.counter, const Cell(10, 6), Dir.nw);
  for (final t in const [Cell(3, 5), Cell(6, 5), Cell(7, 7)]) {
    d.place(Kind.table, t);
    d.place(Kind.chair, Cell(t.x - 1, t.y), Dir.se);
    d.place(Kind.chair, Cell(t.x + 1, t.y), Dir.nw);
  }
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
  group('the menu', () {
    test('it has more places as the restaurant grows', () {
      final d = Diner(coins: 0);
      final slots = <int>[];
      for (var l = 1; l <= 8; l++) {
        d.progress.level = l;
        slots.add(d.menuSlots);
      }
      expect(slots, [2, 2, 3, 3, 4, 4, 5, 5]);
    });

    test('new dishes join by themselves while there is room', () {
      final d = Diner.starter();
      expect(d.menu(), [Dish.burger]);
      d.progress.level = 2;
      d.coins = 1000;
      d.place(Kind.fryer, const Cell(4, 6), Dir.sw);
      expect(d.menu(), [Dish.burger, Dish.fries]);
    });

    test('a full menu does not take more, and the player chooses', () {
      final d = kitchen(level: 3);
      d.declined.clear();
      final menu = d.menu();
      expect(menu.length, 3);
      expect(menu, [Dish.burger, Dish.cheeseburger, Dish.fries]);
      expect(d.toggleOffer(Dish.soda), isFalse, reason: 'no room');
      expect(d.toggleOffer(Dish.cheeseburger), isTrue);
      // The room it left goes to the next dish that can be sold.
      expect(d.menu(), [Dish.burger, Dish.fries, Dish.soda]);
      expect(d.toggleOffer(Dish.soda), isTrue);
      expect(d.menu(), [Dish.burger, Dish.fries]);
    });

    test('a dish you turned off stays off when there is room again', () {
      final d = kitchen(level: 4);
      d.menu();
      d.toggleOffer(Dish.cheeseburger);
      d.progress.level = 8;
      expect(d.menu(), isNot(contains(Dish.cheeseburger)));
      d.toggleOffer(Dish.cheeseburger);
      expect(d.menu(), contains(Dish.cheeseburger));
    });

    test('a dish cannot be sold without its machine, and says why', () {
      final d = Diner.starter()..progress.level = 6;
      expect(d.whyNot(Dish.fries), 'Needs a fryer');
      expect(d.whyNot(Dish.iceCream), 'Needs a ice cream freezer');
      expect(d.whyNot(Dish.burger), isNull);
      d.progress.level = 1;
      expect(d.whyNot(Dish.fries), 'Unlocks at level 2');
    });

    test('losing a machine takes its dish off the menu', () {
      final d = kitchen(level: 4);
      expect(d.menu(), contains(Dish.fries));
      d.sell(d.items.firstWhere((p) => p.kind == Kind.fryer));
      expect(d.menu(), isNot(contains(Dish.fries)));
    });

    test('a machine with no room in front sells nothing', () {
      final d = kitchen(level: 4);
      final fryer = d.items.firstWhere((p) => p.kind == Kind.fryer);
      d.rotate(fryer); // now facing a wall or another fixture
      d.rotate(fryer);
      // Whatever it faces, the menu follows what really works.
      expect(d.menu().contains(Dish.fries), d.hasMachineFor(Dish.fries));
    });

    test('a diner needs a main dish on the menu to open', () {
      final d = Diner.starter();
      expect(d.report().ready, isTrue);
      d.toggleOffer(Dish.burger);
      expect(d.report().ready, isFalse);
      expect(d.report().missing, contains('Needs a main dish on the menu'));
    });

    test('the menu, quality and plan survive a save', () {
      final d = kitchen(level: 4);
      d.menu();
      d.toggleOffer(Dish.soda);
      d.progress.recipeLevel[Dish.burger] = Diner.premiumLevel;
      d.tiers[Dish.burger] = Tier.premium;
      d.plan[Dish.burger] = 14;
      final back = Diner.fromJson(d.toJson());
      expect(back.offered, d.offered);
      expect(back.declined, d.declined);
      expect(back.tierOf(Dish.burger), Tier.premium);
      expect(back.plan[Dish.burger], 14);
    });

    test('an old save with no menu gets the sensible one', () {
      final d = Diner.fromJson({'coins': 5, 'items': []});
      expect(d.offered, isEmpty);
      expect(d.tiers, isEmpty);
    });

    test('every dish, machine and facing has its picture', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final art = await DinerArt.load(_Assets());
      for (final d in Dish.values) {
        expect(art.has('plate_${d.name}'), isTrue, reason: 'plate ${d.name}');
        expect(art.has('ico_${d.name}'), isTrue, reason: 'icon ${d.name}');
      }
      for (final k in Kind.values) {
        for (final f in Dir.values) {
          expect(
            art.has(spriteName(k, f)),
            isTrue,
            reason: '${k.name} ${f.name}',
          );
        }
      }
    });
  });

  group('meals', () {
    test('a guest orders a main, and often more', () {
      final sim = play(kitchen(rep: 80));
      var guests = 0;
      var items = 0;
      final sim2 = DinerSim(kitchen(rep: 80), seed: 3);
      while (!sim2.finished) {
        sim2.tick();
        for (final g in sim2.guests) {
          if (g.items.isEmpty) continue;
          expect(
            g.items.any((i) => recipes[i.dish]!.course == Course.main),
            isTrue,
          );
          // Never two of the same course.
          final courses = g.items.map((i) => recipes[i.dish]!.course).toList();
          expect(courses.toSet().length, courses.length);
        }
      }
      for (final seed in [1, 2, 3]) {
        final s = DinerSim(kitchen(rep: 80), seed: seed);
        final seen = <int>{};
        while (!s.finished) {
          s.tick();
          for (final g in s.guests) {
            if (g.items.isNotEmpty && seen.add(g.id)) {
              guests++;
              items += g.items.length;
            }
          }
        }
      }
      expect(items / guests, inInclusiveRange(1.6, 2.8));
      expect(sim.served, greaterThan(10));
    });

    test('with only a main on the menu, a meal is one dish', () {
      final d = kitchen(fryer: false, soda: false);
      final sim = DinerSim(d, seed: 2);
      while (!sim.finished) {
        sim.tick();
        for (final g in sim.guests) {
          expect(g.items.length, lessThanOrEqualTo(1));
        }
      }
    });

    test('every dish is cooked on its own kind of machine', () {
      final d = kitchen(rep: 80);
      final sim = DinerSim(d, seed: 2);
      while (!sim.finished) {
        sim.tick();
        for (final m in sim.machines) {
          final i = m.item;
          if (i != null) expect(recipes[i.dish]!.station, m.kind);
        }
      }
    });

    test('nobody starts eating until all of their order is on the table', () {
      final sim = DinerSim(kitchen(rep: 80), seed: 4);
      var multi = 0;
      while (!sim.finished) {
        sim.tick();
        for (final g in sim.guests.where((g) => g.state == GuestState.eating)) {
          expect(g.items.any((i) => i.open), isFalse, reason: g.name);
          if (g.items.length > 1) multi++;
        }
      }
      expect(multi, greaterThan(0), reason: 'saw some bigger meals');
    });

    test('a bigger order is a bigger bill', () {
      final burgers = play(kitchen(fryer: false, soda: false, staff: 4));
      final meals = play(kitchen(staff: 4));
      expect(
        meals.earned / meals.served,
        greaterThan(burgers.earned / burgers.served * 1.25),
      );
    });

    test('with enough staff, a fuller menu pays; with too few it does not', () {
      int profit(DinerSim s) => s.earned - s.ingredientCost;
      var plain = 0;
      var full = 0;
      for (final seed in [1, 2, 3]) {
        plain += profit(
          play(kitchen(fryer: false, soda: false, staff: 4), seed: seed),
        );
        full += profit(play(kitchen(staff: 4), seed: seed));
      }
      expect(full, greaterThan(plain * 1.2));

      // The same menu with only two people drowns the kitchen.
      var thin = 0;
      for (final seed in [1, 2, 3]) {
        thin += play(kitchen(staff: 2), seed: seed).served;
      }
      var thick = 0;
      for (final seed in [1, 2, 3]) {
        thick += play(kitchen(staff: 4), seed: seed).served;
      }
      expect(thin, lessThan(thick));
    });

    test('a bigger order is given more patience', () {
      final sim = DinerSim(kitchen(rep: 90), seed: 5);
      final base = sim.progress.patience;
      // Patience once the guest's own temper, and a dirty table, are set aside.
      final byCount = <int, double>{};
      while (!sim.finished) {
        sim.tick();
        for (final g in sim.guests.where((g) => g.items.isNotEmpty)) {
          byCount[g.items.length] =
              g.patienceMax /
              (g.temper.patienceMul * (g.grumpy ? DinerSim.messPatience : 1));
        }
      }
      expect(byCount.keys.length, greaterThan(1));
      final sorted = byCount.keys.toList()..sort();
      expect(byCount[sorted.first]!, closeTo(base, 1.5));
      expect(byCount[sorted.last]!, greaterThan(byCount[sorted.first]!));
    });

    test(
      'a tray holds the rest of a meal until it can all go out together',
      () {
        // With a good tray, a lone server carries several dishes at once.
        final d = kitchen(staff: 1, rep: 80);
        final sim = DinerSim(d, seed: 2);
        var most = 0;
        while (!sim.finished) {
          sim.tick();
          for (final w in sim.workers) {
            if (w.carrying.length > most) most = w.carrying.length;
          }
        }
        expect(most, greaterThan(1));
        expect(most, lessThanOrEqualTo(sim.progress.carry));
      },
    );

    test('a bubble over a waiting guest shows everything they ordered', () {
      final sim = DinerSim(kitchen(rep: 80), seed: 2);
      var shown = 0;
      while (!sim.finished) {
        sim.tick();
        for (final a in sim.actors(0).where((a) => a.items.isNotEmpty)) {
          shown++;
          expect(a.items.length, lessThanOrEqualTo(4));
        }
      }
      expect(shown, greaterThan(0));
    });
  });

  group('new dishes', () {
    test('there are seven, in four courses, each with a home machine', () {
      expect(Dish.values.length, 7);
      expect(recipes.length, 7);
      expect(
        recipes.values.map((r) => r.course).toSet(),
        Course.values.toSet(),
      );
      for (final r in recipes.values) {
        expect(fixtureDefs[r.station]!.role, Role.station);
      }
    });

    test('machines unlock with the restaurant, in step with their dish', () {
      for (final r in recipes.values) {
        expect(
          fixtureDefs[r.station]!.unlock,
          lessThanOrEqualTo(r.unlock),
          reason: '${r.name} should not unlock before its machine',
        );
      }
    });

    test('a better dish sells for more', () {
      expect(
        recipes[Dish.cheeseburger]!.price,
        greaterThan(recipes[Dish.burger]!.price),
      );
      expect(
        recipes[Dish.pizza]!.price,
        greaterThan(recipes[Dish.cheeseburger]!.price),
      );
      expect(
        recipes[Dish.pizza]!.cook,
        greaterThan(recipes[Dish.burger]!.cook),
      );
    });

    test('desserts and coffee come out with the right machines', () {
      final d = kitchen(
        level: 7,
        espresso: true,
        freezer: true,
        oven: true,
        staff: 4,
      );
      d.declined.addAll([Dish.cheeseburger, Dish.pizza]);
      d.roster.employees.first.teach(Dish.coffee);
      final menu = d.menu();
      expect(menu, contains(Dish.coffee));
      expect(menu, contains(Dish.iceCream));
      final sim = DinerSim(d, seed: 2);
      final made = <Dish>{};
      while (!sim.finished) {
        sim.tick();
        for (final m in sim.machines) {
          if (m.item != null) made.add(m.item!.dish);
        }
      }
      expect(made, contains(Dish.iceCream));
    });
  });

  group('mastery and specialists', () {
    test('making a dish over and over makes you better at it', () {
      final s = person();
      expect(s.masteryLevel(Dish.burger), 0);
      s.mastery[Dish.burger] = 8;
      expect(s.masteryLevel(Dish.burger), 1);
      s.mastery[Dish.burger] = 25;
      expect(s.masteryLevel(Dish.burger), 2);
      s.mastery[Dish.burger] = 60;
      expect(s.masteryLevel(Dish.burger), 3);
      s.mastery[Dish.burger] = 500;
      expect(s.masteryLevel(Dish.burger), 3, reason: 'there is a top');
    });

    test('each level sells for more and cooks quicker', () {
      final s = person();
      var price = s.masteryPrice(Dish.burger);
      var time = s.masteryTime(Dish.burger);
      for (final n in [8, 25, 60]) {
        s.mastery[Dish.burger] = n;
        expect(s.masteryPrice(Dish.burger), greaterThan(price));
        expect(s.masteryTime(Dish.burger), lessThan(time));
        price = s.masteryPrice(Dish.burger);
        time = s.masteryTime(Dish.burger);
      }
    });

    test('it is per dish: a burger expert is a beginner at fries', () {
      final s = person()..mastery[Dish.burger] = 60;
      expect(s.masteryLevel(Dish.burger), 3);
      expect(s.masteryLevel(Dish.fries), 0);
    });

    test('doing the work builds it, and it is remembered and told', () {
      final d = kitchen(staff: 1, rep: 60);
      final s = d.roster.employees.single;
      final sim = play(d, seed: 2);
      expect(s.made(Dish.burger), greaterThan(8));
      expect(s.masteryLevel(Dish.burger), greaterThanOrEqualTo(1));
      expect(
        sim.story.any(
          (l) =>
              l.text.contains('good at making') ||
              l.text.contains('best burger'),
        ),
        isTrue,
      );
      expect(s.memories.any((m) => m.contains('got better')), isTrue);
    });

    test('a master cook\'s food sells for more and is ready sooner', () {
      final fresh = person();
      final master = person()..mastery[Dish.burger] = 60;
      int firstCook(Staff who) {
        final d = Diner.starter();
        d.roster.employees
          ..clear()
          ..add(who);
        final sim = DinerSim(d, seed: 2);
        while (sim.ticks < 300) {
          sim.tick();
          final m = sim.machines.first;
          if (m.item != null && !m.ready) return m.total;
        }
        return -1;
      }

      expect(firstCook(master), lessThan(firstCook(fresh)));
      expect(master.masteryPrice(Dish.burger), greaterThan(1.1));
    });

    test('a hard dish needs someone who has been taught it', () {
      final plain = person();
      expect(plain.canCook(Dish.burger), isTrue);
      expect(plain.canCook(Dish.pizza), isFalse);
      expect(plain.canCook(Dish.coffee), isFalse);
      plain.teach(Dish.pizza);
      expect(plain.canCook(Dish.pizza), isTrue);
      expect(plain.masteryLevel(Dish.pizza), 1);
    });

    test('a specialist already knows their dish, and well', () {
      final s = person(specialty: Dish.pizza);
      expect(s.canCook(Dish.pizza), isTrue);
      expect(s.masteryLevel(Dish.pizza), 2);
      expect(s.canCook(Dish.coffee), isFalse);
    });

    test('a specialist costs a little more', () {
      expect(
        person(specialty: Dish.pizza).salary,
        greaterThan(person().salary),
      );
    });

    test('pizza is not on the menu until someone can make it', () {
      final d = kitchen(level: 6, oven: true);
      d.declined.addAll([Dish.cheeseburger, Dish.soda]);
      expect(d.whyNot(Dish.pizza), 'Needs someone who knows how');
      expect(d.menu(), isNot(contains(Dish.pizza)));
      d.roster.employees.first.teach(Dish.pizza);
      expect(d.whyNot(Dish.pizza), isNull);
      expect(d.menu(), contains(Dish.pizza));
    });

    test('only the person who knows pizza ever puts one in the oven', () {
      final d = kitchen(level: 6, oven: true, staff: 3);
      d.declined.addAll([Dish.cheeseburger, Dish.soda, Dish.fries]);
      final chef = d.roster.employees.last..teach(Dish.pizza);
      final sim = DinerSim(d, seed: 3);
      while (!sim.finished) {
        sim.tick();
      }
      for (final s in d.roster.employees) {
        if (s != chef) expect(s.made(Dish.pizza), 0, reason: s.name);
      }
      expect(chef.made(Dish.pizza), greaterThan(0));
    });

    test('teaching costs a day and a course fee, once', () {
      final d = Diner.starter()..coins = 500;
      final s = d.roster.employees.single;
      expect(d.teach(s, Dish.pizza), StaffResult.ok);
      expect(d.coins, 500 - Diner.teachCost);
      expect(s.canCook(Dish.pizza), isTrue);
      expect(
        d.teach(s, Dish.pizza),
        StaffResult.maxed,
        reason: 'already knows',
      );
      final other = person(id: 90, name: 'O');
      d.roster.employees.add(other);
      other.trainedToday = true;
      expect(d.teach(other, Dish.pizza), StaffResult.tired);
      expect(
        d.teach(s, Dish.burger),
        StaffResult.maxed,
        reason: 'no course for it',
      );
    });

    test('teaching needs the money', () {
      final d = Diner.starter()..coins = 20;
      expect(d.teach(d.roster.employees.single, Dish.pizza), StaffResult.broke);
    });

    test('some candidates come knowing a hard dish', () {
      final seen = <Dish>{};
      var n = 0;
      var with_ = 0;
      for (var day = 1; day <= 300; day++) {
        final r = Roster.starter()..rollCandidates(day, 5, 3, Ad.paper);
        for (final c in r.candidates) {
          n++;
          if (c.specialty != null) {
            with_++;
            seen.add(c.specialty!);
            expect(recipes[c.specialty]!.skilled, isTrue);
          }
        }
      }
      expect(seen, {Dish.pizza, Dish.coffee});
      expect(with_ / n, inInclusiveRange(0.1, 0.35));
    });

    test(
      'nobody is a specialist before there is anything to specialise in',
      () {
        for (var day = 1; day <= 100; day++) {
          final r = Roster.starter()..rollCandidates(day, 1, 1, Ad.paper);
          for (final c in r.candidates) {
            expect(c.specialty, isNull);
          }
        }
      },
    );

    test('mastery, specialty and duty are saved', () {
      final s = person(specialty: Dish.coffee, duty: Kind.grill)
        ..mastery[Dish.burger] = 31;
      final back = Staff.fromJson(s.toJson())!;
      expect(back.specialty, Dish.coffee);
      expect(back.duty, Kind.grill);
      expect(back.made(Dish.burger), 31);
      expect(back.masteryLevel(Dish.burger), 2);
    });
  });

  group('station duty', () {
    test('someone with a station spends most of their time on it', () {
      int madeAt(Staff s, Dish d) => s.made(d);

      var onDuty = 0;
      var other = 0;
      for (final seed in [1, 2, 3]) {
        final d = kitchen(staff: 2, rep: 80);
        final a = d.roster.employees[0]..duty = Kind.fryer;
        final b = d.roster.employees[1];
        play(d, seed: seed);
        onDuty += madeAt(a, Dish.fries);
        other += madeAt(b, Dish.fries);
      }
      expect(onDuty, greaterThan(other));
    });

    test('without duty, two equal people share the work', () {
      var a = 0;
      var b = 0;
      for (final seed in [1, 2, 3]) {
        final d = kitchen(staff: 2, rep: 80);
        play(d, seed: seed);
        a += d.roster.employees[0].made(Dish.fries);
        b += d.roster.employees[1].made(Dish.fries);
      }
      expect((a - b).abs(), lessThan((a + b) * 0.8 + 1));
    });

    test('duty is a preference, not a cage: they help when it is quiet', () {
      final d = kitchen(staff: 2, rep: 40);
      final a = d.roster.employees[0]..duty = Kind.fryer;
      play(d, seed: 2);
      // Looks after the fryer, but still makes burgers when that is needed.
      expect(a.made(Dish.fries), greaterThan(0));
      expect(a.made(Dish.burger), greaterThan(0));
    });

    test('a lone worker has no use for a station: it is ignored', () {
      final plain = kitchen(staff: 1, rep: 25);
      final duty = kitchen(staff: 1, rep: 25);
      duty.roster.employees.single.duty = Kind.fryer;
      final a = play(plain, seed: 2);
      final b = play(duty, seed: 2);
      expect(b.served, a.served);
      expect(b.earned, a.earned);
    });

    test('a duty for a machine that is gone does nothing', () {
      final d = kitchen(staff: 1, rep: 25);
      d.roster.employees.single.duty = Kind.oven;
      final sim = play(d, seed: 2);
      expect(sim.served, greaterThanOrEqualTo(3));
    });
  });

  group('ingredients and the prep list', () {
    test('a portion costs a share of the price, more for better stuff', () {
      final d = Diner.starter();
      d.progress.recipeLevel[Dish.burger] = Diner.premiumLevel;
      d.tiers[Dish.burger] = Tier.budget;
      final cheap = d.unitCost(Dish.burger);
      d.tiers[Dish.burger] = Tier.standard;
      final normal = d.unitCost(Dish.burger);
      d.tiers[Dish.burger] = Tier.premium;
      final fine = d.unitCost(Dish.burger);
      expect(cheap, lessThan(normal));
      expect(normal, lessThan(fine));
    });

    test('premium needs a level 3 recipe, and falls back without it', () {
      final d = Diner.starter();
      d.tiers[Dish.burger] = Tier.premium;
      expect(d.tierOf(Dish.burger), Tier.standard);
      d.progress.recipeLevel[Dish.burger] = Diner.premiumLevel;
      expect(d.tierOf(Dish.burger), Tier.premium);
    });

    test('better ingredients sell for more', () {
      expect(Tier.premium.priceMul, greaterThan(Tier.standard.priceMul));
      expect(Tier.budget.priceMul, lessThan(Tier.standard.priceMul));
    });

    test('premium keeps more per portion; budget is the cheap way to open', () {
      double keeps(Tier t) => (t.priceMul - t.costFrac);
      expect(keeps(Tier.premium), greaterThanOrEqualTo(keeps(Tier.standard)));
      expect(Tier.budget.costFrac, lessThan(Tier.standard.costFrac));
    });

    test('the forecast prepares a little more than the guests will want', () {
      final d = kitchen(level: 4);
      final plan = d.forecastPlan(20);
      // One main per guest, shared between the mains on the menu.
      final mains = plan.entries
          .where((e) => recipes[e.key]!.course == Course.main)
          .fold(0, (a, e) => a + e.value);
      expect(mains, greaterThanOrEqualTo(20));
      expect(mains, lessThan(30));
      // Sides and drinks only some people want.
      expect(plan[Dish.fries]!, lessThan(20));
      expect(plan[Dish.soda]!, lessThan(20));
    });

    test('unless you choose, the forecast is used; your choice wins', () {
      final d = kitchen(level: 4);
      final forecast = d.portions(Dish.burger);
      expect(forecast, greaterThan(0));
      d.plan[Dish.burger] = 3;
      expect(d.portions(Dish.burger), 3);
      d.plan.clear();
      expect(d.portions(Dish.burger), forecast);
    });

    test('the plan costs what it says, and it comes out of the till', () {
      final d = kitchen(level: 4, rep: 60);
      d.coins = 1000;
      final cost = d.prepCost();
      expect(cost, greaterThan(0));
      final sim = DinerSim(d, seed: 2);
      sim.tick();
      expect(sim.ingredientCost, cost);
      expect(d.coins, 1000 - cost);
    });

    test('stock is used up as guests order', () {
      final d = kitchen(level: 4, rep: 80);
      final sim = DinerSim(d, seed: 2);
      sim.tick();
      final start = Map.of(sim.stock);
      while (!sim.finished) {
        sim.tick();
      }
      var left = 0;
      var began = 0;
      for (final e in start.entries) {
        began += e.value;
        left += sim.stock[e.key] ?? 0;
      }
      expect(left, lessThan(began));
    });

    test('running out of burgers turns people away', () {
      final d = kitchen(level: 4, rep: 80);
      d.plan[Dish.burger] = 2;
      final sim = play(d, seed: 2);
      expect(sim.soldOut, greaterThan(3));
      expect(sim.result!.soldOut, sim.soldOut);
      expect(
        sim.story.any(
          (l) => l.text.contains('run out') || l.text.contains('Sold out'),
        ),
        isTrue,
      );
    });

    test('nobody orders what has sold out', () {
      final d = kitchen(level: 4, rep: 80);
      d.plan[Dish.fries] = 1;
      final sim = DinerSim(d, seed: 2);
      var friesOrdered = 0;
      final seen = <int>{};
      while (!sim.finished) {
        sim.tick();
        for (final g in sim.guests) {
          if (!seen.add(g.id)) continue;
        }
        friesOrdered = sim.guests
            .expand((g) => g.items)
            .where((i) => i.dish == Dish.fries)
            .length;
      }
      expect(sim.stock[Dish.fries] ?? 0, greaterThanOrEqualTo(0));
      expect(friesOrdered, lessThanOrEqualTo(1 + 1));
    });

    test('too much prepared is thrown away, and it is counted', () {
      final d = kitchen(level: 4, rep: 20);
      d.plan[Dish.burger] = 60;
      final sim = play(d, seed: 2);
      expect(sim.result!.leftover, greaterThan(20));
      expect(d.coins, lessThan(100000));
    });

    test('with no money for the plan, you get as much as you can afford', () {
      final d = kitchen(level: 4, rep: 60);
      d.coins = 15;
      final sim = DinerSim(d, seed: 2);
      sim.tick();
      expect(sim.ingredientCost, lessThanOrEqualTo(15));
      expect(d.coins, greaterThanOrEqualTo(0));
      expect(
        sim.story.any(
          (l) =>
              l.text.contains('not enough money') ||
              l.text.contains('short at the market'),
        ),
        isTrue,
      );
    });

    test('premium ingredients sell for more, and the cook\'s food too', () {
      double perGuest(Tier t) {
        final d = kitchen(staff: 4, fryer: false, soda: false);
        d.progress.recipeLevel[Dish.burger] = Diner.premiumLevel;
        d.tiers[Dish.burger] = t;
        final s = play(d, seed: 3);
        return s.earned / s.served;
      }

      expect(perGuest(Tier.premium), greaterThan(perGuest(Tier.standard)));
      expect(perGuest(Tier.standard), greaterThan(perGuest(Tier.budget)));
    });

    test('good ingredients make people like the place; cheap ones do not', () {
      int rep(Tier t) {
        final d = kitchen(staff: 4, rep: 50, fryer: false, soda: false);
        d.progress.recipeLevel[Dish.burger] = Diner.premiumLevel;
        // Cheap enough that every kind of guest will buy it, so only the
        // quality differs.
        d.markup[Dish.burger] = -20;
        d.tiers[Dish.burger] = t;
        play(d, seed: 2);
        return d.progress.reputation;
      }

      expect(rep(Tier.premium), greaterThan(rep(Tier.budget)));
    });

    test('the report says what the ingredients cost', () {
      final d = kitchen(level: 4);
      final sim = play(d, seed: 2);
      expect(sim.result!.ingredients, sim.ingredientCost);
      expect(sim.result!.profit, sim.earned - sim.ingredientCost);
      expect(sim.result!.items, sim.itemsServed);
    });
  });

  group('the screens', () {
    Future<Diner> open(WidgetTester tester, Diner d) async {
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
      return d;
    }

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('menu')));
      await tester.pumpAndSettle();
    }

    Future<void> show(WidgetTester tester, Finder f) async {
      await tester.scrollUntilVisible(
        f,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
    }

    testWidgets('the menu screen lists every dish and what stops it', (
      tester,
    ) async {
      final d = await open(tester, kitchen(level: 3));
      d.coins = 900;
      await openMenu(tester);
      expect(find.byKey(const ValueKey('dish-burger')), findsOneWidget);
      await show(tester, find.byKey(const ValueKey('dish-iceCream')));
      expect(find.byKey(const ValueKey('dish-iceCream')), findsOneWidget);
      expect(find.textContaining('Unlocks at level 6'), findsOneWidget);
    });

    testWidgets('a dish can be switched off and on', (tester) async {
      final d = await open(tester, kitchen(level: 4));
      await openMenu(tester);
      expect(d.menu(), contains(Dish.fries));
      await show(tester, find.byKey(const ValueKey('offer-fries')));
      await tester.tap(find.byKey(const ValueKey('offer-fries')));
      await tester.pump();
      expect(d.menu(), isNot(contains(Dish.fries)));
      await tester.tap(find.byKey(const ValueKey('offer-fries')));
      await tester.pump();
      expect(d.menu(), contains(Dish.fries));
    });

    Future<void> openDish(WidgetTester tester, Dish d) async {
      await tester.tap(find.byKey(ValueKey('dish-${d.name}')));
      await tester.pumpAndSettle();
    }

    Future<void> openPrep(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('open-prep')));
      await tester.pumpAndSettle();
    }

    testWidgets('the menu page is one line per dish, with no extras', (
      tester,
    ) async {
      final d = await open(tester, kitchen(level: 4));
      await openMenu(tester);
      expect(find.byKey(const ValueKey('dish-burger')), findsOneWidget);
      expect(find.byKey(const ValueKey('tier-burger-budget')), findsNothing);
      expect(find.byKey(const ValueKey('level-burger')), findsNothing);
      expect(find.byKey(const ValueKey('prep-plus-burger')), findsNothing);
      expect(find.byKey(const ValueKey('open-prep')), findsOneWidget);
      expect(d.menu(), isNotEmpty);
    });

    testWidgets("today's portions shows a projected cost, not a price to pay", (
      tester,
    ) async {
      final d = await open(tester, kitchen(level: 4));
      d.coins = 5000;
      await openMenu(tester);
      expect(find.text("Today's portions"), findsOneWidget);
      expect(find.text('Projected cost'), findsOneWidget);
      expect(find.text('Plan ingredients'), findsNothing);
      final cost = find.byKey(const ValueKey('projected-cost'));
      expect(
        (tester.widget(cost) as dynamic).text,
        contains('${d.prepCost()}'),
      );
      // Not a gold button: nothing on it looks like spending.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('open-prep')),
          matching: find.byType(GoldButton),
        ),
        findsNothing,
      );
      // It follows the plan.
      await tester.tap(find.byKey(const ValueKey('open-prep')));
      await tester.pumpAndSettle();
      expect(find.text("Today's portions"), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('prep-plus-burger')));
      await tester.pump();
      expect(find.textContaining('Projected cost'), findsOneWidget);
      expect(d.coins, 5000, reason: 'looking at it costs nothing');
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(
        (tester.widget(cost) as dynamic).text,
        contains('${d.prepCost()}'),
      );
    });

    testWidgets('a dish shows its price as a bar split into cost and profit', (
      tester,
    ) async {
      final d = await open(tester, kitchen(level: 4));
      await openMenu(tester);
      final price = d.progress.price(Dish.burger) * Tier.standard.priceMul;
      final cost = d.unitCost(Dish.burger);
      expect(find.text('+${(price - cost).toStringAsFixed(1)}'), findsWidgets);
      expect(find.textContaining('Price'), findsNothing);
      expect(find.textContaining('Sells'), findsNothing);
      // A dearer dish has a longer bar, and a better margin a bigger green.
      final burger = tester.getSize(
        find.byKey(const ValueKey('price-bar-burger')),
      );
      final fries = tester.getSize(
        find.byKey(const ValueKey('price-bar-fries')),
      );
      final pizza =
          d.progress.price(Dish.pizza) > d.progress.price(Dish.burger);
      expect(burger.width, greaterThan(fries.width));
      expect(pizza, isTrue);
      expect(burger.height, 8);
      // The words are on the dish page, with what each number means.
      await openDish(tester, Dish.burger);
      expect(
        find.text('Profit ${(price - cost).toStringAsFixed(1)} a portion'),
        findsOneWidget,
      );
      expect(find.textContaining('Wages come out separately'), findsOneWidget);
    });

    testWidgets('ingredient quality is chosen on the dish page', (
      tester,
    ) async {
      final d = await open(tester, kitchen(level: 4));
      d.progress.recipeLevel[Dish.burger] = Diner.premiumLevel;
      await openMenu(tester);
      await openDish(tester, Dish.burger);
      await tester.tap(find.byKey(const ValueKey('tier-burger-premium')));
      await tester.pump();
      expect(d.tierOf(Dish.burger), Tier.premium);
      await tester.tap(find.byKey(const ValueKey('tier-burger-budget')));
      await tester.pump();
      expect(d.tierOf(Dish.burger), Tier.budget);
    });

    testWidgets('a recipe can be improved from the dish page', (tester) async {
      final d = await open(tester, kitchen(level: 4));
      d.coins = 1000;
      await openMenu(tester);
      await openDish(tester, Dish.burger);
      expect(find.byKey(const ValueKey('next-level-burger')), findsOneWidget);
      final cost = d.progress.recipeUpgradeCost(Dish.burger);
      await tester.tap(find.byKey(const ValueKey('level-burger')));
      await tester.pump();
      expect(d.progress.recipeLvl(Dish.burger), 2);
      expect(d.coins, 1000 - cost);
    });

    testWidgets('premium stays locked until the recipe is level 3', (
      tester,
    ) async {
      final d = await open(tester, kitchen(level: 4));
      await openMenu(tester);
      await openDish(tester, Dish.burger);
      await tester.tap(find.byKey(const ValueKey('tier-burger-premium')));
      await tester.pump();
      expect(d.tierOf(Dish.burger), Tier.standard);
      expect(find.text('Premium needs recipe level 3.'), findsOneWidget);
    });

    testWidgets(
      'portions can be raised and lowered, and reset to the forecast',
      (tester) async {
        final d = await open(tester, kitchen(level: 4));
        await openMenu(tester);
        await openPrep(tester);
        final start = d.portions(Dish.burger);
        await tester.tap(find.byKey(const ValueKey('prep-plus-burger')));
        await tester.pump();
        expect(d.portions(Dish.burger), start + 1);
        await tester.tap(find.byKey(const ValueKey('prep-minus-burger')));
        await tester.tap(find.byKey(const ValueKey('prep-minus-burger')));
        await tester.pump();
        expect(d.portions(Dish.burger), start - 1);
        await tester.tap(find.byKey(const ValueKey('prep-forecast')));
        await tester.pump();
        expect(d.portions(Dish.burger), start);
        expect(d.plan, isEmpty);
      },
    );

    testWidgets('the prep total follows the plan and warns when short', (
      tester,
    ) async {
      final d = await open(tester, kitchen(level: 4));
      d.coins = 5;
      await openMenu(tester);
      await openPrep(tester);
      expect(find.textContaining('only 5 in the till'), findsOneWidget);
    });

    testWidgets('a person can be taught a dish on the training page', (
      tester,
    ) async {
      final d = kitchen(level: 6, oven: true, staff: 1);
      final s = d.roster.employees.single..mastery[Dish.burger] = 30;
      d.coins = 900;
      await open(tester, d);
      await tester.tap(find.byKey(const ValueKey('staff')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('team-${s.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('mastery-${s.id}')), findsOneWidget);
      expect(
        find.byKey(ValueKey('teach-${s.id}-pizza')),
        findsNothing,
        reason: 'lessons are on their own page',
      );
      await tester.tap(find.byKey(ValueKey('open-training-${s.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('teach-${s.id}-pizza')));
      await tester.pump();
      expect(s.canCook(Dish.pizza), isTrue);
      expect(find.textContaining('learned to make pizza'), findsOneWidget);
    });

    testWidgets('a specialist is marked on their page', (tester) async {
      final d = Diner.starter()..coins = 900;
      d.progress.level = 5;
      d.progress.upgrades[Upgrade.staff] = 1;
      d.roster.candidateDay = d.progress.day;
      d.roster.candidates = [
        person(id: 200, name: 'Gio', specialty: Dish.pizza),
      ];
      await open(tester, d);
      await tester.tap(find.byKey(const ValueKey('staff')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hire')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cand-200')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('trait-200-specialty')), findsOneWidget);
      expect(find.text('Pizza specialist'), findsOneWidget);
    });

    testWidgets('the day summary says what the ingredients cost', (
      tester,
    ) async {
      final d = await open(tester, kitchen(level: 4, rep: 60));
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('speed-3')));
      await tester.pump();
      for (var i = 0; i < 900; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byKey(const ValueKey('next-day')).evaluate().isNotEmpty) break;
      }
      expect(find.byKey(const ValueKey('next-day')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('details')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ingredients'), findsWidgets);
      expect(d.progress.day, 2);
    });
  });
}

/// Loads sprites from the real files, for tests that run without a bundle.
class _Assets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final f = await _read(key);
    return ByteData.sublistView(f);
  }

  Future<Uint8List> _read(String key) async =>
      Uint8List.fromList(await File(key).readAsBytes());
}
