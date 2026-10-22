import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'diner_art.dart';

/// A fixture's sprite for the picker: just the part with pixels in it, one
/// art pixel per whole device-pixel multiple.
class DinerSprite extends StatelessWidget {
  const DinerSprite(this.name, {super.key, this.mult = 1});

  final String name;

  /// Whole-number size multiple.
  final int mult;

  @override
  Widget build(BuildContext context) {
    final art = DinerArt.instance;
    if (art == null) return const SizedBox.shrink();
    final spr = art.sprite(name);
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final u = math.max(1, dpr.floor()) / dpr * mult;
    return SizedBox(
      width: spr.trim.width * u,
      height: spr.trim.height * u,
      child: CustomPaint(painter: _SpritePainter(spr)),
    );
  }
}

class _SpritePainter extends CustomPainter {
  _SpritePainter(this.spr);

  final Spr spr;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      spr.image,
      spr.trim,
      Offset.zero & size,
      Paint()
        ..filterQuality = FilterQuality.none
        ..isAntiAlias = false,
    );
  }

  @override
  bool shouldRepaint(covariant _SpritePainter old) => old.spr != spr;
}
