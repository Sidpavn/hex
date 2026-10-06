// Dev tool: measures campaign difficulty by letting a bot play every level.
//   BALANCE=1 flutter test test/balance_test.dart            (all levels)
//   BALANCE=1 BALANCE_RUNS=40 BALANCE_LEVEL=9 flutter test ...  (one level)
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hex/game/campaign.dart';
import 'package:hex/game/config.dart';
import 'package:hex/game/game_controller.dart';
import 'package:hex/game/models.dart';

import 'balance/bot.dart';

class _Stat {
  int wins = 0, games = 0, rounds = 0, stars = 0, winRounds = 0;
}

Future<(bool, int)> _play(LevelDef lv, Bot bot, {Set<CardType>? deck}) async {
  final g = GameController(
    aiDelayScale: 0,
    config: lv.config.copyWith(deck: deck ?? baseCards),
  );
  for (var i = 0; i < 40 && g.winner == null; i++) {
    await bot.playTurn(g);
  }
  return (g.winner == Team.player, g.round);
}

void main() {
  final on = Platform.environment['BALANCE'] != null;
  final runs = int.tryParse(Platform.environment['BALANCE_RUNS'] ?? '') ?? 20;
  final only = int.tryParse(Platform.environment['BALANCE_LEVEL'] ?? '');

  test(
    'campaign balance report',
    () async {
      final out = StringBuffer();
      out.writeln(
        'lvl  name                      par  careful       bold          '
        'distracted    (win%, avg rounds when won)',
      );
      final styles = <(String, Bot Function(int))>[
        ('careful', (s) => Bot(math.Random(s), heroCaution: 3)),
        ('bold', (s) => Bot(math.Random(s), heroCaution: 0.5)),
        (
          'distracted',
          (s) => Bot(math.Random(s), heroCaution: 2, mistakes: 0.25),
        ),
      ];
      for (var i = 0; i < campaignLevels.length; i++) {
        if (only != null && i != only) continue;
        final lv = campaignLevels[i];
        // Lessons teach with a fixed card set; campaign levels use their deck or
        // every card the player could plausibly own by then.
        final deck = lv.config.deck;
        final cells = <String>[];
        for (final (_, make) in styles) {
          final s = _Stat();
          for (var r = 0; r < runs; r++) {
            final (won, rounds) = await _play(lv, make(1000 + r), deck: deck);
            s.games++;
            if (won) {
              s.wins++;
              s.winRounds += rounds;
            }
          }
          final avg = s.wins == 0 ? 0 : s.winRounds / s.wins;
          cells.add(
            '${(100 * s.wins / s.games).round().toString().padLeft(3)}% '
            'r${avg.toStringAsFixed(1).padLeft(4)}',
          );
        }
        out.writeln(
          '${(i + 1).toString().padLeft(2)}   '
          '${lv.name.padRight(25)} ${lv.par.toString().padLeft(3)}  '
          '${cells.join('   ')}',
        );
      }
      stdout.write(out);
    },
    skip: !on,
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
