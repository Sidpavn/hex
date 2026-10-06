import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hex/world/pathfinding.dart';
import 'package:hex/world/quests.dart';
import 'package:hex/world/world_state.dart';
import 'package:hex/world/zone.dart';

Map<String, Zone> _zones() => {
  for (final id in ZoneRepo.ids)
    id: Zone.parse(File('assets/zones/$id.txt').readAsStringSync()),
};

void main() {
  final zones = _zones();
  final mara = zones['meadow']!.npcs.firstWhere((n) => n.id == 'mara');

  test('Mara offers the quest, accepts it, then takes the lantern', () {
    final w = WorldState();
    expect(npcMark(mara, w), 'alert');
    var d = talkTo(mara, w);
    expect(d.choices.map((c) => c.label), contains('I will find it'));
    d.choices.first.apply!(w);
    expect(questStage(w, 'lantern'), 1);
    expect(npcMark(mara, w), isNull);
    expect(currentObjective(w)?.zone, 'cave');

    // Talking again before finding it only gives a hint.
    d = talkTo(mara, w);
    expect(d.choices, isEmpty);

    // Pick the lantern up: she is now waiting for it.
    w.addItem('lantern');
    expect(npcMark(mara, w), 'search');
    expect(currentObjective(w)?.zone, 'meadow');
    d = talkTo(mara, w);
    d.choices.single.apply!(w);
    expect(questStage(w, 'lantern'), 2);
    expect(w.tokens, 3);
    expect(w.hasItem('lantern'), isFalse);
    expect(currentObjective(w), isNull);
    expect(npcMark(mara, w), isNull);
  });

  test('finding the lantern before accepting still lets you hand it in', () {
    final w = WorldState()..addItem('lantern');
    final d = talkTo(mara, w);
    d.choices.single.apply!(w);
    expect(w.quests['lantern'], 2);
    expect(w.tokens, 3);
  });

  test('markers point at the target, or at the portal that leads there', () {
    final w = WorldState()..quests['lantern'] = 1;
    final goal = currentObjective(w)!;
    final meadow = zones['meadow']!;
    final cave = zones['cave']!;
    // In the meadow the marker is the cave mouth.
    expect(markerHex(meadow, goal, zones), meadow.portalHex['1']);
    // In the cave it is the lantern itself.
    final lantern = cave.items.firstWhere((i) => i.id == 'lantern');
    expect(markerHex(cave, goal, zones), lantern.hex);
    // Carrying it back, the cave's marker is its exit.
    w.addItem('lantern');
    final back = currentObjective(w)!;
    expect(markerHex(cave, back, zones), cave.portalHex['1']);
    expect(markerHex(meadow, back, zones), mara.hex);
  });

  test('every item, camp and NPC stands on walkable ground', () {
    for (final z in zones.values) {
      for (final h in z.camps) {
        expect(z.tiles[h]?.walkable, isTrue, reason: '${z.id} camp');
      }
      for (final n in z.npcs) {
        expect(z.tiles[n.hex]?.walkable, isTrue, reason: '${z.id} ${n.id}');
      }
      for (final i in z.items) {
        expect(z.tiles[i.hex]?.walkable, isTrue, reason: '${z.id} ${i.id}');
      }
    }
  });

  test('the lantern can be reached from the cave entrance', () {
    final cave = zones['cave']!;
    final lantern = cave.items.firstWhere((i) => i.id == 'lantern');
    expect(findPath(cave, cave.spawn, lantern.hex), isNotNull);
    // And Mara and the camp are reachable from the meadow's spawn.
    final meadow = zones['meadow']!;
    expect(findPath(meadow, meadow.spawn, meadow.camps.first), isNotNull);
    expect(findPath(meadow, meadow.spawn, mara.hex), isNotNull);
  });
}
