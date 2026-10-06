import '../game/hex.dart';
import '../game/models.dart';

enum WeaponKind { sword, bow }

class Weapon {
  const Weapon(
    this.kind,
    this.name,
    this.damage,
    this.minRange,
    this.maxRange,
    this.icon,
    this.blurb,
  );

  final WeaponKind kind;
  final String name;

  /// Base damage before upgrades.
  final int damage;
  final int minRange;
  final int maxRange;
  final String icon;
  final String blurb;
}

const Map<WeaponKind, Weapon> weapons = {
  WeaponKind.sword: Weapon(
    WeaponKind.sword,
    'Iron Sword',
    3,
    1,
    1,
    'swords',
    'Hits hard, but you have to be right next to them.',
  ),
  WeaponKind.bow: Weapon(
    WeaponKind.bow,
    'Short Bow',
    2,
    2,
    4,
    'archer',
    'Shoots 2 to 4 hexes. Needs a clear line of sight.',
  ),
};

/// Things a rested, saved hero carries between zones.
class WorldState {
  static final int maxHp = unitStats[UnitType.hero]!.maxHp;
  static const int maxMana = 4;
  static const int maxUpgrade = 2;

  int hp = maxHp;
  int mana = maxMana;
  WeaponKind equipped = WeaponKind.sword;
  final Map<WeaponKind, int> upgrades = {
    WeaponKind.sword: 0,
    WeaponKind.bow: 0,
  };
  int tokens = 0;

  /// Enemies killed since the last rest, as `zone#index`.
  final Set<String> slain = {};

  /// Pickups already taken, as `zone#id`.
  final Set<String> collected = {};

  /// Quest items carried.
  final Set<String> inventory = {};

  /// Quest id to stage.
  final Map<String, int> quests = {};

  /// The last campsite rested at. Falling returns you here.
  ({String zone, Hex hex})? camp;

  Weapon get weapon => weapons[equipped]!;

  int damageOf(WeaponKind k) => weapons[k]!.damage + upgrades[k]!;

  /// Tokens needed for the next upgrade of [k] (1, then 2).
  int upgradeCost(WeaponKind k) => upgrades[k]! + 1;

  bool canUpgrade(WeaponKind k) =>
      upgrades[k]! < maxUpgrade && tokens >= upgradeCost(k);

  bool upgrade(WeaponKind k) {
    if (!canUpgrade(k)) return false;
    tokens -= upgradeCost(k);
    upgrades[k] = upgrades[k]! + 1;
    return true;
  }
}
