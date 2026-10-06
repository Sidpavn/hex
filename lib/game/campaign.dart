import 'config.dart';
import 'game_controller.dart';
import 'hex.dart';
import 'models.dart';

/// The first levels of the campaign are lessons.
const int lessonCount = 6;

/// Lessons you must finish before hot-seat unlocks (move, cover, cards).
const int hotseatLessons = 3;

// ───────────────────────── lesson boards ─────────────────────────
//
// Every lesson clears the random board and places things by hand, so the
// coach can point at exact hexes.

const _you = Team.player;
const _foe = Team.enemy;

void _lessonMove(GameController g) {
  g.units.clear();
  g.blankBoard();
  g.placeUnit(_you, g.config.playerHero, const Hex(0, 1));
  g.placeUnit(_foe, UnitType.hero, const Hex(0, -2), hp: 4);
}

void _lessonCover(GameController g) {
  g.units.clear();
  g.blankBoard();
  for (final h in const [Hex(0, 2), Hex(-1, 2), Hex(1, 1), Hex(-1, 1)]) {
    g.setTerrain(h, Terrain.forest);
  }
  g.placeUnit(_you, g.config.playerHero, const Hex(0, 3));
  g.placeUnit(_you, UnitType.knight, const Hex(1, 2));
  g.placeUnit(_foe, UnitType.hero, const Hex(0, -3), hp: 5);
  g.placeUnit(_foe, UnitType.archer, const Hex(0, -1));
}

void _lessonCards(GameController g) {
  g.units.clear();
  g.blankBoard();
  g.placeUnit(_you, g.config.playerHero, const Hex(0, 3));
  g.placeUnit(_foe, UnitType.hero, const Hex(0, -3), hp: 5);
  g.placeUnit(_foe, UnitType.knight, const Hex(0, -2));
  g.setHand(_you, [
    CardType.summonKnight,
    CardType.summonArcher,
    CardType.fireball,
  ]);
}

void _lessonPush(GameController g) {
  g.units.clear();
  g.blankBoard();
  g.setTerrain(const Hex(0, -3), Terrain.lava);
  g.placeUnit(_you, g.config.playerHero, const Hex(0, 3));
  g.placeUnit(_you, UnitType.knight, const Hex(0, 1));
  g.placeUnit(_foe, UnitType.hero, const Hex(0, -2), hp: 6);
  g.setHand(_you, [CardType.gust]);
}

void _lessonFire(GameController g) {
  g.units.clear();
  g.blankBoard();
  for (final h in const [
    Hex(0, -2),
    Hex(1, -2),
    Hex(1, -3),
    Hex(0, -3),
    Hex(-1, -2),
    Hex(-1, -1),
    Hex(0, -1),
  ]) {
    g.setTerrain(h, Terrain.forest);
  }
  g.placeUnit(_you, g.config.playerHero, const Hex(0, 2));
  g.placeUnit(_foe, UnitType.hero, const Hex(0, -2), hp: 3);
  g.setHand(_you, [CardType.fireball]);
}

void _lessonSupport(GameController g) {
  g.units.clear();
  g.blankBoard();
  g.setTerrain(const Hex(0, 1), Terrain.crystal);
  g.placeUnit(_you, g.config.playerHero, const Hex(0, 3));
  g.placeUnit(_you, UnitType.knight, const Hex(1, 2), hp: 2);
  g.placeUnit(_foe, UnitType.hero, const Hex(0, -3), hp: 6);
  g.placeUnit(_foe, UnitType.knight, const Hex(0, -2));
  g.setHand(_you, [CardType.heal, CardType.shield]);
}

LevelDef _lesson(
  String name,
  String topic,
  String blurb,
  int par,
  BoardSetup setup,
  List<CoachStep> coach, {
  EnemyAi ai = EnemyAi.units,
}) => LevelDef(
  name: name,
  topic: topic,
  blurb: blurb,
  par: par,
  config: GameConfig(
    mode: GameMode.campaign,
    difficulty: Difficulty.easy,
    enemyAi: ai,
    playerStartUnits: const [],
    enemyStartUnits: const [],
    coach: coach,
    setup: setup,
  ),
);

final List<LevelDef> campaignLevels = [
  for (final (i, l) in _defs.indexed) l.atIndex(i),
];

final List<LevelDef> _defs = [
  // ── Training ──
  _lesson(
    'First Steps',
    'Move & attack',
    'Learn to move your hero and strike the enemy.',
    4,
    _lessonMove,
    const [
      CoachStep(
        'Welcome! Your Sorcerer is your hero: if it falls, you lose. Tap it.',
        until: CoachEvent.unitSelected,
        hexes: [Hex(0, 1)],
      ),
      CoachStep(
        'Green hexes show where it can move. Tap one next to the enemy hero.',
        until: CoachEvent.moved,
      ),
      CoachStep(
        'Red means an enemy is in range. Tap the enemy hero to attack. '
        'Each unit can move once and act once per turn.',
        until: CoachEvent.attacked,
      ),
      CoachStep(
        'Nicely done. Press End turn to let the enemy act.',
        until: CoachEvent.endedTurn,
        endTurn: true,
      ),
      CoachStep('Select your hero and hit the enemy again to finish the job.'),
    ],
    ai: EnemyAi.passive,
  ),
  _lesson(
    'Forest Cover',
    'Terrain & cover',
    'Forests slow you down, but shield you from damage.',
    8,
    _lessonCover,
    const [
      CoachStep(
        'Forests cost 2 movement to enter but cut incoming damage by 1. '
        'Tap your Sorcerer.',
        until: CoachEvent.unitSelected,
        hexes: [Hex(0, 3)],
      ),
      CoachStep(
        'Move into the glowing forest.',
        until: CoachEvent.moved,
        hexes: [Hex(0, 2)],
      ),
      CoachStep(
        'The enemy Archer shoots from 2–3 hexes away. Look for the "Cover" '
        'tag when it hits. End your turn.',
        until: CoachEvent.endedTurn,
        endTurn: true,
      ),
      CoachStep(
        'Cover turned 2 damage into 1. Now take out the Archer, then the '
        'enemy hero. Archers cannot hit adjacent units.',
      ),
    ],
  ),
  _lesson(
    'Cards & Energy',
    'Cards',
    'Spend energy on cards to summon units and cast spells.',
    6,
    _lessonCards,
    const [
      CoachStep(
        'Cards cost :bolt: energy. You get 3 each turn, shown at the top. '
        'Tap the Knight card (2:bolt:).',
        until: CoachEvent.cardSelected,
        card: CardType.summonKnight,
      ),
      CoachStep(
        'Pick a glowing hex next to your hero to summon the Knight.',
        until: CoachEvent.cardPlayed,
        card: CardType.summonKnight,
      ),
      CoachStep(
        'The Archer costs 1:bolt:, exactly what is left. Play it too.',
        until: CoachEvent.cardPlayed,
        card: CardType.summonArcher,
      ),
      CoachStep(
        'New units can move but not attack the turn they arrive. Move them '
        'forward if you like, then End turn.',
        until: CoachEvent.endedTurn,
        endTurn: true,
      ),
      CoachStep(
        'Energy refills and you draw 2 cards each turn. Cast Fireball (2:bolt:) '
        'at the enemy: it hits a hex and the ring around it.',
        until: CoachEvent.cardPlayed,
        card: CardType.fireball,
      ),
      CoachStep('Now finish the enemy hero to win.'),
    ],
  ),
  _lesson(
    'Knockback',
    'Pushing',
    'Shove enemies into lava and water to destroy them.',
    3,
    _lessonPush,
    const [
      CoachStep(
        'Knights knock enemies back 1 hex when they hit. Lava and water kill '
        'instantly, and the Gust card shoves 2 hexes the same way.',
        hexes: [Hex(0, -3)],
      ),
      CoachStep(
        'Select your Knight and move it to the glowing hex, directly '
        'opposite the lava.',
        until: CoachEvent.moved,
        hexes: [Hex(0, -1)],
      ),
      CoachStep(
        'Now hit the enemy hero and watch it fly into the lava.',
        until: CoachEvent.attacked,
      ),
    ],
    ai: EnemyAi.passive,
  ),
  _lesson(
    'Playing with Fire',
    'Fire',
    'Fireballs ignite forests and burn anyone standing in them.',
    4,
    _lessonFire,
    const [
      CoachStep(
        'Forests burn! Tap the Fireball card.',
        until: CoachEvent.cardSelected,
        card: CardType.fireball,
      ),
      CoachStep(
        'Target the forest the enemy hero stands in.',
        until: CoachEvent.cardPlayed,
        card: CardType.fireball,
        hexes: [Hex(0, -2)],
      ),
      CoachStep(
        'Burning tiles hurt anyone on them at the end of each round, and fire '
        'spreads between forests. End your turn and watch.',
        until: CoachEvent.endedTurn,
        endTurn: true,
      ),
      CoachStep(
        'Never end your turn in flames yourself, unless you are a '
        'Pyromancer who is immune to fire.',
      ),
    ],
    ai: EnemyAi.passive,
  ),
  _lesson(
    'Crystals & Support',
    'Support',
    'Collect crystals, heal allies and block hits.',
    7,
    _lessonSupport,
    const [
      CoachStep(
        'Crystals give +1:bolt: the first time anyone steps on one. Move your '
        'Sorcerer onto the glowing crystal.',
        until: CoachEvent.moved,
        hexes: [Hex(0, 1)],
      ),
      CoachStep(
        'Your Knight is hurt. Heal restores 3 HP: play it on the Knight.',
        until: CoachEvent.cardPlayed,
        card: CardType.heal,
      ),
      CoachStep(
        'Shield blocks the next hit completely. Shield your Sorcerer.',
        until: CoachEvent.cardPlayed,
        card: CardType.shield,
      ),
      CoachStep('You are ready. Defeat the enemy hero!'),
    ],
  ),

  // ── Campaign ──
  const LevelDef(
    name: 'First Blood',
    blurb: 'A lone sorcerer-slayer blocks the road. Show them the cards.',
    par: 7,
    rewardCards: [CardType.summonCavalry],
    config: GameConfig(
      mode: GameMode.campaign,
      difficulty: Difficulty.easy,
      seed: 11,
    ),
  ),
  const LevelDef(
    name: 'Hold the Line',
    blurb: 'Seize the centre hex and keep it for 3 turns in a row.',
    par: 6,
    rewardCards: [CardType.lightning],
    config: GameConfig(
      mode: GameMode.campaign,
      objective: Objective.hold,
      target: 3,
      seed: 22,
      coach: [
        CoachStep(
          'New objective! Keep any unit on the :star: centre hex at the end of '
          'your turn, 3 turns in a row. The enemy wants it too.',
        ),
      ],
    ),
  ),
  const LevelDef(
    name: "Warlord's Challenge",
    blurb: 'A brutal Warlord and his archer demand a duel.',
    par: 8,
    rewardCards: [CardType.summonMage],
    rewardHeroes: [UnitType.warlord],
    config: GameConfig(
      mode: GameMode.campaign,
      enemyHero: UnitType.warlord,
      enemyStartUnits: [UnitType.knight, UnitType.archer],
      seed: 33,
      coach: [
        CoachStep(
          'The Warlord hits for 3 and knocks you back. Keep your hero away '
          'from lava, water and the board edge!',
        ),
      ],
    ),
  ),
  const LevelDef(
    name: 'Last Stand',
    blurb: 'Hold out for 6 rounds against an endless tide.',
    par: 6,
    rewardCards: [CardType.teleport],
    config: GameConfig(
      mode: GameMode.campaign,
      objective: Objective.survive,
      target: 6,
      enemyBonusEnergy: 1,
      seed: 44,
      coach: [
        CoachStep(
          'Survive until round 6 and you win. The enemy gets extra energy '
          'every turn, so keep your hero safe.',
        ),
      ],
    ),
  ),
  const LevelDef(
    name: 'Fire and Fury',
    blurb: 'The Pyromancer is immune to flames. Find another way.',
    par: 9,
    rewardCards: [CardType.summonHealer],
    rewardHeroes: [UnitType.pyromancer],
    config: GameConfig(
      mode: GameMode.campaign,
      enemyHero: UnitType.pyromancer,
      enemyStartUnits: [UnitType.knight, UnitType.golem],
      seed: 55,
      coach: [
        CoachStep(
          'The Pyromancer takes no fire damage. Try Lightning, knockback or '
          'plain steel instead.',
        ),
      ],
    ),
  ),
  const LevelDef(
    name: 'King of the Hill',
    blurb: 'Hold the centre for 4 turns against a ruthless opponent.',
    par: 8,
    rewardCards: [CardType.wall],
    config: GameConfig(
      mode: GameMode.campaign,
      objective: Objective.hold,
      target: 4,
      difficulty: Difficulty.hard,
      seed: 66,
    ),
  ),
  const LevelDef(
    name: 'Siege',
    blurb: 'The Warlord returns with an army. Survive 8 rounds.',
    par: 8,
    config: GameConfig(
      mode: GameMode.campaign,
      objective: Objective.survive,
      target: 8,
      difficulty: Difficulty.hard,
      enemyHero: UnitType.warlord,
      enemyBonusEnergy: 1,
      seed: 77,
    ),
  ),
  const LevelDef(
    name: 'The Titan',
    blurb: 'A colossal boss that summons a Knight every turn. Slay it.',
    par: 12,
    config: GameConfig(
      mode: GameMode.campaign,
      difficulty: Difficulty.hard,
      enemyHero: UnitType.titan,
      enemyStartUnits: [UnitType.knight, UnitType.knight, UnitType.archer],
      enemyBonusEnergy: 1,
      seed: 88,
      coach: [
        CoachStep(
          'The Titan calls a Knight to its side every turn. Strike fast, or '
          'you will be overrun.',
        ),
      ],
    ),
  ),

  // ── Challenge levels: each one hands you a fixed set of cards ──
  const LevelDef(
    name: 'Burn Notice',
    blurb: 'Fire is your friend. Cook the enemy before time runs out.',
    par: 5,
    config: GameConfig(
      mode: GameMode.campaign,
      seed: 101,
      roundLimit: 7,
      deck: {
        CardType.fireball,
        CardType.grow,
        CardType.shield,
        CardType.summonKnight,
        CardType.dash,
        CardType.heal,
      },
      coach: [
        CoachStep(
          'Challenge levels give you a fixed set of cards and a clock: win '
          'within 7 rounds (see :hourglass: at the top). Grow forests, then burn them.',
        ),
      ],
    ),
  ),
  const LevelDef(
    name: 'Gale Force',
    blurb: 'Shove, wall and blink your way to a win.',
    par: 5,
    config: GameConfig(
      mode: GameMode.campaign,
      seed: 202,
      roundLimit: 8,
      deck: {
        CardType.gust,
        CardType.wall,
        CardType.teleport,
        CardType.dash,
        CardType.summonKnight,
        CardType.shield,
      },
    ),
  ),
  const LevelDef(
    name: 'Glass Cannons',
    blurb: 'Fragile, deadly casters against a stronger foe.',
    par: 7,
    config: GameConfig(
      mode: GameMode.campaign,
      seed: 303,
      roundLimit: 9,
      enemyBonusEnergy: 1,
      deck: {
        CardType.lightning,
        CardType.summonMage,
        CardType.summonArcher,
        CardType.summonHealer,
        CardType.shield,
        CardType.heal,
      },
    ),
  ),
  const LevelDef(
    name: 'Crystal Rush',
    blurb: 'Grab the centre fast with mobile units.',
    par: 6,
    config: GameConfig(
      mode: GameMode.campaign,
      objective: Objective.hold,
      target: 3,
      difficulty: Difficulty.hard,
      seed: 404,
      roundLimit: 9,
      deck: {
        CardType.teleport,
        CardType.dash,
        CardType.summonCavalry,
        CardType.shield,
        CardType.wall,
        CardType.summonKnight,
      },
    ),
  ),
  const LevelDef(
    name: 'Iron Wall',
    blurb: 'Dig in with walls, golems and healers for 7 rounds.',
    par: 7,
    config: GameConfig(
      mode: GameMode.campaign,
      objective: Objective.survive,
      target: 7,
      enemyBonusEnergy: 1,
      seed: 505,
      deck: {
        CardType.wall,
        CardType.summonGolem,
        CardType.heal,
        CardType.shield,
        CardType.summonKnight,
        CardType.summonHealer,
      },
    ),
  ),
  const LevelDef(
    name: 'Blitz',
    blurb: 'Five rounds. No time to waste.',
    par: 4,
    config: GameConfig(
      mode: GameMode.campaign,
      difficulty: Difficulty.hard,
      seed: 606,
      roundLimit: 5,
      deck: {
        CardType.dash,
        CardType.summonCavalry,
        CardType.lightning,
        CardType.fireball,
        CardType.gust,
        CardType.teleport,
      },
    ),
  ),
  const LevelDef(
    name: "Warlord's Revenge",
    blurb: 'The Warlord, harder than ever, with every card at your side.',
    par: 9,
    config: GameConfig(
      mode: GameMode.campaign,
      difficulty: Difficulty.hard,
      enemyHero: UnitType.warlord,
      enemyStartUnits: [UnitType.knight, UnitType.knight, UnitType.archer],
      enemyBonusEnergy: 1,
      seed: 707,
      roundLimit: 12,
    ),
  ),
  const LevelDef(
    name: "Titan's Wrath",
    blurb: 'The final battle. The Titan is not alone.',
    par: 12,
    config: GameConfig(
      mode: GameMode.campaign,
      difficulty: Difficulty.hard,
      enemyHero: UnitType.titan,
      enemyStartUnits: [UnitType.golem, UnitType.golem, UnitType.knight],
      enemyBonusEnergy: 2,
      seed: 808,
      coach: [
        CoachStep(
          'The final test. The Titan calls a Knight every turn and brought '
          'Golems. Use everything you have learned.',
        ),
      ],
    ),
  ),
];
