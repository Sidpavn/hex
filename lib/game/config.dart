import 'game_controller.dart';
import 'hex.dart';
import 'models.dart';

enum GameMode { skirmish, hotseat, campaign }

enum Objective { eliminate, hold, survive }

extension ObjectiveX on Objective {
  String get label => switch (this) {
    Objective.eliminate => 'Eliminate',
    Objective.hold => 'Hold the centre',
    Objective.survive => 'Survive',
  };

  String get blurb => switch (this) {
    Objective.eliminate => 'Defeat the enemy hero.',
    Objective.hold => 'Keep a unit on the centre hex at the end of your turn.',
    Objective.survive => 'Outlast the enemy for a set number of rounds.',
  };
}

/// How much the enemy AI does on its turn (lessons dial this down).
enum EnemyAi {
  /// Casts cards, summons and moves units.
  full,

  /// Only moves and attacks with the units it already has.
  units,

  /// Does nothing at all: a training dummy.
  passive,
}

/// Things the player can do that advance a coach step.
enum CoachEvent {
  next,
  unitSelected,
  moved,
  attacked,
  cardSelected,
  cardPlayed,
  endedTurn,
  turnStarted,
}

/// One tip in a lesson. It stays on screen until [until] happens.
class CoachStep {
  const CoachStep(
    this.text, {
    this.until = CoachEvent.next,
    this.card,
    this.hexes = const [],
    this.endTurn = false,
  });

  final String text;
  final CoachEvent until;

  /// For card events: only this card counts, and it is highlighted in hand.
  final CardType? card;

  /// Hexes to point at.
  final List<Hex> hexes;

  /// Pulse the End turn button.
  final bool endTurn;
}

typedef BoardSetup = void Function(GameController game);

enum Difficulty { easy, normal, hard }

extension DifficultyX on Difficulty {
  String get label => switch (this) {
    Difficulty.easy => 'Easy',
    Difficulty.normal => 'Normal',
    Difficulty.hard => 'Hard',
  };

  /// Added to the AI's energy income each turn.
  int get energyBonus => switch (this) {
    Difficulty.easy => -1,
    Difficulty.normal => 0,
    Difficulty.hard => 1,
  };

  /// Most non-hero units the AI keeps on the board.
  int get summonCap => switch (this) {
    Difficulty.easy => 3,
    Difficulty.normal => 4,
    Difficulty.hard => 6,
  };

  /// Chance the AI wastes a unit's turn.
  double get blunder => this == Difficulty.easy ? 0.2 : 0;

  /// AI plays Gust / Lightning for kills.
  bool get tactics => this != Difficulty.easy;

  /// AI heals, shields, avoids danger and protects its hero.
  bool get smart => this == Difficulty.hard;
}

/// The cards every player starts with.
const Set<CardType> baseCards = {
  CardType.summonKnight,
  CardType.summonArcher,
  CardType.summonGolem,
  CardType.fireball,
  CardType.gust,
  CardType.heal,
  CardType.dash,
  CardType.shield,
  CardType.grow,
};

class GameConfig {
  const GameConfig({
    this.mode = GameMode.skirmish,
    this.objective = Objective.eliminate,
    this.target = 8,
    this.difficulty = Difficulty.normal,
    this.playerHero = UnitType.hero,
    this.enemyHero = UnitType.hero,
    this.enemyBonusEnergy = 0,
    this.playerStartUnits = const [UnitType.knight],
    this.enemyStartUnits = const [UnitType.knight],
    this.seed,
    this.deck,
    this.level,
    this.enemyAi = EnemyAi.full,
    this.coach = const [],
    this.setup,
    this.roundLimit,
  });

  final GameMode mode;
  final Objective objective;

  /// Rounds to survive, or consecutive turns to hold the centre.
  final int target;
  final Difficulty difficulty;
  final UnitType playerHero;
  final UnitType enemyHero;
  final int enemyBonusEnergy;
  final List<UnitType> playerStartUnits;
  final List<UnitType> enemyStartUnits;

  /// Fixed seed gives the same board every time (used by campaign levels).
  final int? seed;

  /// Cards the draw pile can produce. Null means [baseCards].
  final Set<CardType>? deck;

  /// Index into the campaign level list when playing the campaign.
  final int? level;

  final EnemyAi enemyAi;

  /// If set, the enemy wins when this many rounds pass without a result.
  final int? roundLimit;

  /// Tips shown in order during a lesson or level intro.
  final List<CoachStep> coach;

  /// Rewrites the generated board (used by hand-built lessons).
  final BoardSetup? setup;

  bool get hotseat => mode == GameMode.hotseat;

  GameConfig copyWith({
    Objective? objective,
    int? target,
    Difficulty? difficulty,
    UnitType? playerHero,
    Set<CardType>? deck,
    int? level,
  }) => GameConfig(
    mode: mode,
    objective: objective ?? this.objective,
    target: target ?? this.target,
    difficulty: difficulty ?? this.difficulty,
    playerHero: playerHero ?? this.playerHero,
    enemyHero: enemyHero,
    enemyBonusEnergy: enemyBonusEnergy,
    playerStartUnits: playerStartUnits,
    enemyStartUnits: enemyStartUnits,
    seed: seed,
    deck: deck ?? this.deck,
    level: level ?? this.level,
    enemyAi: enemyAi,
    coach: coach,
    setup: setup,
    roundLimit: roundLimit,
  );
}

class LevelDef {
  const LevelDef({
    required this.name,
    required this.blurb,
    required this.config,
    required this.par,
    this.topic = '',
    this.rewardCards = const [],
    this.rewardHeroes = const [],
  });

  final String name;
  final String blurb;
  final GameConfig config;

  /// Win within this many rounds for three stars.
  final int par;

  /// Short label for lessons, e.g. "Cover".
  final String topic;
  final List<CardType> rewardCards;
  final List<UnitType> rewardHeroes;

  LevelDef atIndex(int i) => LevelDef(
    name: name,
    blurb: blurb,
    config: config.copyWith(level: i),
    par: par,
    topic: topic,
    rewardCards: rewardCards,
    rewardHeroes: rewardHeroes,
  );

  int starsFor(int rounds) => rounds <= par
      ? 3
      : rounds <= par + 3
      ? 2
      : 1;
}
