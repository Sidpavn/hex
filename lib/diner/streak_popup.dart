import 'package:flutter/material.dart';

import '../data/storage.dart';
import '../ui/widgets.dart';
import 'diner.dart';

class StreakPopup extends StatelessWidget {
  const StreakPopup({super.key, required this.diner, required this.game});

  final Diner diner;
  final int game;

  @override
  Widget build(BuildContext context) {
    final dayInCycle = Storage.streakDayInCycle;
    final ready = Storage.streakReady;
    final reward = Storage.nextClaimReward;
    final streak = Storage.streakCount;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: PixelBox(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── header ──────────────────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Expanded(
                    child: PxText(
                      'Daily reward',
                      style: TextStyle(color: Pal.gold, fontSize: 22),
                    ),
                  ),
                  if (streak > 0)
                    PxText(
                      '$streak day${streak == 1 ? '' : 's'} running',
                      style: const TextStyle(color: Pal.teal, fontSize: 14),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              PxText(
                ready
                    ? 'Your reward is waiting.'
                    : 'Come back tomorrow to keep the streak.',
                style: const TextStyle(color: Pal.dim, fontSize: 14),
              ),
              const SizedBox(height: 16),

              // ── row 1: days 1–4 ─────────────────────────────────────────
              Row(
                children: [
                  for (var i = 1; i <= 4; i++) ...[
                    if (i > 1) const SizedBox(width: 4),
                    Expanded(
                      child: _DayTile(
                        day: i,
                        reward: _streakRewards[i - 1],
                        isToday: i == dayInCycle,
                        isPast: ready ? false : i < dayInCycle,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              // ── row 2: days 5–7 ─────────────────────────────────────────
              Row(
                children: [
                  for (var i = 5; i <= 7; i++) ...[
                    if (i > 5) const SizedBox(width: 4),
                    Expanded(
                      child: _DayTile(
                        day: i,
                        reward: _streakRewards[i - 1],
                        isToday: i == dayInCycle,
                        isPast: ready ? false : i < dayInCycle,
                      ),
                    ),
                  ],
                  // spacer to keep day 7 the same width as days 1–4
                  const Expanded(child: SizedBox()),
                ],
              ),

              const SizedBox(height: 16),

              // ── attribution — plain text, not a button ───────────────────
              Row(
                children: [
                  const PxText(
                    ':coin:',
                    style: TextStyle(color: Pal.gold, fontSize: 16),
                  ),
                  const SizedBox(width: 6),
                  PxText(
                    diner.name,
                    style: const TextStyle(color: Pal.text, fontSize: 14),
                  ),
                  const PxText(
                    ' gets the coins',
                    style: TextStyle(color: Pal.dim, fontSize: 14),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ── action ───────────────────────────────────────────────────
              if (ready)
                GoldButton(
                  key: const ValueKey('streak-claim'),
                  label: reward.gems > 0
                      ? 'Claim ${reward.coins} coins + ${reward.gems} gem${reward.gems > 1 ? 's' : ''}'
                      : 'Claim ${reward.coins} coins',
                  onTap: () {
                    final r = Storage.claimStreak();
                    if (r.isEmpty) return;
                    diner.coins += r.coins;
                    if (r.gems > 0) Storage.pendingGems += r.gems;
                    if (Storage.streakCount > diner.maxStreakDays) {
                      diner.maxStreakDays = Storage.streakCount;
                    }
                    Storage.saveSlot(game, diner);
                    Navigator.of(context).pop(true);
                  },
                )
              else
                GoldButton(
                  key: const ValueKey('streak-tomorrow'),
                  label:
                      'Back tomorrow — +${_streakRewards[dayInCycle % 7].coins} coins',
                  filled: false,
                  color: Pal.dim,
                  onTap: () => Navigator.of(context).pop(false),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── day tile ──────────────────────────────────────────────────────────────────

class _DayTile extends StatelessWidget {
  const _DayTile({
    required this.day,
    required this.reward,
    required this.isToday,
    required this.isPast,
  });

  final int day;
  final StreakReward reward;
  final bool isToday;
  final bool isPast;

  // all tiles the same height so the two columns align
  static const _height = 72.0;

  @override
  Widget build(BuildContext context) {
    final isGemDay = reward.gems > 0;
    final bg = isToday
        ? Pal.gold
        : isPast
        ? Pal.panelLo
        : Pal.panel;
    final border = isToday ? Pal.goldDark : isGemDay ? Pal.purple : Pal.ink;
    final dayColor = isToday ? Pal.ink : Pal.dim;
    final coinColor = isToday ? Pal.ink : isPast ? Pal.dim : Pal.text;
    final gemColor = isToday ? Pal.ink : Pal.purple;

    return PixelBox(
      color: bg,
      border: border,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SizedBox(
        height: _height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PxText(
              'Day $day',
              style: TextStyle(color: dayColor, fontSize: 11),
            ),
            const SizedBox(height: 4),
            if (isPast)
              PxText(
                ':check:',
                style: const TextStyle(color: Pal.dim, fontSize: 18),
              )
            else
              PxText(
                ':coin: ${reward.coins}',
                style: TextStyle(color: coinColor, fontSize: 15),
              ),
            if (!isPast && isGemDay) ...[
              const SizedBox(height: 2),
              PxText(
                ':gem: ×${reward.gems}',
                iconMult: 0.7,
                style: TextStyle(color: gemColor, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// mirrors the schedule in storage.dart
const List<StreakReward> _streakRewards = [
  StreakReward(coins: 25,  gems: 0),
  StreakReward(coins: 50,  gems: 0),
  StreakReward(coins: 75,  gems: 1),
  StreakReward(coins: 100, gems: 0),
  StreakReward(coins: 125, gems: 0),
  StreakReward(coins: 150, gems: 0),
  StreakReward(coins: 200, gems: 3),
];
