import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../world/items.dart';
import 'inventory_ui.dart' show ReachRuler;
import 'pixel/pixel_assets.dart';
import 'widgets.dart';
import 'zone_overlays.dart' show ModalFrame;

/// A chest was opened: the item rises out of it, hangs in the air with a few
/// sparkles and waits for the player to take it. Everything moves in whole
/// art pixels and nothing fades or glows.
class ChestOverlay extends StatefulWidget {
  const ChestOverlay({
    super.key,
    required this.itemId,
    required this.canTake,
    required this.onTake,
    required this.onLeave,
  });

  final String itemId;

  /// False when the bag has no room.
  final bool canTake;
  final VoidCallback onTake;
  final VoidCallback onLeave;

  @override
  State<ChestOverlay> createState() => _ChestOverlayState();
}

class _ChestOverlayState extends State<ChestOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _t = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) {
      setState(() => _t = d.inMicroseconds / 1e6);
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final u = PixelUi.unit(context);
    final def = itemOf(widget.itemId);
    return ModalFrame(
      child: SizedBox(
        width: 280,
        child: PixelBox(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: CustomPaint(
                  size: Size(_stageW * u, _stageH * u),
                  painter: _StagePainter(def.icon, _t, u),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: PxText(
                  def.name,
                  style: const TextStyle(color: Pal.goldLight, fontSize: 28),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                def.desc,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Pal.text, fontSize: 15),
              ),
              if (def.isWeapon) ...[
                const SizedBox(height: 12),
                Center(
                  child: ReachRuler(min: def.minRange, max: def.maxRange),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Damage ${def.damage}',
                    style: const TextStyle(color: Pal.dim, fontSize: 15),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              GoldButton(
                label: widget.canTake ? 'Take' : 'Bag full',
                onTap: widget.canTake ? widget.onTake : null,
              ),
              if (!widget.canTake) ...[
                const SizedBox(height: 8),
                GoldButton(
                  label: 'Leave it',
                  filled: false,
                  color: Pal.dim,
                  onTap: widget.onLeave,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Stage size in art pixels.
const _stageW = 64.0;
const _stageH = 56.0;

class _StagePainter extends CustomPainter {
  _StagePainter(this.icon, this.t, this.u);

  final String icon;
  final double t;
  final double u;

  static const _rise = 0.7;

  @override
  void paint(Canvas canvas, Size size) {
    final art = PixelAssets.instance;
    if (art == null) return;

    void draw(ui.Image img, double x, double y, double k) {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH(
          x.roundToDouble() * u,
          y.roundToDouble() * u,
          img.width * k * u,
          img.height * k * u,
        ),
        Paint()
          ..filterQuality = FilterQuality.none
          ..isAntiAlias = false,
      );
    }

    final chest = art.sprite('chest', t < 0.15 ? 'idle0' : 'open');
    const chestX = (_stageW - 14) / 2;
    const chestY = _stageH - 10;
    draw(chest, chestX, chestY, 1);

    // The item climbs out in whole-pixel steps, then bobs one pixel.
    const itemSize = 24.0;
    const top = 6.0;
    const bottom = chestY - 6;
    final k = ((t - 0.15) / _rise).clamp(0.0, 1.0);
    final step = (k * 8).floor() / 8;
    final y = bottom - (bottom - top) * step;
    final bob = k >= 1 && (t * 2.5).floor().isOdd ? 1.0 : 0.0;
    draw(art.icon(icon), (_stageW - itemSize) / 2, y - bob, 2);

    // Four sparkles blink around it once it has settled.
    if (k >= 1) {
      final star = art.sprite('star_s');
      const spots = [
        Offset(6, 12),
        Offset(50, 8),
        Offset(12, 34),
        Offset(46, 30),
      ];
      for (var i = 0; i < spots.length; i++) {
        if (((t * 3).floor() + i) % 4 < 2) {
          draw(star, spots[i].dx, spots[i].dy, 1);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StagePainter old) => old.t != t;
}
