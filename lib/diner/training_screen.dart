import 'package:flutter/material.dart';

import '../data/storage.dart';
import '../ui/widgets.dart';
import 'diner.dart';
import 'recipes.dart';
import 'staff.dart';

/// Lessons for one person: a point in a stat, or how to make a hard dish.
/// Either is one lesson a day.
class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key, required this.diner, required this.staff});

  final Diner diner;
  final Staff staff;

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  Diner get diner => widget.diner;
  Staff get s => widget.staff;

  String _note = '';
  bool _ok = true;

  void _do(StaffResult Function() act, String done) {
    setState(() {
      final r = act();
      _ok = r == StaffResult.ok;
      _note = _ok ? done : r.message;
    });
    Storage.saveDiner(diner);
  }

  @override
  Widget build(BuildContext context) {
    final loc = diner.locationDef;
    final teach = [
      for (final r in recipes.values)
        if (r.skilled &&
            loc.dishes.contains(r.dish) &&
            diner.progress.level >=
                (loc.unlockAt[r.dish] ?? recipes[r.dish]!.unlock)) r,
    ];
    return ScreenFrame(
      title: 'Train ${s.name}',
      subtitle: s.trainedToday ? 'Had their lesson today' : 'One lesson a day',
      trailing: PxText(
        ':coin: ${diner.coins}',
        style: const TextStyle(color: Pal.text, fontSize: 20),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          const SizedBox(height: 8),
          const Eyebrow('Skills'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final st in Stat.values) _statRow(st)],
            ),
          ),
          if (teach.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Eyebrow('Recipes'),
            for (final r in teach) ...[
              _recipeRow(r),
              const SizedBox(height: 8),
            ],
          ],
          if (_note.isNotEmpty) ...[
            const SizedBox(height: 4),
            PxText(
              _note,
              key: const ValueKey('training-note'),
              style: TextStyle(color: _ok ? Pal.text : Pal.red, fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statRow(Stat stat) {
    final info = statInfo[stat]!;
    final maxed = s.stat(stat) >= s.cap(stat);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: PxText(
              info.name,
              style: const TextStyle(color: Pal.dim, fontSize: 14),
            ),
          ),
          Expanded(
            child: PxBar(value: s.stat(stat) / Staff.maxStat, color: Pal.gold),
          ),
          SizedBox(
            width: 56,
            child: PxText(
              '${s.stat(stat)} / ${s.cap(stat)}',
              textAlign: TextAlign.right,
              style: const TextStyle(color: Pal.text, fontSize: 14),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 84,
            child: GoldButton(
              key: ValueKey('train-${s.id}-${stat.name}'),
              label: maxed ? 'Full' : ':coin: ${s.trainCost(stat)}',
              filled: false,
              color: Pal.text,
              onTap: s.canTrain(stat) && diner.coins >= s.trainCost(stat)
                  ? () => _do(
                      () => diner.train(s, stat),
                      '${s.name} improved at ${info.name.toLowerCase()}',
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _recipeRow(Recipe r) {
    final knows = s.canCook(r.dish);
    final level = s.masteryLevel(r.dish);
    return Panel(
      key: ValueKey('recipe-${s.id}-${r.dish.name}'),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PxText(
                  r.name,
                  style: const TextStyle(color: Pal.text, fontSize: 17),
                ),
                PxText(
                  knows
                      ? level > 0
                            ? 'Knows how  ${List.filled(level, ':star:').join()}'
                            : 'Knows how'
                      : 'Does not know how yet',
                  key: knows && level > 0 ? ValueKey('mastery-${s.id}') : null,
                  style: TextStyle(
                    color: knows ? Pal.gold : Pal.dim,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          if (!knows)
            SizedBox(
              width: 150,
              child: GoldButton(
                key: ValueKey('teach-${s.id}-${r.dish.name}'),
                label: 'Teach  :coin: ${Diner.teachCost}',
                filled: false,
                color: Pal.text,
                onTap: s.trainedToday || diner.coins < Diner.teachCost
                    ? null
                    : () => _do(
                        () => diner.teach(s, r.dish),
                        '${s.name} learned to make '
                        '${r.name.toLowerCase()}',
                      ),
              ),
            ),
        ],
      ),
    );
  }
}
