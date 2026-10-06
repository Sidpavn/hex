import 'package:flutter/material.dart';

import 'pixel/palette.dart';
import 'pixel/pixel_assets.dart';
import 'pixel/pixel_ui.dart';

export 'pixel/palette.dart';
export 'pixel/pixel_ui.dart';

/// Flat screen background. No ambient decoration: the pixel art carries it.
class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Pal.bgTop,
    child: SizedBox.expand(child: child),
  );
}

/// Slides its child in, [index] beats after the screen opens. Motion is eased
/// but snapped to whole UI pixels each frame, so it is smooth and still crisp.
class Entrance extends StatelessWidget {
  const Entrance({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  Widget build(BuildContext context) {
    final u = PixelUi.unit(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 360 + index * 70),
      builder: (context, t, child) {
        final delay = (index * 70) / (360 + index * 70);
        final p = ((t - delay) / (1 - delay)).clamp(0.0, 1.0);
        if (p <= 0) return const Opacity(opacity: 0, child: SizedBox());
        // Eased, but landing on whole UI pixels every frame.
        final e = Curves.easeOutCubic.transform(p);
        final dy = (((1 - e) * 28)).roundToDouble() * u;
        return Transform.translate(offset: Offset(0, dy), child: child);
      },
      child: child,
    );
  }
}

/// Wraps a [PixelBox] so a tap presses it in by one pixel.
class _PressBox extends StatefulWidget {
  const _PressBox({required this.onTap, required this.builder});

  final VoidCallback? onTap;
  final Widget Function(bool pressed) builder;

  @override
  State<_PressBox> createState() => _PressBoxState();
}

class _PressBoxState extends State<_PressBox> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.builder(false);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: widget.builder(_down),
    );
  }
}

/// A slate panel. [accent] swaps the border to a colour (current/done items);
/// [dim] fades a locked one.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.glow,
    this.dim = false,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;

  /// Accent colour for the border. (Named `glow` for existing call sites.)
  final Color? glow;
  final bool dim;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _PressBox(
      onTap: onTap,
      builder: (pressed) => Opacity(
        opacity: dim ? 0.55 : 1,
        child: PixelBox(
          border: glow ?? Pal.ink,
          padding: padding,
          pressed: pressed,
          child: child,
        ),
      ),
    );
  }
}

/// The primary call-to-action, or a quieter outlined variant.
class GoldButton extends StatelessWidget {
  const GoldButton({
    super.key,
    required this.label,
    required this.onTap,
    this.filled = true,
    this.color = Pal.gold,
  });

  final String label;
  final VoidCallback? onTap;
  final bool filled;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return _PressBox(
      onTap: onTap,
      builder: (pressed) => Opacity(
        opacity: enabled ? 1 : 0.45,
        child: PixelBox(
          color: filled ? color : Pal.panel,
          border: filled ? Pal.ink : color,
          pressed: pressed,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Center(
            child: PxText(
              label,
              maxLines: 1,
              style: TextStyle(color: filled ? Pal.ink : color, fontSize: 17),
            ),
          ),
        ),
      ),
    );
  }
}

/// Section heading used inside panels and forms.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: PxText(text, style: const TextStyle(color: Pal.gold, fontSize: 14)),
  );
}

/// A selectable chip: gold when selected, slate otherwise.
class Choice extends StatelessWidget {
  const Choice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.locked = false,
  });

  final String label;

  /// Pixel icon name shown before the label.
  final String? icon;
  final bool selected;
  final bool locked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _PressBox(
      onTap: locked ? null : onTap,
      builder: (pressed) => Opacity(
        opacity: locked ? 0.5 : 1,
        child: PixelBox(
          color: selected ? Pal.gold : Pal.panel,
          border: selected ? Pal.goldDark : Pal.ink,
          pressed: pressed,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null || locked) ...[
                PxIcon(locked ? 'lock' : icon!),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? Pal.ink : Pal.text,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small label chip.
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.color = Pal.dim});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => PixelBox(
    color: Pal.panelLo,
    shadow: false,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: PxText(text, style: TextStyle(color: color, fontSize: 11)),
  );
}

/// A hexagon badge holding [child], used for level numbers and icons. Drawn
/// from the same hex mask as the board tiles.
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

  /// Fills the badge with a dithered tint (current / completed).
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final art = PixelAssets.instance;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final k = (size * dpr / 24).floor().clamp(1, 99);
    final s = k / dpr;
    return SizedBox(
      width: 24 * s,
      height: 28 * s,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (art != null)
            CustomPaint(
              size: Size(24 * s, 28 * s),
              painter: _HexBadgePainter(art, color, glow),
            ),
          child,
        ],
      ),
    );
  }
}

class _HexBadgePainter extends CustomPainter {
  _HexBadgePainter(this.art, this.color, this.glow);

  final PixelAssets art;
  final Color color;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    void draw(String mask, Color c) {
      final img = art.mask(mask);
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        dst,
        Paint()
          ..filterQuality = FilterQuality.none
          ..isAntiAlias = false
          ..colorFilter = ColorFilter.mode(c, BlendMode.srcIn),
      );
    }

    draw('fillA', Pal.ink);
    draw('fillB', Pal.ink);
    if (glow) draw('fillA', color.withValues(alpha: 0.35));
    draw('ring', color);
  }

  @override
  bool shouldRepaint(covariant _HexBadgePainter old) =>
      old.color != color || old.glow != glow;
}

/// Backdrop + safe area + a header with a back button and a title.
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
                padding: const EdgeInsets.fromLTRB(4, 6, 16, 6),
                child: Row(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).maybePop(),
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: PxIcon('back'),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          PxText(
                            title,
                            style: const TextStyle(
                              color: Pal.gold,
                              fontSize: 26,
                              height: 1,
                            ),
                          ),
                          if (subtitle != null)
                            PxText(
                              subtitle!,
                              style: const TextStyle(
                                color: Pal.dim,
                                fontSize: 13,
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
  const Stars(
    this.count, {
    super.key,
    this.of = 3,
    this.size = 18,
    this.mult = 1,
  });

  final int count;
  final int of;
  final double size;
  final int mult;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < of; i++)
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: PxIcon(
            'star',
            mult: mult,
            tint: i < count ? null : const Color(0xCC1A1C2C),
          ),
        ),
    ],
  );
}

/// A minus / value / plus control for picking a whole number.
class PxStepper extends StatelessWidget {
  const PxStepper({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  Widget _btn(String label, bool enabled, VoidCallback tap) => SizedBox(
    width: 56,
    child: GoldButton(label: label, filled: false, onTap: enabled ? tap : null),
  );

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _btn('-', value > min, () => onChanged(value - 1)),
      SizedBox(
        width: 72,
        child: Center(
          child: Text(
            '$value',
            style: const TextStyle(color: Pal.gold, fontSize: 28),
          ),
        ),
      ),
      _btn('+', value < max, () => onChanged(value + 1)),
    ],
  );
}

/// Marks [child] as the thing to do next (used by the coach): a blinking
/// gold frame, no glow.
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
      duration: const Duration(milliseconds: 800),
    );
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant Pulse old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) _c.repeat();
    if (!widget.active && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    final u = PixelUi.unit(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: _c.value < 0.5 ? Pal.goldLight : Pal.goldDark,
            width: u,
          ),
        ),
        child: Padding(padding: EdgeInsets.all(u), child: child),
      ),
      child: widget.child,
    );
  }
}
