import 'dart:math' as math;

import 'actor.dart';
import 'diner.dart';
import 'nav.dart';

/// How long things take, in ticks (see [TickClock]).
abstract final class Pace {
  /// Seconds per tick.
  static const tickSeconds = 0.4;

  /// A new customer every this many ticks while there is a free seat.
  static const spawnEvery = 10;
  static const cook = 6;
  static const eat = 14;

  /// Coins paid for one meal.
  static const price = 8;
}

class Person {
  Person(this.cell) : prev = cell;

  Cell cell;
  Cell prev;
  List<Cell> path = [];

  /// Steps taken so far, to alternate walking frames.
  int walked = 0;

  /// Which way they are facing.
  Dir dir = Dir.sw;

  void face(Cell target) => dir = Dir.between(cell, target) ?? dir;

  /// Takes one step along [path]. False if there is nowhere to go.
  bool step() {
    prev = cell;
    if (path.isEmpty) return false;
    cell = path.removeAt(0);
    dir = Dir.between(prev, cell) ?? dir;
    walked++;
    return true;
  }
}

enum CustomerState { toSeat, waiting, eating, toPay, leaving }

class Customer extends Person {
  Customer(this.id, this.sprite, this.seat, Cell start) : super(start);

  final int id;
  final String sprite;
  Seat seat;
  CustomerState state = CustomerState.toSeat;
  int timer = 0;

  /// The chef is already on this order.
  bool claimed = false;
  bool gone = false;
}

enum ChefState { idle, toGrill, cooking, toTable }

class Chef extends Person {
  Chef(super.cell);

  ChefState state = ChefState.idle;
  Customer? order;
  int timer = 0;
}

/// A coin rising off a paying customer.
class Pop {
  Pop(this.cell);

  final Cell cell;
  int age = 0;
}

/// Runs the restaurant: customers arrive, sit, wait, eat, pay and leave, and
/// the chef cooks for whoever is waiting. Advances in whole ticks and never
/// looks at the clock, so it can be fast-forwarded.
class DinerSim {
  DinerSim(this.diner, {int seed = 1})
    : rng = math.Random(seed),
      chef = Chef(diner.entrance) {
    layoutChanged();
    final spot = nearest(diner, chef.cell, _grillSpots());
    if (spot != null) chef.cell = chef.prev = spot.$1;
  }

  final Diner diner;
  final math.Random rng;
  final Chef chef;
  final List<Customer> customers = [];
  final List<Pop> pops = [];

  int ticks = 0;

  /// Meals served and paid for.
  int meals = 0;

  int _nextId = 1;
  late Report report;
  late List<Seat> seats;

  static const _looks = [
    'cust_a',
    'cust_b',
    'cust_c',
    'cust_d',
    'cust_e',
    'cust_f',
  ];

  Iterable<Cell> _grillSpots() => [
    for (final c in diner.cellsOf(Kind.grill)) ...diner.approaches(c),
  ];

  Iterable<Cell> _counterSpots() => [
    for (final c in diner.cellsOf(Kind.counter)) ...diner.approaches(c),
  ];

  /// Whether anyone is walking between cells, or a coin is rising, so frames
  /// between ticks still change.
  bool get animating =>
      chef.prev != chef.cell ||
      pops.isNotEmpty ||
      customers.any((c) => c.prev != c.cell);

  /// Whether anyone is standing on [c] (so it can't be built on).
  bool occupied(Cell c) =>
      chef.cell == c || customers.any((p) => p.cell == c && !p.gone);

  bool _reserved(Seat s) => customers.any(
    (c) =>
        c.seat.cell == s.cell &&
        (c.state == CustomerState.toSeat ||
            c.state == CustomerState.waiting ||
            c.state == CustomerState.eating),
  );

  void tick() {
    ticks++;
    for (final p in pops) {
      p.age++;
    }
    pops.removeWhere((p) => p.age > 4);

    if (report.ready && ticks % Pace.spawnEvery == 0) _spawn();
    for (final c in customers) {
      _customer(c);
    }
    customers.removeWhere((c) => c.gone);
    _cook();
  }

  void _spawn() {
    final free = [
      for (final s in seats)
        if (!_reserved(s)) s,
    ];
    if (free.isEmpty) return;
    final seat = free[rng.nextInt(free.length)];
    final way = route(diner, diner.street, seat.cell);
    if (way == null) return;
    // Prefer a look nobody in the room has.
    final unused = [
      for (final l in _looks)
        if (!customers.any((c) => c.sprite == l)) l,
    ];
    final pool = unused.isEmpty ? _looks : unused;
    customers.add(
      Customer(_nextId++, pool[rng.nextInt(pool.length)], seat, diner.street)
        ..path = way,
    );
  }

  void _customer(Customer c) {
    switch (c.state) {
      case CustomerState.toSeat:
        c.step();
        if (c.cell == c.seat.cell) {
          c.state = CustomerState.waiting;
          c.face(c.seat.table);
        }
      case CustomerState.waiting:
        c.prev = c.cell;
      case CustomerState.eating:
        c.prev = c.cell;
        if (--c.timer <= 0) _toPay(c);
      case CustomerState.toPay:
        c.step();
        if (c.path.isEmpty) {
          diner.coins += Pace.price;
          meals++;
          pops.add(Pop(c.cell));
          _leave(c);
        }
      case CustomerState.leaving:
        c.step();
        if (c.cell == diner.street && c.path.isEmpty) c.gone = true;
    }
  }

  void _toPay(Customer c) {
    final spot = nearest(diner, c.cell, _counterSpots());
    if (spot == null) {
      _leave(c);
      return;
    }
    c.path = spot.$2;
    c.state = CustomerState.toPay;
  }

  void _leave(Customer c) {
    c.claimed = false;
    c.state = CustomerState.leaving;
    final way = route(diner, c.cell, diner.street);
    if (way == null) {
      c.cell = c.prev = diner.street;
      c.gone = true;
      return;
    }
    c.path = way;
  }

  void _cook() {
    switch (chef.state) {
      case ChefState.idle:
        chef.prev = chef.cell;
        final next = customers
            .where((c) => c.state == CustomerState.waiting && !c.claimed)
            .firstOrNull;
        if (next == null) return;
        final spot = nearest(diner, chef.cell, _grillSpots());
        if (spot == null) return;
        next.claimed = true;
        chef
          ..order = next
          ..path = spot.$2
          ..state = ChefState.toGrill;
      case ChefState.toGrill:
        chef.step();
        if (chef.path.isEmpty) {
          for (final g in diner.cellsOf(Kind.grill)) {
            chef.face(g);
          }
          chef
            ..state = ChefState.cooking
            ..timer = Pace.cook;
        }
      case ChefState.cooking:
        chef.prev = chef.cell;
        if (--chef.timer > 0) return;
        final order = chef.order;
        final spot = order == null || order.gone
            ? null
            : nearest(diner, chef.cell, diner.approaches(order.seat.cell));
        if (spot == null) {
          _chefIdle();
          return;
        }
        chef
          ..path = spot.$2
          ..state = ChefState.toTable;
      case ChefState.toTable:
        chef.step();
        if (chef.path.isNotEmpty) return;
        final order = chef.order;
        if (order != null) chef.face(order.seat.cell);
        if (order != null &&
            !order.gone &&
            order.state == CustomerState.waiting) {
          order
            ..state = CustomerState.eating
            ..timer = Pace.eat;
        }
        _chefIdle();
    }
  }

  void _chefIdle() {
    chef
      ..order = null
      ..path = []
      ..state = ChefState.idle;
  }

  /// Call after the layout changes. Re-checks the layout and re-routes
  /// everyone, sending customers home if their seat has gone.
  void layoutChanged() {
    report = diner.report();
    seats = diner.seats();
    for (final c in customers) {
      final seatOk = seats.any((s) => s.cell == c.seat.cell);
      switch (c.state) {
        case CustomerState.toSeat:
        case CustomerState.waiting:
        case CustomerState.eating:
          if (!seatOk) {
            _leave(c);
          } else if (c.state == CustomerState.toSeat) {
            final way = route(diner, c.cell, c.seat.cell);
            way == null ? _leave(c) : c.path = way;
          }
        case CustomerState.toPay:
          _toPay(c);
        case CustomerState.leaving:
          _leave(c);
      }
    }
    customers.removeWhere((c) => c.gone);
    for (final c in customers) {
      c.claimed = false;
    }
    _chefIdle();
    if (!diner.walkable(chef.cell)) {
      final spot = nearest(diner, diner.entrance, _grillSpots());
      chef.cell = chef.prev = spot?.$1 ?? diner.entrance;
    }
  }

  /// Everything to draw this frame, [alpha] of the way through the tick.
  List<Actor> actors(double alpha) {
    final out = <Actor>[];

    Actor person(
      Person p,
      String sprite, {
      String? badge,
      bool seated = false,
    }) {
      final moved = p.prev != p.cell;
      final t = moved ? alpha : 1.0;
      final x = p.prev.x + (p.cell.x - p.prev.x) * t + 0.5;
      final y = p.prev.y + (p.cell.y - p.prev.y) * t + 0.5;
      final walking = moved || p.path.isNotEmpty;
      final frame = seated
          ? 'sit'
          : walking
          ? '${p.walked % 4}'
          : ((ticks ~/ 3).isOdd ? 's1' : 's0');
      return Actor(
        sprite,
        x,
        y,
        dir: p.dir,
        frame: frame,
        // Sitting: on the cushion, in front of the chair but behind whoever
        // stands in the next cell along.
        lift: seated ? 11 : 0,
        row: seated ? p.cell.x + p.cell.y + 0.5 : x + y,
        badge: badge,
      );
    }

    out.add(person(chef, 'chef'));
    for (final c in customers) {
      final seated =
          c.state == CustomerState.waiting || c.state == CustomerState.eating;
      out.add(
        person(
          c,
          c.sprite,
          seated: seated,
          badge: c.state == CustomerState.waiting ? 'bubble' : null,
        ),
      );
      if (c.state == CustomerState.eating) {
        final t = c.seat.table;
        out.add(
          Actor('plate', t.x + 0.5, t.y + 0.5, lift: 12, row: t.x + t.y + 0.5),
        );
      }
    }
    for (final p in pops) {
      out.add(
        Actor(
          'coin',
          p.cell.x + 0.5,
          p.cell.y + 0.5,
          lift: 18 + p.age * 4.0,
          row: 999,
        ),
      );
    }
    return out;
  }
}
