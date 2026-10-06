import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Shared look for every screen outside the game board: the same forest
/// gradient, drifting fireflies and gold accents the board uses.
class Pal {
  static const bgTop = Color(0xFF12231F);
  static const bgBottom = Color(0xFF1E3B34);
  static const panel = Color(0xCC0B1512);
  static const gold = Color(0xFFE0A030);
  static const goldLight = Color(0xFFFFE082);
  static const blue = Color(0xFF6FA3FF);
  static const red = Color(0xFFFF7A7A);
  static const green = Color(0xFF69F0AE);
  static const purple = Color(0xFFD1A3FF);
}

Path hexPath(Offset c, double r) {
  final p = Path();
  for (var i = 0; i < 6; i++) {
    final a = math.pi / 180 * (60 * i - 30);
    final pt = c + Offset(r * math.cos(a), r * math.sin(a));
    i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
  }
  return p..close();
}

/// Animated gradient with drifting fireflies and faint floating hexagons.
class Backdrop extends StatefulWidget {
  const Backdrop({super.key, required this.child});

  final Widget child;

  @override
  State<Backdrop> createState() => _BackdropState();
}

class _BackdropState extends State<Backdrop>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _time = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) => _time.value = d.inMicroseconds / 1e6)
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(child: CustomPaint(painter: _BackdropPainter(_time))),
        widget.child,
      ],
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.time) : super(repaint: time);

  final ValueNotifier<double> time;

  static double _h(int a, int b) {
    final v = math.sin(a * 127.1 + b * 311.7) * 43758.5453;
    return v - v.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Pal.bgTop, Pal.bgBottom],
        ).createShader(rect),
    );

    // Big faint hexagons drifting upward.
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var i = 0; i < 9; i++) {
      final r = 40 + _h(i, 1) * 80;
      final speed = 4 + _h(i, 2) * 8;
      final x = _h(i, 3) * size.width + math.sin(t * 0.2 + i) * 20;
      final y =
          size.height +
          r -
          ((t * speed + _h(i, 4) * size.height * 1.4) % (size.height + r * 2));
      line.color = Pal.goldLight.withValues(alpha: 0.035 + 0.03 * _h(i, 5));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(t * 0.05 * (i.isEven ? 1 : -1));
      canvas.drawPath(hexPath(Offset.zero, r), line);
      canvas.restore();
    }

    // Fireflies, same recipe as the board.
    final dot = Paint();
    for (var i = 0; i < 34; i++) {
      final speed = 6 + _h(i, 3) * 12;
      final x =
          (_h(i, 1) * size.width + math.sin(t * 0.5 + i) * 18) % size.width;
      final y =
          size.height - ((t * speed + _h(i, 2) * size.height) % size.height);
      final tw = 0.5 + 0.5 * math.sin(t * 2 + i * 1.7);
      dot.color = const Color(0xFFD8FF9E).withValues(alpha: 0.12 + 0.28 * tw);
      canvas.drawCircle(Offset(x, y), 1.2 + _h(i, 4) * 2, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter old) => false;
}

/// Fades and slides its child in, [index] steps after the screen opens.
class Entrance extends StatelessWidget {
  const Entrance({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 450 + index * 70),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        final delay = (index * 70) / (450 + index * 70);
        final p = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
        return Opacity(
          opacity: p,
          child: Transform.translate(
            offset: Offset(0, (1 - p) * 28),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Dark glass panel with a soft gold edge.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.glow,
    this.dim = false,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;

  /// Colour of an optional soft glow behind the panel.
  final Color? glow;
  final bool dim;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: padding,
      decoration: BoxDecoration(
        color: Pal.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: (glow ?? Pal.goldLight).withValues(alpha: dim ? 0.12 : 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (glow ?? Colors.black).withValues(
              alpha: glow != null ? 0.35 : 0.4,
            ),
            blurRadius: glow != null ? 20 : 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Opacity(opacity: dim ? 0.5 : 1, child: child),
    );
    if (onTap == null) return box;
    return _Pressable(onTap: onTap!, child: box);
  }
}

class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 120),
        child: widget.child,
      ),
    );
  }
}

/// Big gold call-to-action, or a quieter outlined variant.
class GoldButton extends StatelessWidget {
  const GoldButton({
    super.key,
    required this.label,
    required this.onTap,
    this.filled = true,
  });

  final String label;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final btn = Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 28),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
        gradient: filled
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Pal.goldLight, Pal.gold],
              )
            : null,
        border: filled
            ? null
            : Border.all(
                color: Pal.goldLight.withValues(alpha: 0.6),
                width: 1.5,
              ),
        boxShadow: filled
            ? const [BoxShadow(color: Color(0x66FFC400), blurRadius: 18)]
            : null,
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: filled ? Colors.black : Pal.goldLight,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
          fontSize: 15,
        ),
      ),
    );
    if (!enabled) return Opacity(opacity: 0.4, child: btn);
    return _Pressable(onTap: onTap!, child: btn);
  }
}

/// Section heading used inside panels and forms.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Pal.goldLight,
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 2.2,
      ),
    ),
  );
}

/// A pill-shaped option, glowing gold when selected.
class Choice extends StatelessWidget {
  const Choice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.emoji,
    this.locked = false,
  });

  final String label;
  final String? emoji;
  final bool selected;
  final bool locked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: selected ? Pal.gold : Colors.white10,
        border: Border.all(
          color: selected ? Pal.goldLight : Colors.white24,
          width: 1.5,
        ),
        boxShadow: selected
            ? const [BoxShadow(color: Color(0x66FFC400), blurRadius: 12)]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (emoji != null || locked) ...[
            Text(locked ? '🔒' : emoji!, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
    return locked || onTap == null
        ? Opacity(opacity: 0.45, child: chip)
        : _Pressable(onTap: onTap!, child: chip);
  }
}

/// A hexagon badge holding [child], used for level numbers and icons.
class HexBadge extends StatelessWidget {
  const HexBadge({
    super.key,
    required this.child,
    this.size = 54,
    this.color = Pal.gold,
    this.glow = false,
  });

  final Widget child;
  final double size;
  final Color color;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _HexBadgePainter(color, glow),
        child: Center(child: child),
      ),
    );
  }
}

class _HexBadgePainter extends CustomPainter {
  _HexBadgePainter(this.color, this.glow);

  final Color color;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final path = hexPath(c, size.width * 0.5);
    if (glow) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }
    canvas.drawPath(path, Paint()..color = const Color(0xFF0B1512));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _HexBadgePainter old) =>
      old.color != color || old.glow != glow;
}

/// Backdrop + safe area + a header with a back button and a gold title.
class ScreenFrame extends StatelessWidget {
  const ScreenFrame({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Pal.bgTop,
      body: Backdrop(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 16, 4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Pal.goldLight,
                        size: 20,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title.toUpperCase(),
                            style: const TextStyle(
                              color: Pal.goldLight,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3,
                            ),
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    ?trailing,
                  ],
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row of stars, filled up to [count] of [of].
class Stars extends StatelessWidget {
  const Stars(this.count, {super.key, this.of = 3, this.size = 18});

  final int count;
  final int of;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < of; i++)
        Icon(
          i < count ? Icons.star_rounded : Icons.star_outline_rounded,
          size: size,
          color: i < count ? const Color(0xFFFFD54F) : Colors.white30,
        ),
    ],
  );
}

/// Wraps [child] in a pulsing gold glow while [active] (used by the coach).
class Pulse extends StatefulWidget {
  const Pulse({
    super.key,
    required this.active,
    required this.child,
    this.radius = 14,
  });

  final bool active;
  final Widget child;
  final double radius;

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(
            color: Pal.goldLight.withValues(alpha: 0.6 + 0.4 * _c.value),
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(
                0xFFFFC400,
              ).withValues(alpha: 0.35 + 0.4 * _c.value),
              blurRadius: 10 + 14 * _c.value,
            ),
          ],
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}
