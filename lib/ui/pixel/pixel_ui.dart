import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../game/models.dart';
import 'palette.dart';
import 'pixel_assets.dart';

/// Sizing helpers that keep every UI pixel a whole number of device pixels.
class PixelUi {
  /// Logical size of one UI "art pixel". Tracks the board's scale so panels,
  /// icons and sprites all share one pixel grid.
  static double unit(BuildContext context) {
    final mq = MediaQuery.of(context);
    final dpr = mq.devicePixelRatio;
    // Capped so wide desktop windows don't blow the fixed-width layouts up.
    final w = math.min(mq.size.shortestSide, 460.0);
    final k = math.max(2, (w * dpr / 224).floor());
    return k / dpr;
  }
}

/// Snaps every font size to a size where one VT323 font pixel is a whole
/// number of device pixels, so text stays crisp. VT323 reads small, so sizes
/// are boosted a little first.
class PixelTextScaler extends TextScaler {
  const PixelTextScaler(this.dpr);

  final double dpr;
  static const _boost = 1.25;

  @override
  double scale(double fontSize) {
    final kMin = math.max(1, (10 * dpr / 16).ceil());
    final k = math.max(kMin, (fontSize * _boost * dpr / 16).round());
    return 16 * k / dpr;
  }

  @override
  // ignore: deprecated_member_use_from_same_package
  double get textScaleFactor => _boost;

  @override
  bool operator ==(Object other) =>
      other is PixelTextScaler && other.dpr == dpr;

  @override
  int get hashCode => dpr.hashCode;
}

// ───────────────────────── icons ─────────────────────────

class _ImagePainter extends CustomPainter {
  _ImagePainter(this.image, this.filter);

  final ui.Image image;
  final ColorFilter? filter;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()
        ..filterQuality = FilterQuality.none
        ..isAntiAlias = false
        ..colorFilter = filter,
    );
  }

  @override
  bool shouldRepaint(covariant _ImagePainter old) =>
      old.image != image || old.filter != filter;
}

/// A pixel icon (see `sprites.txt`) drawn at a whole multiple of the UI unit.
class PxIcon extends StatelessWidget {
  const PxIcon(this.name, {super.key, this.mult = 1, this.tint});

  final String name;

  /// Whole-number multiple of the UI pixel.
  final int mult;

  /// Flat tint (e.g. to grey out an icon).
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final art = PixelAssets.instance;
    if (art == null) return const SizedBox.shrink();
    final img = art.icon(name);
    final s = PixelUi.unit(context) * mult;
    return SizedBox(
      width: img.width * s,
      height: img.height * s,
      child: CustomPaint(
        painter: _ImagePainter(
          img,
          tint == null ? null : ColorFilter.mode(tint!, BlendMode.srcATop),
        ),
      ),
    );
  }
}

/// A unit's idle sprite, optionally animating between its two idle frames.
class UnitPortrait extends StatefulWidget {
  const UnitPortrait(
    this.type, {
    super.key,
    this.team = Team.player,
    this.mult = 2,
    this.animated = false,
    this.dim = false,
  });

  final UnitType type;
  final Team team;
  final int mult;
  final bool animated;
  final bool dim;

  @override
  State<UnitPortrait> createState() => _UnitPortraitState();
}

class _UnitPortraitState extends State<UnitPortrait>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void initState() {
    super.initState();
    if (widget.animated) {
      _c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 900),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final art = PixelAssets.instance;
    if (art == null) return const SizedBox.shrink();
    final s = PixelUi.unit(context) * widget.mult;
    final filter = widget.dim
        ? const ColorFilter.mode(Color(0xAA26363E), BlendMode.srcATop)
        : null;
    Widget frame(String f) {
      final img = art.unit(widget.type, widget.team, f);
      return SizedBox(
        width: img.width * s,
        height: img.height * s,
        child: CustomPaint(painter: _ImagePainter(img, filter)),
      );
    }

    if (_c == null) return frame('idle0');
    return AnimatedBuilder(
      animation: _c!,
      builder: (_, _) => frame(_c!.value < 0.5 ? 'idle0' : 'idle1'),
    );
  }
}

/// Text that swaps `:icon:` tokens for pixel icons, e.g. `Costs 2 :bolt:`.
class PxText extends StatelessWidget {
  const PxText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.iconMult = 1,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final int iconMult;

  static final _token = RegExp(r':([a-z0-9]+):');

  @override
  Widget build(BuildContext context) {
    final art = PixelAssets.instance;
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _token.allMatches(text)) {
      // Inline stars use the small glyph so they sit on the text line.
      final name = m.group(1)! == 'star' ? 'star_s' : m.group(1)!;
      if (art == null || !art.hasIcon(name)) continue;
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: PxIcon(name, mult: iconMult),
        ),
      );
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(
      TextSpan(children: spans),
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }
}

// ───────────────────────── boxes ─────────────────────────

class _BoxPainter extends CustomPainter {
  _BoxPainter({
    required this.u,
    required this.color,
    required this.border,
    required this.light,
    required this.dark,
    required this.depth,
    required this.pressed,
  });

  final double u;
  final Color color;
  final Color border;
  final Color light;
  final Color dark;
  final double depth;
  final bool pressed;

  void _notched(Canvas canvas, Rect r, Paint p) {
    canvas.drawRect(Rect.fromLTRB(r.left + u, r.top, r.right - u, r.bottom), p);
    canvas.drawRect(Rect.fromLTRB(r.left, r.top + u, r.right, r.bottom - u), p);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..isAntiAlias = false;
    final top = pressed ? depth : 0.0;
    final body = Rect.fromLTWH(0, top, size.width, size.height - depth);
    if (!pressed && depth > 0) {
      _notched(
        canvas,
        Rect.fromLTWH(0, depth, size.width, size.height - depth),
        p..color = Pal.ink,
      );
    }
    _notched(canvas, body, p..color = border);
    final inner = body.deflate(u);
    _notched(canvas, inner, p..color = color);
    if (inner.width > 4 * u && inner.height > 4 * u) {
      canvas.drawRect(
        Rect.fromLTWH(inner.left + u, inner.top, inner.width - 2 * u, u),
        p..color = light,
      );
      canvas.drawRect(
        Rect.fromLTWH(inner.left + u, inner.bottom - u, inner.width - 2 * u, u),
        p..color = dark,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BoxPainter old) =>
      old.u != u ||
      old.color != color ||
      old.border != border ||
      old.light != light ||
      old.dark != dark ||
      old.depth != depth ||
      old.pressed != pressed;
}

/// A hard-edged panel: notched corners, a 1px border, a top highlight and a
/// bottom shade, with an optional drop shadow that a press flattens.
class PixelBox extends StatelessWidget {
  const PixelBox({
    super.key,
    required this.child,
    this.color = Pal.panel,
    this.border = Pal.ink,
    this.light,
    this.dark,
    this.padding = const EdgeInsets.all(12),
    this.shadow = true,
    this.pressed = false,
  });

  final Widget child;
  final Color color;
  final Color border;
  final Color? light;
  final Color? dark;
  final EdgeInsets padding;
  final bool shadow;
  final bool pressed;

  static Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

  @override
  Widget build(BuildContext context) {
    final u = PixelUi.unit(context);
    final depth = shadow ? u : 0.0;
    return CustomPaint(
      painter: _BoxPainter(
        u: u,
        color: color,
        border: border,
        light: light ?? _mix(color, Colors.white, 0.14),
        dark: dark ?? _mix(color, Colors.black, 0.22),
        depth: depth,
        pressed: pressed,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          padding.left + u,
          padding.top + u + (pressed ? depth : 0),
          padding.right + u,
          padding.bottom + u + (pressed ? 0 : depth),
        ),
        child: child,
      ),
    );
  }
}

// ───────────────────────── bars ─────────────────────────

class _BarPainter extends CustomPainter {
  _BarPainter(this.u, this.value, this.color);

  final double u;
  final double value;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..isAntiAlias = false;
    canvas.drawRect(Offset.zero & size, p..color = Pal.ink);
    final inner = Rect.fromLTWH(u, u, size.width - 2 * u, size.height - 2 * u);
    canvas.drawRect(inner, p..color = const Color(0xFF3A3E52));
    final w = ((inner.width / u) * value.clamp(0.0, 1.0)).round() * u;
    if (w > 0) {
      canvas.drawRect(
        Rect.fromLTWH(inner.left, inner.top, w, inner.height),
        p..color = color,
      );
      canvas.drawRect(
        Rect.fromLTWH(inner.left, inner.top, w, u),
        p..color = Color.lerp(color, Colors.white, 0.35)!,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) =>
      old.u != u || old.value != value || old.color != color;
}

/// A flat progress bar that fills in whole pixels.
class PxBar extends StatelessWidget {
  const PxBar({
    super.key,
    required this.value,
    required this.color,
    this.rows = 4,
  });

  final double value;
  final Color color;

  /// Height in UI pixels, border included.
  final int rows;

  @override
  Widget build(BuildContext context) {
    final u = PixelUi.unit(context);
    return SizedBox(
      height: rows * u,
      child: CustomPaint(
        painter: _BarPainter(u, value, color),
        size: Size.infinite,
      ),
    );
  }
}
