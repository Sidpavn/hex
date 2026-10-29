import 'package:flutter/material.dart';

import '../ui/widgets.dart';
import 'diner.dart';
import 'hiring_screen.dart';
import 'person_screen.dart';
import 'staff.dart';
import 'staff_widgets.dart';

/// The team: one line each. Tapping a person opens their page; hiring has a
/// page of its own.
class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key, required this.diner});

  final Diner diner;

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  Diner get diner => widget.diner;
  Roster get roster => diner.roster;

  Future<void> _open(Staff s) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PersonScreen(diner: diner, staff: s),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _hire() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => HiringScreen(diner: diner)));
    if (mounted) setState(() {});
  }

  Widget _card(Staff s) => KeyedSubtree(
    key: ValueKey('team-${s.id}'),
    child: StaffCard(staff: s, onTap: () => _open(s)),
  );

  String _names(List<Kind> kinds) {
    final list = [for (final k in kinds) fixtureDefs[k]!.name.toLowerCase()];
    if (list.length <= 1) return list.join();
    return '${list.sublist(0, list.length - 1).join(', ')} and ${list.last}';
  }

  @override
  Widget build(BuildContext context) {
    final limit = diner.progress.staffLimit;
    final due = roster.wages;
    final short = due - diner.coins;
    return ScreenFrame(
      title: 'Staff',
      subtitle: '${roster.employees.length} of $limit places',
      trailing: PxText(
        ':coin: ${diner.coins}',
        style: const TextStyle(color: Pal.text, fontSize: 20),
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                PxText(
                  key: const ValueKey('payroll'),
                  short > 0
                      ? 'Wages tonight $due, but only ${diner.coins} in the '
                            'till. Unpaid people lose heart.'
                      : 'Wages $due a day, paid at the end of each day.',
                  style: TextStyle(
                    color: short > 0 ? Pal.red : Pal.dim,
                    fontSize: 14,
                  ),
                ),
                if (diner.uncoveredMachines.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  PxText(
                    'Nobody is set to the ${_names(diner.uncoveredMachines)}. '
                    'Whoever is free will cook there.',
                    key: const ValueKey('uncovered'),
                    style: const TextStyle(color: Pal.gold, fontSize: 14),
                  ),
                ],
                const SizedBox(height: 12),
                if (roster.employees.isEmpty)
                  const PxText(
                    'Nobody works here. Hire someone.',
                    style: TextStyle(color: Pal.red, fontSize: 14),
                  ),
                for (var i = 0; i < roster.employees.length; i += 2) ...[
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _card(roster.employees[i])),
                        const SizedBox(width: 8),
                        Expanded(
                          child: i + 1 < roster.employees.length
                              ? _card(roster.employees[i + 1])
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: GoldButton(
              key: const ValueKey('hire'),
              label: 'Hire someone',
              onTap: _hire,
            ),
          ),
        ],
      ),
    );
  }
}
