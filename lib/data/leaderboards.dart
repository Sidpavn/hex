import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:games_services/games_services.dart';

import 'storage.dart';

/// The leaderboards. Each ranks one number; the player's best is kept.
enum Board {
  /// What was kept in a single day: takings less ingredients and wages.
  bestDay('best-day', 'Best day\'s profit'),

  /// Every coin taken at the tills, over all the days.
  totalCoins('total-coins', 'Total coins earned');

  const Board(this.key, this.title);

  /// A stable name, for remembering what was sent.
  final String key;

  /// What the player sees.
  final String title;
}

/// The Play Games leaderboard IDs, made in Play Console under Play Games
/// Services -> Leaderboards. A board with no ID is quietly left out.
const leaderboardIds = <Board, String>{
  Board.bestDay: 'CgkIh6O00u4WEAIQAQ',
  Board.totalCoins: 'CgkIh6O00u4WEAIQAg',
};

/// Somewhere scores can be sent and shown. Play Games, or a test's.
abstract class ScoreBoard {
  /// Whether [b] can be used: it has an ID, and the player is signed in.
  /// Never asks the player to sign in.
  Future<bool> ready(Board b);

  Future<void> submit(Board b, int score);

  /// Opens the leaderboard screen, on [b] if given, else the list.
  Future<void> show([Board? b]);

  /// Whether there is anything to open at all.
  bool get any;
}

/// Leaderboards in Google Play Games, on Android.
class PlayGamesBoard implements ScoreBoard {
  const PlayGamesBoard([this.ids = leaderboardIds]);

  final Map<Board, String> ids;

  String? _id(Board b) {
    final id = ids[b];
    return id == null || id.isEmpty ? null : id;
  }

  @override
  bool get any => Board.values.any((b) => _id(b) != null);

  @override
  Future<bool> ready(Board b) async {
    if (_id(b) == null) return false;
    try {
      return await GamesServices.isSignedIn;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> submit(Board b, int score) async {
    final id = _id(b);
    if (id == null) return;
    await GamesServices.submitScore(
      score: Score(androidLeaderboardID: id, value: score),
    );
  }

  @override
  Future<void> show([Board? b]) async {
    try {
      if (!await GamesServices.isSignedIn) await GamesServices.signIn();
      await GamesServices.showLeaderboards(
        androidLeaderboardID: b == null ? '' : (_id(b) ?? ''),
      );
    } catch (e) {
      debugPrint('Leaderboards unavailable: $e');
    }
  }
}

/// The leaderboards for this platform, if there are any: Play Games on
/// Android, nothing under `flutter test` or elsewhere.
ScoreBoard? defaultScoreBoard() =>
    !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        !Platform.environment.containsKey('FLUTTER_TEST')
    ? const PlayGamesBoard()
    : null;

/// Sends the day's scores, quietly. Only what beats what was sent before,
/// only when the player has not turned it off, and never anything that could
/// ask them to sign in.
class ScorePoster {
  ScorePoster(this.board);

  final ScoreBoard board;

  /// What a finished day is worth on each board.
  static Map<Board, int> scoresFor({required int kept, required int total}) => {
    Board.bestDay: kept < 0 ? 0 : kept,
    Board.totalCoins: total,
  };

  /// Sends whatever is a new best. Returns the boards that were sent.
  Future<List<Board>> post({required int kept, required int total}) async {
    if (!Storage.postScores) return const [];
    final sent = <Board>[];
    for (final e in scoresFor(kept: kept, total: total).entries) {
      final b = e.key;
      final score = e.value;
      if (score <= 0 || score <= Storage.sentScore(b.key)) continue;
      try {
        if (!await board.ready(b)) continue;
        await board.submit(b, score);
        Storage.sentScoreIs(b.key, score);
        sent.add(b);
      } catch (_) {
        // Try again after the next day.
      }
    }
    return sent;
  }
}

/// A board that keeps scores in memory. For tests.
class MemoryScoreBoard implements ScoreBoard {
  MemoryScoreBoard({this.signedIn = true, this.configured = true});

  bool signedIn;
  bool configured;
  final Map<Board, int> best = {};
  final List<(Board, int)> submitted = [];
  final List<Board?> shown = [];

  @override
  bool get any => configured;

  @override
  Future<bool> ready(Board b) async => configured && signedIn;

  @override
  Future<void> submit(Board b, int score) async {
    submitted.add((b, score));
    if (score > (best[b] ?? 0)) best[b] = score;
  }

  @override
  Future<void> show([Board? b]) async => shown.add(b);
}
