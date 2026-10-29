// Wallpapers and floors: some free, some bought with gems. Chairs, benches,
// tables and long tables are styled one piece at a time instead.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/city.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/diner_painter.dart';
import 'package:hex/diner/iso.dart';
import 'package:hex/diner/styles.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';

void main() {
  group('the list', () {
    test('has a free default for each, and ids that do not repeat', () {
      expect(styleById(StyleKind.wall, wallDefault)!.free, isTrue);
      expect(styleById(StyleKind.floor, floorDefault)!.free, isTrue);
      final keys = {for (final s in styles) '${s.kind.name}:${s.id}'};
      expect(keys.length, styles.length);
    });

    test('some are free and some cost gems', () {
      expect(styles.where((s) => s.free).length, greaterThan(3));
      expect(styles.where((s) => !s.free).length, greaterThan(5));
      expect(styles.every((s) => s.gems >= 0), isTrue);
    });

    test('the default has no suffix, the rest name their sprite', () {
      expect(styleById(StyleKind.wall, wallDefault)!.suffix, '');
      expect(styleById(StyleKind.floor, floorDefault)!.suffix, '');
      expect(styleById(StyleKind.floor, 'mint')!.suffix, '_s_mint');
      expect(styleById(StyleKind.wall, 'rose')!.suffix, '_s_rose');
    });

    testWidgets('every style has its pictures', (tester) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
      });
      final art = DinerArt.instance!;
      for (final s in styles) {
        if (s.kind == StyleKind.wall) {
          for (final n in const [
            'wall_a',
            'wall_a_window',
            'wall_a_board',
            'wall_b',
            'wall_b_window',
            'wall_corner',
          ]) {
            expect(
              art.sprite('$n${s.suffix}'),
              isNotNull,
              reason: '$n ${s.id}',
            );
          }
        } else if (s.kind == StyleKind.floor) {
          expect(art.sprite('floor_a${s.suffix}'), isNotNull, reason: s.id);
          expect(art.sprite('floor_b${s.suffix}'), isNotNull, reason: s.id);
        } else if (s.kind == StyleKind.chair) {
          for (final n in const ['chair_se', 'chair_sw', 'chair_nw', 'chair_ne']) {
            expect(
              art.sprite('$n${s.suffix}'),
              isNotNull,
              reason: '$n ${s.id}',
            );
          }
        } else if (s.kind == StyleKind.bench) {
          for (final n in const ['bench_se', 'bench_sw', 'bench_nw', 'bench_ne']) {
            expect(
              art.sprite('$n${s.suffix}'),
              isNotNull,
              reason: '$n ${s.id}',
            );
          }
        } else if (s.kind == StyleKind.table) {
          expect(art.sprite('table${s.suffix}'), isNotNull, reason: s.id);
        } else {
          for (final n in const ['longTable_se', 'longTable_sw']) {
            expect(
              art.sprite('$n${s.suffix}'),
              isNotNull,
              reason: '$n ${s.id}',
            );
          }
        }
      }
    });
  });

  group('owning', () {
    Diner diner() => Diner(coins: 0)..gems = 100;

    test('free ones are always usable, paid ones are not yet', () {
      final d = diner();
      expect(d.owns(styleById(StyleKind.wall, 'cream')!), isTrue);
      expect(d.owns(styleById(StyleKind.wall, 'rose')!), isFalse);
      expect(d.useStyle(styleById(StyleKind.wall, 'rose')!), isFalse);
      expect(d.wallStyle, wallDefault);
    });

    test('buying takes the gems, once, and the style is kept', () {
      final d = diner();
      final rose = styleById(StyleKind.wall, 'rose')!;
      expect(d.buyStyle(rose), PlaceResult.ok);
      expect(d.gems, 70);
      expect(d.buyStyle(rose), PlaceResult.taken);
      expect(d.gems, 70);
      expect(d.useStyle(rose), isTrue);
      expect(d.wallStyle, 'rose');
    });

    test('too few gems buys nothing', () {
      final d = Diner(coins: 0)..gems = 10;
      expect(
        d.buyStyle(styleById(StyleKind.floor, 'wood')!),
        PlaceResult.broke,
      );
      expect(d.gems, 10);
      expect(d.ownedStyles, isEmpty);
    });

    test('a wall and a floor with the same id are two styles', () {
      final d = diner();
      d.buyStyle(styleById(StyleKind.floor, 'mint')!);
      expect(d.owns(styleById(StyleKind.floor, 'mint')!), isTrue);
      expect(d.owns(styleById(StyleKind.wall, wallDefault)!), isTrue);
    });

    test('they are saved, and what is not owned is not applied', () {
      final d = diner();
      d.buyStyle(styleById(StyleKind.wall, 'brick')!);
      d.useStyle(styleById(StyleKind.wall, 'brick')!);
      d.useStyle(styleById(StyleKind.floor, 'slate')!);
      final back = Diner.fromJson(d.toJson());
      expect(back.gems, 50);
      expect(back.wallStyle, 'brick');
      expect(back.floorStyle, 'slate');
      final j = d.toJson();
      j['floor'] = 'checker';
      expect(Diner.fromJson(j).floorStyle, floorDefault, reason: 'not bought');
      j['styles'] = ['floor:checker', 'wall:nothing', 'junk'];
      final loaded = Diner.fromJson(j);
      expect(loaded.floorStyle, 'checker');
      expect(loaded.ownedStyles, {'floor:checker'});
    });

    test('a game with none saves nothing extra', () {
      final j = Diner(coins: 0).toJson();
      for (final k in [
        'gems',
        'styles',
        'wall',
        'floor',
        'chair',
        'bench',
        'table',
        'longTable',
      ]) {
        expect(j.containsKey(k), isFalse, reason: k);
      }
    });

    test('each placed chair keeps its own look, not the whole kind', () {
      final d = diner();
      final one = Placed(1, Kind.chair, const Cell(0, 0));
      final two = Placed(2, Kind.chair, const Cell(2, 0));
      final mint = styleById(StyleKind.chair, 'mint')!;
      expect(d.styleFixture(one, mint), isTrue);
      expect(one.style, 'mint');
      expect(two.style, isNull);
    });

    test('a goal-locked furniture look is unowned until the goal is met', () {
      final d = diner();
      final p = Placed(1, Kind.chair, const Cell(0, 0));
      final dinerLook = styleById(StyleKind.chair, 'diner')!;
      expect(d.owns(dinerLook), isFalse);
      expect(d.styleFixture(p, dinerLook), isFalse);
      // It is earned, not bought.
      expect(d.buyStyle(dinerLook), PlaceResult.taken);
      d.goalsDone.add('seats10');
      expect(d.owns(dinerLook), isTrue);
      expect(d.styleFixture(p, dinerLook), isTrue);
      expect(p.style, 'diner');
    });

    test('a bought furniture look is saved and restored with its piece', () {
      final d = diner()..coins = 100;
      d.place(Kind.chair, Cell(Diner.left, Diner.top));
      d.place(Kind.chair, Cell(Diner.left + 2, Diner.top));
      final mint = styleById(StyleKind.chair, 'mint')!;
      final walnut = styleById(StyleKind.chair, 'walnut')!;
      d.styleFixture(d.items[0], mint);
      d.buyStyle(walnut);
      d.styleFixture(d.items[1], walnut);
      final back = Diner.fromJson(d.toJson());
      final styled = back.items.where((p) => p.kind == Kind.chair).toList();
      expect(styled[0].style, 'mint');
      expect(styled[1].style, 'walnut');
    });
  });

  group('the room', () {
    test('the floor and walls follow the style', () {
      final d = Diner(coins: 0)..gems = 100;
      expect(groundTile(d, const Cell(3, 5)), 'floor_a');
      d.buyStyle(styleById(StyleKind.floor, 'wood')!);
      d.useStyle(styleById(StyleKind.floor, 'wood')!);
      expect(groundTile(d, const Cell(3, 5)), 'floor_a_s_wood');
    });
  });

  group('styling one piece, on screen', () {
    final board = find.byKey(const ValueKey('diner-board'));

    Future<Diner> open(WidgetTester tester) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
      });
      Storage.clearMemory();
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final d = Diner.starter()..coins = 500;
      await tester.pumpWidget(HexApp(home: BuildScreen(diner: d)));
      await tester.pump();
      return d;
    }

    BoardFit fit(WidgetTester tester) =>
        (tester.widget<CustomPaint>(board).painter! as DinerPainter).fit;

    Offset onCell(WidgetTester tester, Cell c) {
      final f = fit(tester);
      return tester.getTopLeft(board) +
          f.view.vertex(c.x + 0.5, c.y + 0.5) * f.s;
    }

    Future<void> select(WidgetTester tester, Placed p) async {
      await tester.tapAt(onCell(tester, p.at));
      await tester.pump();
    }

    Future<void> openFixtureStyle(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('style-fixture')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('the Style button is only on chairs, benches and tables', (
      tester,
    ) async {
      final d = await open(tester);
      final grill = d.items.firstWhere((p) => p.kind == Kind.grill);
      await select(tester, grill);
      expect(find.byKey(const ValueKey('style-fixture')), findsNothing);
      final chair = d.items.firstWhere((p) => p.kind == Kind.chair);
      await select(tester, chair);
      expect(find.byKey(const ValueKey('style-fixture')), findsOneWidget);
    });

    testWidgets('styling one chair leaves the other one as it was', (
      tester,
    ) async {
      final d = await open(tester);
      final chairs = d.items.where((p) => p.kind == Kind.chair).toList();
      expect(chairs.length, 2, reason: 'the starter diner seats two');
      await select(tester, chairs[0]);
      await openFixtureStyle(tester);
      expect(find.byKey(const ValueKey('fixture-style-popup')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('fstyle-mint')));
      await tester.pump();
      expect(chairs[0].style, 'mint');
      expect(chairs[1].style, isNull);
    });

    testWidgets(
      'a goal-locked look says so until the goal is met, then it is earned',
      (tester) async {
        final d = await open(tester);
        final chair = d.items.firstWhere((p) => p.kind == Kind.chair);
        await select(tester, chair);
        await openFixtureStyle(tester);
        await tester.tap(find.byKey(const ValueKey('fstyle-diner')));
        await tester.pump();
        expect(find.textContaining('Seat 10 guests at once unlocks'),
            findsOneWidget);
        expect(chair.style, isNull);
        d.goalsDone.add('seats10');
        await tester.tap(find.byKey(const ValueKey('fstyle-diner')));
        await tester.pump();
        expect(chair.style, 'diner');
      },
    );

    testWidgets('a gem-priced look asks first, and spends gems once', (
      tester,
    ) async {
      final d = await open(tester)
        ..gems = 80;
      final chair = d.items.firstWhere((p) => p.kind == Kind.chair);
      await select(tester, chair);
      await openFixtureStyle(tester);
      await tester.tap(find.byKey(const ValueKey('fstyle-walnut')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Unlock for 40 gems'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('confirm-style')));
      await tester.pump();
      expect(d.gems, 40);
      expect(chair.style, 'walnut');
    });
  });
}
