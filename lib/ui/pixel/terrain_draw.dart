import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../game/models.dart';
import 'hex_art.dart';
import 'pixel_assets.dart';

/// Stable pseudo-random value in [0, 1) for a hex and a purpose [k].
double hash01(int a, int b, int k) {
  var x = (a * 374761393 + b * 668265263 + k * 2147483647) & 0x7FFFFFFF;
  x = ((x ^ (x >> 13)) * 1274126177) & 0x7FFFFFFF;
  x ^= x >> 16;
  return (x & 0xFFFF) / 65535.0;
}

/// Bit flags for [TerrainDraw.draw]'s `openEdges`: sides with no neighbour.
int openEdgesFor(bool Function(int q, int r) has, int q, int r) {
  var bits = 0;
  if (!has(q + 1, r)) bits |= 1; // E
  if (!has(q, r + 1)) bits |= 2; // SE
  if (!has(q - 1, r + 1)) bits |= 4; // SW
  return bits;
}

/// Drop (in height levels) from [t] to each south neighbour, as
/// `(southEast, southWest)`. A missing neighbour counts as a one-level drop, so
/// the edge of the map gets a cliff too.
(int, int) cliffsFor(
  Terrain? Function(int q, int r) terrainAt,
  int q,
  int r,
  Terrain t,
) {
  int drop(Terrain? n) =>
      n == null ? 1 : math.max(0, HexArt.elevation(t) - HexArt.elevation(n));
  return (drop(terrainAt(q, r + 1)), drop(terrainAt(q - 1, r + 1)));
}

/// Draws one terrain hex (base tile plus its trees, peaks or crystals) the
/// same way on the battle board and in the explorable world.
class TerrainDraw {
  TerrainDraw(this.art);

  final PixelAssets art;
  final Paint _plain = Paint()
    ..filterQuality = FilterQuality.none
    ..isAntiAlias = false;
  final Paint _fill = Paint()..isAntiAlias = false;

  void blit(
    Canvas canvas,
    ui.Image img,
    Offset c,
    double ax,
    double ay,
    double scale, {
    ColorFilter? filter,
  }) {
    _plain.colorFilter = filter;
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH(
        c.dx + ax * scale,
        c.dy + ay * scale,
        img.width * scale,
        img.height * scale,
      ),
      _plain,
    );
    _plain.colorFilter = null;
  }

  void rect(
    Canvas canvas,
    Offset c,
    double ax,
    double ay,
    int w,
    int h,
    double scale,
    Color color,
  ) {
    _fill.color = color;
    canvas.drawRect(
      Rect.fromLTWH(c.dx + ax * scale, c.dy + ay * scale, w * scale, h * scale),
      _fill,
    );
  }

  int _tick(double time, double rate, [double phase = 0]) =>
      (time * rate + phase).floor();

  /// [c] is the hex centre in logical pixels, already snapped to the art grid.
  void draw(
    Canvas canvas,
    Offset c,
    double s,
    Terrain terrain,
    int q,
    int r,
    double time, {
    ColorFilter? filter,
    bool features = true,
    int openEdges = 0,
    int cliffSE = 0,
    int cliffSW = 0,
  }) {
    final variant = (hash01(q, r, 7) * HexArt.variants).floor();
    final frames = HexArt.framesOf(terrain);
    final frame = frames == 1 ? 0 : _tick(time, 3, hash01(q, r, 8) * frames);
    final sunk = HexArt.sunk(terrain);

    blit(
      canvas,
      art.tile(terrain, variant, frame),
      c,
      -HexArt.w / 2,
      -HexArt.h / 2 + (sunk ? 2 : 0),
      s,
      filter: filter,
    );
    // Cliff faces where the neighbour to the south is lower than this tile.
    for (final (drop, name) in [(cliffSE, 'SE'), (cliffSW, 'SW')]) {
      if (drop <= 0) continue;
      blit(
        canvas,
        art.mask('cliff$name${HexArt.cliffPixels(drop)}'),
        c,
        -HexArt.w / 2,
        -HexArt.h / 2,
        s,
        filter: ColorFilter.mode(
          Color(0xFF000000 | HexArt.sideOf(terrain)),
          BlendMode.srcIn,
        ),
      );
    }

    // Edges that have no neighbouring tile get their own outline.
    if (openEdges != 0) {
      final line = ColorFilter.mode(
        Color(HexArt.outlineOf(terrain)),
        BlendMode.srcIn,
      );
      for (final e in const {1: 'edgeE', 2: 'edgeSE', 4: 'edgeSW'}.entries) {
        if (openEdges & e.key == 0) continue;
        blit(
          canvas,
          art.mask(e.value),
          c,
          -HexArt.w / 2,
          -HexArt.h / 2 + (sunk ? 2 : 0),
          s,
          filter: line,
        );
      }
    }
    if (!features) return;

    switch (terrain) {
      case Terrain.forest:
        final sway = _tick(time, 1.6, hash01(q, r, 9) * 2).isEven
            ? 'idle0'
            : 'idle1';
        final other = _tick(time, 1.6, hash01(q, r, 10) * 2 + 1).isEven
            ? 'idle0'
            : 'idle1';
        blit(canvas, art.sprite('tree', other), c, -11, -9, s, filter: filter);
        blit(canvas, art.sprite('tree', sway), c, -1, -4, s, filter: filter);
      case Terrain.mountain:
        blit(canvas, art.sprite('mountain'), c, -13, -6, s, filter: filter);
        blit(canvas, art.sprite('mountain'), c, -2, -1, s, filter: filter);
      case Terrain.crystal:
        final f = _tick(time, 1.5, hash01(q, r, 11) * 2).isEven
            ? 'idle0'
            : 'idle1';
        blit(canvas, art.sprite('crystal', f), c, -8, -9, s, filter: filter);
        if (_tick(time, 2.5, hash01(q, r, 12) * 4) % 4 == 0) {
          rect(canvas, c, 4, -9, 1, 3, s, Colors.white);
          rect(canvas, c, 3, -8, 3, 1, s, Colors.white);
        }
      case Terrain.grass:
      case Terrain.water:
      case Terrain.lava:
        break;
    }
  }
}
