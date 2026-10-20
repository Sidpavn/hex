import 'package:flutter/material.dart';

import '../ui/widgets.dart';
import 'build_screen.dart' show DinerSprite;
import 'recipes.dart';
import 'staff.dart';
import 'traits.dart';

/// Pieces shared by the staff pages.

Color moodColour(int morale) => switch (morale) {
  >= 3 => Pal.green,
  2 => Pal.gold,
  _ => Pal.red,
};

/// A face and a word for how they feel.
class MoodFace extends StatelessWidget {
  const MoodFace(this.staff, {super.key});

  final Staff staff;

  @override
  Widget build(BuildContext context) => Row(
    key: ValueKey('mood-${staff.id}'),
    mainAxisSize: MainAxisSize.min,
    children: [
      PxText(
        staff.mood,
        style: TextStyle(color: moodColour(staff.morale), fontSize: 14),
      ),
      const SizedBox(width: 6),
      DinerSprite('mood_${staff.morale.clamp(0, 3)}', mult: 2),
    ],
  );
}

/// Three pips under the face: how much heart they have left.
class MoodPips extends StatelessWidget {
  const MoodPips(this.staff, {super.key});

  final Staff staff;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < Staff.maxMorale; i++)
        Container(
          key: ValueKey('pip-${staff.id}-$i'),
          width: 10,
          height: 6,
          margin: const EdgeInsets.only(left: 3),
          color: i < staff.morale ? moodColour(staff.morale) : Pal.panelLo,
        ),
    ],
  );
}

/// One person in a list: who they are and what they cost, on one line each.
/// Tapping it opens their page.
class StaffRow extends StatelessWidget {
  const StaffRow({
    super.key,
    required this.staff,
    required this.onTap,
    this.applicant = false,
  });

  final Staff staff;
  final VoidCallback onTap;

  /// Someone looking for work rather than on the team.
  final bool applicant;

  @override
  Widget build(BuildContext context) {
    final s = staff;
    final missed = !applicant && s.lastPay == Pay.missed;
    return Panel(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Center(
              child: DinerSprite(s.kitchen ? 'chef_sw_s0' : 'waiter_sw_s0'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PxText(
                  '${s.name}   ${s.role}',
                  style: const TextStyle(color: Pal.text, fontSize: 17),
                ),
                PxText(
                  missed
                      ? ':coin: ${s.salary} a day   missed a payday'
                      : ':coin: ${s.salary} a day',
                  style: TextStyle(
                    color: missed ? Pal.red : Pal.dim,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          if (applicant)
            PxText(
              s.walkIn ? 'walked in, fee ${s.fee}' : 'fee ${s.fee}',
              style: const TextStyle(color: Pal.dim, fontSize: 14),
            )
          else
            MoodFace(s),
        ],
      ),
    );
  }
}

/// A quirk or speciality shown as a tag, with what it means.
class TagInfo {
  const TagInfo(this.key, this.label, this.colour, this.help);

  final String key;
  final String label;
  final Color colour;
  final String help;
}

/// Their quirks as tags: green for good, red for bad, plain for a bit of
/// both. Anything not yet found out shows as a question mark.
List<TagInfo> tagsFor(Staff s) {
  Color colour(Tone t) => switch (t) {
    Tone.good => Pal.green,
    Tone.bad => Pal.red,
    Tone.mixed => Pal.gold,
  };
  return [
    if (s.specialty != null)
      TagInfo(
        'specialty',
        '${recipes[s.specialty]!.name} specialist',
        Pal.gold,
        'Came here already knowing how to make '
            '${recipes[s.specialty]!.name.toLowerCase()}, and is better at it '
            'from the start.',
      ),
    for (final t in s.visibleTraits)
      TagInfo(
        t.name,
        traitInfo[t]!.name,
        colour(traitInfo[t]!.tone),
        traitInfo[t]!.info,
      ),
    if (s.hiddenTraits > 0)
      TagInfo(
        'hidden',
        '?',
        Pal.dim,
        'There is more to ${s.name} than the interview showed. You will find '
            'out in time.',
      ),
  ];
}

/// The tags of [s], each tappable. The help for the open one is shown right
/// under the tags, where the eye already is.
class TagList extends StatelessWidget {
  const TagList({
    super.key,
    required this.staff,
    required this.open,
    required this.onOpen,
  });

  final Staff staff;
  final String? open;
  final ValueChanged<String?> onOpen;

  @override
  Widget build(BuildContext context) {
    final tags = tagsFor(staff);
    if (tags.isEmpty) return const SizedBox.shrink();
    final shown = tags.where((t) => t.key == open).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in tags)
              GestureDetector(
                key: ValueKey('trait-${staff.id}-${t.key}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => onOpen(open == t.key ? null : t.key),
                child: Tag(t.label, color: t.colour),
              ),
          ],
        ),
        if (shown != null) ...[
          const SizedBox(height: 6),
          PxText(
            shown.help,
            key: ValueKey('help-${staff.id}'),
            style: const TextStyle(color: Pal.text, fontSize: 14),
          ),
        ],
      ],
    );
  }
}
