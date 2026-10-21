// The leaderboards: best day's profit, and total coins earned.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/leaderboards.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/crowd.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/goals.dart';
import 'package:hex/diner/home_screen.dart';
import 'package:hex/diner/service.dart';
import 'package:hex/diner/settings_screen.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';

void main() {
  setUp(Storage.clearMemory);

  group('what is worth sending', () {
    test('a day is worth what was kept, and never below nothing', () {
      expect(ScorePoster.scoresFor(kept: 120, total: 900), {
        Board.bestDay: 120,
        Board.totalCoins: 900,
      });
      expect(ScorePoster.scoresFor(kept: -30, total: 50)[Board.bestDay], 0);
    });

    test('the two boards are named for what they rank', () {
      expect(Board.bestDay.title, contains('profit'));
      expect(Board.totalCoins.title, contains('coins'));
      expect(Board.bestDay.key, isNot(Board.totalCoins.key));
    });
  });

  group('the real boards', () {
    test('both have an ID, and they are different', () {
      expect(leaderboardIds[Board.bestDay], 'CgkIh6O00u4WEAIQAQ');
      expect(leaderboardIds[Board.totalCoins], 'CgkIh6O00u4WEAIQAg');
      expect(const PlayGamesBoard().any, isTrue);
      for (final b in Board.values) {
        expect(leaderboardIds[b], isNotEmpty, reason: b.name);
      }
    });
  });

  group('sending it', () {
    test('both are sent after a good day', () async {
      final b = MemoryScoreBoard();
      final sent = await ScorePoster(b).post(kept: 80, total: 400);
      expect(sent, [Board.bestDay, Board.totalCoins]);
      expect(b.best, {Board.bestDay: 80, Board.totalCoins: 400});
    });

    test('only what beats the last is sent again', () async {
      final b = MemoryScoreBoard();
      final poster = ScorePoster(b);
      await poster.post(kept: 80, total: 400);
      b.submitted.clear();
      // A worse day, but more coins in all.
      final sent = await poster.post(kept: 50, total: 450);
      expect(sent, [Board.totalCoins]);
      expect(b.submitted, [(Board.totalCoins, 450)]);
      // Nothing better at all.
      expect(await poster.post(kept: 50, total: 450), isEmpty);
    });

    test('a day that made nothing sends nothing', () async {
      final b = MemoryScoreBoard();
      expect(await ScorePoster(b).post(kept: -10, total: 0), isEmpty);
      expect(b.submitted, isEmpty);
    });

    test('nothing is sent when the player has turned it off', () async {
      Storage.postScores = false;
      final b = MemoryScoreBoard();
      expect(await ScorePoster(b).post(kept: 80, total: 400), isEmpty);
      expect(b.submitted, isEmpty);
    });

    test('nothing is sent when not signed in, and it is tried again', () async {
      final b = MemoryScoreBoard(signedIn: false);
      final poster = ScorePoster(b);
      expect(await poster.post(kept: 80, total: 400), isEmpty);
      b.signedIn = true;
      expect(await poster.post(kept: 80, total: 400), hasLength(2));
    });

    test('a board with no ID is left out', () async {
      final b = MemoryScoreBoard(configured: false);
      expect(await ScorePoster(b).post(kept: 80, total: 400), isEmpty);
      // And a Play Games board with no IDs has nothing to open.
      expect(const PlayGamesBoard({}).any, isFalse);
    });

    test('a failure is not fatal, and not counted as sent', () async {
      final poster = ScorePoster(_Failing());
      expect(await poster.post(kept: 80, total: 400), isEmpty);
      expect(Storage.sentScore(Board.bestDay.key), 0);
    });
  });

  group('the running total', () {
    test('a day adds what it took', () {
      final d = Diner.starter();
      d.goalsDone.addAll([for (final g in goals) g.id]);
      final sim = DinerSim(d, seed: 3);
      while (!sim.finished && sim.ticks < 2500) {
        sim.tick();
      }
      final r = sim.result ?? sim.finishDay();
      expect(d.totalEarned, r.earned);
      expect(r.earned, greaterThan(0));
    });

    test('it is kept in the save', () {
      final d = Diner.starter()..totalEarned = 1234;
      expect(Diner.fromJson(d.toJson()).totalEarned, 1234);
    });

    test('an older save starts from its history', () {
      final d = Diner.starter();
      d.history.addAll([
        DayLog(
          day: 1,
          kept: 10,
          served: 1,
          walkouts: 0,
          rating: 50,
          detailed: true,
          income: 100,
          ingredients: 50,
          wages: 40,
        ),
        DayLog(day: 2, kept: 30, served: 1, walkouts: 0, rating: 50),
        DayLog(day: 3, kept: -20, served: 1, walkouts: 0, rating: 50),
      ]);
      final j = d.toJson()..remove('earned');
      expect(Diner.fromJson(j).totalEarned, 130);
    });
  });

  group('on screen', () {
    Future<void> show(WidgetTester tester, Widget page) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
      });
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(HexApp(home: page));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('a finished day sends its scores', (tester) async {
      final board = MemoryScoreBoard();
      final d = Diner.starter();
      d.goalsDone.addAll([for (final g in goals) g.id]);
      await show(tester, BuildScreen(diner: d, scores: board));
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('speed-3')));
      await tester.pump();
      for (var i = 0; i < 1500; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byKey(const ValueKey('next-day')).evaluate().isNotEmpty) break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      expect(board.best[Board.totalCoins], d.totalEarned);
      expect(board.best[Board.bestDay], d.history.last.kept);
    });

    testWidgets('the title has a leaderboards button that opens them', (
      tester,
    ) async {
      final board = MemoryScoreBoard();
      await show(tester, HomeScreen(cloudFor: (_) => null, scores: board));
      await tester.tap(find.byKey(const ValueKey('leaderboards')));
      await tester.pump();
      expect(board.shown, [null]);
    });

    testWidgets('and none where there are none', (tester) async {
      await show(tester, HomeScreen(cloudFor: (_) => null));
      expect(find.byKey(const ValueKey('leaderboards')), findsNothing);
      expect(find.byKey(const ValueKey('settings')), findsOneWidget);
    });

    testWidgets('settings can stop scores, and open the boards', (
      tester,
    ) async {
      final board = MemoryScoreBoard();
      await show(tester, SettingsScreen(cloudFor: (_) => null, scores: board));
      expect(find.text('Post scores on'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('toggle-scores')));
      await tester.pump();
      expect(Storage.postScores, isFalse);
      expect(find.text('Post scores off'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('settings-leaderboards')),
      );
      await tester.tap(find.byKey(const ValueKey('settings-leaderboards')));
      await tester.pump();
      expect(board.shown, [null]);
    });
  });
}

class _Failing implements ScoreBoard {
  @override
  bool get any => true;
  @override
  Future<bool> ready(Board b) async => true;
  @override
  Future<void> submit(Board b, int score) async => throw StateError('offline');
  @override
  Future<void> show([Board? b]) async {}
}
