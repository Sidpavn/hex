import 'dart:math' as math;

import 'actor.dart';
import 'bank.dart';
import 'crowd.dart';
import 'diner.dart';
import 'events.dart';
import 'guests.dart';
import 'nav.dart';
import 'recipes.dart';
import 'staff.dart';
import 'traits.dart';

/// How long things take, in ticks (see [TickClock]).
abstract final class Pace {
  /// Seconds per tick.
  static const tickSeconds = 0.4;

  /// How long the diner takes new guests: two minutes.
  static const dayTicks = 300;

  /// After closing, guests still in the room get this long to finish.
  static const lastCall = 150;

  /// How many guests the player can rush in a day, and how much quicker a
  /// rushed guest's food is cooked.
  static const rushPerDay = 2;
  static const rushSpeed = 0.7;

  /// Ticks a guest spends eating.
  static const eat = 14;
}

/// How one person's morale changed when wages were paid.
class MoodChange {
  const MoodChange(this.name, this.before, this.after);

  final String name;
  final int before;
  final int after;

  bool get better => after > before;
  bool get worse => after < before;
}

/// One thing that happened today, told as a sentence.
class StoryLine {
  const StoryLine(this.tick, this.text, this.tone);

  final int tick;
  final String text;

  /// Good news, bad news, or just colour.
  final Tone tone;
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

  /// The cell passed through this tick when a quick walker takes two steps,
  /// so the move is drawn along the real path.
  Cell? mid;

  void face(Cell target) => dir = Dir.between(cell, target) ?? dir;

  /// Takes one step along [path]. False if there is nowhere to go.
  bool step() {
    prev = cell;
    mid = null;
    if (path.isEmpty) return false;
    cell = path.removeAt(0);
    dir = Dir.between(prev, cell) ?? dir;
    walked++;
    return true;
  }
}

enum GuestState {
  /// Walking along the pavement to their place in the queue. They have not
  /// started waiting yet.
  arriving,

  /// In the queue outside the door. Patience runs down.
  queued,
  toSeat,

  /// Seated, order in. Patience runs down.
  waiting,
  eating,
  toPay,
  paying,
  leaving,
}

/// Where one item of a meal has got to.
enum ItemState {
  /// Ordered, waiting for someone to start it.
  pending,

  /// Someone is on their way to put it on a machine.
  claimed,
  cooking,
  ready,

  /// On a tray, on its way to the table.
  carried,
  delivered,

  /// Dropped, thrown away, or its guest has gone.
  lost,
}

/// One dish in a guest's order. A meal is a few of these, each cooked on its
/// own machine and carried to the table.
class OrderItem {
  OrderItem(this.guest, this.dish, this.tier);

  final Guest guest;
  final Dish dish;
  final Tier tier;
  ItemState state = ItemState.pending;

  /// What the guest will pay for it, as a multiple of the menu price: the
  /// cook's skill and mastery, and the ingredients.
  double quality = 1;

  bool get open => state != ItemState.delivered && state != ItemState.lost;
}

class Guest extends Person {
  Guest(
    this.id,
    this.sprite,
    this.patienceMax,
    super.start, {
    this.name = 'A guest',
  }) : patience = patienceMax;

  final int id;
  final String name;
  final String sprite;

  /// How much they will pay, and how long they will wait.
  Wallet wallet = Wallet.regular;
  Temper temper = Temper.steady;
  int patienceMax;
  int patience;
  GuestState state = GuestState.arriving;

  /// What they ordered, once they have sat down.
  final List<OrderItem> items = [];

  /// Their place in the queue, 0 at the door.
  int slot = -1;

  /// Walking past: they saw the queue and carried on.
  bool passerby = false;

  /// The player has told the kitchen to see to this guest first.
  bool rushed = false;

  /// They had to sit at a table nobody had cleared.
  bool grumpy = false;

  /// The food critic, who is here to judge the place.
  bool critic = false;

  /// The food blogger, who is here to see whether it is worth the money.
  bool blogger = false;

  /// Who they are, for the books.
  Gender gender = Gender.man;

  /// Whether they have been counted among those fed or those missed.
  bool tallied = false;

  /// The tick they turned up.
  int arrived = 0;

  /// Someone whose visit moves the rating.
  bool get reviewer => critic || blogger;

  /// Arrived by car and is served at the takeaway window.
  bool car = false;
  Seat? seat;
  CounterState? counter;
  int timer = 0;
  bool gone = false;
  bool angry = false;

  /// Part of a patience point not yet lost.
  double drainAcc = 0;

  /// Ticks spent from sitting down to being served.
  int waited = 0;
  int tip = 0;

  /// The tip before rounding to whole coins.
  double tipExact = 0;

  /// How much patience is left, 0 to 1.
  double get mood => patience / patienceMax;

  bool get inQueue => state == GuestState.queued;

  /// Every item is either on the table or has been written off.
  bool get mealComplete => items.isNotEmpty && items.every((i) => !i.open);

  Iterable<OrderItem> get unfinished => items.where((i) => i.open);

  /// Items that are waiting for someone to start them.
  Iterable<OrderItem> get toStart =>
      items.where((i) => i.state == ItemState.pending);
}

/// A cooker: it makes one dish at a time, on its own, once loaded.
class Machine {
  Machine(this.at);

  final Placed at;
  Kind get kind => at.kind;
  OrderItem? item;
  int left = 0;

  /// How long the current item takes, for the progress bar.
  int total = 1;
  bool ready = false;

  /// A member of staff is on their way to use it.
  bool claimed = false;

  bool get free => item == null && !claimed;
}

class CounterState {
  CounterState(this.at);

  final Placed at;
  final List<Guest> line = [];
  int timer = 0;
}

enum WorkState { idle, toPickup, toLoad, toDeliver, toClean, toRest, resting }

class Worker extends Person {
  Worker(this.staff, super.cell);

  final Staff staff;
  final List<OrderItem> carrying = [];
  WorkState state = WorkState.idle;
  Machine? machine;

  /// The item they are on their way to put on a machine.
  OrderItem? loading;

  /// The guest they are carrying food to.
  Guest? target;

  /// The seat they are on their way to clear.
  Seat? cleaning;

  /// How much they have left in them, 0 to 100. Work wears it down, a rest in
  /// the staff room builds it back, and below [tired] they slow down.
  double energy = 100;
  static const tired = 40.0;
  bool get isTired => energy < tired;

  /// Ticks left on whatever they are doing with their hands.
  int busy = 0;

  /// A little picture over their head for a few ticks after something happens.
  String? emote;
  int emoteLeft = 0;

  /// Teammates who help everyone along, as a multiple of their pace.
  double paceMul = 1;

  /// Plates served today.
  int platesToday = 0;

  void feel(String what, [int ticks = 8]) {
    emote = what;
    emoteLeft = ticks;
  }

  /// Part of a tile walked but not yet stepped, and part of a tick of
  /// handling not yet spent.
  double _walkAcc = 0;
  double _handleAcc = 0;

  /// Kitchen people wear whites; floor staff, an apron.
  String get sprite => staff.kitchen ? 'chef' : 'waiter';

  /// Walks along [path] at their own pace: a slow walker misses a tick now
  /// and then, a quick one sometimes takes two steps.
  bool walk() {
    final start = cell;
    mid = null;
    _walkAcc += staff.pace * paceMul * (isTired ? 0.85 : 1);
    var steps = _walkAcc.floor().clamp(0, 2);
    _walkAcc -= steps;
    var moved = false;
    var taken = 0;
    while (steps-- > 0 && path.isNotEmpty) {
      final from = cell;
      cell = path.removeAt(0);
      dir = Dir.between(from, cell) ?? dir;
      walked++;
      taken++;
      moved = true;
      if (taken == 1) mid = cell;
    }
    if (taken < 2) mid = null;
    prev = start;
    return moved;
  }

  /// Ticks to spend handling a plate now.
  int takeHandling() {
    _handleAcc += staff.handlingTicks / (isTired ? 0.85 : 1);
    final n = _handleAcc.floor();
    _handleAcc -= n;
    return n;
  }
}

/// A coin rising off a paying guest.
class Pop {
  Pop(this.cell);

  final Cell cell;
  int age = 0;
}

/// How a day went.
class DayReport {
  const DayReport({
    required this.day,
    required this.served,
    required this.walkouts,
    required this.earned,
    required this.tips,
    required this.wasted,
    required this.avgWait,
    required this.stars,
    required this.xp,
    required this.levelsGained,
    required this.reputation,
    required this.reputationBefore,
    required this.tomorrow,
    required this.wages,
    required this.unpaid,
    required this.quit,
    required this.story,
    required this.moods,
    this.ingredients = 0,
    this.leftover = 0,
    this.soldOut = 0,
    this.tooDear = 0,
    this.cleaned = 0,
    this.event = DayEvent.none,
    this.reviewDelta = 0,
    this.gaveUp = 0,
    this.queueFull = 0,
    this.spoiled = 0,
    this.crowd,
    this.loanPaid = 0,
    this.loanMissed = false,
    this.cars = 0,
    this.items = 0,
  });

  final int day;
  final int served;

  /// Guests who gave up and left, including those who couldn't get in.
  final int walkouts;
  final int earned;
  final int tips;

  /// Meals cooked for guests who had gone.
  final int wasted;

  /// Seconds from sitting down to being served.
  final double avgWait;
  final int stars;
  final int xp;
  final int levelsGained;

  /// Reputation after the day, and before it.
  final int reputation;
  final int reputationBefore;

  /// How many guests to expect tomorrow at the new rating.
  final int tomorrow;

  /// Wages paid out, and wages that could not be paid.
  final int wages;
  final int unpaid;

  /// People who left because they went unpaid.
  final List<String> quit;

  /// What happened, in order.
  final List<StoryLine> story;

  /// How each person's mood moved overnight.
  final List<MoodChange> moods;

  /// What the day's ingredients cost, what was left over and thrown away, how
  /// many guests were turned away because a dish had sold out, and how many
  /// dishes were served.
  final int ingredients;
  final int leftover;
  final int soldOut;
  final int tooDear;

  /// Tables cleared, by hand or by staff.
  final int cleaned;

  /// What was special about the day, and what a critic did to the rating.
  final DayEvent event;
  final int reviewDelta;

  /// Guests who gave up waiting, guests who walked past a full queue, and
  /// portions that arrived spoiled.
  final int gaveUp;
  final int queueFull;
  final int spoiled;

  /// Who came, by kind, and what they bought.
  final Crowd? crowd;

  /// What the bank took tonight, and whether it went without.
  final int loanPaid;
  final bool loanMissed;

  /// How many of those served came by car, to the window.
  final int cars;
  final int items;

  /// What the day made after the ingredients.
  int get profit => earned - ingredients;

  /// The lines worth telling: a mix of the bad news, the good and the colour,
  /// so a rough day still has something to smile about. Told in the order they
  /// happened.
  List<StoryLine> highlights([int n = 4]) {
    final groups = [
      for (final t in [Tone.bad, Tone.good, Tone.mixed])
        story.where((l) => l.tone == t).toList(),
    ];
    final picked = <StoryLine>[];
    for (var i = 0; picked.length < n; i++) {
      var any = false;
      for (final g in groups) {
        if (i < g.length && picked.length < n) {
          picked.add(g[i]);
          any = true;
        }
      }
      if (!any) break;
    }
    return picked..sort((a, b) => a.tick.compareTo(b.tick));
  }
}

/// Runs one day at the restaurant: guests arrive, queue, sit, order, wait,
/// eat, pay and leave, while staff cook and carry. Advances in whole ticks
/// and never looks at the clock, so it can be fast-forwarded.
class DinerSim {
  DinerSim(this.diner, {int? seed})
    : rng = math.Random(seed ?? diner.progress.day) {
    layoutChanged();
  }

  final Diner diner;
  final math.Random rng;
  final List<Worker> workers = [];
  final List<Guest> guests = [];
  final List<Machine> machines = [];
  final List<CounterState> counters = [];
  final List<Pop> pops = [];
  final List<Guest> _queue = [];

  /// Cars waiting for the window, the one at the window first.
  final List<Guest> _cars = [];

  Progress get progress => diner.progress;

  int ticks = 0;

  /// The ticks at which guests turn up today, worked out when the day starts.
  late final List<int> arrivalSchedule = _plan();
  int _next = 0;
  int _nextId = 1;

  /// When cars turn up, if there is a window to serve them from. They use
  /// their own random stream, so a day without a window is unchanged.
  late final List<int> carSchedule = _carPlan();

  /// Guests' wallets and tempers come from their own stream, so they never
  /// change who turns up or when.
  late final math.Random _traitRng = math.Random(progress.day * 211 + 5);

  /// Gives [g] their wallet and temper.
  /// Genders come from a stream of their own, so who turns up is the same
  /// whatever else changes about the day.
  late final math.Random _genderRng = math.Random(progress.day * 257 + 11);

  /// What happened with each kind of guest, today.
  final Crowd crowd = Crowd();

  /// Which eighth of opening hours [g] arrived in.
  int _hourOf(Guest g) => (g.arrived * Crowd.slots / Pace.dayTicks)
      .floor()
      .clamp(0, Crowd.slots - 1);

  /// Counts [g] among those who left without being fed, once.
  void _missed(Guest g) {
    if (g.tallied) return;
    g.tallied = true;
    crowd.missed(g.gender, g.wallet, hour: _hourOf(g));
  }

  void _rollGuest(Guest g) {
    g.wallet = Wallet.roll(progress.rating, _traitRng.nextDouble());
    g.temper = Temper.roll(_traitRng.nextDouble());
    if (event.thriftyShift > 0 && _traitRng.nextDouble() < event.thriftyShift) {
      g.wallet = Wallet.thrifty;
    }
    g.patienceMax = (g.patienceMax * g.temper.patienceMul).round();
    g.patience = g.patienceMax;
  }

  late final math.Random _carRng = math.Random(progress.day * 131 + 17);
  int _nextCar = 0;
  int carsServed = 0;

  // What happened today.
  int served = 0;
  int walkouts = 0;

  /// How many of those lost their patience, rather than never getting in.
  int gaveUp = 0;

  /// Guests who walked past because the queue was out of the door, and
  /// portions lost to a poor delivery.
  int queueFull = 0;
  int spoiled = 0;
  int earned = 0;
  int tips = 0;
  int wasted = 0;
  int _waitTotal = 0;
  int xp = 0;

  /// Portions of each dish left to sell, bought at the start of the day.
  final Map<Dish, int> stock = {};

  /// What the day's ingredients cost, and how many guests asked for something
  /// that had sold out.
  int ingredientCost = 0;
  int soldOut = 0;

  /// What is special about today, which shapes who turns up and what things
  /// cost.
  late final DayEvent event = diner.today;

  /// What the critic's visit did to the rating, and whether they have come.
  int reviewDelta = 0;
  bool _reviewSent = false;
  late final int _reviewTick =
      (Pace.dayTicks *
              (0.40 + 0.20 * math.Random(progress.day * 17).nextDouble()))
          .round();

  /// Seats where a guest has eaten and left, and nobody has cleared yet. Guests
  /// take a clean seat when there is one; someone who has to sit at a dirty one
  /// is put out: they wait less patiently and tip less.
  final Set<Cell> dirty = {};

  /// For each seat, what the decor near it does to waiting and to tips.
  final Map<Cell, double> _drainAt = {};
  final Map<Cell, double> _tipAt = {};

  /// How much patience and tip a guest keeps when their table is dirty.
  static const messPatience = 0.65;
  static const messTip = 0.5;

  /// Seats cleared today, by the player's hand or by staff.
  int cleaned = 0;

  /// Clears the mess at [c], if [c] is a dirty seat or the table it is at.
  /// Returns how many seats were cleared.
  int cleanAt(Cell c) {
    var n = 0;
    for (final s in seats) {
      if ((s.cell == c || s.table == c) && dirty.remove(s.cell)) n++;
    }
    cleaned += n;
    return n;
  }

  /// Whether [w] is kept for clearing tables rather than cooking or serving.
  bool _isCleaner(Worker w) =>
      w.staff.duty == Kind.table && diner.ofRole(Role.table).isNotEmpty;

  /// How many more guests can be rushed today.
  int rushLeft = Pace.rushPerDay;

  /// The guest standing at [c], if anyone is: the one nearest the viewer when
  /// several overlap.
  Guest? guestAt(Cell c) {
    Guest? best;
    for (final g in guests) {
      if (g.gone || g.cell != c) continue;
      if (best == null || g.cell.x + g.cell.y >= best.cell.x + best.cell.y) {
        best = g;
      }
    }
    return best;
  }

  /// Whether [g] can be rushed now: still waiting for food, not already
  /// rushed, and there is a rush left.
  bool canRush(Guest g) =>
      rushLeft > 0 &&
      !g.rushed &&
      !g.gone &&
      g.state == GuestState.waiting &&
      g.items.any((i) => i.open);

  /// Tells the kitchen to see to [g] first: their dishes are started before
  /// anyone else's, collected and carried out first, and cook quicker. Costs
  /// one of the day's rushes.
  bool rush(Guest g) {
    if (!canRush(g)) return false;
    rushLeft--;
    g.rushed = true;
    for (final m in machines) {
      final item = m.item;
      if (item != null && item.guest == g && !m.ready) {
        m.left = math.max(1, (m.left * Pace.rushSpeed).round());
      }
    }
    _tell(
      _say([
        'Rushing {a}\'s order.',
        '{a} is first in line for the kitchen now.',
      ], a: g.name),
      Tone.mixed,
      key: 'rush',
      limit: 4,
    );
    return true;
  }

  /// Guests who left because the food cost more than they would pay.
  int tooDear = 0;

  /// Dishes served, and the ingredient quality of them, for the rating.
  int itemsServed = 0;
  int _tierPoints = 0;

  /// The day is over and the report is ready.
  bool finished = false;
  DayReport? result;

  late Report report;
  late List<Seat> seats;

  /// How much slower guests tire of waiting, from the team's charm.
  double _calm = 0;
  double get calmness => _calm;

  // ---------------------------------------------------------- the story

  /// What happened today, as sentences, in order.
  final List<StoryLine> story = [];

  /// Story wording is chosen from its own stream, so telling the tale never
  /// changes how the day plays out.
  late final math.Random _tales = math.Random(
    (diner.progress.day * 31 + 7) ^ (diner.roster.employees.length * 977),
  );
  final Map<String, int> _told = {};

  /// The most recent line, while it is still news.
  StoryLine? get ticker {
    if (story.isEmpty) return null;
    final last = story.last;
    return ticks - last.tick <= 30 ? last : null;
  }

  /// Picks one of [lines], filling in {a} and {b}.
  String _say(
    List<String> lines, {
    String a = '',
    String b = '',
    String c = '',
  }) => lines[_tales.nextInt(lines.length)]
      .replaceAll('{a}', a)
      .replaceAll('{b}', b)
      .replaceAll('{c}', c);

  /// Records [text]. [key] limits how many times a kind of thing is told in
  /// one day, so a busy day does not drown in repeats.
  void _tell(
    String text,
    Tone tone, {
    String? key,
    int limit = 1,
    Staff? about,
    String? memory,
  }) {
    if (key != null) {
      final n = _told[key] ?? 0;
      if (n >= limit) return;
      _told[key] = n + 1;
    }
    story.add(StoryLine(ticks, text, tone));
    if (about != null && memory != null) {
      about.remember(diner.progress.day, memory);
    }
  }

  late List<Dish> menu;

  /// Whether the doors are open to new guests.
  bool get open => ticks < Pace.dayTicks;

  /// How far through opening hours, 0 to 1.
  double get dayProgress => (ticks / Pace.dayTicks).clamp(0.0, 1.0);

  /// How many guests have turned up so far.
  int get arrived => _nextId - 1;

  /// Plans the day's arrivals. How many come depends on the rating alone, so
  /// a new place is quiet and a famous one is packed whatever its size.
  /// They bunch up at lunch and dinner rather than trickling in.
  List<int> _plan() {
    final n =
        (progress.expectedGuests *
                event.guestMul *
                diner.specialLift *
                (0.85 + 0.3 * rng.nextDouble()))
            .round()
            .clamp(1, 80);
    double normal() {
      final u = 1 - rng.nextDouble();
      final v = rng.nextDouble();
      return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
    }

    final last = Pace.dayTicks - 25;
    final times = <int>[];
    for (var i = 0; i < n; i++) {
      final r = rng.nextDouble();
      final double t;
      if (r < 0.3) {
        t = rng.nextDouble() * last;
      } else {
        final peak = r < 0.65 ? 0.3 : 0.72;
        t = (peak + normal() * 0.07) * Pace.dayTicks;
      }
      times.add(t.round().clamp(2, last));
    }
    // A lunch rush: a bunch of extra guests all at once around midday, from a
    // stream of their own so the usual arrivals are the same either way.
    if (event.peakShare > 0) {
      final r = math.Random(progress.day * 41 + 3);
      final extra = (n * event.peakShare).round().clamp(2, 30);
      for (var i = 0; i < extra; i++) {
        final u = 1 - r.nextDouble();
        final v = r.nextDouble();
        final z = math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
        times.add(((0.45 + z * 0.04) * Pace.dayTicks).round().clamp(2, last));
      }
    }
    return times..sort();
  }

  /// Whether anyone is walking between cells, or a coin is rising, so frames
  /// between ticks still change.
  bool get animating =>
      pops.isNotEmpty ||
      workers.any((w) => w.prev != w.cell) ||
      guests.any((g) => g.prev != g.cell);

  /// Whether anyone is standing on [c] (so it can't be built on).
  bool occupied(Cell c) =>
      workers.any((w) => w.cell == c) || guests.any((g) => g.cell == c);

  /// Rebuilds everything that depends on the layout. Call after any edit,
  /// and when the sim is first made.
  void layoutChanged() {
    report = diner.report();
    seats = diner.seats();
    _drainAt
      ..clear()
      ..addAll({for (final s in seats) s.cell: diner.drainAt(s.cell)});
    _tipAt
      ..clear()
      ..addAll({for (final s in seats) s.cell: diner.tipAt(s.cell)});
    final team = diner.roster.employees;
    _calm = team.isEmpty
        ? 0
        : (team.fold(0.0, (a, s) => a + s.calm) / team.length).clamp(-0.1, 0.3);
    menu = diner.menu();
    machines
      ..clear()
      ..addAll([
        for (final p in diner.ofRole(Role.station))
          if (diner.useCells(p).isNotEmpty) Machine(p),
      ]);
    counters
      ..clear()
      ..addAll([
        for (final p in diner.ofRole(Role.counter))
          if (diner.useCells(p).isNotEmpty) CounterState(p),
      ]);
    guests.clear();
    _queue.clear();
    // Staff start at the first machine, or just inside the door.
    workers.clear();
    final spots = [for (final m in machines) ...diner.useCells(m.at)];
    for (var i = 0; i < diner.roster.employees.length; i++) {
      final spot = spots.isEmpty ? diner.entrance : spots[i % spots.length];
      workers.add(Worker(diner.roster.employees[i], spot));
    }
    // Team players help everyone else along.
    final helpers = diner.roster.employees.where(
      (e) => e.has(Trait.teamPlayer),
    );
    for (final w in workers) {
      final others = helpers.where((h) => h != w.staff).length;
      w.paceMul = 1 + 0.05 * others;
    }
  }

  void tick() {
    if (finished) return;
    ticks++;
    for (final p in pops) {
      p.age++;
    }
    pops.removeWhere((p) => p.age > 4);

    for (final w in workers) {
      if (w.emoteLeft > 0 && --w.emoteLeft == 0) w.emote = null;
    }
    if (ticks == 1) {
      _opening();
      _buyStock();
    }
    if (open && report.ready) _arrivals();
    _seating();
    _lane();
    for (final g in guests) {
      _guest(g);
    }
    _machines();
    _checkout();
    for (final w in workers) {
      _work(w);
    }
    guests.removeWhere((g) => g.gone);
    _queue.removeWhere(
      (g) =>
          g.gone ||
          (g.state != GuestState.queued && g.state != GuestState.arriving),
    );

    if (!open) _closing();
  }

  void _opening() {
    final helper = workers
        .where((w) => w.staff.has(Trait.teamPlayer))
        .firstOrNull;
    if (helper != null && workers.length > 1) {
      _tell(
        _say([
          '{a} has everyone moving a little quicker.',
          '{a} is the reason the team keeps in step.',
        ], a: helper.staff.name),
        Tone.mixed,
        key: 'team',
      );
    }
  }

  // ------------------------------------------------------------- arrivals

  void _arrivals() {
    while (_next < arrivalSchedule.length && arrivalSchedule[_next] <= ticks) {
      _next++;
      _arrive();
    }
    while (_nextCar < carSchedule.length && carSchedule[_nextCar] <= ticks) {
      _nextCar++;
      _arriveCar();
    }
    if (event.reviewed && !_reviewSent && ticks >= _reviewTick) {
      _reviewSent = true;
      _arrive(who: event);
    }
  }

  /// A drive-through brings a good share of extra custom, spread over the day
  /// like everyone else.
  List<int> _carPlan() {
    if (!diner.driveThrough) return const [];
    final n =
        (progress.expectedGuests *
                0.5 *
                event.carMul *
                (0.85 + 0.3 * _carRng.nextDouble()))
            .round()
            .clamp(1, 40);
    final last = Pace.dayTicks - 25;
    return [for (var i = 0; i < n; i++) 2 + _carRng.nextInt(last - 2)]..sort();
  }

  static const _carLooks = ['car_red', 'car_blue', 'car_sun'];

  /// The cells from [from] to [to]: along the main road, then up the side
  /// street to the window, or on up the line.
  List<Cell> _drive(Cell from, Cell to) {
    final out = <Cell>[];
    var c = from;
    if (c.x != to.x) {
      while (c.y < diner.laneRow) {
        c = Cell(c.x, c.y + 1);
        out.add(c);
      }
      while (c.x != to.x) {
        c = Cell(c.x + (to.x > c.x ? 1 : -1), c.y);
        out.add(c);
      }
    }
    while (c.y != to.y) {
      c = Cell(c.x, c.y + (to.y > c.y ? 1 : -1));
      out.add(c);
    }
    return out;
  }

  /// Off down the street from [from]. Leaving the window or the line, a car
  /// turns across into the other lane of the side street and goes back down
  /// it, so it never drives through the cars still waiting. Then it joins the
  /// far lane of the main road.
  List<Cell> _driveOff(Cell from) {
    final out = <Cell>[];
    var c = from;
    if (c.y < diner.laneRow) {
      if (c.x == diner.inLane) {
        c = Cell(diner.outLane, c.y);
        out.add(c);
      }
      while (c.y < diner.passRow) {
        c = Cell(c.x, c.y + 1);
        out.add(c);
      }
    } else if (c.y < diner.passRow) {
      c = Cell(c.x, c.y + 1);
      out.add(c);
    }
    while (c.x < diner.laneEnd.x) {
      c = Cell(c.x + 1, c.y);
      out.add(c);
    }
    return out;
  }

  /// Whether another car is standing on [c].
  bool _carAt(Cell c, Guest self) =>
      guests.any((o) => o.car && o != self && !o.gone && o.cell == c);

  /// One step along the road, unless something is in the way.
  void _carStep(Guest g) {
    if (g.path.isNotEmpty && _carAt(g.path.first, g)) {
      g
        ..prev = g.cell
        ..mid = null;
      return;
    }
    g.step();
  }

  void _arriveCar() {
    final gender = Gender.roll(_genderRng.nextDouble());
    final names = [
      for (final n in gender.names)
        if (!guests.any((g) => g.name == n)) n,
    ];
    final passing = _cars.length >= diner.carQueueLength;
    final start = passing ? diner.passStart : diner.laneStart;
    final g = Guest(
      _nextId++,
      _carLooks[_carRng.nextInt(_carLooks.length)],
      progress.patience,
      start,
      name: names.isEmpty ? 'A driver' : names[_carRng.nextInt(names.length)],
    )..car = true;
    g.gender = gender;
    g.arrived = ticks;
    _rollGuest(g);
    g.dir = Dir.se;
    guests.add(g);
    if (passing) {
      walkouts++;
      _missed(g);
      g
        ..passerby = true
        ..state = GuestState.leaving
        ..path = _driveOff(start);
      _tell(
        _say([
          '{a} saw the line of cars and drove on.',
          '{a} did not fancy waiting behind four cars.',
        ], a: g.name),
        Tone.bad,
        key: 'carpass',
      );
      return;
    }
    g
      ..slot = _cars.length
      ..seat = Seat(diner.operatorSpot!, diner.operatorSpot!, Dir.sw)
      ..path = _drive(start, diner.carSlot(g.slot));
    _cars.add(g);
  }

  /// Whether someone is at the window and free to take an order.
  bool get _windowManned => workers.any(
    (w) =>
        diner.operatorSpots.contains(w.cell) &&
        w.state == WorkState.idle &&
        w.busy == 0,
  );

  /// The car at the window that still has to give its order.
  Guest? get _carAwaitingOrder {
    final car = _cars.firstOrNull;
    if (car == null ||
        car.state != GuestState.queued ||
        car.slot != 0 ||
        car.path.isNotEmpty ||
        car.cell != diner.bay) {
      return null;
    }
    return car;
  }

  bool _isOperator(Worker w) =>
      diner.driveThrough && w.staff.duty == Kind.window;

  /// Cars shuffle up to the window as the one in front drives off. The one
  /// next in line waits until the bay is clear.
  void _lane() {
    _cars.removeWhere((g) => g.gone || g.state == GuestState.leaving);
    for (var i = 0; i < _cars.length; i++) {
      final g = _cars[i];
      final want = diner.carSlot(i);
      if (g.cell == want && g.path.isEmpty) {
        g.slot = i;
        continue;
      }
      if (g.slot == i && g.path.isNotEmpty) continue;
      if (i == 0 && _carAt(want, g)) continue;
      g.slot = i;
      g.path = _drive(g.cell, want);
    }
  }

  void _car(Guest g) {
    switch (g.state) {
      case GuestState.arriving:
        _carStep(g);
        if (g.path.isEmpty && g.cell == diner.carSlot(g.slot)) {
          g.state = GuestState.queued;
        }
      case GuestState.queued:
        _carStep(g);
        if (!_drain(g)) return;
        if (g.slot == 0 && g.path.isEmpty && g.cell == diner.bay) {
          if (_windowManned) {
            if (++g.timer >= 3) {
              g
                ..state = GuestState.waiting
                ..patience = g.patienceMax;
              _order(g);
            }
          }
        }
      case GuestState.waiting:
        g.prev = g.cell;
        g.waited++;
        _drain(g);
      case GuestState.leaving:
        _carStep(g);
        if (g.path.isEmpty) g.gone = true;
      default:
        g.prev = g.cell;
    }
  }

  void _arrive({DayEvent? who}) {
    final critic = who == DayEvent.critic;
    final blogger = who == DayEvent.blogger;
    // They come in from either end of the pavement, from off the screen.
    final fromLeft = rng.nextBool();
    final start = fromLeft ? diner.arrivalLeft : diner.arrivalRight;
    final gender = Gender.roll(_genderRng.nextDouble());
    final unused = [
      for (final l in gender.looks)
        if (!guests.any((g) => g.sprite == l)) l,
    ];
    final pool = unused.isEmpty ? gender.looks : unused;
    final names = [
      for (final n in gender.names)
        if (!guests.any((g) => g.name == n)) n,
    ];
    final g = Guest(
      _nextId++,
      critic
          ? 'cust_d'
          : blogger
          ? 'cust_c'
          : pool[rng.nextInt(pool.length)],
      progress.patience,
      start,
      name: critic
          ? 'The critic'
          : blogger
          ? 'The blogger'
          : names.isEmpty
          ? 'A guest'
          : names[rng.nextInt(names.length)],
    );
    g.gender = gender;
    g.arrived = ticks;
    _rollGuest(g);
    if (critic || blogger) {
      g
        ..critic = critic
        ..blogger = blogger
        ..wallet = critic ? Wallet.wealthy : Wallet.thrifty
        ..temper = Temper.steady
        ..patienceMax = progress.patience
        ..patience = progress.patience;
    }
    guests.add(g);
    if (_queue.length >= diner.queueLength) {
      // The queue is out of sight of the door already: they walk on by.
      walkouts++;
      if (g.reviewer) {
        reviewDelta -= g.critic ? 4 : 3;
        _tell(
          'The ${g.critic ? 'critic' : 'blogger'} saw the queue and went '
          'somewhere else.',
          Tone.bad,
          key: 'critic',
        );
      }
      queueFull++;
      _missed(g);
      g
        ..passerby = true
        ..state = GuestState.leaving
        ..path =
            route(
              diner,
              start,
              fromLeft ? diner.arrivalRight : diner.arrivalLeft,
            ) ??
            [];
      _tell(
        _say([
          '{a} took one look at the queue and kept walking.',
          '{a} saw the line and decided on a sandwich instead.',
          '{a} walked past. The queue was too long.',
        ], a: g.name),
        Tone.bad,
        key: 'pass',
        limit: 2,
      );
      return;
    }
    _queue.add(g);
    if (_queue.length == diner.queueLength) {
      _tell(
        _say([
          'The queue stretches along the pavement.',
          'There is a line out of the door.',
        ]),
        Tone.mixed,
        key: 'queue',
      );
    }
  }

  bool _reserved(Seat s) => guests.any(
    (g) =>
        g.seat?.cell == s.cell &&
        (g.state == GuestState.toSeat ||
            g.state == GuestState.waiting ||
            g.state == GuestState.eating),
  );

  void _seating() {
    // Everyone in the queue shuffles up to their place.
    for (var i = 0; i < _queue.length; i++) {
      final g = _queue[i];
      final slot = diner.queueSlot(i);
      if (g.slot != i) {
        g.slot = i;
        g.path = route(diner, g.cell, slot) ?? [];
      } else if (g.cell != slot && g.path.isEmpty) {
        g.path = route(diner, g.cell, slot) ?? [];
      }
    }
    if (_queue.isEmpty) return;
    final head = _queue.first;
    if (head.state != GuestState.queued ||
        head.cell != diner.queueSlot(0) ||
        head.path.isNotEmpty) {
      return;
    }
    var free = [
      for (final s in seats)
        if (!_reserved(s)) s,
    ];
    if (free.isEmpty) return;
    // A clean seat if there is one.
    final clean = free.where((s) => !dirty.contains(s.cell)).toList();
    if (clean.isNotEmpty) free = clean;
    // The nearest free seat to the door.
    (Seat, List<Cell>)? best;
    for (final s in free) {
      final r = route(diner, head.cell, s.cell);
      if (r != null && (best == null || r.length < best.$2.length)) {
        best = (s, r);
      }
    }
    if (best == null) return;
    head
      ..seat = best.$1
      ..path = best.$2
      ..state = GuestState.toSeat;
    _queue.remove(head);
  }

  // --------------------------------------------------------------- guests

  void _guest(Guest g) {
    if (g.car) {
      _car(g);
      return;
    }
    switch (g.state) {
      case GuestState.arriving:
        g.step();
        if (g.path.isEmpty && g.cell == diner.queueSlot(g.slot)) {
          g.state = GuestState.queued;
        }
      case GuestState.queued:
        g.step();
        if (!_drain(g)) return;
      case GuestState.toSeat:
        g.step();
        if (g.cell == g.seat!.cell) {
          g
            ..state = GuestState.waiting
            // Sitting down resets their patience: the wait for a table is
            // forgiven, the wait for food is not.
            ..patience = g.patienceMax
            ..dir = g.seat!.facing;
          if (dirty.contains(g.seat!.cell)) {
            g
              ..grumpy = true
              ..patienceMax = (g.patienceMax * messPatience).round();
            g.patience = g.patienceMax;
            _tell(
              _say([
                '{a} sat down at a table nobody had cleared.',
                '{a} pushed someone else\'s plates aside and sat.',
              ], a: g.name),
              Tone.bad,
              key: 'dirty',
              limit: 2,
            );
          }
          _order(g);
        }
      case GuestState.waiting:
        g.prev = g.cell;
        g.waited++;
        _drain(g);
      case GuestState.eating:
        g.prev = g.cell;
        if (--g.timer <= 0) _toPay(g);
      case GuestState.toPay:
        g.step();
        if (g.path.isEmpty) {
          final c = g.counter!;
          c.line.add(g);
          g.state = GuestState.paying;
          g.face(c.at.at);
        }
      case GuestState.paying:
        g.prev = g.cell;
      case GuestState.leaving:
        g.step();
        if (g.path.isEmpty) g.gone = true;
    }
  }

  /// How fast patience drains for [g]: slower with a TV or a plant near their
  /// seat. Anyone not yet seated feels the usual.
  double _drainMul(Guest g) {
    final seat = g.seat;
    if (seat == null || g.car) return 1;
    return _drainAt[seat.cell] ?? 1;
  }

  /// Patience runs down; at nothing they storm out. Returns false if so.
  bool _drain(Guest g) {
    // A charming team takes the sting out of waiting.
    g.drainAcc += (1 - _calm) * _drainMul(g);
    while (g.drainAcc >= 1) {
      g.drainAcc -= 1;
      g.patience--;
    }
    if (g.patience > 0) return true;
    g.angry = true;
    walkouts++;
    gaveUp++;
    if (g.reviewer) {
      reviewDelta -= g.critic ? 6 : 5;
      _tell(
        'The ${g.critic ? 'critic' : 'blogger'} gave up waiting and walked '
        'out. That will be written up.',
        Tone.bad,
        key: 'critic',
      );
    }
    final cooking = g.items
        .where((i) => i.state == ItemState.cooking)
        .firstOrNull;
    _tell(
      cooking != null
          ? _say(
              [
                '{a} gave up waiting, with the {b} still cooking.',
                '{a} stormed out just before the {b} was ready.',
              ],
              a: g.name,
              b: recipes[cooking.dish]!.name.toLowerCase(),
            )
          : _say([
              '{a} gave up waiting and left.',
              '{a} waited and waited, then walked out.',
              '{a} stormed out. Nobody had noticed them.',
            ], a: g.name),
      Tone.bad,
      key: 'gaveup',
      limit: 3,
    );
    _leave(g);
    return false;
  }

  void _toPay(Guest g) {
    // They have eaten and got up: what they leave is for someone to clear.
    final seat = g.seat;
    if (seat != null && !g.car) dirty.add(seat.cell);
    // The counter with the shortest line, counting the walk.
    (CounterState, Cell, List<Cell>)? best;
    var bestCost = 1 << 30;
    for (final c in counters) {
      final spot = nearest(diner, g.cell, diner.useCells(c.at));
      if (spot == null) continue;
      final cost = spot.$2.length + c.line.length * 3;
      if (cost < bestCost) {
        bestCost = cost;
        best = (c, spot.$1, spot.$2);
      }
    }
    if (best == null) {
      _pay(g);
      return;
    }
    g
      ..counter = best.$1
      ..path = best.$3
      ..state = GuestState.toPay;
  }

  void _checkout() {
    for (final c in counters) {
      if (c.line.isEmpty) {
        c.timer = 0;
        continue;
      }
      if (++c.timer < progress.checkoutTicks) continue;
      c.timer = 0;
      _pay(c.line.removeAt(0));
    }
  }

  void _pay(Guest g) {
    var exact = 0.0;
    var count = 0;
    for (final i in g.items.where((i) => i.state == ItemState.delivered)) {
      exact += progress.price(i.dish) * i.quality;
      _tierPoints += i.tier.rating;
      count++;
    }
    final total = _coins(exact + g.tipExact);
    diner.coins += total;
    earned += total;
    tips += g.tip;
    served++;
    g.tallied = true;
    final bought = <Dish, (int, int)>{};
    for (final i in g.items.where((i) => i.state == ItemState.delivered)) {
      final was = bought[i.dish] ?? (0, 0);
      bought[i.dish] = (
        was.$1 + 1,
        was.$2 + (progress.price(i.dish) * i.quality).round(),
      );
    }
    crowd.fed(
      g.gender,
      g.wallet,
      total,
      bought,
      costs: {
        for (final e in bought.entries)
          e.key: (diner.unitCost(e.key) * e.value.$1).round(),
      },
      hour: _hourOf(g),
    );
    if (g.car) carsServed++;
    itemsServed += count;
    _waitTotal += g.waited;
    xp += exact.round();
    pops.add(Pop(g.cell));
    _leave(g);
  }

  /// Fractions of a coin left over from earlier payments. A burger that
  /// sells for 9.6 pays 10, then 9, then 10: so a small improvement in
  /// quality still shows up over a day, instead of vanishing in the rounding.
  double _change = 0;

  int _coins(double exact) {
    _change += exact;
    final whole = _change.floor();
    _change -= whole;
    return whole;
  }

  void _leave(Guest g) {
    _missed(g);
    g
      ..state = GuestState.leaving
      ..counter = null;
    // Whatever they had ordered and not received is written off.
    for (final i in g.items) {
      if (i.open) i.state = ItemState.lost;
    }
    if (g.car) {
      g.path = _driveOff(g.cell);
      return;
    }
    // Off along the pavement, one way or the other.
    final exit = g.id.isEven ? diner.arrivalLeft : diner.arrivalRight;
    final way = route(diner, g.cell, exit);
    if (way == null) {
      g
        ..cell = exit
        ..prev = exit
        ..gone = true;
      return;
    }
    g.path = way;
  }

  // ------------------------------------------------------------- ordering

  /// Buys the day's ingredients: what the plan says, or as much of it as the
  /// till can pay for.
  void _buyStock() {
    final want = {for (final d in menu) d: diner.portions(d)};
    double cost() =>
        want.entries.fold(0.0, (a, e) => a + e.value * diner.unitCost(e.key));
    var trimmed = false;
    while (cost().round() > diner.coins && want.values.any((n) => n > 0)) {
      // Take a portion off whichever dish has the most.
      final big = want.entries.reduce((a, b) => a.value >= b.value ? a : b);
      want[big.key] = big.value - 1;
      trimmed = true;
    }
    ingredientCost = cost().round();
    // A poor supplier sends some of it bad: paid for, and thrown straight out.
    final lost = diner.supplier.spoiledShare(progress.day);
    if (lost > 0) {
      for (final e in want.entries.toList()) {
        final bad = (e.value * lost).floor();
        spoiled += bad;
        want[e.key] = e.value - bad;
      }
    }
    stock
      ..clear()
      ..addAll(want);
    diner.coins -= ingredientCost;
    if (spoiled > 0) {
      _tell(
        '$spoiled portions arrived spoiled from the ${diner.supplier.label.toLowerCase()}.',
        Tone.bad,
        key: 'spoiled',
      );
    }
    if (trimmed) {
      _tell(
        _say([
          'There was not enough money for all the ingredients.',
          'The till was short at the market. Some things will run out.',
        ]),
        Tone.bad,
      );
    }
  }

  /// What a guest orders when they sit down: a main, and perhaps a side, a
  /// drink and a dessert, from what there is left to sell.
  void _order(Guest g) {
    final picks = <Dish>[];
    for (final c in Course.values) {
      final options = [
        for (final d in menu)
          if (recipes[d]!.course == c &&
              (stock[d] ?? 0) > 0 &&
              g.wallet.accepts(diner.priceRatio(d)) &&
              // The critic will only have a main made with the best.
              (!g.critic ||
                  c != Course.main ||
                  diner.tierOf(d) == Tier.premium))
            d,
      ];
      if (options.isEmpty) continue;
      if (c != Course.main && rng.nextDouble() >= c.appetite) continue;
      // Whatever is on the board outside is asked for more often.
      final weighted = [
        for (final d in options) ...[
          d,
          if (diner.isSpecial(d)) ...[d, d],
        ],
      ];
      picks.add(weighted[rng.nextInt(weighted.length)]);
    }
    if (g.critic && !picks.any((d) => recipes[d]!.course == Course.main)) {
      // Nothing on the menu worth their time.
      reviewDelta -= 4;
      walkouts++;
      g.angry = true;
      _tell(
        'The critic read the menu, found nothing made with the best, and left.',
        Tone.bad,
        key: 'critic',
      );
      _leave(g);
      return;
    }
    if (!picks.any((d) => recipes[d]!.course == Course.main)) {
      walkouts++;
      g.angry = true;
      final inStock = menu.any(
        (d) => recipes[d]!.course == Course.main && (stock[d] ?? 0) > 0,
      );
      if (inStock) {
        // There is food, but it costs more than they will pay.
        tooDear++;
        if (g.blogger) {
          reviewDelta -= 4;
          _tell(
            'The blogger found the prices too high and wrote about it.',
            Tone.bad,
            key: 'critic',
          );
        }
        _tell(
          _say([
            '{a} looked at the prices and walked out.',
            '{a} read the menu, winced, and left.',
            '{a} wanted something cheaper than this.',
          ], a: g.name),
          Tone.bad,
          key: 'toodear',
          limit: 2,
        );
        _leave(g);
        return;
      }
      // Nothing to eat: the mains have sold out.
      soldOut++;
      final wanted = menu
          .where((d) => recipes[d]!.course == Course.main)
          .firstOrNull;
      _tell(
        _say(
          [
            '{a} asked for a {b} and was told we had run out.',
            '{a} wanted a {b}. Sold out. {a} was not pleased.',
          ],
          a: g.name,
          b: wanted == null ? 'burger' : recipes[wanted]!.name.toLowerCase(),
        ),
        Tone.bad,
        key: 'soldout',
        limit: 2,
      );
      _leave(g);
      return;
    }
    for (final d in picks) {
      stock[d] = stock[d]! - 1;
      g.items.add(OrderItem(g, d, diner.tierOf(d)));
    }
    // A bigger order is expected to take longer.
    g.patienceMax = (g.patienceMax * (1 + 0.2 * (picks.length - 1))).round();
    g.patience = g.patienceMax;
  }

  // -------------------------------------------------------------- kitchen

  void _machines() {
    for (final m in machines) {
      final item = m.item;
      if (item == null) continue;
      if (item.state == ItemState.lost) {
        // Cooked for someone who has gone: it goes in the bin.
        m
          ..item = null
          ..ready = false;
        wasted++;
        continue;
      }
      if (m.ready) continue;
      if (--m.left <= 0) {
        m.ready = true;
        item.state = ItemState.ready;
      }
    }
  }

  // ---------------------------------------------------------------- staff

  int get _capacity => progress.carry;

  /// Ticks to allow for walking an order out when deciding if it can still
  /// be delivered in time.
  static const _walkAllowance = 6;

  /// How many ticks [staff] take over [dish]: the recipe and kitchen
  /// upgrades, then how well they know it.
  int _cookTime(Dish dish, Staff staff) =>
      (progress.cookTicks(dish) * staff.masteryTime(dish)).round().clamp(2, 99);

  /// How quickly [w] tires: hot-headed people fast, loyal ones slowly. A
  /// worker on their feet tires faster than one standing about.
  double _wear(Worker w) {
    final trait = w.staff.has(Trait.hotHeaded)
        ? 1.3
        : w.staff.has(Trait.loyal)
        ? 0.85
        : 1.0;
    final on = w.busy > 0 || w.state != WorkState.idle;
    return (on ? 0.25 : 0.05) * trait;
  }

  /// Whether food is waiting to be cooked for someone, so a rest can be cut
  /// short.
  bool get _foodWaiting => guests.any(
    (g) =>
        g.state == GuestState.waiting &&
        g.items.any((i) => i.state == ItemState.pending),
  );

  /// A worker with nothing to do and not much left goes to the staff room, if
  /// there is one and a sofa free.
  void _maybeRest(Worker w) {
    if (diner.room.sofaCount == 0 || w.energy >= 55) return;
    final taking = workers
        .where(
          (o) => o.state == WorkState.toRest || o.state == WorkState.resting,
        )
        .length;
    if (taking >= diner.room.sofaCount) return;
    final door = diner.staffDoor;
    if (door == null) return;
    final way = route(diner, w.cell, door);
    if (way == null) return;
    w
      ..path = way
      ..state = WorkState.toRest;
  }

  void _work(Worker w) {
    if (w.state == WorkState.resting) {
      w.energy = math.min(100, w.energy + 1.0);
      w.prev = w.cell;
      // Back out when rested, or sooner if there is food nobody is cooking.
      if (w.energy >= 85 || (w.energy >= Worker.tired && _foodWaiting)) {
        w.state = WorkState.idle;
      }
      return;
    }
    w.energy = math.max(0, w.energy - _wear(w));
    if (w.busy > 0) {
      w.prev = w.cell;
      w.busy--;
      return;
    }
    switch (w.state) {
      case WorkState.idle:
        w.prev = w.cell;
        _decide(w);
      case WorkState.toPickup:
        w.walk();
        if (w.path.isNotEmpty) return;
        final m = w.machine!;
        w
          ..state = WorkState.idle
          ..machine = null
          ..busy = w.takeHandling();
        m.claimed = false;
        w.face(_nearestCell(w.cell, m.at));
        final item = m.item;
        if (m.ready &&
            item != null &&
            item.state == ItemState.ready &&
            item.guest.state == GuestState.waiting) {
          w.carrying.add(item);
          item.state = ItemState.carried;
          m
            ..item = null
            ..ready = false;
        }
      case WorkState.toLoad:
        w.walk();
        if (w.path.isNotEmpty) return;
        final m = w.machine!;
        final item = w.loading;
        w
          ..state = WorkState.idle
          ..machine = null
          ..loading = null
          ..busy = w.takeHandling();
        m.claimed = false;
        w.face(_nearestCell(w.cell, m.at));
        if (item == null) return;
        if (item.state == ItemState.claimed &&
            item.guest.state == GuestState.waiting &&
            m.item == null) {
          _load(w, m, item);
        } else if (item.state == ItemState.claimed) {
          item.state = ItemState.pending;
        }
      case WorkState.resting:
        break;
      case WorkState.toRest:
        w.walk();
        if (w.path.isNotEmpty) return;
        // Through the door and out of sight.
        w.state = WorkState.resting;
      case WorkState.toClean:
        w.walk();
        if (w.path.isNotEmpty) return;
        final seat = w.cleaning;
        w
          ..state = WorkState.idle
          ..cleaning = null
          ..busy = w.takeHandling() + 1;
        if (seat != null && dirty.remove(seat.cell)) {
          cleaned++;
          w.face(seat.cell);
        }
      case WorkState.toDeliver:
        w.walk();
        if (w.path.isNotEmpty) return;
        final g = w.target;
        w
          ..state = WorkState.idle
          ..target = null
          ..busy = w.takeHandling();
        if (g == null) return;
        final mine = w.carrying.where((i) => i.guest == g).toList();
        w.carrying.removeWhere((i) => i.guest == g);
        w.face(g.seat?.cell ?? w.cell);
        if (mine.isEmpty) return;
        if (g.state != GuestState.waiting || g.gone) {
          for (final i in mine) {
            i.state = ItemState.lost;
          }
          wasted += mine.length;
          return;
        }
        if (w.staff.has(Trait.clumsy) && rng.nextDouble() < 0.07) {
          _drop(w, g, mine.removeAt(0));
        }
        for (final i in mine) {
          i.state = ItemState.delivered;
        }
        w.platesToday += mine.length;
        w.staff.plates += mine.length;
        if (g.mealComplete) _finishMeal(w, g);
    }
  }

  /// Puts [item] on [m], cooked by [w]: how well it turns out depends on who
  /// is cooking and what it is made from, and they get better at it.
  void _load(Worker w, Machine m, OrderItem item) {
    final staff = w.staff;
    final dish = item.dish;
    var time = _cookTime(dish, staff);
    if (item.guest.rushed) {
      time = math.max(2, (time * Pace.rushSpeed).round());
    }
    m
      ..item = item
      ..left = time
      ..total = time
      ..ready = false;
    item
      ..state = ItemState.cooking
      ..quality =
          staff.priceFactor *
          staff.masteryPrice(dish) *
          item.tier.priceMul *
          (1 + diner.markupOf(dish) / 100);
    final before = staff.masteryLevel(dish);
    staff.mastery[dish] = staff.made(dish) + 1;
    final after = staff.masteryLevel(dish);
    if (after > before) {
      w.feel('emote_star');
      final what = recipes[dish]!.name.toLowerCase();
      _tell(
        _say(
          [
            '{a} is getting good at making {b}.',
            'Everyone agrees {a} makes the best {b} now.',
          ],
          a: staff.name,
          b: what,
        ),
        Tone.good,
        key: 'mastery-$what',
        about: staff,
        memory: 'got better at ${what}s (level $after)',
      );
    }
  }

  /// All the food is on the table: they start to eat, and the tip depends on
  /// how long they waited.
  void _finishMeal(Worker w, Guest g) {
    final delivered = g.items.where((i) => i.state == ItemState.delivered);
    if (delivered.isEmpty) {
      // Everything was dropped or lost: nothing to eat.
      _leave(g);
      return;
    }
    // The faster they were served, the better they tip, and a charming waiter
    // coaxes a little more.
    final base = g.mood > 0.66
        ? 0.3
        : g.mood > 0.33
        ? 0.1
        : 0.0;
    var price = 0.0;
    for (final i in delivered) {
      price += progress.price(i.dish) * i.quality;
    }
    g.tipExact = base == 0
        ? 0
        : price *
              (base + w.staff.tipBonus).clamp(0.0, 1.0) *
              g.wallet.tipMul *
              diner.supplier.tipMul *
              (g.grumpy ? messTip : 1) *
              (g.seat == null ? 1 : (_tipAt[g.seat!.cell] ?? 1));
    g.tip = g.tipExact.round();
    _served(w, g);
    if (g.critic) {
      if (g.mood >= 0.4) {
        reviewDelta += 8;
        _tell(
          'The critic raved about the food. People will hear about this.',
          Tone.good,
          key: 'critic',
        );
      } else {
        reviewDelta += 2;
        _tell(
          'The critic liked the food, but said the wait was too long.',
          Tone.mixed,
          key: 'critic',
        );
      }
    } else if (g.blogger) {
      final fair = delivered.every(
        (i) => diner.priceRatio(i.dish) <= diner.tierOf(i.dish).priceMul,
      );
      if (!fair) {
        reviewDelta -= 2;
        _tell(
          'The blogger enjoyed the food, but wrote that it was overpriced.',
          Tone.bad,
          key: 'critic',
        );
      } else if (g.mood >= 0.4) {
        reviewDelta += 6;
        _tell(
          'The blogger posted that the prices are fair and the food is good.',
          Tone.good,
          key: 'critic',
        );
      } else {
        reviewDelta += 1;
        _tell(
          'The blogger said the prices were fair, but the wait was long.',
          Tone.mixed,
          key: 'critic',
        );
      }
    }
    if (g.car) {
      // Paid at the window and off.
      _pay(g);
      return;
    }
    g
      ..state = GuestState.eating
      ..timer = Pace.eat + 3 * (delivered.length - 1);
  }

  /// The name of the main thing a guest ordered, for the story.
  String _mealName(Guest g) => g.items.isEmpty
      ? 'order'
      : recipes[g.items.first.dish]!.name.toLowerCase();

  /// The plate hits the floor. That portion is lost; the guest goes back to
  /// waiting for it, and it has to be cooked again if there is any left.
  void _drop(Worker w, Guest g, OrderItem item) {
    wasted++;
    w.staff.drops++;
    w
      ..busy += 2
      ..feel('emote_oops', 10);
    final left = stock[item.dish] ?? 0;
    if (left > 0) {
      stock[item.dish] = left - 1;
      item.state = ItemState.pending;
    } else {
      item.state = ItemState.lost;
    }
    final what = recipes[item.dish]!.name.toLowerCase();
    _tell(
      _say(
        [
          '{a} dropped {b}\'s {c}. They say it was already like that.',
          '{b}\'s {c} hit the floor. {a} is looking at the ceiling.',
          '{a} tripped over nothing. {b}\'s {c} did not survive.',
        ],
        a: w.staff.name,
        b: g.name,
        c: what,
      ),
      Tone.bad,
      key: 'drop',
      limit: 3,
      about: w.staff,
      memory: 'dropped ${g.name}\'s $what',
    );
    if (w.staff.reveal(Trait.clumsy)) {
      _tell(
        _say([
          'Turns out {a} is clumsy.',
          'Nobody mentioned that {a} is clumsy.',
        ], a: w.staff.name),
        Tone.bad,
        key: 'reveal-clumsy',
      );
    }
  }

  /// Colour for a meal that has just been served.
  void _served(Worker w, Guest g) {
    final name = w.staff.name;
    final meal = _mealName(g);
    final late = g.mood < 0.25;
    if (late) {
      w.feel('emote_star');
      _tell(
        _say(
          [
            '{b} was about to leave when {a} arrived with the {c}.',
            '{a} saved the {c} for {b} with seconds to spare.',
          ],
          a: name,
          b: g.name,
          c: meal,
        ),
        Tone.good,
        key: 'saved',
        limit: 2,
        about: w.staff,
        memory: 'saved ${g.name} from leaving',
      );
    } else if (g.waited <= 9) {
      _tell(
        _say(
          [
            '{a} had {b}\'s {c} out in seconds.',
            '{b} could not believe how fast {a} was.',
          ],
          a: name,
          b: g.name,
          c: meal,
        ),
        Tone.good,
        key: 'fast',
        about: w.staff,
        memory: 'served ${g.name} in a flash',
      );
    }
    if (g.tip >= 3) {
      w.feel('emote_heart');
      _tell(
        _say(
          [
            '{b} tipped {a} {c} coins. "Best service in town."',
            '{b} left {a} {c} coins and a smile.',
            '{a} charmed {b} out of {c} extra coins.',
          ],
          a: name,
          b: g.name,
          c: '${g.tip}',
        ),
        Tone.good,
        key: 'tip',
        limit: 2,
        about: w.staff,
        memory: '${g.name} tipped ${g.tip}',
      );
    }
    if (w.staff.has(Trait.perfectionist) && rng.nextDouble() < 0.12) {
      w
        ..busy += 1
        ..feel('emote_star');
      _tell(
        _say(
          [
            '{a} sent {b}\'s {c} back to be remade. Twice.',
            '{a} turned the {c} so the best side faced {b}.',
          ],
          a: name,
          b: g.name,
          c: meal,
        ),
        Tone.mixed,
        key: 'perfect',
        about: w.staff,
        memory: 'fussed over ${g.name}\'s $meal',
      );
      w.staff.reveal(Trait.perfectionist);
    }
  }

  Cell _nearestCell(Cell from, Placed p) {
    Cell best = p.at;
    var bd = 1 << 30;
    for (final c in p.cells) {
      final d = (c.x - from.x).abs() + (c.y - from.y).abs();
      if (d < bd) {
        bd = d;
        best = c;
      }
    }
    return best;
  }

  /// What to do next, in order of priority:
  ///
  /// 1. Take a finished dish off a machine, if there is room on the tray.
  /// 2. Start the next dish if its machine is right here, even with a plate
  ///    in hand, so the cooker never sits empty while someone walks.
  /// 3. Deliver what they are carrying.
  /// 4. Go and start the next dish.
  ///
  /// Someone with a station they prefer looks after that machine first, and
  /// helps elsewhere when it needs nothing.
  void _decide(Worker w) {
    if (_isOperator(w)) {
      _operate(w);
      return;
    }
    if (_isCleaner(w)) {
      _clear(w);
      return;
    }
    if (_holdAtWindow(w)) return;
    if (_pickUp(w)) return;
    if (_tendWindow(w)) return;
    if (_startLoading(w, within: 1)) return;

    // Anything on the tray for someone who has left is written off.
    w.carrying.removeWhere((i) {
      final gone = i.guest.gone || i.guest.state != GuestState.waiting;
      if (gone) {
        i.state = ItemState.lost;
        wasted++;
      }
      return gone;
    });
    if (w.carrying.isNotEmpty && _holdForRest(w)) {
      w.prev = w.cell;
      return;
    }
    if (w.carrying.isNotEmpty) {
      // Whose food is there most of, so one trip does the most good.
      final counts = <Guest, int>{};
      for (final i in w.carrying) {
        counts[i.guest] = (counts[i.guest] ?? 0) + 1;
      }
      final g = counts.keys.reduce(
        (a, b) => a.rushed != b.rushed
            ? (a.rushed ? a : b)
            : counts[a]! != counts[b]!
            ? (counts[a]! > counts[b]! ? a : b)
            : (a.patience <= b.patience ? a : b),
      );
      final spot = nearest(
        diner,
        w.cell,
        g.car ? _freeSpots(w) : diner.approaches(g.seat!.cell),
      );
      if (spot != null) {
        w
          ..target = g
          ..path = spot.$2
          ..state = WorkState.toDeliver;
        return;
      }
    }
    if (_startLoading(w)) return;
    _maybeRest(w);
  }

  /// The window operator: fetches finished food for the cars, hands it over,
  /// and waits at the window otherwise.
  void _operate(Worker w) {
    if (_pickUp(w)) return;
    w.carrying.removeWhere((i) {
      final gone = i.guest.gone || i.guest.state != GuestState.waiting;
      if (gone) {
        i.state = ItemState.lost;
        wasted++;
      }
      return gone;
    });
    final spots = diner.operatorSpots;
    if (w.carrying.isNotEmpty) {
      final r = nearest(diner, w.cell, spots);
      if (r != null) {
        w
          ..target = w.carrying.first.guest
          ..path = r.$2
          ..state = WorkState.toDeliver;
        return;
      }
    }
    w.prev = w.cell;
    if (!spots.contains(w.cell)) {
      // A tile behind the window that nobody else is on.
      final free = [
        for (final c in spots)
          if (!workers.any((o) => o != w && o.cell == c)) c,
      ];
      final r = nearest(diner, w.cell, free);
      if (r != null) {
        w
          ..target = null
          ..path = r.$2
          ..state = WorkState.toDeliver;
      }
      return;
    }
    w.face(diner.window!.at);
  }

  /// The tiles behind the window that nobody else is standing on, so two
  /// people at the window do not stack up on one tile. All of them if none
  /// is free.
  List<Cell> _freeSpots(Worker w) {
    final spots = diner.operatorSpots;
    final free = [
      for (final c in spots)
        if (!workers.any((o) => o != w && o.cell == c)) c,
    ];
    return free.isEmpty ? spots : free;
  }

  /// A worker kept for the tables walks to the nearest mess and clears it.
  void _clear(Worker w) {
    w.prev = w.cell;
    // Not one somebody else is already on their way to.
    final taken = {
      for (final o in workers)
        if (o != w && o.cleaning != null) o.cleaning!.cell,
    };
    (Seat, List<Cell>)? best;
    for (final seat in seats) {
      if (!dirty.contains(seat.cell) || taken.contains(seat.cell)) continue;
      final r = nearest(diner, w.cell, diner.approaches(seat.cell));
      if (r == null) continue;
      if (best == null || r.$2.length < best.$2.length) best = (seat, r.$2);
    }
    if (best == null) return;
    w
      ..cleaning = best.$1
      ..path = best.$2
      ..state = WorkState.toClean;
  }

  /// Whoever has just reached the window stays until the car has given its
  /// order.
  bool _holdAtWindow(Worker w) {
    if (!diner.operatorSpots.contains(w.cell)) return false;
    if (_carAwaitingOrder == null) return false;
    w.prev = w.cell;
    w.face(diner.window!.at);
    return true;
  }

  /// Anyone can serve the window. When a car has pulled up and nobody is at
  /// it or on the way, whoever is free walks over.
  bool _tendWindow(Worker w) {
    if (_carAwaitingOrder == null) return false;
    final spots = diner.operatorSpots;
    bool heading(Worker o) =>
        spots.contains(o.cell) ||
        (o.state == WorkState.toDeliver &&
            o.target == null &&
            o.path.isNotEmpty &&
            spots.contains(o.path.last));
    if (workers.any((o) => o != w && heading(o))) return false;
    final r = nearest(diner, w.cell, spots);
    if (r == null) return false;
    w
      ..target = null
      ..path = r.$2
      ..state = WorkState.toDeliver;
    return true;
  }

  /// Whether it is worth waiting a moment for the rest of an order before
  /// carrying it out: something for the same table is nearly done, and the
  /// tray has room for it.
  bool _holdForRest(Worker w) {
    if (w.carrying.length >= _capacity) return false;
    if (w.carrying.any((i) => i.guest.rushed)) return false;
    for (final g in w.carrying.map((i) => i.guest).toSet()) {
      if (g.patience < 12) continue;
      for (final i in g.items) {
        if (i.state != ItemState.cooking && i.state != ItemState.ready) {
          continue;
        }
        final m = machines.where((m) => m.item == i).firstOrNull;
        if (m != null && (m.ready || m.left <= 4)) return true;
      }
    }
    return false;
  }

  /// The machine [w] looks after first. A station only makes sense when
  /// someone else is there to cover the rest, so a lone worker has none.
  Kind? _duty(Worker w) => workers.length > 1 ? w.staff.duty : null;

  /// Goes to collect a finished dish, if there is one and room to carry it.
  bool _pickUp(Worker w) {
    if (w.carrying.length >= _capacity) return false;
    final ready = machines.where(
      (m) =>
          m.ready &&
          !m.claimed &&
          m.item != null &&
          m.item!.guest.state == GuestState.waiting &&
          (!_isOperator(w) || m.item!.guest.car),
    );
    final duty = _duty(w);
    // Anything for a rushed guest comes off first.
    var pick = _nearestMachine(w, ready.where((m) => m.item!.guest.rushed));
    pick ??= duty == null
        ? null
        : _nearestMachine(w, ready.where((m) => m.kind == duty));
    pick ??= _nearestMachine(w, ready);
    if (pick == null) return false;
    pick.$1.claimed = true;
    w
      ..machine = pick.$1
      ..path = pick.$2
      ..state = WorkState.toPickup;
    return true;
  }

  /// Picks the next dish to start and a free machine for it, and sets off.
  /// [within] limits how far they will walk to do it. False if there is
  /// nothing to do.
  bool _startLoading(Worker w, {int? within}) {
    if (_isOperator(w)) return false;
    // The guest who has waited longest, unless they will have left before it
    // could reach them. A good cook doesn't waste a burger on someone already
    // halfway out the door. Longer dishes first, so a meal comes out together.
    final items =
        <OrderItem>[
          for (final g in guests)
            if (g.state == GuestState.waiting)
              for (final i in g.toStart)
                if (w.staff.canCook(i.dish) &&
                    g.patience > progress.cookTicks(i.dish) + _walkAllowance)
                  i,
        ]..sort((a, b) {
          // Anyone rushed goes to the front of the line.
          final r = (b.guest.rushed ? 1 : 0).compareTo(a.guest.rushed ? 1 : 0);
          if (r != 0) return r;
          final c = a.guest.patience.compareTo(b.guest.patience);
          return c != 0
              ? c
              : progress
                    .cookTicks(b.dish)
                    .compareTo(progress.cookTicks(a.dish));
        });

    bool tryKinds({required bool dutyOnly}) {
      for (final item in items) {
        final kind = recipes[item.dish]!.station;
        if (dutyOnly && kind != _duty(w)) continue;
        final m = _nearestMachine(
          w,
          machines.where((m) => m.free && m.kind == kind),
        );
        if (m == null) continue;
        if (within != null && m.$2.length > within) continue;
        item.state = ItemState.claimed;
        m.$1.claimed = true;
        w
          ..machine = m.$1
          ..loading = item
          ..path = m.$2
          ..state = WorkState.toLoad;
        return true;
      }
      return false;
    }

    if (_duty(w) != null && tryKinds(dutyOnly: true)) return true;
    return tryKinds(dutyOnly: false);
  }

  /// The closest of [options] to [w], with the walk to its front.
  (Machine, List<Cell>)? _nearestMachine(Worker w, Iterable<Machine> options) {
    (Machine, List<Cell>)? best;
    for (final m in options) {
      final spot = nearest(diner, w.cell, diner.useCells(m.at));
      if (spot == null) continue;
      if (best == null || spot.$2.length < best.$2.length) {
        best = (m, spot.$2);
      }
    }
    return best;
  }

  // -------------------------------------------------------------- closing

  void _closing() {
    // Anyone still waiting for a table when the doors shut goes home.
    for (final g in [
      ..._queue,
      ..._cars.where((c) => c.state == GuestState.queued),
    ]) {
      walkouts++;
      _leave(g);
    }
    final inside = guests.any((g) => g.state != GuestState.leaving);
    if (inside && ticks < Pace.dayTicks + Pace.lastCall) return;
    // Time is up for anyone left.
    for (final g in guests) {
      if (g.state != GuestState.leaving) {
        walkouts++;
        _leave(g);
      }
    }
    finishDay();
  }

  /// Ends the day: tallies it, and updates level, reputation and the
  /// calendar. Called once.
  DayReport finishDay() {
    if (result != null) return result!;
    finished = true;
    guests.clear();
    _queue.clear();
    _cars.clear();
    final total = served + walkouts;
    final share = total == 0 ? 0.0 : served / total;
    final stars = total == 0
        ? 0
        : share >= 0.9
        ? 3
        : share >= 0.7
        ? 2
        : share >= 0.4
        ? 1
        : 0;
    final avgWait = served == 0 ? 0.0 : _waitTotal / served * Pace.tickSeconds;
    // Ingredients left over at closing are thrown away.
    var left = 0.0;
    for (final e in stock.entries) {
      left += e.value * diner.unitCost(e.key);
    }
    final leftoverCost = left.round();
    for (final e in stock.entries) {
      crowd.thrownAway(e.key, e.value);
    }
    diner.crowd.add(crowd);
    diner.lastCrowd = crowd;
    final ratingBefore = progress.reputation;
    if (total > 0) {
      // A day is judged on how many were fed, and how quickly. The rating
      // moves a third of the way to that, so one day never swings it far.
      final speed = (1 - avgWait / 20).clamp(0.0, 1.0);
      // Better ingredients make people like a place more, and cheap ones less.
      final tierAvg = itemsServed == 0 ? 0 : _tierPoints / itemsServed;
      final score = (100 * (0.75 * share + 0.25 * speed) + tierAvg).clamp(
        0.0,
        100.0,
      );
      var step = ((score - progress.reputation) * 0.3).round();
      // A handful of guests tells you little.
      if (total < 4) step = (step / 2).round();
      progress.reputation = (progress.reputation + step).clamp(0, 100);
    }
    // A critic's verdict moves the rating on its own, on top of the day.
    if (reviewDelta != 0) {
      progress.reputation = (progress.reputation + reviewDelta).clamp(0, 100);
    }
    // Wages come out of the takings. Anyone who can't be paid loses heart, and
    // goes if it happens again. Some take it harder than others.
    var paid = 0;
    var unpaid = 0;
    final quit = <String>[];
    final moods = <MoodChange>[];
    final day = progress.day;
    for (final st in diner.roster.employees.toList()) {
      moods.add(MoodChange(st.name, st.morale, st.morale));
      if (diner.coins >= st.salary) {
        diner.coins -= st.salary;
        paid += st.salary;
        st.morale = math.min(Staff.maxMorale, st.morale + 1);
        st.grudge = 0;
        st.lastPay = Pay.paid;
      } else {
        unpaid += st.salary;
        st.lastPay = Pay.missed;
        var loss = 1;
        if (st.has(Trait.hotHeaded)) {
          loss = 2;
        } else if (st.has(Trait.loyal)) {
          // They put up with it once.
          st.grudge++;
          loss = st.grudge >= 2 ? 1 : 0;
          if (loss > 0) st.grudge = 0;
          if (loss == 0) {
            _tell(
              _say([
                '{a} is owed money but stayed anyway. "We\'ll sort it out."',
                '{a} missed a payday and did not say a word.',
              ], a: st.name),
              Tone.mixed,
              about: st,
              memory: 'stayed on, unpaid',
            );
          }
        }
        st.morale -= loss;
        if (st.morale <= 0) {
          quit.add(st.name);
          diner.roster.employees.remove(st);
          _tell(
            st.has(Trait.hotHeaded)
                ? _say([
                    '{a} threw down the apron and walked out.',
                    '{a} slammed the door on the way out.',
                  ], a: st.name)
                : _say([
                    '{a} quit. Rent does not pay itself.',
                    '{a} has found a job that pays on time.',
                  ], a: st.name),
            Tone.bad,
          );
          st.reveal(Trait.hotHeaded);
        }
      }
      moods.last = MoodChange(st.name, moods.last.before, st.morale);
      st.daysWorked++;
      st.trainedToday = false;
      // A few days in, you know what they are like.
      if (st.daysWorked >= 3) st.revealAll();
      // The late bloomer's moment.
      if (st.has(Trait.lateBloomer) && !st.bloomed && st.daysWorked >= 10) {
        st.bloomed = true;
        for (final s in Stat.values) {
          st.stats[s] = math.min(st.cap(s), st.stat(s) + 2);
        }
        st.revealAll();
        _tell(
          _say([
            '{a} finally found their feet: better at everything.',
            'Something clicked for {a} today. Everyone noticed.',
          ], a: st.name),
          Tone.good,
          about: st,
          memory: 'finally found their feet',
        );
      }
    }
    // The star of the day.
    final star = workers
        .where(
          (w) => w.platesToday > 0 && diner.roster.employees.contains(w.staff),
        )
        .fold<Worker?>(
          null,
          (best, w) =>
              best == null || w.platesToday > best.platesToday ? w : best,
        );
    if (star != null) {
      _tell(
        workers.length > 1
            ? _say(
                [
                  '{a} carried the day: {b} plates.',
                  '{a} was everywhere today. {b} plates served.',
                ],
                a: star.staff.name,
                b: '${star.platesToday}',
              )
            : _say(
                [
                  '{a} did it all today: {b} plates.',
                  '{a} ran the whole place. {b} plates, no help.',
                ],
                a: star.staff.name,
                b: '${star.platesToday}',
              ),
        Tone.good,
        about: star.staff,
        memory: 'served ${star.platesToday} plates',
      );
    }
    if (story.isEmpty) {
      _tell(
        _say([
          'A quiet day. Nothing much happened.',
          'Nobody dropped anything, nobody shouted. A good day.',
        ]),
        Tone.mixed,
      );
    }
    // The bank takes its share each night, after the wages.
    var loanPaid = 0;
    var loanMissed = false;
    if (diner.loan > 0) {
      final due = Bank.due(diner.loan);
      if (diner.coins >= due) {
        diner.coins -= due;
        diner.loan -= due;
        loanPaid = due;
        diner.loanLate = 0;
        if (diner.loan == 0) {
          _tell('The loan is paid off.', Tone.good, key: 'loan');
        }
      } else {
        loanMissed = true;
        diner.loanLate++;
        diner.loan += (diner.loan * Bank.latePenalty).ceil();
        progress.reputation = (progress.reputation - Bank.lateRating).clamp(
          0,
          100,
        );
        _tell(
          'The bank did not get its payment. It has been added to what you '
          'owe.',
          Tone.bad,
          key: 'loan',
        );
      }
    }
    final gained = progress.gain(xp);
    progress.day++;
    diner.history
      ..add(
        DayLog(
          day: day,
          kept: earned - ingredientCost - paid,
          served: served,
          walkouts: walkouts,
          rating: progress.reputation,
          event: event == DayEvent.none ? '' : event.name,
        ),
      )
      ..removeRange(0, math.max(0, diner.history.length - DayLog.keep));
    return result = DayReport(
      day: day,
      served: served,
      walkouts: walkouts,
      earned: earned,
      tips: tips,
      wasted: wasted,
      avgWait: avgWait,
      stars: stars,
      xp: xp,
      levelsGained: gained,
      reputation: progress.reputation,
      reputationBefore: ratingBefore,
      tomorrow: progress.expectedGuests,
      wages: paid,
      unpaid: unpaid,
      quit: quit,
      story: List.of(story),
      moods: moods,
      ingredients: ingredientCost,
      leftover: leftoverCost,
      soldOut: soldOut,
      tooDear: tooDear,
      cleaned: cleaned,
      event: event,
      reviewDelta: reviewDelta,
      gaveUp: gaveUp,
      queueFull: queueFull,
      spoiled: spoiled,
      crowd: crowd,
      loanPaid: loanPaid,
      loanMissed: loanMissed,
      cars: carsServed,
      items: itemsServed,
    );
  }

  // -------------------------------------------------------------- drawing

  /// Everything to draw this frame, [alpha] of the way through the tick.
  List<Actor> actors(double alpha) {
    final out = <Actor>[];

    Actor person(
      Person p,
      String sprite, {
      String? badge,
      List<String> items = const [],
      double? meter,
      bool seated = false,
      bool car = false,
      double offset = 0,
    }) {
      final moved = p.prev != p.cell;
      final t = moved ? alpha : 1.0;
      final back = Cell(-p.dir.dx, -p.dir.dy);
      // Along the path walked this tick: one step, or two for a quick walker.
      final mid = moved ? p.mid : null;
      final Cell a;
      final Cell b;
      final double u;
      if (mid == null) {
        a = p.prev;
        b = p.cell;
        u = t;
      } else if (t < 0.5) {
        a = p.prev;
        b = mid;
        u = t * 2;
      } else {
        a = mid;
        b = p.cell;
        u = (t - 0.5) * 2;
      }
      final x = a.x + (b.x - a.x) * u + 0.5 + back.x * offset;
      final y = a.y + (b.y - a.y) * u + 0.5 + back.y * offset;
      final walking = moved || p.path.isNotEmpty;
      final frame = seated
          ? 'sit'
          : walking
          ? '${p.walked % 4}'
          : ((ticks ~/ 3).isOdd ? 's1' : 's0');
      if (car) {
        return Actor(
          '${sprite}_${p.dir.name}',
          x,
          y,
          row: x + y,
          badge: badge,
          items: items,
          meter: meter,
        );
      }
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
        items: items,
        meter: meter,
      );
    }

    for (final w in workers) {
      // Resting is out of sight, in the staff room.
      if (w.state == WorkState.resting) continue;
      out.add(
        person(
          w,
          w.sprite,
          badge:
              w.emote ??
              (w.carrying.isEmpty
                  ? null
                  : 'plate_${w.carrying.first.dish.name}'),
        ),
      );
    }
    for (final g in guests) {
      final seated =
          g.state == GuestState.waiting || g.state == GuestState.eating;
      final lineIndex = g.counter?.line.indexOf(g) ?? -1;
      final waiting = g.state == GuestState.waiting;
      final impatient =
          g.state == GuestState.queued || g.state == GuestState.waiting;
      out.add(
        person(
          g,
          g.sprite,
          car: g.car,
          seated: seated && !g.car,
          badge: g.angry
              ? 'warn'
              : g.rushed
              ? 'emote_star'
              : null,
          items: waiting && !g.angry
              ? [for (final i in g.unfinished) i.dish.name]
              : const [],
          meter: impatient ? g.mood : null,
          offset: lineIndex > 0 ? lineIndex * 0.28 : 0,
        ),
      );
      if (g.state == GuestState.eating) {
        // A plate on the table for each thing they ordered.
        final t = g.seat!.table;
        final n = g.items.where((i) => i.state == ItemState.delivered).length;
        var k = 0;
        for (final i in g.items.where((i) => i.state == ItemState.delivered)) {
          out.add(
            Actor(
              'plate_${i.dish.name}',
              t.x + 0.5 + (k - (n - 1) / 2) * 0.22,
              t.y + 0.5 + (k - (n - 1) / 2) * 0.22,
              lift: 12,
              row: t.x + t.y + 0.5 + k * 0.01,
            ),
          );
          k++;
        }
      }
    }
    for (final seat in seats) {
      if (!dirty.contains(seat.cell)) continue;
      // The mess lies on the table, a little towards the chair it came from.
      final t = seat.table;
      out.add(
        Actor(
          'mess',
          t.x + 0.5 + (seat.cell.x - t.x) * 0.22,
          t.y + 0.5 + (seat.cell.y - t.y) * 0.22,
          lift: 12,
          row: t.x + t.y + 0.5,
        ),
      );
    }
    for (final m in machines) {
      final c = m.at.at;
      final x = c.x + 0.5;
      final y = c.y + 0.5;
      if (m.item != null && !m.ready) {
        final total = m.total;
        out.add(
          Actor(
            '',
            x,
            y,
            lift: 34,
            row: 999,
            meter: 1 - m.left / total,
            meterKind: Meter.cooking,
          ),
        );
      } else if (m.ready) {
        out.add(Actor('plate_${m.item!.dish.name}', x, y, lift: 30, row: 999));
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
