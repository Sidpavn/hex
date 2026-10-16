/// What the kitchen can cook, what the player can buy to run it better, and
/// how the restaurant levels up. Pure data and arithmetic.
library;

import 'diner.dart' show Kind;

enum Dish { burger, cheeseburger, pizza, fries, soda, coffee, iceCream }

/// What part of the meal a dish is. A guest orders one main and, if the menu
/// has them, perhaps a side, a drink and a dessert.
enum Course {
  main,
  side,
  drink,
  dessert;

  String get label => switch (this) {
    main => 'Mains',
    side => 'Sides',
    drink => 'Drinks',
    dessert => 'Desserts',
  };

  /// How likely a guest is to order something from this course, when the menu
  /// has it.
  double get appetite => switch (this) {
    main => 1.0,
    side => 0.55,
    drink => 0.65,
    dessert => 0.3,
  };
}

class Recipe {
  const Recipe(
    this.dish,
    this.name,
    this.station,
    this.course,
    this.cook,
    this.price,
    this.unlock, {
    this.skilled = false,
  });

  final Dish dish;
  final String name;

  /// The machine that makes it.
  final Kind station;
  final Course course;

  /// Ticks to cook at level 1 with no kitchen upgrades.
  final int cook;

  /// Coins a guest pays at level 1.
  final int price;

  /// Restaurant level that unlocks it.
  final int unlock;

  /// Needs someone who has been taught how: a specialist, or a person who has
  /// been through the training.
  final bool skilled;
}

const Map<Dish, Recipe> recipes = {
  Dish.burger: Recipe(Dish.burger, 'Burger', Kind.grill, Course.main, 7, 8, 1),
  Dish.cheeseburger: Recipe(
    Dish.cheeseburger,
    'Cheeseburger',
    Kind.grill,
    Course.main,
    9,
    12,
    3,
  ),
  Dish.pizza: Recipe(
    Dish.pizza,
    'Pizza',
    Kind.oven,
    Course.main,
    14,
    18,
    5,
    skilled: true,
  ),
  Dish.fries: Recipe(Dish.fries, 'Fries', Kind.fryer, Course.side, 5, 5, 2),
  Dish.soda: Recipe(Dish.soda, 'Soda', Kind.soda, Course.drink, 3, 4, 3),
  Dish.coffee: Recipe(
    Dish.coffee,
    'Coffee',
    Kind.espresso,
    Course.drink,
    5,
    6,
    4,
    skilled: true,
  ),
  Dish.iceCream: Recipe(
    Dish.iceCream,
    'Ice cream',
    Kind.freezer,
    Course.dessert,
    3,
    6,
    6,
  ),
};

/// How good the ingredients are. Better ingredients cost more, sell for more,
/// and make a restaurant better liked.
enum Tier {
  budget('Budget', 0.92, 0.18, -6),
  standard('Standard', 1.0, 0.26, 0),
  premium('Premium', 1.18, 0.38, 6);

  const Tier(this.label, this.priceMul, this.costFrac, this.rating);

  final String label;

  /// What the dish sells for, as a multiple of the menu price.
  final double priceMul;

  /// What a portion of ingredients costs, as a fraction of the menu price.
  final double costFrac;

  /// Points added to (or taken from) the day's score for the rating.
  final int rating;
}

/// Things to spend coins on between days.
enum Upgrade { kitchen, checkout, cosy, staff, tray }

class UpgradeDef {
  const UpgradeDef(this.name, this.info, this.max, this.cost);

  final String name;
  final String info;
  final int max;

  /// Cost of the first level; each next level costs one more multiple.
  final int cost;
}

const Map<Upgrade, UpgradeDef> upgradeDefs = {
  Upgrade.kitchen: UpgradeDef(
    'Faster kitchen',
    'Every machine cooks 8% quicker.',
    5,
    80,
  ),
  Upgrade.checkout: UpgradeDef(
    'Quicker checkout',
    'Counters take payment faster.',
    2,
    60,
  ),
  Upgrade.cosy: UpgradeDef(
    'Cosy seating',
    'Guests wait 15% longer before they leave.',
    5,
    70,
  ),
  Upgrade.staff: UpgradeDef(
    'Staff room',
    'Room for one more person on the team.',
    3,
    120,
  ),
  Upgrade.tray: UpgradeDef(
    'Bigger tray',
    'Staff carry five dishes at a time, not three.',
    1,
    150,
  ),
};

/// What the restaurant has earned: level, recipe levels and upgrades.
class Progress {
  Progress({
    this.level = 1,
    this.xp = 0,
    this.day = 1,
    this.reputation = startReputation,
    Map<Dish, int>? recipeLevel,
    Map<Upgrade, int>? upgrades,
  }) : recipeLevel = recipeLevel ?? {},
       upgrades = upgrades ?? {};

  int level;

  /// Experience towards the next level.
  int xp;
  int day;

  /// How well liked the restaurant is, 0 to 100, shown as a rating of 0 to 5
  /// stars. It alone decides how many guests come each day: a new place is
  /// unknown, and has to earn its crowd.
  int reputation;
  final Map<Dish, int> recipeLevel;
  final Map<Upgrade, int> upgrades;

  static const maxRecipeLevel = 5;

  /// A new restaurant is hardly known at all.
  static const startReputation = 10;

  /// The rating in stars, 0 to 5.
  double get rating => reputation / 20;

  /// How many guests to expect on a day at this rating: a handful at first,
  /// a crowd for a famous place.
  int get expectedGuests => (5 + reputation * 0.35).round();

  int get xpToNext => 120 * level;

  bool unlocked(Dish d) => level >= recipes[d]!.unlock;

  int recipeLvl(Dish d) => recipeLevel[d] ?? 1;

  int upgradeLvl(Upgrade u) => upgrades[u] ?? 0;

  /// Ticks to cook [d] now.
  int cookTicks(Dish d) {
    final base = recipes[d]!.cook;
    final k = 1 - 0.08 * upgradeLvl(Upgrade.kitchen);
    final r = 1 - 0.06 * (recipeLvl(d) - 1);
    return (base * k * r).round().clamp(2, 99);
  }

  /// Coins one [d] earns now.
  int price(Dish d) =>
      (recipes[d]!.price * (1 + 0.25 * (recipeLvl(d) - 1))).round();

  /// Ticks a counter spends on one guest's payment.
  int get checkoutTicks => (3 - upgradeLvl(Upgrade.checkout)).clamp(1, 3);

  /// How many ticks a guest will wait before leaving.
  int get patience => (70 * (1 + 0.15 * upgradeLvl(Upgrade.cosy))).round();

  /// How many people the restaurant has room to employ.
  int get staffLimit => 1 + upgradeLvl(Upgrade.staff);

  int get carry => 3 + 2 * upgradeLvl(Upgrade.tray);

  int recipeUpgradeCost(Dish d) => 40 * recipeLvl(d);

  bool canLevelRecipe(Dish d) => unlocked(d) && recipeLvl(d) < maxRecipeLevel;

  int? upgradeCost(Upgrade u) {
    final lvl = upgradeLvl(u);
    final def = upgradeDefs[u]!;
    return lvl >= def.max ? null : def.cost * (lvl + 1);
  }

  /// Adds experience; returns how many levels it gained.
  int gain(int amount) {
    xp += amount;
    var gained = 0;
    while (xp >= xpToNext) {
      xp -= xpToNext;
      level++;
      gained++;
    }
    return gained;
  }

  Map<String, Object?> toJson() => {
    'level': level,
    'xp': xp,
    'day': day,
    'rep': reputation,
    'v': 2,
    'recipes': {for (final e in recipeLevel.entries) e.key.name: e.value},
    'upgrades': {for (final e in upgrades.entries) e.key.name: e.value},
  };

  static Progress fromJson(Map<String, Object?>? j) {
    if (j == null) return Progress();
    final p = Progress(
      level: ((j['level'] as int?) ?? 1).clamp(1, 99),
      xp: (j['xp'] as int?) ?? 0,
      day: ((j['day'] as int?) ?? 1).clamp(1, 9999),
      // Saves from before the rating system used reputation differently:
      // start those over as an unknown restaurant.
      reputation: j['v'] == 2
          ? ((j['rep'] as int?) ?? startReputation).clamp(0, 100)
          : startReputation,
    );
    final r = j['recipes'];
    if (r is Map) {
      for (final d in Dish.values) {
        final v = r[d.name];
        if (v is int) p.recipeLevel[d] = v.clamp(1, maxRecipeLevel);
      }
    }
    final u = j['upgrades'];
    if (u is Map) {
      for (final up in Upgrade.values) {
        final v = u[up.name];
        if (v is int) p.upgrades[up] = v.clamp(0, upgradeDefs[up]!.max);
      }
    }
    return p;
  }
}
