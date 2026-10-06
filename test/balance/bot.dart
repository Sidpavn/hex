import 'dart:math' as math;

import 'package:hex/game/config.dart';
import 'package:hex/game/game_controller.dart';
import 'package:hex/game/hex.dart';
import 'package:hex/game/models.dart';

/// A stand-in for a human playing Blue, used to measure level difficulty.
/// It plays a sensible-but-not-perfect game: summons, fireballs, focuses the
/// enemy hero, takes the centre, and keeps its own hero out of reach
/// ([heroCaution]). Randomness comes from [rng] so repeated runs differ.
class Bot {
  Bot(
    this.rng, {
    this.heroCaution = 3.0,
    this.mistakes = 0.0,
    this.spam = false,
  });

  /// Plays damage spells (Fireball, Gust, Lightning) before anything else and
  /// with a low bar, to see how strong spell-spam is.
  final bool spam;

  /// Cards played this game, by type (for reporting).
  final Map<CardType, int> cast = {};

  final math.Random rng;

  /// How strongly the hero avoids hexes enemies can reach (0 = reckless).
  final double heroCaution;

  /// Chance a unit simply skips its turn (a distracted player).
  final double mistakes;

  Future<void> playTurn(GameController g) async {
    _cards(g);
    final mine = g.units.where((u) => u.team == Team.player).toList()
      ..sort((a, b) => (a.isHero ? 1 : 0).compareTo(b.isHero ? 1 : 0));
    for (final u in mine) {
      if (g.winner != null) return;
      if (!g.units.contains(u)) continue;
      if (rng.nextDouble() < mistakes) continue;
      _unit(g, u);
    }
    if (g.winner != null) return;
    g.endTurn();
    for (var k = 0; k < 200 && !g.isPlayerTurn && g.winner == null; k++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  // ───────────────────────── cards ─────────────────────────

  static const _summonScore = {
    CardType.summonKnight: 5.0,
    CardType.summonArcher: 6.0,
    CardType.summonGolem: 4.0,
    CardType.summonCavalry: 5.0,
    CardType.summonMage: 5.5,
    CardType.summonHealer: 2.0,
  };

  void _cards(GameController g) {
    final skipped = <GameCard>{};
    for (var guard = 0; guard < 8 && g.winner == null; guard++) {
      GameCard? best;
      var bestScore = 0.0;
      for (final c in g.hand) {
        if (skipped.contains(c) || !g.canCast(c)) continue;
        final s = _cardScore(g, c);
        if (s > bestScore) {
          bestScore = s;
          best = c;
        }
      }
      if (best == null) return;
      g.selectCard(best);
      if (g.selectedCard != best) {
        skipped.add(best);
        continue;
      }
      final t = _cardTarget(g, best);
      if (t == null) {
        g.selectCard(best);
        skipped.add(best);
        continue;
      }
      final type = best.type;
      g.tapHex(t);
      if (g.hand.every((c) => c != best)) cast[type] = (cast[type] ?? 0) + 1;
    }
  }

  int _armySize(GameController g) =>
      g.units.where((u) => u.team == Team.player && !u.isHero).length;

  double _cardScore(GameController g, GameCard c) {
    final hero = g.heroOf(Team.player);
    switch (c.type) {
      case CardType.fireball:
        final t = _fireballTarget(g);
        if (t == null) return 0;
        return spam ? 9 + t.$2 / 10 : t.$2.toDouble();
      case CardType.gust:
        if (_gustTarget(g) != null) return spam ? 10 : 7;
        return spam && _enemyInRange(g) ? 6 : 0;
      case CardType.heal:
        return hero != null && hero.hp <= hero.stats.maxHp - 3 ? 7 : 0;
      case CardType.shield:
        return hero != null && hero.shield == 0 && _threat(g, hero.pos) >= 2
            ? 6
            : 0;
      case CardType.lightning:
        if (spam) return _enemyInRange(g) ? 8 : 0;
        return g.units.any((u) => u.team == Team.enemy && u.hp <= 2) ? 6 : 0;
      case CardType.summonKnight:
      case CardType.summonArcher:
      case CardType.summonGolem:
      case CardType.summonCavalry:
      case CardType.summonMage:
      case CardType.summonHealer:
        if (_armySize(g) >= 4) return 0;
        return _summonScore[c.type]! - c.info.cost * 0.4;
      default:
        return 0;
    }
  }

  bool _enemyInRange(GameController g) =>
      g.targetsFor(CardType.gust).any((h) => g.unitAt(h)?.team == Team.enemy);

  /// An enemy a Gust would throw into water, lava or off the board.
  Hex? _gustTarget(GameController g) {
    final hero = g.heroOf(Team.player);
    if (hero == null) return null;
    for (final h in g.targetsFor(CardType.gust)) {
      final u = g.unitAt(h);
      if (u == null || u.team != Team.enemy) continue;
      final dir = hero.pos.directionToward(u.pos);
      var p = u.pos;
      for (var i = 0; i < 2; i++) {
        p = p.neighbor(dir);
        final tile = g.tiles[p];
        if (tile == null ||
            tile.terrain == Terrain.water ||
            tile.terrain == Terrain.lava) {
          return h;
        }
        if (tile.terrain == Terrain.mountain || g.unitAt(p) != null) break;
      }
    }
    return null;
  }

  (Hex, int)? _fireballTarget(GameController g) {
    Hex? best;
    var bestScore = spam ? 1 : 3;
    for (final h in g.targetsFor(CardType.fireball)) {
      var score = 0;
      for (final x in [h, ...h.neighbors]) {
        final u = g.unitAt(x);
        if (u == null || u.stats.fireImmune) continue;
        if (u.team == Team.enemy) {
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
    return best == null ? null : (best, bestScore);
  }

  Hex? _cardTarget(GameController g, GameCard c) {
    final hero = g.heroOf(Team.player);
    final enemyHero = g.heroOf(Team.enemy);
    switch (c.type) {
      case CardType.fireball:
        return _fireballTarget(g)?.$1;
      case CardType.heal:
      case CardType.shield:
        return hero?.pos;
      case CardType.gust:
        final kill = _gustTarget(g);
        if (kill != null) return kill;
        for (final h in g.cardTargets) {
          if (g.unitAt(h)?.team == Team.enemy) return h;
        }
        return null;
      case CardType.lightning:
        Hex? best;
        var bestHp = 99;
        for (final h in g.cardTargets) {
          final u = g.unitAt(h);
          if (u != null && u.hp < bestHp) {
            bestHp = u.hp;
            best = h;
          }
        }
        return best;
      default:
        if (enemyHero == null || g.cardTargets.isEmpty) return null;
        final targets = g.cardTargets.toList()
          ..sort(
            (a, b) => a
                .distanceTo(enemyHero.pos)
                .compareTo(b.distanceTo(enemyHero.pos)),
          );
        return targets.first;
    }
  }

  // ───────────────────────── units ─────────────────────────

  /// How many enemy units could plausibly hit [at] next turn.
  int _threat(GameController g, Hex at) {
    var n = 0;
    for (final e in g.units) {
      if (e.team != Team.enemy) continue;
      final reach = e.stats.move + e.stats.maxRange;
      if (e.pos.distanceTo(at) <= reach) n++;
    }
    return n;
  }

  void _unit(GameController g, Unit u) {
    if (!u.canMove && !u.canAct) return;
    g.tapHex(u.pos);
    if (g.selected != u) return;
    final enemies = g.units.where((e) => e.team == Team.enemy).toList();
    if (enemies.isEmpty) return;
    final enemyHero = g.heroOf(Team.enemy);
    final caution = u.isHero ? heroCaution : 0.4;

    final cands = <Hex>[if (u.canMove) ...g.moveTargets.keys, u.pos];
    Hex? bestHex;
    var bestScore = -1e9;
    for (final h in cands) {
      var s = rng.nextDouble() * 0.5;
      if (u.canAct) {
        var hit = 0.0;
        for (final e in enemies) {
          if (!g.inAttackRange(u, h, e)) continue;
          final dmg = math.min(u.stats.damage, e.hp);
          final v = dmg * 3.0 + (e.isHero ? 14 : 0) + (dmg >= e.hp ? 8 : 0);
          if (v > hit) hit = v;
        }
        s += hit;
      }
      if (enemyHero != null) s -= h.distanceTo(enemyHero.pos) * 0.6;
      if (g.objective == Objective.hold && h == GameController.centre) s += 12;
      if (g.objective == Objective.survive || u.isHero) {
        s -= _threat(g, h) * caution;
      } else {
        s -= _threat(g, h) * caution * 0.5;
      }
      if (g.tiles[h]?.terrain == Terrain.forest) s += 0.8;
      if (s > bestScore) {
        bestScore = s;
        bestHex = h;
      }
    }
    if (bestHex != null && bestHex != u.pos && u.canMove) {
      g.tapHex(bestHex);
      if (g.selected != u) g.tapHex(u.pos);
    }
    if (g.selected == u && u.canAct) {
      Hex? tgt;
      var best = -1.0;
      for (final h in g.attackTargets) {
        final e = g.unitAt(h);
        if (e == null) continue;
        double v;
        if (e.team == u.team) {
          v = 5.0 + (e.stats.maxHp - e.hp);
        } else {
          final dmg = math.min(u.stats.damage, e.hp);
          v = dmg * 3.0 + (e.isHero ? 14 : 0) + (dmg >= e.hp ? 8 : 0);
        }
        if (v > best) {
          best = v;
          tgt = h;
        }
      }
      if (tgt != null) g.tapHex(tgt);
    }
    g.tapHex(const Hex(99, 99)); // deselect
  }
}
