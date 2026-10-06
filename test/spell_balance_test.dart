// Dev tool: compares spell-spam against a builder (summon-first) player in
// skirmish, so card-economy changes can be judged by numbers.
//   BALANCE=1 flutter test test/spell_balance_test.dart
//   BALANCE=1 BALANCE_RUNS=100 flutter test test/spell_balance_test.dart
//
// Columns: win% for Blue (the bot), average rounds, share of games over by
// round 3, share ended by a hazard knock-out (Gust into water/lava/off-board),
// and average Fireball / Gust casts per game by the bot.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hex/game/config.dart';
import 'package:hex/game/game_controller.dart';
import 'package:hex/game/models.dart';

import 'balance/bot.dart';

void main() {
  final on = Platform.environment['BALANCE'] != null;
  final runs = int.tryParse(Platform.environment['BALANCE_RUNS'] ?? '') ?? 40;

  test(
    'spell spam vs builder',
    () async {
      final out = StringBuffer()
        ..writeln(
          'difficulty  deck   style     win%  rounds  <=r3%  hazard%  '
          'fireballs  gusts',
        );
      for (final d in [Difficulty.normal, Difficulty.hard]) {
        for (final (deckName, deck) in [
          ('base', baseCards),
          ('full', CardType.values.toSet()),
        ]) {
          for (final (style, spam) in [('builder', false), ('spam', true)]) {
            var wins = 0, rounds = 0, quick = 0, hazard = 0;
            final cast = <CardType, int>{};
            for (var r = 0; r < runs; r++) {
              final bot = Bot(math.Random(500 + r), spam: spam);
              final g = GameController(
                seed: 7000 + r,
                aiDelayScale: 0,
                config: GameConfig(difficulty: d, deck: deck),
              );
              final recent = <String>[];
              g.fx = (e) {
                if (e.kind == FxKind.text) recent.add(e.text);
              };
              for (var i = 0; i < 40 && g.winner == null; i++) {
                recent.clear();
                await bot.playTurn(g);
              }
              if (g.winner == Team.player) wins++;
              if (g.round <= 3) quick++;
              const hazards = ['Knocked off!', 'Drowned!', 'Incinerated!'];
              if (recent.any(hazards.contains)) hazard++;
              rounds += g.round;
              bot.cast.forEach((k, v) => cast[k] = (cast[k] ?? 0) + v);
            }
            String avg(CardType c) =>
                ((cast[c] ?? 0) / runs).toStringAsFixed(1).padLeft(5);
            String pct(int n) => (100 * n / runs).round().toString().padLeft(3);
            out.writeln(
              '${d.name.padRight(10)}  ${deckName.padRight(5)}  '
              '${style.padRight(8)}  ${pct(wins)}%  '
              '${(rounds / runs).toStringAsFixed(1).padLeft(6)}  '
              '${pct(quick).padLeft(4)}%  ${pct(hazard).padLeft(6)}%  '
              '${avg(CardType.fireball)}      ${avg(CardType.gust)}',
            );
          }
        }
      }
      stdout.write(out);
    },
    skip: !on,
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
