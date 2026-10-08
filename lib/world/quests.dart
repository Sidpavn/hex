import '../game/hex.dart';
import '../game/models.dart';
import 'quest_rules.dart';
import 'world_state.dart';
import 'zone.dart';

export 'quest_rules.dart';

/// One line of conversation and what the player can answer.
class Dialogue {
  const Dialogue(this.speaker, this.lines, [this.choices = const []]);

  final String speaker;
  final List<String> lines;

  /// Empty means "tap to close".
  final List<DialogueChoice> choices;
}

class DialogueChoice {
  const DialogueChoice(this.text, [this.effects = const []])
    : showGains = false;

  /// A choice that hands something in: the label lists what you get, taken
  /// from [effects] so the text can't drift from what happens.
  const DialogueChoice.reward(this.text, this.effects) : showGains = true;

  final String text;
  final bool showGains;

  /// What happens when it is picked (accepting a quest, handing something in).
  final List<Effect> effects;

  String get label {
    if (!showGains) return text;
    final gains = [for (final e in effects) ?e.summary];
    return gains.isEmpty ? text : '$text (${gains.join(', ')})';
  }

  void apply(WorldState w) {
    for (final e in effects) {
      e.apply(w);
    }
  }
}

/// Where the active quest wants you to go.
class QuestObjective {
  const QuestObjective(
    this.zone,
    this.text, {
    this.npc,
    this.item,
    this.unit,
    this.hint,
  });

  final String zone;
  final String text;

  /// Id of the NPC or item to head for in [zone].
  final String? npc;
  final String? item;

  /// Type of creature to head for in [zone] (the first of that type).
  final UnitType? unit;

  /// A quick-bar item or spell id to point at while this is the goal.
  final String? hint;
}

/// The first rule whose [when] holds decides the result. Order them from most
/// to least specific.
class Rule<T> {
  const Rule(this.when, this.value);

  final Condition when;
  final T value;
}

/// A quest and everything it says. The stage in [WorldState.quests] is
/// 0 not started, 1 accepted, and [doneStage] or later finished; stages in
/// between are free for longer quests.
class Quest {
  const Quest({
    required this.id,
    required this.title,
    required this.giver,
    required this.summary,
    required this.objectives,
    this.requires = const Always(),
    this.doneStage = 2,
  });

  final String id;
  final String title;

  /// Display name of who to talk to to start it.
  final String giver;
  final String summary;
  final int doneStage;

  /// Must hold for the quest to appear in the journal. Once you have started
  /// it, it stays listed whatever happens to this.
  final Condition requires;

  /// Where to go next, by situation. No match means no objective.
  final List<Rule<QuestObjective>> objectives;

  int stage(WorldState w) => w.quests[id] ?? 0;
  bool isListed(WorldState w) => stage(w) > 0 || requires.test(w);
  bool isDone(WorldState w) => stage(w) >= doneStage;
  bool isActive(WorldState w) => stage(w) > 0 && !isDone(w);

  QuestObjective? objective(WorldState w) {
    if (isDone(w)) return null;
    for (final r in objectives) {
      if (r.when.test(w)) return r.value;
    }
    return null;
  }
}

/// What an NPC says and shows, by situation.
class NpcScript {
  const NpcScript({this.talk = const [], this.marks = const []});

  final List<Rule<Dialogue>> talk;

  /// `alert` (has a quest for you) or `search` (a quest of yours is ready to
  /// hand in).
  final List<Rule<String?>> marks;
}

// ───────────────────────── content ─────────────────────────

const List<Quest> quests = [
  Quest(
    id: 'training',
    title: 'Basic training',
    giver: 'Tobin',
    summary:
        'Tobin runs the training ground. Learn the sword, the bow and '
        'healing, then head out to the meadow.',
    doneStage: 5,
    objectives: [
      // 1: the sword.
      Rule(
        All([
          QuestAt('training', 1),
          Not(HasItem('sword')),
          Collected('training#sword'),
        ]),
        QuestObjective('training', 'Ask Tobin for a sword.', npc: 'trainer'),
      ),
      Rule(
        All([QuestAt('training', 1), Not(HasItem('sword'))]),
        QuestObjective('training', 'Pick up the sword.', item: 'sword'),
      ),
      Rule(
        All([QuestAt('training', 1), Not(Count(Counts.postMelee, 3))]),
        QuestObjective(
          'training',
          'Hit the training post 3 times.',
          unit: UnitType.post,
        ),
      ),
      Rule(
        QuestAt('training', 1),
        QuestObjective('training', 'Tell Tobin.', npc: 'trainer'),
      ),
      // 2: the bow.
      Rule(
        All([
          QuestAt('training', 2),
          Not(HasItem('bow')),
          Collected('training#bow'),
        ]),
        QuestObjective('training', 'Ask Tobin for a bow.', npc: 'trainer'),
      ),
      Rule(
        All([QuestAt('training', 2), Not(HasItem('bow'))]),
        QuestObjective('training', 'Pick up the bow.', item: 'bow'),
      ),
      Rule(
        All([
          QuestAt('training', 2),
          Not(Holding('bow')),
          Not(Count(Counts.postRanged, 3)),
        ]),
        QuestObjective(
          'training',
          'Tap the bow on the quick bar to hold it.',
          hint: 'bow',
        ),
      ),
      Rule(
        All([QuestAt('training', 2), Not(Count(Counts.postRanged, 3))]),
        QuestObjective(
          'training',
          'Shoot the training post 3 times.',
          unit: UnitType.post,
        ),
      ),
      Rule(
        QuestAt('training', 2),
        QuestObjective('training', 'Tell Tobin.', npc: 'trainer'),
      ),
      // 3: Tobin hurts you and teaches Mend. 4: you cast it.
      Rule(
        QuestAt('training', 3),
        QuestObjective(
          'training',
          'Talk to Tobin about healing.',
          npc: 'trainer',
        ),
      ),
      Rule(
        All([QuestAt('training', 4), Not(Count(Counts.castMend, 1))]),
        QuestObjective(
          'training',
          'Cast Mend from the quick bar.',
          hint: 'mend',
        ),
      ),
      Rule(
        QuestAt('training', 4),
        QuestObjective('training', 'Tell Tobin.', npc: 'trainer'),
      ),
    ],
  ),
  Quest(
    id: 'lantern',
    title: "Mara's Lantern",
    giver: 'Mara',
    summary:
        'Mara dropped her lantern in the Hollow Deep, the cave beyond the '
        'ridge. Find it and bring it back.',
    objectives: [
      Rule(
        HasItem('lantern'),
        QuestObjective(
          'meadow',
          'Bring the lantern back to Mara.',
          npc: 'mara',
        ),
      ),
      Rule(
        All([QuestAt('lantern', 1), Repaired('meadow', 1)]),
        QuestObjective(
          'cave',
          'Find the lantern in the Hollow Deep.',
          item: 'lantern',
        ),
      ),
      Rule(
        All([QuestAt('lantern', 1), HasItem('hatchet')]),
        QuestObjective('meadow', 'Chop trees and mend the bridge.'),
      ),
      Rule(
        QuestAt('lantern', 1),
        QuestObjective(
          'mine',
          'Find the hatchet in the Old Mine.',
          item: 'hatchet',
        ),
      ),
    ],
  ),
];

const Map<String, NpcScript> npcScripts = {
  'trainer': NpcScript(
    marks: [
      Rule(QuestFrom('training', 5), null),
      Rule(QuestAt('training', 0), 'alert'),
      Rule(
        All([
          QuestAt('training', 1),
          HasItem('sword'),
          Count(Counts.postMelee, 3),
        ]),
        'search',
      ),
      Rule(
        All([
          QuestAt('training', 2),
          HasItem('bow'),
          Count(Counts.postRanged, 3),
        ]),
        'search',
      ),
      Rule(
        All([
          QuestAt('training', 1),
          Not(HasItem('sword')),
          Collected('training#sword'),
        ]),
        'search',
      ),
      Rule(
        All([
          QuestAt('training', 2),
          Not(HasItem('bow')),
          Collected('training#bow'),
        ]),
        'search',
      ),
      Rule(QuestAt('training', 3), 'search'),
      Rule(All([QuestAt('training', 4), Count(Counts.castMend, 1)]), 'search'),
    ],
    talk: [
      Rule(
        QuestFrom('training', 5),
        Dialogue('Tobin', [
          'The meadow is through the gate to the east.',
          'Stay on the paths until you know what lives out there.',
        ]),
      ),
      Rule(
        All([QuestAt('training', 4), Count(Counts.castMend, 1)]),
        Dialogue(
          'Tobin',
          ['That is everything I can teach you here.'],
          [
            DialogueChoice('Thanks', [SetQuest('training', 5)]),
          ],
        ),
      ),
      Rule(
        All([QuestAt('training', 4), Wounded()]),
        Dialogue('Tobin', ['Tap Mend on the quick bar. It costs 2 mana.']),
      ),
      Rule(
        QuestAt('training', 4),
        Dialogue(
          'Tobin',
          ['You healed on your own. Hold still and I will fix that.'],
          [
            DialogueChoice('Hold still', [Hurt(4)]),
          ],
        ),
      ),
      Rule(
        QuestAt('training', 3),
        Dialogue(
          'Tobin',
          [
            'Last one: healing. Mend costs 2 mana and restores 3 HP.',
            'It uses the same mana as your attack spells, and mana comes '
                'back slowly. A potion heals without any.',
            'You need to be hurt to use it, so hold still.',
          ],
          [
            DialogueChoice('Hold still', [
              LearnSpell('mend'),
              Hurt(4),
              ResetCount(Counts.castMend),
              SetQuest('training', 4),
            ]),
          ],
        ),
      ),
      Rule(
        All([
          QuestAt('training', 2),
          HasItem('bow'),
          Count(Counts.postRanged, 3),
        ]),
        Dialogue(
          'Tobin',
          ['The bow only works from 2 to 4 hexes, with nothing in the way.'],
          [
            DialogueChoice('Got it', [SetQuest('training', 3)]),
          ],
        ),
      ),
      Rule(
        All([QuestAt('training', 2), HasItem('bow'), Not(Holding('bow'))]),
        Dialogue('Tobin', [
          'You are still holding the sword. Tap the bow on the quick bar '
              'to take it in hand.',
          'Then step back 2 to 4 hexes from the post and tap it.',
        ]),
      ),
      Rule(
        All([QuestAt('training', 2), HasItem('bow')]),
        Dialogue('Tobin', [
          'Step back 2 to 4 hexes from the post and tap it. Trees and '
              'mountains block the shot.',
        ]),
      ),
      Rule(
        All([
          QuestAt('training', 2),
          Not(HasItem('bow')),
          Collected('training#bow'),
        ]),
        Dialogue(
          'Tobin',
          ['Lost the bow? I keep spares.'],
          [
            DialogueChoice('Take it', [GiveItem('bow')]),
          ],
        ),
      ),
      Rule(
        QuestAt('training', 2),
        Dialogue('Tobin', [
          'The bow is lying further east. Walk over it to pick it up.',
        ]),
      ),
      Rule(
        All([
          QuestAt('training', 1),
          HasItem('sword'),
          Count(Counts.postMelee, 3),
        ]),
        Dialogue(
          'Tobin',
          [
            'A sword only hits the hex next to you, so close in before you swing.',
          ],
          [
            DialogueChoice('Got it', [
              SetQuest('training', 2),
              ResetCount(Counts.postRanged),
            ]),
          ],
        ),
      ),
      Rule(
        All([QuestAt('training', 1), HasItem('sword')]),
        Dialogue('Tobin', [
          'Walk up to the post and tap it. The sword only reaches the next hex.',
        ]),
      ),
      Rule(
        All([
          QuestAt('training', 1),
          Not(HasItem('sword')),
          Collected('training#sword'),
        ]),
        Dialogue(
          'Tobin',
          ['Lost the sword? I keep spares.'],
          [
            DialogueChoice('Take it', [GiveItem('sword')]),
          ],
        ),
      ),
      Rule(
        QuestAt('training', 1),
        Dialogue('Tobin', [
          'The sword is lying a few hexes east of here. Walk over it to '
              'pick it up.',
        ]),
      ),
      Rule(
        Always(),
        Dialogue(
          'Tobin',
          [
            'New here? Everyone starts with empty hands.',
            'I will show you the sword, the bow and healing, in that order.',
          ],
          [
            DialogueChoice('Show me', [
              SetQuest('training', 1),
              ResetCount(Counts.postMelee),
              ResetCount(Counts.postRanged),
            ]),
            DialogueChoice('Not now'),
          ],
        ),
      ),
    ],
  ),
  'mara': NpcScript(
    marks: [
      Rule(QuestFrom('lantern', 2), null),
      Rule(HasItem('lantern'), 'search'),
      Rule(QuestAt('lantern', 0), 'alert'),
    ],
    talk: [
      Rule(
        QuestFrom('lantern', 2),
        Dialogue('Mara', [
          'The light is back in my window. Thank you again, traveller.',
        ]),
      ),
      Rule(
        HasItem('lantern'),
        Dialogue(
          'Mara',
          ['My lantern! You found it!', 'Please, take these.'],
          [
            DialogueChoice.reward('Hand it over', [
              TakeItem('lantern'),
              SetQuest('lantern', 2),
              GiveTokens(3),
              GiveItem('potion', 2),
            ]),
          ],
        ),
      ),
      Rule(
        All([QuestAt('lantern', 1), Repaired('meadow', 1)]),
        Dialogue('Mara', [
          'The bridge holds again. The cave is north-east, past the ridge.',
          'Mind the things that sleep in the dark.',
        ]),
      ),
      Rule(
        All([QuestAt('lantern', 1), HasItem('hatchet')]),
        Dialogue('Mara', [
          'That is my husband\'s hatchet. He kept it sharp.',
          'Chop the trees by the river. Five wood is enough to mend the '
              'bridge.',
        ]),
      ),
      Rule(
        QuestAt('lantern', 1),
        Dialogue('Mara', [
          'The cave is across the river, but the bridge is broken.',
          'My husband\'s hatchet is in the old mine, in the north-west corner '
              'of the meadow. With wood from the trees you can mend it.',
        ]),
      ),
      Rule(
        Always(),
        Dialogue(
          'Mara',
          [
            'Oh, a traveller! Please, I dropped my lantern in the cave past '
                'the ridge, across the river.',
            'It is the only light I have for the winter nights. Would you '
                'fetch it?',
          ],
          [
            DialogueChoice('I will find it', [SetQuest('lantern', 1)]),
            DialogueChoice('Not now'),
          ],
        ),
      ),
    ],
  ),
};

/// A portal that stays shut until [requires] holds. Keyed `zone#portal`.
class Gate {
  const Gate(this.requires, this.message);

  final Condition requires;

  /// What to tell the player when they walk into it.
  final String message;
}

const Map<String, Gate> gates = {
  'training#1': Gate(QuestFrom('training', 5), 'Finish your training first.'),
};

/// The gate stopping [portal] in [zone], or null if it is open.
Gate? closedGate(String zone, String portal, WorldState w) {
  final g = gates['$zone#$portal'];
  return g != null && !g.requires.test(w) ? g : null;
}

// ───────────────────────── lookups ─────────────────────────

Quest? questById(String id) {
  for (final q in quests) {
    if (q.id == id) return q;
  }
  return null;
}

int questStage(WorldState w, String id) => w.quests[id] ?? 0;

T? _first<T>(List<Rule<T>> rules, WorldState w) {
  for (final r in rules) {
    if (r.when.test(w)) return r.value;
  }
  return null;
}

/// What to show over an NPC's head, if anything.
String? npcMark(NpcSpawn npc, WorldState w) {
  final script = npcScripts[npc.id];
  return script == null ? null : _first<String?>(script.marks, w);
}

/// What an NPC says right now, given how the world looks.
Dialogue talkTo(NpcSpawn npc, WorldState w) {
  final script = npcScripts[npc.id];
  return (script == null ? null : _first(script.talk, w)) ??
      Dialogue(npc.name, const ['...']);
}

/// The goal to point at: the first active quest that has one.
QuestObjective? currentObjective(WorldState w) {
  for (final q in quests) {
    final o = q.objective(w);
    if (o != null) return o;
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
    if (o.unit != null) {
      for (final e in z.enemies) {
        if (e.type == o.unit) return e.hex;
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
