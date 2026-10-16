import 'package:flutter/material.dart';

import '../data/storage.dart';
import '../ui/widgets.dart';
import 'diner.dart';
import 'person_screen.dart';
import 'staff.dart';
import 'staff_widgets.dart';

/// Where new people are found. Nobody turns up on their own: an advert has to
/// be paid for, and a dearer one reaches better people. Whoever answers is
/// here for the rest of the day.
class HiringScreen extends StatefulWidget {
  const HiringScreen({super.key, required this.diner});

  final Diner diner;

  @override
  State<HiringScreen> createState() => _HiringScreenState();
}

class _HiringScreenState extends State<HiringScreen> {
  Diner get diner => widget.diner;
  Roster get roster => diner.roster;

  String _note = '';

  @override
  void initState() {
    super.initState();
    diner.lookForStaff();
  }

  void _advertise(Ad ad) {
    setState(() {
      final r = diner.advertise(ad);
      _note = r == StaffResult.ok
          ? '${adDefs[ad]!.count == 2 ? 'Two' : 'Three'} people answered'
          : r.message;
    });
    Storage.saveDiner(diner);
  }

  Future<void> _open(Staff s) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PersonScreen(diner: diner, staff: s, applicant: true),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final full = roster.employees.length >= diner.progress.staffLimit;
    return ScreenFrame(
      title: 'Hiring',
      subtitle: full
          ? 'No room on the team'
          : '${roster.employees.length} of ${diner.progress.staffLimit} places',
      trailing: PxText(
        ':coin: ${diner.coins}',
        style: const TextStyle(color: Pal.text, fontSize: 20),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          if (roster.candidates.isNotEmpty) ...[
            const Eyebrow('Answered today'),
            for (final s in roster.candidates) ...[
              StaffRow(
                key: ValueKey('cand-${s.id}'),
                staff: s,
                applicant: true,
                onTap: () => _open(s),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
          ],
          Eyebrow(roster.candidates.isEmpty ? 'Find people' : 'Look again'),
          if (full)
            const PxText(
              'The team is full. Let someone go, or add a place in the '
              'upgrades.',
              style: TextStyle(color: Pal.red, fontSize: 14),
            )
          else
            for (final ad in Ad.values) ...[
              _adCard(ad),
              const SizedBox(height: 8),
            ],
          if (_note.isNotEmpty)
            PxText(
              _note,
              key: const ValueKey('hiring-note'),
              style: TextStyle(
                color: _note.contains('answered') ? Pal.text : Pal.red,
                fontSize: 14,
              ),
            ),
        ],
      ),
    );
  }

  Widget _adCard(Ad ad) {
    final def = adDefs[ad]!;
    return Panel(
      key: ValueKey('ad-${ad.name}'),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PxText(
                  def.name,
                  style: const TextStyle(color: Pal.text, fontSize: 17),
                ),
                PxText(
                  def.info,
                  style: const TextStyle(color: Pal.dim, fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 96,
            child: GoldButton(
              key: ValueKey('advertise-${ad.name}'),
              label: ':coin: ${def.cost}',
              filled: false,
              color: Pal.text,
              onTap: diner.coins >= def.cost ? () => _advertise(ad) : null,
            ),
          ),
        ],
      ),
    );
  }
}
