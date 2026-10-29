import 'package:flutter/material.dart';

import '../data/save_sync.dart';

import '../ui/widgets.dart';
import 'diner.dart';
import 'goals.dart';
import 'guide.dart';
import '../data/play_games_store.dart';
import '../data/storage.dart';
import 'save_panel.dart';
import 'settings_screen.dart';

/// What to aim for: the next few goals with how to go about each, then what
/// is further off, then what has been done.
class GoalsScreen extends StatefulWidget {
  const GoalsScreen({
    super.key,
    required this.diner,
    this.onReset,
    this.onLoad,
    this.store,
    this.onTitle,
  });

  final Diner diner;

  /// Wipes the save and starts again. A testing aid, kept out of the way.
  final VoidCallback? onReset;

  /// Where the save is also kept off the phone. By default Google Play
  /// Games on Android, and nowhere else.
  final CloudStore? store;

  /// Called to save, just before going back to the title screen.
  final VoidCallback? onTitle;

  /// Carries on from a save the player pasted in.
  final ValueChanged<Diner>? onLoad;

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  Diner get diner => widget.diner;
  VoidCallback? get onReset => widget.onReset;
  CloudStore? get store => widget.store;
  VoidCallback? get onTitle => widget.onTitle;
  ValueChanged<Diner>? get onLoad => widget.onLoad;

  /// Done goals start folded away: once there are a lot of them, they would
  /// otherwise push everything else on the page a long way down.
  bool _doneOpen = false;

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
            _nextGoals(next),
            const SizedBox(height: 8),
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
            _doneHeader(done.length),
            if (_doneOpen) ...[
              const SizedBox(height: 8),
              for (final g in done) ...[
                _row(g, Pal.green),
                const SizedBox(height: 6),
              ],
            ],
          ],
          const SizedBox(height: 24),
          ButtonRow(
            children: [
              GoldButton(
                key: const ValueKey('open-guide'),
                label: 'How to play',
                filled: false,
                color: Pal.text,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const GuideScreen()),
                ),
              ),
              GoldButton(
                key: const ValueKey('open-settings'),
                label: ':gear: Settings',
                filled: false,
                color: Pal.text,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SettingsScreen(diner: diner),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Eyebrow('Your save'),
          SavePanel(
            diner: diner,
            onSave: () => Storage.saveDiner(diner),
            onTitle: onTitle == null
                ? null
                : () {
                    onTitle!();
                    // Back to the first screen, which is the title.
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  },
            store: store ?? defaultCloudStore(slot: Storage.slot),
            onLoad: onLoad == null
                ? null
                : (d) {
                    onLoad!(d);
                    Navigator.of(context).pop();
                  },
          ),
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

  /// The "Done" heading, tappable to fold its list away: with enough goals
  /// met, that list would otherwise push the rest of the page far down.
  Widget _doneHeader(int count) => GestureDetector(
    key: const ValueKey('done-toggle'),
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() => _doneOpen = !_doneOpen),
    child: Row(
      children: [
        Expanded(
          child: PxText(
            'Done ($count)',
            style: const TextStyle(color: Pal.gold, fontSize: 14),
          ),
        ),
        PxText(
          _doneOpen ? 'Hide' : 'Show',
          style: const TextStyle(color: Pal.dim, fontSize: 14),
        ),
      ],
    ),
  );

  /// The goals to aim for next, grouped in one static panel: nothing here
  /// is tappable, so it must not read as a stack of separate buttons the
  /// way a list of saved games or staff rows does elsewhere in the app.
  Widget _nextGoals(List<Goal> goals) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < goals.length; i++) ...[
          if (i > 0) ...[
            const SizedBox(height: 6),
            Container(height: 1, color: Pal.panelLo),
            const SizedBox(height: 6),
          ],
          _goalLine(goals[i]),
        ],
      ],
    ),
  );

  Widget _goalLine(Goal g) => Column(
    key: ValueKey('goal-${g.id}'),
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
