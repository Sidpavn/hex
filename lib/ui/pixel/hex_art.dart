import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../game/models.dart';
import 'pixel_assets.dart';

/// Procedural hex tiles and shape masks, in art pixels.
///
/// A tile is 24x28 and tiles with a step of (24, 21) per column/row, offset by
/// half a tile on odd rows. That tessellates with no gaps or overlaps, so the
/// board stays seamless at any integer scale.
class HexArt {
  static const int w = 24;
  static const int h = 28;
  static const int rowStep = 21;
  static const int variants = 3;

  static bool inside(int x, int y) {
    final dx = (x + 0.5 - w / 2).abs();
    final dy = (y + 0.5 - h / 2).abs();
    return dx <= w / 2 && dy <= h / 2 - (h / 4) * dx / (w / 2);
  }

  static bool animated(Terrain t) => t == Terrain.water || t == Terrain.lava;

  static int framesOf(Terrain t) => switch (t) {
    Terrain.water => 4,
    Terrain.lava => 3,
    _ => 1,
  };

  /// Water and lava sit in a basin: drawn flat and a little lower.
  /// Tiles are flat now: a basin offset would break the seamless tiling.
  static bool sunk(Terrain t) => false;

  /// Neighbour offsets in art pixels, in the order E, W, NE, NW, SE, SW.
  static const _nbrs = [
    (24, 0),
    (-24, 0),
    (12, -21),
    (-12, -21),
    (12, 21),
    (-12, 21),
  ];

  /// Which neighbouring hex owns the (outside) pixel at [x],[y] in this
  /// tile's coordinates, as an index into [_nbrs].
  static int _ownerOf(int x, int y) {
    for (var i = 0; i < _nbrs.length; i++) {
      if (inside(x - _nbrs[i].$1, y - _nbrs[i].$2)) return i;
    }
    return -1;
  }

  // A shared edge is drawn by exactly one of the two tiles that meet there:
  // each tile outlines its W, NW and NE sides. That makes grid lines one pixel
  // thick instead of two. The E, SE and SW sides are only drawn (as separate
  // overlays, see [bakeMasks]) where there is no neighbouring tile.
  static const _kept = {1, 2, 3};
  static const edgeBits = {0: 1, 4: 2, 5: 4};

  /// How high a terrain stands. Edges only get a cliff face where a tile
  /// stands above its neighbour: grass beside water, mountains beside anything.
  static int elevation(Terrain t) => switch (t) {
    Terrain.water || Terrain.lava => 0,
    Terrain.mountain => 2,
    _ => 1,
  };

  /// Colour of the cliff face under a terrain.
  static int sideOf(Terrain t) => _palette[t]![3];

  /// Cliff thickness in pixels for a drop of [diff] levels.
  static int cliffPixels(int diff) => diff >= 2 ? 4 : 2;

  /// Outline colour for a terrain's tile edges.
  static int outlineOf(Terrain t) => _darken(_palette[t]![3], 0.62);

  /// Outward-facing neighbour directions of the inside pixel [x],[y].
  static Set<int> _outsideDirs(int x, int y) {
    final dirs = <int>{};
    for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      if (!inside(x + dx, y + dy)) dirs.add(_ownerOf(x + dx, y + dy));
    }
    return dirs;
  }

  static int _hash(int x, int y, int s) {
    var v = (x * 73856093) ^ (y * 19349663) ^ (s * 83492791);
    v = (v ^ (v >> 13)) * 1274126177;
    return (v & 0x7FFFFFFF) % 100;
  }

  // base, dark speckle, light speckle, side (lip) colour
  static const _palette = <Terrain, List<int>>{
    Terrain.grass: [0xFF60B060, 0xFF4C9654, 0xFF84C86E, 0xFF306846],
    Terrain.crystal: [0xFF60B060, 0xFF4C9654, 0xFF84C86E, 0xFF306846],
    Terrain.forest: [0xFF3C8254, 0xFF2E6C48, 0xFF4C965A, 0xFF225040],
    Terrain.water: [0xFF4690DC, 0xFF3674C8, 0xFF78BEF0, 0xFF224A8C],
    Terrain.lava: [0xFFC83C28, 0xFFA02828, 0xFFFA9632, 0xFF641E28],
    Terrain.mountain: [0xFF82869A, 0xFF6E7286, 0xFFA0A6B4, 0xFF464A60],
  };

  static int _darken(int argb, double f) {
    final r = (((argb >> 16) & 0xFF) * f).round();
    final g = (((argb >> 8) & 0xFF) * f).round();
    final b = ((argb & 0xFF) * f).round();
    return 0xFF000000 | (r << 16) | (g << 8) | b;
  }

  static void _put(Uint8List px, int x, int y, int argb, [int width = w]) {
    final i = (y * width + x) * 4;
    px[i] = (argb >> 16) & 0xFF;
    px[i + 1] = (argb >> 8) & 0xFF;
    px[i + 2] = argb & 0xFF;
    px[i + 3] = (argb >> 24) & 0xFF;
  }

  static Future<Map<String, ui.Image>> bakeTiles() async {
    final out = <String, ui.Image>{};
    for (final t in Terrain.values) {
      final pal = _palette[t]!;
      final outline = _darken(pal[3], 0.62);
      for (var v = 0; v < variants; v++) {
        for (var f = 0; f < framesOf(t); f++) {
          final px = Uint8List(w * h * 4);
          for (var y = 0; y < h; y++) {
            for (var x = 0; x < w; x++) {
              if (!inside(x, y)) continue;
              final still = _hash(x, y, v * 7 + 1);
              var c = pal[0];
              switch (t) {
                case Terrain.water:
                  final ripple = y % 6 == 1 && (x + (y ~/ 6) * 4 + f) % 10 < 3;
                  if (ripple) {
                    c = pal[2];
                  } else if (_hash(x, y, 200 + f) < 2) {
                    c = 0xFFDCF0FF;
                  } else if (still < 14) {
                    c = pal[1];
                  }
                case Terrain.lava:
                  final spark = _hash(x, y, 300 + f * 5 + v);
                  if (spark < 2) {
                    c = 0xFFFADC64;
                  } else if (spark < 6) {
                    c = pal[2];
                  } else if (still < 30) {
                    c = pal[1];
                  }
                default:
                  if (still < 7) {
                    c = pal[2];
                  } else if (still < 24) {
                    c = pal[1];
                  }
              }
              final dirs = _outsideDirs(x, y);
              if (dirs.any(_kept.contains)) {
                _put(px, x, y, outline);
                continue;
              }
              _put(px, x, y, c);
            }
          }
          out['${t.name}.$v.$f'] = await PixelAssets.decodePixels(px, w, h);
        }
      }
    }
    return out;
  }

  static Future<Map<String, ui.Image>> bakeMasks() async {
    final out = <String, ui.Image>{};
    const white = 0xFFFFFFFF;

    for (final phase in [0, 1]) {
      final px = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          if (inside(x, y) && (x + y) % 2 == phase) _put(px, x, y, white);
        }
      }
      out[phase == 0 ? 'fillA' : 'fillB'] = await PixelAssets.decodePixels(
        px,
        w,
        h,
      );
    }

    final ring = Uint8List(w * h * 4);
    bool nearEdge(int x, int y) {
      for (var dy = -2; dy <= 2; dy++) {
        for (var dx = -2; dx <= 2; dx++) {
          if (dx.abs() + dy.abs() <= 2 && !inside(x + dx, y + dy)) return true;
        }
      }
      return false;
    }

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (inside(x, y) && nearEdge(x, y)) _put(ring, x, y, white);
      }
    }
    out['ring'] = await PixelAssets.decodePixels(ring, w, h);

    // Outline pieces for the sides a tile does not draw itself (E, SE, SW),
    // used where a tile has no neighbour there.
    for (final entry in {0: 'edgeE', 4: 'edgeSE', 5: 'edgeSW'}.entries) {
      final px = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          if (!inside(x, y)) continue;
          final dirs = _outsideDirs(x, y);
          if (dirs.any(_kept.contains)) continue;
          if (dirs.contains(entry.key)) _put(px, x, y, white);
        }
      }
      out[entry.value] = await PixelAssets.decodePixels(px, w, h);
    }

    // Cliff faces for the two south-facing sides, 2 and 4 pixels deep.
    for (final dir in const [(4, 'SE'), (5, 'SW')]) {
      for (final depth in const [2, 4]) {
        final px = Uint8List(w * h * 4);
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            if (!inside(x, y)) continue;
            for (var j = 1; j <= depth; j++) {
              if (!inside(x, y + j) && _ownerOf(x, y + j) == dir.$1) {
                _put(px, x, y, white);
                break;
              }
            }
          }
        }
        out['cliff${dir.$2}$depth'] = await PixelAssets.decodePixels(px, w, h);
      }
    }

    const s = 22;
    final shield = Uint8List(s * s * 4);
    for (var y = 0; y < s; y++) {
      for (var x = 0; x < s; x++) {
        final d = math.sqrt(math.pow(x - 10.5, 2) + math.pow(y - 10.5, 2));
        if ((d >= 9.2 && d <= 10.8) || (d < 9.2 && x.isEven && y.isEven)) {
          _put(shield, x, y, white, s);
        }
      }
    }
    out['shield'] = await PixelAssets.decodePixels(shield, s, s);

    Future<ui.Image> shadow(int sw, int sh) {
      final px = Uint8List(sw * sh * 4);
      for (var y = 0; y < sh; y++) {
        for (var x = 0; x < sw; x++) {
          final nx = (x + 0.5 - sw / 2) / (sw / 2);
          final ny = (y + 0.5 - sh / 2) / (sh / 2);
          if (nx * nx + ny * ny <= 1) _put(px, x, y, 0x59000000, sw);
        }
      }
      return PixelAssets.decodePixels(px, sw, sh);
    }

    out['shadowS'] = await shadow(12, 4);
    out['shadowL'] = await shadow(22, 6);
    return out;
  }
}
