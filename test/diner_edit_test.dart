// Editing the layout: aim a fixture, then confirm it; nudge it a tile; undo
// what was done.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/diner_painter.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';

void main() {
  group('undo, in the model', () {
    Diner room() => Diner(coins: 1000);

    test('placing can be undone, with the coins', () {
      final d = room();
      d.place(Kind.table, const Cell(3, 5));
      expect(d.coins, 970);
      expect(d.canUndo, isTrue);
      expect(d.undoLabel, 'Placed table');
      expect(d.undo(), 'Placed table');
      expect(d.objectAt(const Cell(3, 5)), isNull);
      expect(d.coins, 1000);
      expect(d.canUndo, isFalse);
    });

    test('selling can be undone: it comes back, and the refund goes', () {
      final d = room();
      d.place(Kind.table, const Cell(3, 5));
      final t = d.objectAt(const Cell(3, 5))!;
      final id = t.id;
      d.sell(t);
      expect(d.coins, 985);
      expect(d.undo(), 'Sold table');
      expect(d.objectAt(const Cell(3, 5))?.id, id);
      expect(d.coins, 970);
    });

    test('moving and turning can be undone', () {
      final d = room();
      d.place(Kind.grill, const Cell(1, 3), Dir.sw);
      final g = d.items.single;
      d.moveTo(g, const Cell(2, 3));
      d.rotate(d.items.single);
      expect(d.items.single.at, const Cell(2, 3));
      expect(d.items.single.facing, Dir.sw.cw);
      expect(d.undo(), 'Turned grill');
      expect(d.items.single.facing, Dir.sw);
      expect(d.undo(), 'Moved grill');
      expect(d.items.single.at, const Cell(1, 3));
    });

    test('undo goes back one step at a time, newest first', () {
      final d = room()..progress.level = 5;
      d.place(Kind.table, const Cell(3, 5));
      d.place(Kind.plant, const Cell(5, 5));
      d.place(Kind.jukebox, const Cell(2, 6));
      expect(d.items.length, 3);
      d.undo();
      d.undo();
      expect(d.items.single.kind, Kind.table);
    });

    test('a refused change leaves nothing to undo', () {
      final d = room();
      expect(d.place(Kind.plant, const Cell(20, 20)), PlaceResult.outside);
      expect(d.canUndo, isFalse);
      d.place(Kind.table, const Cell(3, 5));
      d.clearUndo();
      expect(d.place(Kind.table, const Cell(3, 5)), PlaceResult.taken);
      expect(d.canUndo, isFalse);
    });

    test('it remembers twenty changes and no more', () {
      final d = Diner(coins: 100000);
      d.place(Kind.table, const Cell(3, 5));
      final t = d.items.single;
      for (var i = 0; i < 30; i++) {
        d.rotate(t);
      }
      var n = 0;
      while (d.undo() != null) {
        n++;
      }
      expect(n, Diner.undoLimit);
    });

    test('buying more of the plot clears it: that cannot be taken back', () {
      final d = Diner(coins: 100000, progress: Progress(level: 9));
      d.place(Kind.table, const Cell(3, 5));
      expect(d.canUndo, isTrue);
      d.unlock(1);
      expect(d.canUndo, isFalse);
    });

    test(
      'undoing keeps every fixture\'s id, so staff and saves still match',
      () {
        final d = room();
        d.place(Kind.table, const Cell(3, 5));
        d.place(Kind.plant, const Cell(5, 5));
        final ids = d.items.map((p) => p.id).toList();
        d.sell(d.items.first);
        d.undo();
        expect(d.items.map((p) => p.id).toList(), ids);
      },
    );

    test('an undone layout is saved like any other', () {
      final d = room();
      d.place(Kind.table, const Cell(3, 5));
      d.place(Kind.plant, const Cell(5, 5));
      d.undo();
      final back = Diner.fromJson(d.toJson());
      expect(back.items.length, 1);
      expect(back.coins, d.coins);
    });
  });

  group('groups, in the model', () {
    /// A table with a chair either side, and a plant, in a wide room.
    (Diner, List<Placed>) set() {
      final d = Diner(coins: 5000, owned: {0, 1});
      d.place(Kind.table, const Cell(5, 5));
      d.place(Kind.chair, const Cell(4, 5), Dir.se);
      d.place(Kind.chair, const Cell(6, 5), Dir.nw);
      d.clearUndo();
      return (d, List.of(d.items));
    }

    test('a quarter turn takes a step south-west to north-west', () {
      const m = GroupMove(turns: 1, pivot: Cell(3, 3));
      expect(m.cell(const Cell(3, 4)), const Cell(2, 3));
      expect(m.cell(const Cell(2, 3)), const Cell(3, 2));
      expect(m.cell(const Cell(3, 3)), const Cell(3, 3), reason: 'the pivot');
      expect(m.face(Dir.sw), Dir.nw);
      expect(m.face(Dir.nw), Dir.ne);
    });

    test('four quarter turns bring everything back', () {
      const m = GroupMove(turns: 4, pivot: Cell(5, 5));
      for (final c in const [Cell(1, 2), Cell(7, 3), Cell(5, 5)]) {
        expect(m.cell(c), c);
      }
      expect(const GroupMove(turns: 4).face(Dir.sw), Dir.sw);
    });

    test('two turns are a half turn about the pivot', () {
      const m = GroupMove(turns: 2, pivot: Cell(5, 5));
      expect(m.cell(const Cell(7, 4)), const Cell(3, 6));
    });

    test('a turn then a slide puts the pivot where it is slid to', () {
      const m = GroupMove(turns: 1, dx: 2, dy: -1, pivot: Cell(5, 5));
      expect(m.cell(const Cell(5, 5)), const Cell(7, 4));
    });

    test('turning keeps a fixture the size it was, however it lies', () {
      final d = Diner(coins: 5000, progress: Progress(level: 5));
      d.place(Kind.bench, const Cell(4, 4), Dir.sw);
      final bench = d.items.single;
      for (var turns = 0; turns < 4; turns++) {
        final mv = d.movedBy([
          bench,
        ], GroupMove(turns: turns, pivot: const Cell(4, 4))).single;
        final probe = Placed(0, Kind.bench, mv.at, mv.facing);
        expect(
          probe.cells.toSet(),
          mv.cells.toSet(),
          reason: 'turns $turns: footprint and cells agree',
        );
        expect(mv.cells.length, 2);
      }
    });

    test('the middle of a group is the middle of its tiles', () {
      final (d, group) = set();
      expect(d.groupPivot(group), const Cell(5, 5));
      expect(d.groupPivot(const []), const Cell(0, 0));
    });

    test('a group moves together, and keeps its shape', () {
      final (d, group) = set();
      final coins = d.coins;
      expect(d.moveGroup(group, const GroupMove(dx: 2, dy: 1)), PlaceResult.ok);
      expect(d.objectAt(const Cell(7, 6))?.kind, Kind.table);
      expect(d.objectAt(const Cell(6, 6))?.kind, Kind.chair);
      expect(d.objectAt(const Cell(8, 6))?.kind, Kind.chair);
      expect(d.coins, coins);
    });

    test('a moved group costs nothing, and one undo puts it all back', () {
      final (d, group) = set();
      final coins = d.coins;
      d.moveGroup(group, const GroupMove(dx: 2));
      expect(d.coins, coins);
      expect(d.undoLabel, 'Moved 3 fixtures');
      d.undo();
      expect(d.objectAt(const Cell(5, 5))?.kind, Kind.table);
      expect(d.objectAt(const Cell(4, 5))?.kind, Kind.chair);
      expect(d.canUndo, isFalse, reason: 'it was one step');
    });

    test('a table with its chairs turns about its middle and still seats', () {
      final (d, group) = set();
      expect(d.seats().length, 2);
      expect(
        d.moveGroup(group, const GroupMove(turns: 1, pivot: Cell(5, 5))),
        PlaceResult.ok,
      );
      expect(d.seats().length, 2, reason: 'the chairs still face the table');
      expect(d.objectAt(const Cell(5, 4))?.kind, Kind.chair);
      expect(d.objectAt(const Cell(5, 6))?.kind, Kind.chair);
      expect(d.objectAt(const Cell(5, 5))?.kind, Kind.table);
    });

    test('a group cannot go outside the room', () {
      final (d, group) = set();
      expect(d.checkGroup(group, const GroupMove(dx: 20)), PlaceResult.outside);
      expect(
        d.checkGroup(group, const GroupMove(dy: -20)),
        PlaceResult.outside,
      );
    });

    test('a group cannot land on something else, but may on where it was', () {
      final (d, group) = set();
      d.place(Kind.plant, const Cell(8, 5));
      expect(d.checkGroup(group, const GroupMove(dx: 2)), PlaceResult.taken);
      // One step along overlaps its own old tiles, which is fine.
      expect(d.checkGroup(group, const GroupMove(dx: 1)), PlaceResult.ok);
    });

    test('a group cannot go on the door, or cut off part of the room', () {
      final (d, group) = set();
      expect(
        d.checkGroup(group, const GroupMove(dx: -2, dy: 2)),
        PlaceResult.entrance,
      );
      // A wall of counters across the room, with one gap at the end.
      final wall = Diner(coins: 100000, owned: {0, 1});
      for (var x = 1; x <= 9; x++) {
        expect(wall.place(Kind.counter, Cell(x, 5)), PlaceResult.ok);
      }
      wall.place(Kind.plant, const Cell(4, 7));
      final plant = wall.items.last;
      // Closing the gap with it strands the room behind.
      expect(
        wall.checkGroup([plant], const GroupMove(dx: 6, dy: -2)),
        PlaceResult.blocksWay,
      );
      // Moving it somewhere harmless is fine.
      expect(wall.checkGroup([plant], const GroupMove(dx: 1)), PlaceResult.ok);
    });

    test('a window cannot be part of a group', () {
      final d = Diner(coins: 5000, owned: {0, 1}, progress: Progress(level: 5));
      d.place(Kind.window, Cell(d.right, 4));
      d.place(Kind.plant, const Cell(4, 4));
      expect(d.checkGroup(d.items, const GroupMove(dy: 1)), PlaceResult.wall);
    });

    test('copying pays for every piece and leaves the originals', () {
      final (d, group) = set();
      final coins = d.coins;
      final before = d.items.length;
      final made = d.copyGroup(group, const GroupMove(dy: 2));
      expect(made.length, 3);
      expect(d.items.length, before + 3);
      expect(d.coins, coins - d.groupCost(group));
      expect(
        made
            .map((p) => p.id)
            .toSet()
            .intersection(group.map((p) => p.id).toSet()),
        isEmpty,
      );
      expect(d.objectAt(const Cell(5, 5))?.kind, Kind.table, reason: 'kept');
      expect(d.objectAt(const Cell(5, 7))?.kind, Kind.table);
      expect(d.seats().length, 4);
    });

    test('a copy cannot overlap what it copies, or be unaffordable', () {
      final (d, group) = set();
      expect(
        d.checkGroup(group, const GroupMove(dx: 1), copy: true),
        PlaceResult.taken,
      );
      d.coins = 10;
      expect(
        d.checkGroup(group, const GroupMove(dy: 2), copy: true),
        PlaceResult.broke,
      );
      expect(d.copyGroup(group, const GroupMove(dy: 2)), isEmpty);
      expect(d.items.length, 3);
      expect(d.coins, 10);
    });

    test('a copy is one undo, and the money comes back', () {
      final (d, group) = set();
      final coins = d.coins;
      d.copyGroup(group, const GroupMove(dy: 2));
      expect(d.undoLabel, 'Copied 3 fixtures');
      d.undo();
      expect(d.items.length, 3);
      expect(d.coins, coins);
    });

    test('selling a group pays the refunds, and one undo brings it back', () {
      final (d, group) = set();
      final coins = d.coins;
      d.sellGroup(group);
      expect(d.items, isEmpty);
      expect(d.coins, coins + d.groupRefund(group));
      expect(d.groupRefund(group), 15 + 5 + 5);
      d.undo();
      expect(d.items.length, 3);
      expect(d.coins, coins);
    });

    test('a group of one reads as that fixture, not "1 fixtures"', () {
      final (d, group) = set();
      d.moveGroup([group.first], const GroupMove(dy: 1));
      expect(d.undoLabel, 'Moved table');
    });

    test('rugs go in a group and move with it, under everything', () {
      final d = Diner(coins: 5000);
      d.place(Kind.rug, const Cell(4, 5));
      d.place(Kind.table, const Cell(4, 5));
      final group = List.of(d.items);
      expect(d.moveGroup(group, const GroupMove(dx: 1)), PlaceResult.ok);
      expect(d.floorAt(const Cell(5, 5))?.kind, Kind.rug);
      expect(d.objectAt(const Cell(5, 5))?.kind, Kind.table);
    });
  });

  group('on screen', () {
    final board = find.byKey(const ValueKey('diner-board'));

    Future<Diner> open(WidgetTester tester, {Diner? diner}) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
      });
      Storage.clearMemory();
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final d = diner ?? (Diner.starter()..coins = 500);
      await tester.pumpWidget(HexApp(home: BuildScreen(diner: d)));
      await tester.pump();
      return d;
    }

    DinerPainter painter(WidgetTester tester) =>
        tester.widget<CustomPaint>(board).painter! as DinerPainter;

    Offset onCell(WidgetTester tester, Cell c) {
      final f = painter(tester).fit;
      return tester.getTopLeft(board) +
          f.view.vertex(c.x + 0.5, c.y + 0.5) * f.s;
    }

    Future<void> pick(WidgetTester tester, String kind) async {
      final tile = find.byKey(ValueKey('fixture-$kind'));
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pump();
    }

    testWidgets('picking a fixture puts a ghost on a free spot, in view', (
      tester,
    ) async {
      final d = await open(tester);
      await pick(tester, 'table');
      final at = painter(tester).hover;
      expect(at, isNotNull);
      expect(d.check(Kind.table, at!), PlaceResult.ok);
      expect(d.items.length, 9, reason: 'nothing placed yet');
    });

    testWidgets('tapping or dragging the board never places anything', (
      tester,
    ) async {
      final d = await open(tester);
      final before = d.items.length;
      await pick(tester, 'table');
      await tester.tapAt(onCell(tester, const Cell(4, 6)));
      await tester.pump();
      final g = await tester.startGesture(onCell(tester, const Cell(5, 6)));
      await g.moveTo(onCell(tester, const Cell(6, 4)));
      await g.up();
      await tester.pump();
      expect(d.items.length, before);
      expect(d.coins, 500);
      expect(painter(tester).hover, const Cell(6, 4), reason: 'ghost stayed');
    });

    testWidgets('Place puts it down, and the ghost is still there for more', (
      tester,
    ) async {
      final d = await open(tester);
      await pick(tester, 'table');
      await tester.tapAt(onCell(tester, const Cell(4, 6)));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('place')));
      await tester.pump();
      expect(d.objectAt(const Cell(4, 6))?.kind, Kind.table);
      expect(d.coins, 470);
      expect(painter(tester).placing, Kind.table, reason: 'still placing');
      expect(painter(tester).hover, const Cell(4, 6));
    });

    testWidgets('a spot that is taken cannot be placed on, and says why', (
      tester,
    ) async {
      final d = await open(tester);
      await pick(tester, 'table');
      await tester.tapAt(onCell(tester, const Cell(4, 6)));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('place')));
      await tester.pump();
      final items = d.items.length;
      // Along and back onto the same spot: refused, and the button is dead.
      await tester.tap(find.byKey(const ValueKey('nudge-se')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('nudge-nw')));
      await tester.pump();
      expect(find.text('That spot is taken'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('place')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(d.items.length, items);
      expect(d.coins, 470);
    });

    testWidgets('the arrows move the ghost one tile along the grid', (
      tester,
    ) async {
      await open(tester);
      await pick(tester, 'table');
      await tester.tapAt(onCell(tester, const Cell(5, 5)));
      await tester.pump();
      const moves = {
        'se': Cell(6, 5),
        'sw': Cell(6, 6),
        'nw': Cell(5, 6),
        'ne': Cell(5, 5),
      };
      for (final e in moves.entries) {
        await tester.tap(find.byKey(ValueKey('nudge-${e.key}')));
        await tester.pump();
        expect(painter(tester).hover, e.value, reason: e.key);
      }
    });

    testWidgets('nudging along and placing makes a row, tap by tap', (
      tester,
    ) async {
      final d = await open(tester);
      await pick(tester, 'plant');
      await tester.tapAt(onCell(tester, const Cell(4, 7)));
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const ValueKey('place')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('nudge-se')));
        await tester.pump();
      }
      final plants = d.items.where((p) => p.kind == Kind.plant && p.at.y == 7);
      expect(plants.map((p) => p.at.x).toSet(), {4, 5, 6});
    });

    testWidgets('Done puts the fixture away without placing it', (
      tester,
    ) async {
      final d = await open(tester);
      final before = d.items.length;
      await pick(tester, 'table');
      await tester.tap(find.byKey(const ValueKey('cancel-edit')));
      await tester.pump();
      expect(painter(tester).placing, isNull);
      expect(d.items.length, before);
      expect(d.coins, 500);
    });

    testWidgets('turning the ghost can make a spot valid or not', (
      tester,
    ) async {
      final d = await open(tester);
      await pick(tester, 'chair');
      await tester.tapAt(onCell(tester, const Cell(4, 6)));
      await tester.pump();
      final first = painter(tester).placeOk;
      await tester.tap(find.byKey(const ValueKey('rotate')));
      await tester.pump();
      expect(painter(tester).facing, isNot(Dir.sw));
      expect(painter(tester).placeOk, isNotNull);
      expect(first, isNotNull);
      expect(d.coins, 500);
    });

    testWidgets('the ghost sits on the spot it will be placed on', (
      tester,
    ) async {
      await open(tester);
      await pick(tester, 'table');
      await tester.tapAt(onCell(tester, const Cell(4, 6)));
      await tester.pump();
      expect(painter(tester).placeOk, isTrue);
      await tester.tapAt(onCell(tester, const Cell(1, 3))); // the grill
      await tester.pump();
      expect(painter(tester).placeOk, isFalse);
    });

    testWidgets('Undo takes back a placement, and says what it undid', (
      tester,
    ) async {
      final d = await open(tester);
      expect(find.byKey(const ValueKey('undo')), findsOneWidget);
      await pick(tester, 'table');
      await tester.tapAt(onCell(tester, const Cell(4, 6)));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('place')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('cancel-edit')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('undo')));
      await tester.pump();
      expect(d.objectAt(const Cell(4, 6)), isNull);
      expect(d.coins, 500);
      expect(find.text('Undid: placed table'), findsOneWidget);
    });

    testWidgets('Undo is there to press only when there is something to undo', (
      tester,
    ) async {
      final d = await open(tester);
      expect(d.canUndo, isFalse);
      await tester.tap(find.byKey(const ValueKey('undo')), warnIfMissed: false);
      await tester.pump();
      expect(find.textContaining('Undid'), findsNothing);
    });

    testWidgets('a sale can be undone from the idle panel', (tester) async {
      final d = await open(tester);
      final grill = d.items.firstWhere((p) => p.kind == Kind.grill);
      await tester.tapAt(onCell(tester, grill.at));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('sell')));
      await tester.pump();
      expect(d.items.any((p) => p.kind == Kind.grill), isFalse);
      await tester.tap(find.byKey(const ValueKey('undo')));
      await tester.pump();
      expect(d.items.any((p) => p.kind == Kind.grill), isTrue);
    });

    // ------------------------------------------------ several at once

    /// A table with chairs and a couple of plants, in the front of a roomy
    /// restaurant, ready to be chosen.
    Diner furnished() {
      final d = Diner(coins: 5000, owned: {0, 1});
      d.progress.level = 5;
      d.place(Kind.table, const Cell(5, 5));
      d.place(Kind.chair, const Cell(4, 5), Dir.se);
      d.place(Kind.chair, const Cell(6, 5), Dir.nw);
      d.place(Kind.plant, const Cell(8, 4));
      d.place(Kind.plant, const Cell(9, 4));
      d.clearUndo();
      return d;
    }

    Future<void> selectFirst(WidgetTester tester, Cell at) async {
      await tester.tapAt(onCell(tester, at));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('select-more')));
      await tester.pump();
    }

    Future<void> add(WidgetTester tester, Cell at) async {
      await tester.tapAt(onCell(tester, at));
      await tester.pump();
    }

    testWidgets('Select starts a group with the fixture already chosen', (
      tester,
    ) async {
      await open(tester, diner: furnished());
      await selectFirst(tester, const Cell(5, 5));
      final p = painter(tester);
      expect(p.group.length, 1);
      expect(p.group.single.kind, Kind.table);
      expect(
        find.text('1 chosen. Tap fixtures to add or remove them.'),
        findsOneWidget,
      );
      // The shelf is put away while choosing.
      expect(find.byKey(const ValueKey('fixture-table')), findsNothing);
      expect(find.byKey(const ValueKey('group-move')), findsOneWidget);
    });

    testWidgets('tapping fixtures adds them, and again takes them out', (
      tester,
    ) async {
      await open(tester, diner: furnished());
      await selectFirst(tester, const Cell(5, 5));
      await add(tester, const Cell(4, 5));
      await add(tester, const Cell(6, 5));
      expect(painter(tester).group.length, 3);
      await add(tester, const Cell(4, 5));
      expect(painter(tester).group.length, 2);
      await add(tester, const Cell(1, 6)); // bare floor: nothing happens
      expect(painter(tester).group.length, 2);
    });

    testWidgets('Same kind adds every fixture of the kinds chosen', (
      tester,
    ) async {
      final d = await open(tester, diner: furnished());
      await selectFirst(tester, const Cell(8, 4));
      await tester.tap(find.byKey(const ValueKey('group-same')));
      await tester.pump();
      expect(painter(tester).group.length, 2);
      expect(painter(tester).group.every((p) => p.kind == Kind.plant), isTrue);
      expect(d.items.where((p) => p.kind == Kind.plant).length, 2);
    });

    testWidgets(
      'a group moves together with the ghost, and Put down moves it',
      (tester) async {
        final d = await open(tester, diner: furnished());
        await selectFirst(tester, const Cell(5, 5));
        await add(tester, const Cell(4, 5));
        await add(tester, const Cell(6, 5));
        await tester.tap(find.byKey(const ValueKey('group-move')));
        await tester.pump();
        // The ghost is the whole group, where it already is, to begin with.
        expect(painter(tester).ghostGroup.length, 3);
        expect(find.text('Put down'), findsOneWidget);
        // Nudge it along: nothing moves until Put down.
        await tester.tap(find.byKey(const ValueKey('nudge-sw')));
        await tester.pump();
        expect(d.objectAt(const Cell(5, 5))?.kind, Kind.table);
        expect(painter(tester).ghostGroup.map((g) => g.at).toSet(), {
          const Cell(5, 6),
          const Cell(4, 6),
          const Cell(6, 6),
        });
        await tester.tap(find.byKey(const ValueKey('place')));
        await tester.pump();
        expect(d.objectAt(const Cell(5, 6))?.kind, Kind.table);
        expect(d.objectAt(const Cell(5, 5)), isNull);
        // Back to choosing, with the same three still chosen.
        expect(painter(tester).group.length, 3);
        expect(painter(tester).ghostGroup, isEmpty);
      },
    );

    testWidgets('a group that does not fit shows red and cannot be put down', (
      tester,
    ) async {
      final d = await open(tester, diner: furnished());
      await selectFirst(tester, const Cell(5, 5));
      await add(tester, const Cell(4, 5));
      await add(tester, const Cell(6, 5));
      await tester.tap(find.byKey(const ValueKey('group-move')));
      await tester.pump();
      // Slide it into the plants.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const ValueKey('nudge-se')));
        await tester.pump();
      }
      for (var i = 0; i < 1; i++) {
        await tester.tap(find.byKey(const ValueKey('nudge-ne')));
        await tester.pump();
      }
      expect(painter(tester).placeOk, isFalse);
      expect(find.text('That spot is taken'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('place')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(d.objectAt(const Cell(5, 5))?.kind, Kind.table, reason: 'unmoved');
    });

    testWidgets('Turn turns the whole group about its middle, in place', (
      tester,
    ) async {
      final d = await open(tester, diner: furnished());
      await selectFirst(tester, const Cell(5, 5));
      await add(tester, const Cell(4, 5));
      await add(tester, const Cell(6, 5));
      await tester.tap(find.byKey(const ValueKey('group-turn')));
      await tester.pump();
      expect(d.objectAt(const Cell(5, 5))?.kind, Kind.table);
      expect(d.objectAt(const Cell(5, 4))?.kind, Kind.chair);
      expect(d.objectAt(const Cell(5, 6))?.kind, Kind.chair);
      expect(d.seats().length, 2, reason: 'still seats two');
    });

    testWidgets('Rotate while aiming a group turns its ghost', (tester) async {
      await open(tester, diner: furnished());
      await selectFirst(tester, const Cell(5, 5));
      await add(tester, const Cell(4, 5));
      await add(tester, const Cell(6, 5));
      await tester.tap(find.byKey(const ValueKey('group-move')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rotate')));
      await tester.pump();
      expect(painter(tester).ghostGroup.map((g) => g.at).toSet(), {
        const Cell(5, 5),
        const Cell(5, 4),
        const Cell(5, 6),
      });
    });

    testWidgets('Copy shows a ghost of the group, and Place pays for it', (
      tester,
    ) async {
      final d = await open(tester, diner: furnished());
      await selectFirst(tester, const Cell(5, 5));
      await add(tester, const Cell(4, 5));
      await add(tester, const Cell(6, 5));
      final coins = d.coins;
      final before = d.items.length;
      await tester.tap(find.byKey(const ValueKey('group-copy')));
      await tester.pump();
      expect(painter(tester).ghostGroup.length, 3);
      expect(
        painter(tester).placeOk,
        isTrue,
        reason: 'it starts on free floor',
      );
      expect(d.groupCost(painter(tester).group), 50);
      await tester.tap(find.byKey(const ValueKey('place')));
      await tester.pump();
      expect(d.items.length, before + 3);
      expect(d.coins, coins - 50);
      // The originals are still there, and another copy can follow.
      expect(d.objectAt(const Cell(5, 5))?.kind, Kind.table);
      expect(painter(tester).ghostGroup.length, 3);
      expect(painter(tester).placeOk, isFalse, reason: 'on the copy just made');
    });

    testWidgets('Sell sells them all and says what was paid', (tester) async {
      final d = await open(tester, diner: furnished());
      await selectFirst(tester, const Cell(8, 4));
      await tester.tap(find.byKey(const ValueKey('group-same')));
      await tester.pump();
      final coins = d.coins;
      await tester.tap(find.byKey(const ValueKey('group-sell')));
      await tester.pump();
      expect(d.items.where((p) => p.kind == Kind.plant), isEmpty);
      expect(d.coins, coins + 2 * 7);
      expect(find.text('Sold 2 for 14'), findsOneWidget);
      expect(painter(tester).group, isEmpty);
    });

    testWidgets('and one Undo takes a group change back whole', (tester) async {
      final d = await open(tester, diner: furnished());
      await selectFirst(tester, const Cell(8, 4));
      await tester.tap(find.byKey(const ValueKey('group-same')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('group-sell')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('undo')));
      await tester.pump();
      expect(d.items.where((p) => p.kind == Kind.plant).length, 2);
    });

    testWidgets('Done leaves choosing, and nothing stays chosen', (
      tester,
    ) async {
      await open(tester, diner: furnished());
      await selectFirst(tester, const Cell(5, 5));
      await tester.tap(find.byKey(const ValueKey('group-done')));
      await tester.pump();
      expect(painter(tester).group, isEmpty);
      expect(find.byKey(const ValueKey('fixture-table')), findsOneWidget);
    });

    testWidgets('Done while aiming goes back to choosing, group kept', (
      tester,
    ) async {
      await open(tester, diner: furnished());
      await selectFirst(tester, const Cell(5, 5));
      await tester.tap(find.byKey(const ValueKey('group-move')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('cancel-edit')));
      await tester.pump();
      expect(painter(tester).group.length, 1);
      expect(painter(tester).ghostGroup, isEmpty);
      expect(find.byKey(const ValueKey('group-move')), findsOneWidget);
    });

    testWidgets('the window cannot be chosen into a group', (tester) async {
      final d = furnished()..place(Kind.window, Cell(10, 4));
      await open(tester, diner: d);
      await selectFirst(tester, const Cell(5, 5));
      await add(tester, const Cell(10, 4));
      expect(painter(tester).group.length, 1);
      expect(find.text('The window is moved on its own'), findsOneWidget);
    });

    testWidgets('nothing chosen means nothing to do', (tester) async {
      await open(tester, diner: furnished());
      await selectFirst(tester, const Cell(5, 5));
      await add(tester, const Cell(5, 5)); // take it out again
      expect(painter(tester).group, isEmpty);
      expect(
        find.text('Nothing chosen. Tap a fixture to add it.'),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('group-move')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(painter(tester).ghostGroup, isEmpty);
    });

    testWidgets('starting the day clears the undo list', (tester) async {
      final d = await open(tester);
      d.place(Kind.plant, const Cell(4, 7));
      expect(d.canUndo, isTrue);
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump();
      expect(d.canUndo, isFalse);
    });
  });
}
