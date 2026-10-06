import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../game/models.dart';
import 'hex_art.dart';

/// Every sprite in the game, decoded from `assets/pixel/sprites.txt` and baked
/// into small GPU images once at startup. Nothing here is drawn per-pixel at
/// runtime: the board just blits these with nearest-neighbour sampling.
class PixelAssets {
  PixelAssets._(this._sprites, this._tiles, this._masks);

  static PixelAssets? _instance;

  /// Null until [load] completes. Painters draw nothing sprite-based before.
  static PixelAssets? get instance => _instance;

  static const _teamColours = {
    'b': {'t': 0xFF5082E6, 'T': 0xFF2846A0},
    'r': {'t': 0xFFE25454, 'T': 0xFF8A283C},
  };

  /// `team key → "name.frame" → image`.
  final Map<String, Map<String, ui.Image>> _sprites;
  final Map<String, ui.Image> _tiles;
  final Map<String, ui.Image> _masks;

  static Future<PixelAssets> load([AssetBundle? bundle]) async {
    final text = await (bundle ?? rootBundle).loadString(
      'assets/pixel/sprites.txt',
    );
    final parsed = SpriteFile.parse(text);
    final sprites = <String, Map<String, ui.Image>>{};
    for (final entry in _teamColours.entries) {
      final map = sprites[entry.key] = {};
      for (final s in parsed.frames.entries) {
        map[s.key] = await _bake(s.value, parsed.palette, entry.value);
      }
    }
    final tiles = await HexArt.bakeTiles();
    final masks = await HexArt.bakeMasks();
    return _instance = PixelAssets._(sprites, tiles, masks);
  }

  /// Frames are `idle0`, `idle1` and `attack`. Falls back to `idle0`.
  ui.Image unit(UnitType type, Team team, String frame) {
    final set = _sprites[team == Team.player ? 'b' : 'r']!;
    return set['${type.name}.$frame'] ?? set['${type.name}.idle0']!;
  }

  /// Terrain features and icons (`tree`, `mountain`, `crystal`, `flame`,
  /// `crown`, `star`, `lock`, `heart`, `cursor`).
  ui.Image sprite(String name, [String frame = 'idle0']) =>
      _sprites['b']!['$name.$frame'] ?? _sprites['b']!['$name.idle0']!;

  /// Any icon by name: a UI icon, a terrain feature, or a unit type's idle
  /// frame (`knight`, `mage`...). Unknown names fall back to a star.
  ui.Image icon(String name) {
    final set = _sprites['b']!;
    if (name == 'fire') return set['flame.f0']!;
    for (final u in UnitType.values) {
      if (u.name == name) return unit(u, Team.player, 'idle0');
    }
    return set['$name.idle0'] ?? set['star.idle0']!;
  }

  bool hasIcon(String name) =>
      name == 'fire' ||
      UnitType.values.any((u) => u.name == name) ||
      _sprites['b']!.containsKey('$name.idle0');

  ui.Image tile(Terrain t, int variant, int frame) =>
      _tiles['${t.name}.${variant % HexArt.variants}.${frame % HexArt.framesOf(t)}']!;

  /// White-on-clear mask images, tinted at draw time: `fillA`, `fillB`
  /// (checkerboard dithers), `ring`, `shield`, `shadowS`, `shadowL`.
  ui.Image mask(String name) => _masks[name]!;

  static Future<ui.Image> _bake(
    List<String> rows,
    Map<String, int> palette,
    Map<String, int> team,
  ) {
    final h = rows.length;
    final w = rows.first.length;
    final px = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final ch = rows[y][x];
        final argb = team[ch] ?? palette[ch];
        if (argb == null) continue;
        final i = (y * w + x) * 4;
        px[i] = (argb >> 16) & 0xFF;
        px[i + 1] = (argb >> 8) & 0xFF;
        px[i + 2] = argb & 0xFF;
        px[i + 3] = 0xFF;
      }
    }
    return decodePixels(px, w, h);
  }

  static Future<ui.Image> decodePixels(Uint8List rgba, int w, int h) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }
}

/// Parsed `sprites.txt`: palette plus every frame (including derived ones).
class SpriteFile {
  SpriteFile(this.palette, this.frames);

  final Map<String, int> palette;

  /// `"name.frame" → rows`.
  final Map<String, List<String>> frames;

  static SpriteFile parse(String text) {
    final palette = <String, int>{};
    final frames = <String, List<String>>{};
    final derive = <String, String>{};
    var section = '';
    String? key;
    List<String>? rows;

    void close() {
      if (key != null && rows != null && rows!.isNotEmpty) {
        final w = rows!.first.length;
        for (final r in rows!) {
          if (r.length != w) {
            throw FormatException('Sprite $key has uneven rows', r);
          }
        }
        frames[key!] = rows!;
      }
      key = null;
      rows = null;
    }

    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      if (line.startsWith('#')) continue;
      if (line.startsWith('@palette')) {
        close();
        section = 'palette';
        continue;
      }
      if (line.startsWith('@sprite')) {
        close();
        section = 'sprite';
        final parts = line.split(RegExp(r'\s+'));
        key = '${parts[1]}.${parts[2]}';
        rows = [];
        for (final extra in parts.skip(3)) {
          if (extra.startsWith('frame1=')) {
            derive['${parts[1]}.idle1'] =
                '${parts[1]}.${parts[2]}|'
                '${extra.substring(7)}';
          }
        }
        continue;
      }
      if (line.isEmpty) {
        if (section == 'sprite') close();
        continue;
      }
      if (section == 'palette') {
        final p = line.split(RegExp(r'\s+'));
        palette[p[0]] = 0xFF000000 | int.parse(p[1], radix: 16);
      } else if (section == 'sprite') {
        rows?.add(line);
      }
    }
    close();

    for (final e in derive.entries) {
      final parts = e.value.split('|');
      final base = frames[parts[0]];
      if (base != null) frames[e.key] = _derive(base, parts[1]);
    }
    return SpriteFile(palette, frames);
  }

  static List<String> _derive(List<String> rows, String mode) {
    final bits = mode.split(':');
    final n = bits.length > 1 ? int.parse(bits[1]) : 0;
    final blank = '.' * rows.first.length;
    switch (bits[0]) {
      case 'breathe':
        if (rows.first != blank) return rows;
        return [...rows.sublist(1, n + 1), rows[n], ...rows.sublist(n + 1)];
      case 'float':
        if (rows.first != blank) return rows;
        return [...rows.sublist(1), blank];
      case 'sway':
        return [
          for (var i = 0; i < rows.length; i++)
            i < n ? '.${rows[i].substring(0, rows[i].length - 1)}' : rows[i],
        ];
    }
    return rows;
  }
}

@visibleForTesting
Future<ui.Image> imageFromRows(List<String> rows, Map<String, int> palette) =>
    PixelAssets._bake(rows, palette, const {});
