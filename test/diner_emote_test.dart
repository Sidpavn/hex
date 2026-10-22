// Guests show how they feel: a heart for the food, a coin for a tip.
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/goals.dart';
import 'package:hex/diner/service.dart';

Diner open() {
  final d = Diner.starter();
  d.progress
    ..level = 3
    ..reputation = 70;
  d.goalsDone.addAll([for (final g in goals) g.id]);
  return d;
}

void main() {
  test('guests have a heart when the food comes, and a coin when they tip', () {
    final seen = <String>{};
    for (final seed in [1, 2, 3]) {
      final sim = DinerSim(open(), seed: seed);
      while (!sim.finished && sim.ticks < 2500) {
        sim.tick();
        for (final g in sim.guests) {
          final e = g.emote;
          if (e != null) seen.add(e);
        }
        for (final a in sim.actors(1)) {
          if (a.badge != null && a.badge!.startsWith('emote_')) {
            seen.add(a.badge!);
          }
        }
      }
    }
    expect(seen, contains('emote_heart'));
    expect(seen, contains('emote_coin'));
  });

  test('an emote goes away by itself', () {
    final sim = DinerSim(open(), seed: 2);
    var most = 0;
    var run = 0;
    while (!sim.finished && sim.ticks < 2500) {
      sim.tick();
      final any = sim.guests.any((g) => g.emote != null);
      run = any ? run + 1 : 0;
      if (run > most) most = run;
    }
    // Never stuck on for long: a few ticks each, and different guests overlap.
    expect(most, lessThan(200));
    expect(
      sim.guests.where((g) => !g.gone && g.emote != null),
      hasLength(lessThan(3)),
    );
  });
}
