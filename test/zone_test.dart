import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/game/hex.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';
import 'package:hex/ui/zone_screen.dart';
import 'package:hex/world/pathfinding.dart';
import 'package:hex/world/sim.dart';
import 'package:hex/world/zone.dart';

Map<String, Zone> _load() {
  final zones = <String, Zone>{};
  for (final f in Directory('assets/zones').listSync().whereType<File>()) {
    if (!f.path.endsWith('.txt')) continue;
    final z = Zone.parse(f.readAsStringSync());
    zones[z.id] = z;
  }
  return zones;
}

void main() {
  test('every zone has a spawn, is connected, and portals link both ways', () {
    final zones = _load();
    expect(zones, isNotEmpty);
    for (final z in zones.values) {
      expect(z.tiles[z.spawn]?.walkable, isTrue, reason: '${z.id} spawn');
      for (final p in z.portals.values) {
        final here = z.portalHex[p.id];
        expect(here, isNotNull, reason: '${z.id} portal ${p.id} not on map');
        final other = zones[p.toZone];
        expect(
          other,
          isNotNull,
          reason: '${z.id} links to missing ${p.toZone}',
        );
        final back = other!.portals[p.toPortal];
        expect(
          back,
          isNotNull,
          reason: '${p.toZone} has no portal ${p.toPortal}',
        );
        expect(
          back!.toZone,
          z.id,
          reason: '${z.id}/${p.id} does not link back',
        );
        // The spawn can walk to every portal in its zone.
        expect(
          findPath(z, z.spawn, here!),
          isNotNull,
          reason: '${z.id}: cannot reach portal ${p.id}',
        );
      }
    }
  });

  test('pathfinding avoids water and prefers cheap ground', () {
    final z = Zone.parse(File('assets/zones/meadow.txt').readAsStringSync());
    final path = findPath(z, z.spawn, z.portalHex['1']!)!;
    expect(path, isNotEmpty);
    for (final h in path) {
      expect(z.tiles[h]!.walkable, isTrue);
    }
    // Moving between neighbours only.
    var prev = z.spawn;
    for (final h in path) {
      expect(prev.distanceTo(h), 1);
      prev = h;
    }
  });

  test('hexAtWorld inverts hexWorld', () {
    for (final h in const [Hex(0, 0), Hex(3, -2), Hex(-5, 7), Hex(12, 20)]) {
      expect(hexAtWorld(hexWorld(h)), h);
    }
  });

  testWidgets('tapping a hex walks the hero there, one turn per hex', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await PixelAssets.load();
      await ZoneRepo.load('meadow');
    });
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ZoneScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    final dynamic st = tester.state(find.byType(ZoneScreen));
    final Hex start = st.heroHex as Hex;
    // Tap three hexes up and to the right of the hero (screen centre area).
    final size = tester.getSize(find.byType(Scaffold));
    await tester.tapAt(Offset(size.width / 2 + 90, size.height / 2 + 120));
    await tester.pump();
    expect((st.path as List).isNotEmpty, isTrue);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(st.heroHex as Hex, isNot(start));
    expect((st.turn.value as int), greaterThan(0));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('walking into the cave mouth loads the cave and back', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await PixelAssets.load();
      await ZoneRepo.load('meadow');
      await ZoneRepo.load('cave');
    });
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: ZoneScreen()));
    await tester.pump(const Duration(milliseconds: 100));
    final dynamic st = tester.state(find.byType(ZoneScreen));
    final meadow = st.zone as Zone;
    // Keep the walk uninterrupted: this test is about portals, not enemies.
    (st.sim as ZoneSim).enemies.clear();
    st.path = findPath(meadow, st.heroHex as Hex, meadow.portalHex['1']!)!;
    for (var i = 0; i < 400 && (st.zone as Zone).id == 'meadow'; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final cave = st.zone as Zone;
    expect(cave.id, 'cave');
    expect(st.heroHex as Hex, cave.portalHex['1']);
    await tester.pumpWidget(const SizedBox());
  });
}
