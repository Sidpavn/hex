// The save layer: codes to copy and paste, and keeping a cloud store in step.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/cloud_save.dart';
import 'package:hex/data/save_sync.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/diner/save_panel.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';

Diner at(int day, {int savedAt = 1000, int coins = 50}) {
  final d = Diner(
    coins: coins,
    progress: Progress(level: 3, day: day),
  );
  d.savedAt = savedAt;
  return d;
}

SaveInfo info(int day, int savedAt) =>
    SaveInfo(day: day, level: 3, coins: 0, savedAt: savedAt);

void main() {
  group('save code', () {
    test('goes out and comes back the same', () {
      final d = Diner.starter()..coins = 777;
      final back = SaveCode.decode(SaveCode.encode(d));
      expect(back.coins, 777);
      expect(back.toJson(), d.toJson());
    });

    test('is plain text that survives spaces and line breaks', () {
      final code = SaveCode.encode(at(9));
      final wrapped = [
        for (var i = 0; i < code.length; i += 40)
          code.substring(i, i + 40 > code.length ? code.length : i + 40),
      ].join('\n ');
      expect(SaveCode.decode('  $wrapped\n').progress.day, 9);
    });

    test('says what is wrong with a bad one', () {
      String why(String s) {
        try {
          SaveCode.decode(s);
        } on SaveCodeError catch (e) {
          return e.message;
        }
        return '';
      }

      final code = SaveCode.encode(at(9));
      expect(why(''), contains('nothing'));
      expect(why('hello there'), contains('not a save code'));
      expect(why(code.substring(0, code.length - 12)), contains('damaged'));
      final parts = code.split('.');
      final flipped = parts[2].replaceRange(
        10,
        11,
        parts[2][10] == 'A' ? 'B' : 'A',
      );
      expect(why('${parts[0]}.${parts[1]}.$flipped'), contains('damaged'));
    });

    test('a save from a newer game is not loaded', () {
      final j = at(2).toJson()..['v'] = Diner.saveVersion + 1;
      final fake = Diner.fromJson(j);
      expect(fake, isNotNull);
      // Build a code by hand with the higher version.
      final code = SaveCode.encodeJson(j);
      expect(
        () => SaveCode.decode(code),
        throwsA(
          isA<SaveCodeError>().having((e) => e.message, 'm', contains('newer')),
        ),
      );
    });

    test('saving stamps the time, and it is kept', () {
      final d = at(4, savedAt: 0);
      expect(d.toJson()['saved'], 0);
      d.savedAt = 123456;
      expect(Diner.fromJson(d.toJson()).savedAt, 123456);
    });

    test('an old save with no stamp loads with none', () {
      final j = at(4).toJson()
        ..remove('saved')
        ..remove('v');
      expect(Diner.fromJson(j).savedAt, 0);
    });
  });

  group('which save wins', () {
    test('nothing anywhere, nothing to do', () {
      expect(planSync(null, null), SyncAction.nothing);
    });
    test('only one side has one', () {
      expect(planSync(info(3, 5), null), SyncAction.upload);
      expect(planSync(null, info(3, 5)), SyncAction.download);
    });
    test('the same save is left alone', () {
      expect(planSync(info(3, 5000), info(3, 5500)), SyncAction.nothing);
    });
    test('further on and newer wins', () {
      expect(planSync(info(8, 9000000), info(3, 1000)), SyncAction.upload);
      expect(planSync(info(3, 1000), info(8, 9000000)), SyncAction.download);
    });
    test('same day, the newer one wins', () {
      expect(planSync(info(5, 900000), info(5, 100)), SyncAction.upload);
      expect(planSync(info(5, 100), info(5, 900000)), SyncAction.download);
    });
    test('further on but older is for the player to settle', () {
      expect(planSync(info(8, 100), info(3, 9000000)), SyncAction.conflict);
      expect(planSync(info(3, 9000000), info(8, 100)), SyncAction.conflict);
    });
  });

  group('syncing', () {
    Future<bool> never(SaveInfo a, SaveInfo b) async =>
        throw StateError('no question expected');

    test('sends the phone\'s save up when the cloud is empty', () async {
      final store = MemoryStore();
      final r = await SaveSync(store).run(at(6), ask: never);
      expect(r.action, SyncAction.upload);
      expect(store.writes, 1);
      expect(SaveCode.decode(store.saved!.code).progress.day, 6);
      expect(r.message, contains('The cloud'));
    });

    test('brings a save down onto a new phone', () async {
      final store = MemoryStore();
      await SaveSync(store).run(at(6), ask: never);
      final r = await SaveSync(store).run(null, ask: never);
      expect(r.action, SyncAction.download);
      expect(r.diner!.progress.day, 6);
    });

    test('leaves matching saves alone', () async {
      final store = MemoryStore();
      await SaveSync(store).run(at(6), ask: never);
      final r = await SaveSync(store).run(at(6), ask: never);
      expect(r.action, SyncAction.nothing);
      expect(store.writes, 1);
    });

    test('asks when they disagree, and does as told', () async {
      final store = MemoryStore();
      await SaveSync(store).run(at(8, savedAt: 100), ask: never);
      final mine = at(3, savedAt: 9000000);
      SaveInfo? shown;
      final keep = await SaveSync(store).run(
        mine,
        ask: (l, c) async {
          shown = c;
          return false;
        },
      );
      expect(shown!.day, 8);
      expect(keep.action, SyncAction.upload);
      expect(SaveCode.decode(store.saved!.code).progress.day, 3);

      final store2 = MemoryStore();
      await SaveSync(store2).run(at(8, savedAt: 100), ask: never);
      final take = await SaveSync(store2).run(mine, ask: (l, c) async => true);
      expect(take.action, SyncAction.download);
      expect(take.diner!.progress.day, 8);
    });

    test('does nothing, and says so, when it cannot be reached', () async {
      final store = MemoryStore(name: 'Google Play Games', online: false);
      final r = await SaveSync(store).run(at(6), ask: never);
      expect(r.action, SyncAction.nothing);
      expect(r.message, contains('Google Play Games'));
      expect(store.writes, 0);
    });
  });

  group('after a day, quietly', () {
    test('sends the phone\'s save up', () async {
      final store = MemoryStore(name: 'Google Play Games');
      final note = await SaveSync(store).quiet(at(5));
      expect(note, 'Backed up to Google Play Games');
      expect(SaveCode.decode(store.saved!.code).progress.day, 5);
    });

    test('says nothing when they already match', () async {
      final store = MemoryStore();
      await SaveSync(store).quiet(at(5));
      expect(await SaveSync(store).quiet(at(5)), isNull);
      expect(store.writes, 1);
    });

    test('never takes a save down, or overwrites one', () async {
      final store = MemoryStore(name: 'Google Play Games');
      await SaveSync(store).quiet(at(20, savedAt: 9000000));
      final before = store.saved!.code;
      // This phone is behind: the cloud is left alone, and the player told.
      final behind = await SaveSync(store).quiet(at(3, savedAt: 100));
      expect(behind, contains('different save'));
      expect(store.saved!.code, before);
      // This phone is further on but older: also left for the player.
      final odd = await SaveSync(store).quiet(at(40, savedAt: 50));
      expect(odd, contains('different save'));
      expect(store.saved!.code, before);
      expect(store.writes, 1);
    });

    test('does nothing when not signed in, and never asks to', () async {
      final store = MemoryStore()..signedInAlready = false;
      expect(await SaveSync(store).quiet(at(5)), isNull);
      expect(store.writes, 0);
    });

    test('does nothing when offline, and does not fail', () async {
      final store = MemoryStore(online: false);
      expect(await SaveSync(store).quiet(at(5)), isNull);
    });
  });

  group('after a day on the build screen', () {
    Future<void> playDay(WidgetTester tester, MemoryStore store) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
      });
      Storage.clearMemory();
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final d = Diner.starter();
      await tester.pumpWidget(
        HexApp(
          home: BuildScreen(diner: d, cloud: store),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('speed-3')));
      await tester.pump();
      for (var i = 0; i < 1500; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byKey(const ValueKey('next-day')).evaluate().isNotEmpty) break;
      }
      expect(find.byKey(const ValueKey('next-day')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('the save goes up by itself, and a note says so', (
      tester,
    ) async {
      final store = MemoryStore(name: 'Google Play Games');
      await playDay(tester, store);
      expect(store.writes, 1);
      expect(find.byKey(const ValueKey('cloud-note')), findsOneWidget);
      expect(find.text('Backed up to Google Play Games'), findsOneWidget);
    });

    testWidgets('nothing happens when not signed in', (tester) async {
      final store = MemoryStore()..signedInAlready = false;
      await playDay(tester, store);
      expect(store.writes, 0);
      expect(find.byKey(const ValueKey('cloud-note')), findsNothing);
    });
  });

  group('backed up on the way out', () {
    Future<void> opened(WidgetTester tester, MemoryStore store) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
      });
      Storage.clearMemory();
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        HexApp(
          home: BuildScreen(diner: Diner.starter(), cloud: store),
        ),
      );
      await tester.pump();
    }

    testWidgets('putting the app away sends the save up', (tester) async {
      final store = MemoryStore(name: 'Google Play Games');
      await opened(tester, store);
      expect(store.writes, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      expect(store.writes, 1);
    });

    testWidgets('and not again within the minute', (tester) async {
      final store = MemoryStore(name: 'Google Play Games');
      await opened(tester, store);
      for (var i = 0; i < 3; i++) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
      }
      expect(store.writes, 1);
    });

    testWidgets('coming back to the app does not', (tester) async {
      final store = MemoryStore(name: 'Google Play Games');
      await opened(tester, store);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      expect(store.writes, 0);
    });

    testWidgets('leaving the game does', (tester) async {
      final store = MemoryStore(name: 'Google Play Games');
      await opened(tester, store);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      expect(store.writes, 1);
    });
  });

  group('on screen', () {
    Future<void> open(
      WidgetTester tester,
      Diner d,
      void Function(Diner)? on, {
      CloudStore? store,
    }) async {
      await tester.runAsync(PixelAssets.load);
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        HexApp(
          home: Scaffold(
            body: SavePanel(diner: d, onLoad: on, store: store),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('shows what is saved and copies a code', (tester) async {
      String? clip;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clip = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final d = at(12, coins: 840);
      await open(tester, d, null);
      expect(find.text('Day 12, level 3, 840 coins'), findsOneWidget);
      expect(find.byKey(const ValueKey('load-save')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('copy-save')));
      await tester.pump();
      expect(clip, startsWith(SaveCode.prefix));
      expect(SaveCode.decode(clip!).progress.day, 12);
      expect(find.byKey(const ValueKey('save-note')), findsOneWidget);
    });

    testWidgets('a bad paste says why and loads nothing', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async =>
            call.method == 'Clipboard.getData' ? {'text': 'nonsense'} : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      Diner? got;
      await open(tester, at(2), (d) => got = d);
      await tester.tap(find.byKey(const ValueKey('load-save')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('not a save code'), findsOneWidget);
      expect(got, isNull);
    });

    testWidgets('a good paste asks first, then loads', (tester) async {
      final code = SaveCode.encode(at(30));
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async =>
            call.method == 'Clipboard.getData' ? {'text': code} : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      Diner? got;
      await open(tester, at(2), (d) => got = d);
      await tester.tap(find.byKey(const ValueKey('load-save')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(got, isNull);
      expect(find.textContaining('Day 30'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm-load')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(got!.progress.day, 30);
    });

    testWidgets('no sync button without a store', (tester) async {
      await open(tester, at(2), null);
      expect(find.byKey(const ValueKey('sync-save')), findsNothing);
    });

    testWidgets('sync sends the phone\'s save up', (tester) async {
      final store = MemoryStore(name: 'Google Play Games');
      await open(tester, at(7), null, store: store);
      expect(find.text('Back up with Google Play Games'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('sync-save')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump(const Duration(milliseconds: 300));
      expect(store.writes, 1);
      expect(
        find.textContaining('Backed up to Google Play Games'),
        findsOneWidget,
      );
    });

    testWidgets('sync brings a newer cloud save down', (tester) async {
      final store = MemoryStore(name: 'Google Play Games');
      await SaveSync(
        store,
      ).run(at(20, savedAt: 9000000), ask: (a, b) async => false);
      Diner? got;
      await open(tester, at(3, savedAt: 100), (d) => got = d, store: store);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('sync-save')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump(const Duration(milliseconds: 300));
      expect(got!.progress.day, 20);
    });

    testWidgets('sync says so when the store is out of reach', (tester) async {
      final store = MemoryStore(name: 'Google Play Games', online: false);
      await open(tester, at(3), null, store: store);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('sync-save')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('not available'), findsOneWidget);
      expect(store.writes, 0);
    });
  });
}
