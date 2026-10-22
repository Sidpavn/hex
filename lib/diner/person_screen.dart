import 'package:flutter/material.dart';

import '../data/storage.dart';
import '../ui/pixel_dialog.dart';
import '../ui/widgets.dart';
import 'build_screen.dart' show DinerSprite;
import 'diner.dart';
import 'recipes.dart';
import 'staff.dart';
import 'staff_widgets.dart';
import 'training_screen.dart';

/// One person: who they are, what they are good at, where they work. For
/// someone on the team it also leads to training and to letting them go; for
/// an applicant it is where they are hired.
class PersonScreen extends StatefulWidget {
  const PersonScreen({
    super.key,
    required this.diner,
    required this.staff,
    this.applicant = false,
  });

  final Diner diner;
  final Staff staff;
  final bool applicant;

  @override
  State<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends State<PersonScreen> {
  Diner get diner => widget.diner;
  Staff get s => widget.staff;
  bool get applicant => widget.applicant;

  String? _tag;
  Stat? _stat;
  String _note = '';
  bool _ok = true;

  void _save() => Storage.saveDiner(diner);

  Future<void> _fire() async {
    final ok = await askPixel(
      context,
      title: 'Let ${s.name} go?',
      body:
          'They are paid a day\'s wages, ${s.severance} coins, and leave. '
          'Everything you trained them in goes with them.',
      yes: 'Let go',
      no: 'Keep them',
      yesKey: const ValueKey('confirm-fire'),
    );
    if (!ok || !mounted) return;
    diner.fire(s);
    _save();
    Navigator.of(context).pop();
  }

  void _hire() {
    final r = diner.hire(s);
    if (r == StaffResult.ok) {
      _save();
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _ok = false;
      _note = r.message;
    });
  }

  Future<void> _train() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TrainingScreen(diner: diner, staff: s),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final full = diner.roster.employees.length >= diner.progress.staffLimit;
    final known = [
      for (final d in Dish.values)
        if (s.masteryLevel(d) > 0) d,
    ];
    return ScreenFrame(
      title: s.name,
      subtitle: applicant ? 'Looking for work' : s.role,
      trailing: PxText(
        ':coin: ${diner.coins}',
        style: const TextStyle(color: Pal.text, fontSize: 20),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          _header(),
          if (tagsFor(s).isNotEmpty) ...[
            const SizedBox(height: 12),
            TagList(
              staff: s,
              open: _tag,
              onOpen: (k) => setState(() => _tag = k),
            ),
          ],
          const SizedBox(height: 12),
          const Eyebrow('Skills'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final st in Stat.values) _statRow(st),
                if (known.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  PxText(
                    [
                      for (final d in known)
                        '${recipes[d]!.name} '
                            '${List.filled(s.masteryLevel(d), ':star:').join()}',
                    ].join('   '),
                    key: ValueKey('mastery-${s.id}'),
                    style: const TextStyle(color: Pal.gold, fontSize: 14),
                  ),
                ],
              ],
            ),
          ),
          if (!applicant) ...[
            const SizedBox(height: 12),
            const Eyebrow('Works'),
            _work(),
          ],
          const SizedBox(height: 16),
          if (applicant && s.walkIn) ...[
            PxText(
              'Walked in off the street with a CV, so the fee is half.',
              key: ValueKey('walk-in-${s.id}'),
              style: const TextStyle(color: Pal.gold, fontSize: 14),
            ),
            const SizedBox(height: 8),
          ],
          if (applicant)
            GoldButton(
              key: ValueKey('hire-${s.id}'),
              label: full ? 'No room on the team' : 'Hire  :coin: ${s.fee}',
              onTap: full || diner.coins < s.fee ? null : _hire,
            )
          else ...[
            GoldButton(
              key: ValueKey('open-training-${s.id}'),
              label: 'Train and teach',
              onTap: _train,
            ),
            const SizedBox(height: 8),
            GoldButton(
              key: ValueKey('fire-${s.id}'),
              label: 'Let go  :coin: ${s.severance}',
              filled: false,
              color: Pal.dim,
              onTap: _fire,
            ),
          ],
          if (_note.isNotEmpty) ...[
            const SizedBox(height: 8),
            PxText(
              _note,
              style: TextStyle(color: _ok ? Pal.text : Pal.red, fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }

  Widget _header() => Panel(
    key: ValueKey('${applicant ? 'cand' : 'team'}-${s.id}'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 44,
              child: Center(
                child: DinerSprite(
                  s.kitchen ? 'chef_sw_s0' : 'waiter_sw_s0',
                  mult: 2,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PxText(
                    ':coin: ${s.salary} a day',
                    style: const TextStyle(color: Pal.text, fontSize: 17),
                  ),
                  PxText(
                    applicant
                        ? 'Fee ${s.fee}'
                        : s.lastPay == Pay.missed
                        ? 'Missed a payday'
                        : s.lastPay == Pay.paid
                        ? 'Paid on time'
                        : 'New',
                    style: TextStyle(
                      color: !applicant && s.lastPay == Pay.missed
                          ? Pal.red
                          : Pal.dim,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            if (!applicant)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [MoodFace(s), const SizedBox(height: 4), MoodPips(s)],
              ),
          ],
        ),
        if (!applicant) ...[
          const SizedBox(height: 8),
          PxText(
            s.moodNote,
            key: ValueKey('mood-note-${s.id}'),
            style: TextStyle(color: moodColour(s.morale), fontSize: 14),
          ),
          if (s.memories.isNotEmpty) ...[
            const SizedBox(height: 4),
            PxText(
              s.memories.first,
              style: const TextStyle(color: Pal.dim, fontSize: 14),
            ),
          ],
        ],
      ],
    ),
  );

  Widget _statRow(Stat stat) {
    final info = statInfo[stat]!;
    final open = _stat == stat;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            key: ValueKey('stat-${s.id}-${stat.name}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _stat = open ? null : stat),
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
                  child: PxBar(
                    value: s.stat(stat) / Staff.maxStat,
                    color: Pal.gold,
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: PxText(
                    '${s.stat(stat)} / ${s.cap(stat)}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Pal.text, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: PxText(
                info.info,
                key: ValueKey('help-${s.id}-${stat.name}'),
                style: const TextStyle(color: Pal.text, fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }

  /// What they do: which machines they cook at, whether they carry food out,
  /// clear tables or run the window. Each one is a switch.
  Widget _work() {
    final machines = <Kind>[
      for (final k in Kind.values)
        if (diner.ofRole(Role.station).any((p) => p.kind == k)) k,
    ];
    final hasTables = diner.ofRole(Role.table).isNotEmpty;
    final hasWindow = diner.window != null;

    // The machines they cook at now, as a set: all of them when it is open.
    Set<Kind> cooking() => s.cooksAt == null
        ? machines.toSet()
        : s.cooksAt!.where(machines.contains).toSet();

    void save(void Function() change) {
      setState(() {
        change();
        _note = '';
      });
      _save();
    }

    bool leavesNothing(Set<Task> tasks, Set<Kind>? cooks) =>
        tasks.isEmpty && cooks != null && cooks.isEmpty;

    void refuse() => setState(() => _note = 'Keep at least one thing on');

    void cookAtAll() {
      if (s.cooksAt == null) {
        if (leavesNothing(s.tasks, {})) return refuse();
        save(() => s.cooksAt = {});
      } else {
        save(() {
          s.cooksAt = null;
          s.tasks.remove(Task.window);
        });
      }
      s.focus = null;
    }

    void cookAt(Kind k) {
      final now = cooking();
      final next = now.contains(k)
          ? (now.toSet()..remove(k))
          : (now.toSet()..add(k));
      if (leavesNothing(s.tasks, next)) return refuse();
      save(() {
        // Every machine there is: the same as "all", so new ones are included.
        s.cooksAt = next.length == machines.length ? null : next;
        if (next.isNotEmpty) s.tasks.remove(Task.window);
        s.focus = null;
      });
    }

    void task(Task t) {
      final on = s.tasks.contains(t);
      if (on && leavesNothing(s.tasks.difference({t}), s.cooksAt)) {
        return refuse();
      }
      save(() {
        if (t == Task.window && !on) {
          // The window is a job of its own.
          s.tasks = {Task.window};
          s.cooksAt = {};
          s.focus = null;
          return;
        }
        if (on) {
          s.tasks = s.tasks.difference({t});
        } else {
          s.tasks = {...s.tasks, t}..remove(Task.window);
        }
      });
    }

    String names(Iterable<Kind> kinds) {
      final list = [for (final k in kinds) fixtureDefs[k]!.name.toLowerCase()];
      if (list.length <= 1) return list.join();
      return '${list.sublist(0, list.length - 1).join(', ')} and ${list.last}';
    }

    final cook = cooking();
    final parts = <String>[
      if (s.does(Task.window))
        'stays at the takeaway window and serves the cars'
      else ...[
        if (s.cooksAt == null)
          'cooks at every machine'
        else if (cook.isNotEmpty)
          'cooks at the ${names(cook)}',
        if (s.does(Task.serve)) 'carries food out to the tables',
        if (s.does(Task.clear)) 'clears the tables',
      ],
    ];
    final help = parts.isEmpty
        ? '${s.name} does nothing. Turn something on.'
        : '${s.name} ${parts.length == 1 ? parts.first : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}'}.';

    Widget group(String label, List<Widget> chips) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PxText(label, style: const TextStyle(color: Pal.dim, fontSize: 14)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: chips),
      ],
    );

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (machines.isNotEmpty) ...[
            group('Cooks at', [
              Choice(
                key: ValueKey('cook-${s.id}-all'),
                label: 'All machines',
                selected: s.cooksAt == null,
                onTap: cookAtAll,
              ),
              for (final k in machines)
                Choice(
                  key: ValueKey('cook-${s.id}-${k.name}'),
                  label: fixtureDefs[k]!.name,
                  selected: cook.contains(k),
                  onTap: () => cookAt(k),
                ),
            ]),
            const SizedBox(height: 8),
          ],
          group('Also', [
            Choice(
              key: ValueKey('task-${s.id}-serve'),
              label: 'Serves food',
              selected: s.does(Task.serve),
              onTap: () => task(Task.serve),
            ),
            if (hasTables)
              Choice(
                key: ValueKey('task-${s.id}-clear'),
                label: 'Clears tables',
                selected: s.does(Task.clear),
                onTap: () => task(Task.clear),
              ),
            if (hasWindow)
              Choice(
                key: ValueKey('task-${s.id}-window'),
                label: 'Takeaway window',
                selected: s.does(Task.window),
                onTap: () => task(Task.window),
              ),
          ]),
          const SizedBox(height: 8),
          PxText(
            help,
            key: ValueKey('duty-help-${s.id}'),
            style: const TextStyle(color: Pal.dim, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
