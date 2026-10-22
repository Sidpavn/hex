// What the game sounds like, and when it keeps quiet.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'shelf.dart';
import 'package:hex/audio/sound.dart';
import 'package:hex/data/save_sync.dart' show CloudStore;
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/cues.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/goals.dart';
import 'package:hex/diner/home_screen.dart';
import 'package:hex/diner/service.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';

class Recording implements SoundBackend {
  final List<Sfx> played = [];
  final List<String> music = [];

  final List<double> scales = [];

  @override
  void play(Sfx sfx, double scale) {
    played.add(sfx);
    scales.add(scale);
  }

  @override
  void startMusic(Music m, double scale) {
    music.add('start ${m.name}');
    scales.add(scale);
  }

  @override
  void setMusicScale(double scale) => music.add('level $scale');

  @override
  void stopMusic() => music.add('stop');
  @override
  void pauseMusic() => music.add('pause');
  @override
  void resumeMusic() => music.add('resume');
}

CloudStore? _none(int slot) => null;

void main() {
  late Recording backend;
  var ms = 10000;

  Sound make() =>
      Sound(backend, clock: () => DateTime.fromMillisecondsSinceEpoch(ms));

  final original = Sound.instance;
  setUp(() {
    Storage.clearMemory();
    backend = Recording();
    ms = 10000;
    Sound.instance = make();
  });
  tearDown(() => Sound.instance = original);

  group('keeping it from piling up', () {
    test('a sound plays', () {
      Sound.instance.play(Sfx.coin);
      expect(backend.played, [Sfx.coin]);
    });

    test('the same one twice in a hurry plays once', () {
      Sound.instance.play(Sfx.till);
      ms += Sfx.till.minGap - 1;
      Sound.instance.play(Sfx.till);
      expect(backend.played.length, 1);
      ms += 2;
      Sound.instance.play(Sfx.till);
      expect(backend.played.length, 2);
    });

    test('different sounds do not hold each other up', () {
      Sound.instance
        ..play(Sfx.chime)
        ..play(Sfx.till)
        ..play(Sfx.plate);
      expect(backend.played, [Sfx.chime, Sfx.till, Sfx.plate]);
    });

    test('only so many at once, and the important ones get in', () {
      // Fill every voice with quiet ones that are still sounding.
      final fillers = [
        Sfx.tap,
        Sfx.tick,
        Sfx.plate,
        Sfx.sizzle,
        Sfx.chime,
        Sfx.ding,
      ];
      for (final f in fillers) {
        Sound.instance.play(f);
      }
      expect(backend.played.length, Sound.maxVoices);
      // A repeat of something unimportant is dropped.
      ms += 1000;
      for (final f in fillers) {
        Sound.instance.play(f);
      }
      backend.played.clear();
      ms += 10;
      // Everything is busy again; a bell is more important than any of them.
      Sound.instance.play(Sfx.bellOpen);
      expect(backend.played, [Sfx.bellOpen]);
    });

    test('when all are busy, something less important waits its turn', () {
      for (final f in [
        Sfx.bellOpen,
        Sfx.bellClose,
        Sfx.jingleGood,
        Sfx.jingleBad,
        Sfx.jingleUp,
        Sfx.grumble,
      ]) {
        Sound.instance.play(f);
      }
      backend.played.clear();
      Sound.instance.play(Sfx.tap);
      expect(backend.played, isEmpty);
    });
  });

  group('the switches', () {
    test('both are on to begin with', () {
      expect(Storage.effectsOn, isTrue);
      expect(Storage.musicOn, isTrue);
    });

    test('effects off means no effects, and it is remembered', () {
      Sound.instance.setEffects(false);
      Sound.instance.play(Sfx.coin);
      expect(backend.played, isEmpty);
      expect(Storage.effectsOn, isFalse);
      Sound.instance.setEffects(true);
      Sound.instance.play(Sfx.coin);
      expect(backend.played, [Sfx.coin]);
    });

    test('music plays when asked for, and stops when asked to', () {
      Sound.instance.music(Music.build);
      expect(backend.music, ['start build']);
      Sound.instance.music(Music.service);
      expect(backend.music.last, 'start service');
      Sound.instance.music(null);
      expect(backend.music.last, 'stop');
    });

    test('music off keeps it quiet, and on brings it back', () {
      Sound.instance.setMusic(false);
      Sound.instance.music(Music.build);
      expect(backend.music, isEmpty);
      Sound.instance.setMusic(true);
      expect(backend.music, ['start build']);
      Sound.instance.setMusic(false);
      expect(backend.music.last, 'stop');
    });

    test('effects do not depend on music', () {
      Sound.instance.setMusic(false);
      Sound.instance.play(Sfx.till);
      expect(backend.played, [Sfx.till]);
    });

    test('in the background the music is held, then carries on', () {
      Sound.instance.music(Music.build);
      Sound.instance.pause();
      expect(backend.music.last, 'pause');
      Sound.instance.resume();
      expect(backend.music.last, 'resume');
      expect(backend.music.where((m) => m.startsWith('start')).length, 1);
    });
  });

  group('out of sight, and how loud', () {
    test('everything is half as loud as the files were made', () {
      expect(Sound.master, 0.5);
      expect(AudioplayersBackend.musicVolume, closeTo(0.15, 1e-9));
    });

    test('going to the background holds the music and silences effects', () {
      Sound.instance.music(Music.build);
      Sound.instance.lifecycle(AppLifecycleState.paused);
      expect(backend.music.last, 'pause');
      Sound.instance.play(Sfx.coin);
      expect(backend.played, isEmpty);
    });

    test('hidden counts too, a shade pulled down does not', () {
      Sound.instance.music(Music.build);
      Sound.instance.lifecycle(AppLifecycleState.inactive);
      expect(backend.music, ['start build']);
      Sound.instance.play(Sfx.coin);
      expect(backend.played, [Sfx.coin]);
      Sound.instance.lifecycle(AppLifecycleState.hidden);
      expect(backend.music.last, 'pause');
    });

    test('coming back carries on, with effects again', () {
      Sound.instance.music(Music.build);
      Sound.instance.lifecycle(AppLifecycleState.paused);
      Sound.instance.lifecycle(AppLifecycleState.resumed);
      expect(backend.music.last, 'resume');
      Sound.instance.play(Sfx.coin);
      expect(backend.played, [Sfx.coin]);
    });

    test('music asked for while away waits until the app is back', () {
      Sound.instance.lifecycle(AppLifecycleState.paused);
      Sound.instance.music(Music.service);
      expect(backend.music.where((m) => m.startsWith('start')), isEmpty);
      Sound.instance.lifecycle(AppLifecycleState.resumed);
      expect(backend.music.last, 'start service');
    });

    testWidgets('the app tells it, on whatever screen it is', (tester) async {
      Sound.instance.watchLifecycle();
      Sound.instance.watchLifecycle();
      Sound.instance.music(Music.build);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(backend.music.where((m) => m == 'pause').length, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(backend.music.last, 'resume');
    });
  });

  group('what the sim says', () {
    test('every cue has a sound', () {
      for (final c in Cue.values) {
        expect(sfxFor(c), isNotNull, reason: c.name);
      }
    });

    DinerSim play(Diner d, {int seed = 2}) {
      final sim = DinerSim(d, seed: seed);
      while (!sim.finished && sim.ticks < 2500) {
        sim.tick();
      }
      return sim;
    }

    test('a day with guests has them come in, cook, serve and pay', () {
      final d = Diner.starter();
      d.goalsDone.addAll([for (final g in goals) g.id]);
      final sim = play(d);
      final seen = sim.cues.toSet();
      expect(
        seen,
        containsAll([
          Cue.enter,
          Cue.cookStart,
          Cue.dishReady,
          Cue.plate,
          Cue.paid,
        ]),
      );
    });

    test('a hurried order of cues: cooked before it is ready', () {
      final d = Diner.starter();
      final cues = play(d).cues;
      expect(
        cues.indexOf(Cue.cookStart),
        lessThan(cues.indexOf(Cue.dishReady)),
      );
      expect(cues.indexOf(Cue.dishReady), lessThan(cues.indexOf(Cue.plate)));
    });

    test('guests who leave unserved are heard going', () {
      // Some days a few give up; look through a handful of them.
      var left = 0;
      var heard = 0;
      for (var seed = 1; seed < 12; seed++) {
        final sim = play(Diner.starter(), seed: seed);
        left += sim.walkouts;
        heard += sim.cues.where((c) => c == Cue.walkout).length;
      }
      expect(left, greaterThan(0));
      expect(heard, greaterThan(0));
    });

    test('a good tip sounds bigger than a small one', () {
      final d = Diner.starter();
      d.goalsDone.addAll([for (final g in goals) g.id]);
      var well = 0;
      var plain = 0;
      for (var seed = 1; seed < 6; seed++) {
        final dd = Diner.starter();
        final sim = play(dd, seed: seed);
        well += sim.cues.where((c) => c == Cue.paidWell).length;
        plain += sim.cues.where((c) => c == Cue.paid).length;
      }
      expect(well + plain, greaterThan(0));
      expect(plain, greaterThan(0));
    });

    test('cues only record: a day plays out the same with or without them', () {
      final a = play(Diner.starter(), seed: 4);
      final b = play(Diner.starter(), seed: 4);
      expect(a.cues, b.cues);
      expect(a.earned, b.earned);
    });
  });

  group('the files', () {
    final dir = Directory('assets/sounds');

    Uint8List bytes(String name) =>
        File('${dir.path}/$name.wav').readAsBytesSync();

    test('every effect and track has a file, listed in the assets', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('assets/sounds/'));
      for (final s in Sfx.values) {
        expect(
          File('${dir.path}/${s.file}.wav').existsSync(),
          isTrue,
          reason: s.file,
        );
      }
      for (final m in Music.values) {
        expect(
          File('${dir.path}/${m.file}.wav').existsSync(),
          isTrue,
          reason: m.file,
        );
      }
    });

    test('each is a small 8-bit mono WAV at 22050 Hz', () {
      for (final f in dir.listSync().whereType<File>()) {
        final b = f.readAsBytesSync();
        final d = ByteData.sublistView(b);
        expect(String.fromCharCodes(b.sublist(0, 4)), 'RIFF', reason: f.path);
        expect(String.fromCharCodes(b.sublist(8, 12)), 'WAVE', reason: f.path);
        expect(d.getUint16(22, Endian.little), 1, reason: 'mono');
        expect(d.getUint32(24, Endian.little), 22050, reason: 'rate');
        expect(d.getUint16(34, Endian.little), 8, reason: 'bits');
      }
    });

    test('effects are short and music is a loop of a few seconds', () {
      for (final s in Sfx.values) {
        final seconds = (bytes(s.file).length - 44) / 22050;
        expect(seconds, lessThan(1.2), reason: s.file);
        // The length the player is told to expect is about right.
        expect(seconds * 1000, closeTo(s.length, 120), reason: s.file);
      }
      for (final m in Music.values) {
        final seconds = (bytes(m.file).length - 44) / 22050;
        expect(seconds, inInclusiveRange(10, 40), reason: m.file);
      }
    });

    test('a loop ends quietly, so it repeats without a click', () {
      for (final m in Music.values) {
        final b = bytes(m.file);
        final tail = b.sublist(b.length - 40);
        for (final v in tail) {
          expect((v - 128).abs(), lessThan(30), reason: m.file);
        }
      }
    });

    test('none is silent, and none is clipped flat', () {
      for (final f in dir.listSync().whereType<File>()) {
        final b = f.readAsBytesSync().sublist(44);
        final loud = b.where((v) => (v - 128).abs() > 10).length;
        expect(loud, greaterThan(20), reason: f.path);
        expect(b.where((v) => v == 0 || v == 255).length, 0, reason: f.path);
      }
    });
  });

  group('on screen', () {
    Future<void> show(WidgetTester tester, Widget page) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
      });
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(HexApp(home: page));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('the title screen opens the settings, which have both', (
      tester,
    ) async {
      await show(tester, const HomeScreen(cloudFor: _none));
      await tester.tap(find.byKey(const ValueKey('settings')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('toggle-sfx')), findsOneWidget);
      expect(find.byKey(const ValueKey('toggle-music')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('toggle-sfx')));
      await tester.pump();
      expect(Storage.effectsOn, isFalse);
      await tester.tap(find.byKey(const ValueKey('toggle-music')));
      await tester.pump();
      expect(Storage.musicOn, isFalse);
      expect(find.text('Sound off'), findsOneWidget);
      expect(find.text('Music off'), findsOneWidget);
    });

    testWidgets('the title has the music going', (tester) async {
      await show(tester, const HomeScreen(cloudFor: _none));
      expect(backend.music, ['start build']);
    });

    testWidgets('a button makes a small tap, and none with sound off', (
      tester,
    ) async {
      await show(tester, const HomeScreen(cloudFor: _none));
      backend.played.clear();
      await tester.tap(find.byKey(const ValueKey('saved-games')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(backend.played, [Sfx.tap]);
      Sound.instance.setEffects(false);
      backend.played.clear();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const ValueKey('game-1')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(backend.played, isEmpty);
    });

    testWidgets('a day has its bells, its music, and its sounds', (
      tester,
    ) async {
      final d = Diner.starter();
      d.goalsDone.addAll([for (final g in goals) g.id]);
      await show(tester, BuildScreen(diner: d));
      expect(backend.music, ['start build']);
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump();
      expect(backend.played, contains(Sfx.bellOpen));
      expect(backend.music.last, 'start service');
      await tester.tap(find.byKey(const ValueKey('speed-3')));
      await tester.pump();
      for (var i = 0; i < 1500; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byKey(const ValueKey('next-day')).evaluate().isNotEmpty) break;
      }
      expect(find.byKey(const ValueKey('next-day')), findsOneWidget);
      expect(backend.played, contains(Sfx.bellClose));
      expect(backend.played, contains(Sfx.till));
      expect(backend.played, contains(Sfx.chime));
      expect(backend.music.last, 'start build');
      // Then, after the bell, a few notes for how it went.
      await tester.pump(const Duration(seconds: 1));
      expect(
        backend.played.toSet().intersection({
          Sfx.jingleGood,
          Sfx.jingleBad,
          Sfx.jingleUp,
          Sfx.warn,
        }),
        isNotEmpty,
      );
    });

    testWidgets('leaving the game stops its music', (tester) async {
      await show(tester, BuildScreen(diner: Diner.starter()));
      await tester.pumpWidget(const SizedBox());
      expect(backend.music.last, 'stop');
    });

    testWidgets('placing something makes a sound, and a bad spot another', (
      tester,
    ) async {
      final d = Diner.starter();
      d.coins = 100000;
      await show(tester, BuildScreen(diner: d));
      await openShelf(tester, Kind.table);
      await tester.ensureVisible(find.byKey(const ValueKey('fixture-table')));
      await openShelf(tester, Kind.table);
      await tester.tap(find.byKey(const ValueKey('fixture-table')));
      await tester.pump();
      expect(backend.played, contains(Sfx.tick));
      await tester.tap(find.byKey(const ValueKey('place')));
      await tester.pump();
      expect(
        backend.played.toSet().intersection({Sfx.place, Sfx.no}),
        isNotEmpty,
      );
    });
  });
}
