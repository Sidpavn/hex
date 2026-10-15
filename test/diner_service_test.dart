import 'package:flutter_test/flutter_test.dart';
import 'package:hex/diner/clock.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/service.dart';

const _l = Diner.left;
const _t = Diner.top;

void main() {
  group('layout report', () {
    test('the starter diner can open', () {
      final r = Diner.starter().report();
      expect(r.ready, isTrue);
      expect(r.seats, 2);
      expect(r.problems, isEmpty);
    });

    test('an empty room says what it needs', () {
      final r = Diner(coins: 0).report();
      expect(r.ready, isFalse);
      expect(r.missing, [
        'Needs a grill',
        'Needs a counter',
        'Needs a chair beside a table',
      ]);
    });

    test('a table with no seat and a chair with no table are flagged', () {
      final d = Diner(coins: 500)
        ..place(Kind.table, const Cell(_l + 3, _t + 1))
        ..place(Kind.chair, const Cell(_l, _t + 3));
      final text = d.report().problems.map((p) => p.text).toList();
      expect(text, contains('Table has no seat'));
      expect(text, contains('Chair needs a table beside it'));
    });

    test('a chair walled in by furniture is boxed in', () {
      final d = Diner(coins: 500)
        ..place(Kind.chair, const Cell(_l, _t))
        ..place(Kind.table, const Cell(_l + 1, _t))
        ..place(Kind.counter, const Cell(_l, _t + 1));
      final text = d.report().problems.map((p) => p.text).toList();
      expect(text, contains('Chair is boxed in'));
      expect(d.report().seats, 0);
    });

    test('a grill with no free side is boxed in', () {
      final d = Diner(coins: 900)
        ..place(Kind.grill, const Cell(_l, _t))
        ..place(Kind.counter, const Cell(_l + 1, _t))
        ..place(Kind.counter, const Cell(_l, _t + 1));
      expect(
        d.report().problems.map((p) => p.text),
        contains('Grill is boxed in'),
      );
      expect(d.report().missing, contains('Needs a grill'));
    });

    test('a bench seats both cells when a table runs alongside', () {
      final d = Diner(coins: 900)
        ..place(Kind.bench, const Cell(_l, _t + 2))
        ..place(Kind.table, const Cell(_l, _t + 3))
        ..place(Kind.table, const Cell(_l + 1, _t + 3));
      expect(d.seats().length, 2);
    });
  });

  group('service', () {
    DinerSim run(Diner d, int ticks, {int seed = 1}) {
      final sim = DinerSim(d, seed: seed);
      for (var i = 0; i < ticks; i++) {
        sim.tick();
      }
      return sim;
    }

    test('customers sit, eat, pay and leave, and the diner earns', () {
      final d = Diner.starter();
      final before = d.coins;
      final sim = run(d, 600);
      expect(sim.meals, greaterThan(5));
      expect(d.coins, before + sim.meals * Pace.price);
      expect(sim.customers.length, lessThanOrEqualTo(sim.seats.length + 1));
    });

    test('customers in the room look different from each other', () {
      final d = Diner.starter();
      final sim = DinerSim(d, seed: 3);
      for (var i = 0; i < 400; i++) {
        sim.tick();
        final looks = sim.customers.map((c) => c.sprite).toList();
        expect(looks.toSet().length, looks.length, reason: 'tick $i');
      }
    });

    test('same seed, same day', () {
      final a = run(Diner.starter(), 400, seed: 5);
      final b = run(Diner.starter(), 400, seed: 5);
      expect(a.meals, b.meals);
      expect(a.customers.map((c) => c.cell), b.customers.map((c) => c.cell));
    });

    test('a closed diner gets no customers', () {
      final d = Diner(coins: 100)..place(Kind.grill, const Cell(_l, _t));
      final sim = run(d, 200);
      expect(sim.customers, isEmpty);
      expect(sim.meals, 0);
    });

    test('nobody ever stands inside a fixture', () {
      final d = Diner.starter();
      final sim = DinerSim(d);
      for (var i = 0; i < 500; i++) {
        sim.tick();
        for (final p in [sim.chef, ...sim.customers]) {
          final ok =
              d.walkable(p.cell) ||
              p.cell == d.street ||
              sim.customers.any(
                (c) =>
                    c.cell == p.cell && sim.seats.any((s) => s.cell == p.cell),
              );
          expect(ok, isTrue, reason: 'tick $i: ${p.cell}');
        }
      }
    });

    test('selling a seat sends its customer home unpaid', () {
      final d = Diner.starter();
      final sim = DinerSim(d);
      while (!sim.customers.any((c) => c.state == CustomerState.waiting)) {
        sim.tick();
      }
      final guest = sim.customers.firstWhere(
        (c) => c.state == CustomerState.waiting,
      );
      final seatCell = guest.seat.cell;
      final paid = d.coins;
      d.sell(d.objectAt(seatCell)!);
      sim.layoutChanged();
      expect(guest.state, CustomerState.leaving);
      for (var i = 0; i < 40 && !guest.gone; i++) {
        sim.tick();
      }
      expect(guest.gone, isTrue);
      expect(d.coins, paid + 5, reason: 'only the half-price refund');
    });

    test('someone standing on a cell is reported so it cannot be built on', () {
      final d = Diner.starter();
      final sim = DinerSim(d);
      expect(sim.occupied(sim.chef.cell), isTrue);
      expect(sim.occupied(const Cell(_l + 4, _t + 3)), isFalse);
    });

    test('losing the grill stops new orders being cooked', () {
      final d = Diner.starter();
      final sim = DinerSim(d);
      d.sell(d.objectAt(const Cell(_l, _t))!);
      sim.layoutChanged();
      expect(sim.report.ready, isFalse);
      final before = sim.customers.length;
      for (var i = 0; i < 60; i++) {
        sim.tick();
      }
      expect(sim.customers.length, lessThanOrEqualTo(before));
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
