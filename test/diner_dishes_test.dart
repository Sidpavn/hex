// The fast-food dishes added to the menu: hot dogs, onion rings, a chicken
// sandwich, nuggets, a milkshake, a bacon double and a sundae.
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/diner/service.dart';
import 'package:hex/diner/staff.dart';

const fastFood = [
  Dish.hotDog,
  Dish.onionRings,
  Dish.chickenSandwich,
  Dish.nuggets,
  Dish.milkshake,
  Dish.baconBurger,
  Dish.sundae,
];

/// A kitchen with every machine, where only [dish] is on offer.
Diner serving(Dish dish) {
  final d = Diner(
    coins: 100000,
    owned: {0, 1},
    progress: Progress(level: 10, reputation: 70, day: 3),
  );
  d.roster.employees.clear();
  d.progress.upgrades[Upgrade.staff] = 2;
  for (var i = 0; i < 3; i++) {
    d.roster.employees.add(
      Staff(
        id: 70 + i,
        name: 'S$i',
        stats: {Stat.cooking: 6, Stat.speed: 6, Stat.service: 6, Stat.charm: 5},
        potential: {for (final s in Stat.values) s: 10},
      ),
    );
  }
  for (final s in d.roster.employees) {
    s.teach(Dish.baconBurger);
  }
  d.place(Kind.grill, const Cell(1, 3), Dir.sw);
  d.place(Kind.grill, const Cell(2, 3), Dir.sw);
  d.place(Kind.fryer, const Cell(3, 3), Dir.sw);
  d.place(Kind.fryer, const Cell(4, 3), Dir.sw);
  d.place(Kind.freezer, const Cell(5, 3), Dir.sw);
  d.place(Kind.counter, const Cell(10, 7), Dir.nw);
  d.place(Kind.counter, const Cell(10, 6), Dir.nw);
  for (final t in const [Cell(3, 5), Cell(6, 5), Cell(7, 7), Cell(9, 5)]) {
    d.place(Kind.table, t);
    d.place(Kind.chair, Cell(t.x - 1, t.y), Dir.se);
    d.place(Kind.chair, Cell(t.x + 1, t.y), Dir.nw);
  }
  d.declined.addAll([
    for (final x in Dish.values)
      if (x != dish) x,
  ]);
  d.menu();
  return d;
}

void main() {
  group('the new dishes', () {
    test('seven more, all fast food, all with a machine to cook them', () {
      for (final d in fastFood) {
        final r = recipes[d]!;
        expect(r.name, isNotEmpty);
        expect(
          const [Kind.grill, Kind.fryer, Kind.freezer],
          contains(r.station),
          reason: r.name,
        );
        expect(fixtureDefs[r.station]!.unlock, lessThanOrEqualTo(r.unlock));
      }
    });

    test('they arrive one level at a time, from level 2 to 9', () {
      final levels = [for (final d in fastFood) recipes[d]!.unlock]..sort();
      expect(levels, [2, 4, 5, 6, 7, 8, 9]);
    });

    test('a hot dog is cheaper than a burger, a bacon double the dearest', () {
      expect(
        recipes[Dish.hotDog]!.price,
        greaterThan(recipes[Dish.burger]!.price),
      );
      expect(
        recipes[Dish.hotDog]!.price,
        lessThan(recipes[Dish.cheeseburger]!.price),
      );
      for (final d in fastFood) {
        if (d == Dish.baconBurger) continue;
        expect(
          recipes[Dish.baconBurger]!.price,
          greaterThan(recipes[d]!.price),
          reason: '${recipes[d]!.name} should be cheaper than bacon burger',
        );
      }
      expect(recipes[Dish.baconBurger]!.skilled, isTrue);
    });

    test('there are mains, sides, drinks and desserts among them', () {
      final courses = {for (final d in fastFood) recipes[d]!.course};
      expect(courses, Course.values.toSet());
      expect(recipes[Dish.chickenSandwich]!.course, Course.main);
      expect(recipes[Dish.milkshake]!.course, Course.drink);
      expect(recipes[Dish.sundae]!.course, Course.dessert);
    });

    test(
      'each has a picture on a plate and a small one for order bubbles',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        final art = await DinerArt.load();
        for (final d in Dish.values) {
          expect(art.sprite('plate_${d.name}').blank, isFalse, reason: d.name);
          expect(art.sprite('ico_${d.name}').blank, isFalse, reason: d.name);
        }
      },
    );

    test('they are saved and loaded like the rest', () {
      final d = serving(Dish.nuggets);
      d.progress.recipeLevel[Dish.sundae] = 2;
      d.special = Dish.hotDog;
      d.tiers[Dish.milkshake] = Tier.budget;
      final back = Diner.fromJson(d.toJson());
      expect(back.progress.recipeLvl(Dish.sundae), 2);
      expect(back.tiers[Dish.milkshake], Tier.budget);
    });
  });

  group('serving them', () {
    for (final dish in fastFood) {
      test('${recipes[dish]!.name} is cooked and sold', () {
        final d = serving(dish);
        final sim = DinerSim(d, seed: 2);
        while (!sim.finished && sim.ticks < 2500) {
          sim.tick();
        }
        final crowd = sim.result!.crowd!;
        if (recipes[dish]!.course == Course.main) {
          expect(crowd.ofDish(dish).served, greaterThan(3), reason: dish.name);
        } else {
          // A side, drink or dessert is only ordered with a main: with none on
          // the menu a guest has nothing to start with, so it sells nothing.
          expect(crowd.ofDish(dish).served, 0);
        }
      });
    }

    test('a side or a drink sells beside a main', () {
      for (final side in [
        Dish.onionRings,
        Dish.nuggets,
        Dish.milkshake,
        Dish.sundae,
      ]) {
        final d = serving(side);
        d.declined.remove(Dish.burger);
        d.menu();
        final sim = DinerSim(d, seed: 3);
        while (!sim.finished && sim.ticks < 2500) {
          sim.tick();
        }
        expect(
          sim.result!.crowd!.ofDish(side).served,
          greaterThan(0),
          reason: side.name,
        );
      }
    });

    test('the bacon double needs someone taught it', () {
      final d = serving(Dish.baconBurger);
      for (final s in d.roster.employees) {
        s.mastery.remove(Dish.baconBurger);
      }
      expect(d.whyNot(Dish.baconBurger), 'Needs someone who knows how');
      d.roster.employees.first.teach(Dish.baconBurger);
      expect(d.whyNot(Dish.baconBurger), isNull);
    });

    test('a chicken sandwich wants a fryer, not a grill', () {
      final d = serving(Dish.chickenSandwich);
      d.items.removeWhere((p) => p.kind == Kind.fryer);
      expect(d.whyNot(Dish.chickenSandwich), 'Needs a fryer');
      expect(d.whyNot(Dish.hotDog), isNull);
    });
  });
}
