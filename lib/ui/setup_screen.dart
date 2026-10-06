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

  static String _objectiveIcon(Objective o) => switch (o) {
    Objective.eliminate => 'swords',
    Objective.hold => 'star',
    Objective.survive => 'shield',
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
                            icon: switch (d) {
                              Difficulty.easy => 'sprout',
                              Difficulty.normal => 'swords',
                              Difficulty.hard => 'skull',
                            },
                            selected: difficulty == d,
                            onTap: () => setState(() => difficulty = d),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(switch (difficulty) {
                      Difficulty.easy =>
                        'The AI makes mistakes and has less energy.',
                      Difficulty.normal =>
                        'A solid opponent that pushes you into hazards.',
                      Difficulty.hard =>
                        'Heals, shields, retreats and finishes you off. Extra energy.',
                    }, style: const TextStyle(color: Pal.dim, fontSize: 13)),
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
                      height: 150,
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
                      style: const TextStyle(color: Pal.dim, fontSize: 13),
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
                          icon: _objectiveIcon(o),
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
                    style: const TextStyle(color: Pal.dim, fontSize: 13),
                  ),
                  if (objective != Objective.eliminate) ...[
                    const SizedBox(height: 14),
                    Text(
                      objective == Objective.hold
                          ? 'Turns to hold'
                          : 'Rounds to survive',
                      style: const TextStyle(color: Pal.gold, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    PxStepper(
                      value: shown,
                      min: lo,
                      max: hi,
                      onChanged: (v) => setState(() => target = v),
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
    final s = unitStats[type]!;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: locked ? null : onTap,
        child: SizedBox(
          width: 104,
          child: PixelBox(
            color: selected ? Pal.panelHi : Pal.panel,
            border: selected ? Pal.gold : Pal.ink,
            padding: const EdgeInsets.all(6),
            child: Opacity(
              opacity: locked ? 0.45 : 1,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  locked
                      ? const SizedBox(
                          height: 32,
                          child: PxIcon('lock', mult: 2),
                        )
                      : UnitPortrait(type, mult: 2),
                  const SizedBox(height: 4),
                  Text(
                    s.name,
                    style: const TextStyle(color: Pal.text, fontSize: 15),
                  ),
                  PxText(
                    ':heart: ${s.maxHp}  :swords: ${s.damage}',
                    style: const TextStyle(color: Pal.dim, fontSize: 13),
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
