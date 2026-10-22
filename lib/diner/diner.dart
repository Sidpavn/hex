/// The restaurant's build grid: which cells are open, what stands on them,
/// which way each thing faces, and the rules for placing, rotating, moving,
/// selling and expanding. Pure Dart, no Flutter, so it can be tested and
/// driven by the service sim.
library;

import 'dart:math' as math;

import 'contracts.dart';
import 'crowd.dart';
import 'events.dart';
import 'suppliers.dart';
import 'vending.dart';
import 'recipes.dart';
import 'regulars.dart';
import 'staff.dart';

part 'layout_group.dart';

/// Size of one cell in art pixels.
const cellPx = 16;

/// The four ways to face on the grid. On screen `x` runs down-right and `y`
/// runs down-left, so these are the four diagonals.
enum Dir {
  se(1, 0),
  sw(0, 1),
  nw(-1, 0),
  ne(0, -1);

  const Dir(this.dx, this.dy);

  final int dx;
  final int dy;

  /// The direction of the one step from [from] to [to], if they touch.
  static Dir? between(Cell from, Cell to) {
    for (final d in values) {
      if (from.x + d.dx == to.x && from.y + d.dy == to.y) return d;
    }
    return null;
  }

  /// A quarter turn clockwise on screen.
  Dir get cw => switch (this) {
    sw => nw,
    nw => ne,
    ne => se,
    se => sw,
  };

  /// Sprites are drawn facing `sw` and `nw`; the other two are mirrors.
  bool get mirrored => this == se || this == ne;

  /// The drawn facing: `sw` or `nw`.
  String get art => (this == sw || this == se) ? 'sw' : 'nw';
}

/// A square cell on the build grid.
class Cell {
  const Cell(this.x, this.y);

  final int x;
  final int y;

  Cell operator +(Cell o) => Cell(x + o.x, y + o.y);

  /// The cell one step in [d].
  Cell step(Dir d) => Cell(x + d.dx, y + d.dy);

  /// The four orthogonal neighbours: customers and staff walk in these steps.
  List<Cell> get neighbors => [
    Cell(x + 1, y),
    Cell(x - 1, y),
    Cell(x, y + 1),
    Cell(x, y - 1),
  ];

  @override
  bool operator ==(Object other) =>
      other is Cell && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x,$y)';
}

/// The border between two touching cells, where a wall can stand. It is named
/// by one cell and a side: with [alongX] it is the cell's north side, between
/// (x, y - 1) and (x, y), and a wall there runs along x; without it, the
/// west side, between (x - 1, y) and (x, y), and the wall runs along y.
class Edge {
  const Edge(this.x, this.y, this.alongX);

  final int x;
  final int y;
  final bool alongX;

  /// The cell on the north or west side of it, and the one the edge is named
  /// for, on the other.
  Cell get a => alongX ? Cell(x, y - 1) : Cell(x - 1, y);
  Cell get b => Cell(x, y);

  /// The edge between two touching cells, or null if they do not touch.
  static Edge? between(Cell p, Cell q) {
    if (p.x == q.x && (p.y - q.y).abs() == 1) {
      return Edge(p.x, p.y > q.y ? p.y : q.y, true);
    }
    if (p.y == q.y && (p.x - q.x).abs() == 1) {
      return Edge(p.x > q.x ? p.x : q.x, p.y, false);
    }
    return null;
  }

  List<int> toJson() => [x, y, alongX ? 1 : 0];

  static Edge? fromJson(Object? j) {
    if (j is! List || j.length != 3) return null;
    final x = j[0];
    final y = j[1];
    final h = j[2];
    if (x is! int || y is! int || (h != 0 && h != 1)) return null;
    return Edge(x, y, h == 1);
  }

  @override
  bool operator ==(Object other) =>
      other is Edge && other.x == x && other.y == y && other.alongX == alongX;

  @override
  int get hashCode => Object.hash(x, y, alongX);

  @override
  String toString() => 'Edge($x,$y,${alongX ? 'x' : 'y'})';
}

enum Kind {
  counter,
  grill,
  fryer,
  soda,
  espresso,
  oven,
  freezer,
  window,
  table,
  longTable,
  chair,
  bench,
  plant,
  jukebox,
  tv,
  rug,
  wall,
  pass,
}

/// What a fixture does in the restaurant.
enum Role {
  /// Cooks a dish. Staff load and empty it from the cell in front.
  station,

  /// Where guests pay, one at a time, from the cell in front.
  counter,

  /// Where a guest sits, facing the table in front of it.
  seat,

  /// Where seated guests are served.
  table,

  /// A hatch in the front wall where drivers are served from the street. An
  /// operator stands behind it.
  window,

  /// Where cooks put finished dishes for the servers to carry out.
  pass,

  /// Looks nice; does nothing.
  decor,
}

/// What a piece of decor does to the guests seated near it.
enum AuraEffect {
  /// Waiting feels shorter: a guest's patience runs down more slowly.
  patience,

  /// A better mood: they tip more.
  tips,
}

/// A fixture's effect on the seats around it: [strength] is a multiple, below
/// one for patience (it drains slower) and above one for tips, felt by guests
/// seated within [radius] tiles of any part of it.
class Aura {
  const Aura(this.effect, this.radius, this.strength);

  final AuraEffect effect;
  final int radius;
  final double strength;

  /// How the effect reads to the player: "wait 40% longer within 2 tiles".
  String get describe {
    final tiles = radius == 1 ? '1 tile' : '$radius tiles';
    return switch (effect) {
      AuraEffect.patience =>
        'Guests seated within $tiles wait '
            '${((1 / strength - 1) * 100).round()}% longer.',
      AuraEffect.tips =>
        'Guests seated within $tiles tip '
            '${((strength - 1) * 100).round()}% more.',
    };
  }
}

/// What a fixture is. Sprites are named after the [Kind], plus the facing for
/// those that turn.
class FixtureDef {
  const FixtureDef(
    this.kind,
    this.name,
    this.cost,
    this.role, {
    this.w = 1,
    this.h = 1,
    this.floor = false,
    this.hung = false,
    this.unlock = 1,
    this.info = '',
    this.aura,
  });

  final Kind kind;
  final String name;
  final int cost;
  final Role role;

  /// Footprint in cells when facing `sw` or `ne`; swapped for `se` and `nw`.
  final int w;
  final int h;

  /// Floor decoration: sits under everything and never blocks walking.
  final bool floor;

  /// Hangs on a wall instead of standing on the floor: it takes up no room,
  /// and faces into the room from the back wall or the left wall.
  final bool hung;

  /// Restaurant level that unlocks it.
  final int unlock;

  /// What it does, in a sentence for the player.
  final String info;

  /// What it does for the seats near it, if anything.
  final Aura? aura;

  /// Whether the Rotate button does anything to it.
  bool get rotates => turns;

  /// Whether it has a front that matters.
  bool get turns =>
      hung ||
      (role != Role.decor && role != Role.table && role != Role.window) ||
      // A table two tiles long lies one way or the other.
      (role == Role.table && w != h);

  int get refund => cost ~/ 2;
}

const Map<Kind, FixtureDef> fixtureDefs = {
  Kind.grill: FixtureDef(
    Kind.grill,
    'Grill',
    60,
    Role.station,
    info:
        'Cooks burgers, one at a time. Staff stand on the tile in front to '
        'load it and take the burger off.',
  ),
  Kind.fryer: FixtureDef(
    Kind.fryer,
    'Fryer',
    90,
    Role.station,
    unlock: 2,
    info: 'Cooks fries, one batch at a time. Staff use it from the front.',
  ),
  Kind.soda: FixtureDef(
    Kind.soda,
    'Soda machine',
    110,
    Role.station,
    unlock: 3,
    info: 'Pours drinks fast. Staff use it from the front.',
  ),
  Kind.espresso: FixtureDef(
    Kind.espresso,
    'Espresso machine',
    130,
    Role.station,
    unlock: 4,
    info: 'Makes coffee. Staff use it from the front, and need to know how.',
  ),
  Kind.oven: FixtureDef(
    Kind.oven,
    'Pizza oven',
    200,
    Role.station,
    unlock: 5,
    info:
        'Bakes pizza, slowly. Only someone who knows pizza can use it, and '
        'staff use it from the front.',
  ),
  Kind.freezer: FixtureDef(
    Kind.freezer,
    'Ice cream freezer',
    160,
    Role.station,
    unlock: 6,
    info: 'Scoops ice cream, quickly. Staff use it from the front.',
  ),
  Kind.window: FixtureDef(
    Kind.window,
    'Takeaway window',
    180,
    Role.window,
    w: 2,
    unlock: 3,
    info:
        'A hatch two tiles wide in the right-hand wall, onto the side '
        'street. Cars queue there for it. Anyone can serve it, and someone '
        'you set to the window stays on it. Staff bring the food to the '
        'tiles behind it.',
  ),
  Kind.counter: FixtureDef(
    Kind.counter,
    'Counter',
    40,
    Role.counter,
    info:
        'Guests pay here, one at a time, standing in front. A second '
        'counter doubles the checkout.',
  ),
  Kind.table: FixtureDef(
    Kind.table,
    'Table',
    30,
    Role.table,
    info: 'Guests eat here. It needs a chair or bench facing it.',
  ),
  Kind.longTable: FixtureDef(
    Kind.longTable,
    'Long table',
    50,
    Role.table,
    w: 2,
    unlock: 2,
    info:
        'Two tiles long, for a bench: every guest on the bench has table '
        'in front of them. Turn it to lie beside the bench.',
  ),
  Kind.chair: FixtureDef(
    Kind.chair,
    'Chair',
    10,
    Role.seat,
    info: 'Seats one guest. Turn it to face a table.',
  ),
  Kind.bench: FixtureDef(
    Kind.bench,
    'Bench',
    40,
    Role.seat,
    w: 2,
    unlock: 2,
    info: 'Seats two guests side by side. Turn it to face a table.',
  ),
  Kind.plant: FixtureDef(
    Kind.plant,
    'Plant',
    15,
    Role.decor,
    aura: Aura(AuraEffect.patience, 1, 0.92),
    info: 'Something green to look at while you wait.',
  ),
  Kind.jukebox: FixtureDef(
    Kind.jukebox,
    'Jukebox',
    120,
    Role.decor,
    unlock: 2,
    aura: Aura(AuraEffect.tips, 3, 1.25),
    info: 'Music puts people in a generous mood.',
  ),
  Kind.tv: FixtureDef(
    Kind.tv,
    'Wall TV',
    150,
    Role.decor,
    w: 2,
    hung: true,
    unlock: 3,
    aura: Aura(AuraEffect.patience, 4, 0.6),
    info:
        'A widescreen set, two tiles wide, hung high on the back or left '
        'wall. Guests near it wait longer.',
  ),
  Kind.rug: FixtureDef(
    Kind.rug,
    'Rug',
    12,
    Role.decor,
    floor: true,
    info: 'Just for looks.',
  ),
  Kind.wall: FixtureDef(
    Kind.wall,
    'Low wall',
    6,
    Role.decor,
    unlock: 2,
    info:
        'A low wall on the edge between two tiles, so it takes no floor '
        'space. Tap near an edge to aim it, and Rotate to put it on the '
        'other side of the tile. People walk around it, and you can see '
        'over it. Leave a gap for a door.',
  ),
  Kind.pass: FixtureDef(
    Kind.pass,
    'Pass',
    60,
    Role.pass,
    unlock: 3,
    info:
        'A serving hatch on the edge between two tiles, with a shelf on both '
        'sides. Cooks leave finished dishes on it, and servers carry them '
        'out, so cooks need not leave their machines. It holds four dishes. '
        'Put it where a wall would go, with a free tile on a side.',
  ),
};

/// One fixture standing on the grid. [at] is its top-left cell.
class Placed {
  Placed(this.id, this.kind, this.at, [this.facing = Dir.sw]);

  final int id;
  final Kind kind;
  Cell at;
  Dir facing;

  FixtureDef get def => fixtureDefs[kind]!;

  /// Footprint in cells now: a bench lies the other way when it faces
  /// `se` or `nw`.
  int get w => (facing == Dir.se || facing == Dir.nw) ? def.h : def.w;
  int get h => (facing == Dir.se || facing == Dir.nw) ? def.w : def.h;

  Iterable<Cell> get cells sync* {
    for (var dy = 0; dy < h; dy++) {
      for (var dx = 0; dx < w; dx++) {
        yield Cell(at.x + dx, at.y + dy);
      }
    }
  }

  /// The cell in front of [c], one of this fixture's cells.
  Cell frontOf(Cell c) => c.step(facing);

  /// The cells just in front of the fixture, outside its footprint.
  Iterable<Cell> get fronts sync* {
    final own = cells.toSet();
    for (final c in cells) {
      final f = frontOf(c);
      if (!own.contains(f)) yield f;
    }
  }
}

/// One section of the plot, bought as a whole. The plot is ten tiles wide and
/// thirteen deep; the restaurant starts with the front left corner and takes
/// on the rest a section at a time. A section can only be bought once the one
/// in front of it (nearer the street) is yours, which also keeps the room one
/// connected shape.
class Plot {
  const Plot(
    this.name,
    this.x0,
    this.y0,
    this.x1,
    this.y1, {
    this.needs,
    this.level = 1,
  });

  final String name;
  final int x0;
  final int y0;
  final int x1;
  final int y1;

  /// The section that has to be yours first.
  final int? needs;

  /// The restaurant level it opens at.
  final int level;

  int get width => x1 - x0 + 1;
  int get height => y1 - y0 + 1;
  int get tiles => width * height;

  bool contains(Cell c) => c.x >= x0 && c.x <= x1 && c.y >= y0 && c.y <= y1;
}

/// A spot a guest can sit: the cell, the table cell in front of it, and the
/// way they face.
class Seat {
  const Seat(this.cell, this.table, this.facing);

  final Cell cell;
  final Cell table;
  final Dir facing;
}

class Problem {
  const Problem(this.at, this.text);

  final Placed at;
  final String text;
}

/// The outcome of checking a layout.
class Report {
  const Report(this.problems, this.missing, this.seats);

  /// Fixtures that don't work, each with why.
  final List<Problem> problems;

  /// Things the diner needs before it can open.
  final List<String> missing;
  final int seats;

  bool get ready => missing.isEmpty;

  Problem? problemFor(Placed p) {
    for (final x in problems) {
      if (x.at == p) return x;
    }
    return null;
  }
}

/// What happened when the player tried to hire, fire or train someone.
enum StaffResult {
  ok,
  noRoom,
  broke,
  tired,
  maxed,
  gone;

  String get message => switch (this) {
    ok => '',
    noRoom => 'No room on the team',
    broke => 'Not enough coins',
    tired => 'Already trained today',
    maxed => 'Already as good as they can be',
    gone => 'They are no longer here',
  };
}

enum PlaceResult {
  ok,
  outside,
  taken,
  entrance,
  broke,
  blocksWay,
  occupied,
  locked,
  wall,
  noRoad,
  onlyOne,
  noRoom,
  hang;

  /// What to tell the player when a placement is refused.
  String get message => switch (this) {
    ok => '',
    outside => 'Outside the room',
    taken => 'That spot is taken',
    entrance => 'Keep the door clear',
    broke => 'Not enough coins',
    blocksWay => 'That would block off part of the room',
    occupied => 'Someone is standing there',
    locked => 'Not unlocked yet',
    wall => 'Goes in the right-hand wall',
    noRoad => 'Needs the room to the right first',
    onlyOne => 'One window is enough',
    noRoom => 'Needs a free tile beside it',
    hang => 'Hangs on the back or left wall',
  };
}

/// What the room looked like before a change, so the change can be undone.
class LayoutStep {
  const LayoutStep(
    this.label,
    this.coins,
    this.items, [
    this.walls = const [],
    this.hatches = const [],
  ]);

  /// What was done, in a few words: "Placed grill".
  final String label;
  final int coins;
  final List<({int id, Kind kind, Cell at, Dir facing})> items;
  final List<Edge> walls;
  final List<Edge> hatches;
}

class Diner {
  Diner({this.coins = 200, Set<int>? owned, Progress? progress, Roster? roster})
    : owned = owned ?? {0},
      progress = progress ?? Progress(),
      roster = roster ?? Roster.starter();

  /// A small working diner: grill and counters along the back wall, two
  /// tables with a chair each, a plant.
  factory Diner.starter() {
    final d = Diner(coins: 120);
    d._put(Kind.grill, const Cell(left, top), Dir.sw);
    d._put(Kind.counter, const Cell(left + 1, top), Dir.sw);
    d._put(Kind.counter, const Cell(left + 2, top), Dir.sw);
    d._put(Kind.plant, const Cell(left + 5, top));
    d._put(Kind.rug, const Cell(left + 2, top + 2));
    d._put(Kind.table, const Cell(left + 1, top + 2));
    d._put(Kind.chair, const Cell(left, top + 2), Dir.se);
    d._put(Kind.table, const Cell(left + 4, top + 2));
    d._put(Kind.chair, const Cell(left + 5, top + 2), Dir.nw);
    return d;
  }

  /// The restaurant starts at column [left] and row [top]. The plot reaches
  /// four columns further left, to [plotLeft], which is bare land until
  /// bought, with the pavement and the neighbours' buildings beyond it.
  static const left = 1;
  static const top = 3;
  static const plotLeft = -3;

  /// The plot's right-hand column and back row. The side street runs just
  /// beyond the column.
  static const plotRight = 10;
  static const plotTop = -13;

  /// The sections of the plot, the first being where the restaurant starts.
  /// Behind the front row, sections are four tiles deep.
  static const plots = [
    Plot('The restaurant', 1, 3, 6, 7),
    Plot('Room to the right', 7, 3, 10, 7, needs: 0, level: 2),
    Plot('Room behind', 1, -1, 6, 2, needs: 0, level: 3),
    Plot('Room behind, right', 7, -1, 10, 2, needs: 1, level: 4),
    Plot('Room further back', 1, -5, 6, -2, needs: 2, level: 5),
    Plot('Room further back, right', 7, -5, 10, -2, needs: 3, level: 6),
    Plot('Room at the back', 1, -9, 6, -6, needs: 4, level: 7),
    Plot('Room at the back, right', 7, -9, 10, -6, needs: 5, level: 8),
    Plot('The last room', 1, -13, 6, -10, needs: 6, level: 9),
    Plot('The last room, right', 7, -13, 10, -10, needs: 7, level: 10),
    // Wings on the left. They come after the rest so a saved game's sections
    // keep their numbers.
    Plot('Room to the left', -3, 3, 0, 7, needs: 0, level: 3),
    Plot('Room behind, left', -3, -1, 0, 2, needs: 10, level: 5),
    Plot('Room further back, left', -3, -5, 0, -2, needs: 11, level: 7),
  ];

  /// The plot's cheapest price a tile, and how much dearer each section
  /// already bought makes the next.
  static const pricePerTile = 6;
  static const priceRise = 0.35;

  int coins;

  /// The goals that have been met, by id. See `goals.dart`.
  final Set<String> goalsDone = {};

  /// Every coin taken at the tills, over all the days played: what the
  /// total-coins leaderboard ranks. Older saves start from their history.
  int totalEarned = 0;

  /// One-off tips already shown, so each is said once.
  final Set<String> hintsSeen = {};

  /// The sections of the plot that are the restaurant's, by index in [plots].
  final Set<int> owned;
  final Progress progress;
  final Roster roster;
  final List<Placed> items = [];

  /// The menu: what is on offer, in order. Kept in step with what the
  /// restaurant can actually make (see [menu]).
  final List<Dish> offered = [];

  /// Dishes the player has taken off the menu themselves, so they are not
  /// put back when there is room.
  final Set<Dish> declined = {};

  /// The ingredients chosen for each dish. Standard if not chosen.
  final Map<Dish, Tier> tiers = {};

  /// How much dearer (or cheaper) than the usual price the player sells each
  /// dish, in percent. A dish not here is sold at the usual price.
  final Map<Dish, int> markup = {};
  static const markupMin = -30;
  static const markupMax = 60;
  static const markupStep = 10;

  int markupOf(Dish d) => markup[d] ?? 0;

  /// Moves the price of [d] by [steps] steps, within limits.
  void nudgePrice(Dish d, int steps) {
    markup[d] = (markupOf(d) + steps * markupStep).clamp(markupMin, markupMax);
    if (markup[d] == 0) markup.remove(d);
  }

  /// What [d] sells for against the recipe's own price: the ingredients' worth
  /// and the player's markup together. A guest buys it if it is within their
  /// means.
  double priceRatio(Dish d) =>
      tierOf(d).priceMul *
      (1 + markupOf(d) / 100) *
      (isSpecial(d) ? specialMul : 1);

  /// The dish chalked up on the board outside, if any. It is on offer for
  /// less, guests ask for it more, and the board draws a few more in.
  Dish? special;

  /// How much of the price comes off the special, and how many more guests
  /// the board brings in.
  static const specialMul = 0.8;
  static const specialDraw = 1.1;

  /// Whether [d] is the special today: it has to be on the menu.
  bool isSpecial(Dish d) => special == d && offered.contains(d);

  /// Whether a board stands outside the door.
  bool get specialActive => special != null && offered.contains(special);

  /// What the board does to the number of guests on foot.
  double get specialLift => specialActive ? specialDraw : 1;

  /// The guests who keep coming back.
  RegularBook regulars = RegularBook();

  /// Who has come, over all the days, and on the last one.
  final Crowd crowd = Crowd();
  Crowd? lastCrowd;

  /// Today's catering order: where it stands, the order itself once it has
  /// been taken, who is cooking it, and whether the restaurant is closed to
  /// customers so everyone can. The day each belongs to is [contractDay]; any
  /// other day it is all forgotten.
  int contractDay = 0;
  ContractState _contractState = ContractState.open;
  Contract? _taken;
  final Set<int> crewIds = {};
  bool closedForOrder = false;

  ContractState get contractState =>
      contractDay == progress.day ? _contractState : ContractState.open;

  /// The order on offer today, if there is one and it is still open.
  Contract? get offer => contractState == ContractState.open
      ? ContractBook.offerFor(progress.day, this)
      : null;

  /// The order taken for today, to be cooked when the day starts.
  Contract? get takenContract =>
      contractState == ContractState.accepted ? _taken : null;

  /// The people on the order today. Everyone, if the doors are closed.
  List<Staff> get crew => [
    for (final s in roster.employees)
      if (closedForOrder || crewIds.contains(s.id)) s,
  ];

  /// Why [c] cannot be taken with [people], or null if it can.
  String? whyNotTake(Contract c, Set<int> people, {bool closed = false}) {
    final team = closed
        ? roster.employees
        : [
            for (final s in roster.employees)
              if (people.contains(s.id)) s,
          ];
    if (team.isEmpty) return 'Choose who will cook it';
    for (final dish in c.lines.keys) {
      if (!team.any((s) => s.canCook(dish))) {
        return 'Nobody chosen can cook ${recipes[dish]!.name.toLowerCase()}';
      }
    }
    if (coins < c.ingredients(this)) {
      return 'Not enough coins for the ingredients';
    }
    return null;
  }

  /// Takes the order for today with [people] on it. Returns whether it was
  /// taken. [closed] shuts the doors to customers for the day, so everyone
  /// can work on it.
  bool takeContract(Contract c, Set<int> people, {bool closed = false}) {
    if (contractState != ContractState.open) return false;
    if (whyNotTake(c, people, closed: closed) != null) return false;
    contractDay = progress.day;
    _contractState = ContractState.accepted;
    _taken = c;
    crewIds
      ..clear()
      ..addAll(people);
    closedForOrder = closed;
    return true;
  }

  /// Turns the offer down for today.
  void passContract() {
    if (contractState != ContractState.open) return;
    contractDay = progress.day;
    _contractState = ContractState.declined;
  }

  /// Takes back an order that has been taken but not started.
  void cancelContract() {
    if (contractState != ContractState.accepted) return;
    _contractState = ContractState.open;
    _taken = null;
    crewIds.clear();
    closedForOrder = false;
  }

  /// Records how the order for [day] ended.
  void closeContract(ContractState result) {
    contractDay = progress.day;
    _contractState = result;
  }

  /// How each of the last days went, oldest first.
  final List<DayLog> history = [];

  /// How many vending machines stand out front, and what they sell.
  int get vendingMachines => progress.upgradeLvl(Upgrade.vending);
  Vend vend = Vend.drinks;

  /// Whether the machines are switched on. Off, they sell nothing and cost
  /// nothing: no stock, no repairs.
  bool vendingOn = true;

  /// How many are working.
  int get vendingActive => vendingOn ? vendingMachines : 0;

  /// What has built up in the machines' coin boxes. It stays there until it is
  /// collected, up to what the boxes hold.
  int vendCash = 0;
  int get vendCashLimit => Vending.boxLimit * vendingMachines;

  /// Empties the coin boxes into the till. Returns what was collected.
  int collectVending() {
    final n = vendCash;
    coins += n;
    vendCash = 0;
    return n;
  }

  /// Where the ingredients come from.
  Supplier supplier = Supplier.standard;

  /// Puts [d] on the board, or takes it off if it is there already. Only
  /// something on the menu can be the special. Returns whether it is now.
  bool toggleSpecial(Dish d) {
    if (special == d) {
      special = null;
      return false;
    }
    if (!offered.contains(d)) return false;
    special = d;
    return true;
  }

  /// What one portion of [d] sells for, before the cook's skill.
  double sellPrice(Dish d) => progress.price(d) * priceRatio(d);

  /// Portions the player has chosen to prepare for the day. A dish not here
  /// gets the forecast.
  final Map<Dish, int> plan = {};
  int _nextId = 1;

  /// Changes to the layout, newest last, that can be undone. Cleared when the
  /// day starts or the plot grows.
  final List<LayoutStep> _undo = [];
  static const undoLimit = 20;

  /// Notes the layout as it is now, before a change called [label].
  void remember(String label) {
    _undo.add(
      LayoutStep(
        label,
        coins,
        [
          for (final p in items)
            (id: p.id, kind: p.kind, at: p.at, facing: p.facing),
        ],
        walls.toList(),
        hatches.toList(),
      ),
    );
    if (_undo.length > undoLimit) _undo.removeAt(0);
  }

  bool get canUndo => _undo.isNotEmpty;

  /// What the next undo would take back, or null if there is nothing.
  String? get undoLabel => _undo.lastOrNull?.label;

  void clearUndo() => _undo.clear();

  /// Takes back the last change: the fixtures go back where they were, and so
  /// do the coins. Returns what was undone, or null if there was nothing.
  String? undo() {
    if (_undo.isEmpty) return null;
    final step = _undo.removeLast();
    items
      ..clear()
      ..addAll([
        for (final i in step.items) Placed(i.id, i.kind, i.at, i.facing),
      ]);
    walls
      ..clear()
      ..addAll(step.walls);
    hatches
      ..clear()
      ..addAll(step.hatches);
    coins = step.coins;
    return step.label;
  }

  /// The front row of the restaurant, at the street, and its right-hand end:
  /// the front widens when the section beside it is bought.
  int get bottom => plots[0].y1;
  int get right => owned.contains(1) ? plots[1].x1 : plots[0].x1;
  int get width => right - left + 1;
  int get height => bottom - top + 1;

  /// The door is in the bottom row, two cells in from the left wall, and it
  /// never moves sideways so growing the room can't put it under a fixture.
  Cell get entrance => Cell(left + 2, bottom);

  /// The pavement cell outside the door: the head of the queue.
  Cell get street => Cell(entrance.x, bottom + 1);

  /// Where guests line up on the pavement, nearest the door first.
  Cell queueSlot(int i) => Cell(entrance.x + i, bottom + 1);

  /// How many guests can queue.
  int get queueLength => 4;

  /// How far the pavement runs each way from the door. Guests come and go
  /// from beyond the edge of the screen.
  static const sidewalkReach = 10;

  /// Where guests step onto the pavement, left and right of the door.
  Cell get arrivalLeft => Cell(entrance.x - sidewalkReach, bottom + 1);
  Cell get arrivalRight => Cell(entrance.x + sidewalkReach, bottom + 1);

  bool isSidewalk(Cell c) =>
      c.y == bottom + 1 && (c.x - entrance.x).abs() <= sidewalkReach;

  /// Part of the restaurant: inside any section that has been bought.
  bool isInside(Cell c) {
    for (final i in owned) {
      if (plots[i].contains(c)) return true;
    }
    return false;
  }

  /// Every cell of the restaurant.
  Iterable<Cell> insideCells() sync* {
    for (final i in owned) {
      final p = plots[i];
      for (var y = p.y0; y <= p.y1; y++) {
        for (var x = p.x0; x <= p.x1; x++) {
          yield Cell(x, y);
        }
      }
    }
  }

  /// Whether [c] is on the plot but not yet the restaurant's.
  bool isLocked(Cell c) {
    for (var i = 0; i < plots.length; i++) {
      if (!owned.contains(i) && plots[i].contains(c)) return true;
    }
    return false;
  }

  /// The sections that could be bought next if there were the money: the
  /// ones whose front neighbour is already the restaurant's.
  List<int> get nextPlots => [
    for (var i = 0; i < plots.length; i++)
      if (!owned.contains(i) && owned.contains(plots[i].needs)) i,
  ];

  /// The rows and columns to keep in view: what is owned, and what could be
  /// bought next, so the player can see where the restaurant can grow.
  Iterable<Plot> get framed sync* {
    for (var i = 0; i < plots.length; i++) {
      if (owned.contains(i) || nextPlots.contains(i)) yield plots[i];
    }
  }

  int get topRow => framed.map((p) => p.y0).reduce((a, b) => a < b ? a : b);
  int get rightCol => framed.map((p) => p.x1).reduce((a, b) => a > b ? a : b);
  int get leftCol => framed.map((p) => p.x0).reduce((a, b) => a < b ? a : b);

  /// Whether [c] is within [radius] tiles of any part of [p].
  bool _near(Placed p, Cell c, int radius) {
    for (final f in p.cells) {
      if ((f.x - c.x).abs() <= radius && (f.y - c.y).abs() <= radius) {
        return true;
      }
    }
    return false;
  }

  /// How much more slowly a guest seated at [c] tires of waiting, from the
  /// decor near them: 1 is the usual, less is slower. It never goes below
  /// [auraFloor], so a room full of screens is not a room nobody ever leaves.
  double drainAt(Cell c) {
    var m = 1.0;
    for (final p in items) {
      final a = p.def.aura;
      if (a != null &&
          a.effect == AuraEffect.patience &&
          _near(p, c, a.radius)) {
        m *= a.strength;
      }
    }
    return m < auraFloor ? auraFloor : m;
  }

  /// How much more a guest seated at [c] tips, from the decor near them.
  double tipAt(Cell c) {
    var m = 1.0;
    for (final p in items) {
      final a = p.def.aura;
      if (a != null && a.effect == AuraEffect.tips && _near(p, c, a.radius)) {
        m *= a.strength;
      }
    }
    return m > tipCeiling ? tipCeiling : m;
  }

  static const auraFloor = 0.4;
  static const tipCeiling = 1.6;

  /// The restaurant's tiles that [p] would reach, for showing where it helps.
  List<Cell> auraCells(Placed p) {
    final a = p.def.aura;
    if (a == null) return const [];
    return [
      for (final c in insideCells())
        if (_near(p, c, a.radius)) c,
    ];
  }

  Placed? objectAt(Cell c) {
    for (final p in items) {
      if (!p.def.floor && !p.def.hung && p.cells.contains(c)) return p;
    }
    return null;
  }

  Placed? floorAt(Cell c) {
    for (final p in items) {
      if (p.def.floor && p.cells.contains(c)) return p;
    }
    return null;
  }

  /// The wall cell a fixture hung at [at] facing [facing] is fixed to: the
  /// one just behind it.
  static Cell wallBehind(Cell at, Dir facing) =>
      facing == Dir.se ? Cell(at.x - 1, at.y) : Cell(at.x, at.y - 1);

  /// Whether a hung fixture can face [facing] at [at]: there has to be a wall
  /// behind it, which is wherever the room ends.
  bool hangs(Cell at, Dir facing) =>
      (facing == Dir.sw || facing == Dir.se) &&
      isInside(at) &&
      !isInside(wallBehind(at, facing));

  /// Whether a [kind] hung with its top-left tile at [at] and facing [facing]
  /// has a wall behind every tile it covers. A wide one needs a stretch of
  /// wall, not just a corner of it.
  bool hangsKind(Kind kind, Cell at, Dir facing) {
    if (facing != Dir.sw && facing != Dir.se) return false;
    final probe = Placed(0, kind, at, facing);
    return probe.cells.every((c) => hangs(c, facing));
  }

  /// The fixture hung over [c], if any.
  Placed? hungAt(Cell c) {
    for (final p in items) {
      if (p.def.hung && p.cells.contains(c)) return p;
    }
    return null;
  }

  /// Whatever the player would pick on tapping [c]: a fixture, else
  /// something hung there, else a rug. Tapping a wall picks what hangs on it.
  Placed? pickAt(Cell c) {
    for (final p in items) {
      if (p.def.hung && p.cells.any((t) => wallBehind(t, p.facing) == c)) {
        return p;
      }
    }
    if (!isInside(c)) return null;
    return objectAt(c) ?? hungAt(c) ?? floorAt(c);
  }

  bool walkable(Cell c) => isInside(c) && objectAt(c) == null;

  /// The walls between tiles. Nobody steps across one, and nobody uses a
  /// machine, counter, table or seat from the far side of one.
  final Set<Edge> walls = {};

  /// The walls that have a serving hatch in them. Each is one of [walls]: a
  /// hatch blocks walking like any wall, and plates are passed through it.
  final Set<Edge> hatches = {};

  /// The tiles beside a hatch where someone can stand to use it.
  List<Cell> hatchSides(Edge e) => [
    for (final c in [e.a, e.b])
      if (walkable(c)) c,
  ];

  /// Whether a wall stands between the touching cells [a] and [b].
  bool wallBetween(Cell a, Cell b) {
    final e = Edge.between(a, b);
    return e != null && walls.contains(e);
  }

  /// Whether someone standing on [from] can step to the touching cell [to]:
  /// it is somewhere to stand, with no wall between.
  bool canWalk(Cell from, Cell to) => walkable(to) && !wallBetween(from, to);

  /// Cells next to [c] a person can stand on, and walk to from it.
  List<Cell> approaches(Cell c) => [
    for (final n in c.neighbors)
      if (canWalk(c, n)) n,
  ];

  /// The takeaway window, if there is one.
  Placed? get window {
    for (final p in items) {
      if (p.kind == Kind.window) return p;
    }
    return null;
  }

  /// Where staff stand to serve the window: the tiles behind it.
  List<Cell> get operatorSpots {
    final w = window;
    if (w == null) return const [];
    return [
      for (var dy = 0; dy < w.h; dy++)
        if (canWalk(Cell(w.at.x, w.at.y + dy), Cell(w.at.x - 1, w.at.y + dy)))
          Cell(w.at.x - 1, w.at.y + dy),
    ];
  }

  /// The first of those, or null if there is no room behind the window.
  Cell? get operatorSpot => operatorSpots.firstOrNull;

  /// Whether cars can be served: a window with room behind it.
  bool get driveThrough => operatorSpots.isNotEmpty;

  /// Cars come up the side street in the lane nearest the building, and turn
  /// round at the window to go back down the other.
  int get inLane => Diner.plotRight + 2;
  int get outLane => Diner.plotRight + 3;

  /// The cell in the street where a car stops at the window.
  Cell? get bay {
    final w = window;
    return w == null ? null : Cell(inLane, w.at.y);
  }

  /// The lane along the main road cars arrive in, and the one beside it for
  /// cars driving past or away.
  int get laneRow => bottom + 3;
  int get passRow => bottom + 4;

  /// A car is two cells long, so those waiting stand three apart.
  static const carSpacing = 3;

  /// Where cars wait for the window, nearest first. Slot 0 is the bay, and
  /// the rest are down the street from it.
  Cell carSlot(int i) => Cell(inLane, window!.at.y + carSpacing * i);

  /// How many cars can wait on the side street, including the one at the
  /// window: the nearer the back, the longer the line.
  int get carQueueLength {
    final w = window;
    if (w == null) return 0;
    return ((bottom + 2 - w.at.y) ~/ carSpacing + 1).clamp(1, 4);
  }

  /// Whether a window could go in the right-hand wall with its top at row
  /// [y].
  bool windowFits(int y, {Placed? ignore}) =>
      check(Kind.window, Cell(right, y), free: true, ignore: ignore) ==
      PlaceResult.ok;

  /// The row nearest [y] where a window can go, or null if none can.
  int? windowRow(int y, {Placed? ignore}) {
    int? best;
    for (var r = top; r <= bottom; r++) {
      if (!windowFits(r, ignore: ignore)) continue;
      if (best == null || (r - y).abs() < (best - y).abs()) best = r;
    }
    return best;
  }

  /// Where cars come on and go off the main road.
  Cell get laneStart => Cell(arrivalLeft.x, laneRow);
  Cell get passStart => Cell(arrivalLeft.x, passRow);
  Cell get laneEnd => Cell(carExit, laneRow);

  /// How far along the road cars go before they are gone: past the edge of
  /// the picture, however much of the restaurant is showing, so they drive
  /// out of sight rather than vanishing in view.
  int get carExit => passRow + (rightCol + 1 - topRow) + 5;

  /// Every cell of [kind] fixtures.
  Iterable<Cell> cellsOf(Kind kind) sync* {
    for (final p in items) {
      if (p.kind == kind) yield* p.cells;
    }
  }

  Iterable<Placed> ofRole(Role r) => items.where((p) => p.def.role == r);

  /// The walkable cells in front of a fixture, where it is used from.
  List<Cell> useCells(Placed p) {
    final own = p.cells.toSet();
    return [
      for (final c in p.cells)
        if (!own.contains(p.frontOf(c)) && canWalk(c, p.frontOf(c)))
          p.frontOf(c),
    ];
  }

  /// Every walkable cell reachable from the door.
  Set<Cell> reachable() {
    final seen = <Cell>{entrance};
    final todo = [entrance];
    while (todo.isNotEmpty) {
      final c = todo.removeLast();
      for (final n in c.neighbors) {
        if (canWalk(c, n) && seen.add(n)) todo.add(n);
      }
    }
    return seen;
  }

  /// The places a guest can sit: a seat with a table in front and somewhere
  /// to walk up from.
  List<Seat> seats() {
    final out = <Seat>[];
    for (final p in ofRole(Role.seat)) {
      for (final c in p.cells) {
        final front = p.frontOf(c);
        if (objectAt(front)?.def.role != Role.table) continue;
        // A wall between the seat and the table keeps them apart.
        if (wallBetween(c, front)) continue;
        if (approaches(c).isEmpty) continue;
        out.add(Seat(c, front, p.facing));
      }
    }
    return out;
  }

  /// How many dishes the menu has room for. It grows with the restaurant.
  int get menuSlots => 1 + (progress.level + 1) ~/ 2;

  /// The recipe level at which premium ingredients become available.
  static const premiumLevel = 3;

  /// The ingredients used for [d]. Premium needs a well-developed recipe.
  Tier tierOf(Dish d) {
    final t = tiers[d] ?? Tier.standard;
    if (t == Tier.premium && progress.recipeLvl(d) < premiumLevel) {
      return Tier.standard;
    }
    return t;
  }

  /// The kinds of machine in the restaurant that nobody on the team is set
  /// to cook at. Whoever is free and able cooks there anyway, so this is a
  /// thing to know, not a fault.
  List<Kind> get uncoveredMachines => [
    for (final k in Kind.values)
      if (ofRole(Role.station).any((p) => p.kind == k) &&
          roster.employees.isNotEmpty &&
          !roster.employees.any((e) => e.cooksAtKind(k)))
        k,
  ];

  /// Whether there is a machine in working order that makes [d].
  bool hasMachineFor(Dish d) => ofRole(
    Role.station,
  ).any((p) => p.kind == recipes[d]!.station && useCells(p).isNotEmpty);

  /// Whether someone on the team knows how to make [d].
  bool someoneCooks(Dish d) => roster.employees.any((s) => s.canCook(d));

  /// Why [d] cannot be sold, or null if it can.
  String? whyNot(Dish d) {
    if (!progress.unlocked(d)) return 'Unlocks at level ${recipes[d]!.unlock}';
    if (!hasMachineFor(d)) {
      return 'Needs a ${fixtureDefs[recipes[d]!.station]!.name.toLowerCase()}';
    }
    if (!someoneCooks(d)) return 'Needs someone who knows how';
    return null;
  }

  bool available(Dish d) => whyNot(d) == null;

  /// What is on the menu today: what the player offered, and what the
  /// restaurant can really make. New dishes join by themselves while there is
  /// room, unless the player has turned them down.
  List<Dish> menu() {
    offered.removeWhere((d) => !available(d));
    for (final d in Dish.values) {
      if (offered.length >= menuSlots) break;
      if (offered.contains(d) || declined.contains(d) || !available(d)) {
        continue;
      }
      offered.add(d);
    }
    return List.of(offered);
  }

  /// Puts [d] on the menu or takes it off. False if it can't be put on: it
  /// can't be made, or the menu is full.
  bool toggleOffer(Dish d) {
    menu();
    if (offered.contains(d)) {
      offered.remove(d);
      declined.add(d);
      return true;
    }
    if (!available(d) || offered.length >= menuSlots) return false;
    declined.remove(d);
    offered.add(d);
    return true;
  }

  /// What a portion of [d] costs in ingredients, at the chosen quality.
  /// Dearer on a day of shortage.
  double unitCost(Dish d) =>
      recipes[d]!.price * tierOf(d).costFrac * today.costMul * supplier.costMul;

  /// What is special about today, if anything.
  DayEvent get today => DayEvent.forDay(progress.day, progress.level);

  /// How many guests to expect today, with the day's event counted in.
  int get expectedToday =>
      (progress.expectedGuests * today.guestMul * specialLift).round();

  /// How many portions of each dish to prepare for [guests] guests, with a
  /// little spare. A guest orders one main, and maybe a side, drink or
  /// dessert, shared between whatever the menu has in each course.
  Map<Dish, int> forecastPlan(int guests) {
    final menu = this.menu();
    final out = <Dish, int>{};
    for (final c in Course.values) {
      final dishes = [
        for (final d in menu)
          if (recipes[d]!.course == c) d,
      ];
      for (final d in dishes) {
        out[d] = (guests * c.appetite / dishes.length * 1.15).ceil();
      }
    }
    return out;
  }

  /// Portions that will be prepared: the player's choice, else the forecast.
  int portions(Dish d) => plan[d] ?? (forecastPlan(expectedToday)[d] ?? 0);

  /// What the ingredients for the day's plan cost.
  int prepCost() {
    var total = 0.0;
    for (final d in menu()) {
      total += portions(d) * unitCost(d);
    }
    return total.round();
  }

  /// What is wrong with the layout, and whether the diner can open.
  Report report() {
    final problems = <Problem>[];
    final seatCells = {for (final s in seats()) s.cell};
    final tablesServed = {for (final s in seats()) s.table};
    for (final p in items) {
      switch (p.def.role) {
        case Role.table:
          if (!p.cells.any(tablesServed.contains)) {
            problems.add(Problem(p, 'Nothing is seated at this table'));
          }
        case Role.seat:
          if (!p.cells.any(seatCells.contains)) {
            final faces = p.cells.any(
              (c) => objectAt(p.frontOf(c))?.def.role == Role.table,
            );
            problems.add(
              Problem(
                p,
                faces
                    ? '${p.def.name} is boxed in'
                    : '${p.def.name} must face a table',
              ),
            );
          }
        case Role.station || Role.counter:
          if (useCells(p).isEmpty) {
            problems.add(
              Problem(p, '${p.def.name} needs a free tile in front'),
            );
          }
        case Role.window:
          if (operatorSpots.isEmpty) {
            problems.add(Problem(p, 'Keep a tile behind the window free'));
          }
        case Role.pass:
        case Role.decor:
      }
    }
    bool usable(Role r, [Kind? k]) => ofRole(
      r,
    ).any((p) => (k == null || p.kind == k) && useCells(p).isNotEmpty);
    final missing = [
      if (!usable(Role.station, Kind.grill)) 'Needs a grill',
      if (!usable(Role.counter)) 'Needs a counter',
      if (seatCells.isEmpty) 'Needs a seat facing a table',
      if (roster.employees.isEmpty) 'Needs someone to work',
      // With a grill but nothing to cook on it, the menu was emptied.
      if (usable(Role.station, Kind.grill) &&
          !menu().any((d) => recipes[d]!.course == Course.main))
        'Needs a main dish on the menu',
    ];
    return Report(problems, missing, seatCells.length);
  }

  /// Which way a new [kind] at [at] should face to start with: seats toward a
  /// neighbouring table, machines toward free floor.
  Dir defaultFacing(Kind kind, Cell at) {
    final def = fixtureDefs[kind]!;
    if (def.hung) {
      return hangsKind(kind, at, Dir.sw) || !hangsKind(kind, at, Dir.se)
          ? Dir.sw
          : Dir.se;
    }
    if (!def.turns) return Dir.sw;
    if (def.role == Role.table) {
      // Lie along the seats that already face it, if there are any.
      var best = Dir.sw;
      var most = 0;
      for (final d in [Dir.sw, Dir.se]) {
        final t = Placed(0, kind, at, d);
        final n = [
          for (final s in ofRole(Role.seat))
            for (final c in s.cells)
              if (t.cells.contains(s.frontOf(c))) c,
        ].length;
        if (n > most) {
          most = n;
          best = d;
        }
      }
      return best;
    }
    final probe = Placed(0, kind, at);
    for (final d in [Dir.sw, Dir.se, Dir.nw, Dir.ne]) {
      probe.facing = d;
      for (final c in probe.cells) {
        final f = probe.frontOf(c);
        final isFront = !probe.cells.contains(f);
        if (!isFront) continue;
        if (def.role == Role.seat) {
          if (objectAt(f)?.def.role == Role.table) return d;
        } else if (walkable(f)) {
          return d;
        }
      }
    }
    return Dir.sw;
  }

  /// Whether a [kind] facing [facing] fits at [at]. [ignore] is a fixture
  /// being moved or turned, treated as not there; [free] skips the price.
  PlaceResult check(
    Kind kind,
    Cell at, {
    Dir facing = Dir.sw,
    Placed? ignore,
    bool free = false,
  }) {
    final def = fixtureDefs[kind]!;
    // Walls and passes stand between tiles now, not on one.
    if (kind == Kind.wall || kind == Kind.pass) return PlaceResult.taken;
    if (def.unlock > progress.level && !free) return PlaceResult.locked;
    final probe = Placed(0, kind, at, kind == Kind.window ? Dir.se : facing);
    for (final c in probe.cells) {
      if (!isInside(c)) return PlaceResult.outside;
    }
    if (def.hung) {
      if (!hangsKind(kind, at, facing)) return PlaceResult.hang;
      final mine = probe.cells.toSet();
      final other = items.where(
        (p) =>
            p.def.hung &&
            p != ignore &&
            p.facing == facing &&
            p.cells.any(mine.contains),
      );
      if (other.isNotEmpty) return PlaceResult.taken;
      if (!free && coins < def.cost) return PlaceResult.broke;
      return PlaceResult.ok;
    }
    for (final c in probe.cells) {
      final other = def.floor ? floorAt(c) : objectAt(c);
      if (other != null && other != ignore) return PlaceResult.taken;
      if (!def.floor && c == entrance) return PlaceResult.entrance;
    }
    if (kind == Kind.window) {
      if (!owned.contains(1)) return PlaceResult.noRoad;
      if (probe.cells.any((c) => c.x != right || c.y < top)) {
        return PlaceResult.wall;
      }
      if (items.any((p) => p.kind == Kind.window && p != ignore)) {
        return PlaceResult.onlyOne;
      }
    }
    if (!free && coins < def.cost) return PlaceResult.broke;
    // No pocket of floor may be cut off from the door.
    if (!def.floor && _shutIn(probe, ignore).isNotEmpty) {
      return PlaceResult.blocksWay;
    }
    return PlaceResult.ok;
  }

  /// The floor tiles nobody can walk to from the door as things stand.
  List<Cell> _shutNow() {
    final open = reachable();
    return [
      for (final c in insideCells())
        if (walkable(c) && !open.contains(c)) c,
    ];
  }

  /// The floor tiles that [probe] standing where it is would newly cut off
  /// from the door, with [ignore] (a fixture being moved or turned) taken
  /// away. A pocket that was already shut in before does not count, so a
  /// piece can still be turned or moved beside one.
  List<Cell> _shutIn(Placed probe, Placed? ignore) {
    final before = _shutNow().toSet();
    final had = ignore != null && items.remove(ignore);
    items.add(probe);
    final shut = [
      for (final c in _shutNow())
        if (!before.contains(c)) c,
    ];
    items.remove(probe);
    if (had) items.add(ignore);
    return shut;
  }

  /// The tiles that putting a [kind] at [at] would shut in, so the player can
  /// be shown where the path is blocked. Empty if it would not.
  List<Cell> cutOff(Kind kind, Cell at, {Dir facing = Dir.sw, Placed? ignore}) {
    final def = fixtureDefs[kind]!;
    if (def.floor || def.hung) return const [];
    final probe = Placed(0, kind, at, kind == Kind.window ? Dir.se : facing);
    if (probe.cells.any((c) => !isInside(c))) return const [];
    return _shutIn(probe, ignore);
  }

  // ----------------------------------------------------------- walls

  /// The tiles a wall on [e] would newly cut off from the door.
  List<Cell> cutOffByWall(Edge e) {
    if (walls.contains(e) || !isInside(e.a) || !isInside(e.b)) {
      return const [];
    }
    final before = _shutNow().toSet();
    walls.add(e);
    final after = _shutNow();
    walls.remove(e);
    return [
      for (final c in after)
        if (!before.contains(c)) c,
    ];
  }

  /// Whether a wall can go on [e]: between two tiles of the restaurant, with
  /// none there already, enough coins, and no tile shut in by it. With [free]
  /// the price and the level do not count.
  PlaceResult checkWall(Edge e, {bool free = false}) {
    final def = fixtureDefs[Kind.wall]!;
    if (def.unlock > progress.level && !free) return PlaceResult.locked;
    if (!isInside(e.a) || !isInside(e.b)) return PlaceResult.outside;
    if (walls.contains(e)) return PlaceResult.taken;
    if (!free && coins < def.cost) return PlaceResult.broke;
    if (cutOffByWall(e).isNotEmpty) return PlaceResult.blocksWay;
    return PlaceResult.ok;
  }

  /// Puts a wall on [e], if it can go there.
  PlaceResult placeWall(Edge e) {
    final r = checkWall(e);
    if (r != PlaceResult.ok) return r;
    remember('Placed wall');
    coins -= fixtureDefs[Kind.wall]!.cost;
    walls.add(e);
    return r;
  }

  /// Takes down the wall on [e] and gives back half its price. False if there
  /// was none.
  bool sellWall(Edge e) {
    if (!walls.contains(e)) return false;
    final hatch = hatches.contains(e);
    remember(hatch ? 'Sold pass' : 'Sold wall');
    walls.remove(e);
    hatches.remove(e);
    coins += fixtureDefs[hatch ? Kind.pass : Kind.wall]!.refund;
    return true;
  }

  /// Whether a serving hatch can go on [e]: a wall edge, or one that could be.
  /// A wall already there is taken in, and its price comes off. It needs a
  /// tile to stand on at one side at least.
  PlaceResult checkHatch(Edge e, {bool free = false}) {
    final def = fixtureDefs[Kind.pass]!;
    if (def.unlock > progress.level && !free) return PlaceResult.locked;
    if (!isInside(e.a) || !isInside(e.b)) return PlaceResult.outside;
    if (hatches.contains(e)) return PlaceResult.taken;
    final wall = walls.contains(e) ? fixtureDefs[Kind.wall]!.refund : 0;
    if (!free && coins < def.cost - wall) return PlaceResult.broke;
    if (hatchSides(e).isEmpty) return PlaceResult.noRoom;
    if (!walls.contains(e) && cutOffByWall(e).isNotEmpty) {
      return PlaceResult.blocksWay;
    }
    return PlaceResult.ok;
  }

  /// Whether the wall on [from] (and its hatch, if it has one) can move to
  /// [to]: not outside the room, onto another wall, or so it shuts a tile in.
  /// Changes nothing.
  PlaceResult checkMove(Edge from, Edge to) {
    if (!walls.contains(from)) return PlaceResult.taken;
    // Put back where it was: nothing to do.
    if (from == to) return PlaceResult.ok;
    final hatch = hatches.contains(from);
    if (!isInside(to.a) || !isInside(to.b)) return PlaceResult.outside;
    if (walls.contains(to)) return PlaceResult.taken;
    if (hatch && hatchSides(to).isEmpty) return PlaceResult.noRoom;
    walls.remove(from);
    final shut = cutOffByWall(to).isNotEmpty;
    walls.add(from);
    return shut ? PlaceResult.blocksWay : PlaceResult.ok;
  }

  PlaceResult moveWall(Edge from, Edge to) {
    final r = checkMove(from, to);
    if (r != PlaceResult.ok || from == to) return r;
    final hatch = hatches.contains(from);
    remember(hatch ? 'Moved pass' : 'Moved wall');
    walls.remove(from);
    hatches.remove(from);
    walls.add(to);
    if (hatch) hatches.add(to);
    return PlaceResult.ok;
  }

  /// Puts a serving hatch on [e], if it can go there.
  PlaceResult placeHatch(Edge e) {
    final r = checkHatch(e);
    if (r != PlaceResult.ok) return r;
    remember('Placed pass');
    if (walls.contains(e)) coins += fixtureDefs[Kind.wall]!.refund;
    coins -= fixtureDefs[Kind.pass]!.cost;
    walls.add(e);
    hatches.add(e);
    return r;
  }

  PlaceResult place(Kind kind, Cell at, [Dir? facing]) {
    final f = kind == Kind.window ? Dir.se : facing ?? defaultFacing(kind, at);
    final r = check(kind, at, facing: f);
    if (r != PlaceResult.ok) return r;
    remember('Placed ${fixtureDefs[kind]!.name.toLowerCase()}');
    coins -= fixtureDefs[kind]!.cost;
    _put(kind, at, f);
    return r;
  }

  Placed _put(Kind kind, Cell at, [Dir facing = Dir.sw]) {
    final p = Placed(_nextId++, kind, at, facing);
    items.add(p);
    return p;
  }

  /// Turns [p] a quarter turn clockwise, if it still fits.
  PlaceResult rotate(Placed p) {
    if (p.kind == Kind.window) return PlaceResult.ok;
    // Something hung turns to the other wall, if it is in the corner; a wall
    // piece turns to run the other way.
    final next = p.def.hung
        ? (p.facing == Dir.sw ? Dir.se : Dir.sw)
        : p.facing.cw;
    final r = check(p.kind, p.at, facing: next, ignore: p, free: true);
    if (r == PlaceResult.ok) {
      remember('Turned ${p.def.name.toLowerCase()}');
      p.facing = next;
    }
    return r;
  }

  /// Moves [p] so its top-left cell is [to], keeping its facing. Free.
  PlaceResult moveTo(Placed p, Cell to) {
    final r = check(p.kind, to, facing: p.facing, ignore: p, free: true);
    if (r == PlaceResult.ok) {
      remember('Moved ${p.def.name.toLowerCase()}');
      p.at = to;
    }
    return r;
  }

  /// Picks [p] up and puts it down with its top-left at [to], facing
  /// [facing]. Free.
  PlaceResult relocate(Placed p, Cell to, Dir facing) {
    if (p.kind == Kind.window) facing = Dir.se;
    final r = check(p.kind, to, facing: facing, ignore: p, free: true);
    if (r == PlaceResult.ok) {
      remember('Moved ${p.def.name.toLowerCase()}');
      p.at = to;
      p.facing = facing;
    }
    return r;
  }

  /// Sells [p] back for half its price.
  void sell(Placed p) {
    if (!items.contains(p)) return;
    remember('Sold ${p.def.name.toLowerCase()}');
    items.remove(p);
    coins += p.def.refund;
  }

  /// What section [i] costs now. The more of the plot is yours, the more each
  /// further section costs.
  int unlockCost(int i) {
    final raw =
        plots[i].tiles * pricePerTile * (1 + priceRise * (owned.length - 1));
    return (raw / 10).round() * 10;
  }

  /// Why section [i] cannot be bought now, or null if it can.
  String? whyLocked(int i) {
    if (owned.contains(i)) return 'Yours already';
    final needs = plots[i].needs;
    if (needs != null && !owned.contains(needs)) {
      return 'Buy ${plots[needs].name.toLowerCase()} first';
    }
    if (progress.level < plots[i].level) {
      return 'Needs restaurant level ${plots[i].level}';
    }
    if (coins < unlockCost(i)) return 'Not enough coins';
    return null;
  }

  bool canUnlock(int i) => whyLocked(i) == null;

  /// When the room grows backwards, whatever hung on the old back wall is left
  /// in the middle of the room. It moves to the new back wall, along the same
  /// stretch if it fits and the nearest that does if not, and is sold back if
  /// there is no room for it.
  void _rehang() {
    for (final p in items.where((p) => p.def.hung).toList()) {
      if (hangsKind(p.kind, p.at, p.facing)) continue;
      if (p.facing == Dir.sw) {
        for (final dx in [0, -1, 1, -2, 2, -3, 3, -4, 4, -5, 5]) {
          final x = p.at.x + dx;
          var y = p.at.y;
          while (isInside(Cell(x, y - 1))) {
            y--;
          }
          final c = Cell(x, y);
          if (check(p.kind, c, facing: Dir.sw, ignore: p, free: true) ==
              PlaceResult.ok) {
            p.at = c;
            break;
          }
        }
      }
      if (!hangsKind(p.kind, p.at, p.facing)) {
        items.remove(p);
        coins += p.def.cost;
      }
    }
  }

  /// Buys section [i]. The window moves out to the new end of the wall when
  /// the front is widened.
  bool unlock(int i) {
    if (!canUnlock(i)) return false;
    coins -= unlockCost(i);
    owned.add(i);
    clearUndo();
    final w = window;
    if (i == 1 && w != null) w.at = Cell(right, w.at.y);
    _rehang();
    return true;
  }

  // ---------------------------------------------------------------- staff

  /// Makes sure there are people looking for work today.
  void lookForStaff() => roster.dropStale(progress.day);

  /// Takes on a candidate: their fee, and a place on the team.
  StaffResult hire(Staff c) {
    if (!roster.candidates.contains(c)) return StaffResult.gone;
    if (roster.employees.length >= progress.staffLimit) {
      return StaffResult.noRoom;
    }
    if (coins < c.fee) return StaffResult.broke;
    coins -= c.fee;
    roster.candidates = [
      for (final x in roster.candidates)
        if (x != c) x,
    ];
    roster.employees.add(c);
    return StaffResult.ok;
  }

  /// Lets someone go, paying them a day's wages if there is the money.
  StaffResult fire(Staff s) {
    if (!roster.employees.remove(s)) return StaffResult.gone;
    coins -= coins < s.severance ? coins : s.severance;
    return StaffResult.ok;
  }

  /// Raises one of their stats by a point, once a day.
  StaffResult train(Staff s, Stat stat) {
    if (!roster.employees.contains(s)) return StaffResult.gone;
    if (s.trainedToday) return StaffResult.tired;
    if (s.stat(stat) >= s.cap(stat)) return StaffResult.maxed;
    final cost = s.trainCost(stat);
    if (coins < cost) return StaffResult.broke;
    coins -= cost;
    s.train(stat);
    return StaffResult.ok;
  }

  /// What it costs to teach someone a dish that needs a trained hand.
  static const teachCost = 150;

  /// Teaches [s] to make [d]. It takes their day, and the price of a course.
  StaffResult teach(Staff s, Dish d) {
    if (!roster.employees.contains(s)) return StaffResult.gone;
    if (!recipes[d]!.skilled || s.canCook(d)) return StaffResult.maxed;
    if (s.trainedToday) return StaffResult.tired;
    if (coins < teachCost) return StaffResult.broke;
    coins -= teachCost;
    s.teach(d);
    s.trainedToday = true;
    return StaffResult.ok;
  }

  /// Pays for an advert, and people answer it. Several adverts in a day each
  /// bring a new set, replacing those who had not been hired.
  StaffResult advertise(Ad ad) {
    lookForStaff();
    if (roster.employees.length >= progress.staffLimit) {
      return StaffResult.noRoom;
    }
    final def = adDefs[ad]!;
    if (coins < def.cost) return StaffResult.broke;
    coins -= def.cost;
    roster.refreshes++;
    roster.rollCandidates(progress.day, progress.level, progress.rating, ad);
    return StaffResult.ok;
  }

  /// The save's format, so a newer game's save is recognised as such. Raise it
  /// when what is saved changes in a way an older game could not read.
  static const saveVersion = 1;

  /// When this was last saved, in milliseconds since 1970. Zero if never.
  int savedAt = 0;

  Map<String, Object?> toJson() => {
    'v': saveVersion,
    'saved': savedAt,
    'coins': coins,
    'owned': owned.toList()..sort(),
    'goals': goalsDone.toList()..sort(),
    'hints': hintsSeen.toList()..sort(),
    'earned': totalEarned,
    'supplier': supplier.name,
    'vend': vend.name,
    'regulars': regulars.toJson(),
    'vendOn': vendingOn,
    'vendCash': vendCash,
    'contract': {
      'day': contractDay,
      'state': _contractState.name,
      'order': _taken?.toJson(),
      'crew': crewIds.toList()..sort(),
      'closed': closedForOrder,
    },
    'crowd': crowd.toJson(),
    'lastCrowd': ?lastCrowd?.toJson(),
    'history': [for (final h in history) h.toJson()],
    if (special != null) 'special': special!.name,
    'progress': progress.toJson(),
    'staff': roster.toJson(),
    'menu': [for (final d in offered) d.name],
    'declined': [for (final d in declined) d.name],
    'tiers': {for (final e in tiers.entries) e.key.name: e.value.name},
    'plan': {for (final e in plan.entries) e.key.name: e.value},
    'markup': {for (final e in markup.entries) e.key.name: e.value},
    'items': [
      for (final p in items)
        {'k': p.kind.name, 'x': p.at.x, 'y': p.at.y, 'f': p.facing.name},
    ],
    if (walls.isNotEmpty)
      'walls': [for (final e in walls.toList()..sort(_byPlace)) e.toJson()],
    if (hatches.isNotEmpty)
      'hatches': [for (final e in hatches.toList()..sort(_byPlace)) e.toJson()],
  };

  /// Turns the walls and passes an older save stood on tiles into edges. A
  /// wall on a tile with neighbours in a row becomes the edge on the tile's
  /// north side (a run along x) or west side (a run along y), and one that
  /// joined both ways gets both, so a corner stays a corner. A pass becomes a
  /// hatch on the edge it faced along.
  void _convertTileWalls(List<(Kind, Cell, Dir)> tiles) {
    final at = {for (final t in tiles) t.$2};
    void add(Edge e, {bool hatch = false}) {
      if (!isInside(e.a) || !isInside(e.b)) return;
      walls.add(e);
      if (hatch) hatches.add(e);
    }

    for (final (kind, c, facing) in tiles) {
      final alongX = !(facing == Dir.se || facing == Dir.nw);
      if (kind == Kind.pass) {
        add(Edge(c.x, c.y, alongX), hatch: true);
        continue;
      }
      var horizontal =
          at.contains(Cell(c.x + 1, c.y)) || at.contains(Cell(c.x - 1, c.y));
      var vertical =
          at.contains(Cell(c.x, c.y + 1)) || at.contains(Cell(c.x, c.y - 1));
      if (!horizontal && !vertical) {
        horizontal = alongX;
        vertical = !alongX;
      }
      if (horizontal) add(Edge(c.x, c.y, true));
      if (vertical) add(Edge(c.x, c.y, false));
    }
  }

  static int _byPlace(Edge a, Edge b) {
    final y = a.y.compareTo(b.y);
    if (y != 0) return y;
    final x = a.x.compareTo(b.x);
    return x != 0 ? x : (a.alongX ? 1 : 0).compareTo(b.alongX ? 1 : 0);
  }

  static Diner fromJson(Map<String, Object?> j) {
    final d = Diner(
      coins: (j['coins'] as int?) ?? 0,
      progress: Progress.fromJson(j['progress'] as Map<String, Object?>?),
      roster: Roster.fromJson(j['staff']),
    );
    d.supplier =
        Supplier.values.where((x) => x.name == j['supplier']).firstOrNull ??
        Supplier.standard;
    if (d.supplier.unlock > d.progress.level) d.supplier = Supplier.standard;
    d.special = Dish.values.where((x) => x.name == j['special']).firstOrNull;
    d.crowd.add(Crowd.fromJson(j['crowd']));
    if (j['lastCrowd'] != null) d.lastCrowd = Crowd.fromJson(j['lastCrowd']);
    final cj = j['contract'];
    if (cj is Map) {
      d.contractDay = cj['day'] is int ? cj['day'] as int : 0;
      d._contractState =
          ContractState.values
              .where((x) => x.name == cj['state'])
              .firstOrNull ??
          ContractState.open;
      d._taken = Contract.fromJson(cj['order']);
      if (d._contractState == ContractState.accepted && d._taken == null) {
        d._contractState = ContractState.open;
      }
      final crew = cj['crew'];
      if (crew is List) d.crewIds.addAll(crew.whereType<int>());
      d.closedForOrder = cj['closed'] == true;
    }
    d.vend =
        Vend.values.where((x) => x.name == j['vend']).firstOrNull ??
        Vend.drinks;
    d.vendingOn = j['vendOn'] != false;
    d.vendCash = ((j['vendCash'] as int?) ?? 0).clamp(0, 100000);
    d.savedAt = (j['saved'] is int ? j['saved'] as int : 0).clamp(0, 1 << 52);
    d.regulars = RegularBook.fromJson(j['regulars']);
    final hints = j['hints'];
    if (hints is List) d.hintsSeen.addAll(hints.whereType<String>());
    final log = j['history'];
    if (log is List) {
      d.history.addAll([for (final h in log) ?DayLog.fromJson(h)]);
    }
    final total = j['earned'];
    d.totalEarned = total is int
        ? total
        : d.history.fold(
            0,
            (a, h) => a + (h.detailed ? h.income : h.kept.clamp(0, 1 << 30)),
          );
    final done = j['goals'];
    if (done is List) {
      d.goalsDone.addAll([
        for (final g in done)
          if (g is String) g,
      ]);
    }
    final saved = j['owned'];
    if (saved is List) {
      d.owned
        ..clear()
        ..addAll([
          for (final i in saved)
            if (i is int && i >= 0 && i < plots.length) i,
        ])
        ..add(0);
    } else {
      // Saves from when the room grew wider, deeper and into a yard: the
      // width becomes the section beside it, the yard those behind.
      final wide = (j['wide'] as int?) ?? 0;
      final old = [(0, 0), (1, 0), (1, 1), (2, 1), (2, 2)];
      final stage = old[((j['stage'] as int?) ?? 0).clamp(0, 4)];
      if (wide >= 1 || (j['wide'] == null && stage.$1 >= 1)) d.owned.add(1);
      if (j['backLot'] == true) {
        d.owned.addAll(d.owned.contains(1) ? {2, 3, 4, 5} : {2, 4});
      }
    }
    Dish? dishNamed(Object? n) =>
        Dish.values.where((x) => x.name == n).firstOrNull;
    for (final n in (j['menu'] as List?) ?? const []) {
      final dish = dishNamed(n);
      if (dish != null) d.offered.add(dish);
    }
    for (final n in (j['declined'] as List?) ?? const []) {
      final dish = dishNamed(n);
      if (dish != null) d.declined.add(dish);
    }
    final tiers = j['tiers'];
    if (tiers is Map) {
      for (final e in tiers.entries) {
        final dish = dishNamed(e.key);
        final tier = Tier.values.where((t) => t.name == e.value).firstOrNull;
        if (dish != null && tier != null) d.tiers[dish] = tier;
      }
    }
    final mk = j['markup'];
    if (mk is Map) {
      for (final e in mk.entries) {
        final dish = dishNamed(e.key);
        if (dish != null && e.value is int) {
          final v = (e.value as int).clamp(markupMin, markupMax);
          if (v != 0) d.markup[dish] = v;
        }
      }
    }
    final plan = j['plan'];
    if (plan is Map) {
      for (final e in plan.entries) {
        final dish = dishNamed(e.key);
        if (dish != null && e.value is int) {
          d.plan[dish] = (e.value as int).clamp(0, 200);
        }
      }
    }
    // Walls and passes used to stand on a tile; they stand between tiles now.
    final legacy = <(Kind, Cell, Dir)>[];
    for (final raw in (j['items'] as List?) ?? const []) {
      final m = raw as Map;
      final kind = Kind.values.where((k) => k.name == m['k']).firstOrNull;
      if (kind == null) continue;
      final at = Cell(m['x'] as int, m['y'] as int);
      var facing =
          Dir.values.where((f) => f.name == m['f']).firstOrNull ?? Dir.sw;
      if (kind == Kind.wall || kind == Kind.pass) {
        legacy.add((kind, at, facing));
        continue;
      }
      if (kind == Kind.window) facing = Dir.se;
      // Re-validate so a bad save can't put things outside the room. Whatever
      // no longer fits is sold back at full price.
      final probe = Placed(0, kind, at, facing);
      final fits =
          probe.cells.every(d.isInside) &&
          (!fixtureDefs[kind]!.hung || d.hangsKind(kind, at, facing)) &&
          (kind != Kind.window ||
              probe.cells.every((c) => c.x == d.right && c.y >= top));
      if (fits) {
        d._put(kind, at, facing);
      } else {
        d.coins += fixtureDefs[kind]!.cost;
      }
    }
    d._convertTileWalls(legacy);
    // Walls between tiles: only those still between two tiles of the room.
    for (final raw in (j['walls'] as List?) ?? const []) {
      final e = Edge.fromJson(raw);
      if (e != null && d.isInside(e.a) && d.isInside(e.b)) d.walls.add(e);
    }
    for (final raw in (j['hatches'] as List?) ?? const []) {
      final e = Edge.fromJson(raw);
      if (e != null && d.walls.contains(e)) d.hatches.add(e);
    }
    return d;
  }
}
