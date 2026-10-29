import 'package:flutter/material.dart';

import '../ui/widgets.dart';
import 'build_screen.dart' show DinerSprite;
import 'contracts.dart';
import 'events.dart';
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
                if (r.franchiseIncome > 0)
                  _row(
                    'Investments',
                    '+${r.franchiseIncome}',
                    Pal.gold,
                    const ValueKey('franchise-income-line'),
                  ),
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
                if (r.tooDear > 0)
                  _row(
                    'Walked out at the prices',
                    '${r.tooDear}',
                    Pal.red,
                    const ValueKey('toodear-line'),
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
                if (r.regularsSeen > 0 ||
                    r.regularsJoined.isNotEmpty ||
                    r.regularsGone.isNotEmpty)
                  _row(
                    'Regulars',
                    [
                      if (r.regularsSeen > 0) '${r.regularsSeen} came',
                      if (r.regularsJoined.isNotEmpty)
                        '${r.regularsJoined.join(', ')} joined',
                      if (r.regularsGone.isNotEmpty)
                        '${r.regularsGone.join(', ')} left',
                    ].join(', '),
                    r.regularsGone.isNotEmpty ? Pal.red : Pal.green,
                    const ValueKey('regulars-row'),
                  ),
                if (r.vending != null)
                  _row(
                    'Vending machine',
                    r.vending!.unstocked
                        ? 'no money for stock'
                        : r.vending!.broken
                        ? 'broke down, -${r.vending!.repair}'
                        : '${r.vending!.sold} sold, ${r.vending!.stored} in '
                              'the box',
                    r.vending!.broken ||
                            r.vending!.unstocked ||
                            r.vending!.lost > 0
                        ? Pal.red
                        : Pal.green,
                    const ValueKey('vending-row'),
                  ),
                if (r.catering != null && r.cateringState != ContractState.open)
                  _row(
                    'Catering',
                    switch (r.cateringState) {
                      ContractState.done => 'sent, +${r.cateringReward}',
                      ContractState.missed => 'not ready',
                      _ => 'called off',
                    },
                    r.cateringState == ContractState.done ? Pal.green : Pal.red,
                    const ValueKey('catering-row'),
                  ),
                if (r.cleaned > 0) _row('Tables cleared', '${r.cleaned}'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Eyebrow('Restaurant'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (r.event != DayEvent.none)
                  _row(
                    'Today',
                    r.event.label,
                    Pal.text,
                    const ValueKey('event-line'),
                  ),
                if (r.reviewDelta != 0)
                  _row(
                    r.event == DayEvent.blogger ? 'The blogger' : 'The critic',
                    '${r.reviewDelta > 0 ? '+' : ''}${r.reviewDelta}',
                    r.reviewDelta > 0 ? Pal.green : Pal.red,
                    const ValueKey('critic-line'),
                  ),
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
            // One panel for the whole list, like Money/Guests/Restaurant
            // above: none of these lines do anything when tapped, so they
            // must not look like a stack of separate buttons.
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final l in r.highlights(6))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
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
                ],
              ),
            ),
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
        // A long value wraps, up to half the row, instead of overflowing.
        Flexible(
          child: PxText(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(color: colour ?? Pal.text, fontSize: 17),
          ),
        ),
      ],
    ),
  );
}
