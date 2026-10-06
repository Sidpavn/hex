import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../game/game_controller.dart';
import '../game/hex.dart';
import '../game/models.dart';

/// Particles live in "unit space" (hex circumradius = 1, origin = hex 0,0).
class Particle {
  Particle(
    this.x,
    this.y,
    this.vx,
    this.vy,
    this.life,
    this.color,
    this.size, {
    this.gravity = 0,
    this.ring = false,
  }) : maxLife = life;

  double x, y, vx, vy, life;
  final double maxLife;
  final Color color;
  final double size;
  final double gravity;
  final bool ring;

  double get t => 1 - (life / maxLife).clamp(0.0, 1.0);
}

class FloatText {
  FloatText(this.x, this.y, this.text, this.color);
  final double x;
  final double y;
  final String text;
  final Color color;
  double t = 0;
}

class Projectile {
  Projectile(this.from, this.to, this.color, this.radius, this.dur);
  final Offset from;
  final Offset to;
  final Color color;
  final double radius;
  final double dur;
  double t = 0;
}

class Ghost {
  Ghost(this.unit, this.spin);
  final Unit unit;
  final bool spin;
  double t = 0;
}

class _Pending {
  _Pending(this.delay, this.event);
  double delay;
  final FxEvent event;
}

/// Owns every transient animation: unit tweening, particles, floating text,
/// projectiles, screen shake. Driven by a Ticker in the view.
class FxLayer {
  FxLayer(this.game);

  final GameController game;
  final ValueNotifier<int> tick = ValueNotifier(0);
  final _rng = math.Random();

  double time = 0;
  double introTime = 0;
  double shake = 0;
  Offset shakeOffset = Offset.zero;

  final List<Particle> particles = [];
  final List<FloatText> texts = [];
  final List<Projectile> projectiles = [];
  final List<Ghost> ghosts = [];
  final List<_Pending> _pending = [];

  void Function(String text)? onBanner;

  void reset() {
    introTime = 0;
    shake = 0;
    particles.clear();
    texts.clear();
    projectiles.clear();
    ghosts.clear();
    _pending.clear();
  }

  void handle(FxEvent e) {
    if (e.delay <= 0) {
      _apply(e);
    } else {
      _pending.add(_Pending(e.delay, e));
    }
  }

  // ───────────────────────── update ─────────────────────────

  void update(double dt) {
    time += dt;
    introTime += dt;

    for (final p in List.of(_pending)) {
      p.delay -= dt;
      if (p.delay <= 0) {
        _pending.remove(p);
        _apply(p.event);
      }
    }

    for (final u in game.units) {
      stepUnit(u, dt);
    }

    for (final g in List.of(ghosts)) {
      g.t += dt / 0.7;
      stepUnit(g.unit, dt, ghost: true);
      if (g.t >= 1) ghosts.remove(g);
    }

    for (final p in List.of(particles)) {
      p.life -= dt;
      if (p.life <= 0) {
        particles.remove(p);
        continue;
      }
      p.vy += p.gravity * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
    }

    for (final t in List.of(texts)) {
      t.t += dt / 1.1;
      if (t.t >= 1) texts.remove(t);
    }

    for (final pr in List.of(projectiles)) {
      pr.t += dt / pr.dur;
      final pos = projectilePos(pr);
      _spark(pos, pr.color, pr.radius);
      if (pr.t >= 1) projectiles.remove(pr);
    }

    // Embers rising from burning tiles.
    for (final e in game.tiles.entries) {
      if (e.value.fire > 0 && _rng.nextDouble() < dt * 7) {
        final c = e.key.toUnit();
        particles.add(
          Particle(
            c.dx + (_rng.nextDouble() - 0.5) * 1.0,
            c.dy + (_rng.nextDouble() - 0.5) * 0.4,
            (_rng.nextDouble() - 0.5) * 0.3,
            -0.8 - _rng.nextDouble() * 0.8,
            0.6 + _rng.nextDouble() * 0.5,
            _rng.nextBool() ? const Color(0xFFFFB142) : const Color(0xFFFF6B3D),
            0.05 + _rng.nextDouble() * 0.05,
          ),
        );
      }
    }

    if (shake > 0.01) {
      shake = math.max(0, shake - dt * 2.4);
      shakeOffset = Offset(
        (_rng.nextDouble() - 0.5) * shake,
        (_rng.nextDouble() - 0.5) * shake,
      );
    } else {
      shake = 0;
      shakeOffset = Offset.zero;
    }

    tick.value++;
  }

  Offset projectilePos(Projectile pr) {
    final t = Curves0.easeInOut(pr.t.clamp(0.0, 1.0));
    final base = Offset.lerp(pr.from, pr.to, t)!;
    return base - Offset(0, math.sin(math.pi * t) * 1.1 + 0.4);
  }

  /// Glide a unit's drawn position toward its logical hex.
  void stepUnit(Unit u, double dt, {bool ghost = false}) {
    final target = u.path.isNotEmpty ? u.path.first : u.pos;
    final dq = target.q - u.vq;
    final dr = target.r - u.vr;
    final dx = sqrt3 * (dq + dr / 2);
    final dy = 1.5 * dr;
    final len = math.sqrt(dx * dx + dy * dy);
    final speed = u.path.isNotEmpty ? 7.0 : 10.0;
    final step = speed * dt;
    var moving = false;
    if (len <= step || len < 1e-4) {
      u.vq = target.q.toDouble();
      u.vr = target.r.toDouble();
      if (u.path.isNotEmpty) u.path.removeAt(0);
    } else {
      u.vq += dq * (step / len);
      u.vr += dr * (step / len);
      moving = true;
    }
    u.hop = moving ? (math.sin(time * 22)).abs() * 0.22 : 0;
    if (!ghost && introTime > 1.1) u.spawn = math.min(1, u.spawn + dt * 3.2);
    u.flash = math.max(0, u.flash - dt * 4);
    u.lunge = math.max(0, u.lunge - dt * 5);
  }

  // ───────────────────────── effects ─────────────────────────

  void _apply(FxEvent e) {
    switch (e.kind) {
      case FxKind.text:
        final c = e.at!.toUnit();
        texts.add(
          FloatText(
            c.dx + (_rng.nextDouble() - 0.5) * 0.3,
            c.dy - 0.9,
            e.text,
            e.color,
          ),
        );
      case FxKind.explosion:
        final c = e.at!.toUnit();
        _burst(
          c,
          e.color,
          n: (16 * e.amount).round(),
          speed: 2.6 * e.amount.clamp(0.6, 1.8),
        );
        _burst(
          c,
          const Color(0xFFFFFFFF),
          n: (6 * e.amount).round(),
          speed: 1.8,
          size: 0.07,
        );
        particles.add(
          Particle(c.dx, c.dy, 0, 0, 0.45, e.color, 1.0 * e.amount, ring: true),
        );
        shake = math.max(shake, 0.15 * e.amount);
      case FxKind.projectile:
        final a = e.at!.toUnit();
        final b = e.to!.toUnit();
        final dist = (b - a).distance;
        projectiles.add(
          Projectile(a, b, e.color, e.amount, 0.18 + dist * 0.05),
        );
      case FxKind.spawn:
        final c = e.at!.toUnit();
        particles.add(
          Particle(c.dx, c.dy, 0, 0, 0.6, e.color, 1.2, ring: true),
        );
        particles.add(
          Particle(c.dx, c.dy, 0, 0, 0.4, e.color, 0.7, ring: true),
        );
        for (var i = 0; i < 14; i++) {
          final a = _rng.nextDouble() * math.pi * 2;
          particles.add(
            Particle(
              c.dx + math.cos(a) * 0.7,
              c.dy + math.sin(a) * 0.3,
              0,
              -1.2 - _rng.nextDouble(),
              0.7,
              e.color,
              0.06,
            ),
          );
        }
      case FxKind.heal:
        final c = e.at!.toUnit();
        for (var i = 0; i < 12; i++) {
          particles.add(
            Particle(
              c.dx + (_rng.nextDouble() - 0.5) * 1.0,
              c.dy + (_rng.nextDouble() - 0.2) * 0.4,
              0,
              -0.9 - _rng.nextDouble() * 0.9,
              0.9,
              e.color,
              0.07 + _rng.nextDouble() * 0.05,
            ),
          );
        }
        particles.add(
          Particle(c.dx, c.dy, 0, 0, 0.6, e.color, 0.9, ring: true),
        );
      case FxKind.splash:
        final c = e.at!.toUnit();
        _burst(
          c,
          e.color,
          n: (14 * e.amount).round(),
          speed: 2.4,
          gravity: 7,
          size: 0.09,
        );
        particles.add(
          Particle(c.dx, c.dy, 0, 0, 0.55, e.color, 1.0 * e.amount, ring: true),
        );
      case FxKind.ghost:
        ghosts.add(Ghost(e.unit!, e.spin));
      case FxKind.shake:
        shake = math.max(shake, e.amount * 0.7);
      case FxKind.banner:
        onBanner?.call(e.text);
      case FxKind.flame:
        final c = e.at!.toUnit();
        _burst(c, e.color, n: 12, speed: 1.6, gravity: -1);
    }
  }

  void _burst(
    Offset p,
    Color c, {
    int n = 14,
    double speed = 2.5,
    double size = 0.12,
    double life = 0.65,
    double gravity = 3.5,
  }) {
    for (var i = 0; i < n; i++) {
      final ang = _rng.nextDouble() * math.pi * 2;
      final sp = speed * (0.35 + _rng.nextDouble() * 0.85);
      particles.add(
        Particle(
          p.dx,
          p.dy - 0.2,
          math.cos(ang) * sp,
          math.sin(ang) * sp - speed * 0.35,
          life * (0.6 + _rng.nextDouble() * 0.7),
          c,
          size * (0.6 + _rng.nextDouble() * 0.9),
          gravity: gravity,
        ),
      );
    }
  }

  void _spark(Offset p, Color c, double radius) {
    particles.add(
      Particle(
        p.dx + (_rng.nextDouble() - 0.5) * 0.1,
        p.dy + (_rng.nextDouble() - 0.5) * 0.1,
        (_rng.nextDouble() - 0.5) * 0.6,
        (_rng.nextDouble() - 0.5) * 0.6,
        0.3,
        c,
        radius * 0.7,
      ),
    );
  }
}

class Curves0 {
  static double easeInOut(double t) =>
      t < 0.5 ? 2 * t * t : 1 - math.pow(-2 * t + 2, 2) / 2;
}
