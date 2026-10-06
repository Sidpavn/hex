import 'package:flutter/material.dart';

import '../game/models.dart';

class CardView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final info = card.info;
    final height = width * 1.5;
    final fan = index - (count - 1) / 2;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 450 + index * 70),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Transform.translate(
        offset: Offset(0, (1 - t) * 170 + fan * fan * 2.2),
        child: Transform.rotate(angle: fan * 0.04 * t, child: child),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, selected ? -22 : 0, 0)
            ..scaleByDouble(selected ? 1.08 : 1.0, selected ? 1.08 : 1.0, 1, 1),
          transformAlignment: Alignment.bottomCenter,
          width: width,
          height: height,
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(info.color, Colors.white, 0.25)!,
                info.color,
                Color.lerp(info.color, Colors.black, 0.35)!,
              ],
            ),
            border: Border.all(
              color: selected ? const Color(0xFFFFE082) : Colors.white70,
              width: selected ? 3 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: selected
                    ? const Color(0xAAFFE082)
                    : Colors.black.withValues(alpha: 0.4),
                blurRadius: selected ? 18 : 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Opacity(
            opacity: affordable ? 1 : 0.45,
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: width * 0.28,
                      height: width * 0.28,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1B1B2F),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${info.cost}',
                        style: TextStyle(
                          color: const Color(0xFFFFE082),
                          fontWeight: FontWeight.w900,
                          fontSize: width * 0.17,
                        ),
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      info.emoji,
                      style: TextStyle(fontSize: width * 0.4),
                    ),
                  ),
                ),
                Text(
                  info.name,
                  maxLines: 1,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: (width * 0.15).clamp(10, 15),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  info.desc,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: (width * 0.105).clamp(7.5, 10.5),
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
