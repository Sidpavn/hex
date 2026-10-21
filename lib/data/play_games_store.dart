import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:games_services/games_services.dart';

import 'cloud_save.dart';
import 'save_sync.dart';

/// The place to keep a copy of the save off the phone on this platform, if
/// there is one: Google Play Games on Android.
CloudStore? defaultCloudStore({int slot = 1}) =>
    !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        // The plugin has nothing to talk to under `flutter test`; a test that
        // wants a store passes its own.
        !Platform.environment.containsKey('FLUTTER_TEST')
    ? PlayGamesStore(slot)
    : null;

/// Keeps the save in the player's Google Play Games account, as a saved game.
/// It holds the save code and, beside it, what the save says about itself, so
/// the two sides can be compared without opening the whole save.
class PlayGamesStore implements CloudStore {
  PlayGamesStore([int game = 1])
    : slot = game == 1 ? 'tiny-diner-save' : 'tiny-diner-save-$game';

  /// The saved game's name in Play Games: one for each game the player keeps.
  final String slot;

  @override
  String get name => 'Google Play Games';

  @override
  Future<bool> get available async {
    try {
      if (await GamesServices.isSignedIn) return true;
      await GamesServices.signIn();
      return await GamesServices.isSignedIn;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> get signedIn async {
    try {
      return await GamesServices.isSignedIn;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<StoredSave?> read() async {
    final games = await GamesServices.getSavedGames(forceRefresh: true);
    if (games == null || !games.any((g) => g.name == slot)) return null;
    final text = await GamesServices.loadGame(name: slot);
    if (text == null || text.isEmpty) return null;
    try {
      final json = jsonDecode(text) as Map<String, Object?>;
      final info = SaveInfo.fromJson(json['info']);
      final code = json['code'];
      if (info == null || code is! String) return null;
      return StoredSave(code, info);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(StoredSave save) async {
    await GamesServices.saveGame(
      data: jsonEncode({'info': save.info.toJson(), 'code': save.code}),
      name: slot,
    );
  }

  @override
  Future<void> delete() async {
    await GamesServices.deleteGame(name: slot);
  }
}
