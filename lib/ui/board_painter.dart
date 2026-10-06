import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/config.dart';
import '../game/game_controller.dart';
import '../game/hex.dart';
import '../game/models.dart';
import 'fx_layer.dart';

final Map<String, TextPainter> _textCache = {};

TextPainter _emoji(String s, double size) {
  final key = '$s@${size.round()}';
  return _textCache.putIfAbsent(key, () {
    return TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontSize: size),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  });
}

double _hash(int a, int b, int k) {
  var x = (a * 374761393 + b * 668265263 + k * 2147483647) & 0x7FFFFFFF;
  x = ((x ^ (x >> 13)) * 1274126177) & 0x7FFFFFFF;
  x ^= x >> 16;
  return (x & 0xFFFF) / 65535.0;
}

Path _hexPath(Offset c, double r) {
  final p = Path();
  for (var i = 0; i < 6; i++) {
    final a = (60.0 * i - 30) * math.pi / 180;
    final pt = c + Offset(r * math.cos(a), r * math.sin(a));
    if (i == 0) {
      p.moveTo(pt.dx, pt.dy);
    } else {
      p.lineTo(pt.dx, pt.dy);
    }
  }
  return p..close();
}

class BoardPainter extends CustomPainter {
  BoardPainter(this.game, this.fx) : super(repaint: fx.tick);

  final GameController game;
  final FxLayer fx;

  @override
  bool shouldRepaint(covariant BoardPainter old) => true;

  @override
  void paint(Canvas canvas, Size size) {
    final layout = BoardLayout.fit(size);
    _background(canvas, size);

    canvas.save();
    canvas.translate(
      fx.shakeOffset.dx * layout.size * 0.5,
      fx.shakeOffset.dy * layout.size * 0.5,
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
      for (final u in game.units) _Drawable(u, u.vr, 1, 1, 0),
      for (final g in fx.ghosts)
        _Drawable(
          g.unit,
          g.unit.vr,
          1 - g.t,
          1 - g.t * g.t,
          g.spin ? g.t * math.pi * 3 : 0,
        ),
    ]..sort((a, b) => a.sortKey.compareTo(b.sortKey));
    for (final d in drawables) {
      _unit(canvas, layout, d);
    }

    _projectiles(canvas, layout);
    _particles(canvas, layout);
    _floatTexts(canvas, layout);
    canvas.restore();
  }

  // ───────────────────────── background ─────────────────────────

  void _background(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF12231F), Color(0xFF1E3B34)],
        ).createShader(rect),
    );
    final paint = Paint();
    for (var i = 0; i < 28; i++) {
      final speed = 6 + _hash(i, 3, 3) * 10;
      final x =
          (_hash(i, 1, 1) * size.width + math.sin(fx.time * 0.5 + i) * 18) %
          size.width;
      final y =
          size.height -
          ((fx.time * speed + _hash(i, 2, 2) * size.height) % size.height);
      final tw = 0.5 + 0.5 * math.sin(fx.time * 2 + i * 1.7);
      paint.color = const Color(0xFFD8FF9E).withValues(alpha: 0.12 + 0.25 * tw);
      canvas.drawCircle(Offset(x, y), 1.2 + _hash(i, 4, 4) * 2, paint);
    }
  }

  // ───────────────────────── tiles ─────────────────────────

  void _tile(Canvas canvas, BoardLayout L, Hex h, Tile t) {
    final intro = ((fx.introTime - t.introDelay) / 0.7).clamp(0.0, 1.0);
    if (intro <= 0) return;
    final e = Curves.easeOutBack.transform(intro);
    var c = L.hexCenter(h);
    c += Offset(0, (1 - e) * -L.size * 6);
    final r = L.size * 0.97;
    final depth = L.size * 0.2;
    final v = _hash(h.q, h.r, 7);

    Color top;
    Color side;
    switch (t.terrain) {
      case Terrain.water:
        top = Color.lerp(const Color(0xFF4DA3C7), const Color(0xFF5CB4D6), v)!;
        side = const Color(0xFF2F6F8C);
      case Terrain.lava:
        top = const Color(0xFF3A1F1C);
        side = const Color(0xFF241210);
      case Terrain.forest:
        top = Color.lerp(const Color(0xFF6FA672), const Color(0xFF7DB37E), v)!;
        side = const Color(0xFF3F6F47);
      case Terrain.mountain:
        top = Color.lerp(const Color(0xFF8E9096), const Color(0xFF9DA0A6), v)!;
        side = const Color(0xFF55585E);
      case Terrain.crystal:
      case Terrain.grass:
        top = Color.lerp(const Color(0xFF9CC79A), const Color(0xFFAAD2A5), v)!;
        side = const Color(0xFF5A8A5E);
    }
    if (t.fire > 0) top = Color.lerp(top, const Color(0xFF5B3A2A), 0.55)!;

    final sunk = t.terrain == Terrain.water || t.terrain == Terrain.lava;
    final cTop = sunk ? c + Offset(0, depth * 0.45) : c;
    canvas.drawPath(_hexPath(c + Offset(0, depth), r), Paint()..color = side);
    canvas.drawPath(_hexPath(cTop, r), Paint()..color = top);

    switch (t.terrain) {
      case Terrain.water:
        _waves(canvas, L, cTop, r, h);
      case Terrain.lava:
        _lava(canvas, L, cTop, r, h);
      case Terrain.forest:
        _trees(canvas, L, cTop, h);
      case Terrain.crystal:
        _crystal(canvas, L, cTop, h);
      case Terrain.mountain:
        _peaks(canvas, L, cTop, h);
      case Terrain.grass:
        _grassTufts(canvas, L, cTop, h);
    }

    canvas.drawPath(
      _hexPath(cTop, r),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0x40000000),
    );
  }

  void _grassTufts(Canvas canvas, BoardLayout L, Offset c, Hex h) {
    final p = Paint()
      ..color = const Color(0x2E2F6B3F)
      ..strokeWidth = L.size * 0.05
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final ox = (_hash(h.q, h.r, 10 + i) - 0.5) * L.size * 1.1;
      final oy = (_hash(h.q, h.r, 20 + i) - 0.5) * L.size * 0.9;
      final b = c + Offset(ox, oy);
      canvas.drawLine(b, b + Offset(-L.size * 0.06, -L.size * 0.14), p);
      canvas.drawLine(b, b + Offset(L.size * 0.06, -L.size * 0.14), p);
    }
  }

  void _peaks(Canvas canvas, BoardLayout L, Offset c, Hex h) {
    final s = L.size;
    void peak(Offset base, double w, double hgt) {
      final apex = base + Offset(0, -hgt);
      canvas.drawPath(
        Path()
          ..moveTo(base.dx - w, base.dy)
          ..lineTo(apex.dx, apex.dy)
          ..lineTo(base.dx + w, base.dy)
          ..close(),
        Paint()..color = const Color(0xFF6A6D74),
      );
      canvas.drawPath(
        Path()
          ..moveTo(apex.dx, apex.dy)
          ..lineTo(base.dx + w, base.dy)
          ..lineTo(base.dx + w * 0.1, base.dy)
          ..close(),
        Paint()..color = const Color(0xFF50535A),
      );
      canvas.drawPath(
        Path()
          ..moveTo(apex.dx, apex.dy)
          ..lineTo(apex.dx - w * 0.28, apex.dy + hgt * 0.28)
          ..lineTo(apex.dx + w * 0.28, apex.dy + hgt * 0.28)
          ..close(),
        Paint()..color = const Color(0xFFF2F4F7),
      );
    }

    final j = _hash(h.q, h.r, 41) * 0.1;
    peak(c + Offset(-s * 0.26, s * 0.2), s * 0.38, s * (0.62 + j));
    peak(c + Offset(s * 0.26, s * 0.24), s * 0.34, s * (0.5 + j));
    peak(c + Offset(0, s * 0.3), s * 0.3, s * 0.38);
  }

  void _trees(Canvas canvas, BoardLayout L, Offset c, Hex h) {
    final s = L.size;
    const spots = [Offset(-0.32, 0.12), Offset(0.3, 0.16), Offset(0.0, -0.2)];
    for (var i = 0; i < spots.length; i++) {
      final base = c + spots[i] * s;
      final sway = math.sin(fx.time * 1.6 + h.q + h.r * 1.3 + i) * s * 0.035;
      final sc = 0.85 + _hash(h.q, h.r, 30 + i) * 0.3;
      canvas.drawRect(
        Rect.fromCenter(
          center: base + Offset(0, -s * 0.02),
          width: s * 0.1,
          height: s * 0.16,
        ),
        Paint()..color = const Color(0xFF5D4037),
      );
      for (var layer = 0; layer < 2; layer++) {
        final w = s * (0.34 - layer * 0.08) * sc;
        final hgt = s * 0.34 * sc;
        final y0 = base.dy - s * 0.04 - layer * s * 0.2 * sc;
        final apex = Offset(base.dx + sway * (1 + layer), y0 - hgt);
        final path = Path()
          ..moveTo(base.dx - w, y0)
          ..lineTo(apex.dx, apex.dy)
          ..lineTo(base.dx + w, y0)
          ..close();
        canvas.drawPath(
          path,
          Paint()
            ..color = layer == 0
                ? const Color(0xFF2E6B3E)
                : const Color(0xFF3E8A50),
        );
      }
    }
  }

  void _waves(Canvas canvas, BoardLayout L, Offset c, double r, Hex h) {
    canvas.save();
    canvas.clipPath(_hexPath(c, r));
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = L.size * 0.05
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x66FFFFFF);
    for (var k = -1; k <= 1; k++) {
      final path = Path();
      final y = c.dy + k * L.size * 0.38;
      final phase = fx.time * 2 + h.q + h.r * 2 + k;
      for (var i = 0; i <= 12; i++) {
        final x = c.dx - L.size + i * (L.size * 2 / 12);
        final yy = y + math.sin(phase + i * 0.9) * L.size * 0.06;
        if (i == 0) {
          path.moveTo(x, yy);
        } else {
          path.lineTo(x, yy);
        }
      }
      canvas.drawPath(path, p..color = Color(k == 0 ? 0x55FFFFFF : 0x33FFFFFF));
    }
    canvas.restore();
  }

  void _lava(Canvas canvas, BoardLayout L, Offset c, double r, Hex h) {
    final pulse = 0.5 + 0.5 * math.sin(fx.time * 2.2 + h.q * 1.1 + h.r);
    final glow = Paint()
      ..color = Color.lerp(
        const Color(0xFFFF5A1F),
        const Color(0xFFFFB02E),
        pulse,
      )!.withValues(alpha: 0.35 + 0.25 * pulse)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, L.size * 0.35);
    canvas.drawCircle(c, L.size * 0.7, glow);
    canvas.save();
    canvas.clipPath(_hexPath(c, r));
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color.lerp(
              const Color(0xFFFFC83D),
              const Color(0xFFFFE066),
              pulse,
            )!,
            const Color(0xFFFF6A2B),
            const Color(0xFFB3261E),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
    );
    final crust = Paint()..color = const Color(0x553A1F1C);
    for (var i = 0; i < 3; i++) {
      final o = Offset(
        (_hash(h.q, h.r, 40 + i) - 0.5) * L.size,
        (_hash(h.q, h.r, 50 + i) - 0.5) * L.size * 0.8,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: c + o,
          width: L.size * 0.4,
          height: L.size * 0.22,
        ),
        crust,
      );
    }
    final bubble = Paint()..color = const Color(0xCCFFE29A);
    for (var i = 0; i < 2; i++) {
      final f = (fx.time * 0.6 + _hash(h.q, h.r, 60 + i)) % 1.0;
      final o = Offset(
        (_hash(h.q, h.r, 70 + i) - 0.5) * L.size * 0.9,
        L.size * 0.3 - f * L.size * 0.6,
      );
      canvas.drawCircle(c + o, L.size * 0.06 * (1 - f * 0.4), bubble);
    }
    canvas.restore();
  }

  void _crystal(Canvas canvas, BoardLayout L, Offset c, Hex h) {
    final s = L.size;
    final bob = math.sin(fx.time * 2.2 + h.q) * s * 0.06;
    final center = c + Offset(0, -s * 0.28 + bob);
    canvas.drawCircle(
      center,
      s * 0.55,
      Paint()
        ..color = const Color(0x66C58BFF)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.25),
    );
    Offset p(double x, double y) => center + Offset(x * s, y * s);
    final left = Path()
      ..moveTo(p(0, -0.42).dx, p(0, -0.42).dy)
      ..lineTo(p(-0.26, -0.08).dx, p(-0.26, -0.08).dy)
      ..lineTo(p(0, 0.34).dx, p(0, 0.34).dy)
      ..close();
    final right = Path()
      ..moveTo(p(0, -0.42).dx, p(0, -0.42).dy)
      ..lineTo(p(0.26, -0.08).dx, p(0.26, -0.08).dy)
      ..lineTo(p(0, 0.34).dx, p(0, 0.34).dy)
      ..close();
    canvas.drawPath(left, Paint()..color = const Color(0xFFB88CFF));
    canvas.drawPath(right, Paint()..color = const Color(0xFF8E5BE8));
    canvas.drawLine(
      p(-0.26, -0.08),
      p(0.26, -0.08),
      Paint()
        ..color = const Color(0x88FFFFFF)
        ..strokeWidth = s * 0.03,
    );
    final tw = (math.sin(fx.time * 4 + h.r) * 0.5 + 0.5);
    final sp = Paint()
      ..color = Colors.white.withValues(alpha: tw)
      ..strokeWidth = s * 0.04
      ..strokeCap = StrokeCap.round;
    final sc = p(0.2, -0.3);
    final k = s * 0.1 * tw;
    canvas.drawLine(sc + Offset(-k, 0), sc + Offset(k, 0), sp);
    canvas.drawLine(sc + Offset(0, -k), sc + Offset(0, k), sp);
  }

  void _flames(Canvas canvas, BoardLayout L, Hex h) {
    final c = L.hexCenter(h);
    final s = L.size;
    for (var i = 0; i < 4; i++) {
      final ph = fx.time * 9 + i * 1.9 + h.q * 3;
      final ox = (i - 1.5) * s * 0.28 + math.sin(ph * 0.7) * s * 0.04;
      final base = c + Offset(ox, s * 0.12 - (i.isOdd ? s * 0.08 : 0));
      final hgt =
          s * (0.38 + 0.12 * math.sin(ph)) * (i == 1 || i == 2 ? 1.2 : 0.9);
      final w = s * 0.16;
      final outer = Path()
        ..moveTo(base.dx - w, base.dy)
        ..quadraticBezierTo(
          base.dx - w * 0.6,
          base.dy - hgt * 0.5,
          base.dx + math.sin(ph) * s * 0.05,
          base.dy - hgt,
        )
        ..quadraticBezierTo(
          base.dx + w * 0.6,
          base.dy - hgt * 0.5,
          base.dx + w,
          base.dy,
        )
        ..close();
      canvas.drawPath(outer, Paint()..color = const Color(0xFFFF6B2B));
      canvas.drawPath(
        Path()
          ..moveTo(base.dx - w * 0.5, base.dy)
          ..quadraticBezierTo(
            base.dx,
            base.dy - hgt * 0.8,
            base.dx + w * 0.5,
            base.dy,
          )
          ..close(),
        Paint()..color = const Color(0xFFFFD04A),
      );
    }
  }

  // ───────────────────────── highlights ─────────────────────────

  /// Pulsing ring and a bouncing finger over the hexes a lesson points at.
  void _coachFocus(Canvas canvas, BoardLayout L) {
    final step = game.coachStep;
    if (step == null) return;
    final pulse = 0.5 + 0.5 * math.sin(fx.time * 6);
    for (final h in step.hexes) {
      if (!game.tiles.containsKey(h)) continue;
      final c = L.hexCenter(h);
      final path = _hexPath(c, L.size * (0.95 + 0.08 * pulse));
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = const Color(
            0xFFFFE082,
          ).withValues(alpha: 0.6 + 0.4 * pulse),
      );
      final hand = _emoji('👇', L.size * 0.9);
      final bob = math.sin(fx.time * 5) * L.size * 0.12;
      hand.paint(
        canvas,
        c + Offset(-hand.width / 2, -L.size * 2.0 - hand.height / 2 + bob),
      );
    }
  }

  void _centreMark(Canvas canvas, BoardLayout L) {
    final pulse = 0.5 + 0.5 * math.sin(fx.time * 3);
    final c = L.hexCenter(GameController.centre);
    final path = _hexPath(c, L.size * (0.82 + 0.04 * pulse));
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFFE082).withValues(alpha: 0.12 + 0.1 * pulse),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = const Color(0xFFFFE082).withValues(alpha: 0.8),
    );
    if (game.unitAt(GameController.centre) == null) {
      final star = _emoji('⭐', L.size * 0.8);
      star.paint(canvas, c - Offset(star.width / 2, star.height / 2));
    }
  }

  void _highlights(Canvas canvas, BoardLayout L) {
    final pulse = 0.5 + 0.5 * math.sin(fx.time * 5);
    void hl(Hex h, Color c, {double fill = 0.3}) {
      final center = L.hexCenter(h);
      final path = _hexPath(center, L.size * (0.88 + 0.03 * pulse));
      canvas.drawPath(
        path,
        Paint()..color = c.withValues(alpha: fill + 0.15 * pulse),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..color = c.withValues(alpha: 0.9),
      );
    }

    game.moveTargets.forEach((h, _) => hl(h, const Color(0xFF39E673)));
    for (final h in game.attackTargets) {
      hl(h, const Color(0xFFFF4D4D), fill: 0.35);
    }
    for (final h in game.cardTargets) {
      hl(h, const Color(0xFFFFD54A), fill: 0.25);
    }
    final sel = game.selected;
    if (sel != null) {
      final c = L.hexCenter(sel.pos);
      canvas.drawPath(
        _hexPath(c, L.size * 0.92),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.white.withValues(alpha: 0.6 + 0.4 * pulse),
      );
    }
  }

  // ───────────────────────── units ─────────────────────────

  void _unit(Canvas canvas, BoardLayout L, _Drawable d) {
    final u = d.unit;
    final s = L.size;
    final ease = Curves.easeOutBack.transform(u.spawn.clamp(0.0, 1.0));
    final scale = ease * d.scale;
    if (scale <= 0.01) return;

    var ground = L.toPixel(u.vq, u.vr);
    if (u.lunge > 0 && u.lungeTo != null) {
      final to = L.hexCenter(u.lungeTo!);
      final v = to - ground;
      if (v.distance > 0) {
        ground += v / v.distance * s * 0.65 * math.sin(math.pi * u.lunge);
      }
    }
    final bob = u.hop > 0 ? 0.0 : math.sin(fx.time * 2.6 + u.id) * 0.04;
    final center = ground + Offset(0, -s * (0.42 + u.hop + bob));
    final R = s * 0.52 * scale;

    // shadow
    canvas.drawOval(
      Rect.fromCenter(
        center: ground + Offset(0, s * 0.16),
        width: R * 1.7,
        height: R * 0.6,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.28 * d.alpha),
    );

    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (d.rotation != 0) canvas.rotate(d.rotation);

    final isPlayer = u.team == Team.player;
    var c1 = isPlayer ? const Color(0xFF6FA3FF) : const Color(0xFFFF7A7A);
    var c2 = isPlayer ? const Color(0xFF2C54C7) : const Color(0xFFB92D3B);
    final exhausted =
        u.team == game.viewTeam && game.isPlayerTurn && !u.canMove && !u.canAct;
    if (exhausted) {
      c1 = Color.lerp(c1, const Color(0xFF6B7280), 0.6)!;
      c2 = Color.lerp(c2, const Color(0xFF374151), 0.6)!;
    }

    if (u.shield > 0) {
      final pulse = 0.5 + 0.5 * math.sin(fx.time * 5 + u.id);
      canvas.drawCircle(
        Offset.zero,
        R * (1.32 + 0.05 * pulse),
        Paint()..color = const Color(0x3380D8FF),
      );
      canvas.drawCircle(
        Offset.zero,
        R * (1.32 + 0.05 * pulse),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = const Color(0xCC80D8FF),
      );
    }

    final body = Rect.fromCircle(center: Offset.zero, radius: R);
    canvas.drawCircle(
      Offset.zero,
      R,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [c1, c2],
        ).createShader(body),
    );
    canvas.drawCircle(
      Offset.zero,
      R,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = u.isHero ? 3 : 2
        ..color = u.isHero
            ? const Color(0xFFFFD54F)
            : Colors.white.withValues(alpha: 0.85),
    );

    final tp = _emoji(u.emoji, R * 1.15);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));

    if (u.isHero) {
      final crown = _emoji('👑', R * 0.7);
      crown.paint(canvas, Offset(-crown.width / 2 - R * 0.55, -R * 1.05));
    }

    if (u.flash > 0) {
      canvas.drawCircle(
        Offset.zero,
        R,
        Paint()..color = Colors.white.withValues(alpha: u.flash * 0.85),
      );
    }

    if (u == game.selected) {
      final pulse = 0.5 + 0.5 * math.sin(fx.time * 6);
      canvas.drawCircle(
        Offset.zero,
        R + 3 + 2 * pulse,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.white,
      );
    }
    canvas.restore();

    // HP pips
    if (d.alpha > 0.5) {
      final maxHp = u.stats.maxHp;
      final pipW = math.min(s * 0.14, (s * 1.1) / maxHp);
      final total = pipW * maxHp;
      final origin = center + Offset(-total / 2, -R - s * 0.2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(origin.dx - 2, origin.dy - 2, total + 4, s * 0.14 + 4),
          const Radius.circular(4),
        ),
        Paint()..color = const Color(0xAA000000),
      );
      for (var i = 0; i < maxHp; i++) {
        final filled = i < u.hp;
        final frac = u.hp / maxHp;
        final col = filled
            ? Color.lerp(
                const Color(0xFFFF5252),
                const Color(0xFF69F0AE),
                frac,
              )!
            : const Color(0xFF3B3B3B);
        canvas.drawRect(
          Rect.fromLTWH(
            origin.dx + i * pipW + 0.5,
            origin.dy,
            pipW - 1,
            s * 0.14,
          ),
          Paint()..color = col,
        );
      }
      // Ready indicators for the player's units.
      if (u.team == game.viewTeam && game.isPlayerTurn) {
        final dot = Paint();
        final p0 = center + Offset(R * 0.9, R * 0.8);
        if (u.canMove) {
          canvas.drawCircle(p0, s * 0.07, dot..color = const Color(0xFF39E673));
        }
        if (u.canAct) {
          canvas.drawCircle(
            p0 + Offset(-s * 0.18, 0),
            s * 0.07,
            dot..color = const Color(0xFFFFB142),
          );
        }
      }
    }
  }

  // ───────────────────────── fx ─────────────────────────

  void _projectiles(Canvas canvas, BoardLayout L) {
    for (final pr in fx.projectiles) {
      final p = L.unitToPixel(fx.projectilePos(pr));
      final r = L.size * (pr.radius + 0.08);
      canvas.drawCircle(
        p,
        r * 2.2,
        Paint()
          ..color = pr.color.withValues(alpha: 0.4)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r),
      );
      canvas.drawCircle(p, r, Paint()..color = pr.color);
      canvas.drawCircle(p, r * 0.5, Paint()..color = Colors.white);
    }
  }

  void _particles(Canvas canvas, BoardLayout L) {
    final paint = Paint();
    for (final p in fx.particles) {
      final pos = L.unitToPixel(Offset(p.x, p.y));
      final a = (1 - p.t).clamp(0.0, 1.0);
      if (p.ring) {
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * a + 0.5
          ..color = p.color.withValues(alpha: a);
        final rad = L.size * p.size * Curves.easeOut.transform(p.t);
        canvas.drawOval(
          Rect.fromCenter(center: pos, width: rad * 2, height: rad * 1.2),
          paint,
        );
      } else {
        paint
          ..style = PaintingStyle.fill
          ..color = p.color.withValues(alpha: a);
        canvas.drawCircle(pos, L.size * p.size * (0.5 + 0.5 * a), paint);
      }
    }
  }

  void _floatTexts(Canvas canvas, BoardLayout L) {
    for (final t in fx.texts) {
      final pos = L.unitToPixel(Offset(t.x, t.y - t.t * 0.9));
      final a = t.t < 0.6 ? 1.0 : (1 - (t.t - 0.6) / 0.4);
      final pop = 1 + 0.45 * (1 - (t.t * 6).clamp(0.0, 1.0));
      final fs = L.size * 0.5 * pop;
      final fill = TextPainter(
        text: TextSpan(
          text: t.text,
          style: TextStyle(
            fontSize: fs,
            fontWeight: FontWeight.w900,
            color: t.color.withValues(alpha: a),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final outline = TextPainter(
        text: TextSpan(
          text: t.text,
          style: TextStyle(
            fontSize: fs,
            fontWeight: FontWeight.w900,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.5
              ..color = Colors.black.withValues(alpha: a * 0.8),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final o = pos - Offset(fill.width / 2, fill.height / 2);
      outline.paint(canvas, o);
      fill.paint(canvas, o);
    }
  }
}

class _Drawable {
  _Drawable(this.unit, this.sortKey, this.alpha, this.scale, this.rotation);
  final Unit unit;
  final double sortKey;
  final double alpha;
  final double scale;
  final double rotation;
}
