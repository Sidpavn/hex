import 'events.dart';
import 'luck.dart';

/// What the vending machine sells. Each has its own price, what it costs to
/// stock, how many people want it, and weather it suits.
enum Vend {
  drinks('Cold drinks', 3, 1, 0.13, 'Steady: people always want a drink.'),
  snacks('Snacks', 5, 2, 0.11, 'Dearer, and every day much the same.'),
  iceCream(
    'Ice cream',
    5,
    2,
    0.12,
    'Sells well on a fine day, and hardly at all in the rain.',
  );

  const Vend(this.label, this.price, this.cost, this.appeal, this.blurb);

  final String label;

  /// What one costs the customer, and what it costs to stock.
  final int price;
  final int cost;

  /// The share of people walking by who stop for one.
  final double appeal;
  final String blurb;

  /// How the day's event changes how much people want it.
  double weather(DayEvent e) => switch (this) {
    Vend.iceCream =>
      e == DayEvent.rain
          ? 0.35
          : e == DayEvent.festival
          ? 1.3
          : 1.0,
    Vend.drinks => e == DayEvent.rain ? 0.85 : 1.0,
    Vend.snacks => 1.0,
  };
}

/// How the vending machines did on one day.
class VendingDay {
  const VendingDay({
    required this.sold,
    required this.income,
    required this.restock,
    required this.repair,
    required this.broken,
  });

  final int sold;
  final int income;

  /// What the stock cost, and what a breakdown cost.
  final int restock;
  final int repair;
  final bool broken;

  int get net => income - restock - repair;
}

/// The machines out front. They are passive: people walk past, some stop. The
/// day's takings are what is sold, less the stock put in and any repair.
class Vending {
  Vending._();

  /// How many each machine holds.
  static const stockPerMachine = 18;

  /// How likely a machine is to break down on a given day, and what it costs
  /// to put right.
  static const breakChance = 0.07;
  static const repairCost = 20;

  /// The second machine reaches fewer new people than the first.
  static double reach(int machines) => 1 + 0.7 * (machines - 1);

  /// How many people walk by today: more for a place people think well of,
  /// fewer in the rain, more at a festival, and a little different each day.
  static double walkers(int day, double rating, DayEvent event) =>
      (70 + rating * 14) * event.guestMul * (0.85 + 0.3 * dayLuck(day, 60));

  /// What [machines] machines of [product] do on [day].
  static VendingDay run({
    required int day,
    required int machines,
    required Vend product,
    required double rating,
    required DayEvent event,
  }) {
    if (machines <= 0) {
      return const VendingDay(
        sold: 0,
        income: 0,
        restock: 0,
        repair: 0,
        broken: false,
      );
    }
    if (dayLuck(day, 61) < breakChance) {
      return const VendingDay(
        sold: 0,
        income: 0,
        restock: 0,
        repair: repairCost,
        broken: true,
      );
    }
    final stock = stockPerMachine * machines;
    final want =
        walkers(day, rating, event) *
        product.appeal *
        product.weather(event) *
        reach(machines);
    final sold = want.round().clamp(0, stock);
    return VendingDay(
      sold: sold,
      income: sold * product.price,
      restock: stock * product.cost,
      repair: 0,
      broken: false,
    );
  }

  /// What a normal day brings, for the player to weigh: no luck, no
  /// breakdown, no weather.
  static VendingDay forecast({
    required int machines,
    required Vend product,
    required double rating,
  }) {
    final stock = stockPerMachine * machines;
    final want = (70 + rating * 14) * product.appeal * reach(machines);
    final sold = want.round().clamp(0, stock);
    return VendingDay(
      sold: sold,
      income: sold * product.price,
      restock: stock * product.cost,
      repair: 0,
      broken: false,
    );
  }
}
