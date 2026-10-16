// The screen rules in CLAUDE.md, checked: text is never cut off, news is a
// toast, help sits next to what was tapped, and buttons say what they do.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/goals.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';

void main() {
  group('the sources follow the rules', () {
    final files = [
      for (final f in Directory('lib/diner').listSync())
        if (f is File && f.path.endsWith('.dart')) f,
    ];

    test('no text is clipped or limited to a few lines', () {
      for (final f in files) {
        final src = f.readAsStringSync();
        expect(src, isNot(contains('TextOverflow.clip')), reason: f.path);
        expect(src, isNot(contains('TextOverflow.ellipsis')), reason: f.path);
        expect(
          RegExp(r'maxLines:\s*[2-9]').hasMatch(src),
          isFalse,
          reason: '${f.path} limits text to a few lines',
        );
      }
    });

    test('no bare "Max" or "owned" on a button', () {
      for (final f in files) {
        final src = f.readAsStringSync();
        for (final bad in ["'Max'", "'max'", "'Owned'"]) {
          expect(src, isNot(contains(bad)), reason: '${f.path}: $bad');
        }
      }
    });

    test('questions use the game\'s own dialog, not the stock one', () {
      for (final f in files) {
        final src = f.readAsStringSync();
        expect(src, isNot(contains('AlertDialog')), reason: f.path);
        expect(src, isNot(contains('showDialog')), reason: f.path);
      }
    });

    test('no fixed-height box wraps a line of changing text', () {
      for (final f in files) {
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length - 2; i++) {
          final box = RegExp(r'SizedBox\(\s*$').hasMatch(lines[i]);
          if (!box) continue;
          final next = lines.skip(i + 1).take(3).join(' ');
          final fixed = RegExp(r'height:\s*\d+').hasMatch(next);
          final text = next.contains('PxText(');
          expect(
            fixed && text,
            isFalse,
            reason: '${f.path}:${i + 1} wraps text in a fixed height',
          );
        }
      }
    });
  });

  group('on screen', () {
    Future<Diner> open(WidgetTester tester, Diner d) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
      });
      Storage.clearMemory();
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(HexApp(home: BuildScreen(diner: d)));
      await tester.pump();
      return d;
    }

    testWidgets('what a fixture does shows on the board, whole', (
      tester,
    ) async {
      final d = await open(tester, Diner.starter());
      await tester.tap(find.byKey(const ValueKey('fixture-grill')));
      await tester.pump();
      final hint = find.byKey(const ValueKey('hint'));
      expect(hint, findsOneWidget);
      final text = tester.getRect(find.byKey(const ValueKey('info-line')));
      final box = tester.getRect(hint);
      expect(box.contains(text.topLeft), isTrue);
      expect(box.contains(text.bottomRight - const Offset(1, 1)), isTrue);
      // Over the top-left of the board, not in the panel at the bottom.
      expect(box.top, lessThan(tester.view.physicalSize.height / 3 / 4));
      expect(box.left, lessThan(24));
      expect(d.coins, greaterThan(0));
    });

    testWidgets('a long explanation wraps instead of being cut off', (
      tester,
    ) async {
      final d = Diner.starter()..progress.level = 3;
      await open(tester, d);
      await tester.ensureVisible(find.byKey(const ValueKey('fixture-window')));
      await tester.tap(find.byKey(const ValueKey('fixture-window')));
      await tester.pump();
      final line = find.byKey(const ValueKey('info-line'));
      expect(find.textContaining('Tap the right-hand wall'), findsOneWidget);
      final box = tester.getRect(find.byKey(const ValueKey('hint')));
      final text = tester.getRect(line);
      expect(text.height, greaterThan(40), reason: 'it takes several lines');
      expect(box.bottom, greaterThanOrEqualTo(text.bottom));
    });

    testWidgets('nothing is shown when there is nothing to say', (
      tester,
    ) async {
      // Every goal done, so there is no hint left to give.
      await open(
        tester,
        Diner.starter()..goalsDone.addAll([for (final g in goals) g.id]),
      );
      expect(find.byKey(const ValueKey('hint')), findsNothing);
    });

    testWidgets('the day can be paused, and nothing happens while it is', (
      tester,
    ) async {
      await open(tester, Diner.starter());
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('speed-3')));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.byKey(const ValueKey('pause')));
      await tester.pump();
      expect(find.textContaining('Paused'), findsOneWidget);
      final frozen = find.textContaining('Paused').evaluate().length;
      final before =
          (tester.widget(find.textContaining('Paused')) as dynamic).data
              as String?;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final after =
          (tester.widget(find.textContaining('Paused')) as dynamic).data
              as String?;
      expect(frozen, 1);
      expect(after, before, reason: 'the clock did not move');
      await tester.tap(find.byKey(const ValueKey('speed-1')));
      await tester.pump();
      expect(find.textContaining('Paused'), findsNothing);
      expect(find.textContaining('left'), findsWidgets);
    });
  });
}
