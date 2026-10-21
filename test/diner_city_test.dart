import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/city.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/iso.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/diner/service.dart';
import 'package:hex/diner/staff.dart';

/// A restaurant with every section of the plot bought.
Diner wholePlot() {
  final d = Diner(
    coins: 1000000,
    owned: {for (var i = 0; i < Diner.plots.length; i++) i},
    progress: Progress(level: 9, reputation: 60),
  );
  return d;
}

void main() {
  group('the plot', () {
    test('it starts as 6 by 5, with the rest of the plot to buy', () {
      final d = Diner(coins: 0);
      expect([d.width, d.height], [6, 5]);
      expect(d.owned, {0});
      expect(d.isInside(const Cell(3, 5)), isTrue);
      expect(d.isInside(const Cell(8, 5)), isFalse);
      expect(d.isInside(const Cell(3, 1)), isFalse);
      expect(d.isLocked(const Cell(8, 5)), isTrue);
      expect(d.isLocked(const Cell(3, 1)), isTrue);
    });

    test('the sections add up to the plot, with wings on the left', () {
      final tiles = Diner.plots.fold(0, (a, p) => a + p.tiles);
      // Ten wide and twenty-one deep, and three wings four wide.
      expect(tiles, 10 * 21 + 4 * 5 + 4 * 4 + 4 * 4);
      expect(Diner.plots.length, 13);
      final seen = <Cell>{};
      for (final p in Diner.plots) {
        for (var y = p.y0; y <= p.y1; y++) {
          for (var x = p.x0; x <= p.x1; x++) {
            expect(seen.add(Cell(x, y)), isTrue, reason: 'overlap at $x,$y');
          }
        }
      }
      expect(seen.every(onPlot), isTrue);
      expect(Diner.plots[0].tiles, 30);
      expect(Diner.plots[1].tiles, 20);
    });

    test('every section but the first needs the one in front of it', () {
      expect(Diner.plots[0].needs, isNull);
      expect(Diner.plots[1].needs, 0, reason: 'the room beside the first');
      for (var i = 2; i < 10; i++) {
        final needs = Diner.plots[i].needs!;
        expect(needs, lessThan(i));
        // The one in front is nearer the street, in the same column.
        expect(Diner.plots[needs].x0, Diner.plots[i].x0);
        expect(Diner.plots[needs].y0, greaterThan(Diner.plots[i].y0));
      }
    });

    test('a section cannot be bought before the one in front of it', () {
      final d = Diner(coins: 100000, progress: Progress(level: 9));
      expect(d.whyLocked(3), contains('first'));
      expect(d.canUnlock(3), isFalse);
      expect(d.unlock(3), isFalse);
      expect(d.coins, 100000);
      expect(d.unlock(1), isTrue);
      expect(d.canUnlock(3), isTrue);
    });

    test('the front widens to ten when the section beside it is bought', () {
      final d = Diner(coins: 100000, progress: Progress(level: 9));
      expect(d.right, 6);
      expect(d.unlock(1), isTrue);
      expect([d.width, d.height], [10, 5]);
      expect(d.right, 10);
      expect(d.isInside(const Cell(9, 4)), isTrue);
    });

    test('each section costs more than the last, by size as well', () {
      final d = Diner(coins: 0);
      final first = d.unlockCost(1);
      final second = d.unlockCost(2);
      expect(first, 120);
      expect(second, 140, reason: '24 tiles, to the nearest ten');
      d.owned.add(1);
      expect(
        d.unlockCost(2),
        greaterThan(second),
        reason: 'dearer once you own more',
      );
      d.owned.add(2);
      expect(d.unlockCost(3), greaterThan(16 * 6 * 1.7 - 10));
    });

    test('a section needs the restaurant to be a high enough level', () {
      final d = Diner(coins: 100000, progress: Progress(level: 1));
      expect(d.whyLocked(1), 'Needs restaurant level 2');
      d.progress.level = 2;
      expect(d.whyLocked(1), isNull);
      expect(d.whyLocked(2), 'Needs restaurant level 3');
      for (var i = 1; i < 10; i++) {
        expect(
          Diner.plots[i].level,
          greaterThanOrEqualTo(Diner.plots[i - 1].level),
          reason: 'further back needs a better restaurant',
        );
      }
      for (var i = 10; i < Diner.plots.length; i++) {
        expect(
          Diner.plots[i].level,
          greaterThanOrEqualTo(Diner.plots[Diner.plots[i].needs!].level),
          reason: 'a wing needs at least what the room it opens from needed',
        );
      }
    });

    test('it takes the money, and says so when there is not enough', () {
      final d = Diner(coins: 100, progress: Progress(level: 9));
      expect(d.whyLocked(1), 'Not enough coins');
      expect(d.unlock(1), isFalse);
      d.coins = 1000;
      final cost = d.unlockCost(1);
      expect(d.unlock(1), isTrue);
      expect(d.coins, 1000 - cost);
      expect(d.unlock(1), isFalse, reason: 'only once');
      expect(d.whyLocked(1), 'Yours already');
    });

    test('what is next to buy is what has its front neighbour', () {
      final d = Diner(coins: 0);
      expect(d.nextPlots, [1, 2, 10]);
      d.owned.add(1);
      expect(d.nextPlots, [2, 3, 10]);
      d.owned.addAll({2, 3});
      expect(d.nextPlots, [4, 5, 10]);
      d.owned.addAll({4, 5});
      expect(d.nextPlots, [6, 7, 10]);
      d.owned.addAll({6, 7});
      expect(d.nextPlots, [8, 9, 10]);
      d.owned.addAll({8, 9});
      expect(d.nextPlots, [10]);
      d.owned.add(10);
      expect(d.nextPlots, [11]);
      d.owned.add(11);
      expect(d.nextPlots, [12]);
      d.owned.add(12);
      expect(d.nextPlots, isEmpty);
    });

    test('bought sections join into one room, with no gaps', () {
      final d = wholePlot();
      final reach = d.reachable();
      expect(reach.length, 262);
      expect(d.insideCells().length, 262);
      expect(reach, contains(const Cell(10, -13)));
    });

    test('a section behind is reached through the room in front', () {
      final d = Diner(coins: 0, owned: {0, 2});
      expect(d.reachable(), contains(const Cell(3, 0)));
      // Block the way between the two and it is refused.
      final blocked = Diner(coins: 1000, owned: {0, 2});
      for (var x = 1; x <= 6; x++) {
        if (x == 6) {
          expect(
            blocked.check(Kind.counter, Cell(x, 3)),
            PlaceResult.blocksWay,
          );
        } else {
          blocked.place(Kind.counter, Cell(x, 3));
        }
      }
    });

    test('only what is bought can be built on', () {
      final d = Diner(coins: 1000);
      expect(d.check(Kind.plant, const Cell(8, 5)), PlaceResult.outside);
      expect(d.check(Kind.plant, const Cell(3, 1)), PlaceResult.outside);
      d.owned.add(2);
      expect(d.check(Kind.plant, const Cell(3, 1)), PlaceResult.ok);
    });

    test('the view takes in what is owned and what could be bought next', () {
      final d = Diner(coins: 0);
      // The start, the room beside it and the one behind it.
      expect(d.topRow, -1);
      expect(d.rightCol, 10);
      d.owned.addAll({2});
      expect(d.topRow, -5, reason: 'and the one behind that');
      d.owned.addAll({4});
      expect(d.topRow, -9);
      final small = IsoView(Diner(coins: 0));
      final big = IsoView(d);
      expect(big.height, greaterThan(small.height));
    });

    test('every owned cell lands on the board', () {
      final d = wholePlot();
      final view = IsoView(d);
      for (final c in d.insideCells()) {
        final v = view.vertex(c.x, c.y);
        expect(v.dx, inInclusiveRange(0, view.width));
        expect(v.dy, inInclusiveRange(0, view.height));
      }
    });

    test('the plot survives a save, with things built in every section', () {
      final d = wholePlot();
      d.place(Kind.table, const Cell(4, -3));
      d.place(Kind.chair, const Cell(3, -3), Dir.se);
      final back = Diner.fromJson(d.toJson());
      expect(back.owned, d.owned);
      expect(back.objectAt(const Cell(4, -3))?.kind, Kind.table);
      expect(back.objectAt(const Cell(3, -3))?.kind, Kind.chair);
    });

    test('things saved in a section that is not owned are sold back', () {
      final d = wholePlot();
      d.place(Kind.plant, const Cell(4, -3));
      d.coins = 0;
      final json = d.toJson()..['owned'] = [0];
      final back = Diner.fromJson(json);
      expect(back.owned, {0});
      expect(back.objectAt(const Cell(4, -3)), isNull);
      expect(back.coins, fixtureDefs[Kind.plant]!.cost);
    });

    test('the first section is always yours, whatever a save says', () {
      final d = Diner.fromJson({
        'coins': 1,
        'owned': [3],
        'items': [],
      });
      expect(d.owned, {0, 3});
      expect(Diner.fromJson({'coins': 1, 'items': []}).owned, {0});
    });

    test('an old save keeps its width and its yard as sections', () {
      final wide = Diner.fromJson({'coins': 5, 'wide': 2, 'items': []});
      expect(wide.owned, {0, 1});
      final yard = Diner.fromJson({
        'coins': 5,
        'wide': 1,
        'backLot': true,
        'items': [],
      });
      expect(yard.owned, {0, 1, 2, 3, 4, 5});
      final yardNarrow = Diner.fromJson({
        'coins': 5,
        'backLot': true,
        'items': [],
      });
      expect(yardNarrow.owned, {0, 2, 4});
    });

    test('old rooms deeper than the front are sold back', () {
      final d = Diner.fromJson({
        'coins': 0,
        'deep': 2,
        'items': [
          {'k': 'table', 'x': 3, 'y': 10, 'f': 'sw'},
          {'k': 'table', 'x': 3, 'y': 4, 'f': 'sw'},
        ],
      });
      expect(d.items.length, 1);
      expect(d.coins, fixtureDefs[Kind.table]!.cost);
    });
  });

  group('the ground', () {
    test(
      'owned is floor, bought-able is bare earth, and beside it concrete',
      () {
        final d = Diner(coins: 0);
        expect(groundTile(d, const Cell(3, 5)), startsWith('floor'));
        expect(groundTile(d, const Cell(8, 5)), 'lot');
        expect(groundTile(d, const Cell(3, -3)), 'lot');
        expect(groundTile(d, const Cell(-3, 5)), 'lot');
        expect(groundTile(d, const Cell(-8, 5)), startsWith('concrete'));
        expect(
          groundTile(d, Cell(Diner.plotRight + 7, 2)),
          startsWith('concrete'),
        );
        d.owned.add(1);
        expect(groundTile(d, const Cell(8, 5)), startsWith('floor'));
      },
    );

    test('no buildings are drawn: nothing in the ground names one', () {
      final d = wholePlot();
      for (var y = -8; y <= d.bottom + 8; y++) {
        for (var x = -10; x <= 20; x++) {
          expect(groundTile(d, Cell(x, y)), isNot(startsWith('bld')));
          expect(groundTile(d, Cell(x, y)), isNot(startsWith('low_')));
        }
      }
    });

    test('the side street runs the whole length of the plot', () {
      final d = Diner(coins: 0);
      for (var y = Diner.plotTop; y <= d.bottom; y++) {
        expect(groundTile(d, Cell(Diner.plotRight + 2, y)), 'road_v');
        expect(groundTile(d, Cell(Diner.plotRight + 3, y)), 'road_b');
        expect(
          groundTile(d, Cell(Diner.plotRight + 1, y)),
          startsWith('sidewalk'),
        );
      }
      expect(
        groundTile(d, Cell(Diner.plotRight + 2, d.bottom + 1)),
        'crosswalk_h',
      );
    });

    test(
      'there are no signs on the plot: only lamps and trees on the kerb',
      () {
        for (final owned in [
          <int>{0},
          {0, 1},
          {0, 1, 2, 3, 4, 5},
        ]) {
          final props = streetProps(Diner(coins: 0, owned: owned));
          expect(props.map((p) => p.$1).toSet(), {'lamp', 'tree'});
          for (final p in props) {
            expect(onPlot(p.$2), isFalse, reason: '${p.$1} on the plot');
          }
        }
      },
    );

    test('everything the ground names has a picture file', () {
      final d = wholePlot();
      final names = <String>{};
      for (var y = -9; y <= d.bottom + 8; y++) {
        for (var x = -10; x <= 20; x++) {
          names.add(groundTile(d, Cell(x, y)));
        }
      }
      expect(
        names,
        containsAll(['floor_a', 'road_v', 'crosswalk_h', 'concrete_a']),
      );
    });
  });

  group('the neighbouring buildings', () {
    test('there are six, each one sprite, three a side', () {
      expect(buildings.length, 6);
      expect(buildings.map((b) => b.sprite).toSet().length, 4);
      expect(buildings.where((b) => b.x0 < 0).length, 3);
      expect(buildings.where((b) => b.x0 > 10).length, 3);
    });

    test('they stand clear of the plot, the street and each other', () {
      for (final a in buildings) {
        for (var y = a.y0; y < a.y0 + a.d; y++) {
          for (var x = a.x0; x < a.x0 + a.w; x++) {
            final c = Cell(x, y);
            expect(onPlot(c), isFalse, reason: '${a.sprite} on the plot');
            final tile = groundTile(wholePlot(), c);
            expect(tile, startsWith('concrete'), reason: '${a.sprite} $c');
            for (final b in buildings) {
              if (b != a) expect(b.contains(c), isFalse, reason: '$c shared');
            }
          }
        }
      }
    });

    test('on one side they join up, with no gap between them', () {
      final left = buildings.where((b) => b.x0 < 0).toList()
        ..sort((a, b) => a.y0.compareTo(b.y0));
      expect(left[0].y0 + left[0].d, left[1].y0);
      expect(left[0].x0, left[1].x0);
      expect(left[0].w, left[1].w);
      final right = buildings.where((b) => b.x0 > 10).toList()
        ..sort((a, b) => a.y0.compareTo(b.y0));
      expect(right[0].y0 + right[0].d, right[1].y0);
    });

    test('a building is one long wall, not a row of one-tile blocks', () {
      for (final b in buildings) {
        expect(b.w * b.d, greaterThan(20), reason: b.sprite);
        expect(b.w, greaterThanOrEqualTo(4));
        expect(b.d, greaterThanOrEqualTo(7));
      }
    });

    test('they reach the street at the front, like the shops they are', () {
      for (final b in buildings.where((b) => b.y0 > 0)) {
        expect(b.y0 + b.d - 1, Diner.plots[0].y1);
      }
    });

    test('a pavement runs between the plot and the buildings on the left', () {
      final d = Diner(coins: 0);
      for (var y = -6; y <= d.bottom; y++) {
        expect(
          groundTile(d, Cell(Diner.plotLeft - 1, y)),
          startsWith('sidewalk'),
          reason: '$y',
        );
        expect(
          groundTile(d, Cell(Diner.plotLeft - 2, y)),
          startsWith('sidewalk'),
          reason: '$y',
        );
      }
    });

    test('each building is a whole picture big enough to hold it', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final art = await DinerArt.load(_Assets());
      for (final b in buildings) {
        final spr = art.sprite(b.sprite);
        expect(spr.blank, isFalse, reason: b.sprite);
        expect(spr.trim.width, greaterThanOrEqualTo(16.0 * (b.w + b.d) - 8));
        expect(spr.trim.height, greaterThan(8.0 * (b.w + b.d)));
      }
      for (final old in ['bld_a', 'bld_b', 'low_a', 'low_a_front']) {
        expect(art.has(old), isFalse, reason: '$old is gone');
      }
    });
  });

  group('serving across the plot', () {
    Diner behind() {
      final d = Diner(
        coins: 100000,
        owned: {0, 2},
        progress: Progress(level: 6, reputation: 60),
      );
      d.roster.employees.clear();
      d.progress.upgrades[Upgrade.staff] = 1;
      for (var i = 0; i < 2; i++) {
        d.roster.employees.add(
          Staff(
            id: 70 + i,
            name: 'S$i',
            stats: {
              Stat.cooking: 4,
              Stat.speed: 5,
              Stat.service: 4,
              Stat.charm: 4,
            },
            potential: {for (final s in Stat.values) s: 10},
          ),
        );
      }
      d
        ..place(Kind.grill, const Cell(1, 5), Dir.sw)
        ..place(Kind.counter, const Cell(5, 6), Dir.nw)
        ..place(Kind.counter, const Cell(5, 7), Dir.nw);
      for (final t in const [Cell(3, 0), Cell(5, -1), Cell(3, 2)]) {
        d
          ..place(Kind.table, t)
          ..place(Kind.chair, Cell(t.x - 1, t.y), Dir.se)
          ..place(Kind.chair, Cell(t.x + 1, t.y), Dir.nw);
      }
      return d;
    }

    test('seats in a section behind count, and the diner can open on them', () {
      final d = behind();
      expect(d.seats().length, greaterThanOrEqualTo(4));
      expect(d.report().ready, isTrue);
    });

    test('guests walk through, sit at the back and are served', () {
      final d = behind();
      final sim = DinerSim(d, seed: 2);
      var atTheBack = 0;
      while (!sim.finished && sim.ticks < 2000) {
        sim.tick();
        for (final g in sim.guests) {
          if (g.cell.y < Diner.top) atTheBack++;
        }
        for (final w in sim.workers) {
          expect(d.isInside(w.cell), isTrue, reason: 'staff stay inside');
        }
      }
      expect(atTheBack, greaterThan(0), reason: 'someone sat out there');
      expect(sim.served, greaterThan(4));
    });
  });
}

/// Loads sprites from the real files, for tests that run without a bundle.
class _Assets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = await File(key).readAsBytes();
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}
