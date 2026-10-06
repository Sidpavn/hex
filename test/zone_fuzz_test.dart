import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/game/hex.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';
import 'package:hex/ui/zone_screen.dart';
import 'package:hex/world/sim.dart';
import 'package:hex/world/world_state.dart';
import 'package:hex/world/zone.dart';

/// Plays the zones at random for a long time, at several screen shapes and
/// pixel densities, and fails on any exception: walking, fighting, casting,
/// dying, resting, talking, changing zones.
void main() {
  for (final (w, h, dpr) in const [
    (411.0, 914.0, 2.625), // Pixel 8
    (390.0, 844.0, 3.0),
    (360.0, 640.0, 2.0),
    (800.0, 1200.0, 1.0),
  ]) {
    for (final zoneId in ['meadow', 'cave']) {
      testWidgets('random play in $zoneId at ${w}x$h @$dpr', (tester) async {
        await tester.runAsync(() async {
          await PixelAssets.load();
          await ZoneRepo.loadAll();
        });
        tester.view.physicalSize = Size(w * dpr, h * dpr);
        tester.view.devicePixelRatio = dpr;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(home: ZoneScreen(startZone: zoneId)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        final rng = math.Random(11);
        final dynamic st = tester.state(find.byType(ZoneScreen));

        for (var i = 0; i < 260; i++) {
          final ZoneSim s = st.sim as ZoneSim;
          final Zone z = st.zone as Zone;
          if (s.heroDown) {
            await tester.tap(find.text('Wake up'));
            await tester.pump(const Duration(milliseconds: 100));
            continue;
          }
          switch (rng.nextInt(10)) {
            case 0 || 1 || 2:
              // Tap anywhere on the board.
              await tester.tapAt(
                Offset(
                  20 + rng.nextDouble() * (w - 40),
                  120 + rng.nextDouble() * (h - 240),
                ),
              );
            case 3:
              // Drop in next to a random enemy.
              if (s.enemies.isNotEmpty) {
                final e = s.enemies[rng.nextInt(s.enemies.length)];
                final spots = [
                  for (final n in e.hex.neighbors)
                    if ((z.tiles[n]?.walkable ?? false) && s.enemyAt(n) == null)
                      n,
                ];
                if (spots.isNotEmpty) {
                  s.hero = spots[rng.nextInt(spots.length)];
                  st.heroWorld = hexWorld(s.hero);
                  st.cam = st.heroWorld;
                }
              }
            case 4:
              // Attack whatever is in reach, with either weapon.
              (st.world as WorldState).equipped = [
                'sword',
                'bow',
              ][rng.nextInt(2)];
              for (final e in List.of(s.enemies)) {
                if (s.reaches(e)) {
                  s.attack(e);
                  st.afterTurn(s);
                  break;
                }
              }
            case 5:
              // Fireball somewhere nearby.
              s.world.mana = 4;
              final t = Hex(
                s.hero.q + rng.nextInt(7) - 3,
                s.hero.r + rng.nextInt(7) - 3,
              );
              if (s.castFireball(t)) st.afterTurn(s);
            case 6:
              // Walk to a random walkable hex through the real code path.
              final tiles = z.tiles.entries.where((e) => e.value.walkable);
              final pick = tiles.elementAt(rng.nextInt(tiles.length)).key;
              s.hero = s.hero;
              st.path = <Hex>[];
              st.destination = pick;
            case 7:
              // Nearly dead, so the fall and wake-up screens get exercised.
              s.world.hp = 1;
            case 8:
              // Open and close the overlays.
              st.journalOpen = true;
              st.setState(() {});
              await tester.pump(const Duration(milliseconds: 80));
              st.journalOpen = false;
              st.setState(() {});
            default:
              s.wait();
              st.afterTurn(s);
          }
          for (var k = 0; k < 5; k++) {
            await tester.pump(const Duration(milliseconds: 90));
          }
          expect(tester.takeException(), isNull, reason: 'step $i');
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
