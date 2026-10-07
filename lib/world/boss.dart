import '../game/models.dart';

/// A boss's signature spell. It aims at where the hero stands, shows the
/// blast area for [warn] turns, then fires. Beating the boss teaches [spell].
class BossKit {
  const BossKit({
    required this.spell,
    required this.hp,
    this.center = 2,
    this.ring = 1,
    this.warn = 2,
    this.cooldown = 3,
    this.range = 6,
  });

  /// Id in `spellDefs`, and what the hero learns on the kill.
  final String spell;

  /// Replaces the unit's own hit points.
  final int hp;

  /// Damage at the aimed hex and to the six around it.
  final int center;
  final int ring;

  /// Turns the area is shown before the blast. The hero moves one hex a turn,
  /// so two turns is enough to clear the ring.
  final int warn;

  /// Turns between one blast and the next warning.
  final int cooldown;

  /// How far away it will start a cast.
  final int range;
}

const Map<UnitType, BossKit> bossKits = {
  UnitType.pyromancer: BossKit(spell: 'fireball', hp: 12),
};
