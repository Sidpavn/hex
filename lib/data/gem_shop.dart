import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'storage.dart';

/// A pack of gems on sale: what the store calls it and how many it holds.
class GemPack {
  const GemPack(this.id, this.gems);

  final String id;
  final int gems;
}

/// The packs. The ids are the products to make in Play Console, as consumable
/// in-app products.
const gemPacks = [
  GemPack('gems_100', 100),
  GemPack('gems_550', 550),
  GemPack('gems_1200', 1200),
];

int gemsIn(String productId) {
  for (final p in gemPacks) {
    if (p.id == productId) return p.gems;
  }
  return 0;
}

/// A purchase the store says has gone through.
class Purchase {
  const Purchase(this.orderId, this.productId);

  /// Unique to this purchase, however many times it is reported.
  final String orderId;
  final String productId;
}

/// Where gems are sold. The game's own store is Google Play; tests use one
/// that sells for nothing.
abstract class GemStore {
  /// Whether there is a store to buy from on this device.
  Future<bool> get available;

  /// The price of each pack, as the store words it, by product id. Packs the
  /// store does not know are left out.
  Future<Map<String, String>> prices();

  /// Starts buying [productId]. False if it could not be started.
  Future<bool> buy(String productId);

  /// Every purchase that goes through, now or when the app was last open.
  Stream<Purchase> get purchases;

  void dispose();
}

/// Sells gems through Google Play.
class PlayGemStore implements GemStore {
  PlayGemStore([InAppPurchase? iap]) : _iap = iap ?? InAppPurchase.instance {
    _sub = _iap.purchaseStream.listen(_onUpdates, onError: (_) {});
  }

  final InAppPurchase _iap;
  late final StreamSubscription<List<PurchaseDetails>> _sub;
  final _out = StreamController<Purchase>.broadcast();
  final Map<String, ProductDetails> _products = {};

  @override
  Stream<Purchase> get purchases => _out.stream;

  @override
  Future<bool> get available => _iap.isAvailable();

  @override
  Future<Map<String, String>> prices() async {
    if (!await available) return {};
    final found = await _iap.queryProductDetails({
      for (final p in gemPacks) p.id,
    });
    for (final d in found.productDetails) {
      _products[d.id] = d;
    }
    return {for (final d in found.productDetails) d.id: d.price};
  }

  @override
  Future<bool> buy(String productId) async {
    if (_products.isEmpty) await prices();
    final d = _products[productId];
    if (d == null) return false;
    try {
      return await _iap.buyConsumable(
        purchaseParam: PurchaseParam(productDetails: d),
      );
    } catch (_) {
      return false;
    }
  }

  void _onUpdates(List<PurchaseDetails> updates) {
    for (final u in updates) {
      if (u.status == PurchaseStatus.purchased ||
          u.status == PurchaseStatus.restored) {
        _out.add(
          Purchase(
            u.purchaseID ?? '${u.productID}:${u.transactionDate}',
            u.productID,
          ),
        );
      }
      // Tell Play it was received, or it takes the money back after a few days.
      if (u.pendingCompletePurchase) _iap.completePurchase(u);
    }
  }

  @override
  void dispose() {
    _sub.cancel();
    _out.close();
  }
}

/// A store with nothing behind it: every pack is free, and bought at once.
/// For tests, and for trying the shop where there is no Play.
class TestGemStore implements GemStore {
  final _out = StreamController<Purchase>.broadcast();
  int _n = 0;

  /// What to say next time [buy] is asked: false makes it fail.
  bool works = true;

  @override
  Stream<Purchase> get purchases => _out.stream;

  @override
  Future<bool> get available async => true;

  @override
  Future<Map<String, String>> prices() async => {
    'gems_100': 'free',
    'gems_550': 'free',
    'gems_1200': 'free',
  };

  @override
  Future<bool> buy(String productId) async {
    if (!works) return false;
    _out.add(Purchase('test-${_n++}', productId));
    return true;
  }

  /// Sends a purchase the way Play does when it tells us again about one.
  void repeat(Purchase p) => _out.add(p);

  @override
  void dispose() => _out.close();
}

/// Turns purchases into gems, once each. A purchase that arrives while a game
/// is open goes straight to it; one that arrives when none is waits in
/// storage until a game opens.
class GemShop {
  GemShop(this.store) {
    _sub = store.purchases.listen(_credit);
  }

  final GemStore store;
  late final StreamSubscription<Purchase> _sub;

  /// Called with gems to add to the game that is open. Null when none is.
  void Function(int gems)? onGems;

  void _credit(Purchase p) {
    final seen = Storage.creditedOrders;
    if (!seen.add(p.orderId)) return;
    Storage.creditedOrders = seen;
    final n = gemsIn(p.productId);
    if (n == 0) return;
    final to = onGems;
    if (to != null) {
      to(n);
    } else {
      Storage.pendingGems += n;
    }
  }

  /// Hands over gems that arrived while no game was open.
  int takePending() {
    final n = Storage.pendingGems;
    Storage.pendingGems = 0;
    return n;
  }

  void dispose() {
    _sub.cancel();
    store.dispose();
  }

  /// The one the app uses.
  static GemShop? _instance;
  static GemShop get instance => _instance ??= GemShop(_defaultStore());

  /// For tests: swap in a shop.
  @visibleForTesting
  static set instance(GemShop? s) => _instance = s;

  /// Google Play on Android; nothing to buy from elsewhere. Under
  /// `flutter test` the plugin has nothing to talk to, so a test passes its
  /// own store.
  static GemStore _defaultStore() =>
      !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android &&
          !Platform.environment.containsKey('FLUTTER_TEST')
      ? PlayGemStore()
      : NoGemStore();
}

/// No store: nothing to buy, and nothing arrives.
class NoGemStore implements GemStore {
  @override
  Stream<Purchase> get purchases => const Stream.empty();

  @override
  Future<bool> get available async => false;

  @override
  Future<Map<String, String>> prices() async => {};

  @override
  Future<bool> buy(String productId) async => false;

  @override
  void dispose() {}
}
