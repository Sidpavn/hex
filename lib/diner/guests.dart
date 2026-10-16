/// What kind of guest someone is: how much they will pay, and how long they
/// will wait. Rolled when they arrive, and visible when they are tapped.
library;

/// How much a guest will pay. [tolerance] is the dearest a dish may be, as a
/// multiple of the recipe's own price: a thrifty guest turns down premium
/// ingredients unless they are on offer, a big spender does not blink at them.
enum Wallet {
  thrifty('Thrifty', 1.0, 0.5),
  regular('Regular', 1.3, 1.0),
  wealthy('Big spender', 1.8, 1.6);

  const Wallet(this.label, this.tolerance, this.tipMul);

  final String label;
  final double tolerance;

  /// How generous they are with a tip, against the usual.
  final double tipMul;

  /// Whether a dish at [ratio] times its recipe price is within their means.
  bool accepts(double ratio) => ratio <= tolerance + 1e-9;

  /// Rolls a wallet from [r], 0 to 1. A better rating draws a richer crowd.
  static Wallet roll(double rating, double r) {
    final wealthy = 0.10 + 0.06 * rating;
    final thrifty = (0.45 - 0.06 * rating).clamp(0.10, 0.45);
    if (r < thrifty) return Wallet.thrifty;
    if (r < thrifty + (1 - thrifty - wealthy)) return Wallet.regular;
    return Wallet.wealthy;
  }
}

/// How long a guest will wait, against the usual.
enum Temper {
  hasty('Hasty', 0.7),
  steady('Steady', 1.0),
  easygoing('Easygoing', 1.35);

  const Temper(this.label, this.patienceMul);

  final String label;
  final double patienceMul;

  static Temper roll(double r) => r < 0.25
      ? Temper.hasty
      : r < 0.80
      ? Temper.steady
      : Temper.easygoing;
}

/// Who a guest is, for the restaurant's books. It decides the name they go
/// by and which of the look-alikes they are drawn as.
enum Gender {
  woman(
    'Women',
    'woman',
    0.47,
    [
      'Marge',
      'Priya',
      'Ines',
      'Mina',
      'Luz',
      'Bea',
      'Dot',
      'Nell',
      'Zoe',
      'Fern',
      'Val',
      'Opal',
      'Tove',
      'Wanda',
    ],
    ['cust_b', 'cust_d', 'cust_e', 'cust_f'],
  ),
  man(
    'Men',
    'man',
    0.47,
    [
      'Joe',
      'Walt',
      'Gus',
      'Hank',
      'Otis',
      'Raj',
      'Abe',
      'Stan',
      'Ned',
      'Cyrus',
      'Sid',
      'Mo',
      'Lou',
    ],
    ['cust_a', 'cust_c', 'cust_e'],
  ),
  nonbinary(
    'Non-binary',
    'non-binary guest',
    0.06,
    ['Kit', 'Pat', 'Rue', 'Sam', 'Robin', 'Quinn', 'Ash', 'Remy', 'Bay'],
    ['cust_a', 'cust_b', 'cust_c', 'cust_d', 'cust_e', 'cust_f'],
  );

  const Gender(this.label, this.singular, this.share, this.names, this.looks);

  /// For a list of the crowd: "Women".
  final String label;

  /// For one guest: "woman".
  final String singular;

  /// How much of the crowd, before anything else is considered.
  final double share;

  /// Names they might go by, and the figures that might be drawn for them.
  final List<String> names;
  final List<String> looks;

  /// Rolls a gender from [r], 0 to 1.
  static Gender roll(double r) {
    var left = r;
    for (final g in Gender.values) {
      if (left < g.share) return g;
      left -= g.share;
    }
    return Gender.man;
  }
}
