import 'dart:math' as math;

/// Where the ingredients come from. The market is cheap but some of it goes
/// bad; the farm costs more and guests tip a little better for it.
enum Supplier {
  market(
    'Budget market',
    'Cheapest. Some of every delivery arrives spoiled, and now and then a lot of it.',
    costMul: 0.8,
  ),
  standard(
    'Usual supplier',
    'Fair prices, and everything arrives fit to cook.',
    costMul: 1,
  ),
  farm(
    'Farm delivery',
    'Dearer, but the food is fresh and guests tip more.',
    costMul: 1.25,
    tipMul: 1.1,
    unlock: 3,
  );

  const Supplier(
    this.label,
    this.blurb, {
    required this.costMul,
    this.tipMul = 1,
    this.unlock = 1,
  });

  final String label;
  final String blurb;

  /// What ingredients cost, against the usual.
  final double costMul;

  /// What guests tip, against the usual.
  final double tipMul;

  /// Restaurant level that opens an account with them.
  final int unlock;

  /// The share of the day's portions that arrive spoiled on [day]. Fixed by the
  /// day, so the morning's shopping is the same however often it is looked at.
  double spoiledShare(int day) {
    if (this != Supplier.market) return 0;
    final bad = math.Random(day * 6151 + 29).nextDouble() < 0.2;
    return bad ? 0.35 : 0.1;
  }
}
