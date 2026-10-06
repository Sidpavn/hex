import 'package:flutter/material.dart';

import '../data/storage.dart';
import '../game/campaign.dart';
import '../game/config.dart';
import '../game/models.dart';
import 'menu_screen.dart' show gameRoute;
import 'widgets.dart';

class CampaignScreen extends StatefulWidget {
  const CampaignScreen({super.key});

  @override
  State<CampaignScreen> createState() => _CampaignScreenState();
}

class _CampaignScreenState extends State<CampaignScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _play(int i) async {
    await Navigator.of(
      context,
    ).push(gameRoute(Storage.configFor(campaignLevels[i])));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final n = campaignLevels.length;
    // The first level that is open but not yet beaten is "current".
    var current = n;
    for (var i = 0; i < n; i++) {
      if (Storage.stars(i) == 0) {
        current = i;
        break;
      }
    }
    return ScreenFrame(
      title: 'Campaign',
      subtitle: '★ ${Storage.totalStars} of ${n * 3}',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          for (var i = 0; i < n; i++) ...[
            if (i == 0)
              const _Header(
                'Training',
                'Learn the rules, one mechanic at a time',
              ),
            if (i == lessonCount)
              const _Header('Campaign', 'Put it all to use'),
            Entrance(
              index: i.clamp(0, 6),
              child: _LevelRow(
                index: i,
                first: i == 0 || i == lessonCount,
                last: i == n - 1 || i == lessonCount - 1,
                current: i == current,
                pulse: _pulse,
                onTap: Storage.levelUnlocked(i) ? () => _play(i) : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title, this.subtitle);

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: Pal.goldLight,
            fontWeight: FontWeight.w900,
            letterSpacing: 3,
            fontSize: 15,
          ),
        ),
        Text(
          subtitle,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    ),
  );
}

class _LevelRow extends StatelessWidget {
  const _LevelRow({
    required this.index,
    required this.first,
    required this.last,
    required this.current,
    required this.pulse,
    required this.onTap,
  });

  final int index;
  final bool first;
  final bool last;
  final bool current;
  final Animation<double> pulse;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final lv = campaignLevels[index];
    final c = lv.config;
    final open = onTap != null;
    final stars = Storage.stars(index);
    final done = stars > 0;
    final lesson = index < lessonCount;
    final color = done
        ? Pal.green
        : open
        ? (lesson ? Pal.blue : Pal.gold)
        : Colors.white24;

    final tags = <Widget>[
      if (lesson) _Tag('🎓 ${lv.topic}'),
      if (!lesson)
        _Tag(
          c.objective == Objective.eliminate
              ? '⚔️ Eliminate'
              : c.objective == Objective.hold
              ? '⭐ Hold ${c.target} turns'
              : '🛡️ Survive ${c.target} rounds',
        ),
      if (!lesson) _Tag(c.difficulty.label),
      if (c.roundLimit != null) _Tag('⏳ ${c.roundLimit} rounds'),
      if (c.enemyHero != UnitType.hero)
        _Tag('👹 ${unitStats[c.enemyHero]!.name}'),
    ];
    final rewards = [
      for (final r in lv.rewardCards)
        '${cardInfo[r]!.emoji} ${cardInfo[r]!.name}',
      for (final h in lv.rewardHeroes) '🦸 ${unitStats[h]!.name}',
    ];

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 58,
            child: Column(
              children: [
                Expanded(
                  child: _Line(visible: !first, lit: open),
                ),
                AnimatedBuilder(
                  animation: pulse,
                  builder: (context, _) => Transform.scale(
                    scale: current ? 1 + 0.08 * pulse.value : 1,
                    child: HexBadge(
                      size: 52,
                      color: color,
                      glow: current || done,
                      child: open
                          ? Text(
                              lesson
                                  ? '${index + 1}'
                                  : '${index + 1 - lessonCount}',
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                              ),
                            )
                          : const Icon(
                              Icons.lock_rounded,
                              size: 18,
                              color: Colors.white38,
                            ),
                    ),
                  ),
                ),
                Expanded(
                  child: _Line(visible: !last, lit: done),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Panel(
                glow: current
                    ? (lesson ? Pal.blue : Pal.gold)
                    : (done ? Pal.green : null),
                dim: !open,
                onTap: onTap,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            lv.name.toUpperCase(),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.4,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                        Stars(stars, size: 17),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lv.blurb,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: tags),
                    if (c.deck != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'YOUR CARDS  ${c.deck!.map((t) => cardInfo[t]!.emoji).join(' ')}',
                        style: const TextStyle(
                          color: Pal.goldLight,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                    if (rewards.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'REWARD  ${rewards.join('  ')}',
                        style: const TextStyle(
                          color: Pal.purple,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.visible, required this.lit});

  final bool visible;
  final bool lit;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 3,
      color: !visible
          ? Colors.transparent
          : (lit ? Pal.gold.withValues(alpha: 0.7) : Colors.white12),
    ),
  );
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.white10,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white70, fontSize: 11),
    ),
  );
}
