import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/models.dart';
import 'widgets.dart';

class CardView extends StatefulWidget {
  const CardView({
    super.key,
    required this.card,
    required this.width,
    required this.index,
    required this.count,
    required this.selected,
    required this.affordable,
    required this.onTap,
  });

  final GameCard card;
  final double width;
  final int index;
  final int count;
  final bool selected;
  final bool affordable;
  final VoidCallback onTap;

  @override
  State<CardView> createState() => _CardViewState();
}

class _CardViewState extends State<CardView>
    with SingleTickerProviderStateMixin {
  /// Drives the idle float; each card is offset by its position in the hand.
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..repeat();

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final width = widget.width;
    final index = widget.index;
    final selected = widget.selected;
    final affordable = widget.affordable;
    final info = card.info;
    final height = width * 1.5;
    final u = PixelUi.unit(context);
    final mult = width >= 78 ? 2 : 1;

    // Deal in from below: eased, snapped to whole UI pixels each frame.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 360 + index * 70),
      builder: (context, t, child) => Transform.translate(
        offset: Offset(
          0,
          (((1 - Curves.easeOutCubic.transform(t)) * 120)).roundToDouble() * u,
        ),
        child: child,
      ),
      child: GestureDetector(
        onTap: widget.onTap,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: selected ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          builder: (context, lift, child) => AnimatedBuilder(
            animation: _float,
            builder: (context, _) {
              // A gentle bob. Positions snap to device pixels (not whole art
              // pixels, which are too coarse for a slow float and look like
              // low framerate); the sprite is still nearest-neighbour sampled.
              final dpr = MediaQuery.of(context).devicePixelRatio;
              final wave = math.sin(
                (_float.value + index * 0.17) * 2 * math.pi,
              );
              final amp = affordable ? (selected ? 2.0 : 1.2) : 0.0;
              final raw = (-lift * 4 + wave * amp) * u;
              final dy = (raw * dpr).roundToDouble() / dpr;
              return Transform.translate(offset: Offset(0, dy), child: child);
            },
            child: child,
          ),
          child: SizedBox(
            width: width,
            height: height,
            child: Opacity(
              opacity: affordable ? 1 : 0.5,
              child: PixelBox(
                color: Color.lerp(info.color, Pal.ink, 0.35)!,
                border: selected ? Pal.gold : Pal.ink,
                padding: const EdgeInsets.all(3),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: PixelBox(
                        color: Pal.ink,
                        border: Pal.ink,
                        shadow: false,
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Text(
                          '${info.cost}',
                          style: const TextStyle(color: Pal.gold, fontSize: 14),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: PxIcon(info.icon, mult: mult),
                        ),
                      ),
                    ),
                    Text(
                      info.name,
                      maxLines: 1,
                      style: const TextStyle(color: Pal.text, fontSize: 14),
                    ),
                    Text(
                      info.desc,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Pal.dim,
                        fontSize: 8,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
