import '../diner/diner.dart';
import 'cloud_save.dart';

/// What to do with the saves on the phone and in the cloud.
enum SyncAction {
  /// They are the same, or there is nothing anywhere.
  nothing,

  /// The phone's is the one to keep: send it up.
  upload,

  /// The cloud's is the one to keep: bring it down.
  download,

  /// They disagree about which is newer, so the player must say.
  conflict,
}

/// A second of difference between two save times is not a difference.
const _same = Duration(seconds: 2);

/// Which save wins. The one that is both further on and newer does. If one is
/// further on but the other was saved more recently (say, someone started over
/// on one phone), nobody can tell which is wanted, so it is a conflict.
SyncAction planSync(SaveInfo? local, SaveInfo? cloud) {
  if (local == null && cloud == null) return SyncAction.nothing;
  if (cloud == null) return SyncAction.upload;
  if (local == null) return SyncAction.download;
  final gap = local.savedAt - cloud.savedAt;
  final close = gap.abs() <= _same.inMilliseconds;
  if (close && local.day == cloud.day) return SyncAction.nothing;
  if (local.day == cloud.day) {
    return gap > 0 ? SyncAction.upload : SyncAction.download;
  }
  if (local.day > cloud.day) {
    return gap >= 0 || close ? SyncAction.upload : SyncAction.conflict;
  }
  return gap <= 0 || close ? SyncAction.download : SyncAction.conflict;
}

/// A place the save can be kept off the phone. Google Play Games, iCloud or a
/// server would each be one of these; nothing else in the game knows which.
abstract class CloudStore {
  /// What to call it to the player: "Google Play Games".
  String get name;

  /// Whether it can be used now: signed in, and online. May ask the player to
  /// sign in.
  Future<bool> get available;

  /// Whether the player is already signed in. Never asks anything, so it is
  /// safe to check in the background.
  Future<bool> get signedIn;

  /// What is stored, or null if nothing is.
  Future<StoredSave?> read();

  Future<void> write(StoredSave save);

  Future<void> delete();
}

/// A save as kept in a [CloudStore]: the code, and what it says about itself.
class StoredSave {
  const StoredSave(this.code, this.info);

  final String code;
  final SaveInfo info;

  factory StoredSave.of(Diner d) =>
      StoredSave(SaveCode.encode(d), SaveInfo.of(d));
}

/// How a sync ended.
class SyncResult {
  const SyncResult(this.action, this.message, {this.diner});

  final SyncAction action;

  /// For the player.
  final String message;

  /// The diner to carry on with, if the cloud's was brought down.
  final Diner? diner;
}

/// Asked when the phone and the cloud disagree: true to take the cloud's.
typedef ChooseCloud = Future<bool> Function(SaveInfo local, SaveInfo cloud);

/// Keeps the phone's save and a [CloudStore]'s in step.
class SaveSync {
  SaveSync(this.store);

  final CloudStore store;

  /// What happens after a day with nobody asked: the phone's save goes up if
  /// it is the one to keep, and nothing is ever taken down or overwritten on
  /// the phone. Returns null when there is nothing worth telling the player,
  /// and a message when the cloud has something they should look at.
  Future<String?> quiet(Diner local) async {
    try {
      if (!await store.signedIn) return null;
      final cloud = await store.read();
      final mine = SaveInfo.of(local);
      switch (planSync(mine, cloud?.info)) {
        case SyncAction.nothing:
          return null;
        case SyncAction.upload:
          await store.write(StoredSave.of(local));
          return 'Backed up to ${store.name}';
        case SyncAction.download:
        case SyncAction.conflict:
          return 'A different save is backed up in ${store.name}. '
              'Open Goals to choose which to keep.';
      }
    } catch (_) {
      return null;
    }
  }

  Future<SyncResult> run(Diner? local, {required ChooseCloud ask}) async {
    if (!await store.available) {
      return SyncResult(
        SyncAction.nothing,
        '${store.name} is not available right now.',
      );
    }
    final cloud = await store.read();
    final mine = local == null ? null : SaveInfo.of(local);
    var action = planSync(mine, cloud?.info);
    if (action == SyncAction.conflict) {
      action = await ask(mine!, cloud!.info)
          ? SyncAction.download
          : SyncAction.upload;
    }
    switch (action) {
      case SyncAction.nothing:
        return const SyncResult(SyncAction.nothing, 'Already backed up.');
      case SyncAction.upload:
        await store.write(StoredSave.of(local!));
        return SyncResult(
          SyncAction.upload,
          'Backed up to ${store.name}: ${SaveInfo.of(local).summary}.',
        );
      case SyncAction.download:
        final diner = SaveCode.decode(cloud!.code);
        return SyncResult(
          SyncAction.download,
          'Restored from ${store.name}: ${cloud.info.summary}.',
          diner: diner,
        );
      case SyncAction.conflict:
        throw StateError('a conflict is settled before this point');
    }
  }
}

/// A store that keeps its save in memory. For tests, and as the shape a real
/// store follows.
class MemoryStore implements CloudStore {
  MemoryStore({this.name = 'The cloud', this.online = true});

  @override
  final String name;

  /// Whether it can be reached.
  bool online;

  StoredSave? saved;
  int writes = 0;

  @override
  Future<bool> get available async => online;

  @override
  Future<bool> get signedIn async => online && signedInAlready;

  /// Whether the player has already signed in to it.
  bool signedInAlready = true;

  @override
  Future<StoredSave?> read() async => saved;

  @override
  Future<void> write(StoredSave save) async {
    saved = save;
    writes++;
  }

  @override
  Future<void> delete() async => saved = null;
}
