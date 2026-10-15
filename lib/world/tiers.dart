/// How much tougher a zone's ordinary enemies are. A zone sets its own tier
/// (`tier` line in the zone file), so going back to an old zone never gets
/// harder: difficulty belongs to the place, not to the hero.
///
/// Bosses and nodes are not scaled; their kits in `boss.dart` are tuned one
/// by one.
class Tier {
  const Tier({this.hpPercent = 100, this.damage = 0});

  /// Hit points as a percentage of the unit's base.
  final int hpPercent;

  /// Extra damage on every hit.
  final int damage;
}

/// Index is the tier. Past the end, the last one holds.
const List<Tier> tiers = [
  Tier(),
  Tier(hpPercent: 125, damage: 1),
  Tier(hpPercent: 150, damage: 1),
  Tier(hpPercent: 175, damage: 2),
];

Tier tierOf(int n) => tiers[n.clamp(0, tiers.length - 1)];
