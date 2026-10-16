import 'dart:convert';

import 'package:hive_ce_flutter/hive_flutter.dart';

import '../diner/diner.dart';

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

  /// The saved diner, or null if there is none (or it can't be read).
  static Diner? get diner {
    final raw = _get('diner');
    if (raw is! String) return null;
    try {
      return Diner.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } catch (_) {
      return null;
    }
  }

  static void saveDiner(Diner d) => _put('diner', jsonEncode(d.toJson()));

  /// Forgets the saved diner, so the next one starts from scratch.
  static void clearDiner() => _put('diner', null);

  /// Wipes all saved progress.
  static Future<void> reset() async {
    _mem.clear();
    await _box?.clear();
  }
}
