import 'contracts.dart';
import 'diner.dart';
import 'events.dart';
import 'recipes.dart';
import 'service.dart';

/// What the restaurant has done, for working out whether a goal is met: the
/// restaurant as it stands, and the day just ended, if one has.
class GoalFacts {
  const GoalFacts(this.diner, this.day);

  final Diner diner;
  final DayReport? day;

  /// What was kept on [day]: takings less ingredients and wages.
  int get kept => day == null ? 0 : day!.earned - day!.ingredients - day!.wages;
}

/// Something to aim for, with a reward for doing it. The early ones double as
/// the tutorial: each has a [hint] that says how.
class Goal {
  const Goal(this.id, this.title, this.reward, this.done, {this.hint});

  /// Kept in the save, so it never changes.
  final String id;
  final String title;

  /// Coins for doing it.
  final int reward;
  final bool Function(GoalFacts f) done;

  /// How to go about it, for a player who has not yet.
  final String? hint;
}

/// All the goals, in the order they are asked. Anything that depends on the
/// day just ended can only be met when a day ends; the rest as soon as it is
/// true.
final List<Goal> goals = [
  Goal(
    'open',
    'Open the doors',
    30,
    (f) => f.diner.progress.day > 1,
    hint: 'Press Start day when you are ready. Guests come to the door.',
  ),
  Goal(
    'serve10',
    'Serve 10 guests in a day',
    40,
    (f) => (f.day?.served ?? 0) >= 10,
    hint: 'Keep the kitchen busy. Tap a waiting guest to rush their order.',
  ),
  Goal(
    'level2',
    'Reach restaurant level 2',
    40,
    (f) => f.diner.progress.level >= 2,
    hint: 'Serving guests earns experience. A new level unlocks new things.',
  ),
  Goal(
    'rating2',
    'Reach a 2 star rating',
    60,
    (f) => f.diner.progress.reputation >= 40,
    hint:
        'Fed guests and short waits raise your rating. It brings a bigger '
        'crowd.',
  ),
  Goal(
    'fries',
    'Put fries on the menu',
    60,
    (f) => f.diner.menu().contains(Dish.fries),
    hint: 'Buy a fryer from the shelf, then look at the Menu.',
  ),
  Goal(
    'price',
    'Set your own price',
    40,
    (f) => f.diner.markup.isNotEmpty,
    hint:
        'In the Menu, tap a dish and change its price. Thrifty guests will '
        'not pay much.',
  ),
  Goal(
    'hire',
    'Hire a second person',
    80,
    (f) => f.diner.roster.employees.length >= 2,
    hint: 'Upgrades has a Staff room for one more place. Then hire from Staff.',
  ),
  Goal(
    'clean5',
    'Clear 5 tables in a day',
    60,
    (f) => (f.day?.cleaned ?? 0) >= 5,
    hint: 'During the day, tap a messy table to clear it.',
  ),
  Goal(
    'right',
    'Buy the room to the right',
    100,
    (f) => f.diner.owned.contains(1),
    hint: 'Expand shows the plot. Gold outlines are what you can buy.',
  ),
  Goal(
    'tv',
    'Put a TV in the dining room',
    80,
    (f) => f.diner.items.any((p) => p.kind == Kind.tv),
    hint: 'A TV makes guests nearby wait longer. Aim it before you place it.',
  ),
  Goal(
    'seats10',
    'Seat 10 guests at once',
    100,
    (f) => f.diner.seats().length >= 10,
    hint:
        'Chairs, benches and tables each seat guests. Add enough for ten at '
        'once.',
  ),
  Goal(
    'happy',
    'A day when nobody leaves angry',
    150,
    (f) => f.day != null && f.day!.served >= 8 && f.day!.walkouts == 0,
  ),
  Goal(
    'window',
    'Open a takeaway window',
    120,
    (f) => f.diner.window != null,
    hint: 'It goes in the right-hand wall, once you own the room to the right.',
  ),
  Goal('cars5', 'Serve 5 cars in a day', 100, (f) => (f.day?.cars ?? 0) >= 5),
  Goal('kept300', 'Keep 300 coins in a day', 150, (f) => f.kept >= 300),
  Goal(
    'critic',
    'Impress the food critic',
    200,
    (f) => (f.day?.reviewDelta ?? 0) >= 8,
    hint: 'A critic only orders a premium dish. Premium needs recipe level 3.',
  ),
  Goal(
    'blogger',
    'Win over the food blogger',
    150,
    (f) => f.day?.event == DayEvent.blogger && f.day!.reviewDelta >= 6,
    hint:
        'A blogger wants fair prices: no markup above the usual, and a '
        'short wait.',
  ),
  Goal(
    'special',
    'Put a special on the board',
    60,
    (f) => f.diner.specialActive,
    hint:
        'Open a dish in the Menu and make it the special. A board goes '
        'outside the door.',
  ),
  Goal(
    'catering',
    'Send out a catering order',
    120,
    (f) => f.day?.cateringState == ContractState.done,
    hint:
        'Some days bring a catering order. Open it from the card above the '
        'shelf and choose who cooks it.',
  ),
  Goal(
    'vending',
    'Put a vending machine out front',
    80,
    (f) => f.diner.vendingMachines >= 1,
    hint:
        'The Vending machine in Upgrades stands on the pavement and earns '
        'from people walking by.',
  ),
  Goal(
    'supplier',
    'Run a day with another supplier',
    60,
    (f) => f.diner.history.any(
      (h) => h.supplier.isNotEmpty && h.supplier != 'standard',
    ),
    hint:
        "Change supplier in Today's portions. The budget market costs less "
        'but some food arrives spoiled; the farm costs more and guests tip '
        'more.',
  ),
  Goal(
    'regular',
    'Win a regular',
    100,
    (f) => f.diner.regulars.people.isNotEmpty,
    hint:
        'A guest who leaves happy may come back for good. Keep them fed '
        'quickly, with what they like.',
  ),
  Goal(
    'plot',
    'Own the whole plot',
    300,
    (f) => f.diner.owned.length == Diner.plots.length,
  ),
  Goal(
    'supply',
    'Buy better storage',
    100,
    (f) => f.diner.progress.upgradeLvl(Upgrade.supply) >= 1,
    hint:
        'Better storage is in Upgrades, under Kitchen. It cuts how much the '
        "budget market's deliveries spoil.",
  ),
  Goal(
    'pass',
    'Buy a bigger pass',
    100,
    (f) => f.diner.progress.upgradeLvl(Upgrade.pass) >= 1,
    hint:
        'Bigger pass is in Upgrades, under Service. More plates fit on the '
        'shelf for servers to carry out.',
  ),
  Goal(
    'loyalty',
    'Buy loyalty cards',
    100,
    (f) => f.diner.progress.upgradeLvl(Upgrade.loyalty) >= 1,
    hint:
        'Loyalty cards is in Upgrades, under Team. Regulars warm to the '
        'place faster on a happy visit.',
  ),
  Goal(
    'bigTeam',
    'Grow the team to 6',
    150,
    (f) => f.diner.roster.employees.length >= 6,
    hint: 'Staff room in Upgrades makes room for more people on the team.',
  ),
  Goal(
    'level5',
    'Reach restaurant level 5',
    150,
    (f) => f.diner.progress.level >= 5,
    hint: 'Keep serving guests and the level will come. A new location unlocks.',
  ),
  Goal(
    'level10',
    'Reach restaurant level 10',
    200,
    (f) => f.diner.progress.level >= 10,
    hint: 'The highest level takes time. New dishes unlock along the way.',
  ),
  Goal(
    'streak3',
    'Play 3 days in a row',
    150,
    (f) => f.diner.maxStreakDays >= 3,
    hint: 'Open the app on 3 days in a row. A streak bonus arrives each day.',
  ),
  Goal(
    'streak7',
    'Play 7 days in a row',
    300,
    (f) => f.diner.maxStreakDays >= 7,
    hint:
        'Seven days in a row earns the biggest streak bonus. Come back every '
        'day to keep the streak alive.',
  ),
];

/// Working out which goals are met.
extension GoalBook on Diner {
  /// The goal for [id], if there is one.
  Goal? goalNamed(String id) => goals.where((g) => g.id == id).firstOrNull;

  /// The next few goals still to do.
  List<Goal> get activeGoals => [
    for (final g in goals)
      if (!goalsDone.contains(g.id)) g,
  ].take(3).toList();

  /// The goal to point the player at: the first not done.
  Goal? get currentGoal => activeGoals.firstOrNull;

  /// What to say to someone who has not found their feet: the current goal's
  /// hint, if it has one.
  String? get hint {
    final g = currentGoal;
    if (g == null || g.hint == null) return null;
    return 'Goal: ${g.title}. ${g.hint}';
  }

  /// Marks every goal that is now met as done, pays out the rewards, and
  /// returns them. [day] is the day that has just ended, if one has. A goal is
  /// only ever paid once.
  List<Goal> checkGoals([DayReport? day]) {
    final facts = GoalFacts(this, day);
    final met = <Goal>[];
    for (final g in goals) {
      if (goalsDone.contains(g.id) || !g.done(facts)) continue;
      goalsDone.add(g.id);
      coins += g.reward;
      gems += Diner.goalGems;
      met.add(g);
    }
    return met;
  }
}
