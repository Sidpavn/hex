import 'package:flutter/material.dart';

import '../ui/widgets.dart';
import 'service.dart';
import 'traits.dart';

/// One piece of news on screen for a few seconds.
class ToastItem {
  ToastItem(this.text, this.tone, this.shownAt);

  final String text;
  final Tone tone;
  final Duration shownAt;
}

/// What is on screen right now: the latest few things that happened, each for
/// a few seconds. Pure logic, so it can be tested without drawing.
class ToastQueue {
  /// How many can be showing at once.
  static const maxShown = 3;

  /// How long each stays.
  static const life = Duration(seconds: 5);

  final List<ToastItem> shown = [];
  int _seen = 0;

  /// Takes up whatever [story] has gained since last time. Returns whether
  /// anything changed.
  bool feed(List<StoryLine> story, Duration now) {
    var changed = false;
    while (_seen < story.length) {
      final line = story[_seen++];
      if (shown.any((t) => t.text == line.text)) continue;
      shown.add(ToastItem(line.text, line.tone, now));
      changed = true;
    }
    // When news piles up, the oldest goes first.
    while (shown.length > maxShown) {
      shown.removeAt(0);
      changed = true;
    }
    return changed;
  }

  /// Drops what has been up long enough. Returns whether anything went.
  bool expire(Duration now) {
    final before = shown.length;
    shown.removeWhere((t) => now - t.shownAt >= life);
    return shown.length != before;
  }

  /// Starts again, for a new day.
  void clear() {
    shown.clear();
    _seen = 0;
  }
}

/// The toasts, stacked down the top-left of the board. They never take taps.
class ToastStack extends StatelessWidget {
  const ToastStack({super.key, required this.toasts});

  final List<ToastItem> toasts;

  static Color colour(Tone t) => switch (t) {
    Tone.good => Pal.green,
    Tone.bad => Pal.red,
    Tone.mixed => Pal.gold,
  };

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 232),
        child: Column(
          key: const ValueKey('toasts'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final t in toasts)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: PixelBox(
                  key: ValueKey('toast-${t.text.hashCode}'),
                  color: Pal.panel,
                  border: colour(t.tone),
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 8,
                  ),
                  child: PxText(
                    t.text,
                    style: const TextStyle(color: Pal.text, fontSize: 14),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
