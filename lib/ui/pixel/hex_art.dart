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
  static bool sunk(Terrain t) => animated(t);

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
              if (!sunk(t) && y > h ~/ 2 && !inside(x, y + 2)) c = pal[3];
              final edge =
                  !inside(x + 1, y) ||
                  !inside(x - 1, y) ||
                  !inside(x, y + 1) ||
                  !inside(x, y - 1);
              _put(px, x, y, edge ? outline : c);
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
