import '../game/hex.dart';
import 'world_state.dart';
import 'zone.dart';

/// One line of conversation and what the player can answer.
class Dialogue {
  const Dialogue(this.speaker, this.lines, [this.choices = const []]);

  final String speaker;
  final List<String> lines;

  /// Empty means "tap to close".
  final List<DialogueChoice> choices;
}

class DialogueChoice {
  const DialogueChoice(this.label, [this.apply]);

  final String label;

  /// What happens when it is picked (accepting a quest, handing something in).
  final void Function(WorldState)? apply;
}

/// Where the active quest wants you to go.
class QuestObjective {
  const QuestObjective(this.zone, this.text, {this.npc, this.item});

  final String zone;
  final String text;

  /// Id of the NPC or item to head for in [zone].
  final String? npc;
  final String? item;
}

class QuestInfo {
  const QuestInfo(this.id, this.title, this.giver, this.summary);

  final String id;
  final String title;
  final String giver;
  final String summary;
}

/// The quests that exist. A quest id maps to a stage in
/// [WorldState.quests]: 0 not started, 1 accepted, 2 done.
const List<QuestInfo> questList = [
  QuestInfo(
    'lantern',
    "Mara's Lantern",
    'Mara',
    'Mara dropped her lantern in the Hollow Deep, the cave beyond the ridge. '
        'Find it and bring it back.',
  ),
];

int questStage(WorldState w, String id) => w.quests[id] ?? 0;

/// What to show over an NPC's head: `alert` (has a quest for you) or `search`
/// (a quest of yours is ready to hand in).
String? npcMark(NpcSpawn npc, WorldState w) {
  if (npc.id != 'mara') return null;
  final stage = questStage(w, 'lantern');
  if (stage >= 2) return null;
  if (w.inventory.contains('lantern')) return 'search';
  return stage == 0 ? 'alert' : null;
}

/// What an NPC says right now, given how the world looks.
Dialogue talkTo(NpcSpawn npc, WorldState w) {
  switch (npc.id) {
    case 'mara':
      final stage = questStage(w, 'lantern');
      final has = w.inventory.contains('lantern');
      if (stage >= 2) {
        return const Dialogue('Mara', [
          'The light is back in my window. Thank you again, traveller.',
        ]);
      }
      if (has) {
        return Dialogue(
          'Mara',
          const [
            'My lantern! You found it!',
            'Please, take these. You have earned them.',
          ],
          [
            DialogueChoice('Hand it over (+3 tokens)', (w) {
              w.inventory.remove('lantern');
              w.quests['lantern'] = 2;
              w.tokens += 3;
            }),
          ],
        );
      }
      if (stage == 1) {
        return const Dialogue('Mara', [
          'The cave is north-east, past the river and the ridge.',
          'Mind the things that sleep in the dark.',
        ]);
      }
      return Dialogue(
        'Mara',
        const [
          'Oh, a traveller! Please, I dropped my lantern in the cave past the ridge.',
          'It is the only light I have for the winter nights. Would you fetch it?',
        ],
        [
          DialogueChoice('I will find it', (w) => w.quests['lantern'] = 1),
          const DialogueChoice('Not now'),
        ],
      );
  }
  return Dialogue(npc.name, const ['...']);
}

/// The active quest's goal, if any.
QuestObjective? currentObjective(WorldState w) {
  final stage = questStage(w, 'lantern');
  if (stage >= 2) return null;
  if (w.inventory.contains('lantern')) {
    return const QuestObjective(
      'meadow',
      "Bring the lantern back to Mara.",
      npc: 'mara',
    );
  }
  if (stage == 1) {
    return const QuestObjective(
      'cave',
      'Find the lantern in the Hollow Deep.',
      item: 'lantern',
    );
  }
  return null;
}

/// Where to point the player inside [current]: the objective itself if it is
/// here, otherwise the portal that leads toward it.
Hex? markerHex(Zone current, QuestObjective o, Map<String, Zone> zones) {
  Hex? target(Zone z) {
    if (o.npc != null) {
      for (final n in z.npcs) {
        if (n.id == o.npc) return n.hex;
      }
    }
    if (o.item != null) {
      for (final i in z.items) {
        if (i.id == o.item) return i.hex;
      }
    }
    return null;
  }

  if (current.id == o.zone) return target(current);
  // Breadth-first search over zone links for the first portal on the way.
  final firstStep = <String, Hex>{};
  final queue = <String>[];
  for (final p in current.portals.values) {
    final hex = current.portalHex[p.id];
    if (hex != null && !firstStep.containsKey(p.toZone)) {
      firstStep[p.toZone] = hex;
      queue.add(p.toZone);
    }
  }
  final seen = {current.id, ...queue};
  while (queue.isNotEmpty) {
    final id = queue.removeAt(0);
    if (id == o.zone) return firstStep[id];
    final z = zones[id];
    if (z == null) continue;
    for (final p in z.portals.values) {
      if (seen.add(p.toZone)) {
        firstStep[p.toZone] = firstStep[id]!;
        queue.add(p.toZone);
      }
    }
  }
  return null;
}
