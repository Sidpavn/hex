import 'guests.dart';
import 'recipes.dart';

/// One slice of the crowd: how many were fed, how many left without eating,
/// and what the fed ones spent. For a dish it is portions sold, portions
/// thrown away, what they took, and what their ingredients cost.
class Tally {
  Tally({this.served = 0, this.lost = 0, this.spent = 0, this.cost = 0});

  int served;
  int lost;
  int spent;
  int cost;

  /// What was left after the ingredients.
  int get profit => spent - cost;

  int get total => served + lost;

  /// What each guest who was fed spent, tips included.
  double get average => served == 0 ? 0 : spent / served;

  void add(Tally o) {
    served += o.served;
    lost += o.lost;
    spent += o.spent;
    cost += o.cost;
  }

  Map<String, Object?> toJson() => {
    's': served,
    'l': lost,
    'c': spent,
    if (cost != 0) 'k': cost,
  };

  static Tally fromJson(Object? j) {
    if (j is! Map) return Tally();
    int n(String k) => (j[k] is int) ? (j[k] as int).clamp(0, 1 << 30) : 0;
    return Tally(served: n('s'), lost: n('l'), spent: n('c'), cost: n('k'));
  }
}

/// Who came to the restaurant, and what they ordered: by gender, by how much
/// they will spend, and by dish. Kept for one day and for all of them.
class Crowd {
  Crowd();

  final Map<Gender, Tally> gender = {};
  final Map<Wallet, Tally> wallet = {};

  /// Portions sold of each dish, and what they brought in.
  final Map<Dish, Tally> dishes = {};

  /// How many guests arrived in each eighth of the opening hours.
  static const slots = 8;
  final List<int> hours = List.filled(slots, 0);

  Tally ofGender(Gender g) => gender[g] ?? Tally();
  Tally ofWallet(Wallet w) => wallet[w] ?? Tally();
  Tally ofDish(Dish d) => dishes[d] ?? Tally();

  int get served => gender.values.fold(0, (a, t) => a + t.served);
  int get lost => gender.values.fold(0, (a, t) => a + t.lost);
  int get total => served + lost;
  bool get isEmpty => total == 0;

  /// A guest who ate and paid [coins], with [portions] of each dish that
  /// brought in [take] coins.
  void fed(
    Gender g,
    Wallet w,
    int coins,
    Map<Dish, (int, int)> bought, {
    Map<Dish, int> costs = const {},
    int? hour,
  }) {
    if (hour != null) hours[hour.clamp(0, slots - 1)]++;
    for (final t in [
      gender.putIfAbsent(g, Tally.new),
      wallet.putIfAbsent(w, Tally.new),
    ]) {
      t.served++;
      t.spent += coins;
    }
    for (final e in bought.entries) {
      final t = dishes.putIfAbsent(e.key, Tally.new);
      t.served += e.value.$1;
      t.spent += e.value.$2;
      t.cost += costs[e.key] ?? 0;
    }
  }

  /// A guest who left, or walked past, without being fed.
  void missed(Gender g, Wallet w, {int? hour}) {
    if (hour != null) hours[hour.clamp(0, slots - 1)]++;
    gender.putIfAbsent(g, Tally.new).lost++;
    wallet.putIfAbsent(w, Tally.new).lost++;
  }

  void add(Crowd o) {
    for (final e in o.gender.entries) {
      gender.putIfAbsent(e.key, Tally.new).add(e.value);
    }
    for (final e in o.wallet.entries) {
      wallet.putIfAbsent(e.key, Tally.new).add(e.value);
    }
    for (final e in o.dishes.entries) {
      dishes.putIfAbsent(e.key, Tally.new).add(e.value);
    }
    for (var i = 0; i < slots; i++) {
      hours[i] += o.hours[i];
    }
  }

  /// Portions of [d] thrown away at closing.
  void thrownAway(Dish d, int portions) {
    if (portions > 0) dishes.putIfAbsent(d, Tally.new).lost += portions;
  }

  /// Dishes by portions sold, best first. Ties go to what earned more.
  List<Dish> bestSellers() =>
      [
        for (final e in dishes.entries)
          if (e.value.served > 0) e.key,
      ]..sort((a, b) {
        final x = dishes[a]!;
        final y = dishes[b]!;
        final c = y.served.compareTo(x.served);
        return c != 0 ? c : y.spent.compareTo(x.spent);
      });

  Map<String, Object?> toJson() => {
    'g': {for (final e in gender.entries) e.key.name: e.value.toJson()},
    'w': {for (final e in wallet.entries) e.key.name: e.value.toJson()},
    'd': {for (final e in dishes.entries) e.key.name: e.value.toJson()},
    'h': hours,
  };

  static Crowd fromJson(Object? j) {
    final c = Crowd();
    if (j is! Map) return c;
    void read<T extends Enum>(Object? raw, List<T> values, Map<T, Tally> into) {
      if (raw is! Map) return;
      for (final e in raw.entries) {
        final k = values.where((v) => v.name == e.key).firstOrNull;
        if (k != null) into[k] = Tally.fromJson(e.value);
      }
    }

    read(j['g'], Gender.values, c.gender);
    read(j['w'], Wallet.values, c.wallet);
    read(j['d'], Dish.values, c.dishes);
    final h = j['h'];
    if (h is List) {
      for (var i = 0; i < slots && i < h.length; i++) {
        if (h[i] is int) c.hours[i] = (h[i] as int).clamp(0, 1 << 30);
      }
    }
    return c;
  }
}

/// One day in the books, for the chart of how the restaurant is doing.
class DayLog {
  const DayLog({
    required this.day,
    required this.kept,
    required this.served,
    required this.walkouts,
    required this.rating,
    this.event = '',
  });

  final int day;

  /// Takings less ingredients and wages.
  final int kept;
  final int served;
  final int walkouts;

  /// Rating at the end of the day, 0 to 100.
  final int rating;

  /// The day's event, by name, or empty.
  final String event;

  /// How many days are kept.
  static const keep = 60;

  Map<String, Object?> toJson() => {
    'd': day,
    'k': kept,
    's': served,
    'w': walkouts,
    'r': rating,
    if (event.isNotEmpty) 'e': event,
  };

  static DayLog? fromJson(Object? j) {
    if (j is! Map) return null;
    int n(String k) => j[k] is int ? j[k] as int : 0;
    return DayLog(
      day: n('d'),
      kept: n('k'),
      served: n('s'),
      walkouts: n('w'),
      rating: n('r'),
      event: j['e'] is String ? j['e'] as String : '',
    );
  }
}
