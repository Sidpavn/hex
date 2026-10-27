import 'package:flutter/material.dart';

import '../audio/sound.dart';
import '../ui/widgets.dart';

/// Alternating two-colour squares: a diner's checkerboard trim, used as the
/// top and bottom edge of the home screen's menu card.
class CheckerBand extends StatelessWidget {
  const CheckerBand({
    super.key,
    this.colorA = Pal.ink,
    this.colorB = Pal.cream,
    this.rows = 3,
  });

  final Color colorA;
  final Color colorB;
  final int rows;

  @override
  Widget build(BuildContext context) {
    final u = PixelUi.unit(context);
    return SizedBox(
      height: rows * u,
      width: double.infinity,
      child: CustomPaint(painter: _CheckerPainter(u, colorA, colorB)),
    );
  }
}

class _CheckerPainter extends CustomPainter {
  _CheckerPainter(this.u, this.a, this.b);

  final double u;
  final Color a;
  final Color b;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..isAntiAlias = false;
    final cell = size.height;
    final n = (size.width / cell).ceil();
    for (var i = 0; i < n; i++) {
      final x = i * cell;
      final w = (x + cell > size.width) ? size.width - x : cell;
      p.color = i.isEven ? a : b;
      canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), p);
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter old) =>
      old.u != u || old.a != a || old.b != b;
}

/// A punched tear line: dots on a dark band, where the exterior ends and the
/// menu card begins.
class PerfBand extends StatelessWidget {
  const PerfBand({super.key, this.bg = Pal.ink, this.dot = Pal.cream});

  final Color bg;
  final Color dot;

  @override
  Widget build(BuildContext context) {
    final u = PixelUi.unit(context);
    return SizedBox(
      height: 4 * u,
      width: double.infinity,
      child: CustomPaint(painter: _PerfPainter(u, bg, dot)),
    );
  }
}

class _PerfPainter extends CustomPainter {
  _PerfPainter(this.u, this.bg, this.dot);

  final double u;
  final Color bg;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..isAntiAlias = false;
    canvas.drawRect(Offset.zero & size, p..color = bg);
    final step = 4 * u;
    p.color = dot;
    for (var x = 2 * u; x < size.width; x += step) {
      canvas.drawRect(Rect.fromLTWH(x, u, 2 * u, 2 * u), p);
    }
  }

  @override
  bool shouldRepaint(_PerfPainter old) =>
      old.u != u || old.bg != bg || old.dot != dot;
}

/// A dotted rule between a label and its value, like a menu's price leader.
class DotLeader extends StatelessWidget {
  const DotLeader({super.key, this.color = Pal.creamDark});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final u = PixelUi.unit(context);
    return SizedBox(
      height: 2 * u,
      child: CustomPaint(painter: _DotLeaderPainter(u, color)),
    );
  }
}

class _DotLeaderPainter extends CustomPainter {
  _DotLeaderPainter(this.u, this.color);

  final double u;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..isAntiAlias = false
      ..color = color;
    final step = 3 * u;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawRect(Rect.fromLTWH(x, 0, u, u), p);
    }
  }

  @override
  bool shouldRepaint(_DotLeaderPainter old) =>
      old.u != u || old.color != color;
}

/// A label/value line with a dotted leader between them, like a menu's price
/// list: "Lifetime earned ⋯⋯⋯⋯ 1,204".
class LedgerLine extends StatelessWidget {
  const LedgerLine({
    super.key,
    required this.label,
    required this.value,
    this.ink = Pal.inkWarm,
    this.dim = Pal.teal,
  });

  final String label;
  final String value;
  final Color ink;
  final Color dim;

  @override
  Widget build(BuildContext context) {
    final u = PixelUi.unit(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: u),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          PxText(label, style: TextStyle(color: dim, fontSize: 14)),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 5 * u),
              child: DotLeader(),
            ),
          ),
          PxText(value, style: TextStyle(color: ink, fontSize: 14)),
        ],
      ),
    );
  }
}

/// A hex seal pinned at a seam: the game's own tile shape, standing in for
/// the diner's health-grade card — reads the player's level. A hard offset
/// shadow, not a blur, for elevation.
class HexSeal extends StatelessWidget {
  const HexSeal({
    super.key,
    required this.child,
    this.color = Pal.teal,
    this.size = 46,
  });

  final Widget child;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final u = PixelUi.unit(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 3 * u,
          top: 3 * u,
          child: HexBadge(size: size, color: Pal.tealDark, child: const SizedBox()),
        ),
        HexBadge(size: size, color: color, child: child),
      ],
    );
  }
}

/// A button styled for the cream menu card: flat teal fill or a teal outline
/// on the card itself, never the usual dark slate chrome.
class DinerButton extends StatefulWidget {
  const DinerButton({
    super.key,
    required this.label,
    required this.onTap,
    this.filled = true,
    this.fontSize = 14,
    this.tall = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final double fontSize;
  final bool tall;

  @override
  State<DinerButton> createState() => _DinerButtonState();
}

class _DinerButtonState extends State<DinerButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final box = Opacity(
      opacity: enabled ? 1 : 0.45,
      child: PixelBox(
        color: widget.filled ? Pal.teal : Pal.cream,
        border: widget.filled ? Pal.tealDark : Pal.teal,
        pressed: _down,
        padding: EdgeInsets.symmetric(
          vertical: widget.tall ? 12 : 7,
          horizontal: 10,
        ),
        child: Center(
          child: PxText(
            widget.label,
            maxLines: 1,
            style: TextStyle(
              color: widget.filled ? Pal.cream : Pal.inkWarm,
              fontSize: widget.fontSize,
            ),
          ),
        ),
      ),
    );
    if (!enabled) return box;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: () {
        Sound.instance.play(Sfx.tap);
        widget.onTap!();
      },
      child: box,
    );
  }
}
