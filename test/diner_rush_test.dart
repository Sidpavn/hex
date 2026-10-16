// Rushing a guest who is about to leave: the kitchen sees to them first.
import 'package:flutter/material.dart';
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

Diner busyKitchen({int staff = 1, int rep = 90}) {
  final d = Diner(
    coins: 100000,
    owned: {0, 1},
    progress: Progress(level: 4, reputation: rep),
  );
  d.declined.add(Dish.cheeseburger);
  d.roster.employees.clear();
  d.progress.upgrades[Upgrade.staff] = staff - 1;
  for (var i = 0; i < staff; i++) {
    d.roster.employees.add(
      Staff(
        id: 70 + i,
        name: 'S$i',
        stats: {Stat.cooking: 4, Stat.speed: 5, Stat.service: 4, Stat.charm: 4},
        potential: {for (final s in Stat.values) s: 10},
      ),
    );
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

/// Runs until [pick] finds a waiting guest, and returns the sim at that moment.
(DinerSim, Guest)? until(int seed, bool Function(Guest) pick, {int staff = 1}) {
  final sim = DinerSim(busyKitchen(staff: staff), seed: seed);
  while (!sim.finished && sim.ticks < 2000) {
    sim.tick();
    for (final g in sim.guests) {
      if (g.state == GuestState.waiting && pick(g)) return (sim, g);
    }
  }
  return null;
}

void main() {
  group('rushing, in the sim', () {
    test('there are two rushes a day', () {
      expect(Pace.rushPerDay, 2);
      expect(DinerSim(busyKitchen()).rushLeft, 2);
    });

    test('a waiting guest can be rushed, once, and it costs a rush', () {
      final (sim, g) = until(1, (g) => g.items.isNotEmpty)!;
      expect(sim.canRush(g), isTrue);
      expect(sim.rush(g), isTrue);
      expect(g.rushed, isTrue);
      expect(sim.rushLeft, 1);
      expect(sim.canRush(g), isFalse);
      expect(sim.rush(g), isFalse, reason: 'already rushed');
      expect(sim.rushLeft, 1);
    });

    test('the rushes run out', () {
      final sim = DinerSim(busyKitchen(), seed: 2);
      final rushed = <Guest>[];
      while (!sim.finished && sim.ticks < 2000 && rushed.length < 3) {
        sim.tick();
        for (final g in sim.guests) {
          if (sim.canRush(g)) {
            if (sim.rush(g)) rushed.add(g);
          } else if (g.state == GuestState.waiting &&
              sim.rushLeft == 0 &&
              !g.rushed) {
            expect(sim.rush(g), isFalse);
            expect(rushed.length, 2);
            return;
          }
        }
      }
      fail('never ran out of rushes');
    });

    test('only a guest still waiting for food can be rushed', () {
      final sim = DinerSim(busyKitchen(), seed: 3);
      while (!sim.finished && sim.ticks < 2000) {
        sim.tick();
        for (final g in sim.guests) {
          if (g.state != GuestState.waiting) {
            expect(sim.rush(g), isFalse, reason: g.state.name);
          }
        }
      }
      expect(sim.rushLeft, 2);
    });

    test('rushes come back with each new day', () {
      final d = busyKitchen();
      final a = DinerSim(d, seed: 1);
      a.rushLeft = 0;
      expect(DinerSim(d, seed: 2).rushLeft, 2);
    });

    test('a dish already cooking comes out sooner', () {
      final (sim, g) = until(1, (g) => sim0Cooking(g))!;
      final m = sim.machines.firstWhere((m) => m.item?.guest == g && !m.ready);
      final before = m.left;
      sim.rush(g);
      expect(m.left, lessThanOrEqualTo(before));
      if (before > 3) expect(m.left, lessThan(before));
    });

    test('a rushed guest\'s dishes cook quicker from the start', () {
      final plain = DinerSim(busyKitchen(), seed: 4);
      final fast = DinerSim(busyKitchen(), seed: 4);
      int firstCook(DinerSim sim, {bool rush = false}) {
        while (sim.ticks < 400) {
          sim.tick();
          if (rush) {
            for (final g in sim.guests.where(sim.canRush)) {
              sim.rush(g);
            }
          }
          for (final m in sim.machines) {
            if (m.item != null && !m.ready) return m.total;
          }
        }
        return -1;
      }

      final slow = firstCook(plain);
      final quick = firstCook(fast, rush: true);
      expect(quick, lessThanOrEqualTo(slow));
    });

    test(
      'with one cook, the rushed guest is served before one who came first',
      () {
        var checked = 0;
        for (final seed in [1, 2, 3, 4, 5, 6]) {
          final sim = DinerSim(busyKitchen(), seed: seed);
          Guest? early;
          Guest? late;
          while (!sim.finished && sim.ticks < 2000) {
            sim.tick();
            final waiting = [
              for (final g in sim.guests)
                if (g.state == GuestState.waiting &&
                    g.items.isNotEmpty &&
                    g.items.every((i) => i.state == ItemState.pending))
                  g,
            ];
            if (waiting.length >= 2) {
              early = waiting.first;
              late = waiting.last;
              break;
            }
          }
          if (early == null || late == null || early == late) continue;
          sim.rush(late);
          var lateDone = -1;
          var earlyDone = -1;
          while (!sim.finished && sim.ticks < 2000) {
            sim.tick();
            if (lateDone < 0 && late.state != GuestState.waiting) {
              lateDone = sim.ticks;
            }
            if (earlyDone < 0 && early.state != GuestState.waiting) {
              earlyDone = sim.ticks;
            }
            if (lateDone > 0 && earlyDone > 0) break;
          }
          if (lateDone > 0 && earlyDone > 0) {
            expect(
              lateDone,
              lessThanOrEqualTo(earlyDone),
              reason: 'seed $seed',
            );
            checked++;
          }
        }
        expect(checked, greaterThan(0));
      },
    );

    test('rushing saves guests who would otherwise have left', () {
      var savedBase = 0;
      var savedRush = 0;
      for (final seed in List.generate(12, (i) => i + 1)) {
        // Find a guest at low patience, and see what happens to them.
        final probe = until(seed, (g) => g.mood < 0.4 && g.items.isNotEmpty);
        if (probe == null) continue;
        final id = probe.$2.id;
        final tick = probe.$1.ticks;

        Guest? find(DinerSim s) =>
            s.guests.where((g) => g.id == id).firstOrNull;

        bool leavesAngry(bool rush) {
          final sim = DinerSim(busyKitchen(), seed: seed);
          while (sim.ticks < tick) {
            sim.tick();
          }
          final g = find(sim)!;
          if (rush) sim.rush(g);
          var angry = false;
          while (!sim.finished && sim.ticks < 2000) {
            sim.tick();
            if (g.angry) angry = true;
            if (g.gone || g.state == GuestState.eating) break;
          }
          return angry;
        }

        if (leavesAngry(false)) savedBase++;
        if (leavesAngry(true)) savedRush++;
      }
      expect(savedRush, lessThanOrEqualTo(savedBase));
      expect(savedBase, greaterThan(0), reason: 'someone does give up');
    });

    test(
      'a rushed guest wears a star, so you can see who is being seen to',
      () {
        final (sim, g) = until(1, (g) => g.items.isNotEmpty)!;
        sim.rush(g);
        final star = sim.actors(1).where((a) => a.badge == 'emote_star');
        expect(star, isNotEmpty);
      },
    );

    test('the story says so', () {
      final (sim, g) = until(1, (g) => g.items.isNotEmpty)!;
      sim.rush(g);
      expect(sim.story.any((l) => l.text.contains(g.name)), isTrue);
    });
  });

  group('rushing, on screen', () {
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
      await tester.pumpWidget(HexApp(home: BuildScreen(diner: busyKitchen())));
      await tester.pump();
    }

    DinerPainter painter(WidgetTester tester) =>
        tester.widget<CustomPaint>(board).painter! as DinerPainter;

    Offset onCell(WidgetTester tester, Cell c) {
      final f = painter(tester).fit;
      return tester.getTopLeft(board) +
          f.view.vertex(c.x + 0.5, c.y + 0.5) * f.s;
    }

    /// Starts the day and runs until someone is waiting for food.
    Future<Guest> waiting(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump();
      for (var i = 0; i < 600; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        final sim = painter(tester).sim!;
        final g = sim.guests
            .where((g) => g.state == GuestState.waiting && g.items.isNotEmpty)
            .firstOrNull;
        if (g != null) return g;
      }
      fail('nobody sat down');
    }

    testWidgets('tapping a guest shows who they are, and a Rush button', (
      tester,
    ) async {
      await open(tester);
      final g = await waiting(tester);
      expect(find.byKey(const ValueKey('guest-card')), findsNothing);
      await tester.tapAt(onCell(tester, g.cell));
      await tester.pump();
      expect(find.byKey(const ValueKey('guest-card')), findsOneWidget);
      expect(find.text(g.name), findsOneWidget);
      expect(
        find.text(
          '${g.gender.singular[0].toUpperCase()}${g.gender.singular.substring(1)}, '
          '${g.temper.label.toLowerCase()}, ${g.wallet.label.toLowerCase()}',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('guest-rush')), findsOneWidget);
    });

    testWidgets('Rush rushes them, and uses up one of two', (tester) async {
      await open(tester);
      final g = await waiting(tester);
      await tester.tapAt(onCell(tester, g.cell));
      await tester.pump();
      final sim = painter(tester).sim!;
      expect(sim.rushLeft, 2);
      await tester.tap(find.byKey(const ValueKey('guest-rush')));
      await tester.pump();
      expect(g.rushed, isTrue);
      expect(sim.rushLeft, 1);
      expect(find.text('Being rushed'), findsOneWidget);
    });

    testWidgets('tapping a guest alone rushes nobody: it takes the button', (
      tester,
    ) async {
      await open(tester);
      final g = await waiting(tester);
      await tester.tapAt(onCell(tester, g.cell));
      await tester.pump();
      await tester.tapAt(onCell(tester, g.cell));
      await tester.pump();
      expect(g.rushed, isFalse);
      expect(painter(tester).sim!.rushLeft, 2);
    });

    testWidgets('Close and tapping bare ground put the card away', (
      tester,
    ) async {
      await open(tester);
      final g = await waiting(tester);
      await tester.tapAt(onCell(tester, g.cell));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('guest-close')));
      await tester.pump();
      expect(find.byKey(const ValueKey('guest-card')), findsNothing);
      await tester.tapAt(onCell(tester, g.cell));
      await tester.pump();
      await tester.tapAt(onCell(tester, const Cell(8, 3)));
      await tester.pump();
      expect(find.byKey(const ValueKey('guest-card')), findsNothing);
    });

    testWidgets('the button is dead once the rushes are used', (tester) async {
      await open(tester);
      final g = await waiting(tester);
      painter(tester).sim!.rushLeft = 0;
      await tester.tapAt(onCell(tester, g.cell));
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('guest-rush')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(g.rushed, isFalse);
      expect(find.text('Rush  0 left'), findsOneWidget, reason: 'says why');
    });

    testWidgets('the card goes when the guest does', (tester) async {
      await open(tester);
      final g = await waiting(tester);
      await tester.tapAt(onCell(tester, g.cell));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('speed-3')));
      for (var i = 0; i < 900 && !g.gone; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump();
      expect(g.gone, isTrue);
      expect(find.byKey(const ValueKey('guest-card')), findsNothing);
    });
  });
}

bool sim0Cooking(Guest g) => g.items.any((i) => i.state == ItemState.cooking);
