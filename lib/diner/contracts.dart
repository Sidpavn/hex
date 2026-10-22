import 'diner.dart';
import 'luck.dart';
import 'recipes.dart';

/// Where a catering order stands today.
enum ContractState {
  /// Offered, and neither taken nor turned down.
  open,

  /// Taken: the crew works on it when the day starts.
  accepted,
  declined,

  /// Sent out on time.
  done,

  /// Not ready by closing.
  missed,

  /// Could not be started: the ingredients were not affordable.
  voided,
}

/// A catering order: so many of these dishes, by closing time, for a fixed
/// price. It is cooked by a crew set aside for it, who do not serve the
/// restaurant meanwhile.
class Contract {
  const Contract({
    required this.day,
    required this.client,
    required this.lines,
    required this.reward,
  });

  /// The day it is for.
  final int day;

  /// Who ordered it, in a few words: "the office on Elm Street".
  final String client;

  /// How many of each dish.
  final Map<Dish, int> lines;

  /// What it pays when it goes out.
  final int reward;

  int get portions => lines.values.fold(0, (a, n) => a + n);

  /// What the ingredients cost today, at the going price.
  int ingredients(Diner d) => lines.entries
      .fold(0.0, (a, e) => a + d.unitCost(e.key) * e.value)
      .round();

  /// "12 burgers and 8 fries".
  String get summary {
    final parts = [
      for (final e in lines.entries)
        '${e.value} ${recipes[e.key]!.name.toLowerCase()}',
    ];
    return parts.length < 2
        ? parts.join()
        : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  }

  Map<String, Object?> toJson() => {
    'day': day,
    'client': client,
    'lines': {for (final e in lines.entries) e.key.name: e.value},
    'reward': reward,
  };

  static Contract? fromJson(Object? raw) {
    if (raw is! Map || raw['lines'] is! Map) return null;
    final lines = <Dish, int>{};
    for (final e in (raw['lines'] as Map).entries) {
      final dish = Dish.values.where((d) => d.name == e.key).firstOrNull;
      if (dish != null && e.value is int && (e.value as int) > 0) {
        lines[dish] = (e.value as int).clamp(1, 200);
      }
    }
    if (lines.isEmpty) return null;
    return Contract(
      day: raw['day'] is int ? raw['day'] as int : 0,
      client: raw['client'] is String ? raw['client'] as String : 'a customer',
      lines: lines,
      reward: raw['reward'] is int
          ? (raw['reward'] as int).clamp(0, 100000)
          : 0,
    );
  }
}

/// Offers of catering orders: which days have one, and what is in it.
class ContractBook {
  ContractBook._();

  /// Orders only come to a restaurant people think well of: this many stars
  /// or more. Zero for now, so they can be tried from the first day; it was
  /// 3.5.
  static double minRating = 0.0;

  /// How likely a day is to have an offer.
  static const chance = 0.4;

  /// What not delivering costs in rating, besides the ingredients.
  static const missedRating = 2;

  /// How much more than the menu price an order pays.
  static const premium = 1.5;

  static const clients = [
    'the office on Elm Street',
    'a birthday party',
    'the school bake sale',
    'the book club',
    'the football team',
    'a wedding next door',
    'the night shift at the depot',
    'a film crew',
  ];

  /// The offer for [day], or null if there is none. It is fixed by the day,
  /// the rating and what the restaurant can cook, so it is the same each time
  /// it is looked at.
  static Contract? offerFor(int day, Diner d) {
    if (d.progress.rating < minRating || day <= 1) return null;
    if (dayLuck(day, 31) >= chance) return null;
    final menu = d.menu();
    if (menu.isEmpty) return null;
    // A few dishes from the menu, in an order that belongs to the day.
    final order = [...menu]
      ..sort(
        (a, b) =>
            dayLuck(day, 40 + a.index).compareTo(dayLuck(day, 40 + b.index)),
      );
    final kinds = (1 + (dayLuck(day, 32) * 3).floor()).clamp(1, order.length);
    final dishes = order.take(kinds).toList();
    // How much: more as the restaurant grows.
    final total = 6 + 2 * d.progress.level + (dayLuck(day, 33) * 7).floor();
    final lines = <Dish, int>{};
    var left = total;
    for (var i = 0; i < dishes.length; i++) {
      final n = i == dishes.length - 1 ? left : (left * 0.55).round();
      lines[dishes[i]] = n.clamp(3, 60);
      left -= n;
    }
    final base = lines.entries.fold(
      0.0,
      (a, e) => a + d.progress.price(e.key) * e.value,
    );
    final reward = ((base * premium) / 5).round() * 5;
    final client = clients[(dayLuck(day, 34) * clients.length).floor()];
    return Contract(day: day, client: client, lines: lines, reward: reward);
  }
}
