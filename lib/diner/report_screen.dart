import 'package:flutter/material.dart';

import '../ui/widgets.dart';
import 'build_screen.dart' show DinerSprite;
import 'recipes.dart';
import 'service.dart';
import 'traits.dart';

/// The whole of one day, for anyone who wants it: the figures behind the
/// short summary, and what happened.
class DayReportScreen extends StatelessWidget {
  const DayReportScreen({
    super.key,
    required this.report,
    required this.progress,
  });

  final DayReport report;
  final Progress progress;

  @override
  Widget build(BuildContext context) {
    final r = report;
    return ScreenFrame(
      title: 'Day ${r.day}',
      subtitle: 'The whole day',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          const Eyebrow('Money'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _row('Earned', '${r.earned}', Pal.gold),
                _row('Tips included', '${r.tips}'),
                _row('Ingredients', '${r.ingredients}'),
                _row('Wages', '${r.wages}'),
                _row('Kept', '${r.earned - r.ingredients - r.wages}', Pal.gold),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Eyebrow('Guests'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _row('Served', '${r.served}', Pal.green),
                _row('Left angry', '${r.walkouts}', Pal.red),
                _row('Average wait', '${r.avgWait.toStringAsFixed(1)} s'),
                if (r.cars > 0)
                  _row(
                    'Served at the window',
                    '${r.cars}',
                    Pal.text,
                    const ValueKey('cars-line'),
                  ),
                if (r.soldOut > 0)
                  _row(
                    'Turned away, sold out',
                    '${r.soldOut}',
                    Pal.red,
                    const ValueKey('stock-line'),
                  ),
                _row('Dishes wasted', '${r.wasted}'),
                if (r.leftover > 0)
                  _row('Ingredients thrown away', '${r.leftover}'),
                _row('Expected tomorrow', 'about ${r.tomorrow}'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Eyebrow('Restaurant'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _row(
                  'Rating',
                  '${(r.reputationBefore / 20).toStringAsFixed(1)} to '
                      '${(r.reputation / 20).toStringAsFixed(1)}',
                  r.reputation >= r.reputationBefore ? Pal.green : Pal.red,
                ),
                _row('Level', '${progress.level}'),
                const SizedBox(height: 4),
                PxBar(value: progress.xp / progress.xpToNext, color: Pal.gold),
              ],
            ),
          ),
          if (r.moods.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Eyebrow('The team'),
            Panel(
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  for (final m in r.moods)
                    Row(
                      key: ValueKey('mood-${m.name}'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DinerSprite('mood_${m.after.clamp(0, 3)}'),
                        const SizedBox(width: 6),
                        PxText(
                          m.name,
                          style: TextStyle(
                            color: m.worse
                                ? Pal.red
                                : m.better
                                ? Pal.green
                                : Pal.dim,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
          if (r.highlights(6).isNotEmpty) ...[
            const SizedBox(height: 12),
            const Eyebrow('What happened'),
            for (final l in r.highlights(6)) ...[
              Panel(
                padding: const EdgeInsets.all(8),
                child: PxText(
                  l.text,
                  style: TextStyle(
                    color: switch (l.tone) {
                      Tone.good => Pal.green,
                      Tone.bad => Pal.red,
                      Tone.mixed => Pal.text,
                    },
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value, [Color? colour, Key? key]) => Padding(
    key: key,
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: PxText(
            label,
            style: const TextStyle(color: Pal.dim, fontSize: 14),
          ),
        ),
        PxText(
          value,
          style: TextStyle(color: colour ?? Pal.text, fontSize: 17),
        ),
      ],
    ),
  );
}
