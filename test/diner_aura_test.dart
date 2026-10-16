// Decor that helps the seats around it: a TV makes the wait go by, a jukebox
// loosens purses.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/diner_painter.dart';
import 'package:hex/diner/iso.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/diner/service.dart';
import 'package:hex/diner/staff.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';

Diner room({int level = 5, int cooks = 2}) {
  final d = Diner(
    coins: 100000,
    owned: {0, 1},
    progress: Progress(level: level, reputation: 70),
  );
  d.roster.employees.clear();
  d.progress.upgrades[Upgrade.staff] = cooks - 1;
  for (var i = 0; i < cooks; i++) {
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
  for (final t in const [Cell(3, 5), Cell(7, 5)]) {
    d.place(Kind.table, t);
    d.place(Kind.chair, Cell(t.x - 1, t.y), Dir.se);
    d.place(Kind.chair, Cell(t.x + 1, t.y), Dir.nw);
  }
  d.clearUndo();
  return d;
}

void main() {
  group('what decor does', () {
    test('a TV helps the wait, a jukebox the tips, a plant a little', () {
      final tv = fixtureDefs[Kind.tv]!.aura!;
      final plant = fixtureDefs[Kind.plant]!.aura!;
      final jukebox = fixtureDefs[Kind.jukebox]!.aura!;
      expect(tv.effect, AuraEffect.patience);
      expect(plant.effect, AuraEffect.patience);
      expect(jukebox.effect, AuraEffect.tips);
      expect(tv.strength, lessThan(plant.strength), reason: 'TV helps more');
      expect(tv.radius, greaterThan(plant.radius));
      expect(jukebox.strength, greaterThan(1));
    });

    test('a rug and the furniture do nothing for the seats', () {
      for (final k in [Kind.rug, Kind.table, Kind.chair, Kind.grill]) {
        expect(fixtureDefs[k]!.aura, isNull, reason: k.name);
      }
    });

    test('a TV is bought at level 3, and is decor', () {
      final def = fixtureDefs[Kind.tv]!;
      expect(def.role, Role.decor);
      expect(def.unlock, 3);
      expect(def.cost, greaterThan(fixtureDefs[Kind.jukebox]!.cost));
      expect(def.hung, isTrue, reason: 'it hangs on a wall');
      expect(def.turns, isTrue);
    });

    test('they say what they do in plain words', () {
      expect(
        fixtureDefs[Kind.tv]!.aura!.describe,
        'Guests seated within 2 tiles wait 67% longer.',
      );
      expect(
        fixtureDefs[Kind.jukebox]!.aura!.describe,
        'Guests seated within 3 tiles tip 25% more.',
      );
      expect(
        fixtureDefs[Kind.plant]!.aura!.describe,
        startsWith('Guests seated within 1 tile wait'),
      );
    });

    test('the help text carries it', () {
      expect(
        describeFixture(fixtureDefs[Kind.tv]!, Progress()),
        contains('wait 67% longer'),
      );
    });
  });

  group('how far it reaches', () {
    test('no decor, no effect', () {
      final d = room();
      expect(d.drainAt(const Cell(4, 5)), 1);
      expect(d.tipAt(const Cell(4, 5)), 1);
    });

    test(
      'a seat within two tiles of a TV waits longer, one further out does not',
      () {
        final d = room();
        d.place(Kind.tv, const Cell(5, 3));
        expect(d.drainAt(const Cell(4, 5)), closeTo(0.6, 1e-9));
        expect(
          d.drainAt(const Cell(7, 5)),
          closeTo(0.6, 1e-9),
          reason: '2 away',
        );
        expect(d.drainAt(const Cell(8, 5)), 1, reason: '3 away');
        expect(d.drainAt(const Cell(2, 5)), 1, reason: '3 away');
      },
    );

    test('diagonals count: it is a square, not a diamond', () {
      final d = room();
      d.place(Kind.tv, const Cell(5, 3));
      expect(d.drainAt(const Cell(7, 5)), closeTo(0.6, 1e-9));
      expect(d.drainAt(const Cell(8, 6)), 1);
    });

    test('a plant only helps the seat right next to it', () {
      final d = room();
      d.place(Kind.plant, const Cell(5, 7));
      expect(d.drainAt(const Cell(4, 6)), closeTo(0.92, 1e-9));
      expect(d.drainAt(const Cell(3, 5)), 1);
    });

    test('several add up, but never past a floor', () {
      final d = room();
      d.place(Kind.tv, const Cell(5, 3));
      d.place(Kind.plant, const Cell(4, 6));
      expect(d.drainAt(const Cell(4, 5)), closeTo(0.6 * 0.92, 1e-9));
      d.place(Kind.tv, const Cell(4, 3));
      d.place(Kind.tv, const Cell(6, 3));
      expect(d.drainAt(const Cell(4, 5)), Diner.auraFloor);
    });

    test('a jukebox raises tips within three tiles, up to a ceiling', () {
      final d = room();
      d.place(Kind.jukebox, const Cell(5, 5));
      expect(d.tipAt(const Cell(4, 5)), closeTo(1.25, 1e-9));
      expect(d.tipAt(const Cell(8, 5)), closeTo(1.25, 1e-9));
      expect(d.tipAt(const Cell(9, 5)), 1);
      d.place(Kind.jukebox, const Cell(5, 6));
      d.place(Kind.jukebox, const Cell(5, 4));
      expect(d.tipAt(const Cell(4, 5)), Diner.tipCeiling);
    });

    test('a TV does nothing for tips, and a jukebox nothing for patience', () {
      final d = room();
      d.place(Kind.tv, const Cell(5, 3));
      d.place(Kind.jukebox, const Cell(5, 6));
      expect(d.tipAt(const Cell(4, 5)), closeTo(1.25, 1e-9));
      expect(d.drainAt(const Cell(4, 5)), closeTo(0.6, 1e-9));
    });

    test('the tiles it reaches are only the restaurant\'s', () {
      final d = Diner(coins: 1000, progress: Progress(level: 5));
      d.place(Kind.tv, const Cell(1, 3));
      final cells = d.auraCells(d.items.last);
      expect(cells.every(d.isInside), isTrue);
      expect(cells.length, 9, reason: 'a corner: 3 by 3');
      expect(d.auraCells(Placed(0, Kind.table, const Cell(3, 5))), isEmpty);
    });
  });

  group('in a day', () {
    test('guests at a seat by the TV tire of waiting more slowly', () {
      double drainPerTick(bool nearTv) {
        var drop = 0.0;
        var ticks = 0;
        for (final seed in [1, 2, 3, 4]) {
          final d = room(cooks: 1);
          // A TV by the left table, or by neither.
          d.place(Kind.tv, nearTv ? const Cell(3, 3) : const Cell(9, 3));
          final sim = DinerSim(d, seed: seed);
          final last = <int, int>{};
          while (!sim.finished && sim.ticks < 1500) {
            sim.tick();
            for (final g in sim.guests.where(
              (g) =>
                  g.state == GuestState.waiting &&
                  g.seat != null &&
                  g.seat!.table == const Cell(3, 5) &&
                  g.temper.patienceMul == 1,
            )) {
              final before = last[g.id];
              if (before != null) {
                drop += before - g.patience;
                ticks++;
              }
              last[g.id] = g.patience;
            }
          }
        }
        return ticks == 0 ? 0 : drop / ticks;
      }

      final withTv = drainPerTick(true);
      final without = drainPerTick(false);
      expect(without, greaterThan(0));
      expect(withTv, lessThan(without * 0.8));
    });

    test('with TVs by the tables, fewer guests give up', () {
      int gaveUp(bool tvs) {
        var n = 0;
        for (final seed in [1, 2, 3, 4]) {
          final d = room(cooks: 1);
          if (tvs) {
            d.place(Kind.tv, const Cell(3, 3));
            d.place(Kind.tv, const Cell(7, 3));
          }
          final sim = DinerSim(d, seed: seed);
          while (!sim.finished && sim.ticks < 2000) {
            sim.tick();
          }
          n += sim.gaveUp;
        }
        return n;
      }

      expect(gaveUp(true), lessThan(gaveUp(false)));
    });

    test('a jukebox by the table earns bigger tips', () {
      double tipFraction(bool box) {
        var tip = 0.0;
        var price = 0.0;
        for (final seed in [1, 2, 3, 4]) {
          final d = room();
          if (box) {
            d.place(Kind.jukebox, const Cell(3, 4));
            d.place(Kind.jukebox, const Cell(7, 4));
          }
          final sim = DinerSim(d, seed: seed);
          while (!sim.finished && sim.ticks < 2000) {
            sim.tick();
          }
          tip += sim.tips;
          price += sim.earned - sim.tips;
        }
        return tip / price;
      }

      expect(tipFraction(true), greaterThan(tipFraction(false)));
    });

    test('placing a TV in the middle of a day\'s planning counts at once', () {
      final d = room();
      final sim = DinerSim(d, seed: 1);
      d.place(Kind.tv, const Cell(3, 3));
      sim.layoutChanged();
      // The sim picked up the change: a guest at that table drains slower.
      final seat = sim.seats.firstWhere((s) => s.table == const Cell(3, 5));
      expect(d.drainAt(seat.cell), closeTo(0.6, 1e-9));
    });

    test('a TV survives a save', () {
      final d = room();
      d.place(Kind.tv, const Cell(5, 3));
      final back = Diner.fromJson(d.toJson());
      expect(back.hungAt(const Cell(5, 3))?.kind, Kind.tv);
      expect(back.drainAt(const Cell(4, 5)), closeTo(0.6, 1e-9));
    });
  });

  group('showing where it helps', () {
    testWidgets('while a TV is being placed, the tiles it reaches are tinted', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final art = await DinerArt.load();
        final d = room();
        const size = ui.Size(390, 560);
        const dpr = 3.0;
        final fit = BoardFit.of(d, size, dpr);

        Future<Uint8List> shot(Kind? placing, Cell? at) async {
          final rec = ui.PictureRecorder();
          final canvas = ui.Canvas(rec)..scale(dpr);
          DinerPainter(
            diner: d,
            art: art,
            fit: fit,
            placing: placing,
            hover: at,
            placeOk: true,
          ).paint(canvas, size);
          final img = await rec.endRecording().toImage(
            (size.width * dpr).round(),
            (size.height * dpr).round(),
          );
          return (await img.toByteData())!.buffer.asUint8List();
        }

        int pixel(Uint8List px, Cell c, int ch) {
          final v = fit.view.vertex(c.x + 0.5, c.y + 0.5) * fit.s * dpr;
          return px[(v.dy.round() * (size.width * dpr).round() + v.dx.round()) *
                  4 +
              ch];
        }

        final plain = await shot(null, null);
        final tinted = await shot(Kind.tv, const Cell(5, 3));
        // A bare floor tile within two of the TV is bluer than before; one
        // further away is the same.
        const near = Cell(4, 4);
        const far = Cell(9, 4);
        expect(pixel(tinted, near, 2), greaterThan(pixel(plain, near, 2) - 1));
        var changed = 0;
        for (var ch = 0; ch < 3; ch++) {
          changed += (pixel(tinted, near, ch) - pixel(plain, near, ch)).abs();
        }
        expect(changed, greaterThan(8), reason: 'the tile near it changed');
        var same = 0;
        for (var ch = 0; ch < 3; ch++) {
          same += (pixel(tinted, far, ch) - pixel(plain, far, ch)).abs();
        }
        expect(same, 0, reason: 'a tile out of reach did not');
      });
    });

    testWidgets('furniture with no effect has no tint', (tester) async {
      await tester.runAsync(() async {
        final art = await DinerArt.load();
        final d = room();
        const size = ui.Size(390, 560);
        final fit = BoardFit.of(d, size, 3);
        Future<Uint8List> shot(Kind? placing) async {
          final rec = ui.PictureRecorder();
          final canvas = ui.Canvas(rec)..scale(3);
          DinerPainter(
            diner: d,
            art: art,
            fit: fit,
            placing: placing,
            hover: placing == null ? null : const Cell(5, 6),
            placeOk: true,
          ).paint(canvas, size);
          final img = await rec.endRecording().toImage(1170, 1680);
          return (await img.toByteData())!.buffer.asUint8List();
        }

        // A rug's ghost changes only its own outline, never the room.
        final a = await shot(null);
        final b = await shot(Kind.table);
        final v = fit.view.vertex(9.5, 4.5) * fit.s * 3;
        final i = (v.dy.round() * 1170 + v.dx.round()) * 4;
        expect(a.sublist(i, i + 3), b.sublist(i, i + 3));
      });
    });
  });

  group('on screen', () {
    Future<Diner> open(WidgetTester tester, {int level = 5}) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
      });
      Storage.clearMemory();
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final d = room(level: level);
      await tester.pumpWidget(HexApp(home: BuildScreen(diner: d)));
      await tester.pump();
      return d;
    }

    testWidgets('the TV is on the shelf, and locked until level 3', (
      tester,
    ) async {
      await open(tester, level: 2);
      final tile = find.byKey(const ValueKey('fixture-tv'));
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pump();
      expect(find.text('Wall TV unlocks at level 3'), findsOneWidget);
    });

    testWidgets('picking it says what it does', (tester) async {
      await open(tester);
      final tile = find.byKey(const ValueKey('fixture-tv'));
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pump();
      expect(find.textContaining('wait 67% longer'), findsOneWidget);
    });
  });

  test('the TV has a picture', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final art = await DinerArt.load(_Assets());
    expect(art.sprite('tv_sw').blank, isFalse);
    expect(art.sprite('tv_se').blank, isFalse);
    expect(spriteName(Kind.tv, Dir.sw), 'tv_sw');
    expect(spriteName(Kind.tv, Dir.se), 'tv_se');
  });
}

class _Assets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File(key).readAsBytes());
}
