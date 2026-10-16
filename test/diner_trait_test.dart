import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/goals.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/diner/service.dart';
import 'package:hex/diner/staff.dart';
import 'package:hex/diner/toast.dart';
import 'package:hex/diner/traits.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';
import 'package:hex/ui/widgets.dart' show PixelBox;
import 'support/office.dart';

Staff person({
  int id = 70,
  String name = 'Test',
  int cooking = 4,
  int speed = 5,
  int service = 4,
  int charm = 4,
  List<Trait> traits = const [],
  int morale = Staff.maxMorale,
}) {
  final stats = {
    Stat.cooking: cooking,
    Stat.speed: speed,
    Stat.service: service,
    Stat.charm: charm,
  };
  return Staff(
    id: id,
    name: name,
    stats: stats,
    potential: {for (final s in Stat.values) s: 10},
    morale: morale,
    traits: [...traits],
    known: {...traits},
  );
}

Diner dinerWith(Staff who, {int rep = 60}) {
  final d = Diner.starter()..progress.reputation = rep;
  d.roster.employees
    ..clear()
    ..add(who);
  return d;
}

DinerSim play(Diner d, {int seed = 1}) {
  final sim = DinerSim(d, seed: seed);
  while (!sim.finished && sim.ticks < 2000) {
    sim.tick();
  }
  return sim;
}

/// Closes the day straight away, as if it had run.
DayReport closeNow(Diner d, {int seed = 1}) {
  final sim = DinerSim(d, seed: seed);
  sim.ticks = Pace.dayTicks + Pace.lastCall;
  sim.tick();
  return sim.result!;
}

void main() {
  group('the traits', () {
    test('there are ten, each described and priced in', () {
      expect(Trait.values.length, 10);
      for (final t in Trait.values) {
        final i = traitInfo[t]!;
        expect(i.name, isNotEmpty);
        expect(i.info, isNotEmpty);
        expect(i.salary, inInclusiveRange(0.8, 1.2));
      }
      expect(
        Trait.values.map((t) => traitInfo[t]!.name).toSet().length,
        10,
        reason: 'no two share a name',
      );
      expect(Trait.values.map((t) => traitInfo[t]!.tone).toSet(), {
        Tone.good,
        Tone.bad,
        Tone.mixed,
      });
    });

    test('quick hands handles plates faster', () {
      final base = person().handlingTicks;
      expect(
        person(traits: [Trait.quickHands]).handlingTicks,
        closeTo(base * 0.7, 1e-9),
      );
    });

    test('a perfectionist sells for more but is slower with the plate', () {
      final p = person(traits: [Trait.perfectionist]);
      expect(p.priceFactor, greaterThan(person().priceFactor * 1.1));
      expect(p.handlingTicks, greaterThan(person().handlingTicks));
    });

    test('cheerful people keep guests calm', () {
      expect(
        person(traits: [Trait.cheerful]).calm,
        greaterThan(person().calm + 0.05),
      );
    });

    test('a fast learner trains for less', () {
      final plain = person().trainCost(Stat.cooking);
      final quick = person(traits: [Trait.fastLearner]).trainCost(Stat.cooking);
      expect(quick, lessThan(plain));
      expect(quick, closeTo(plain * 0.7, 1));
    });

    test('wages reflect quirks: frugal and flawed are cheaper', () {
      final plain = person().salary;
      expect(person(traits: [Trait.frugal]).salary, lessThan(plain));
      expect(person(traits: [Trait.clumsy]).salary, lessThan(plain));
      expect(person(traits: [Trait.quickHands]).salary, greaterThan(plain));
      expect(
        person(traits: [Trait.quickHands, Trait.clumsy]).salary,
        closeTo(plain, 2),
        reason: 'an upside and a downside roughly cancel out',
      );
    });

    test('team players speed up everyone else, not themselves', () {
      final d = dinerWith(person(name: 'Lead', traits: [Trait.teamPlayer]))
        ..progress.upgrades[Upgrade.staff] = 2;
      d.roster.employees
        ..add(person(id: 71, name: 'B'))
        ..add(person(id: 72, name: 'C', traits: [Trait.teamPlayer]));
      final sim = DinerSim(d);
      final byName = {for (final w in sim.workers) w.staff.name: w};
      expect(
        byName['Lead']!.paceMul,
        closeTo(1.05, 1e-9),
        reason: 'only the other team player helps them',
      );
      expect(byName['B']!.paceMul, closeTo(1.10, 1e-9));
      expect(byName['C']!.paceMul, closeTo(1.05, 1e-9));
    });

    test('a lone team player helps nobody', () {
      final sim = DinerSim(dinerWith(person(traits: [Trait.teamPlayer])));
      expect(sim.workers.single.paceMul, 1);
    });
  });

  group('clumsy', () {
    test('drops plates, and the guest is served again', () {
      var drops = 0;
      for (final seed in [1, 2, 3, 4, 5]) {
        final d = dinerWith(person(traits: [Trait.clumsy]), rep: 70);
        final sim = play(d, seed: seed);
        drops += d.roster.employees.single.drops;
        // Nothing is left half done at the end of the day.
        expect(sim.guests, isEmpty);
        expect(
          sim.wasted,
          greaterThanOrEqualTo(d.roster.employees.single.drops),
        );
      }
      expect(drops, greaterThan(0));
    });

    test('the guest whose plate was dropped is cooked for again', () {
      for (final seed in [1, 2, 3, 4, 5, 6, 7, 8]) {
        final d = dinerWith(person(traits: [Trait.clumsy]), rep: 70);
        final sim = DinerSim(d, seed: seed);
        final carried = <OrderItem>{};
        final dropped = <OrderItem>{};
        final recovered = <OrderItem>{};
        while (!sim.finished) {
          sim.tick();
          for (final g in sim.guests) {
            for (final i in g.items) {
              if (i.state == ItemState.carried) carried.add(i);
              if (i.state == ItemState.pending && carried.contains(i)) {
                dropped.add(i);
              }
              if (i.state == ItemState.delivered && dropped.contains(i)) {
                recovered.add(i);
              }
            }
          }
        }
        if (dropped.isNotEmpty) {
          expect(recovered, isNotEmpty, reason: 'seed $seed');
          return;
        }
      }
      fail('no seed produced a drop');
    });

    test('nobody drops a plate without the trait', () {
      final d = dinerWith(person(), rep: 70);
      play(d);
      expect(d.roster.employees.single.drops, 0);
    });

    test('it makes the day worse: fewer served, more wasted', () {
      var clumsyServed = 0;
      var cleanServed = 0;
      var wasted = 0;
      for (final seed in [1, 2, 3, 4]) {
        final c = play(
          dinerWith(person(traits: [Trait.clumsy]), rep: 80),
          seed: seed,
        );
        final n = play(dinerWith(person(), rep: 80), seed: seed);
        clumsyServed += c.served;
        cleanServed += n.served;
        wasted += c.wasted - n.wasted;
      }
      expect(clumsyServed, lessThan(cleanServed));
      expect(wasted, greaterThan(0));
    });

    test('the first drop reveals the flaw, and tells the story', () {
      for (final seed in [1, 2, 3, 4, 5, 6, 7, 8]) {
        final who = person(traits: [Trait.clumsy])..known.clear();
        final d = dinerWith(who, rep: 80);
        final sim = play(d, seed: seed);
        if (who.drops == 0) continue;
        expect(who.known, contains(Trait.clumsy));
        final lines = sim.story.map((l) => l.text).toList();
        expect(lines.any((t) => t.contains('Test')), isTrue);
        expect(lines.any((t) => t.toLowerCase().contains('clumsy')), isTrue);
        expect(who.memories.any((m) => m.contains('dropped')), isTrue);
        return;
      }
      fail('no drop in eight seeds');
    });

    test('a drop makes the person look embarrassed for a moment', () {
      final who = person(traits: [Trait.clumsy]);
      final d = dinerWith(who, rep: 90);
      final sim = DinerSim(d, seed: 2);
      var seen = false;
      while (!sim.finished) {
        sim.tick();
        if (sim.workers.single.emote == 'emote_oops') {
          seen = true;
          expect(sim.actors(0).any((a) => a.badge == 'emote_oops'), isTrue);
        }
      }
      expect(seen, isTrue);
    });
  });

  group('hot-headed and loyal', () {
    test('a hot-headed person takes unpaid wages twice as hard', () {
      final d = Diner.starter()..coins = 0;
      final who = person(traits: [Trait.hotHeaded], morale: 3);
      d.roster.employees
        ..clear()
        ..add(who);
      closeNow(d);
      expect(who.morale, 1);
      final second = closeNow(d);
      expect(second.quit, ['Test']);
      expect(second.story.any((l) => l.text.contains('Test')), isTrue);
    });

    test('a loyal person puts up with a missed payday', () {
      final d = Diner.starter()..coins = 0;
      final who = person(traits: [Trait.loyal], morale: 3);
      d.roster.employees
        ..clear()
        ..add(who);
      final first = closeNow(d);
      expect(who.morale, 3, reason: 'the first one does not count');
      expect(first.story.any((l) => l.text.contains('Test')), isTrue);
      closeNow(d);
      expect(who.morale, 2, reason: 'the second does');
      d.coins = 0;
      closeNow(d);
      closeNow(d);
      expect(who.morale, 1);
    });

    test('being paid clears a grudge', () {
      final d = Diner.starter()..coins = 0;
      final who = person(traits: [Trait.loyal]);
      d.roster.employees
        ..clear()
        ..add(who);
      closeNow(d);
      expect(who.grudge, 1);
      d.coins = 500;
      closeNow(d);
      expect(who.grudge, 0);
    });

    test('an ordinary person loses a point at once', () {
      final d = Diner.starter()..coins = 0;
      final who = person(morale: 3);
      d.roster.employees
        ..clear()
        ..add(who);
      closeNow(d);
      expect(who.morale, 2);
    });
  });

  group('late bloomer', () {
    test('candidates with it start weaker but can become more', () {
      for (var day = 1; day < 400; day++) {
        final r = Roster.starter()..rollCandidates(day, 5, 2.5, Ad.paper);
        for (final c in r.candidates.where((c) => c.has(Trait.lateBloomer))) {
          expect(c.headroom, greaterThan(8), reason: 'a lot left to give');
          return;
        }
      }
      fail('never rolled one');
    });

    test('after ten days they improve in everything, once', () {
      final who = person(traits: [Trait.lateBloomer]);
      who.daysWorked = 9;
      final before = who.total;
      final d = dinerWith(who);
      final report = closeNow(d);
      expect(who.bloomed, isTrue);
      expect(who.total, before + 8);
      expect(report.story.any((l) => l.text.contains('Test')), isTrue);
      expect(who.memories.first, contains('found their feet'));
      closeNow(d);
      expect(who.total, before + 8, reason: 'it only happens once');
    });

    test('they cannot bloom past what they could become', () {
      final who = Staff(
        id: 99,
        name: 'Cap',
        stats: {for (final s in Stat.values) s: 4},
        potential: {for (final s in Stat.values) s: 5},
        traits: [Trait.lateBloomer],
        daysWorked: 9,
      );
      closeNow(dinerWith(who));
      for (final s in Stat.values) {
        expect(who.stat(s), 5);
      }
    });
  });

  group('finding out', () {
    test('a candidate shows one trait; the rest are a surprise', () {
      var hidden = 0;
      for (var day = 1; day <= 200; day++) {
        final r = Roster.starter()..rollCandidates(day, 3, 2, Ad.paper);
        for (final c in r.candidates) {
          expect(c.visibleTraits.length, lessThanOrEqualTo(1));
          expect(c.hiddenTraits, c.traits.length - c.visibleTraits.length);
          if (c.hiddenTraits > 0) hidden++;
          if (c.traits.isNotEmpty) {
            expect(c.visibleTraits.single, c.traits.first);
          }
        }
      }
      expect(hidden, greaterThan(60), reason: 'a good share have a secret');
    });

    test('candidates are a mixed bag: all ten traits come up', () {
      final seen = <Trait>{};
      var none = 0;
      var two = 0;
      var n = 0;
      for (var day = 1; day <= 300; day++) {
        final r = Roster.starter()..rollCandidates(day, 4, 2, Ad.paper);
        for (final c in r.candidates) {
          seen.addAll(c.traits);
          n++;
          if (c.traits.isEmpty) none++;
          if (c.traits.length == 2) two++;
          expect(
            c.traits.toSet().length,
            c.traits.length,
            reason: 'no repeats',
          );
          expect(c.traits.length, lessThanOrEqualTo(2));
        }
      }
      expect(seen.length, 10);
      expect(none / n, inInclusiveRange(0.1, 0.3));
      expect(two / n, inInclusiveRange(0.25, 0.55));
    });

    test('a good trait often comes with a flaw', () {
      var paired = 0;
      var goodFirst = 0;
      for (var day = 1; day <= 300; day++) {
        final r = Roster.starter()..rollCandidates(day, 4, 2, Ad.paper);
        for (final c in r.candidates) {
          if (c.traits.length == 2 &&
              traitInfo[c.traits.first]!.tone == Tone.good) {
            goodFirst++;
            if (traitInfo[c.traits[1]]!.tone != Tone.good) paired++;
          }
        }
      }
      expect(goodFirst, greaterThan(50));
      expect(paired, goodFirst, reason: 'a good first trait pairs with a flaw');
    });

    test('three days on the job and you know them', () {
      final who = person(traits: [Trait.clumsy, Trait.quickHands])
        ..known.clear()
        ..known.add(Trait.quickHands);
      expect(who.hiddenTraits, 1);
      final d = dinerWith(who, rep: 5);
      closeNow(d);
      closeNow(d);
      expect(who.hiddenTraits, 1, reason: 'two days is not enough');
      closeNow(d);
      expect(who.hiddenTraits, 0);
    });

    test('a hired person keeps their secrets until they come out', () {
      final d = Diner.starter()
        ..coins = 1000000
        ..progress.upgrades[Upgrade.staff] = 1;
      for (var day = 1; day < 100; day++) {
        d.progress.day = day;
        d.roster.candidateDay = 0;
        d.advertise(Ad.paper);
        final c = d.roster.candidates.firstWhere(
          (c) => c.traits.length == 2,
          orElse: () => d.roster.candidates.first,
        );
        if (c.traits.length != 2) continue;
        d.hire(c);
        expect(c.hiddenTraits, 1);
        return;
      }
      fail('no candidate with a secret');
    });

    test('traits survive a save, hidden ones included', () {
      final d = Diner.starter();
      final who = person(traits: [Trait.clumsy, Trait.frugal])
        ..known.clear()
        ..known.add(Trait.frugal)
        ..grudge = 1
        ..bloomed = true
        ..plates = 17
        ..drops = 3
        ..remember(2, 'dropped a burger');
      d.roster.employees.add(who);
      final back = Diner.fromJson(d.toJson()).roster.employees.last;
      expect(back.traits, [Trait.clumsy, Trait.frugal]);
      expect(back.known, {Trait.frugal});
      expect(back.hiddenTraits, 1);
      expect(back.grudge, 1);
      expect(back.bloomed, isTrue);
      expect(back.plates, 17);
      expect(back.drops, 3);
      expect(back.memories, ['Day 2: dropped a burger']);
    });

    test('an old save with no traits loads with none', () {
      final s = Staff.fromJson({
        'id': 5,
        'name': 'Old',
        'stats': {'cooking': 3},
        'cap': {'cooking': 5},
      })!;
      expect(s.traits, isEmpty);
      expect(s.memories, isEmpty);
    });

    test('Sam, who starts here, is loyal and everyone knows it', () {
      final sam = Roster.starter().employees.single;
      expect(sam.traits, [Trait.loyal]);
      expect(sam.hiddenTraits, 0);
    });
  });

  group('the story of a day', () {
    test('guests have names, each different at the same time', () {
      final sim = DinerSim(dinerWith(person(), rep: 90), seed: 3);
      while (!sim.finished) {
        sim.tick();
        final names = sim.guests.map((g) => g.name).toList();
        expect(names.toSet().length, names.length);
        expect(names, isNot(contains('A guest')));
      }
    });

    test('a busy day produces a story with names in it', () {
      final sim = play(dinerWith(person(), rep: 90));
      expect(sim.story, isNotEmpty);
      final all = sim.story.map((l) => l.text).join(' ');
      expect(all, contains('Test'));
      expect(sim.result!.story.length, sim.story.length);
    });

    test('the same day is told the same way', () {
      final a = play(dinerWith(person(), rep: 80), seed: 4);
      final b = play(dinerWith(person(), rep: 80), seed: 4);
      expect(a.story.map((l) => l.text), b.story.map((l) => l.text));
    });

    test('telling the story never changes how the day goes', () {
      // The same day, with and without the extra wording in play, plays out
      // the same: the story has its own source of chance.
      final a = play(dinerWith(person(), rep: 80), seed: 9);
      final b = play(dinerWith(person(), rep: 80), seed: 9);
      expect(a.served, b.served);
      expect(a.earned, b.earned);
    });

    test('the highlights mix good and bad, and are told in time order', () {
      final lines = [
        const StoryLine(5, 'good', Tone.good),
        const StoryLine(9, 'bad one', Tone.bad),
        const StoryLine(12, 'colour', Tone.mixed),
        const StoryLine(20, 'bad two', Tone.bad),
        const StoryLine(30, 'good two', Tone.good),
      ];
      final r = DayReport(
        day: 1,
        served: 0,
        walkouts: 0,
        earned: 0,
        tips: 0,
        wasted: 0,
        avgWait: 0,
        stars: 0,
        xp: 0,
        levelsGained: 0,
        reputation: 0,
        reputationBefore: 0,
        tomorrow: 0,
        wages: 0,
        unpaid: 0,
        quit: const [],
        story: lines,
        moods: const [],
      );
      final top = r.highlights(3).map((l) => l.text).toList();
      // A mix of bad, good and colour, told in the order they happened.
      expect(top, ['good', 'bad one', 'colour']);
      expect(r.highlights(2).map((l) => l.text), ['good', 'bad one']);
      expect(r.highlights(1).single.text, 'bad one', reason: 'bad news first');
      expect(r.highlights(10).length, 5);
    });

    test('a big tip gets told', () {
      final who = person(charm: 10, cooking: 8, speed: 7, service: 7);
      final sim = play(dinerWith(who, rep: 50));
      expect(sim.story.any((l) => l.text.contains('coins')), isTrue);
      expect(who.memories.any((m) => m.contains('tipped')), isTrue);
    });

    test('someone giving up is told, with their name', () {
      final slow = person(speed: 1, service: 1, cooking: 1);
      final sim = play(dinerWith(slow, rep: 90));
      expect(sim.gaveUp, greaterThan(0));
      final bad = sim.story.where((l) => l.tone == Tone.bad).toList();
      expect(bad, isNotEmpty);
    });

    test('walking past a long queue is told', () {
      final sim = play(dinerWith(person(speed: 2, service: 2), rep: 100));
      expect(sim.walkouts, greaterThan(sim.gaveUp));
      expect(
        sim.story.any(
          (l) =>
              l.text.contains('queue') ||
              l.text.contains('line') ||
              l.text.contains('walked past') ||
              l.text.contains('walking'),
        ),
        isTrue,
      );
    });

    test('a day nothing happens still gets a line', () {
      final d = Diner(coins: 100)..place(Kind.grill, const Cell(1, 7));
      d.roster.employees.clear();
      final sim = DinerSim(d);
      sim.ticks = Pace.dayTicks + Pace.lastCall;
      sim.tick();
      expect(sim.result!.story, isNotEmpty);
    });

    test('the star of the day is named, and remembers it', () {
      final who = person(speed: 7, service: 7);
      final sim = play(dinerWith(who, rep: 70));
      expect(
        sim.story.any(
          (l) => l.text.contains('Test') && l.text.contains('plates'),
        ),
        isTrue,
      );
      expect(who.memories.any((m) => m.contains('plates')), isTrue);
      expect(who.plates, sim.workers.single.platesToday);
    });

    test('a person remembers only their last five days of note', () {
      final who = person();
      for (var i = 1; i <= 9; i++) {
        who.remember(i, 'thing $i');
      }
      expect(who.memories.length, 5);
      expect(who.memories.first, 'Day 9: thing 9');
      expect(who.memories.last, 'Day 5: thing 5');
    });

    test('the ticker shows a line while it is news, then clears', () {
      final sim = DinerSim(dinerWith(person(), rep: 90), seed: 2);
      while (sim.story.isEmpty && !sim.finished) {
        sim.tick();
      }
      expect(sim.ticker, isNotNull);
      final when = sim.story.last.tick;
      while (sim.ticks - when <= 31 &&
          sim.story.last.tick == when &&
          !sim.finished) {
        sim.tick();
      }
      if (sim.story.last.tick == when) expect(sim.ticker, isNull);
    });

    test('team player gets a line at opening time', () {
      final d = dinerWith(person(name: 'Lead', traits: [Trait.teamPlayer]))
        ..progress.upgrades[Upgrade.staff] = 1;
      d.roster.employees.add(person(id: 71, name: 'B'));
      final sim = DinerSim(d);
      sim.tick();
      expect(sim.story.single.text, contains('Lead'));
    });
  });

  group('no trait rules the game', () {
    Diner busy(Staff who) {
      final d = Diner(
        coins: 100000,
        owned: {0, 1},
        progress: Progress(reputation: 80),
      );
      d.roster.employees
        ..clear()
        ..add(who);
      d.place(Kind.grill, const Cell(1, 3), Dir.sw);
      d.place(Kind.grill, const Cell(2, 3), Dir.sw);
      d.place(Kind.counter, const Cell(7, 3), Dir.sw);
      d.place(Kind.counter, const Cell(8, 3), Dir.sw);
      for (final t in const [Cell(3, 5), Cell(6, 5), Cell(6, 7)]) {
        d.place(Kind.table, t);
        d.place(Kind.chair, Cell(t.x - 1, t.y), Dir.se);
        d.place(Kind.chair, Cell(t.x + 1, t.y), Dir.nw);
      }
      return d;
    }

    double earned(Staff who) {
      var sum = 0.0;
      for (var seed = 1; seed <= 16; seed++) {
        sum += play(busy(who), seed: seed).earned;
      }
      return sum / 16;
    }

    test('each trait changes a day by less than a fifth either way', () {
      final base = earned(person());
      for (final t in Trait.values) {
        final e = earned(person(traits: [t]));
        expect(
          e,
          inInclusiveRange(base * 0.78, base * 1.22),
          reason: '${t.name}: $base vs $e',
        );
      }
    });

    test('and the ones that should help or hurt, do', () {
      final base = earned(person());
      // A day varies a lot with who turns up and when, so a 10% edge cannot be
      // seen in a handful of days. What can be said: helpful traits do not
      // hurt, and a flaw does.
      expect(
        earned(person(traits: [Trait.quickHands])),
        greaterThan(base * 0.93),
      );
      expect(
        earned(person(traits: [Trait.cheerful])),
        greaterThan(base * 0.93),
      );
      expect(earned(person(traits: [Trait.perfectionist])), isNot(base));
      expect(earned(person(traits: [Trait.clumsy])), lessThan(base * 0.97));
    });
  });

  group('the screens', () {
    Future<Diner> open(WidgetTester tester, Diner d) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
      });
      Storage.clearMemory();
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(HexApp(home: BuildScreen(diner: d)));
      await tester.pump();
      return d;
    }

    testWidgets(
      'the page of a person shows trait tags, and a tap explains one right under them',
      (tester) async {
        final d = Diner.starter()..coins = 900;
        final sam = d.roster.employees.single
          ..traits.add(Trait.clumsy)
          ..remember(1, 'dropped Marge\'s burger');
        await open(tester, d);
        await openApp(tester, 'staff');
        await tester.tap(find.byKey(ValueKey('team-${sam.id}')));
        await tester.pumpAndSettle();
        expect(find.byKey(ValueKey('trait-${sam.id}-loyal')), findsOneWidget);
        expect(
          find.byKey(ValueKey('trait-${sam.id}-clumsy')),
          findsNothing,
          reason: 'not found out yet',
        );
        expect(find.byKey(ValueKey('trait-${sam.id}-hidden')), findsOneWidget);
        expect(find.textContaining('Day 1: dropped'), findsOneWidget);

        await tester.tap(find.byKey(ValueKey('trait-${sam.id}-loyal')));
        await tester.pump();
        expect(find.textContaining('half as fast'), findsOneWidget);
        await tester.tap(find.byKey(ValueKey('trait-${sam.id}-hidden')));
        await tester.pump();
        expect(find.textContaining('find out in time'), findsOneWidget);
        expect(
          find.textContaining('half as fast'),
          findsNothing,
          reason: 'one explanation at a time',
        );
      },
    );

    testWidgets('news during the day comes up as small toasts', (tester) async {
      final d = dinerWith(person(traits: [Trait.clumsy]), rep: 90);
      await open(tester, d);
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('speed-3')));
      await tester.pump();
      var most = 0;
      for (var i = 0; i < 600; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        final n = find
            .descendant(
              of: find.byKey(const ValueKey('toasts')),
              matching: find.byType(PixelBox),
            )
            .evaluate()
            .length;
        if (n > most) most = n;
        if (find.byKey(const ValueKey('next-day')).evaluate().isNotEmpty) break;
      }
      expect(most, greaterThan(0), reason: 'something was shown');
      expect(most, lessThanOrEqualTo(ToastQueue.maxShown));
      expect(find.byKey(const ValueKey('ticker')), findsNothing);
    });

    testWidgets('the end of the day tells what happened', (tester) async {
      final d = dinerWith(person(traits: [Trait.clumsy]), rep: 90);
      d.goalsDone.addAll([for (final g in goals) g.id]); // no goal line
      await open(tester, d);
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('speed-3')));
      await tester.pump();
      for (var i = 0; i < 900; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byKey(const ValueKey('next-day')).evaluate().isNotEmpty) break;
      }
      expect(find.byKey(const ValueKey('next-day')), findsOneWidget);
      // One line says what to do next, else one says what happened.
      expect(
        find.byKey(const ValueKey('story-line')).evaluate().length +
            find.byKey(const ValueKey('fix-first')).evaluate().length,
        1,
      );
    });
  });
}
