// Every page on a small phone: nothing overflows, nothing is cut off.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/dish_screen.dart';
import 'package:hex/diner/goals_screen.dart';
import 'package:hex/diner/hiring_screen.dart';
import 'package:hex/diner/contracts.dart';
import 'package:hex/diner/menu_screen.dart';
import 'package:hex/diner/order_screen.dart';
import 'package:hex/diner/person_screen.dart';
import 'package:hex/diner/prep_screen.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/diner/report_screen.dart';
import 'package:hex/diner/service.dart';
import 'package:hex/diner/staff_screen.dart';
import 'package:hex/diner/stats_screen.dart';
import 'package:hex/diner/training_screen.dart';
import 'package:hex/diner/upgrade_screen.dart';
import 'package:hex/diner/vending_dialog.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';

/// Phones, as logical size and pixel ratio: a small old one, a common small
/// one, and a large one.
const phones = [
  (Size(320, 568), 2.0),
  (Size(360, 640), 3.0),
  (Size(412, 915), 2.625),
];

Diner played() {
  final d = Diner.starter()
    ..coins = 5000
    ..progress.level = 6;
  d.menu();
  for (var day = 2; day < 6; day++) {
    d.progress.day = day;
    final sim = DinerSim(d, seed: day);
    while (!sim.finished && sim.ticks < 2500) {
      sim.tick();
    }
  }
  d.toggleSpecial(Dish.burger);
  return d;
}

void main() {
  for (final (size, dpr) in phones) {
    final name = '${size.width.round()} by ${size.height.round()}';

    Future<void> show(WidgetTester tester, Widget page) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
        // The game's own font: the test one is much wider, and would report
        // overflows that never happen.
        final loader = FontLoader('VT323')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                File('assets/fonts/VT323-Regular.ttf').readAsBytesSync(),
              ),
            ),
          );
        await loader.load();
      });
      Storage.clearMemory();
      tester.view.physicalSize = size * dpr;
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(HexApp(home: page));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
    }

    group(name, () {
      testWidgets('the restaurant, before the day', (tester) async {
        await show(tester, BuildScreen(diner: played()));
        expect(find.byKey(const ValueKey('start-day')), findsOneWidget);
      });

      testWidgets('the restaurant, during the day and at the end', (
        tester,
      ) async {
        await show(tester, BuildScreen(diner: played()));
        await tester.tap(find.byKey(const ValueKey('start-day')));
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('speed-3')));
        await tester.pump();
        for (var i = 0; i < 900; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (find.byKey(const ValueKey('next-day')).evaluate().isNotEmpty) {
            break;
          }
        }
        expect(find.byKey(const ValueKey('next-day')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the menu, a dish and the portions', (tester) async {
        final d = played();
        await show(tester, MenuScreen(diner: d));
        await show(tester, DishScreen(diner: d, dish: Dish.burger));
        await show(tester, PrepScreen(diner: d));
      });

      testWidgets('staff, a person, hiring and training', (tester) async {
        final d = played();
        await show(tester, StaffScreen(diner: d));
        await show(
          tester,
          PersonScreen(diner: d, staff: d.roster.employees.first),
        );
        await show(tester, HiringScreen(diner: d));
        await show(
          tester,
          TrainingScreen(diner: d, staff: d.roster.employees.first),
        );
      });

      testWidgets('a catering order, and the corner button for it', (
        tester,
      ) async {
        final d = played()
          ..progress.level = 6
          ..progress.reputation = 85;
        var n = 2;
        while (ContractBook.offerFor(n, d) == null) {
          n++;
        }
        d.progress.day = n;
        await show(tester, BuildScreen(diner: d));
        expect(find.byKey(const ValueKey('catering')), findsOneWidget);
        await show(tester, OrderScreen(diner: d));
        d.takeContract(d.offer!, {d.roster.employees.first.id}, closed: true);
        await show(tester, BuildScreen(diner: d));
        await show(tester, OrderScreen(diner: d));
      });

      testWidgets('the vending machine dialog, empty and full', (tester) async {
        final d = played()
          ..progress.upgrades[Upgrade.vending] = 2
          ..vendCash = 280;
        await show(tester, Scaffold(body: VendingDialog(diner: d)));
        d
          ..vendCash = 0
          ..vendingOn = false;
        await show(tester, Scaffold(body: VendingDialog(diner: d)));
      });

      testWidgets('upgrades and goals', (tester) async {
        final d = played();
        await show(tester, UpgradeScreen(diner: d));
        await show(tester, GoalsScreen(diner: d, onReset: () {}));
      });

      testWidgets('the stats, on each tab', (tester) async {
        final d = played();
        await show(tester, StatsScreen(diner: d));
        for (final t in ['dishes', 'regulars', 'days', 'guests']) {
          await tester.tap(find.byKey(ValueKey('tab-$t')));
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull, reason: t);
        }
      });

      testWidgets('the day report', (tester) async {
        final d = Diner.starter()..coins = 500;
        d.progress.day = 2;
        final sim = DinerSim(d, seed: 1);
        while (!sim.finished && sim.ticks < 2500) {
          sim.tick();
        }
        await show(
          tester,
          DayReportScreen(report: sim.result!, progress: d.progress),
        );
      });
    });
  }
}
