import 'dart:convert';

import 'package:hive_ce_flutter/hive_flutter.dart';

import '../diner/diner.dart';
import 'cloud_save.dart';

/// A reward given for claiming a daily streak bonus.
class StreakReward {
  const StreakReward({required this.coins, required this.gems});
  final int coins;
  final int gems;
  bool get isEmpty => coins == 0 && gems == 0;
}

const List<StreakReward> _streakRewards = [
  StreakReward(coins: 25, gems: 0),
  StreakReward(coins: 50, gems: 0),
  StreakReward(coins: 75, gems: 1),
  StreakReward(coins: 100, gems: 0),
  StreakReward(coins: 125, gems: 0),
  StreakReward(coins: 150, gems: 0),
  StreakReward(coins: 200, gems: 3),
];

/// Persistent save: the diner.
///
/// Everything lives in one Hive box as plain values (no adapters). If Hive was
/// never initialised (tests), a throwaway in-memory map is used instead.
class Storage {
  Storage._();

  static Box<dynamic>? _box;
  static final Map<String, dynamic> _mem = {};

  /// Opens the box. Pass [path] to use a plain directory (tests, desktop).
  static Future<void> init({String? path}) async {
    if (path == null) {
      await Hive.initFlutter();
    } else {
      Hive.init(path);
    }
    _box = await Hive.openBox<dynamic>('hex');
  }

  static Future<void> close() async {
    await _box?.close();
    _box = null;
  }

  static void clearMemory() => _mem.clear();

  static dynamic _get(String key) => _box != null ? _box!.get(key) : _mem[key];

  static void _put(String key, dynamic value) {
    if (_box != null) {
      _box!.put(key, value);
    } else {
      _mem[key] = value;
    }
  }

  // ───────────────────────── sound settings ─────────────────────────

  /// Whether sound effects play. On unless the player turned them off.
  static bool get effectsOn => _get('sfx') != false;
  static set effectsOn(bool on) => _put('sfx', on);

  /// Whether music plays. On unless the player turned it off.
  static bool get musicOn => _get('music') != false;
  static set musicOn(bool on) => _put('music', on);

  /// How loud effects and music are, 0 to 2: low, medium (the default), high.
  static int get effectsLevel => _level('sfx_level');
  static set effectsLevel(int n) => _put('sfx_level', n.clamp(0, 2));
  static int get musicLevel => _level('music_level');
  static set musicLevel(int n) => _put('music_level', n.clamp(0, 2));

  static int _level(String key) {
    final n = _get(key);
    return n is int ? n.clamp(0, 2) : 1;
  }

  /// Whether the save is sent to the cloud by itself, after each day and on
  /// the way out. On unless the player turned it off.
  static bool get autoBackup => _get('auto_backup') != false;
  static set autoBackup(bool on) => _put('auto_backup', on);

  /// Whether scores are sent to the leaderboards. On unless turned off.
  static bool get postScores => _get('post_scores') != false;
  static set postScores(bool on) => _put('post_scores', on);

  // ───────────────────────── daily streak ─────────────────────────

  static int _dayNum() {
    final epoch = DateTime(2024, 1, 1);
    return DateTime.now().difference(epoch).inDays;
  }

  /// The calendar day (days since 2024-01-01) when the last streak bonus was
  /// claimed. Zero means never.
  static int get _lastStreakDay => (_get('streak_day') as int?) ?? 0;
  static set _lastStreakDay(int d) => _put('streak_day', d);

  /// The current streak length, in consecutive calendar days.
  static int get streakCount => (_get('streak_count') as int?) ?? 0;
  static set streakCount(int n) => _put('streak_count', n < 0 ? 0 : n);

  /// Whether a streak bonus is ready to claim (a new calendar day has started
  /// since the last claim).
  static bool get streakReady => _lastStreakDay < _dayNum();

  /// Which day of the 7-day cycle the next claim will land on (1-based, 1–7).
  static int get streakDayInCycle {
    if (!streakReady) return ((streakCount - 1) % 7) + 1;
    final next = (_lastStreakDay == _dayNum() - 1) ? streakCount + 1 : 1;
    return ((next - 1) % 7) + 1;
  }

  /// The reward that will be given on the next claim.
  static StreakReward get nextClaimReward => _streakRewards[streakDayInCycle - 1];

  /// Claims the streak bonus. Returns the reward; coins and gems are both zero
  /// if already claimed today.
  static StreakReward claimStreak() {
    final today = _dayNum();
    if (_lastStreakDay >= today) return const StreakReward(coins: 0, gems: 0);
    final streak = (_lastStreakDay == today - 1) ? streakCount + 1 : 1;
    streakCount = streak;
    _lastStreakDay = today;
    return _streakRewards[(streak - 1) % 7];
  }

  /// The best score already sent for a leaderboard, by name, so a lower one
  /// is not sent again.
  static int sentScore(String board) {
    final n = _get('score_$board');
    return n is int ? n : 0;
  }

  static void sentScoreIs(String board, int n) => _put('score_$board', n);

  // ───────────────────────── diner save ─────────────────────────

  /// How many games can be kept side by side.
  /// Gems bought but not yet put in a save: the purchase went through while
  /// no game was open, or before it could be written.
  static int get pendingGems => (_get('pending_gems') as int?) ?? 0;
  static set pendingGems(int n) => _put('pending_gems', n < 0 ? 0 : n);

  /// The purchases already turned into gems, by order id, so the same one is
  /// never paid twice when the store tells us again.
  static Set<String> get creditedOrders => {
    for (final o in (_get('gem_orders') as List? ?? const [])) '$o',
  };
  static set creditedOrders(Set<String> ids) =>
      _put('gem_orders', ids.toList()..sort());

  static const slots = 3;

  /// Which game is being played, 1 to [slots]. The first uses the key every
  /// earlier version saved under, so nobody loses their game.
  static int get slot {
    final n = _get('slot');
    return n is int && n >= 1 && n <= slots ? n : 1;
  }

  /// Plays game [n] from now on.
  static void useSlot(int n) => _put('slot', n.clamp(1, slots));

  static String _key(int n) => n == 1 ? 'diner' : 'diner$n';

  /// The diner saved in game [n], or null if empty (or it can't be read).
  static Diner? slotDiner(int n) {
    final raw = _get(_key(n));
    if (raw is! String) return null;
    try {
      return Diner.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      return null;
    }
  }

  /// What game [n] says about itself, without keeping the whole diner.
  static SaveInfo? slotInfo(int n) {
    final d = slotDiner(n);
    return d == null ? null : SaveInfo.of(d);
  }

  /// Keeps [d] as game [n], stamped with the time.
  static void saveSlot(int n, Diner d) {
    d.savedAt = DateTime.now().millisecondsSinceEpoch;
    _put(_key(n), jsonEncode(d.toJson()));
  }

  /// Empties game [n].
  static void clearSlot(int n) => _put(_key(n), null);

  /// The saved diner of the game being played, or null if there is none.
  static Diner? get diner => slotDiner(slot);

  static void saveDiner(Diner d) => saveSlot(slot, d);

  /// Forgets the saved diner, so the next one starts from scratch.
  static void clearDiner() => clearSlot(slot);

  /// Wipes all saved progress.
  static Future<void> reset() async {
    _mem.clear();
    await _box?.clear();
  }
}
