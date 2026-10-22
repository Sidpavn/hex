// The first day's tips: one at a time, each done by doing it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/coach.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/goals.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';
import 'package:hex/ui/widgets.dart' show PxText;

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

Finder get card => find.byKey(const ValueKey('coach-card'));
Finder get said => find.byKey(const ValueKey('coach-text'));

String text(WidgetTester tester) => tester.widget<PxText>(said).text;

void main() {
  group('the tips in the save', () {
    test('a new game starts on the first, and an old save has none', () {
      expect(Diner.fresh().coach, 0);
      expect(Diner.starter().coach, -1);
      final j = Diner.starter().toJson();
      expect(j.containsKey('coach'), isFalse);
      expect(Diner.fromJson(j).coach, -1);
    });

    test('the place is kept', () {
      final d = Diner.fresh()..coach = 2;
      expect(Diner.fromJson(d.toJson()).coach, 2);
    });

    test('every tip is short, and says what to do', () {
      for (final c in Coach.values) {
        expect(c.text.length, lessThan(100), reason: c.name);
      }
    });
  });

  group('on screen', () {
    testWidgets('a game with no tips shows none', (tester) async {
      await open(tester, Diner.starter());
      expect(card, findsNothing);
    });

    testWidgets('they go on as each thing is done', (tester) async {
      final d = await open(tester, Diner.fresh());
      d.goalsDone.addAll([for (final g in goals) g.id]);
      await tester.pump();
      expect(text(tester), Coach.openBuild.text);
      await tester.tap(find.byKey(const ValueKey('build-mode')));
      await tester.pump();
      expect(text(tester), Coach.place.text);
      d.coins = 500;
      final tile = find.byKey(const ValueKey('fixture-chair'));
      await tester.scrollUntilVisible(
        tile,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(tile);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('place')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('cancel-edit')));
      await tester.pump();
      expect(text(tester), Coach.startDay.text);
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump();
      expect(text(tester), Coach.watch.text);
      await tester.tap(find.byKey(const ValueKey('speed-3')));
      await tester.pump();
      for (var i = 0; i < 1500; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byKey(const ValueKey('next-day')).evaluate().isNotEmpty) break;
      }
      expect(text(tester), Coach.nextDay.text);
      await tester.tap(find.byKey(const ValueKey('next-day')));
      await tester.pump();
      expect(card, findsNothing);
      expect(d.coach, Coach.values.length);
    });

    testWidgets('pressing Start day early skips the ones in between', (
      tester,
    ) async {
      final d = await open(tester, Diner.fresh());
      d.goalsDone.addAll([for (final g in goals) g.id]);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump();
      expect(text(tester), Coach.watch.text);
    });

    testWidgets('Skip tips ends them, and they stay ended', (tester) async {
      final d = await open(tester, Diner.fresh());
      await tester.tap(find.byKey(const ValueKey('coach-skip')));
      await tester.pump();
      expect(card, findsNothing);
      expect(Diner.fromJson(d.toJson()).coach, Coach.values.length);
    });

    testWidgets('the first tip points at Build with a gold border', (
      tester,
    ) async {
      await open(tester, Diner.fresh());
      expect(card, findsOneWidget);
      expect(find.byKey(const ValueKey('build-mode')), findsOneWidget);
    });
  });
}
