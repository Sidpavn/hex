// The settings screen and the pause menu.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/audio/sound.dart';
import 'package:hex/data/save_sync.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/goals.dart';
import 'package:hex/diner/goals_screen.dart';
import 'package:hex/diner/guide.dart';
import 'package:hex/diner/home_screen.dart';
import 'package:hex/diner/pause_menu.dart';
import 'package:hex/diner/settings_screen.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';
import 'package:hex/ui/widgets.dart' show PxText;

class Heard implements SoundBackend {
  final List<String> log = [];

  @override
  void play(Sfx sfx, double scale) => log.add('play ${sfx.name} $scale');
  @override
  void startMusic(Music m, double scale) => log.add('start ${m.name} $scale');
  @override
  void setMusicScale(double scale) => log.add('level $scale');
  @override
  void stopMusic() => log.add('stop');
  @override
  void pauseMusic() => log.add('pause');
  @override
  void resumeMusic() => log.add('resume');
}

CloudStore? none(int slot) => null;

void main() {
  late Heard heard;
  final original = Sound.instance;

  setUp(() {
    Storage.clearMemory();
    heard = Heard();
    Sound.instance = Sound(heard);
  });
  tearDown(() => Sound.instance = original);

  group('the settings that are kept', () {
    test('sound and music start medium, backup starts on', () {
      expect(Storage.effectsLevel, 1);
      expect(Storage.musicLevel, 1);
      expect(Storage.autoBackup, isTrue);
    });

    test('levels are kept, and kept within bounds', () {
      Storage.effectsLevel = 2;
      Storage.musicLevel = 0;
      expect(Storage.effectsLevel, 2);
      expect(Storage.musicLevel, 0);
      Storage.effectsLevel = 9;
      expect(Storage.effectsLevel, 2);
      Storage.musicLevel = -3;
      expect(Storage.musicLevel, 0);
    });

    test(
      'the level sets how loud: low is half, high is half as much again',
      () {
        Sound.instance.setEffectsLevel(0);
        Sound.instance.play(Sfx.coin);
        Sound.instance.setEffectsLevel(2);
        Sound.instance.play(Sfx.till);
        expect(heard.log[0], 'play coin 0.5');
        expect(heard.log[1], 'play till 1.5');
      },
    );

    test('the music level changes at once, and sets the next track', () {
      Sound.instance.music(Music.build);
      Sound.instance.setMusicLevel(2);
      expect(heard.log, ['start build 1.0', 'level 1.5']);
      Sound.instance.music(Music.service);
      expect(heard.log.last, 'start service 1.5');
    });
  });

  group('on screen', () {
    Future<void> show(
      WidgetTester tester,
      Widget page, {
      Size size = const Size(1170, 2532),
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
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(HexApp(home: page));
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('sound, backup and help are all there', (tester) async {
      final store = MemoryStore(name: 'Google Play Games');
      await show(
        tester,
        SettingsScreen(diner: Diner.starter(), cloudFor: (_) => store),
      );
      expect(find.byKey(const ValueKey('toggle-sfx')), findsOneWidget);
      expect(find.byKey(const ValueKey('toggle-music')), findsOneWidget);
      expect(find.byKey(const ValueKey('sfx-level-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('music-level-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('toggle-autobackup')), findsOneWidget);
      expect(find.byKey(const ValueKey('cloud-status')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('version')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const ValueKey('settings-guide')), findsOneWidget);
      expect(
        tester.widget<PxText>(find.byKey(const ValueKey('version'))).text,
        'Tiny Diner Tycoon $gameVersion',
      );
    });

    testWidgets('without a cloud it says where games are kept', (tester) async {
      await show(tester, const SettingsScreen(cloudFor: none));
      expect(find.byKey(const ValueKey('no-cloud')), findsOneWidget);
      expect(find.byKey(const ValueKey('toggle-autobackup')), findsNothing);
    });

    testWidgets('the volume buttons set the levels, and sound follows', (
      tester,
    ) async {
      await show(tester, const SettingsScreen(cloudFor: none));
      await tester.tap(find.byKey(const ValueKey('sfx-level-2')));
      await tester.pump();
      expect(Storage.effectsLevel, 2);
      await tester.tap(find.byKey(const ValueKey('music-level-0')));
      await tester.pump();
      expect(Storage.musicLevel, 0);
      Sound.instance.play(Sfx.coin);
      expect(heard.log.last, startsWith('play coin 1.5'));
    });

    testWidgets('the backup switch is remembered, and says what it does', (
      tester,
    ) async {
      final store = MemoryStore(name: 'Google Play Games');
      await show(tester, SettingsScreen(cloudFor: (_) => store));
      expect(find.text('Auto backup on'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('toggle-autobackup')));
      await tester.pump();
      expect(Storage.autoBackup, isFalse);
      expect(find.text('Auto backup off'), findsOneWidget);
      expect(
        tester
            .widget<PxText>(find.byKey(const ValueKey('autobackup-help')))
            .text,
        contains('Nothing is sent'),
      );
    });

    testWidgets('how to play opens the guide', (tester) async {
      await show(tester, const SettingsScreen(cloudFor: none));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-guide')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('settings-guide')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('settings-guide')));
      await settle(tester);
      expect(find.byType(GuideScreen), findsOneWidget);
    });

    testWidgets('it is reached from the title and from Goals', (tester) async {
      await show(tester, const HomeScreen(cloudFor: none));
      await tester.tap(find.byKey(const ValueKey('settings')));
      await settle(tester);
      expect(find.byType(SettingsScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await show(tester, GoalsScreen(diner: Diner.starter()));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('open-settings')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('open-settings')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('open-settings')));
      await settle(tester);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    for (final (size, dpr) in const [
      (Size(360, 640), 3.0),
      (Size(412, 915), 2.625),
    ]) {
      testWidgets('it fits a ${size.width.round()} wide phone', (tester) async {
        final store = MemoryStore(name: 'Google Play Games')
          ..signedInAlready = false;
        await show(
          tester,
          SettingsScreen(diner: Diner.starter(), cloudFor: (_) => store),
          size: size * dpr,
          dpr: dpr,
          font: true,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the pause menu', () {
    Future<Diner> open(WidgetTester tester) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
      });
      final d = Diner.starter();
      d.goalsDone.addAll([for (final g in goals) g.id]);
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(HexApp(home: BuildScreen(diner: d, cloud: null)));
      await tester.pump();
      return d;
    }

    Future<void> beat(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('the back arrow opens it', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('header-back')));
      await beat(tester);
      expect(find.byType(PauseMenu), findsOneWidget);
      expect(find.text('Game menu'), findsOneWidget);
      expect(find.byKey(const ValueKey('toggle-sfx')), findsOneWidget);
      expect(find.byKey(const ValueKey('toggle-music')), findsOneWidget);
      expect(find.byKey(const ValueKey('pause-settings')), findsOneWidget);
      expect(find.byKey(const ValueKey('pause-guide')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('pause-title-button')),
        findsOneWidget,
        reason: 'between days you can leave',
      );
    });

    testWidgets('sound and music can be switched from it', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('header-back')));
      await beat(tester);
      await tester.tap(find.byKey(const ValueKey('toggle-sfx')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('toggle-music')));
      await tester.pump();
      expect(Storage.effectsOn, isFalse);
      expect(Storage.musicOn, isFalse);
      expect(heard.log.last, 'stop');
    });

    testWidgets('close puts it away', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('header-back')));
      await beat(tester);
      await tester.tap(find.byKey(const ValueKey('pause-resume')));
      await beat(tester);
      expect(find.byType(PauseMenu), findsNothing);
    });

    testWidgets('it opens the settings and the guide', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('header-back')));
      await beat(tester);
      await tester.tap(find.byKey(const ValueKey('pause-settings')));
      await beat(tester);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('during a day it holds the clock, and carries on after', (
      tester,
    ) async {
      final d = await open(tester);
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('speed-2')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('header-back')));
      await beat(tester);
      expect(find.text('Paused'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('pause-title-button')),
        findsNothing,
        reason: 'a day is not left half way',
      );
      // Time stands still while it is open.
      final left = d.progress.day;
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.byKey(const ValueKey('pause-resume')));
      await beat(tester);
      expect(find.byType(PauseMenu), findsNothing);
      expect(d.progress.day, left);
      // The day goes on at the speed it had.
      final chosen = tester.widget<Widget>(
        find.byKey(const ValueKey('speed-2')),
      );
      expect(chosen, isNotNull);
    });

    testWidgets('back during a day opens it instead of leaving', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await beat(tester);
      expect(find.byType(PauseMenu), findsOneWidget);
      expect(find.byType(BuildScreen), findsOneWidget);
    });

    testWidgets('back between days opens it too, and the arrow does', (
      tester,
    ) async {
      await open(tester);
      await tester.binding.handlePopRoute();
      await beat(tester);
      expect(find.byType(PauseMenu), findsOneWidget);
      expect(find.text('Game menu'), findsOneWidget);
      expect(find.byType(BuildScreen), findsOneWidget);
      // Back again closes the menu, and does not leave.
      await tester.binding.handlePopRoute();
      await beat(tester);
      expect(find.byType(PauseMenu), findsNothing);
      expect(find.byType(BuildScreen), findsOneWidget);
      // The arrow in the header does the same as a swipe.
      await tester.tap(find.byKey(const ValueKey('header-back')));
      await beat(tester);
      expect(find.byType(PauseMenu), findsOneWidget);
    });

    testWidgets('and after a day, from the summary', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('speed-3')));
      await tester.pump();
      for (var i = 0; i < 1500; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byKey(const ValueKey('next-day')).evaluate().isNotEmpty) break;
      }
      expect(find.byKey(const ValueKey('next-day')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await beat(tester);
      expect(find.byType(PauseMenu), findsOneWidget);
      expect(find.text('Game menu'), findsOneWidget);
      expect(find.byType(BuildScreen), findsOneWidget);
    });

    testWidgets('between days, back to the title', (tester) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
      });
      Storage.saveSlot(1, Diner.starter());
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const HexApp(home: HomeScreen(cloudFor: none)));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const ValueKey('continue')));
      await beat(tester);
      await tester.tap(find.byKey(const ValueKey('header-back')));
      await beat(tester);
      await tester.tap(find.byKey(const ValueKey('pause-title-button')));
      await beat(tester);
      await beat(tester);
      expect(find.byType(BuildScreen), findsNothing);
      expect(find.byKey(const ValueKey('title')), findsOneWidget);
    });
  });
}
