import 'package:flutter/material.dart';

import '../data/storage.dart';
import '../game/campaign.dart';
import '../game/config.dart';
import '../game/models.dart';
import 'widgets.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reset all progress?'),
        content: const Text(
          'This clears stars, unlocks, your deck and every record.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Reset', style: TextStyle(color: Pal.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await Storage.reset();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    const modes = [
      (GameMode.campaign, 'flag', 'Campaign', Pal.gold),
      (GameMode.skirmish, 'swords', 'Skirmish', Pal.red),
      (GameMode.hotseat, 'people', 'Hot-seat', Pal.blue),
    ];
    final cards = Storage.unlockedCards.length;
    final heroes = Storage.unlockedHeroes.length;
    return ScreenFrame(
      title: 'Stats',
      subtitle: 'Your record so far',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Entrance(
            child: Panel(
              glow: Pal.gold,
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _Big(
                    'star',
                    '${Storage.totalStars}/${campaignLevels.length * 3}',
                    'Stars',
                  ),
                  _Big('cards', '$cards/${CardType.values.length}', 'Cards'),
                  _Big('crown', '$heroes/${playableHeroes.length}', 'Heroes'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < modes.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Entrance(
                index: i + 1,
                child: _ModeCard(
                  mode: modes[i].$1,
                  icon: modes[i].$2,
                  name: modes[i].$3,
                  color: modes[i].$4,
                ),
              ),
            ),
          const SizedBox(height: 10),
          Entrance(
            index: 5,
            child: GoldButton(
              label: 'Reset progress',
              filled: false,
              onTap: _reset,
            ),
          ),
        ],
      ),
    );
  }
}

class _Big extends StatelessWidget {
  const _Big(this.icon, this.value, this.label);
  final String icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        PxIcon(icon, mult: 2),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 26, color: Pal.text)),
        Text(label, style: const TextStyle(color: Pal.dim, fontSize: 13)),
      ],
    ),
  );
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.mode,
    required this.icon,
    required this.name,
    required this.color,
  });

  final GameMode mode;
  final String icon;
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final played = Storage.played(mode);
    final won = Storage.won(mode);
    final best = Storage.bestRounds(mode);
    final hot = mode == GameMode.hotseat;
    final frac = played == 0 ? 0.0 : won / played;
    return Panel(
      glow: color,
      dim: played == 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HexBadge(size: 32, color: color, child: PxIcon(icon)),
              const SizedBox(width: 12),
              Text(name, style: const TextStyle(fontSize: 22, color: Pal.text)),
              const Spacer(),
              Text(
                '$played played',
                style: const TextStyle(color: Pal.dim, fontSize: 13),
              ),
            ],
          ),
          if (!hot) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: PxBar(value: frac, color: color),
                ),
                const SizedBox(width: 12),
                Text('$won won', style: TextStyle(color: color, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              best > 0 ? 'Fastest win: round $best' : 'No wins yet',
              style: const TextStyle(color: Pal.dim, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}
