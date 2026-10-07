import 'dart:ui';

import 'hex.dart';

enum Team { player, enemy }

extension TeamX on Team {
  Team get other => this == Team.player ? Team.enemy : Team.player;
}

enum Terrain { grass, forest, water, lava, crystal, mountain }

class Tile {
  Tile(this.terrain, {this.fire = 0, this.introDelay = 0});

  Terrain terrain;

  /// Rounds of burning left. Burning tiles hurt units standing on them.
  int fire;

  /// Seconds before this tile drops in during the board intro animation.
  double introDelay;

  bool get walkable =>
      terrain != Terrain.water &&
      terrain != Terrain.lava &&
      terrain != Terrain.mountain;
}

enum UnitType {
  hero,
  knight,
  archer,
  golem,
  cavalry,
  mage,
  healer,
  warlord,
  pyromancer,
  titan,

  /// A training post. Only exists in Explore zones; never fights back.
  post,
}

class UnitStats {
  const UnitStats({
    required this.name,
    required this.maxHp,
    required this.move,
    required this.damage,
    this.minRange = 1,
    this.maxRange = 1,
    this.pushes = false,
    this.splash = false,
    this.heals = false,
    this.hero = false,
    this.fireImmune = false,
    this.summons = false,
    this.inert = false,
    this.blurb = '',
  });

  final String name;
  final int maxHp;
  final int move;
  final int damage;
  final int minRange;
  final int maxRange;

  /// Melee hits knock the target back one hex.
  final bool pushes;

  /// Hits also deal 1 damage to foes next to the target.
  final bool splash;

  /// Can spend its action to restore 2 HP to a wounded ally in range.
  final bool heals;

  /// Losing this unit loses the game.
  final bool hero;

  /// Takes no damage from burning tiles or fireballs.
  final bool fireImmune;

  /// Calls a Knight to its side at the start of every turn.
  final bool summons;

  /// Never acts and never dies; hits on it are only counted.
  final bool inert;

  final String blurb;
}

const Map<UnitType, UnitStats> unitStats = {
  UnitType.hero: UnitStats(
    name: 'Sorcerer',
    maxHp: 8,
    move: 2,
    damage: 2,
    hero: true,
    blurb: 'Balanced all-rounder.',
  ),
  UnitType.knight: UnitStats(
    name: 'Knight',
    maxHp: 5,
    move: 2,
    damage: 2,
    pushes: true,
  ),
  UnitType.archer: UnitStats(
    name: 'Archer',
    maxHp: 3,
    move: 2,
    damage: 2,
    minRange: 2,
    maxRange: 3,
  ),
  UnitType.golem: UnitStats(name: 'Golem', maxHp: 8, move: 1, damage: 3),
  UnitType.cavalry: UnitStats(name: 'Cavalry', maxHp: 4, move: 4, damage: 2),
  UnitType.mage: UnitStats(
    name: 'Mage',
    maxHp: 3,
    move: 2,
    damage: 2,
    minRange: 2,
    maxRange: 3,
    splash: true,
  ),
  UnitType.healer: UnitStats(
    name: 'Healer',
    maxHp: 3,
    move: 2,
    damage: 1,
    maxRange: 2,
    heals: true,
  ),
  UnitType.warlord: UnitStats(
    name: 'Warlord',
    maxHp: 9,
    move: 2,
    damage: 3,
    pushes: true,
    hero: true,
    blurb: 'Hits for 3 and knocks foes back.',
  ),
  UnitType.pyromancer: UnitStats(
    name: 'Pyromancer',
    maxHp: 7,
    move: 2,
    damage: 2,
    maxRange: 2,
    hero: true,
    fireImmune: true,
    blurb: 'Immune to fire. Attacks from 2 hexes away.',
  ),
  UnitType.titan: UnitStats(
    name: 'Titan',
    maxHp: 14,
    move: 1,
    damage: 3,
    hero: true,
    summons: true,
    blurb: 'Colossal boss. Calls a Knight every turn.',
  ),
  UnitType.post: UnitStats(
    name: 'Training post',
    maxHp: 99,
    move: 0,
    damage: 0,
    inert: true,
  ),
};

const List<UnitType> playableHeroes = [
  UnitType.hero,
  UnitType.warlord,
  UnitType.pyromancer,
];

class Unit {
  Unit({
    required this.id,
    required this.team,
    required this.type,
    required this.pos,
  }) : hp = unitStats[type]!.maxHp,
       vq = pos.q.toDouble(),
       vr = pos.r.toDouble();

  final int id;
  final Team team;
  final UnitType type;
  Hex pos;
  int hp;
  int shield = 0;
  bool canMove = true;
  bool canAct = true;
  int bonusMove = 0;

  // Visual state, advanced by the view each frame.
  double vq;
  double vr;
  List<Hex> path = [];
  double spawn = 0;
  double flash = 0;
  double lunge = 0;
  Hex? lungeTo;
  double hop = 0;

  UnitStats get stats => unitStats[type]!;
  bool get isHero => stats.hero;
}

enum CardType {
  summonKnight,
  summonArcher,
  summonGolem,
  fireball,
  gust,
  heal,
  dash,
  shield,
  grow,
  summonCavalry,
  summonMage,
  summonHealer,
  lightning,
  teleport,
  wall,
}

/// Which unit each summon card calls.
const Map<CardType, UnitType> summonOf = {
  CardType.summonKnight: UnitType.knight,
  CardType.summonArcher: UnitType.archer,
  CardType.summonGolem: UnitType.golem,
  CardType.summonCavalry: UnitType.cavalry,
  CardType.summonMage: UnitType.mage,
  CardType.summonHealer: UnitType.healer,
};

/// The card that summons [t], used to look up its cost.
CardType summonCardFor(UnitType t) =>
    summonOf.entries.firstWhere((e) => e.value == t).key;

int summonCost(UnitType t) => cardInfo[summonCardFor(t)]!.cost;

class CardInfo {
  const CardInfo(this.name, this.cost, this.icon, this.desc, this.color);

  final String name;
  final int cost;

  /// Pixel icon name (a unit type for summon cards).
  final String icon;
  final String desc;
  final Color color;
}

const Map<CardType, CardInfo> cardInfo = {
  CardType.summonKnight: CardInfo(
    'Knight',
    2,
    'knight',
    'Summon a Knight. Its hits knock foes back.',
    Color(0xFF3C6FB5),
  ),
  CardType.summonArcher: CardInfo(
    'Archer',
    1,
    'archer',
    'Summon an Archer. Shoots 2-3 hexes.',
    Color(0xFF4A7FC9),
  ),
  CardType.summonGolem: CardInfo(
    'Golem',
    3,
    'golem',
    'Summon a Golem. Slow but hits for 3.',
    Color(0xFF5B6FA0),
  ),
  CardType.fireball: CardInfo(
    'Fireball',
    2,
    'fire',
    'Blast a hex for 2 and its ring for 1. Ignites forests!',
    Color(0xFFD9542C),
  ),
  CardType.gust: CardInfo(
    'Gust',
    1,
    'gust',
    'Shove a unit 2 hexes. Water and lava kill. Heroes resist.',
    Color(0xFF3FA7B8),
  ),
  CardType.heal: CardInfo(
    'Heal',
    1,
    'heal',
    'Restore 3 HP to an ally.',
    Color(0xFF4FAE6A),
  ),
  CardType.dash: CardInfo(
    'Dash',
    1,
    'dash',
    '+2 move and an ally can move again.',
    Color(0xFFD99A2B),
  ),
  CardType.shield: CardInfo(
    'Shield',
    1,
    'shield',
    'Block the next hit completely.',
    Color(0xFF7A6BD1),
  ),
  CardType.grow: CardInfo(
    'Grow',
    1,
    'tree',
    'Turn grass into forest for cover.',
    Color(0xFF3E8E4D),
  ),
  CardType.summonCavalry: CardInfo(
    'Cavalry',
    2,
    'cavalry',
    'Summon Cavalry. Moves 4 hexes.',
    Color(0xFF8A6B3C),
  ),
  CardType.summonMage: CardInfo(
    'Mage',
    2,
    'mage',
    'Summon a Mage. Blasts also scorch adjacent foes.',
    Color(0xFF8A4FC9),
  ),
  CardType.summonHealer: CardInfo(
    'Healer',
    1,
    'healer',
    'Summon a Healer. Mends 2 HP from 2 hexes.',
    Color(0xFF3FA88A),
  ),
  CardType.lightning: CardInfo(
    'Lightning',
    2,
    'bolt',
    'Strike a foe within 5 for 3. Ignores cover.',
    Color(0xFFC9A82B),
  ),
  CardType.teleport: CardInfo(
    'Teleport',
    1,
    'portal',
    'Blink your hero up to 4 hexes.',
    Color(0xFF9B59B6),
  ),
  CardType.wall: CardInfo(
    'Rock Wall',
    1,
    'mountain',
    'Raise an impassable mountain within 4 hexes.',
    Color(0xFF7D7F86),
  ),
};

class GameCard {
  GameCard(this.id, this.type);

  final int id;
  final CardType type;

  CardInfo get info => cardInfo[type]!;
}

enum FxKind {
  text,
  explosion,
  projectile,
  spawn,
  heal,
  splash,
  ghost,
  shake,
  banner,
  flame,
}

/// A one-shot visual cue emitted by the game logic for the view to animate.
class FxEvent {
  const FxEvent(
    this.kind, {
    this.at,
    this.to,
    this.text = '',
    this.color = const Color(0xFFFFFFFF),
    this.delay = 0,
    this.amount = 1,
    this.unit,
    this.spin = false,
  });

  final FxKind kind;
  final Hex? at;
  final Hex? to;
  final String text;
  final Color color;
  final double delay;
  final double amount;
  final Unit? unit;
  final bool spin;
}
