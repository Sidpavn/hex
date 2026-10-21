import 'dart:convert';

import 'package:hive_ce_flutter/hive_flutter.dart';

import '../diner/diner.dart';
import 'cloud_save.dart';

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

  // ───────────────────────── diner save ─────────────────────────

  /// How many games can be kept side by side.
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
