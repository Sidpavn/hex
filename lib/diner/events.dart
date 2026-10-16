import 'dart:math' as math;

/// What makes a day different: a crowd at lunch, rain, a festival, a quiet
/// spell, a shortage, or a food critic. Which one comes is fixed by the day
/// and the restaurant's level, so the morning's notice is always right.
enum DayEvent {
  none('Ordinary day', ''),
  lunchRush('Lunch rush', 'Extra guests all come at once, around midday.'),
  rain('Rainy day', 'Fewer people on foot, but more come by car.'),
  festival(
    'Street festival',
    'A bigger crowd, and most of them are watching '
        'their money.',
  ),
  quiet('Quiet day', 'Fewer guests than usual.'),
  shortage('Supplier shortage', 'Ingredients cost more today.'),
  critic(
    'Food critic',
    'A critic visits today. Only a premium dish will impress them.',
  ),
  blogger(
    'Food blogger',
    'A blogger visits today. They want fair prices and a short wait.',
  );

  const DayEvent(this.label, this.blurb);

  final String label;
  final String blurb;

  /// How many guests on foot, against the usual.
  double get guestMul => switch (this) {
    DayEvent.festival => 1.4,
    DayEvent.rain => 0.75,
    DayEvent.quiet => 0.7,
    _ => 1.0,
  };

  /// How many cars, against the usual.
  double get carMul => this == DayEvent.rain ? 1.7 : 1.0;

  /// How much ingredients cost, against the usual.
  double get costMul => this == DayEvent.shortage ? 1.35 : 1.0;

  /// The share of the day's guests who arrive in one bunch at midday, on top
  /// of the usual.
  double get peakShare => this == DayEvent.lunchRush ? 0.35 : 0;

  /// The chance that a guest on foot is a thrifty one, whatever else they
  /// would have been.
  double get thriftyShift => this == DayEvent.festival ? 0.35 : 0;

  /// The first day has nothing special. A critic needs a restaurant worth
  /// reviewing, and the means to cook a premium dish.
  static const criticLevel = 4;
  static const bloggerLevel = 3;

  /// Someone comes to review the place.
  bool get reviewed => this == DayEvent.critic || this == DayEvent.blogger;

  /// The event on [day] for a restaurant at [level].
  static DayEvent forDay(int day, int level) {
    if (day <= 1) return DayEvent.none;
    final rng = math.Random(day * 7919 + 13);
    if (rng.nextDouble() >= 0.45) return DayEvent.none;
    final pool = <DayEvent, int>{
      DayEvent.lunchRush: 20,
      DayEvent.rain: 15,
      DayEvent.festival: 10,
      DayEvent.quiet: 15,
      DayEvent.shortage: 15,
      if (level >= criticLevel) DayEvent.critic: 25,
      if (level >= bloggerLevel) DayEvent.blogger: 20,
    };
    var pick = rng.nextInt(pool.values.reduce((a, b) => a + b));
    for (final e in pool.entries) {
      if (pick < e.value) return e.key;
      pick -= e.value;
    }
    return DayEvent.none;
  }
}
