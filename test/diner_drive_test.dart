import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/city.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/actor.dart';
import 'package:hex/diner/diner_painter.dart';
import 'package:hex/diner/iso.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/diner/service.dart';
import 'package:hex/diner/staff.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';

Staff person({int id = 70, Kind? duty}) => Staff(
  id: id,
  name: 'S$id',
  stats: {Stat.cooking: 4, Stat.speed: 5, Stat.service: 4, Stat.charm: 4},
  potential: {for (final s in Stat.values) s: 10},
  duty: duty,
);

/// A kitchen with a takeaway window in the right-hand wall, [cooks] people
/// working wherever they are needed and, if [operator], one more who stays
/// on the window.
Diner withWindow({int cooks = 2, bool operator = false, int rep = 60}) {
  final d = Diner(
    coins: 100000,
    owned: {0, 1},
    progress: Progress(level: 4, reputation: rep),
  );
  d.declined.add(Dish.cheeseburger);
  d.roster.employees.clear();
  d.progress.upgrades[Upgrade.staff] = cooks + (operator ? 1 : 0) - 1;
  for (var i = 0; i < cooks; i++) {
    d.roster.employees.add(person(id: 70 + i));
  }
  if (operator) d.roster.employees.add(person(id: 90, duty: Kind.window));
  d.place(Kind.grill, const Cell(1, 3), Dir.sw);
  d.place(Kind.grill, const Cell(2, 3), Dir.sw);
  d.place(Kind.fryer, const Cell(3, 3), Dir.sw);
  d.place(Kind.soda, const Cell(4, 3), Dir.sw);
  d.place(Kind.counter, const Cell(8, 6), Dir.nw);
  d.place(Kind.counter, const Cell(8, 7), Dir.nw);
  for (final t in const [Cell(3, 5), Cell(6, 5), Cell(5, 7)]) {
    d.place(Kind.table, t);
    d.place(Kind.chair, Cell(t.x - 1, t.y), Dir.se);
    d.place(Kind.chair, Cell(t.x + 1, t.y), Dir.nw);
  }
  expect(d.place(Kind.window, Cell(d.right, 4)), PlaceResult.ok);
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
  group('the takeaway window', () {
    test('it goes in the right-hand wall, and nowhere else', () {
      final d = Diner(coins: 1000, owned: {0, 1}, progress: Progress(level: 3));
      expect(d.place(Kind.window, const Cell(3, 5)), PlaceResult.wall);
      expect(
        d.place(Kind.window, Cell(d.entrance.x, d.bottom)),
        isNot(PlaceResult.ok),
      );
      // Two tiles wide, so it needs two rows of wall.
      expect(
        d.place(Kind.window, Cell(d.right, d.bottom)),
        PlaceResult.outside,
      );
      expect(d.place(Kind.window, Cell(d.right, 4)), PlaceResult.ok);
      expect(d.window!.facing, Dir.se, reason: 'always faces the street');
      expect(d.window!.cells, [Cell(d.right, 4), Cell(d.right, 5)]);
    });

    test('there is one window, and it needs level 3', () {
      final d = Diner(coins: 1000, owned: {0, 1});
      expect(d.place(Kind.window, Cell(d.right, 4)), PlaceResult.locked);
      d.progress.level = 3;
      expect(d.place(Kind.window, Cell(d.right, 4)), PlaceResult.ok);
      expect(d.place(Kind.window, Cell(d.right, 6)), PlaceResult.onlyOne);
    });

    test('it costs money, and turning it does nothing', () {
      final d = Diner(coins: 100, owned: {0, 1}, progress: Progress(level: 3));
      expect(d.place(Kind.window, Cell(d.right, 4)), PlaceResult.broke);
      d.coins = 500;
      d.place(Kind.window, Cell(d.right, 4));
      expect(d.coins, 500 - fixtureDefs[Kind.window]!.cost);
      d.rotate(d.window!);
      expect(d.window!.facing, Dir.se);
    });

    test('staff stand on the two tiles behind it, which must be free', () {
      final d = Diner(coins: 1000, owned: {0, 1}, progress: Progress(level: 3));
      d.place(Kind.window, Cell(d.right, 4));
      expect(d.operatorSpots, [Cell(d.right - 1, 4), Cell(d.right - 1, 5)]);
      expect(d.driveThrough, isTrue);
      expect(d.report().problems, isEmpty);
      d.place(Kind.plant, Cell(d.right - 1, 4));
      expect(d.operatorSpots, [Cell(d.right - 1, 5)], reason: 'one is enough');
      expect(d.driveThrough, isTrue);
      d.place(Kind.plant, Cell(d.right - 1, 5));
      expect(d.driveThrough, isFalse);
      expect(
        d.report().problems.map((p) => p.text),
        contains('Keep a tile behind the window free'),
      );
    });

    test('a window is not needed to open', () {
      final d = Diner.starter();
      expect(d.report().ready, isTrue);
      expect(d.driveThrough, isFalse);
      expect(d.bay, isNull);
    });

    test(
      'it needs the room to the right first, which is what faces the street',
      () {
        final d = Diner(coins: 1000, progress: Progress(level: 3));
        expect(d.place(Kind.window, Cell(d.right, 4)), PlaceResult.noRoad);
        expect(d.window, isNull);
        d.owned.add(1);
        expect(d.place(Kind.window, Cell(d.right, 4)), PlaceResult.ok);
        expect(d.window!.at, const Cell(10, 4));
      },
    );

    test('buying more of the plot leaves the window where it is', () {
      final d = Diner(
        coins: 100000,
        owned: {0, 1},
        progress: Progress(level: 9),
      );
      d.place(Kind.window, Cell(d.right, 4));
      expect(d.unlock(2), isTrue);
      expect(d.unlock(3), isTrue);
      expect(d.window!.at, Cell(d.right, 4));
      expect(d.driveThrough, isTrue);
    });

    test('cars stop in the side street, with the line down it', () {
      final d = withWindow();
      expect(d.inLane, d.right + 2);
      expect(d.outLane, d.right + 3);
      expect(d.bay, Cell(d.inLane, 4));
      expect(groundTile(d, d.bay!), 'road_v');
      expect(groundTile(d, Cell(d.outLane, 4)), 'road_b');
      expect(d.carSlot(1), Cell(d.inLane, 4 + Diner.carSpacing));
      expect(d.carSlot(2), Cell(d.inLane, 4 + 2 * Diner.carSpacing));
      expect(d.passRow, d.laneRow + 1);
    });

    test('the nearer the back the window, the longer the line', () {
      final d = Diner(coins: 5000, owned: {0, 1}, progress: Progress(level: 3));
      d.place(Kind.window, Cell(d.right, 3));
      final back = d.carQueueLength;
      d.moveTo(d.window!, Cell(d.right, 6));
      expect(d.carQueueLength, lessThan(back));
      expect(d.carQueueLength, greaterThanOrEqualTo(1));
      // Every place in the line is on the side street, not the main road.
      d.moveTo(d.window!, Cell(d.right, 3));
      for (var i = 0; i < d.carQueueLength; i++) {
        expect(d.carSlot(i).y, lessThanOrEqualTo(d.bottom + 2));
      }
    });

    test('it is saved with the restaurant', () {
      final d = withWindow(operator: true);
      final back = Diner.fromJson(d.toJson());
      expect(back.window?.at, d.window!.at);
      expect(back.window!.facing, Dir.se);
      expect(back.roster.employees.last.duty, Kind.window);
      expect(back.driveThrough, isTrue);
    });

    test('a window saved in the front wall is sold back', () {
      final d = Diner(coins: 100, owned: {0, 1}, progress: Progress(level: 3));
      final json = d.toJson();
      (json['items'] as List).add({
        'k': 'window',
        'x': 3,
        'y': d.bottom,
        'f': 'sw',
      });
      final back = Diner.fromJson(json);
      expect(back.window, isNull);
      expect(back.coins, 100 + fixtureDefs[Kind.window]!.cost);
    });
  });

  group('cars', () {
    test('the staff share the window, so cars are served without a hire', () {
      final sim = play(withWindow(cooks: 3));
      expect(sim.carSchedule, isNotEmpty);
      expect(sim.carsServed, greaterThan(2));
      expect(sim.result!.cars, sim.carsServed);
    });

    test('with an operator they come, and are served and pay', () {
      final sim = play(withWindow(cooks: 3, operator: true));
      expect(sim.carsServed, greaterThan(2));
      expect(sim.earned, greaterThan(0));
    });

    test('anyone free walks to the window when a car pulls up', () {
      final d = withWindow(cooks: 2);
      final sim = DinerSim(d, seed: 2);
      final served = <String>{};
      while (!sim.finished) {
        sim.tick();
        for (final w in sim.workers) {
          if (d.operatorSpots.contains(w.cell)) served.add(w.staff.name);
        }
      }
      expect(served.length, greaterThan(0));
      expect(sim.carsServed, greaterThan(0));
    });

    test('both tiles behind the window can be used at once', () {
      var both = false;
      for (final seed in [1, 2, 3]) {
        final d = withWindow(cooks: 3, operator: true, rep: 95);
        final sim = DinerSim(d, seed: seed);
        while (!sim.finished && !both) {
          sim.tick();
          final on = d.operatorSpots
              .where((c) => sim.workers.any((w) => w.cell == c))
              .length;
          if (on == 2) both = true;
        }
      }
      expect(both, isTrue);
    });

    test('a window with nobody to spare brings nobody', () {
      final d = withWindow(cooks: 1);
      d.roster.employees.clear();
      final sim = DinerSim(d, seed: 4);
      while (!sim.finished) {
        sim.tick();
        expect(sim.carsServed, 0);
      }
    });

    test('cars stay on the side street and the road', () {
      final d = withWindow(cooks: 1, rep: 90);
      final sim = DinerSim(d, seed: 2);
      var most = 0;
      while (!sim.finished) {
        sim.tick();
        final cars = sim.guests.where((g) => g.car).toList();
        for (final c in cars) {
          expect(
            c.cell.x >= d.inLane || c.cell.y >= d.laneRow,
            isTrue,
            reason: '${c.name} at ${c.cell} is off the road',
          );
        }
        final waiting = cars
            .where(
              (c) =>
                  c.state == GuestState.queued || c.state == GuestState.waiting,
            )
            .length;
        if (waiting > most) most = waiting;
      }
      expect(most, greaterThan(1));
      expect(most, lessThanOrEqualTo(d.carQueueLength));
    });

    test('a car is served at the window and does not sit and eat', () {
      final sim = DinerSim(withWindow(cooks: 3), seed: 3);
      while (!sim.finished) {
        sim.tick();
        for (final g in sim.guests.where((g) => g.car)) {
          expect(g.state, isNot(GuestState.eating));
          expect(g.state, isNot(GuestState.toSeat));
        }
      }
    });

    test('someone set to the window stays on it and does not cook', () {
      final d = withWindow(cooks: 3, operator: true, rep: 80);
      final sim = DinerSim(d, seed: 3);
      while (!sim.finished) {
        sim.tick();
        for (final w in sim.workers) {
          if (w.staff.duty != Kind.window) continue;
          for (final i in w.carrying) {
            expect(i.guest.car, isTrue, reason: 'only cars for them');
          }
        }
      }
      final op = d.roster.employees.last;
      expect(op.made(Dish.burger), 0);
      expect(op.plates, greaterThan(0));
    });

    test('with the kitchen able to keep up, the window pays for itself', () {
      int profit(Diner Function() make) {
        var total = 0;
        for (final seed in [1, 2, 3]) {
          final s = play(make(), seed: seed);
          total += s.earned - s.ingredientCost - s.result!.wages;
        }
        return total;
      }

      final plain = profit(
        () =>
            withWindow(cooks: 4)
              ..items.removeWhere((p) => p.kind == Kind.window),
      );
      final driveThru = profit(() => withWindow(cooks: 4));
      expect(driveThru, greaterThan(plain));
    });

    test('every car, the window and its wall have pictures', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final art = await DinerArt.load(_Assets());
      for (final c in ['car_red', 'car_blue', 'car_sun']) {
        for (final f in Dir.values) {
          expect(art.has('${c}_${f.name}'), isTrue, reason: '$c ${f.name}');
        }
      }
      expect(art.has(spriteName(Kind.window, Dir.se)), isTrue);
      expect(art.has('front_win_r0'), isTrue);
      expect(art.has('front_win_r1'), isTrue);
    });

    test('a car is bigger than a person, and two cells long', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final art = await DinerArt.load(_Assets());
      final car = art.sprite('car_red_se');
      final person = art.sprite('cust_a_sw_s0');
      expect(car.trim.width, greaterThan(person.trim.width * 2));
      expect(car.trim.height, greaterThanOrEqualTo(person.trim.height * 0.8));
    });
  });

  group('the queue of cars', () {
    DinerSim busy(int seed, {int cooks = 3}) =>
        DinerSim(withWindow(cooks: cooks, rep: 95), seed: seed);

    test('two cars are never on the same square', () {
      for (final seed in [1, 2, 3, 4, 5]) {
        final sim = busy(seed);
        while (!sim.finished && sim.ticks < 2000) {
          sim.tick();
          final seen = <Cell, String>{};
          for (final g in sim.guests.where((g) => g.car)) {
            final other = seen[g.cell];
            expect(
              other,
              isNull,
              reason:
                  't${sim.ticks} seed $seed ${g.name} and $other '
                  'both at ${g.cell}',
            );
            seen[g.cell] = g.name;
          }
        }
      }
    });

    test('waiting cars stand apart, so their pictures do not overlap', () {
      final sim = busy(2, cooks: 1);
      while (!sim.finished) {
        sim.tick();
        final line = [
          for (final g in sim.guests)
            if (g.car &&
                g.state == GuestState.queued &&
                g.cell.x == sim.diner.inLane &&
                g.path.isEmpty)
              g.cell.y,
        ]..sort();
        for (var i = 1; i < line.length; i++) {
          expect(
            line[i] - line[i - 1],
            greaterThanOrEqualTo(Diner.carSpacing),
            reason: 't${sim.ticks} $line',
          );
        }
      }
    });

    test('a car that gives up crosses over and goes back down the street', () {
      var crossed = 0;
      for (final seed in [1, 2, 3, 4, 5, 6]) {
        final sim = busy(seed, cooks: 1);
        final d = sim.diner;
        while (!sim.finished && sim.ticks < 2000) {
          sim.tick();
          for (final g in sim.guests.where((g) => g.car)) {
            if (g.state != GuestState.leaving) continue;
            for (final o in sim.guests.where((o) => o.car && o != g)) {
              if (o.state == GuestState.queued ||
                  o.state == GuestState.waiting) {
                expect(g.cell, isNot(o.cell));
              }
            }
            if (g.cell.x == d.outLane && g.cell.y < d.laneRow) crossed++;
          }
        }
      }
      expect(crossed, greaterThan(0), reason: 'someone used the outbound lane');
    });

    test('the next car waits for the bay to clear before pulling in', () {
      final sim = busy(3);
      final d = sim.diner;
      while (!sim.finished) {
        sim.tick();
        final atBay = sim.guests.where((g) => g.car && g.cell == d.bay);
        expect(atBay.length, lessThanOrEqualTo(1));
      }
    });

    test('everybody gets off the road by the end of the day', () {
      for (final seed in [1, 2, 3]) {
        final sim = busy(seed, cooks: 1);
        while (!sim.finished && sim.ticks < 2500) {
          sim.tick();
        }
        expect(sim.finished, isTrue, reason: 'seed $seed never finished');
        expect(sim.guests.where((g) => g.car), isEmpty);
      }
    });

    test('cars that find the line full use the far lane of the main road', () {
      var passed = 0;
      for (final seed in [1, 2, 3]) {
        final sim = busy(seed, cooks: 1);
        final d = sim.diner;
        while (!sim.finished && sim.ticks < 2000) {
          sim.tick();
          for (final g in sim.guests) {
            if (g.car && g.passerby) {
              expect(g.cell.y, d.passRow);
              passed++;
            }
          }
        }
      }
      expect(passed, greaterThan(0));
    });
  });

  group('leaving the road', () {
    test('cars drive out of sight, not off in the middle of the picture', () {
      for (final yard in [false, true]) {
        final d = withWindow();
        if (yard) d.owned.addAll({2, 3, 4, 5});
        final view = IsoView(d);
        final out = view.vertex(d.laneEnd.x, d.laneEnd.y);
        expect(out.dx, greaterThan(view.width + 16), reason: 'yard $yard');
        final far = view.vertex(d.passStart.x, d.passStart.y);
        expect(far.dx, lessThan(-16), reason: 'they come from out of sight');
      }
    });

    test('a car is only removed once it has driven all the way out', () {
      for (final seed in [1, 2, 3]) {
        final d = withWindow(cooks: 1, rep: 95);
        final sim = DinerSim(d, seed: seed);
        final last = <int, Cell>{};
        var removed = 0;
        while (!sim.finished) {
          sim.tick();
          final now = {
            for (final g in sim.guests)
              if (g.car) g.id: g,
          };
          if (!sim.finished) {
            for (final id in last.keys.toList()) {
              if (now.containsKey(id)) continue;
              removed++;
              expect(
                last[id]!.x,
                greaterThanOrEqualTo(d.carExit - 1),
                reason: 'car $id vanished at ${last[id]}',
              );
              last.remove(id);
            }
          }
          for (final e in now.entries) {
            last[e.key] = e.value.cell;
          }
        }
        expect(removed, greaterThan(0));
      }
    });
  });

  group('cars and the building across the street', () {
    testWidgets('a car further back is hidden by it, not drawn over it', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final art = await DinerArt.load();
        final d = withWindow();
        const size = ui.Size(390, 560);
        const dpr = 3.0;
        final fit = BoardFit.of(d, size, dpr);

        Future<ui.Image> render(List<Actor> actors) async {
          final rec = ui.PictureRecorder();
          final canvas = ui.Canvas(rec)..scale(dpr);
          DinerPainter(
            diner: d,
            art: art,
            fit: fit,
            actors: actors,
          ).paint(canvas, size);
          return rec.endRecording().toImage(
            (size.width * dpr).round(),
            (size.height * dpr).round(),
          );
        }

        // A car on the side street, level with the building's back rows.
        final car = Actor(
          'car_red_ne',
          d.outLane + 0.5,
          3.5,
          row: d.outLane + 0.5 + 3.5,
        );
        final without = await render(const []);
        final with_ = await render([car]);
        Future<List<int>> pixels(ui.Image i) async =>
            (await i.toByteData())!.buffer.asUint8List().toList();
        final a = await pixels(without);
        final b = await pixels(with_);
        final width = without.width;

        // Where the nearest building cell is on the picture, pixel by pixel:
        // only the parts of it that are solid count.
        final first = d.right + 5;
        final spr = art.sprite('low_a');
        final solid = (await spr.image.toByteData())!.buffer.asUint8List();
        final origin = fit.view.vertex(first, 3);
        final k = fit.k;
        final left = (origin.dx - spr.ax).round() * k;
        final top = (origin.dy - spr.ay).round() * k;
        var carPixels = 0;
        var overBuilding = 0;
        for (var y = 0; y < without.height; y++) {
          for (var x = 0; x < width; x++) {
            final i = (y * width + x) * 4;
            final differs =
                a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2];
            if (!differs) continue;
            carPixels++;
            final sx = (x - left) ~/ k;
            final sy = (y - top) ~/ k;
            if (x < left || y < top || sx >= spr.width || sy >= spr.height) {
              continue;
            }
            if (solid[(sy * spr.width + sx) * 4 + 3] > 0) overBuilding++;
          }
        }
        expect(carPixels, greaterThan(100), reason: 'the car was drawn');
        expect(overBuilding, 0, reason: 'but not over the building');
      });
    });
  });

  group('staying inside the picture', () {
    testWidgets(
      'nothing is drawn outside the board, however far in it is zoomed',
      (tester) async {
        await tester.runAsync(() async {
          final art = await DinerArt.load();
          for (final yard in [false, true]) {
            final d = withWindow();
            if (yard) d.owned.addAll({2, 3, 4, 5});
            const size = ui.Size(390, 560);
            const dpr = 3.0;
            final sim = DinerSim(d, seed: 2);
            for (var i = 0; i < 200; i++) {
              sim.tick();
            }
            final base = BoardFit.of(d, size, dpr);
            for (final k in [base.kFit, base.kFit + 1, base.kMax]) {
              for (final focus in [
                null,
                const ui.Offset(0, 0),
                ui.Offset(base.view.width, 0),
              ]) {
                final fit = BoardFit.of(d, size, dpr, k: k, focus: focus);
                // A canvas a little bigger than the board, so a spill shows.
                const margin = 40.0;
                final rec = ui.PictureRecorder();
                final canvas = ui.Canvas(rec)..scale(dpr);
                DinerPainter(
                  diner: d,
                  art: art,
                  fit: fit,
                  sim: sim,
                  gesturing: true,
                ).paint(canvas, size);
                final image = await rec.endRecording().toImage(
                  ((size.width + margin) * dpr).round(),
                  ((size.height + margin) * dpr).round(),
                );
                final px = (await image.toByteData())!.buffer.asUint8List();
                final w = image.width;
                final edgeX = (size.width * dpr).round();
                final edgeY = (size.height * dpr).round();
                var spilled = 0;
                for (var y = 0; y < image.height; y++) {
                  for (var x = 0; x < w; x++) {
                    if (x < edgeX && y < edgeY) continue;
                    if (px[(y * w + x) * 4 + 3] != 0) spilled++;
                  }
                }
                expect(spilled, 0, reason: 'yard $yard zoom $k focus $focus');
              }
            }
          }
        });
      },
    );
  });

  group('placing the window', () {
    test('it snaps to the nearest place along the wall', () {
      final d = Diner(coins: 1000, owned: {0, 1}, progress: Progress(level: 3));
      expect(d.windowRow(5), 5);
      expect(d.windowRow(-3), Diner.top);
      expect(d.windowRow(40), d.bottom - 1, reason: 'two tiles must fit');
    });

    test('it skips places that are taken', () {
      final d = Diner(coins: 1000, owned: {0, 1}, progress: Progress(level: 3));
      d.place(Kind.plant, Cell(d.right, 5));
      expect(d.windowFits(5), isFalse);
      expect(d.windowFits(4), isFalse, reason: 'it would cover row 5');
      expect(d.windowRow(5), isNot(anyOf(4, 5)));
      expect(d.windowFits(6), isTrue);
    });

    test('once placed, moving it shows the same places plus its own', () {
      final d = Diner(coins: 1000, owned: {0, 1}, progress: Progress(level: 3));
      d.place(Kind.window, Cell(d.right, 4));
      expect(d.windowFits(6), isFalse, reason: 'only one');
      expect(d.windowFits(6, ignore: d.window), isTrue);
      expect(d.windowRow(3, ignore: d.window), 3);
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

    testWidgets('staff can be put on the window, and told what it means', (
      tester,
    ) async {
      final d = withWindow();
      d.progress.upgrades[Upgrade.staff] = 2;
      final s = d.roster.employees.first;
      await open(tester, d);
      await tester.tap(find.byKey(const ValueKey('staff')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('team-${s.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('duty-${s.id}-window')));
      await tester.pump();
      expect(s.duty, Kind.window);
      expect(find.textContaining('takeaway window'), findsWidgets);
    });

    testWidgets('choosing the window says where it goes', (tester) async {
      final d = withWindow();
      d.items.removeWhere((p) => p.kind == Kind.window);
      await open(tester, d);
      await tester.ensureVisible(find.byKey(const ValueKey('fixture-window')));
      await tester.tap(find.byKey(const ValueKey('fixture-window')));
      await tester.pump();
      expect(find.textContaining('Tap the right-hand wall'), findsOneWidget);
    });

    testWidgets('the summary says how many came by car', (tester) async {
      final d = await open(tester, withWindow(cooks: 3));
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('speed-3')));
      await tester.pump();
      for (var i = 0; i < 900; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byKey(const ValueKey('next-day')).evaluate().isNotEmpty) break;
      }
      expect(find.byKey(const ValueKey('next-day')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('details')));
      await tester.tap(find.byKey(const ValueKey('details')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cars-line')), findsOneWidget);
      expect(d.progress.day, 2);
    });
  });
}

/// Loads sprites from the real files, for tests that run without a bundle.
class _Assets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = await File(key).readAsBytes();
    return ByteData.sublistView(bytes);
  }
}
