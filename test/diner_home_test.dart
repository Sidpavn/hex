// The title screen, the games kept side by side, and saving by hand.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/cloud_save.dart';
import 'package:hex/data/save_sync.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/guide.dart';
import 'package:hex/diner/home_screen.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/diner/save_panel.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';
import 'package:hex/ui/widgets.dart' show GoldButton, PxText;

Diner game(int day, {int coins = 50}) => Diner(
  coins: coins,
  progress: Progress(level: 3, day: day),
);

CloudStore? none(int slot) => null;

/// A line of status text, whatever icon comes before it.
Finder says(String text) =>
    find.byWidgetPredicate((w) => w is PxText && w.text.endsWith(text));

void main() {
  setUp(Storage.clearMemory);

  group('games kept side by side', () {
    test('the first is where every earlier save already lives', () {
      expect(Storage.slot, 1);
      Storage.saveDiner(game(4));
      expect(Storage.slotInfo(1)!.day, 4);
      expect(Storage.diner!.progress.day, 4);
    });

    test('each place keeps its own', () {
      Storage.saveSlot(1, game(4));
      Storage.saveSlot(2, game(9));
      Storage.saveSlot(3, game(15));
      expect(
        [for (var n = 1; n <= 3; n++) Storage.slotInfo(n)!.day],
        [4, 9, 15],
      );
    });

    test('playing a game saves into its own place', () {
      Storage.saveSlot(1, game(4));
      Storage.useSlot(2);
      Storage.saveDiner(game(9));
      expect(Storage.slotInfo(1)!.day, 4);
      expect(Storage.slotInfo(2)!.day, 9);
      expect(Storage.diner!.progress.day, 9);
      Storage.clearDiner();
      expect(Storage.slotInfo(2), isNull);
      expect(Storage.slotInfo(1)!.day, 4);
    });

    test('a bad place number is put right', () {
      Storage.useSlot(9);
      expect(Storage.slot, Storage.slots);
      Storage.useSlot(0);
      expect(Storage.slot, 1);
    });

    test('an empty place has nothing', () {
      expect(Storage.slotInfo(2), isNull);
      expect(gameToContinue(), isNull);
    });

    test('carry on with the last played, else the latest saved', () {
      Storage.saveSlot(1, game(4));
      Storage.saveSlot(3, game(15));
      Storage.useSlot(3);
      expect(gameToContinue(), 3);
      Storage.clearSlot(3);
      expect(gameToContinue(), 1);
      Storage.saveSlot(2, game(9));
      Storage.useSlot(3);
      // Neither was saved first by the clock; whichever is newest wins.
      expect(gameToContinue(), anyOf(1, 2));
    });
  });

  test('how long ago, in plain words', () {
    final now = DateTime(2026, 10, 20, 12);
    int ago(Duration d) => now.subtract(d).millisecondsSinceEpoch;
    expect(savedAgo(0, now), '');
    expect(savedAgo(ago(const Duration(seconds: 20)), now), 'just now');
    expect(savedAgo(ago(const Duration(minutes: 5)), now), '5 min ago');
    expect(savedAgo(ago(const Duration(hours: 3)), now), '3 h ago');
    expect(savedAgo(ago(const Duration(days: 1, hours: 2)), now), '1 day ago');
    expect(savedAgo(ago(const Duration(days: 6)), now), '6 days ago');
  });

  group('on screen', () {
    Future<void> show(
      WidgetTester tester,
      Widget page, {
      Size size = const Size(1170, 2340),
    }) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
      });
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(HexApp(home: page));
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// A new game starts with the guide: skip it. Also dismisses the name
    /// dialog that appears first.
    Future<void> skipGuide(WidgetTester tester) async {
      // Dismiss the diner name dialog.
      expect(find.byKey(const ValueKey('name-skip')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('name-skip')));
      await settle(tester);
      expect(find.byType(GuideScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('guide-skip')));
      await settle(tester);
    }

    testWidgets('from the game, back to the title, saved', (tester) async {
      Storage.saveSlot(1, game(12, coins: 840));
      await show(tester, const HomeScreen(cloudFor: none));
      await tester.tap(find.byKey(const ValueKey('continue')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('goals')));
      await settle(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('to-title')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('to-title')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('to-title')));
      await settle(tester);
      expect(find.byType(BuildScreen), findsNothing);
      expect(find.byKey(const ValueKey('title')), findsOneWidget);
      expect(Storage.slotInfo(1)!.day, 12);
    });

    testWidgets('a first start has a title and one clear thing to do', (
      tester,
    ) async {
      await show(tester, const HomeScreen(cloudFor: none));
      expect(find.byKey(const ValueKey('title')), findsOneWidget);
      expect(find.byKey(const ValueKey('title-scene')), findsOneWidget);
      expect(find.byKey(const ValueKey('continue')), findsNothing);
      expect(find.byKey(const ValueKey('new-game')), findsOneWidget);
      expect(
        tester
            .widget<GoldButton>(find.byKey(const ValueKey('saved-games')))
            .label,
        ':files: Load a game',
      );
    });

    testWidgets('new game starts one, saved at once', (tester) async {
      await show(tester, const HomeScreen(cloudFor: none));
      await tester.tap(find.byKey(const ValueKey('new-game')));
      await settle(tester);
      await skipGuide(tester);
      expect(find.byType(BuildScreen), findsOneWidget);
      expect(Storage.slotInfo(1), isNotNull);
      expect(Storage.slot, 1);
    });

    testWidgets('a second new game goes in the next free place', (
      tester,
    ) async {
      Storage.saveSlot(1, game(7));
      await show(tester, const HomeScreen(cloudFor: none));
      await tester.tap(find.byKey(const ValueKey('new-game')));
      await settle(tester);
      await skipGuide(tester);
      expect(find.byType(BuildScreen), findsOneWidget);
      expect(Storage.slot, 2);
      expect(Storage.slotInfo(1)!.day, 7);
      expect(Storage.slotInfo(2)!.day, 1);
    });

    testWidgets('with a game saved, continue says where it is up to', (
      tester,
    ) async {
      Storage.saveSlot(1, game(12, coins: 840));
      await show(tester, const HomeScreen(cloudFor: none));
      expect(find.text('Game 1: Day 12, level 3, 840 coins'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('continue')));
      await settle(tester);
      expect(find.byType(BuildScreen), findsOneWidget);
    });

    testWidgets('when every place is full, it says to make room', (
      tester,
    ) async {
      for (var n = 1; n <= 3; n++) {
        Storage.saveSlot(n, game(n));
      }
      await show(tester, const HomeScreen(cloudFor: none));
      await tester.tap(find.byKey(const ValueKey('new-game')));
      await settle(tester);
      expect(find.byKey(const ValueKey('saves-note')), findsOneWidget);
      expect(find.byType(BuildScreen), findsNothing);
    });

    testWidgets('the saved games page lists all three', (tester) async {
      Storage.saveSlot(2, game(9));
      await show(tester, const SavesScreen(cloudFor: none));
      for (var n = 1; n <= 3; n++) {
        expect(find.byKey(ValueKey('game-$n')), findsOneWidget);
      }
      expect(find.text('Day 9, level 3, 50 coins'), findsOneWidget);
      expect(find.text('Empty'), findsNWidgets(2));
    });

    testWidgets('open a game, and play it', (tester) async {
      Storage.saveSlot(2, game(9));
      await show(tester, const SavesScreen(cloudFor: none));
      await tester.tap(find.byKey(const ValueKey('game-2')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('play-2')));
      await settle(tester);
      expect(find.byType(BuildScreen), findsOneWidget);
      expect(Storage.slot, 2);
    });

    testWidgets('an empty place starts a new game there', (tester) async {
      await show(tester, const SlotScreen(game: 3, cloudFor: none));
      await tester.tap(find.byKey(const ValueKey('start-here')));
      await settle(tester);
      await skipGuide(tester);
      expect(find.byType(BuildScreen), findsOneWidget);
      expect(Storage.slot, 3);
      expect(Storage.slotInfo(3), isNotNull);
    });

    testWidgets('delete asks first, and only empties that one', (tester) async {
      Storage.saveSlot(1, game(4));
      Storage.saveSlot(2, game(9));
      await show(tester, const SlotScreen(game: 2, cloudFor: none));
      await tester.tap(find.byKey(const ValueKey('delete-game')));
      await settle(tester);
      expect(Storage.slotInfo(2), isNotNull);
      await tester.tap(find.byKey(const ValueKey('confirm-delete')));
      await settle(tester);
      expect(Storage.slotInfo(2), isNull);
      expect(Storage.slotInfo(1)!.day, 4);
      expect(find.byKey(const ValueKey('start-here')), findsOneWidget);
    });

    testWidgets('a pasted code fills an empty place', (tester) async {
      final code = SaveCode.encode(game(30));
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
      await show(tester, const SlotScreen(game: 2, cloudFor: none));
      await tester.tap(find.byKey(const ValueKey('load-save')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('confirm-load')));
      await settle(tester);
      expect(Storage.slotInfo(2)!.day, 30);
    });

    Future<void> press(WidgetTester tester, String key) async {
      await tester.runAsync(() async {
        await tester.tap(find.byKey(ValueKey(key)));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('all backed up says so, with nothing to press', (tester) async {
      final store = MemoryStore(name: 'Google Play Games');
      Storage.saveSlot(1, game(6));
      await store.write(StoredSave.of(Storage.slotDiner(1)!));
      await show(tester, HomeScreen(cloudFor: (_) => store));
      expect(says('Backed up to Google Play Games.'), findsOneWidget);
      expect(find.byKey(const ValueKey('cloud-action')), findsNothing);
    });

    testWidgets('progress not backed up has a button that backs it up', (
      tester,
    ) async {
      final store = MemoryStore(name: 'Google Play Games');
      Storage.saveSlot(1, game(6));
      await show(tester, HomeScreen(cloudFor: (_) => store));
      expect(says('Your latest progress is not backed up.'), findsOneWidget);
      expect(find.text('Back up now'), findsOneWidget);
      await press(tester, 'cloud-action');
      expect(store.writes, 1);
      expect(says('Backed up to Google Play Games.'), findsOneWidget);
      expect(find.byKey(const ValueKey('cloud-action')), findsNothing);
    });

    testWidgets('not signed in says backup is off, and turns it on', (
      tester,
    ) async {
      final store = MemoryStore(name: 'Google Play Games')
        ..signedInAlready = false;
      Storage.saveSlot(1, game(6));
      await show(tester, HomeScreen(cloudFor: (_) => store));
      expect(says('Backup to Google Play Games is off.'), findsOneWidget);
      expect(find.text('Turn on backup'), findsOneWidget);
      store.signedInAlready = true;
      await press(tester, 'cloud-action');
      expect(find.text('Back up now'), findsOneWidget);
    });

    testWidgets('a newer backup is restored only after asking', (tester) async {
      final store = MemoryStore(name: 'Google Play Games');
      await SaveSync(
        store,
      ).run(game(20, coins: 900)..savedAt = 0, ask: (a, b) async => false);
      Storage.saveSlot(1, game(3));
      store.saved = StoredSave(
        SaveCode.encode(game(20, coins: 900)),
        SaveInfo(
          day: 20,
          level: 3,
          coins: 900,
          savedAt: DateTime.now().millisecondsSinceEpoch + 100000,
        ),
      );
      await show(tester, HomeScreen(cloudFor: (_) => store));
      expect(
        says('A newer save is backed up in Google Play Games.'),
        findsOneWidget,
      );
      await press(tester, 'cloud-action');
      expect(Storage.slotInfo(1)!.day, 3);
      await tester.tap(find.byKey(const ValueKey('confirm-restore')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(Storage.slotInfo(1)!.day, 20);
    });

    testWidgets('a fresh install offers the backup straight away', (
      tester,
    ) async {
      final store = MemoryStore(name: 'Google Play Games');
      await SaveSync(store).run(game(8), ask: (a, b) async => false);
      final others = {
        2: MemoryStore(name: 'Google Play Games'),
        3: MemoryStore(name: 'Google Play Games'),
      };
      await show(
        tester,
        HomeScreen(cloudFor: (n) => n == 1 ? store : others[n]),
      );
      expect(find.byKey(const ValueKey('continue')), findsNothing);
      expect(
        says('Game 1: A newer save is backed up in Google Play Games.'),
        findsOneWidget,
      );
      await press(tester, 'cloud-action');
      await tester.tap(find.byKey(const ValueKey('confirm-restore')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(Storage.slotInfo(1)!.day, 8);
      expect(find.byKey(const ValueKey('continue')), findsOneWidget);
    });

    testWidgets('a fresh install with no backup says nothing of it', (
      tester,
    ) async {
      final store = MemoryStore(name: 'Google Play Games');
      await show(tester, HomeScreen(cloudFor: (_) => store));
      expect(find.byKey(const ValueKey('cloud-action')), findsNothing);
      expect(find.byKey(const ValueKey('new-game')), findsOneWidget);
    });

    testWidgets('a fresh install not signed in offers to turn it on', (
      tester,
    ) async {
      final store = MemoryStore(name: 'Google Play Games')
        ..signedInAlready = false;
      await show(tester, HomeScreen(cloudFor: (_) => store));
      expect(
        says('Game 1: Backup to Google Play Games is off.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('found-backup-2')), findsOneWidget);
      expect(says('Game 2: Backup to Google Play Games is off.'), findsNothing);
    });

    testWidgets('an empty place can restore a backup', (tester) async {
      final store = MemoryStore(name: 'Google Play Games');
      await SaveSync(store).run(game(8), ask: (a, b) async => false);
      await show(tester, SlotScreen(game: 2, cloudFor: (_) => store));
      expect(find.text('Restore it'), findsOneWidget);
      await press(tester, 'cloud-action');
      await tester.tap(find.byKey(const ValueKey('confirm-restore')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(Storage.slotInfo(2)!.day, 8);
    });

    testWidgets('no cloud line when there is no cloud', (tester) async {
      Storage.saveSlot(1, game(6));
      await show(tester, const HomeScreen(cloudFor: none));
      expect(find.byKey(const ValueKey('cloud-status')), findsNothing);
    });
  });

  group('saving by hand', () {
    Future<void> panel(
      WidgetTester tester,
      Diner d, {
      CloudStore? store,
      VoidCallback? onSave,
      VoidCallback? onTitle,
    }) async {
      await tester.runAsync(PixelAssets.load);
      tester.view.physicalSize = const Size(1170, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        HexApp(
          home: Scaffold(
            body: SavePanel(
              diner: d,
              store: store,
              onSave: onSave,
              onTitle: onTitle,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('save now writes at once', (tester) async {
      var saved = 0;
      await panel(tester, game(5), onSave: () => saved++);
      await tester.tap(find.byKey(const ValueKey('save-now')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(saved, 1);
      expect(find.text('Saved on this phone.'), findsOneWidget);
    });

    testWidgets('and sends it to the cloud when there is one', (tester) async {
      final store = MemoryStore(name: 'Google Play Games');
      await panel(tester, game(5), store: store, onSave: () {});
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('save-now')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump(const Duration(milliseconds: 300));
      expect(store.writes, 1);
      expect(
        find.text('Saved on this phone. Backed up to Google Play Games.'),
        findsOneWidget,
      );
    });

    testWidgets('no save button unless asked for', (tester) async {
      await panel(tester, game(5));
      expect(find.byKey(const ValueKey('save-now')), findsNothing);
      expect(find.byKey(const ValueKey('to-title')), findsNothing);
    });

    testWidgets('the way back to the title', (tester) async {
      var back = 0;
      await panel(tester, game(5), onTitle: () => back++);
      await tester.tap(find.byKey(const ValueKey('to-title')));
      await tester.pump();
      expect(back, 1);
    });

    testWidgets('an empty place can still be filled from the cloud', (
      tester,
    ) async {
      final store = MemoryStore(name: 'Google Play Games');
      await SaveSync(store).run(game(8), ask: (a, b) async => false);
      Diner? got;
      await tester.runAsync(PixelAssets.load);
      tester.view.physicalSize = const Size(1170, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        HexApp(
          home: Scaffold(
            body: SavePanel(diner: null, store: store, onLoad: (d) => got = d),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Restore from Google Play Games'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('sync-save')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump(const Duration(milliseconds: 300));
      expect(got!.progress.day, 8);
    });
  });
}
