import 'package:flutter/material.dart';

import '../ui/widgets.dart';
import 'diner.dart';
import 'goals.dart';

/// What to aim for: the next few goals with how to go about each, then what
/// is further off, then what has been done.
class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key, required this.diner, this.onReset});

  final Diner diner;

  /// Wipes the save and starts again. A testing aid, kept out of the way.
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final next = diner.activeGoals;
    final later = [
      for (final g in goals)
        if (!diner.goalsDone.contains(g.id) && !next.contains(g)) g,
    ];
    final done = [
      for (final g in goals)
        if (diner.goalsDone.contains(g.id)) g,
    ];
    return ScreenFrame(
      title: 'Goals',
      subtitle: '${done.length} of ${goals.length} done',
      trailing: PxText(
        ':coin: ${diner.coins}',
        style: const TextStyle(color: Pal.text, fontSize: 20),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          if (next.isEmpty)
            const PxText(
              'Every goal is done.',
              key: ValueKey('all-done'),
              style: TextStyle(color: Pal.green, fontSize: 17),
            ),
          if (next.isNotEmpty) ...[
            const Eyebrow('Next'),
            for (final g in next) ...[_card(g), const SizedBox(height: 8)],
          ],
          if (later.isNotEmpty) ...[
            const SizedBox(height: 4),
            const Eyebrow('Later'),
            for (final g in later) ...[
              _row(g, Pal.dim),
              const SizedBox(height: 6),
            ],
          ],
          if (done.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Eyebrow('Done'),
            for (final g in done) ...[
              _row(g, Pal.green),
              const SizedBox(height: 6),
            ],
          ],
          if (onReset != null) ...[
            const SizedBox(height: 24),
            GestureDetector(
              key: const ValueKey('reset'),
              behavior: HitTestBehavior.opaque,
              onTap: () {
                onReset!();
                Navigator.of(context).pop();
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: PxText(
                  'Start over',
                  style: TextStyle(color: Pal.dimmer, fontSize: 14),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _card(Goal g) => Panel(
    key: ValueKey('goal-${g.id}'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: PxText(
                g.title,
                style: const TextStyle(color: Pal.text, fontSize: 17),
              ),
            ),
            PxText(
              ':coin: ${g.reward}',
              style: const TextStyle(color: Pal.gold, fontSize: 17),
            ),
          ],
        ),
        if (g.hint != null)
          PxText(g.hint!, style: const TextStyle(color: Pal.dim, fontSize: 14)),
      ],
    ),
  );

  Widget _row(Goal g, Color colour) => Row(
    key: ValueKey('goal-${g.id}'),
    children: [
      Expanded(
        child: PxText(g.title, style: TextStyle(color: colour, fontSize: 14)),
      ),
      PxText(
        ':coin: ${g.reward}',
        style: TextStyle(color: colour, fontSize: 14),
      ),
    ],
  );
}
