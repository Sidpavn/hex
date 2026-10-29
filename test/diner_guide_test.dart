// The guide a new player sees before the first day.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/goals_screen.dart';
import 'package:hex/diner/guide.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';

void main() {
  group('what it says', () {
    test('covers placing, seats, the counter, staff duties and the day', () {
      final all = guidePages.map((p) => p.title).join(' | ');
      for (final word in [
        'Placing',
        'Tables and chairs',
        'counter',
        'Staff and duties',
        'Menu',
        'Running the day',
      ]) {
        expect(all, contains(word));
      }
    });

    test('each page is short: a title and at most three lines', () {
      for (final p in guidePages) {
        expect(p.title, isNotEmpty);
        expect(p.lines, isNotEmpty);
        expect(p.lines.length, lessThanOrEqualTo(3), reason: p.title);
        for (final l in p.lines) {
          expect(l.length, lessThan(90), reason: l);
        }
      }
    });

    test('every picture is used once', () {
      expect(
        guidePages.map((p) => p.picture).toSet().length,
        guidePages.length,
      );
      expect(GuidePicture.values.length, guidePages.length);
    });

    test('the buttons it names are the buttons in the game', () {
      final build = File('lib/diner/build_screen.dart').readAsStringSync();
      final staff = File('lib/diner/person_screen.dart').readAsStringSync();
      final text = guidePages.expand((p) => p.lines).join(' ');
      for (final label in [
        'Rotate',
        'Move',
        'Sell',
        'Select',
        'Undo',
        'Place',
        'Expand',
        'Upgrades',
        'Staff',
        'Menu',
        'Stats',
        'Start day',
      ]) {
        if (text.contains(label)) {
          // A button's label may lead with a `:icon:` token before the word.
          expect(
            RegExp("'(:\\w+: )?${RegExp.escape(label)}").hasMatch(build),
            isTrue,
            reason: label,
          );
        }
      }
      expect(text, contains('duty'));
      expect(staff, contains('Clears tables'));
    });
  });

  group('on screen', () {
    Future<void> show(
      WidgetTester tester,
      Widget page, {
      Size size = const Size(1170, 2340),
      double dpr = 3,
      bool font = false,
    }) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
        if (font) {
          final loader = FontLoader('VT323')
            ..addFont(
              Future.value(
                ByteData.sublistView(
                  File('assets/fonts/VT323-Regular.ttf').readAsBytesSync(),
                ),
              ),
            );
          await loader.load();
        }
      });
      Storage.clearMemory();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(HexApp(home: page));
      await tester.pump(const Duration(milliseconds: 300));
    }

    String title(WidgetTester tester) =>
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const ValueKey('guide-title')),
                matching: find.byType(Text),
              ),
            )
            .data ??
        '';

    testWidgets('starts at the first page, with nothing to go back to', (
      tester,
    ) async {
      await show(tester, const GuideScreen(intro: true));
      expect(find.text('Step 1 of ${guidePages.length}'), findsOneWidget);
      expect(find.byKey(const ValueKey('guide-back')), findsNothing);
      expect(find.byKey(const ValueKey('guide-next')), findsOneWidget);
    });

    testWidgets('next and back go through the pages, one at a time', (
      tester,
    ) async {
      await show(tester, const GuideScreen());
      await tester.tap(find.byKey(const ValueKey('guide-next')));
      await tester.pump();
      expect(find.text('Step 2 of ${guidePages.length}'), findsOneWidget);
      expect(find.byKey(const ValueKey('guide-back')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('guide-back')));
      await tester.pump();
      expect(find.text('Step 1 of ${guidePages.length}'), findsOneWidget);
    });

    testWidgets('every page draws, with its own picture', (tester) async {
      await show(tester, const GuideScreen());
      for (var i = 0; i < guidePages.length; i++) {
        expect(
          find.byKey(ValueKey('guide-picture-${guidePages[i].picture.name}')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull, reason: guidePages[i].title);
        if (i < guidePages.length - 1) {
          await tester.tap(find.byKey(const ValueKey('guide-next')));
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
    });

    testWidgets('the last page says Start playing the first time', (
      tester,
    ) async {
      await show(tester, const GuideScreen(intro: true));
      for (var i = 0; i < guidePages.length - 1; i++) {
        await tester.tap(find.byKey(const ValueKey('guide-next')));
        await tester.pump();
      }
      expect(find.text('Start playing'), findsOneWidget);
      expect(find.byKey(const ValueKey('guide-skip')), findsNothing);
    });

    testWidgets('and Done when it is opened again', (tester) async {
      await show(tester, const GuideScreen());
      for (var i = 0; i < guidePages.length - 1; i++) {
        await tester.tap(find.byKey(const ValueKey('guide-next')));
        await tester.pump();
      }
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('it can be skipped from any page', (tester) async {
      await show(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const ValueKey('open'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const GuideScreen(intro: true),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(GuideScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('guide-next')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('guide-skip')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(GuideScreen), findsNothing);
    });

    testWidgets('it can be opened again from Goals', (tester) async {
      await show(tester, GoalsScreen(diner: Diner.starter()));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('open-guide')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('open-guide')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('open-guide')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(GuideScreen), findsOneWidget);
    });

    for (final (size, dpr) in const [
      (Size(360, 640), 3.0),
      (Size(412, 915), 2.625),
      (Size(390, 844), 3.0),
    ]) {
      testWidgets('every page fits a ${size.width.round()} wide phone', (
        tester,
      ) async {
        await show(
          tester,
          const GuideScreen(intro: true),
          size: size * dpr,
          dpr: dpr,
          font: true,
        );
        for (var i = 0; i < guidePages.length; i++) {
          expect(tester.takeException(), isNull, reason: title(tester));
          if (i < guidePages.length - 1) {
            await tester.tap(find.byKey(const ValueKey('guide-next')));
            await tester.pump(const Duration(milliseconds: 100));
          }
        }
      });
    }
  });
}
