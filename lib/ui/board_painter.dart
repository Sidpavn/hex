import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../game/config.dart';
import '../game/game_controller.dart';
import '../game/hex.dart';
import '../game/models.dart';
import 'fx_layer.dart';
import 'pixel/hex_art.dart';
import 'pixel/pixel_assets.dart';

double _hash(int a, int b, int k) {
  var x = (a * 374761393 + b * 668265263 + k * 2147483647) & 0x7FFFFFFF;
  x = ((x ^ (x >> 13)) * 1274126177) & 0x7FFFFFFF;
  x ^= x >> 16;
  return (x & 0xFFFF) / 65535.0;
}

final Map<String, TextPainter> _textCache = {};

TextPainter _pixelText(String s, double size, Color color) {
  final key = '$s@$size@${color.toARGB32()}';
  if (_textCache.length > 200) _textCache.clear();
  return _textCache.putIfAbsent(
    key,
    () => TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontFamily: 'VT323',
          fontSize: size,
          height: 1,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(),
  );
}

/// Draws the board entirely from baked pixel sprites. Everything is placed on
/// the art-pixel grid of [BoardLayout] and sampled with nearest-neighbour, so
/// no sprite is ever smoothed, rotated or fractionally scaled.
class BoardPainter extends CustomPainter {
  BoardPainter(this.game, this.fx) : super(repaint: fx.tick);

  final GameController game;
  final FxLayer fx;

  static const _bg = Color(0xFF182428);
  static const _ink = Color(0xFF1A1C2C);

  final Paint _plain = Paint()
    ..filterQuality = FilterQuality.none
    ..isAntiAlias = false;
  final Paint _fill = Paint()..isAntiAlias = false;

  late PixelAssets _art;
  late BoardLayout _l;

  @override
  bool shouldRepaint(covariant BoardPainter old) => true;

  /// Whole-number animation tick at [rate] frames per second.
  int _tick(double rate, [double phase = 0]) =>
      (fx.time * rate + phase).floor();

  void _blit(
    Canvas canvas,
    ui.Image img,
    Offset topLeft, {
    ColorFilter? filter,
  }) {
    _plain.colorFilter = filter;
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromLTWH(
        topLeft.dx,
        topLeft.dy,
        img.width * _l.scale,
        img.height * _l.scale,
      ),
      _plain,
    );
    _plain.colorFilter = null;
  }

  /// Draws [img] with its top-left [ax],[ay] art pixels from [c].
  void _blitAt(
    Canvas canvas,
    ui.Image img,
    Offset c,
    double ax,
    double ay, {
    ColorFilter? filter,
  }) => _blit(
    canvas,
    img,
    c + Offset(ax * _l.scale, ay * _l.scale),
    filter: filter,
  );

  void _rect(
    Canvas canvas,
    Offset c,
    double ax,
    double ay,
    int w,
    int h,
    Color color,
  ) {
    _fill.color = color;
    final s = _l.scale;
    canvas.drawRect(
      Rect.fromLTWH(c.dx + ax * s, c.dy + ay * s, w * s, h * s),
      _fill,
    );
  }

  ColorFilter _tint(Color c) => ColorFilter.mode(c, BlendMode.srcIn);

  @override
  void paint(Canvas canvas, Size size) {
    _fill.color = _bg;
    canvas.drawRect(Offset.zero & size, _fill);
    final art = PixelAssets.instance;
    if (art == null) return;
    _art = art;
    final layout = _l = BoardLayout.fit(size);

    canvas.save();
    final sh = fx.shakeOffset * layout.size * 0.5;
    canvas.translate(
      (sh.dx / layout.scale).roundToDouble() * layout.scale,
      (sh.dy / layout.scale).roundToDouble() * layout.scale,
    );

    final hexes = game.tiles.keys.toList()
      ..sort((a, b) => a.r != b.r ? a.r.compareTo(b.r) : a.q.compareTo(b.q));
    for (final h in hexes) {
      _tile(canvas, layout, h, game.tiles[h]!);
    }

    if (fx.introTime > 1.0) {
      if (game.objective == Objective.hold) _centreMark(canvas, layout);
      _highlights(canvas, layout);
      _coachFocus(canvas, layout);
      for (final h in hexes) {
        if (game.tiles[h]!.fire > 0) _flames(canvas, layout, h);
      }
    }

    final drawables = <_Drawable>[
      for (final u in game.units) _Drawable(u, u.vr, 1),
      for (final g in fx.ghosts) _Drawable(g.unit, g.unit.vr, 1 - g.t),
    ]..sort((a, b) => a.sortKey.compareTo(b.sortKey));
    for (final d in drawables) {
      _unit(canvas, layout, d);
    }

    _projectiles(canvas, layout);
    _particles(canvas, layout);
    _floatTexts(canvas, layout);
    canvas.restore();
  }

  // ───────────────────────── tiles ─────────────────────────

  void _tile(Canvas canvas, BoardLayout L, Hex h, Tile t) {
    final intro = ((fx.introTime - t.introDelay) / 0.7).clamp(0.0, 1.0);
    if (intro <= 0) return;
    final e = Curves.easeOutCubic.transform(intro);
    final c = L.snap(L.hexCenter(h) + Offset(0, (1 - e) * -L.scale * 90));
    final variant = (_hash(h.q, h.r, 7) * HexArt.variants).floor();
    final frames = HexArt.framesOf(t.terrain);
    final frame = frames == 1 ? 0 : _tick(3, _hash(h.q, h.r, 8) * frames);
    final sunk = HexArt.sunk(t.terrain);

    _blitAt(
      canvas,
      _art.tile(t.terrain, variant, frame),
      c,
      -HexArt.w / 2,
      -HexArt.h / 2 + (sunk ? 2 : 0),
      filter: t.fire > 0
          ? ColorFilter.mode(const Color(0x995B3A2A), BlendMode.srcATop)
          : null,
    );

    switch (t.terrain) {
      case Terrain.forest:
        final sway = _tick(1.6, _hash(h.q, h.r, 9) * 2).isEven
            ? 'idle0'
            : 'idle1';
        final other = _tick(1.6, _hash(h.q, h.r, 10) * 2 + 1).isEven
            ? 'idle0'
            : 'idle1';
        _blitAt(canvas, _art.sprite('tree', other), c, -11, -9);
        _blitAt(canvas, _art.sprite('tree', sway), c, -1, -4);
      case Terrain.mountain:
        _blitAt(canvas, _art.sprite('mountain'), c, -13, -6);
        _blitAt(canvas, _art.sprite('mountain'), c, -2, -1);
      case Terrain.crystal:
        final f = _tick(1.5, _hash(h.q, h.r, 11) * 2).isEven
            ? 'idle0'
            : 'idle1';
        _blitAt(canvas, _art.sprite('crystal', f), c, -8, -9);
        if (_tick(2.5, _hash(h.q, h.r, 12) * 4) % 4 == 0) {
          _rect(canvas, c, 4, -9, 1, 3, Colors.white);
          _rect(canvas, c, 3, -8, 3, 1, Colors.white);
        }
      case Terrain.grass:
      case Terrain.water:
      case Terrain.lava:
        break;
    }
  }

  void _flames(Canvas canvas, BoardLayout L, Hex h) {
    final c = L.snap(L.hexCenter(h));
    const spots = [Offset(-11, -4), Offset(-2, -9), Offset(1, -2)];
    for (var i = 0; i < spots.length; i++) {
      final f = _tick(8, i * 1.3 + h.q) % 3;
      _blitAt(canvas, _art.sprite('flame', 'f$f'), c, spots[i].dx, spots[i].dy);
    }
  }

  // ───────────────────────── highlights ─────────────────────────

  /// Pulsing ring and a bobbing cursor over the hexes a lesson points at.
  void _coachFocus(Canvas canvas, BoardLayout L) {
    final step = game.coachStep;
    if (step == null) return;
    final on = _tick(4).isEven;
    for (final h in step.hexes) {
      if (!game.tiles.containsKey(h)) continue;
      final c = L.snap(L.hexCenter(h));
      _blitAt(
        canvas,
        _art.mask('ring'),
        c,
        -HexArt.w / 2,
        -HexArt.h / 2,
        filter: _tint(on ? const Color(0xFFFFE082) : const Color(0xFFC88C28)),
      );
      final bob = _tick(4).isEven ? 0 : 2;
      _blitAt(canvas, _art.sprite('cursor'), c, -5, -34.0 + bob);
    }
  }

  void _centreMark(Canvas canvas, BoardLayout L) {
    final c = L.snap(L.hexCenter(GameController.centre));
    const gold = Color(0xFFFFE082);
    _blitAt(
      canvas,
      _art.mask(_tick(2).isEven ? 'fillA' : 'fillB'),
      c,
      -HexArt.w / 2,
      -HexArt.h / 2,
      filter: _tint(gold.withValues(alpha: 0.35)),
    );
    _blitAt(
      canvas,
      _art.mask('ring'),
      c,
      -HexArt.w / 2,
      -HexArt.h / 2,
      filter: _tint(gold),
    );
    if (game.unitAt(GameController.centre) == null) {
      _blitAt(canvas, _art.sprite('star'), c, -8, -8);
    }
  }

  void _highlights(Canvas canvas, BoardLayout L) {
    final phase = _tick(3).isEven;
    void hl(Hex h, Color c) {
      final centre = L.snap(L.hexCenter(h));
      _blitAt(
        canvas,
        _art.mask(phase ? 'fillA' : 'fillB'),
        centre,
        -HexArt.w / 2,
        -HexArt.h / 2,
        filter: _tint(c.withValues(alpha: 0.5)),
      );
      _blitAt(
        canvas,
        _art.mask('ring'),
        centre,
        -HexArt.w / 2,
        -HexArt.h / 2,
        filter: _tint(c),
      );
    }

    game.moveTargets.forEach((h, _) => hl(h, const Color(0xFF39E673)));
    for (final h in game.attackTargets) {
      hl(h, const Color(0xFFFF4D4D));
    }
    for (final h in game.cardTargets) {
      hl(h, const Color(0xFFFFD54A));
    }
    final sel = game.selected;
    if (sel != null) {
      final c = L.snap(L.hexCenter(sel.pos));
      _blitAt(
        canvas,
        _art.mask('ring'),
        c,
        -HexArt.w / 2,
        -HexArt.h / 2,
        filter: _tint(_tick(4).isEven ? Colors.white : const Color(0xFFA0AABE)),
      );
    }
  }

  // ───────────────────────── units ─────────────────────────

  void _unit(Canvas canvas, BoardLayout L, _Drawable d) {
    final u = d.unit;
    final s = L.scale;
    final spawn = Curves.easeOutCubic.transform(u.spawn.clamp(0.0, 1.0));
    if (spawn <= 0.01) return;
    // Dying units blink out.
    if (d.alpha < 1 && ((1 - d.alpha) * 14).floor().isOdd) return;

    var ground = L.toPixel(u.vq, u.vr);
    if (u.lunge > 0 && u.lungeTo != null) {
      final to = L.hexCenter(u.lungeTo!);
      final v = to - ground;
      if (v.distance > 0) {
        ground += v / v.distance * L.size * 0.65 * math.sin(math.pi * u.lunge);
      }
    }
    ground = L.snap(ground);
    final hop = (u.hop * L.size / s).round() * s;

    final attacking = u.lunge > 0;
    final frame = attacking
        ? 'attack'
        : (_tick(2, u.id * 0.37).isEven ? 'idle0' : 'idle1');
    final img = _art.unit(u.type, u.team, frame);
    final w = img.width;
    final h = img.height;
    final left = ground.dx - (w / 2).floor() * s;
    final top = ground.dy + 6 * s - h * s - hop;

    // shadow
    final shadow = _art.mask(w > 16 ? 'shadowL' : 'shadowS');
    _blit(
      canvas,
      shadow,
      Offset(ground.dx - (shadow.width / 2).floor() * s, ground.dy + 4 * s),
    );

    final exhausted =
        u.team == game.viewTeam && game.isPlayerTurn && !u.canMove && !u.canAct;
    ColorFilter? filter;
    if (u.flash > 0.15) {
      filter = ColorFilter.mode(Colors.white, BlendMode.srcATop);
    } else if (exhausted) {
      filter = const ColorFilter.mode(Color(0x99586070), BlendMode.srcATop);
    }

    // Spawning units rise out of the ground.
    final visible = (h * spawn).ceil();
    final rise = (h - visible) * s;
    canvas.save();
    if (rise > 0) {
      canvas.clipRect(Rect.fromLTWH(left, top, w * s, h * s));
    }
    _blit(canvas, img, Offset(left, top + rise), filter: filter);
    canvas.restore();

    if (u.shield > 0) {
      final bubble = _art.mask('shield');
      final alt = _tick(3, u.id.toDouble()).isEven;
      _blit(
        canvas,
        bubble,
        Offset(
          ground.dx - (bubble.width / 2).floor() * s,
          top + (h / 2).floor() * s - (bubble.height / 2).floor() * s,
        ),
        filter: _tint(alt ? const Color(0xFF80D8FF) : const Color(0xFFC8F0FF)),
      );
    }

    if (d.alpha < 1) return;
    final maxHp = u.stats.maxHp;
    final pipW = maxHp <= 8 ? 3 : 2;
    final barW = maxHp * pipW + 2;
    final bx = ground.dx - (barW / 2).floor() * s;
    final by = top - 5 * s;
    _fill.color = _ink;
    canvas.drawRect(Rect.fromLTWH(bx, by, barW * s, 4 * s), _fill);
    final frac = u.hp / maxHp;
    final fillColour = frac > 0.5
        ? const Color(0xFF6EDC82)
        : frac > 0.25
        ? const Color(0xFFF4C846)
        : const Color(0xFFE6503C);
    for (var i = 0; i < maxHp; i++) {
      _fill.color = i < u.hp ? fillColour : const Color(0xFF3A3E52);
      canvas.drawRect(
        Rect.fromLTWH(bx + (1 + i * pipW) * s, by + s, (pipW - 1) * s, 2 * s),
        _fill,
      );
    }
    if (u.isHero) {
      final crown = _art.sprite('crown');
      _blit(
        canvas,
        crown,
        Offset(ground.dx - (crown.width / 2).floor() * s, by - 7 * s),
      );
    }

    // Ready indicators for the player's units.
    if (u.team == game.viewTeam && game.isPlayerTurn) {
      void dot(double ox, Color c) {
        _fill.color = _ink;
        canvas.drawRect(
          Rect.fromLTWH(ground.dx + ox * s, ground.dy + 9 * s, 4 * s, 4 * s),
          _fill,
        );
        _fill.color = c;
        canvas.drawRect(
          Rect.fromLTWH(
            ground.dx + (ox + 1) * s,
            ground.dy + 10 * s,
            2 * s,
            2 * s,
          ),
          _fill,
        );
      }

      if (u.canMove) dot(-5, const Color(0xFF39E673));
      if (u.canAct) dot(1, const Color(0xFFFFB142));
    }
  }

  // ───────────────────────── fx ─────────────────────────

  void _projectiles(Canvas canvas, BoardLayout L) {
    for (final pr in fx.projectiles) {
      final p = L.snap(L.unitToPixel(fx.projectilePos(pr)));
      final n = math.max(
        3,
        ((pr.radius + 0.08) * L.size / L.scale * 1.6).round(),
      );
      final half = (n / 2).floor();
      _rect(canvas, p, -half.toDouble(), -half.toDouble(), n, n, pr.color);
      _rect(canvas, p, -half + 1.0, -half + 1.0, n - 2, n - 2, Colors.white);
    }
  }

  void _particles(Canvas canvas, BoardLayout L) {
    for (final p in fx.particles) {
      final pos = L.snap(L.unitToPixel(Offset(p.x, p.y)));
      final a = (1 - p.t).clamp(0.0, 1.0);
      if (a < 0.15) continue;
      if (p.ring) {
        final rad = p.size * L.size / L.scale * Curves.easeOut.transform(p.t);
        final sz = a > 0.5 ? 2 : 1;
        for (var i = 0; i < 12; i++) {
          final ang = i * math.pi / 6;
          final o = Offset(math.cos(ang) * rad, math.sin(ang) * rad * 0.6);
          final q = L.snap(pos + o * L.scale);
          _rect(canvas, q, 0, 0, sz, sz, p.color.withValues(alpha: 1));
        }
      } else {
        final sz = math.max(
          1,
          (p.size * L.size / L.scale * (0.5 + 0.5 * a) * 2).round(),
        );
        _rect(canvas, pos, 0, 0, sz, sz, p.color.withValues(alpha: 1));
      }
    }
  }

  static final _token = RegExp(r':([a-z0-9]+):');

  void _floatTexts(Canvas canvas, BoardLayout L) {
    final s = L.scale;
    for (final t in fx.texts) {
      if (t.t > 0.6 && ((t.t - 0.6) * 20).floor().isOdd) continue;
      final pos = L.snap(L.unitToPixel(Offset(t.x, t.y - t.t * 0.9)));
      final color = t.color.withValues(alpha: 1);

      // Split into text runs and inline icons (`:bolt:`).
      final parts = <Object>[];
      var last = 0;
      for (final m in _token.allMatches(t.text)) {
        if (!_art.hasIcon(m.group(1)!)) continue;
        if (m.start > last) parts.add(t.text.substring(last, m.start));
        parts.add(_art.icon(m.group(1)!));
        last = m.end;
      }
      if (last < t.text.length) parts.add(t.text.substring(last));

      double widthOf(Object p) => p is String
          ? _pixelText(p, 16 * s, color).width
          : (p as ui.Image).width * s;
      final total = parts.fold<double>(0, (a, p) => a + widthOf(p));
      var x = pos.dx - (total / 2).floorToDouble();
      final lineH = _pixelText('0', 16 * s, color).height;
      final y = pos.dy - lineH / 2;
      for (final p in parts) {
        if (p is String) {
          final fill = _pixelText(p, 16 * s, color);
          final line = _pixelText(p, 16 * s, _ink);
          for (final d in const [
            Offset(-1, 0),
            Offset(1, 0),
            Offset(0, -1),
            Offset(0, 1),
          ]) {
            line.paint(canvas, Offset(x, y) + d * s);
          }
          fill.paint(canvas, Offset(x, y));
          x += fill.width;
        } else {
          final img = p as ui.Image;
          _blit(canvas, img, Offset(x, pos.dy - img.height * s / 2));
          x += img.width * s;
        }
      }
    }
  }
}

class _Drawable {
  _Drawable(this.unit, this.sortKey, this.alpha);
  final Unit unit;
  final double sortKey;
  final double alpha;
}
