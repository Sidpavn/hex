import 'dart:convert';

import 'package:hive_ce_flutter/hive_flutter.dart';

import '../game/campaign.dart';
import '../game/config.dart';
import '../game/models.dart';
import '../world/world_state.dart';

/// What a finished game changed in the player's profile.
class GameResult {
  const GameResult({
    this.stars = 0,
    this.newCards = const [],
    this.newHeroes = const [],
    this.newBest = false,
    this.newModes = const [],
  });

  final int stars;
  final List<CardType> newCards;
  final List<UnitType> newHeroes;
  final bool newBest;

  /// Names of game modes this result just unlocked.
  final List<String> newModes;
}

/// Persistent profile: unlocks, deck, campaign progress, stats and settings.
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

  static int _int(String key) => (_get(key) as int?) ?? 0;

  static T? _enum<T extends Enum>(List<T> values, String key) {
    final name = _get(key);
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }

  static Set<T> _enumSet<T extends Enum>(List<T> values, String key) {
    final raw = _get(key);
    if (raw is! List) return {};
    final names = raw.whereType<String>().toSet();
    return {
      for (final v in values)
        if (names.contains(v.name)) v,
    };
  }

  // ───────────────────────── explore save ─────────────────────────

  /// The saved Explore game, or null if there is none (or it can't be read).
  static WorldState? get exploreWorld {
    final raw = _get('explore');
    if (raw is! String) return null;
    try {
      return WorldState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static void saveExplore(WorldState w) =>
      _put('explore', jsonEncode(w.toJson()));

  static void clearExplore() => _put('explore', null);

  // ───────────────────────── unlocks ─────────────────────────

  static Set<CardType> get unlockedCards => {
    ...baseCards,
    ..._enumSet(CardType.values, 'unlockedCards'),
  };

  static Set<UnitType> get unlockedHeroes => {
    UnitType.hero,
    ..._enumSet(UnitType.values, 'unlockedHeroes'),
  };

  // ───────────────────────── level setup ─────────────────────────

  /// Config for playing [lv]: the player's chosen hero, and either the
  /// level's own set of cards or everything unlocked so far.
  static GameConfig configFor(LevelDef lv) => lv.config.copyWith(
    playerHero: hero,
    deck: lv.config.deck ?? unlockedCards,
  );

  // ───────────────────────── settings ─────────────────────────

  static Difficulty get difficulty =>
      _enum(Difficulty.values, 'difficulty') ?? Difficulty.normal;
  static set difficulty(Difficulty d) => _put('difficulty', d.name);

  static UnitType get hero {
    final h = _enum(UnitType.values, 'hero') ?? UnitType.hero;
    return unlockedHeroes.contains(h) ? h : UnitType.hero;
  }

  static set hero(UnitType h) => _put('hero', h.name);

  static Objective get objective =>
      _enum(Objective.values, 'objective') ?? Objective.eliminate;
  static set objective(Objective o) => _put('objective', o.name);

  // ───────────────────────── campaign ─────────────────────────

  static int stars(int level) {
    final raw = _get('stars');
    if (raw is Map) return (raw['$level'] as int?) ?? 0;
    return 0;
  }

  static int get totalStars => [
    for (var i = 0; i < campaignLevels.length; i++) stars(i),
  ].fold(0, (a, b) => a + b);

  static bool levelUnlocked(int level) =>
      level == 0 ||
      stars(level - 1) > 0 ||
      (skippedTutorial && level >= lessonCount);

  // ───────────────────────── tutorial gating ─────────────────────────

  static bool get skippedTutorial => _get('skipTutorial') == true;

  /// Lets the player past the lessons straight away.
  static void skipTutorial() => _put('skipTutorial', true);

  static int get lessonsDone => [
    for (var i = 0; i < lessonCount; i++)
      if (stars(i) > 0) i,
  ].length;

  static bool get hotseatUnlocked =>
      skippedTutorial || lessonsDone >= hotseatLessons;

  static bool get skirmishUnlocked =>
      skippedTutorial || lessonsDone >= lessonCount;

  // ───────────────────────── stats ─────────────────────────

  static int played(GameMode m) => _int('played_${m.name}');
  static int won(GameMode m) => _int('won_${m.name}');

  /// Fewest rounds a game of [m] was won in, or 0 if never won.
  static int bestRounds(GameMode m) => _int('best_${m.name}');

  /// Records a finished game and applies any campaign rewards.
  static GameResult recordGame(
    GameConfig config, {
    required bool won,
    required int rounds,
  }) {
    final m = config.mode;
    final hadHotseat = hotseatUnlocked;
    final hadSkirmish = skirmishUnlocked;
    _put('played_${m.name}', played(m) + 1);
    if (!won) return const GameResult();
    _put('won_${m.name}', Storage.won(m) + 1);
    final best = bestRounds(m);
    final newBest = best == 0 || rounds < best;
    if (newBest) _put('best_${m.name}', rounds);

    final idx = config.level;
    if (m != GameMode.campaign || idx == null) {
      return GameResult(newBest: newBest);
    }
    final level = campaignLevels[idx];
    final stars = level.starsFor(rounds);
    if (stars > Storage.stars(idx)) {
      final raw = _get('stars');
      final map = <String, int>{
        if (raw is Map)
          for (final e in raw.entries) '${e.key}': e.value as int,
      };
      map['$idx'] = stars;
      _put('stars', map);
    }

    final haveCards = unlockedCards;
    final haveHeroes = unlockedHeroes;
    final newCards = [
      for (final c in level.rewardCards)
        if (!haveCards.contains(c)) c,
    ];
    final newHeroes = [
      for (final h in level.rewardHeroes)
        if (!haveHeroes.contains(h)) h,
    ];
    if (newCards.isNotEmpty) {
      _put('unlockedCards', [
        for (final c in {...haveCards, ...newCards}) c.name,
      ]);
    }
    if (newHeroes.isNotEmpty) {
      _put('unlockedHeroes', [
        for (final h in {...haveHeroes, ...newHeroes}) h.name,
      ]);
    }
    return GameResult(
      stars: stars,
      newCards: newCards,
      newHeroes: newHeroes,
      newBest: newBest,
      newModes: [
        if (!hadHotseat && hotseatUnlocked) 'Hot-seat',
        if (!hadSkirmish && skirmishUnlocked) 'Skirmish',
      ],
    );
  }

  /// Wipes all saved progress.
  static Future<void> reset() async {
    _mem.clear();
    await _box?.clear();
  }
}
