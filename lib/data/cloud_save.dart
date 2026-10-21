import 'dart:convert';
import 'dart:io' show gzip;

import '../diner/diner.dart';

/// What can be told about a save without loading it all: enough to show the
/// player which is which, and to decide which is the one to keep.
class SaveInfo {
  const SaveInfo({
    required this.day,
    required this.level,
    required this.coins,
    required this.savedAt,
  });

  /// The in-game day the diner is up to, its level and coins.
  final int day;
  final int level;
  final int coins;

  /// When it was saved, in milliseconds since 1970. Zero if never.
  final int savedAt;

  factory SaveInfo.of(Diner d) => SaveInfo(
    day: d.progress.day,
    level: d.progress.level,
    coins: d.coins,
    savedAt: d.savedAt,
  );

  /// "Day 12, level 5, 840 coins".
  String get summary => 'Day $day, level $level, $coins coins';

  Map<String, Object?> toJson() => {
    'day': day,
    'level': level,
    'coins': coins,
    'savedAt': savedAt,
  };

  static SaveInfo? fromJson(Object? raw) {
    if (raw is! Map) return null;
    int n(String k) => raw[k] is int ? raw[k] as int : 0;
    return SaveInfo(
      day: n('day'),
      level: n('level'),
      coins: n('coins'),
      savedAt: n('savedAt'),
    );
  }
}

/// A save turned into a short piece of text to copy somewhere safe, and back.
/// It is the whole diner, squeezed and checked, so a code that has been cut
/// short or changed is noticed rather than loaded.
class SaveCode {
  SaveCode._();

  /// What every code starts with, and its format number.
  static const prefix = 'HEXSAVE1';

  /// Makes the code for [d].
  static String encode(Diner d) => encodeJson(d.toJson());

  /// Makes a code from saved [json] as it is.
  static String encodeJson(Map<String, Object?> json) {
    final bytes = gzip.encode(utf8.encode(jsonEncode(json)));
    return '$prefix.${_check(bytes)}.${base64Url.encode(bytes)}';
  }

  /// Reads a code back into a diner. Throws a [SaveCodeError] saying what is
  /// wrong with it if it cannot.
  static Diner decode(String text) {
    // A code copied through chat or notes may have picked up spaces or breaks.
    final code = text.replaceAll(RegExp(r'\s+'), '');
    if (code.isEmpty) throw const SaveCodeError('There is nothing to load.');
    final parts = code.split('.');
    if (parts.length != 3 || parts[0] != prefix) {
      throw const SaveCodeError('That is not a save code from this game.');
    }
    final List<int> bytes;
    try {
      bytes = base64Url.decode(parts[2]);
    } on FormatException {
      throw const SaveCodeError('The code is damaged: part of it is missing.');
    }
    if (_check(bytes) != parts[1]) {
      throw const SaveCodeError(
        'The code is damaged: it has been cut short or changed.',
      );
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(gzip.decode(bytes)));
    } catch (_) {
      throw const SaveCodeError('The code is damaged: it cannot be read.');
    }
    if (json is! Map<String, Object?> || json['v'] is! int) {
      throw const SaveCodeError('That is not a save code from this game.');
    }
    if ((json['v'] as int) > Diner.saveVersion) {
      throw const SaveCodeError(
        'This save is from a newer version of the game. Update to load it.',
      );
    }
    try {
      return Diner.fromJson(json);
    } catch (_) {
      throw const SaveCodeError('The code is damaged: it cannot be read.');
    }
  }

  /// A short fingerprint of [bytes], to notice a code that was altered.
  static String _check(List<int> bytes) {
    var h = 0x811c9dc5;
    for (final b in bytes) {
      h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }
}

/// Why a save code could not be loaded, in words for the player.
class SaveCodeError implements Exception {
  const SaveCodeError(this.message);

  final String message;

  @override
  String toString() => message;
}
