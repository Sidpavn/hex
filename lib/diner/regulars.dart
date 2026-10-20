import 'guests.dart';
import 'recipes.dart';

/// Someone who keeps coming back. They have a favourite dish, a wallet and a
/// temper that do not change, and how fond of the restaurant they are rises
/// and falls with how they are treated. A fonder regular comes more often,
/// tips more and waits longer.
class Regular {
  Regular({
    required this.id,
    required this.name,
    required this.gender,
    required this.look,
    required this.wallet,
    required this.temper,
    required this.favourite,
    this.points = startPoints,
    this.visits = 1,
    this.firstDay = 0,
    this.lastDay = 0,
  });

  final int id;
  final String name;
  final Gender gender;

  /// Which figure they are drawn as.
  final String look;
  final Wallet wallet;
  final Temper temper;

  /// What they come for.
  final Dish favourite;

  /// How fond of the place they are, 0 to [maxPoints], three to a heart.
  int points;
  int visits;
  int firstDay;
  int lastDay;

  static const startPoints = 3;
  static const maxPoints = 15;

  /// Whole hearts, 0 to 5.
  int get hearts => (points ~/ 3).clamp(0, 5);

  /// What they tip, against another guest: a little more per heart.
  double get tipMul => 1 + 0.08 * hearts;

  /// How long they will wait, against what they would otherwise: they forgive.
  double get patienceMul => 1 + 0.06 * hearts;

  /// How likely they are to come on a given day.
  double get chance => (0.35 + 0.1 * hearts).clamp(0.0, 0.85);

  /// How likely they are to bring a friend, when they come.
  double get friendChance => 0.08 * hearts;

  void give(int by) => points = (points + by).clamp(0, maxPoints);

  /// How many days away before they start to drift.
  static const driftAfter = 10;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'gender': gender.name,
    'look': look,
    'wallet': wallet.name,
    'temper': temper.name,
    'fav': favourite.name,
    'points': points,
    'visits': visits,
    'first': firstDay,
    'last': lastDay,
  };

  static Regular? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final dish = Dish.values.where((d) => d.name == raw['fav']).firstOrNull;
    final gender = Gender.values
        .where((g) => g.name == raw['gender'])
        .firstOrNull;
    final wallet = Wallet.values
        .where((w) => w.name == raw['wallet'])
        .firstOrNull;
    final temper = Temper.values
        .where((t) => t.name == raw['temper'])
        .firstOrNull;
    if (raw['id'] is! int ||
        raw['name'] is! String ||
        dish == null ||
        gender == null ||
        wallet == null ||
        temper == null) {
      return null;
    }
    int n(String k, int fallback) => raw[k] is int ? raw[k] as int : fallback;
    return Regular(
      id: raw['id'] as int,
      name: raw['name'] as String,
      gender: gender,
      look: raw['look'] is String ? raw['look'] as String : gender.looks.first,
      wallet: wallet,
      temper: temper,
      favourite: dish,
      points: n('points', startPoints).clamp(0, maxPoints),
      visits: n('visits', 1).clamp(1, 100000),
      firstDay: n('first', 0),
      lastDay: n('last', 0),
    );
  }
}

/// The restaurant's regulars, and how many it can hold.
class RegularBook {
  RegularBook();

  final List<Regular> people = [];
  int nextId = 1;

  /// How many regulars there can be: a few to begin with, more as the
  /// restaurant grows.
  static int cap(int level) => 3 + level;

  /// How likely a happy guest is to become one.
  static const joinChance = 0.12;

  bool has(String name) => people.any((r) => r.name == name);

  Map<String, Object?> toJson() => {
    'next': nextId,
    'people': [for (final r in people) r.toJson()],
  };

  static RegularBook fromJson(Object? raw) {
    final book = RegularBook();
    if (raw is! Map) return book;
    final list = raw['people'];
    if (list is List) {
      for (final e in list) {
        final r = Regular.fromJson(e);
        if (r != null && !book.has(r.name)) book.people.add(r);
      }
    }
    final top = book.people.fold(0, (a, r) => r.id > a ? r.id : a);
    book.nextId = raw['next'] is int
        ? (raw['next'] as int).clamp(top + 1, 1 << 30)
        : top + 1;
    return book;
  }
}
