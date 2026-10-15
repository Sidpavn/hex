import 'package:flutter/foundation.dart';

/// Turns frame time into whole sim ticks. The sim only ever sees fixed steps,
/// so it behaves the same at any frame rate and can be fast-forwarded in a
/// test. [alpha] is how far into the next tick we are, for drawing movement
/// between cells.
class TickClock extends ChangeNotifier {
  TickClock(
    this.onTick, {
    this.step = 0.4,
    this.maxCatchUp = 5,
    this.animating,
  });

  final VoidCallback onTick;

  /// Seconds per tick.
  final double step;

  /// Most ticks run for one frame. After a long stall the rest are dropped
  /// rather than replayed: time away is for the offline calculation, not for
  /// walking people around.
  final int maxCatchUp;

  /// Whether anything is mid-step and needs a redraw every frame. When it is
  /// null or false, listeners are only told on a new tick.
  final bool Function()? animating;

  double _acc = 0;

  double get alpha => (_acc / step).clamp(0.0, 1.0);

  void advance(double dt) {
    _acc += dt;
    var ran = 0;
    while (_acc >= step) {
      _acc -= step;
      if (ran < maxCatchUp) {
        onTick();
        ran++;
      }
    }
    if (ran > 0 || (animating?.call() ?? true)) notifyListeners();
  }
}
