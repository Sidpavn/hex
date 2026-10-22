// Gems: free ones for goals and levels, bought ones from the store, and the
// style popup that spends them.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/gem_shop.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/goals.dart';
import 'package:hex/diner/styles.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';

void main() {
  setUp(Storage.clearMemory);

  group('the shop keeps count', () {
    test('a purchase becomes gems, once, however often it is told', () async {
      final store = TestGemStore();
      final shop = GemShop(store);
      var got = 0;
      shop.onGems = (n) => got += n;
      await store.buy('gems_100');
      await store.buy('gems_550');
      store.repeat(const Purchase('test-0', 'gems_100'));
      await Future<void>.delayed(Duration.zero);
      expect(got, 650);
      shop.dispose();
    });

    test('a purchase with no game open waits for one', () async {
      final store = TestGemStore();
      final shop = GemShop(store);
      await store.buy('gems_1200');
      await Future<void>.delayed(Duration.zero);
      expect(Storage.pendingGems, 1200);
      expect(shop.takePending(), 1200);
      expect(shop.takePending(), 0);
      shop.dispose();
    });

    test('an unknown pack gives nothing', () async {
      final store = TestGemStore();
      final shop = GemShop(store);
      var got = 0;
      shop.onGems = (n) => got += n;
      store.repeat(const Purchase('x', 'something_else'));
      await Future<void>.delayed(Duration.zero);
      expect(got, 0);
      shop.dispose();
    });

    test('the packs are three, in order of size', () {
      expect(gemPacks.map((p) => p.gems), [100, 550, 1200]);
      expect(gemPacks.map((p) => p.id).toSet().length, 3);
    });

    test('a failed purchase says so', () async {
      final store = TestGemStore()..works = false;
      expect(await store.buy('gems_100'), isFalse);
    });
  });

  group('free gems', () {
    test('each goal done gives a couple, once', () {
      final d = Diner.starter();
      final before = d.gems;
      final met = d.checkGoals();
      expect(d.gems, before + met.length * Diner.goalGems);
      d.checkGoals();
      expect(d.gems, before + met.length * Diner.goalGems);
    });
  });

  group('on screen', () {
    Future<Diner> open(
      WidgetTester tester,
      GemShop shop, {
      int gems = 0,
    }) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
      });
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final d = Diner.starter();
      d.goalsDone.addAll([for (final g in goals) g.id]);
      d.gems = gems;
      await tester.pumpWidget(
        HexApp(
          home: BuildScreen(diner: d, gems: shop),
        ),
      );
      await tester.pump();
      return d;
    }

    Future<void> openStyle(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('style')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('a free style is used with a tap', (tester) async {
      final shop = GemShop(TestGemStore());
      final d = await open(tester, shop);
      await openStyle(tester);
      expect(find.byKey(const ValueKey('style-popup')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('style-wall-cream')));
      await tester.pump();
      expect(d.wallStyle, 'cream');
      await tester.tap(find.byKey(const ValueKey('style-tab-floor')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('style-floor-slate')));
      await tester.pump();
      expect(d.floorStyle, 'slate');
      shop.dispose();
    });

    testWidgets('a dear one with too few gems says how many it needs', (
      tester,
    ) async {
      final shop = GemShop(TestGemStore());
      final d = await open(tester, shop, gems: 10);
      await openStyle(tester);
      await tester.tap(find.byKey(const ValueKey('style-wall-brick')));
      await tester.pump();
      expect(find.textContaining('costs 50 gems'), findsOneWidget);
      expect(d.wallStyle, wallDefault);
      expect(d.gems, 10);
      shop.dispose();
    });

    testWidgets('with enough gems it asks, and unlocks and uses it', (
      tester,
    ) async {
      final shop = GemShop(TestGemStore());
      final d = await open(tester, shop, gems: 80);
      await openStyle(tester);
      await tester.tap(find.byKey(const ValueKey('style-wall-brick')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Unlock for 50 gems'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('confirm-style')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(d.gems, 30);
      expect(d.wallStyle, 'brick');
      shop.dispose();
    });

    testWidgets('the gem shop sells a pack, and the gems arrive', (
      tester,
    ) async {
      final shop = GemShop(TestGemStore());
      final d = await open(tester, shop);
      await openStyle(tester);
      await tester.tap(find.byKey(const ValueKey('get-gems')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('gem-shop')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pack-gems_550')));
      await tester.pump();
      await tester.pump();
      expect(d.gems, 550);
      expect(find.byKey(const ValueKey('gem-note')), findsOneWidget);
      shop.dispose();
    });

    testWidgets('with no store it says so, and sells nothing', (tester) async {
      final shop = GemShop(NoGemStore());
      await open(tester, shop);
      await openStyle(tester);
      await tester.tap(find.byKey(const ValueKey('get-gems')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('gem-unavailable')), findsOneWidget);
      expect(find.byKey(const ValueKey('pack-gems_100')), findsNothing);
      shop.dispose();
    });

    testWidgets('gems paid for while no game was open are added', (
      tester,
    ) async {
      Storage.pendingGems = 100;
      final shop = GemShop(TestGemStore());
      final d = await open(tester, shop);
      expect(d.gems, 100);
      expect(Storage.pendingGems, 0);
      shop.dispose();
    });
  });
}
