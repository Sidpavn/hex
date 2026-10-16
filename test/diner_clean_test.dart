// Tables get messy when guests leave. Guests mind a dirty table; tapping it
// clears it, and a member of staff kept for tables does it for you.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/diner_painter.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/diner/service.dart';
import 'package:hex/diner/staff.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';

Staff person(int id, {Kind? duty}) => Staff(
  id: id,
  name: 'S$id',
  stats: {Stat.cooking: 4, Stat.speed: 5, Stat.service: 4, Stat.charm: 4},
  potential: {for (final s in Stat.values) s: 10},
  duty: duty,
);

Diner cafe({int cooks = 2, int cleaners = 0, int rep = 80}) {
  final d = Diner(
    coins: 100000,
    owned: {0, 1},
    progress: Progress(level: 4, reputation: rep),
  );
  d.roster.employees.clear();
  d.progress.upgrades[Upgrade.staff] = cooks + cleaners - 1;
  for (var i = 0; i < cooks; i++) {
    d.roster.employees.add(person(70 + i));
  }
  for (var i = 0; i < cleaners; i++) {
    d.roster.employees.add(person(90 + i, duty: Kind.table));
  }
  d.place(Kind.grill, const Cell(1, 3), Dir.sw);
  d.place(Kind.grill, const Cell(2, 3), Dir.sw);
  d.place(Kind.counter, const Cell(10, 7), Dir.nw);
  d.place(Kind.counter, const Cell(10, 6), Dir.nw);
  for (final t in const [Cell(3, 5), Cell(6, 5), Cell(7, 7), Cell(9, 5)]) {
    d.place(Kind.table, t);
    d.place(Kind.chair, Cell(t.x - 1, t.y), Dir.se);
    d.place(Kind.chair, Cell(t.x + 1, t.y), Dir.nw);
  }
  return d;
}

DinerSim play(Diner d, {int seed = 1}) {
  final sim = DinerSim(d, seed: seed);
  while (!sim.finished && sim.ticks < 2000) {
    sim.tick();
  }
  return sim;
}

void main() {
  group('messy tables', () {
    test('a table is clean until someone has eaten at it', () {
      final sim = DinerSim(cafe(), seed: 2);
      expect(sim.dirty, isEmpty);
      var sawEat = false;
      while (!sim.finished && sim.ticks < 2000) {
        sim.tick();
        if (sim.guests.any((g) => g.state == GuestState.eating)) {
          sawEat = true;
          expect(sim.dirty.length, lessThanOrEqualTo(sim.seats.length));
        }
      }
      expect(sawEat, isTrue);
    });

    test('it is messy once the guest has got up to pay', () {
      final sim = DinerSim(cafe(), seed: 2);
      var checked = 0;
      final eaten = <int, Cell>{};
      while (!sim.finished && sim.ticks < 2000) {
        sim.tick();
        for (final g in sim.guests) {
          if (g.state == GuestState.eating) eaten[g.id] = g.seat!.cell;
          if ((g.state == GuestState.toPay || g.state == GuestState.paying) &&
              eaten.containsKey(g.id)) {
            expect(sim.dirty.contains(eaten[g.id]), isTrue);
            checked++;
          }
        }
      }
      expect(checked, greaterThan(0));
    });

    test('a guest who left without eating leaves no mess', () {
      final d = cafe(cooks: 1, rep: 100);
      final sim = DinerSim(d, seed: 3);
      final seats = <int, Cell>{};
      final ate = <int>{};
      while (!sim.finished && sim.ticks < 2000) {
        sim.tick();
        for (final g in sim.guests) {
          if (g.seat != null) seats[g.id] = g.seat!.cell;
          if (g.state == GuestState.eating) ate.add(g.id);
        }
      }
      final gaveUp = seats.keys.where((id) => !ate.contains(id));
      expect(gaveUp, isNotEmpty, reason: 'someone left hungry');
      final fed = {for (final id in ate) seats[id]};
      for (final id in gaveUp) {
        // A seat only they used is not dirty.
        if (!fed.contains(seats[id])) {
          expect(sim.dirty.contains(seats[id]), isFalse);
        }
      }
    });

    test('tapping the table or the chair clears it', () {
      final sim = DinerSim(cafe(), seed: 2);
      final seat = sim.seats.first;
      sim.dirty.add(seat.cell);
      expect(sim.cleanAt(const Cell(0, 0)), 0);
      expect(sim.cleanAt(seat.table), 1);
      expect(sim.dirty, isEmpty);
      sim.dirty.add(seat.cell);
      expect(sim.cleanAt(seat.cell), 1);
      expect(sim.cleaned, 2);
    });

    test('a table with two chairs is cleared in one go', () {
      final sim = DinerSim(cafe(), seed: 2);
      final table = sim.seats.first.table;
      final both = sim.seats.where((s) => s.table == table).toList();
      expect(both.length, 2);
      sim.dirty.addAll(both.map((s) => s.cell));
      expect(sim.cleanAt(table), 2);
      expect(sim.dirty, isEmpty);
    });

    test('a clean seat is taken before a dirty one', () {
      final sim = DinerSim(cafe(rep: 40), seed: 1);
      // Everything but the farthest table is a mess.
      final far = sim.seats.where((s) => s.table == const Cell(9, 5));
      sim.dirty.addAll([
        for (final s in sim.seats)
          if (!far.contains(s)) s.cell,
      ]);
      while (!sim.finished && sim.ticks < 400) {
        sim.tick();
        final sitter = sim.guests
            .where((g) => g.seat != null && g.state == GuestState.toSeat)
            .firstOrNull;
        if (sitter != null) {
          expect(far.map((s) => s.cell), contains(sitter.seat!.cell));
          return;
        }
      }
      fail('nobody sat');
    });

    test('someone who must sit at a dirty table is put out', () {
      final sim = DinerSim(cafe(rep: 60), seed: 2);
      sim.dirty.addAll(sim.seats.map((s) => s.cell));
      var grumpy = 0;
      while (!sim.finished && sim.ticks < 2000) {
        sim.tick();
        for (final g in sim.guests.where((g) => g.grumpy)) {
          grumpy++;
          expect(g.state, isNot(GuestState.arriving));
        }
      }
      expect(grumpy, greaterThan(0));
      expect(
        sim.story.any((l) => l.text.contains('cleared')),
        isTrue,
        reason: 'the story mentions it',
      );
    });

    test('a dirty table costs patience and tips', () {
      double meanPatience(bool messy) {
        var sum = 0.0;
        var n = 0;
        for (final seed in [1, 2, 3, 4]) {
          final sim = DinerSim(cafe(rep: 60), seed: seed);
          if (messy) sim.dirty.addAll(sim.seats.map((s) => s.cell));
          while (!sim.finished && sim.ticks < 300) {
            sim.tick();
            for (final g in sim.guests.where(
              (g) => g.state == GuestState.waiting && g.waited == 1,
            )) {
              sum += g.patienceMax / g.temper.patienceMul;
              n++;
            }
          }
        }
        return n == 0 ? 0 : sum / n;
      }

      expect(
        meanPatience(true),
        lessThan(meanPatience(false) * 0.9),
        reason: 'they wait less',
      );
      expect(DinerSim.messTip, lessThan(1));
      expect(DinerSim.messPatience, lessThan(1));
    });

    test('a mess does not cost more than it should: guests still eat', () {
      final sim = DinerSim(cafe(), seed: 2);
      sim.dirty.addAll(sim.seats.map((s) => s.cell));
      while (!sim.finished && sim.ticks < 2000) {
        sim.tick();
      }
      expect(sim.served, greaterThan(3));
    });

    test('the day report counts what was cleared', () {
      final sim = DinerSim(cafe(cleaners: 1), seed: 2);
      while (!sim.finished && sim.ticks < 2000) {
        sim.tick();
      }
      expect(sim.result!.cleaned, sim.cleaned);
      expect(sim.cleaned, greaterThan(0));
    });
  });

  group('a member of staff for the tables', () {
    test('they clear the mess without being told', () {
      final sim = DinerSim(cafe(cleaners: 1), seed: 2);
      while (!sim.finished && sim.ticks < 2000) {
        sim.tick();
      }
      expect(sim.cleaned, greaterThan(3));
    });

    test('they walk to it, and the mess goes when they get there', () {
      final sim = DinerSim(cafe(cleaners: 1), seed: 2);
      final cleaner = sim.workers.last;
      var walked = false;
      while (!sim.finished && sim.ticks < 2000) {
        sim.tick();
        if (cleaner.state == WorkState.toClean) {
          walked = true;
          final seat = cleaner.cleaning!;
          expect(sim.dirty.contains(seat.cell), isTrue, reason: 'still there');
        }
      }
      expect(walked, isTrue);
    });

    test('they do not cook or carry plates', () {
      final d = cafe(cleaners: 1);
      final cleaner = d.roster.employees.last;
      final sim = DinerSim(d, seed: 2);
      while (!sim.finished && sim.ticks < 2000) {
        sim.tick();
        final w = sim.workers.last;
        expect(w.carrying, isEmpty);
      }
      expect(cleaner.made(Dish.burger), 0);
      expect(cleaner.plates, 0);
    });

    test('with one, fewer guests sit at a dirty table', () {
      int grumpy(int cleaners) {
        var n = 0;
        for (final seed in [1, 2, 3]) {
          final sim = DinerSim(cafe(cleaners: cleaners), seed: seed);
          final seen = <int>{};
          while (!sim.finished && sim.ticks < 2000) {
            sim.tick();
            for (final g in sim.guests.where((g) => g.grumpy)) {
              if (seen.add(g.id)) n++;
            }
          }
        }
        return n;
      }

      expect(grumpy(1), lessThan(grumpy(0)));
    });

    test('two of them do not both go for the same table', () {
      final d = cafe(cleaners: 2);
      final sim = DinerSim(d, seed: 2);
      while (!sim.finished && sim.ticks < 2000) {
        sim.tick();
        final going = [
          for (final w in sim.workers)
            if (w.cleaning != null) w.cleaning!.cell,
        ];
        expect(going.toSet().length, going.length);
      }
    });

    test('with no tables there is nothing to keep them for', () {
      final d = cafe(cleaners: 1);
      d.items.removeWhere((p) => p.kind == Kind.table);
      final sim = DinerSim(d, seed: 2);
      expect(sim.workers.length, 3);
      // Their duty is ignored, so they work like anyone else.
      final cleaner = sim.workers.last;
      sim.tick();
      expect(cleaner.cleaning, isNull);
    });

    test('they are saved as being on tables', () {
      final d = cafe(cleaners: 1);
      final back = Diner.fromJson(d.toJson());
      expect(back.roster.employees.last.duty, Kind.table);
    });
  });

  group('on screen', () {
    final board = find.byKey(const ValueKey('diner-board'));

    Future<void> open(WidgetTester tester) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
      });
      Storage.clearMemory();
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(HexApp(home: BuildScreen(diner: cafe())));
      await tester.pump();
    }

    DinerPainter painter(WidgetTester tester) =>
        tester.widget<CustomPaint>(board).painter! as DinerPainter;

    Offset onCell(WidgetTester tester, Cell c) {
      final f = painter(tester).fit;
      return tester.getTopLeft(board) +
          f.view.vertex(c.x + 0.5, c.y + 0.5) * f.s;
    }

    testWidgets('tapping a messy table clears it', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump();
      final sim = painter(tester).sim!;
      final seat = sim.seats.first;
      sim.dirty.add(seat.cell);
      await tester.tapAt(onCell(tester, seat.table));
      await tester.pump();
      expect(sim.dirty.contains(seat.cell), isFalse);
      expect(sim.cleaned, 1);
    });

    testWidgets('tapping a clean table does nothing', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump();
      final sim = painter(tester).sim!;
      await tester.tapAt(onCell(tester, sim.seats.first.table));
      await tester.pump();
      expect(sim.cleaned, 0);
    });

    testWidgets('a mess is drawn on the table, and gone when cleared', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump();
      final sim = painter(tester).sim!;
      final seat = sim.seats.first;
      sim.dirty.add(seat.cell);
      expect(sim.actors(1).where((a) => a.sprite == 'mess').length, 1);
      sim.cleanAt(seat.table);
      expect(sim.actors(1).where((a) => a.sprite == 'mess'), isEmpty);
    });

    testWidgets('a person can be kept for the tables from their page', (
      tester,
    ) async {
      final d = cafe();
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
      final s = d.roster.employees.first;
      await tester.tap(find.byKey(const ValueKey('staff')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('team-${s.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Clears tables'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('duty-${s.id}-table')));
      await tester.pump();
      expect(s.duty, Kind.table);
      expect(find.textContaining('clears the tables'), findsOneWidget);
    });
  });

  test('the mess has a picture', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final art = await DinerArt.load(_Assets());
    expect(art.sprite('mess').blank, isFalse);
  });
}

class _Assets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File(key).readAsBytes());
}
