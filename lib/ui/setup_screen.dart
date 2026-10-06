import 'package:flutter/material.dart';

import '../data/storage.dart';
import '../game/config.dart';
import '../game/models.dart';
import 'menu_screen.dart' show gameRoute;
import 'widgets.dart';

/// Pre-game options for skirmish and hot-seat matches.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.mode});

  final GameMode mode;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late Difficulty difficulty = Storage.difficulty;
  late UnitType hero = Storage.hero;
  late Objective objective = _initialObjective();
  int target = 0; // 0 = use the default for the objective

  bool get hot => widget.mode == GameMode.hotseat;

  Objective _initialObjective() {
    final saved = Storage.objective;
    return hot && saved == Objective.survive ? Objective.eliminate : saved;
  }

  List<Objective> get objectives => [
    Objective.eliminate,
    Objective.hold,
    if (!hot) Objective.survive,
  ];

  (int, int, int) get targetRange => switch (objective) {
    Objective.hold => (2, 6, 3),
    _ => (4, 12, 8),
  };

  static String _objectiveEmoji(Objective o) => switch (o) {
    Objective.eliminate => '⚔️',
    Objective.hold => '⭐',
    Objective.survive => '🛡️',
  };

  void _start() {
    Storage.difficulty = difficulty;
    Storage.hero = hero;
    Storage.objective = objective;
    final (_, _, def) = targetRange;
    final cfg = GameConfig(
      mode: widget.mode,
      objective: objective,
      target: target == 0 ? def : target,
      difficulty: difficulty,
      playerHero: hot ? UnitType.hero : hero,
      enemyBonusEnergy: objective == Objective.survive ? 1 : 0,
      deck: Storage.unlockedCards,
    );
    Navigator.of(context).pushReplacement(gameRoute(cfg));
  }

  @override
  Widget build(BuildContext context) {
    final (lo, hi, def) = targetRange;
    final shown = (target == 0 ? def : target).clamp(lo, hi);
    final heroes = Storage.unlockedHeroes;
    var i = 0;
    return ScreenFrame(
      title: hot ? 'Hot-seat' : 'Skirmish',
      subtitle: hot ? 'Two players, one device' : 'Fight the AI',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          if (!hot) ...[
            Entrance(
              index: i++,
              child: Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow('Difficulty'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final d in Difficulty.values)
                          Choice(
                            label: d.label,
                            emoji: switch (d) {
                              Difficulty.easy => '🌱',
                              Difficulty.normal => '⚔️',
                              Difficulty.hard => '💀',
                            },
                            selected: difficulty == d,
                            onTap: () => setState(() => difficulty = d),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      switch (difficulty) {
                        Difficulty.easy =>
                          'The AI makes mistakes and has less energy.',
                        Difficulty.normal =>
                          'A solid opponent that pushes you into hazards.',
                        Difficulty.hard =>
                          'Heals, shields, retreats and finishes you off. Extra energy.',
                      },
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Entrance(
              index: i++,
              child: Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow('Your hero'),
                    SizedBox(
                      height: 136,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final h in playableHeroes)
                            _HeroTile(
                              type: h,
                              selected: hero == h,
                              locked: !heroes.contains(h),
                              onTap: () => setState(() => hero = h),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      unitStats[hero]!.blurb,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12.5,
                      ),
                    ),
                    if (heroes.length < playableHeroes.length)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Win campaign levels to unlock more heroes.',
                          style: TextStyle(color: Pal.purple, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Entrance(
            index: i++,
            child: Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('Objective'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final o in objectives)
                        Choice(
                          label: o.label,
                          emoji: _objectiveEmoji(o),
                          selected: objective == o,
                          onTap: () => setState(() {
                            objective = o;
                            target = 0;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    objective.blurb,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12.5,
                    ),
                  ),
                  if (objective != Objective.eliminate) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text(
                          objective == Objective.hold
                              ? 'TURNS TO HOLD'
                              : 'ROUNDS TO SURVIVE',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            letterSpacing: 1.6,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '$shown',
                          style: const TextStyle(
                            color: Pal.goldLight,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Pal.gold,
                        thumbColor: Pal.goldLight,
                        inactiveTrackColor: Colors.white12,
                        overlayColor: Pal.gold.withValues(alpha: 0.2),
                        valueIndicatorColor: Pal.gold,
                      ),
                      child: Slider(
                        min: lo.toDouble(),
                        max: hi.toDouble(),
                        divisions: hi - lo,
                        value: shown.toDouble(),
                        label: '$shown',
                        onChanged: (v) => setState(() => target = v.round()),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Entrance(
            index: i++,
            child: GoldButton(label: 'Start battle', onTap: _start),
          ),
        ],
      ),
    );
  }
}

class _HeroTile extends StatelessWidget {
  const _HeroTile({
    required this.type,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final UnitType type;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final emoji = switch (type) {
      UnitType.warlord => '🦸',
      UnitType.pyromancer => '🧝',
      _ => '🧙',
    };
    final s = unitStats[type]!;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: locked ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 98,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: selected ? Pal.gold.withValues(alpha: 0.18) : Colors.white10,
            border: Border.all(
              color: selected ? Pal.goldLight : Colors.white24,
              width: selected ? 2.5 : 1.5,
            ),
            boxShadow: selected
                ? const [BoxShadow(color: Color(0x66FFC400), blurRadius: 14)]
                : null,
          ),
          child: Opacity(
            opacity: locked ? 0.4 : 1,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    locked ? '🔒' : emoji,
                    style: const TextStyle(fontSize: 34),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    '❤️ ${s.maxHp}  ⚔️ ${s.damage}',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
