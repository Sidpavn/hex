import 'dart:math' as math;

/// A loan the bank will make: how much, and the restaurant level it asks for.
class LoanOffer {
  const LoanOffer(this.amount, this.level);

  final int amount;
  final int level;

  /// What has to be paid back: the amount and the bank's fee.
  int get owed => (amount * (1 + Bank.fee)).round();
}

/// The terms of borrowing. One loan at a time, a flat fee instead of
/// compounding interest, paid back a little each night out of the takings.
class Bank {
  static const fee = 0.15;

  /// What a missed night adds to what is owed, and what it does to the rating.
  static const latePenalty = 0.05;
  static const lateRating = 2;

  static const offers = [
    LoanOffer(100, 2),
    LoanOffer(250, 3),
    LoanOffer(500, 5),
  ];

  /// What is due each night on a debt of [owed]: a fifth of it, and at least
  /// 10 coins, or all of it if that is less.
  static int due(int owed) =>
      owed <= 0 ? 0 : math.min(owed, math.max(10, (owed * 0.2).ceil()));

  /// The fee on top of the amount, for showing on a button.
  static int feeOn(LoanOffer o) => o.owed - o.amount;
}
