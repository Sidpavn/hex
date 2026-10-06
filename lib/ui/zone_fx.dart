import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/models.dart';
import 'pixel/pixel_assets.dart';
import 'pixel/terrain_draw.dart';

/// Visual effects for exploration combat, all in world space (art pixels).
/// The simulation resolves a turn instantly; these play it back so you can
/// see who hit whom: swings, arrows in flight, spells, sparks, deaths.
///
/// Everything is drawn as whole art-pixel squares, so it stays on the pixel
/// grid, and each effect has a `delay` so one turn can play out in order.

enum ProjectileKind { arrow, bolt, fireball }

class _Timed {
  _Timed(this.delay, this.run);

  double delay;
  final VoidCallback run;
}

class _Spark {
  _Spark(this.pos, this.vel, this.life, this.color, this.size, this.delay);

  Offset pos;
  Offset vel;
  final double life;
  final Color color;
  final int size;
  double delay;
  double age = 0;
}

class _Projectile {
  _Projectile(this.from, this.to, this.kind, this.delay, this.dur);

  final Offset from;
  final Offset to;
  final ProjectileKind kind;
  double delay;
  final double dur;
  double age = 0;
}

class _Slash {
  _Slash(this.centre, this.angle, this.delay, this.dur, this.big);

  final Offset centre;

  /// Direction of the blow, in radians.
  final double angle;
  double delay;
  final double dur;
  final bool big;
  double age = 0;
}

class _Ring {
  _Ring(this.pos, this.maxRadius, this.color, this.delay, this.dur);

  final Offset pos;
  final double maxRadius;
  final Color color;
  double delay;
  final double dur;
  double age = 0;
}

/// A creature that has just died, held on screen until its death blow lands,
/// then blinked and sunk away.
class _Ghost {
  _Ghost(this.type, this.team, this.pos, this.hold, this.dur);

  final UnitType type;
  final Team team;
  final Offset pos;
  final double hold;
  final double dur;
  double age = 0;
}

class ZoneFx {
  final _timed = <_Timed>[];
  final _sparks = <_Spark>[];
  final _projectiles = <_Projectile>[];
  final _slashes = <_Slash>[];
  final _rings = <_Ring>[];
  final _ghosts = <_Ghost>[];
  final _rng = math.Random();

  /// Screen shake, 0 to 1. Decays on its own.
  double shake = 0;

  bool get busy =>
      _timed.isNotEmpty ||
      _sparks.isNotEmpty ||
      _projectiles.isNotEmpty ||
      _slashes.isNotEmpty ||
      _rings.isNotEmpty ||
      _ghosts.isNotEmpty;

  void clear() {
    _timed.clear();
    _sparks.clear();
    _projectiles.clear();
    _slashes.clear();
    _rings.clear();
    _ghosts.clear();
    shake = 0;
  }

  // ───────────────────────── spawning ─────────────────────────

  /// Runs [run] after [delay] seconds (state changes that belong to the
  /// moment a blow lands: flashes, kicks, floating numbers).
  void at(double delay, VoidCallback run) => _timed.add(_Timed(delay, run));

  void projectile(
    Offset from,
    Offset to,
    ProjectileKind kind,
    double delay,
    double dur,
  ) => _projectiles.add(_Projectile(from, to, kind, delay, dur));

  void slash(Offset centre, double angle, double delay, {bool big = false}) =>
      _slashes.add(_Slash(centre, angle, delay, big ? 0.24 : 0.18, big));

  void ring(
    Offset pos,
    double maxRadius,
    Color color,
    double delay, [
    double dur = 0.3,
  ]) => _rings.add(_Ring(pos, maxRadius, color, delay, dur));

  void ghost(UnitType type, Team team, Offset pos, double hold) =>
      _ghosts.add(_Ghost(type, team, pos, hold, 0.5));

  /// A burst of [count] pixels flying out from [pos].
  void burst(
    Offset pos,
    List<Color> colors,
    double delay, {
    int count = 9,
    double speed = 70,
    double life = 0.38,
    int size = 2,
  }) {
    for (var i = 0; i < count; i++) {
      final a = _rng.nextDouble() * math.pi * 2;
      final v = speed * (0.4 + _rng.nextDouble() * 0.7);
      _sparks.add(
        _Spark(
          pos,
          Offset(math.cos(a) * v, math.sin(a) * v * 0.8 - speed * 0.25),
          life * (0.7 + _rng.nextDouble() * 0.5),
          colors[_rng.nextInt(colors.length)],
          size,
          delay,
        ),
      );
    }
  }

  static const _gravity = 140.0;

  // ───────────────────────── update ─────────────────────────

  void update(double dt) {
    shake = math.max(0, shake - dt * 3.5);
    for (final t in List.of(_timed)) {
      t.delay -= dt;
      if (t.delay <= 0) {
        _timed.remove(t);
        t.run();
      }
    }
    for (final s in List.of(_sparks)) {
      if (s.delay > 0) {
        s.delay -= dt;
        continue;
      }
      s.age += dt;
      s.pos += s.vel * dt;
      s.vel = Offset(s.vel.dx * (1 - 2.0 * dt), s.vel.dy + _gravity * dt);
      if (s.age >= s.life) _sparks.remove(s);
    }
    for (final p in List.of(_projectiles)) {
      if (p.delay > 0) {
        p.delay -= dt;
        continue;
      }
      p.age += dt;
      if (p.age >= p.dur) _projectiles.remove(p);
    }
    for (final s in List.of(_slashes)) {
      if (s.delay > 0) {
        s.delay -= dt;
        continue;
      }
      s.age += dt;
      if (s.age >= s.dur) _slashes.remove(s);
    }
    for (final r in List.of(_rings)) {
      if (r.delay > 0) {
        r.delay -= dt;
        continue;
      }
      r.age += dt;
      if (r.age >= r.dur) _rings.remove(r);
    }
    for (final g in List.of(_ghosts)) {
      g.age += dt;
      if (g.age >= g.hold + g.dur) _ghosts.remove(g);
    }
  }

  // ───────────────────────── drawing ─────────────────────────

  /// [toScreen] maps world art pixels to logical screen pixels, [scale] is
  /// logical pixels per art pixel.
  void paint(
    Canvas canvas,
    TerrainDraw td,
    PixelAssets art,
    Offset Function(Offset world) toScreen,
    double scale,
  ) {
    void px(Offset world, int w, int h, Color c) {
      // Whole art pixels, so every spark lands on the grid.
      final p = Offset(world.dx.roundToDouble(), world.dy.roundToDouble());
      td.rect(canvas, toScreen(p), 0, 0, w, h, scale, c);
    }

    for (final g in _ghosts) {
      final dying = g.age - g.hold;
      if (dying > 0 && (dying * 28).floor().isOdd) continue;
      final ground = toScreen(g.pos);
      final img = art.unit(g.type, g.team, 'idle0');
      final sink = dying > 0 ? (dying * 10).floor().toDouble() : 0.0;
      td.blit(
        canvas,
        img,
        ground,
        -(img.width / 2).floorToDouble(),
        6 - img.height + sink,
        scale,
        filter: dying > 0 && dying < 0.1
            ? const ColorFilter.mode(Colors.white, BlendMode.srcATop)
            : null,
      );
    }

    for (final r in _rings) {
      if (r.delay > 0) continue;
      final t = (r.age / r.dur).clamp(0.0, 1.0);
      final rad = r.maxRadius * Curves.easeOut.transform(t);
      final size = t < 0.5 ? 2 : 1;
      for (var i = 0; i < 14; i++) {
        final a = i * math.pi * 2 / 14;
        px(
          r.pos + Offset(math.cos(a) * rad, math.sin(a) * rad * 0.7),
          size,
          size,
          r.color,
        );
      }
    }

    for (final s in _slashes) {
      if (s.delay > 0) continue;
      final t = (s.age / s.dur).clamp(0.0, 1.0);
      final sweep = s.big ? 2.2 : 1.7;
      final radius = s.big ? 13.0 : 10.0;
      final start = s.angle - sweep / 2;
      for (var k = 0; k < 9; k++) {
        final f = t - k * 0.07;
        if (f < 0) continue;
        final a = start + sweep * f;
        final col = k == 0
            ? Colors.white
            : k < 3
            ? const Color(0xFFFFF1A0)
            : const Color(0xFFF4C846);
        px(
          s.centre + Offset(math.cos(a) * radius, math.sin(a) * radius * 0.8),
          k < 3 ? 2 : 1,
          k < 3 ? 2 : 1,
          col,
        );
      }
    }

    for (final p in _projectiles) {
      if (p.delay > 0) continue;
      final t = (p.age / p.dur).clamp(0.0, 1.0);
      final lift = p.kind == ProjectileKind.fireball
          ? -math.sin(math.pi * t) * 16
          : 0.0;
      final head = Offset.lerp(p.from, p.to, t)! + Offset(0, lift);
      final dir = (p.to - p.from);
      final len = math.max(1.0, dir.distance);
      final u = dir / len;
      switch (p.kind) {
        case ProjectileKind.arrow:
          // Fletching, shaft, then a bright head.
          for (var i = 0; i < 7; i++) {
            px(
              head - u * i.toDouble(),
              1,
              1,
              i == 0
                  ? Colors.white
                  : i == 6
                  ? const Color(0xFFE25454)
                  : const Color(0xFFBE8246),
            );
          }
          px(head, 2, 1, Colors.white);
        case ProjectileKind.bolt:
          for (var i = 0; i < 5; i++) {
            px(
              head - u * (i * 2.5),
              i < 2 ? 3 : 2,
              i < 2 ? 3 : 2,
              i == 0
                  ? Colors.white
                  : i < 3
                  ? const Color(0xFFC090F0)
                  : const Color(0xFF643C96),
            );
          }
        case ProjectileKind.fireball:
          for (var i = 0; i < 6; i++) {
            final c = i == 0
                ? const Color(0xFFFFE08A)
                : i < 3
                ? const Color(0xFFFA9632)
                : const Color(0xFFE6503C);
            final prev = Offset.lerp(
              p.from,
              p.to,
              math.max(0.0, t - i * 0.05),
            )!;
            final prevLift = p.kind == ProjectileKind.fireball
                ? -math.sin(math.pi * math.max(0.0, t - i * 0.05)) * 16
                : 0.0;
            px(prev + Offset(0, prevLift), i < 2 ? 4 : 3, i < 2 ? 4 : 3, c);
          }
      }
    }

    for (final s in _sparks) {
      if (s.delay > 0) continue;
      final fade = 1 - s.age / s.life;
      px(
        s.pos,
        fade > 0.5 ? s.size : math.max(1, s.size - 1),
        fade > 0.5 ? s.size : math.max(1, s.size - 1),
        s.color,
      );
    }
  }
}
