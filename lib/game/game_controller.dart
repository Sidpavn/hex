import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'config.dart';
import 'hex.dart';
import 'models.dart';

const _fireColor = Color(0xFFFF8A2B);
const _dmgColor = Color(0xFFFF5252);
const _goodColor = Color(0xFF69F0AE);
const _infoColor = Color(0xFFFFFFFF);

/// All game rules and state. The view animates by listening to [fx] events and
/// by repainting whenever this notifies.
class GameController extends ChangeNotifier {
  GameController({
    int? seed,
    this.aiDelayScale = 1.0,
    this.config = const GameConfig(),
  }) : _seed = seed ?? config.seed,
       _rng = math.Random(seed ?? config.seed) {
    newGame();
  }

  static const int radius = BoardLayout.radius;
  static const int handLimit = 6;
  static const playerStart = Hex(-2, 4);
  static const enemyStart = Hex(2, -4);

  final GameConfig config;
  final int? _seed;
  math.Random _rng;

  bool get hotseat => config.hotseat;
  Objective get objective => config.objective;
  static const centre = Hex(0, 0);

  static String teamName(Team t) => t == Team.player ? 'Blue' : 'Red';

  /// Multiplier for AI pauses (use 0 in tests).
  final double aiDelayScale;

  void Function(FxEvent)? fx;

  Map<Hex, Tile> tiles = {};
  List<Unit> units = [];
  Map<Team, List<GameCard>> hands = {Team.player: [], Team.enemy: []};
  Map<Team, int> energies = {Team.player: 0, Team.enemy: 0};
  Map<Team, int> holdTurns = {Team.player: 0, Team.enemy: 0};
  int round = 1;
  Team turn = Team.player;
  Team? winner;
  String winReason = '';
  bool busy = false;

  /// Hot-seat only: the device is being handed to the next player.
  bool passing = false;

  /// The team whose hand and energy the screen shows.
  Team get viewTeam => hotseat ? turn : Team.player;

  List<GameCard> get hand => hands[viewTeam]!;
  set hand(List<GameCard> v) => hands[viewTeam] = v;

  int get energy => energies[viewTeam]!;
  set energy(int v) => energies[viewTeam] = v;

  int get enemyEnergy => energies[Team.enemy]!;
  set enemyEnergy(int v) => energies[Team.enemy] = v;

  Set<CardType> get deck => config.deck ?? baseCards;

  String get _clock {
    final limit = config.roundLimit;
    if (limit == null) return '';
    final left = math.max(0, limit - round + 1);
    return '  ⏳ $left ${left == 1 ? 'round' : 'rounds'} left';
  }

  String get objectiveText => switch (objective) {
    Objective.eliminate => 'Defeat the enemy hero$_clock',
    Objective.hold =>
      '⭐ Hold the centre  Blue ${holdTurns[Team.player]}/${config.target} · '
          'Red ${holdTurns[Team.enemy]}/${config.target}$_clock',
    Objective.survive => 'Survive until round ${config.target}  (round $round)',
  };

  // Coach (tutorial) state.
  int coachIndex = 0;
  bool coachHidden = false;

  Unit? selected;
  GameCard? selectedCard;
  Map<Hex, int> moveTargets = {};
  Set<Hex> attackTargets = {};
  Set<Hex> cardTargets = {};
  String hint = '';

  int _nextId = 1;
  int _gen = 0;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // ───────────────────────── setup ─────────────────────────

  void newGame() {
    _gen++;
    _nextId = 1;
    if (_seed != null) _rng = math.Random(_seed);
    round = 1;
    turn = Team.player;
    winner = null;
    winReason = '';
    busy = false;
    passing = false;
    holdTurns = {Team.player: 0, Team.enemy: 0};
    coachIndex = 0;
    coachHidden = false;
    selected = null;
    selectedCard = null;
    moveTargets = {};
    attackTargets = {};
    cardTargets = {};
    _generateBoard();

    units = [];
    final ph = _addUnit(Team.player, config.playerHero, playerStart);
    final eh = _addUnit(Team.enemy, config.enemyHero, enemyStart);
    for (final t in config.playerStartUnits) {
      _addUnit(Team.player, t, _freeNear(ph.pos));
    }
    for (final t in config.enemyStartUnits) {
      _addUnit(Team.enemy, t, _freeNear(eh.pos));
    }

    hands = {
      Team.player: _openingHand(),
      Team.enemy: hotseat ? _openingHand() : [],
    };
    energies = {Team.player: energyFor(round), Team.enemy: 0};
    config.setup?.call(this);
    hint = 'Tap a unit to move or attack, or play a card.';
    _notify();
  }

  List<GameCard> _openingHand() => [
    for (final t in [CardType.summonArcher, CardType.fireball, CardType.gust])
      GameCard(_nextId++, deck.contains(t) ? t : _randomCardType()),
    GameCard(_nextId++, _randomCardType()),
  ];

  // ───────────────────────── scripted boards + coach ─────────────────────────

  /// Flattens every tile to plain grass with no fire.
  void blankBoard() {
    for (final t in tiles.values) {
      t.terrain = Terrain.grass;
      t.fire = 0;
    }
  }

  void setTerrain(Hex h, Terrain t) => tiles[h]?.terrain = t;

  Unit placeUnit(Team team, UnitType type, Hex at, {int? hp}) {
    final u = _addUnit(team, type, at);
    if (hp != null) u.hp = hp;
    return u;
  }

  void setHand(Team team, List<CardType> cards) {
    hands[team] = [for (final c in cards) GameCard(_nextId++, c)];
  }

  /// The tip currently on screen, if any.
  CoachStep? get coachStep =>
      !coachHidden && winner == null && coachIndex < config.coach.length
      ? config.coach[coachIndex]
      : null;

  /// Moves to the next tip if [e] is what the current one is waiting for.
  void coachEvent(CoachEvent e, {CardType? card}) {
    if (coachIndex >= config.coach.length) return;
    final s = config.coach[coachIndex];
    if (s.until != e) return;
    if (s.card != null &&
        (e == CoachEvent.cardSelected || e == CoachEvent.cardPlayed) &&
        s.card != card) {
      return;
    }
    coachIndex++;
    _notify();
  }

  void coachNext() => coachEvent(CoachEvent.next);

  void hideCoach() {
    coachHidden = true;
    _notify();
  }

  int energyFor(int r) => math.min(3 + (r - 1) ~/ 3, 5);

  Unit _addUnit(Team team, UnitType type, Hex pos) {
    final u = Unit(id: _nextId++, team: team, type: type, pos: pos);
    units.add(u);
    return u;
  }

  /// Nearest walkable, unoccupied hex to [h] (searching outward ring by ring).
  Hex _freeNear(Hex h) {
    for (var d = 1; d <= 4; d++) {
      for (final e in tiles.entries) {
        if (e.key.distanceTo(h) == d &&
            e.value.walkable &&
            unitAt(e.key) == null) {
          return e.key;
        }
      }
    }
    return h;
  }

  void _generateBoard() {
    while (true) {
      final t = <Hex, Tile>{};
      for (var q = -radius; q <= radius; q++) {
        for (
          var r = math.max(-radius, -q - radius);
          r <= math.min(radius, -q + radius);
          r++
        ) {
          final h = Hex(q, r);
          if (t.containsKey(h)) continue;
          final nearSpawn =
              h.distanceTo(playerStart) <= 2 || h.distanceTo(enemyStart) <= 2;
          final roll = _rng.nextDouble();
          var terrain = Terrain.grass;
          if (nearSpawn) {
            if (roll < 0.15) terrain = Terrain.forest;
          } else if (roll < 0.22) {
            terrain = Terrain.forest;
          } else if (roll < 0.29) {
            terrain = Terrain.water;
          } else if (roll < 0.34) {
            terrain = Terrain.lava;
          } else if (roll < 0.40) {
            terrain = Terrain.crystal;
          } else if (roll < 0.45) {
            terrain = Terrain.mountain;
          }
          if (h == centre) terrain = Terrain.grass;
          // Mirror for fairness.
          t[h] = Tile(terrain);
          t[Hex(-q, -r)] = Tile(terrain);
        }
      }
      if (_connected(t, playerStart, enemyStart)) {
        for (final e in t.entries) {
          e.value.introDelay =
              e.key.distanceTo(const Hex(0, 0)) * 0.08 +
              _rng.nextDouble() * 0.18;
        }
        tiles = t;
        return;
      }
    }
  }

  bool _connected(Map<Hex, Tile> t, Hex a, Hex b) {
    final seen = <Hex>{a};
    final queue = Queue<Hex>()..add(a);
    while (queue.isNotEmpty) {
      final c = queue.removeFirst();
      if (c == b) return true;
      for (final n in c.neighbors) {
        final tile = t[n];
        if (tile == null || !tile.walkable || !seen.add(n)) continue;
        queue.add(n);
      }
    }
    return false;
  }

  CardType _randomCardType() {
    const weights = {
      CardType.summonKnight: 3,
      CardType.summonArcher: 3,
      CardType.summonGolem: 2,
      CardType.fireball: 3,
      CardType.gust: 3,
      CardType.heal: 2,
      CardType.dash: 2,
      CardType.shield: 2,
      CardType.grow: 1,
      CardType.summonCavalry: 2,
      CardType.summonMage: 2,
      CardType.summonHealer: 2,
      CardType.lightning: 2,
      CardType.teleport: 1,
      CardType.wall: 1,
    };
    final pool = [
      for (final e in weights.entries)
        if (deck.contains(e.key)) e,
    ];
    final total = pool.fold<int>(0, (a, e) => a + e.value);
    if (total == 0) return CardType.summonKnight;
    var roll = _rng.nextInt(total);
    for (final e in pool) {
      if (roll < e.value) return e.key;
      roll -= e.value;
    }
    return CardType.summonKnight;
  }

  // ───────────────────────── queries ─────────────────────────

  Unit? unitAt(Hex h) {
    for (final u in units) {
      if (u.pos == h) return u;
    }
    return null;
  }

  Unit? heroOf(Team team) {
    for (final u in units) {
      if (u.team == team && u.isHero) return u;
    }
    return null;
  }

  /// True while a human may act (always for Blue, either side in hot-seat).
  bool get isPlayerTurn =>
      (hotseat || turn == Team.player) && !busy && !passing && winner == null;

  bool canAfford(GameCard c) => energy >= c.info.cost;

  ({Map<Hex, int> cost, Map<Hex, Hex> parent}) _search(Unit u) {
    final budget = u.stats.move + u.bonusMove;
    final cost = <Hex, int>{u.pos: 0};
    final parent = <Hex, Hex>{};
    final open = <Hex>[u.pos];
    while (open.isNotEmpty) {
      open.sort((a, b) => cost[a]!.compareTo(cost[b]!));
      final cur = open.removeAt(0);
      for (final n in cur.neighbors) {
        final tile = tiles[n];
        if (tile == null || !tile.walkable) continue;
        final occ = unitAt(n);
        if (occ != null && occ.team != u.team) continue;
        final c = cost[cur]! + (tile.terrain == Terrain.forest ? 2 : 1);
        if (c > budget) continue;
        final known = cost[n];
        if (known == null || c < known) {
          cost[n] = c;
          parent[n] = cur;
          open.add(n);
        }
      }
    }
    return (cost: cost, parent: parent);
  }

  /// Hexes [u] can end its move on, with movement cost.
  Map<Hex, int> reachable(Unit u) {
    final res = <Hex, int>{};
    _search(u).cost.forEach((h, c) {
      if (h != u.pos && unitAt(h) == null) res[h] = c;
    });
    return res;
  }

  bool inAttackRange(Unit a, Hex from, Unit d) {
    final dist = from.distanceTo(d.pos);
    return dist >= a.stats.minRange && dist <= a.stats.maxRange;
  }

  Set<Hex> targetsFor(CardType type) {
    final team = viewTeam;
    final hero = heroOf(team);
    if (hero == null) return {};
    final out = <Hex>{};
    switch (type) {
      case CardType.summonKnight:
      case CardType.summonArcher:
      case CardType.summonGolem:
      case CardType.summonCavalry:
      case CardType.summonMage:
      case CardType.summonHealer:
        for (final e in tiles.entries) {
          if (e.value.walkable &&
              unitAt(e.key) == null &&
              e.key.distanceTo(hero.pos) <= 2) {
            out.add(e.key);
          }
        }
      case CardType.fireball:
        for (final h in tiles.keys) {
          if (h.distanceTo(hero.pos) <= 5) out.add(h);
        }
      case CardType.gust:
        for (final u in units) {
          if (u != hero && u.pos.distanceTo(hero.pos) <= 5) out.add(u.pos);
        }
      case CardType.lightning:
        for (final u in units) {
          if (u.team != team && u.pos.distanceTo(hero.pos) <= 5) out.add(u.pos);
        }
      case CardType.heal:
        for (final u in units) {
          if (u.team == team && u.hp < u.stats.maxHp) out.add(u.pos);
        }
      case CardType.dash:
        for (final u in units) {
          if (u.team == team) out.add(u.pos);
        }
      case CardType.shield:
        for (final u in units) {
          if (u.team == team && u.shield == 0) out.add(u.pos);
        }
      case CardType.grow:
        for (final e in tiles.entries) {
          if (e.value.terrain == Terrain.grass &&
              unitAt(e.key) == null &&
              e.key.distanceTo(hero.pos) <= 5) {
            out.add(e.key);
          }
        }
      case CardType.teleport:
        for (final e in tiles.entries) {
          if (e.value.walkable &&
              unitAt(e.key) == null &&
              e.key.distanceTo(hero.pos) <= 4) {
            out.add(e.key);
          }
        }
      case CardType.wall:
        for (final e in tiles.entries) {
          final t = e.value.terrain;
          if ((t == Terrain.grass || t == Terrain.forest) &&
              unitAt(e.key) == null &&
              e.key != centre &&
              e.key.distanceTo(hero.pos) <= 4) {
            out.add(e.key);
          }
        }
    }
    return out;
  }

  // ───────────────────────── player input ─────────────────────────

  void tapHex(Hex h) {
    if (!isPlayerTurn) return;
    if (!tiles.containsKey(h)) {
      _clearSelection();
      _refresh();
      return;
    }
    if (selectedCard != null) {
      if (cardTargets.contains(h)) {
        playCard(h);
        return;
      }
      selectedCard = null;
      cardTargets = {};
    }
    final u = unitAt(h);
    final sel = selected;
    if (u != null) {
      if (sel != null && attackTargets.contains(h)) {
        attack(sel, u);
        return;
      } else if (u.team == turn) {
        selected = sel == u ? null : u;
        if (selected != null) coachEvent(CoachEvent.unitSelected);
      } else {
        selected = null;
      }
    } else if (sel != null && moveTargets.containsKey(h)) {
      moveUnit(sel, h);
      return;
    } else {
      selected = null;
    }
    _refresh();
  }

  void selectCard(GameCard card) {
    if (!isPlayerTurn) return;
    if (selectedCard == card) {
      selectedCard = null;
      cardTargets = {};
      _refresh();
      return;
    }
    if (!canAfford(card)) {
      hint = 'Not enough energy for ${card.info.name}.';
      _notify();
      return;
    }
    final targets = targetsFor(card.type);
    if (targets.isEmpty) {
      hint = 'No valid targets for ${card.info.name}.';
      _notify();
      return;
    }
    selected = null;
    selectedCard = card;
    cardTargets = targets;
    coachEvent(CoachEvent.cardSelected, card: card.type);
    _refresh();
  }

  void _clearSelection() {
    selected = null;
    selectedCard = null;
    moveTargets = {};
    attackTargets = {};
    cardTargets = {};
  }

  void _refresh() {
    moveTargets = {};
    attackTargets = {};
    final u = selected;
    if (u != null && !units.contains(u)) selected = null;
    final s = selected;
    if (s != null) {
      if (s.canMove) moveTargets = reachable(s);
      if (s.canAct) {
        attackTargets = {
          for (final e in units)
            if (e != s &&
                inAttackRange(s, s.pos, e) &&
                (e.team != s.team || (s.stats.heals && e.hp < e.stats.maxHp)))
              e.pos,
        };
      }
    }
    if (winner != null) {
      hint = hotseat
          ? '${teamName(winner!)} wins!'
          : winner == Team.player
          ? 'Victory!'
          : 'Defeat…';
    } else if (turn == Team.enemy && !hotseat) {
      hint = 'The enemy is plotting…';
    } else if (selectedCard != null) {
      hint =
          'Pick a target for ${selectedCard!.info.name}. Tap elsewhere to cancel.';
    } else if (s != null) {
      final parts = <String>[];
      if (s.canMove) parts.add('green = move');
      if (s.canAct) {
        parts.add(
          attackTargets.isEmpty
              ? (s.stats.heals
                    ? 'nobody to attack or heal'
                    : 'no foes in range')
              : s.stats.heals
              ? 'red = attack / heal'
              : 'red = attack',
        );
      }
      hint = parts.isEmpty
          ? '${s.stats.name} is exhausted.'
          : '${s.stats.name}: ${parts.join(' • ')}';
    } else {
      hint = hotseat
          ? '${teamName(turn)}: tap a unit or play a card.'
          : 'Tap a unit to move or attack, or play a card.';
    }
    _notify();
  }

  void playCard(Hex target) {
    final card = selectedCard;
    if (card == null || !cardTargets.contains(target) || !canAfford(card)) {
      return;
    }
    energy -= card.info.cost;
    hand.remove(card);
    selectedCard = null;
    cardTargets = {};
    _applyCard(turn, card.type, target);
    coachEvent(CoachEvent.cardPlayed, card: card.type);
    _checkWinner();
    _refresh();
  }

  void endTurn() {
    if (!isPlayerTurn) return;
    coachEvent(CoachEvent.endedTurn);
    _clearSelection();
    _scoreHold(turn);
    if (winner != null) {
      _refresh();
      return;
    }
    if (!hotseat) {
      unawaited(_enemyTurn());
    } else if (turn == Team.player) {
      _beginTurn(Team.enemy);
    } else {
      _endRound();
    }
  }

  /// Hot-seat: the next player has the device and is ready.
  void confirmPass() {
    if (!passing) return;
    passing = false;
    announceTurn();
    _refresh();
  }

  /// Counts a turn of holding the centre hex for [team], if it does.
  void _scoreHold(Team team) {
    if (objective != Objective.hold || winner != null) return;
    final occ = unitAt(centre);
    if (occ != null && occ.team == team) {
      final n = holdTurns[team]! + 1;
      holdTurns[team] = n;
      _fx(
        FxEvent(
          FxKind.text,
          at: centre,
          text: '⭐ $n/${config.target}',
          color: const Color(0xFFFFE082),
        ),
      );
      if (n >= config.target) {
        _declare(
          team,
          team == Team.player && !hotseat
              ? 'You held the centre for $n turns.'
              : hotseat
              ? '${teamName(team)} held the centre for $n turns.'
              : 'The enemy held the centre for $n turns.',
        );
      }
    } else {
      holdTurns[team] = 0;
    }
  }

  // ───────────────────────── actions ─────────────────────────

  void moveUnit(Unit u, Hex dest) {
    final s = _search(u);
    if (!s.cost.containsKey(dest)) return;
    final path = <Hex>[];
    var cur = dest;
    while (cur != u.pos) {
      path.add(cur);
      cur = s.parent[cur]!;
    }
    u.path = path.reversed.toList();
    u.pos = dest;
    u.canMove = false;
    u.bonusMove = 0;
    _onEnter(u, delay: path.length * 0.14);
    if (u.team == Team.player) coachEvent(CoachEvent.moved);
    _checkWinner();
    _refresh();
  }

  void attack(Unit a, Unit d) {
    if (!a.canAct || !inAttackRange(a, a.pos, d)) return;
    final s = a.stats;
    if (a.team == Team.player) coachEvent(CoachEvent.attacked);
    if (d.team == a.team) {
      if (!s.heals || d.hp >= d.stats.maxHp) return;
      a.canAct = false;
      final before = d.hp;
      d.hp = math.min(d.stats.maxHp, d.hp + 2);
      _fx(
        FxEvent(
          FxKind.projectile,
          at: a.pos,
          to: d.pos,
          color: _goodColor,
          amount: 0.12,
        ),
      );
      _fx(FxEvent(FxKind.heal, at: d.pos, color: _goodColor, delay: 0.28));
      _fx(
        FxEvent(
          FxKind.text,
          at: d.pos,
          text: '+${d.hp - before}',
          color: _goodColor,
          delay: 0.28,
        ),
      );
      _refresh();
      return;
    }
    a.canAct = false;
    var delay = 0.12;
    if (s.maxRange > 1) {
      delay = 0.28;
      _fx(
        FxEvent(
          FxKind.projectile,
          at: a.pos,
          to: d.pos,
          color: s.splash ? const Color(0xFFD1A3FF) : const Color(0xFFFFE082),
          amount: 0.12,
        ),
      );
    } else {
      a.lunge = 1;
      a.lungeTo = d.pos;
    }
    final from = a.pos;
    final died = _damage(d, s.damage, delay: delay);
    _fx(
      FxEvent(
        FxKind.explosion,
        at: d.pos,
        color: const Color(0xFFFFF1B0),
        delay: delay,
        amount: 0.6,
      ),
    );
    if (s.splash) {
      for (final n in d.pos.neighbors) {
        final o = unitAt(n);
        if (o == null || o.team == a.team || o == d) continue;
        _fx(
          FxEvent(
            FxKind.explosion,
            at: n,
            color: const Color(0xFFD1A3FF),
            delay: delay,
            amount: 0.7,
          ),
        );
        _damage(o, 1, delay: delay, ignoreCover: true);
      }
    }
    if (!died && s.pushes) {
      _push(d, from.directionToward(d.pos), 1);
    }
    _checkWinner();
    _refresh();
  }

  /// Returns true if the unit died.
  bool _damage(
    Unit u,
    int amount, {
    double delay = 0,
    bool ignoreCover = false,
    bool fire = false,
  }) {
    if (fire && u.stats.fireImmune) {
      _fx(
        FxEvent(
          FxKind.text,
          at: u.pos,
          text: 'Immune',
          color: _fireColor,
          delay: delay,
        ),
      );
      return false;
    }
    if (u.shield > 0) {
      u.shield = 0;
      _fx(
        FxEvent(
          FxKind.text,
          at: u.pos,
          text: 'Blocked!',
          color: const Color(0xFF80D8FF),
          delay: delay,
        ),
      );
      _fx(
        FxEvent(
          FxKind.splash,
          at: u.pos,
          color: const Color(0xFF80D8FF),
          delay: delay,
          amount: 0.5,
        ),
      );
      return false;
    }
    var a = amount;
    final tile = tiles[u.pos];
    if (!ignoreCover &&
        tile != null &&
        tile.terrain == Terrain.forest &&
        a > 1) {
      a -= 1;
      _fx(
        FxEvent(
          FxKind.text,
          at: u.pos,
          text: 'Cover',
          color: _goodColor,
          delay: delay,
        ),
      );
    }
    u.hp -= a;
    u.flash = 1;
    _fx(
      FxEvent(
        FxKind.text,
        at: u.pos,
        text: '-$a',
        color: _dmgColor,
        delay: delay + 0.05,
      ),
    );
    _fx(FxEvent(FxKind.shake, amount: 0.35 + 0.1 * a, delay: delay));
    if (u.hp <= 0) {
      _removeUnit(u, delay: delay);
      return true;
    }
    return false;
  }

  void _removeUnit(
    Unit u, {
    double delay = 0,
    bool spin = false,
    String? text,
  }) {
    units.remove(u);
    final c = u.team == Team.player
        ? const Color(0xFF6EA8FF)
        : const Color(0xFFFF7B7B);
    _fx(FxEvent(FxKind.ghost, unit: u, spin: spin, delay: delay));
    _fx(
      FxEvent(
        FxKind.explosion,
        at: u.pos,
        color: c,
        delay: delay,
        amount: u.isHero ? 2 : 1.2,
      ),
    );
    if (text != null) {
      _fx(
        FxEvent(
          FxKind.text,
          at: u.pos,
          text: text,
          color: _infoColor,
          delay: delay + 0.1,
        ),
      );
    }
    if (u.isHero) _fx(FxEvent(FxKind.shake, amount: 1.2, delay: delay));
  }

  void _push(Unit u, int dir, int dist) {
    for (var i = 0; i < dist; i++) {
      final next = u.pos.neighbor(dir);
      final tile = tiles[next];
      if (tile == null) {
        u.pos = next;
        _removeUnit(u, spin: true, text: 'Knocked off!');
        return;
      }
      if (tile.terrain == Terrain.water) {
        u.pos = next;
        _fx(
          FxEvent(
            FxKind.splash,
            at: next,
            color: const Color(0xFF8AD8FF),
            amount: 1.4,
            delay: 0.1,
          ),
        );
        _removeUnit(u, spin: true, delay: 0.1, text: 'Drowned!');
        return;
      }
      if (tile.terrain == Terrain.lava) {
        u.pos = next;
        _fx(
          FxEvent(
            FxKind.explosion,
            at: next,
            color: _fireColor,
            amount: 1.6,
            delay: 0.1,
          ),
        );
        _removeUnit(u, spin: true, delay: 0.1, text: 'Incinerated!');
        return;
      }
      if (tile.terrain == Terrain.mountain) {
        _fx(
          FxEvent(
            FxKind.text,
            at: u.pos,
            text: 'Thud!',
            color: const Color(0xFFFFD54F),
            delay: 0.1,
          ),
        );
        _fx(const FxEvent(FxKind.shake, amount: 0.6, delay: 0.1));
        _damage(u, 1, delay: 0.1, ignoreCover: true);
        return;
      }
      final other = unitAt(next);
      if (other != null) {
        _fx(
          FxEvent(
            FxKind.text,
            at: next,
            text: 'Crash!',
            color: const Color(0xFFFFD54F),
            delay: 0.1,
          ),
        );
        _fx(const FxEvent(FxKind.shake, amount: 0.8, delay: 0.1));
        _damage(u, 1, delay: 0.1, ignoreCover: true);
        if (units.contains(other)) {
          _damage(other, 1, delay: 0.1, ignoreCover: true);
        }
        return;
      }
      u.pos = next;
      u.path = [];
    }
    _onEnter(u, delay: 0.15);
  }

  void _onEnter(Unit u, {double delay = 0}) {
    final tile = tiles[u.pos];
    if (tile == null) return;
    if (tile.terrain == Terrain.crystal) {
      tile.terrain = Terrain.grass;
      energies[u.team] = energies[u.team]! + 1;
      _fx(
        FxEvent(
          FxKind.text,
          at: u.pos,
          text: '+1 ⚡',
          color: const Color(0xFFD1A3FF),
          delay: delay,
        ),
      );
      _fx(
        FxEvent(
          FxKind.heal,
          at: u.pos,
          color: const Color(0xFFD1A3FF),
          delay: delay,
        ),
      );
    }
    if (tile.fire > 0) {
      _fx(
        FxEvent(
          FxKind.text,
          at: u.pos,
          text: 'Burn!',
          color: _fireColor,
          delay: delay,
        ),
      );
      _damage(u, 1, delay: delay + 0.05, ignoreCover: true, fire: true);
    }
  }

  void _spawn(Team team, UnitType type, Hex at) {
    final u = _addUnit(team, type, at);
    u.canAct = false;
    final c = team == Team.player
        ? const Color(0xFF6EA8FF)
        : const Color(0xFFFF7B7B);
    _fx(FxEvent(FxKind.spawn, at: at, color: c));
    _onEnter(u);
  }

  void _applyCard(Team team, CardType type, Hex target) {
    final hero = heroOf(team);
    switch (type) {
      case CardType.summonKnight:
      case CardType.summonArcher:
      case CardType.summonGolem:
      case CardType.summonCavalry:
      case CardType.summonMage:
      case CardType.summonHealer:
        _spawn(team, summonOf[type]!, target);
      case CardType.fireball:
        if (hero != null) {
          _fx(
            FxEvent(
              FxKind.projectile,
              at: hero.pos,
              to: target,
              color: _fireColor,
              amount: 0.3,
            ),
          );
        }
        final hexes = [target, ...target.neighbors.where(tiles.containsKey)];
        for (final h in hexes) {
          _fx(
            FxEvent(
              FxKind.explosion,
              at: h,
              color: _fireColor,
              delay: 0.4,
              amount: h == target ? 1.4 : 0.9,
            ),
          );
          final tile = tiles[h]!;
          if (tile.terrain != Terrain.water &&
              tile.terrain != Terrain.lava &&
              tile.terrain != Terrain.mountain) {
            tile.fire = 2;
          }
          final u = unitAt(h);
          if (u != null) _damage(u, 2, delay: 0.4, fire: true);
        }
        _fx(const FxEvent(FxKind.shake, amount: 0.8, delay: 0.4));
      case CardType.gust:
        final u = unitAt(target);
        if (u != null && hero != null) {
          _fx(
            FxEvent(
              FxKind.splash,
              at: u.pos,
              color: const Color(0xFFE0F7FA),
              amount: 0.8,
            ),
          );
          _fx(
            FxEvent(
              FxKind.text,
              at: u.pos,
              text: 'Whoosh!',
              color: const Color(0xFFB2EBF2),
            ),
          );
          _push(u, hero.pos.directionToward(u.pos), 2);
        }
      case CardType.lightning:
        final u = unitAt(target);
        if (u != null) {
          const c = Color(0xFFFFF176);
          if (hero != null) {
            _fx(
              FxEvent(
                FxKind.projectile,
                at: hero.pos,
                to: target,
                color: c,
                amount: 0.2,
              ),
            );
          }
          _fx(
            FxEvent(
              FxKind.explosion,
              at: target,
              color: c,
              delay: 0.25,
              amount: 1.3,
            ),
          );
          _damage(u, 3, delay: 0.25, ignoreCover: true);
        }
      case CardType.heal:
        final u = unitAt(target);
        if (u != null) {
          final before = u.hp;
          u.hp = math.min(u.stats.maxHp, u.hp + 3);
          _fx(FxEvent(FxKind.heal, at: u.pos, color: _goodColor));
          _fx(
            FxEvent(
              FxKind.text,
              at: u.pos,
              text: '+${u.hp - before}',
              color: _goodColor,
            ),
          );
        }
      case CardType.dash:
        final u = unitAt(target);
        if (u != null) {
          u.canMove = true;
          u.bonusMove += 2;
          _fx(
            FxEvent(
              FxKind.text,
              at: u.pos,
              text: 'Dash!',
              color: const Color(0xFFFFE082),
            ),
          );
          _fx(
            FxEvent(
              FxKind.splash,
              at: u.pos,
              color: const Color(0xFFFFE082),
              amount: 0.7,
            ),
          );
        }
      case CardType.shield:
        final u = unitAt(target);
        if (u != null) {
          u.shield = 1;
          _fx(FxEvent(FxKind.spawn, at: u.pos, color: const Color(0xFF80D8FF)));
        }
      case CardType.grow:
        tiles[target]?.terrain = Terrain.forest;
        _fx(FxEvent(FxKind.heal, at: target, color: _goodColor));
        _fx(FxEvent(FxKind.text, at: target, text: 'Grow!', color: _goodColor));
      case CardType.teleport:
        if (hero != null) {
          const c = Color(0xFFD1A3FF);
          _fx(FxEvent(FxKind.spawn, at: hero.pos, color: c));
          hero.pos = target;
          hero.path = [];
          _fx(FxEvent(FxKind.spawn, at: target, color: c));
          _fx(FxEvent(FxKind.text, at: target, text: 'Blink!', color: c));
          _onEnter(hero, delay: 0.1);
        }
      case CardType.wall:
        final tile = tiles[target];
        if (tile != null) {
          tile.terrain = Terrain.mountain;
          tile.fire = 0;
          _fx(
            FxEvent(
              FxKind.explosion,
              at: target,
              color: const Color(0xFFB0B3BA),
              amount: 1.2,
            ),
          );
          _fx(
            FxEvent(
              FxKind.text,
              at: target,
              text: 'Rock wall!',
              color: const Color(0xFFE0E0E0),
            ),
          );
          _fx(const FxEvent(FxKind.shake, amount: 0.5));
        }
    }
  }

  void _checkWinner() {
    if (winner != null) return;
    final p = heroOf(Team.player);
    final e = heroOf(Team.enemy);
    if (p == null) {
      _declare(
        Team.enemy,
        hotseat ? 'The blue hero has fallen.' : 'Your hero has fallen.',
      );
    } else if (e == null) {
      _declare(
        Team.player,
        hotseat ? 'The red hero has fallen.' : 'The enemy hero has fallen.',
      );
    }
  }

  void _declare(Team who, String reason) {
    if (winner != null) return;
    winner = who;
    winReason = reason;
    busy = true;
    _clearSelection();
    _fx(
      FxEvent(
        FxKind.banner,
        text: hotseat
            ? '${teamName(who)} wins!'
            : who == Team.player
            ? 'Victory!'
            : 'Defeat',
        delay: 0.6,
      ),
    );
  }

  void _resetUnits(Team team) {
    for (final u in units) {
      if (u.team == team) {
        u.canMove = true;
        u.canAct = true;
        u.bonusMove = 0;
      }
    }
  }

  /// Boss ability: Titans call a Knight at the start of their turn.
  void _bossAbilities(Team team) {
    for (final u in List.of(units.where((u) => u.team == team))) {
      if (!u.stats.summons) continue;
      final minions = units.where((x) => x.team == team && !x.isHero).length;
      if (minions >= 5) continue;
      final spot = _freeNear(u.pos);
      if (spot == u.pos) continue;
      _spawn(team, UnitType.knight, spot);
      _fx(
        FxEvent(
          FxKind.text,
          at: u.pos,
          text: 'Rally!',
          color: _dmgColor,
          delay: 0.1,
        ),
      );
    }
  }

  // ───────────────────────── turn flow ─────────────────────────

  void announceTurn() {
    final r = objective == Objective.survive
        ? 'Round $round/${config.target}'
        : 'Round $round';
    _fx(
      FxEvent(
        FxKind.banner,
        text: hotseat
            ? '$r — ${teamName(turn)}'
            : turn == Team.player
            ? '$r — Your turn'
            : 'Enemy turn',
      ),
    );
  }

  /// Starts a human turn for [team].
  void _beginTurn(Team team) {
    turn = team;
    busy = false;
    _resetUnits(team);
    _bossAbilities(team);
    energies[team] = energyFor(round);
    final h = hands[team]!;
    for (var i = 0; i < 2 && h.length < handLimit; i++) {
      h.add(GameCard(_nextId++, _randomCardType()));
    }
    passing = hotseat;
    if (!passing) announceTurn();
    if (team == Team.player) coachEvent(CoachEvent.turnStarted);
    _refresh();
  }

  bool _burns(Unit u) => !u.stats.fireImmune;

  void _endRound() {
    // Fire hurts whoever stands in it.
    for (final u in List.of(units)) {
      final t = tiles[u.pos];
      if (t != null && t.fire > 0 && _burns(u)) {
        _fx(FxEvent(FxKind.text, at: u.pos, text: 'Burn!', color: _fireColor));
        _damage(u, 1, ignoreCover: true, fire: true);
      }
    }
    // Spread to neighbouring forests, then burn down.
    final ignite = <Hex>[];
    for (final e in tiles.entries) {
      if (e.value.fire > 0 && e.value.terrain == Terrain.forest) {
        for (final n in e.key.neighbors) {
          final nt = tiles[n];
          if (nt != null &&
              nt.terrain == Terrain.forest &&
              nt.fire == 0 &&
              _rng.nextDouble() < 0.5) {
            ignite.add(n);
          }
        }
      }
    }
    for (final e in tiles.entries) {
      final t = e.value;
      if (t.fire > 0) {
        t.fire--;
        if (t.fire == 0 && t.terrain == Terrain.forest) {
          t.terrain = Terrain.grass;
          _fx(
            FxEvent(
              FxKind.text,
              at: e.key,
              text: 'Ash',
              color: const Color(0xFFBDBDBD),
            ),
          );
        }
      }
    }
    for (final h in ignite) {
      tiles[h]!.fire = 2;
      _fx(FxEvent(FxKind.flame, at: h, color: _fireColor));
      _fx(
        FxEvent(
          FxKind.text,
          at: h,
          text: 'Spreading!',
          color: _fireColor,
          delay: 0.05,
        ),
      );
      final u = unitAt(h);
      if (u != null) _damage(u, 1, delay: 0.1, ignoreCover: true, fire: true);
    }
    _checkWinner();
    if (winner == null &&
        objective == Objective.survive &&
        round >= config.target) {
      _declare(Team.player, 'You survived ${config.target} rounds.');
    }
    final limit = config.roundLimit;
    if (winner == null && limit != null && round >= limit) {
      _declare(Team.enemy, 'Out of time: you had $limit rounds.');
    }
    if (winner != null) {
      _refresh();
      return;
    }
    round++;
    _beginTurn(Team.player);
  }

  // ───────────────────────── enemy AI ─────────────────────────

  bool _valid(int gen) => !_disposed && gen == _gen && winner == null;

  Future<bool> _pause(int ms, int gen) async {
    final scaled = (ms * aiDelayScale).round();
    if (scaled > 0) await Future<void>.delayed(Duration(milliseconds: scaled));
    return _valid(gen);
  }

  Difficulty get _diff => config.difficulty;

  int _enemyIncome() => math.max(
    1,
    energyFor(round) + config.enemyBonusEnergy + _diff.energyBonus,
  );

  Unit? _holder;

  Future<void> _enemyTurn() async {
    final gen = _gen;
    turn = Team.enemy;
    busy = true;
    _resetUnits(Team.enemy);
    _bossAbilities(Team.enemy);
    energies[Team.enemy] = enemyEnergy + _enemyIncome();
    announceTurn();
    _refresh();
    if (!await _pause(1100, gen)) return;

    final eh = heroOf(Team.enemy);
    if (eh == null) return;

    if (config.enemyAi == EnemyAi.passive) {
      _scoreHold(Team.enemy);
      _endRound();
      return;
    }
    final full = config.enemyAi == EnemyAi.full;

    // 1. Fireball when it is worth it.
    if (full && enemyEnergy >= 2) {
      Hex? best;
      var bestScore = _diff == Difficulty.easy ? 6 : 3;
      for (final h in tiles.keys) {
        if (h.distanceTo(eh.pos) > 5) continue;
        var score = 0;
        for (final x in [h, ...h.neighbors]) {
          final u = unitAt(x);
          if (u == null || u.stats.fireImmune) continue;
          if (u.team == Team.player) {
            score += (u.isHero ? 6 : 3) + (u.hp <= 2 ? 3 : 0);
          } else {
            score -= u.isHero ? 20 : 4;
          }
        }
        if (score > bestScore) {
          bestScore = score;
          best = h;
        }
      }
      if (best != null) {
        enemyEnergy -= 2;
        _applyCard(Team.enemy, CardType.fireball, best);
        _checkWinner();
        _refresh();
        if (!await _pause(1000, gen)) return;
      }
    }

    // 2. Tactical cards (push kills, lightning, shield, heal).
    if (full && _diff.tactics) {
      for (var plays = 0; plays < 2; plays++) {
        final play = _bestTactic();
        if (play == null) break;
        enemyEnergy -= cardInfo[play.card]!.cost;
        _applyCard(Team.enemy, play.card, play.target);
        _checkWinner();
        _refresh();
        if (!await _pause(900, gen)) return;
      }
    }

    // 3. Summon reinforcements.
    var guard = 0;
    while (full && enemyEnergy >= 1 && guard++ < (_diff.smart ? 4 : 3)) {
      final count = units
          .where((u) => u.team == Team.enemy && !u.isHero)
          .length;
      if (count >= _diff.summonCap) break;
      final type = _pickSummon();
      final spot = _bestSummonSpot();
      if (type == null || spot == null) break;
      enemyEnergy -= summonCost(type);
      _spawn(Team.enemy, type, spot);
      _refresh();
      if (!await _pause(550, gen)) return;
    }

    // 4. Move and attack with every unit.
    _holder = null;
    if (objective == Objective.hold) {
      final cands =
          units.where((u) => u.team == Team.enemy && !u.isHero).toList()..sort(
            (a, b) =>
                a.pos.distanceTo(centre).compareTo(b.pos.distanceTo(centre)),
          );
      if (cands.isNotEmpty) _holder = cands.first;
    }
    for (final u in List.of(units.where((u) => u.team == Team.enemy))) {
      if (!units.contains(u)) continue;
      if (!await _aiAct(u, gen)) return;
    }

    if (!_valid(gen)) return;
    if (!await _pause(500, gen)) return;
    _scoreHold(Team.enemy);
    _endRound();
  }

  /// Chooses what to summon, or null if nothing affordable.
  UnitType? _pickSummon() {
    final e = enemyEnergy;
    final wounded = units.any(
      (u) => u.team == Team.enemy && u.hp <= u.stats.maxHp - 2,
    );
    final weights = <UnitType, double>{
      UnitType.archer: 3,
      UnitType.knight: 3,
      UnitType.golem: _diff == Difficulty.easy ? 1 : 2,
      if (_diff != Difficulty.easy) UnitType.cavalry: 2,
      if (_diff.smart) UnitType.mage: 3,
      if (_diff.smart) UnitType.healer: wounded ? 3 : 0.5,
    };
    weights.removeWhere((t, _) => summonCost(t) > e);
    final total = weights.values.fold<double>(0, (a, b) => a + b);
    if (total == 0) return null;
    var roll = _rng.nextDouble() * total;
    for (final en in weights.entries) {
      if (roll < en.value) return en.key;
      roll -= en.value;
    }
    return weights.keys.first;
  }

  /// Would pushing a unit at [pos] along [dir] for [dist] hexes kill it?
  bool _pushLethal(Hex pos, int dir, int dist) {
    var cur = pos;
    for (var i = 0; i < dist; i++) {
      final next = cur.neighbor(dir);
      final tile = tiles[next];
      if (tile == null ||
          tile.terrain == Terrain.water ||
          tile.terrain == Terrain.lava) {
        return true;
      }
      if (!tile.walkable || unitAt(next) != null) return false;
      cur = next;
    }
    return false;
  }

  /// Damage foes of [team] could plausibly deal to a unit standing on [h].
  int _threatAt(Hex h, Team team) {
    var total = 0;
    for (final f in units) {
      if (f.team == team) continue;
      if (f.pos.distanceTo(h) <= f.stats.move + f.stats.maxRange) {
        total += f.stats.damage;
      }
    }
    return total;
  }

  ({CardType card, Hex target})? _bestTactic() {
    final eh = heroOf(Team.enemy);
    if (eh == null) return null;
    final e = enemyEnergy;
    final foes = units.where((u) => u.team == Team.player).toList();

    // Shove a unit into water, lava or off the board.
    if (e >= 1) {
      Unit? pick;
      for (final f in foes) {
        if (f.pos.distanceTo(eh.pos) > 5) continue;
        if (!_pushLethal(f.pos, eh.pos.directionToward(f.pos), 2)) continue;
        if (pick == null ||
            (f.isHero && !pick.isHero) ||
            f.stats.maxHp > pick.stats.maxHp && !pick.isHero) {
          pick = f;
        }
      }
      if (pick != null) return (card: CardType.gust, target: pick.pos);
    }
    // Finish a wounded foe with lightning.
    if (e >= 2 && _diff.smart) {
      Unit? pick;
      for (final f in foes) {
        if (f.pos.distanceTo(eh.pos) > 5 || f.shield > 0 || f.hp > 3) continue;
        if (pick == null || f.isHero) pick = f;
      }
      if (pick != null) return (card: CardType.lightning, target: pick.pos);
    }
    if (_diff.smart && e >= 1) {
      if (eh.shield == 0 && _threatAt(eh.pos, Team.enemy) >= eh.hp) {
        return (card: CardType.shield, target: eh.pos);
      }
      Unit? hurt;
      for (final u in units) {
        if (u.team != Team.enemy || u.hp > u.stats.maxHp - 3) continue;
        if (hurt == null || u.hp / u.stats.maxHp < hurt.hp / hurt.stats.maxHp) {
          hurt = u;
        }
      }
      if (hurt != null) return (card: CardType.heal, target: hurt.pos);
    }
    return null;
  }

  Hex? _bestSummonSpot() {
    final hero = heroOf(Team.enemy);
    final foe = heroOf(Team.player);
    if (hero == null) return null;
    final spots = [
      for (final e in tiles.entries)
        if (e.value.walkable &&
            unitAt(e.key) == null &&
            e.key.distanceTo(hero.pos) <= 2)
          e.key,
    ];
    if (spots.isEmpty) return null;
    final target = objective == Objective.hold ? centre : (foe?.pos ?? centre);
    spots.sort((a, b) => a.distanceTo(target).compareTo(b.distanceTo(target)));
    return spots[_rng.nextInt(math.min(2, spots.length))];
  }

  /// Returns false if the game state was invalidated (restart / game over).
  Future<bool> _aiAct(Unit u, int gen) async {
    final foes = units.where((x) => x.team == Team.player).toList();
    if (foes.isEmpty) return _valid(gen);
    if (_diff.blunder > 0 && _rng.nextDouble() < _diff.blunder) {
      return _valid(gen);
    }
    final reach = u.canMove ? reachable(u) : <Hex, int>{};
    final spots = [u.pos, ...reach.keys];
    final smart = _diff.smart;
    final healTargets = u.stats.heals
        ? units
              .where(
                (x) => x.team == u.team && x != u && x.hp <= x.stats.maxHp - 2,
              )
              .toList()
        : <Unit>[];

    Hex? bestHex;
    Unit? bestTarget;
    var bestScore = -1e9;
    if (u.canAct) {
      for (final h in spots) {
        for (final t in [...foes, ...healTargets]) {
          if (!inAttackRange(u, h, t)) continue;
          var score = 10.0;
          if (t.team == u.team) {
            score = 6.0 + (t.stats.maxHp - t.hp) + (t.isHero ? 3 : 0);
          } else {
            if (t.hp <= u.stats.damage && t.shield == 0) score += 20;
            if (t.isHero) score += 8;
            if (objective == Objective.hold && t.pos == centre) score += 12;
            if (u.stats.pushes) {
              final n = t.pos.neighbor(h.directionToward(t.pos));
              final nt = tiles[n];
              if (nt == null ||
                  nt.terrain == Terrain.water ||
                  nt.terrain == Terrain.lava) {
                score += t.isHero ? 40 : 25;
              }
            }
            if (u.stats.splash) {
              for (final n in t.pos.neighbors) {
                final o = unitAt(n);
                if (o != null && o.team != u.team && o != t) score += 3;
              }
            }
          }
          final ht = tiles[h]!;
          if (ht.fire > 0 && _burns(u)) score -= 4;
          if (ht.terrain == Terrain.forest) score += 1.5;
          if (ht.terrain == Terrain.crystal) score += 2;
          if (u.stats.maxRange > 1) score += 0.4 * h.distanceTo(t.pos);
          if (smart) {
            final threat = _threatAt(h, Team.enemy);
            score -= threat * (u.isHero ? 0.6 : 0.25);
            if (u.isHero && threat >= u.hp) score -= 30;
          }
          score += _rng.nextDouble();
          if (score > bestScore) {
            bestScore = score;
            bestHex = h;
            bestTarget = t;
          }
        }
      }
    }

    if (bestTarget != null && bestHex != null) {
      if (bestHex != u.pos) {
        moveUnit(u, bestHex);
        if (!await _pause(650, gen)) return false;
      }
      if (!units.contains(u) || !units.contains(bestTarget)) return true;
      attack(u, bestTarget);
      return await _pause(750, gen);
    }

    if (u.canMove && reach.isNotEmpty) {
      // Where is this unit trying to go?
      Hex goal;
      if (_holder == u) {
        goal = centre;
      } else if (u.stats.heals) {
        final friends = units.where((x) => x.team == u.team && x != u).toList();
        friends.sort(
          (a, b) => a.pos.distanceTo(u.pos).compareTo(b.pos.distanceTo(u.pos)),
        );
        goal = friends.isNotEmpty ? friends.first.pos : foes.first.pos;
      } else {
        var near = foes.first;
        for (final f in foes) {
          final d = f.pos.distanceTo(u.pos) - (f.isHero ? 1 : 0);
          if (d < near.pos.distanceTo(u.pos) - (near.isHero ? 1 : 0)) near = f;
        }
        goal = near.pos;
      }
      final flee = smart && u.isHero && u.hp * 2 <= u.stats.maxHp;
      double minFoe(Hex h) =>
          foes.map((f) => f.pos.distanceTo(h)).reduce(math.min).toDouble();

      double rate(Hex h) {
        final t = tiles[h]!;
        if (flee) return -minFoe(h) + _threatAt(h, Team.enemy) * 0.5;
        var s = h.distanceTo(goal).toDouble();
        if (t.fire > 0 && _burns(u)) s += 2;
        if (t.terrain == Terrain.crystal) s -= 1.2;
        if (t.terrain == Terrain.forest) s -= 0.3;
        if ((u.stats.maxRange > 1 || u.stats.heals) && minFoe(h) < 2) s += 3;
        if (smart) s += _threatAt(h, Team.enemy) * (u.isHero ? 0.35 : 0.12);
        return s;
      }

      Hex? pick;
      var pickScore = rate(u.pos);
      reach.forEach((h, c) {
        final s = rate(h);
        if (s < pickScore) {
          pickScore = s;
          pick = h;
        }
      });
      if (pick != null) {
        moveUnit(u, pick!);
        return await _pause(650, gen);
      }
    }
    return _valid(gen);
  }

  // ───────────────────────── plumbing ─────────────────────────

  void _fx(FxEvent e) => fx?.call(e);

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
