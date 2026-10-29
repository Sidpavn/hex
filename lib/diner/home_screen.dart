import 'package:flutter/material.dart';

import '../audio/sound.dart';
import '../data/cloud_save.dart';
import '../data/leaderboards.dart';
import '../data/play_games_store.dart';
import '../data/save_sync.dart';
import '../data/storage.dart';
import '../ui/pixel_dialog.dart';
import '../ui/widgets.dart';
import 'build_screen.dart';
import 'diner.dart';
import 'diner_art.dart';
import 'diner_painter.dart';
import 'guide.dart';
import 'home_card.dart';
import 'iso.dart';
import 'save_panel.dart';
import 'settings_screen.dart';
import 'streak_popup.dart';
import 'title_sign.dart';

/// Where to keep a copy of game [n] off the phone, if anywhere.
typedef CloudFor = CloudStore? Function(int slot);

/// Where each game's backup is kept on this platform, if anywhere.
CloudStore? defaultCloudFor(int slot) => defaultCloudStore(slot: slot);

/// "just now", "5 min ago", "2 h ago", "3 days ago". Empty if never saved.
String savedAgo(int savedAt, [DateTime? now]) {
  if (savedAt <= 0) return '';
  final gap = (now ?? DateTime.now()).millisecondsSinceEpoch - savedAt;
  final mins = gap ~/ 60000;
  if (mins < 1) return 'just now';
  if (mins < 60) return '$mins min ago';
  if (mins < 60 * 24) return '${mins ~/ 60} h ago';
  final days = mins ~/ (60 * 24);
  return days == 1 ? '1 day ago' : '$days days ago';
}

/// The game to carry on with: the one last played, or failing that the most
/// recently saved. Null if nothing has been saved.
int? gameToContinue() {
  final here = Storage.slotInfo(Storage.slot);
  if (here != null) return Storage.slot;
  int? best;
  var bestAt = -1;
  for (var n = 1; n <= Storage.slots; n++) {
    final i = Storage.slotInfo(n);
    if (i != null && i.savedAt > bestAt) {
      best = n;
      bestAt = i.savedAt;
    }
  }
  return best;
}

int? _firstEmpty() {
  for (var n = 1; n <= Storage.slots; n++) {
    if (Storage.slotInfo(n) == null) return n;
  }
  return null;
}

/// Starts playing game [n]. A new game is saved at once, so it is there on
/// the saved games page.
Future<void> _play(
  BuildContext context,
  int n, {
  bool fresh = false,
  String locationId = 'diner',
  String name = 'My Diner',
}) async {
  Storage.useSlot(n);
  if (fresh) {
    final d = Diner.fresh(locationId: locationId)..name = name;
    Storage.saveSlot(n, d);
    // A new game starts with the guide, which can be skipped.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const GuideScreen(intro: true)),
    );
    if (!context.mounted) return;
  }
  await Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const BuildScreen()));
  // The game stopped the music on the way out; the title has it.
  Sound.instance.music(Music.build);
}

/// Shows a dialog asking the player to name their new diner.
Future<String> askDinerName(BuildContext context) async {
  final controller = TextEditingController(text: 'My Diner');
  final result = await popupPixel<String>(
    context,
    (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
      child: PixelBox(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PxText(
              'Name your diner',
              style: TextStyle(color: Pal.gold, fontSize: 22),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 20,
              cursorColor: Pal.gold,
              cursorWidth: 2,
              cursorHeight: 16.0,
              style: const TextStyle(
                fontFamily: 'VT323',
                fontSize: 17,
                color: Pal.text,
              ),
              decoration: const InputDecoration(
                counterText: '',
                filled: true,
                fillColor: Pal.panel,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: Pal.ink, width: 2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: Pal.gold, width: 2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.zero,
                  borderSide: BorderSide(color: Pal.ink, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GoldButton(
                    key: const ValueKey('name-skip'),
                    label: 'Skip',
                    filled: false,
                    color: Pal.dim,
                    onTap: () => Navigator.of(ctx).pop('My Diner'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GoldButton(
                    key: const ValueKey('name-done'),
                    label: 'Done',
                    onTap: () {
                      final v = controller.text.trim();
                      Navigator.of(ctx).pop(v.isEmpty ? 'My Diner' : v);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? 'My Diner';
}

/// The title screen: the restaurant, what to do next, and whether the saves
/// are safe.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.cloudFor = defaultCloudFor, this.scores});

  final CloudFor cloudFor;

  /// The leaderboards (tests). By default Play Games on Android.
  final ScoreBoard? scores;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    Sound.instance.music(Music.build);
  }

  Future<void> _continue(int n) async {
    await _play(context, n);
    if (mounted) setState(() {});
  }

  Future<void> _newGame() async {
    final n = _firstEmpty();
    if (n == null) {
      await _saves(
        note:
            'All ${Storage.slots} places are in use. Delete a game to make '
            'room for a new one.',
      );
      return;
    }
    final name = await _askDinerName();
    if (!mounted) return;
    await _play(context, n, fresh: true, name: name);
    if (mounted) setState(() {});
  }

  Future<String> _askDinerName() => askDinerName(context);

  Future<void> _openStreakPopup(int game, Diner diner) async {
    final claimed = await popupPixel<bool>(
      context,
      (_) => StreakPopup(diner: diner, game: game),
    );
    if (claimed == true && mounted) setState(() {});
  }

  Future<void> _saves({String note = ''}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SavesScreen(cloudFor: widget.cloudFor, note: note),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final game = gameToContinue();
    final info = game == null ? null : Storage.slotInfo(game);
    final shown = game == null ? null : Storage.slotDiner(game);
    final hasGame = game != null && info != null;

    return Scaffold(
      backgroundColor: Pal.bgTop,
      body: Backdrop(
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
              const CheckerBand(colorA: Pal.tealDark, colorB: Pal.cream),
              Expanded(
                child: _Scene(
                  key: const ValueKey('title-scene'),
                  diner: shown ?? Diner.starter(),
                ),
              ),
              const PerfBand(),
              const AwningBand(colorA: Pal.teal, colorB: Pal.cream),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ColoredBox(
                        color: Pal.cream,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 22, 14, 14),
                          child: _card(hasGame, game, info, shown),
                        ),
                      ),
                      const CheckerBand(colorA: Pal.teal, colorB: Pal.cream),
                    ],
                  ),
                  if (hasGame)
                    Positioned(
                      top: -22,
                      right: 9,
                      child: HexSeal(
                        child: PxText(
                          '${info.level}',
                          style: const TextStyle(
                            color: Pal.cream,
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: _belowCard(hasGame, game, info, shown),
              ),
                ],
              ),
              Positioned(
                top: 15,
                left: 10,
                child: _DailyRewardButton(
                  ready: Storage.streakReady,
                  onTap: game != null && shown != null
                      ? () => _openStreakPopup(game, shown)
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The cream menu card: the game's name, today's state, and the one
  /// primary action — everything else is quieter, below.
  Widget _card(bool hasGame, int? game, SaveInfo? info, Diner? shown) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PxText(
          'Tiny Diner Tycoon',
          key: ValueKey('title'),
          style: TextStyle(color: Pal.inkWarm, fontSize: 26, height: 0.95),
        ),
        if (hasGame)
          PxText(
            'Day ${info!.day}',
            style: const TextStyle(color: Pal.teal, fontSize: 14),
          ),
        const SizedBox(height: 8),
        Container(height: 1, color: Pal.creamDark),
        const SizedBox(height: 8),
        if (hasGame) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              PxText(
                '${info!.coins}',
                style: const TextStyle(
                  color: Pal.teal,
                  fontSize: 30,
                  height: 0.85,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PxText(
                  'coins in the till',
                  style: const TextStyle(color: Pal.teal, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(height: 1, color: Pal.creamDark),
          LedgerLine(
            label: 'Lifetime earned',
            value: '${(shown ?? Diner.starter()).totalEarned}',
          ),
          Container(height: 1, color: Pal.creamDark),
        ],
        const SizedBox(height: 14),
        DinerButton(
          key: ValueKey(hasGame ? 'continue' : 'new-game'),
          label: hasGame
              ? 'Open for business — Day ${info!.day + 1}'
              : 'New game',
          tall: true,
          fontSize: 15,
          onTap: hasGame ? () => _continue(game!) : _newGame,
        ),
      ],
    );
  }

  /// Backup status, the exact game, and the quieter secondary actions — all
  /// on the usual dark chrome, below the card.
  Widget _belowCard(bool hasGame, int? game, SaveInfo? info, Diner? shown) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasGame) ...[
          PxText(
            'Game $game: ${info!.summary}',
            key: const ValueKey('continue-summary'),
            style: const TextStyle(color: Pal.dim, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: GoldButton(
                  key: const ValueKey('new-game'),
                  label: ':plus: New game',
                  filled: false,
                  color: Pal.text,
                  onTap: _newGame,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GoldButton(
                  key: const ValueKey('saved-games'),
                  label: ':files: Saved games',
                  filled: false,
                  color: Pal.text,
                  onTap: _saves,
                ),
              ),
            ],
          ),
        ] else ...[
          GoldButton(
            key: const ValueKey('saved-games'),
            label: ':files: Load a game',
            filled: false,
            color: Pal.text,
            onTap: _saves,
          ),
        ],
        if (!hasGame && widget.cloudFor(1) != null) ...[
          const SizedBox(height: 12),
          // A fresh install: any backups are offered for restoring.
          for (var n = 1; n <= Storage.slots; n++)
            CloudLine(
              key: ValueKey('found-backup-$n'),
              store: widget.cloudFor(n)!,
              diner: null,
              prefix: 'Game $n: ',
              quiet: n > 1,
              onRestore: (d) {
                Storage.saveSlot(n, d);
                setState(() {});
              },
            ),
        ],
        if (game != null && widget.cloudFor(game) != null) ...[
          const SizedBox(height: 12),
          CloudLine(
            key: ValueKey('cloud-line-$game-${info?.savedAt}'),
            store: widget.cloudFor(game)!,
            diner: shown,
            onRestore: (d) {
              Storage.saveSlot(game, d);
              setState(() {});
            },
          ),
        ],
        const SizedBox(height: 8),
        Builder(
          builder: (context) {
            final scores = widget.scores ?? defaultScoreBoard();
            final settings = GoldButton(
              key: const ValueKey('settings'),
              label: ':gear: Settings',
              filled: false,
              color: Pal.dim,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsScreen(
                    cloudFor: widget.cloudFor,
                    scores: scores,
                  ),
                ),
              ),
            );
            if (scores == null || !scores.any) return settings;
            return Row(
              children: [
                Expanded(
                  child: GoldButton(
                    key: const ValueKey('leaderboards'),
                    label: ':trophy: Leaderboards',
                    filled: false,
                    color: Pal.dim,
                    onTap: () => scores.show(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: settings),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// The restaurant itself, drawn still, behind the title.
class _Scene extends StatelessWidget {
  const _Scene({super.key, required this.diner});

  final Diner diner;

  @override
  Widget build(BuildContext context) {
    final art = DinerArt.instance;
    if (art == null) return const SizedBox.shrink();
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        final fit = BoardFit.of(diner, size, dpr);
        return ClipRect(
          child: CustomPaint(
            size: size,
            painter: DinerPainter(
              diner: diner,
              art: art,
              fit: fit,
              showProblems: false,
            ),
          ),
        );
      },
    );
  }
}

/// What the backup is up to, in a few words, and the one thing to do about
/// it if there is anything.
enum BackupAction { signIn, backUp, restore, choose }

class _Backup {
  const _Backup(this.text, this.color, [this.action, this.label = '']);

  /// The icon in front of the words: a tick once it is all safe, else a cloud.
  String get icon => color == Pal.green ? ':tick: ' : ':cloud: ';

  final String text;
  final Color color;
  final BackupAction? action;
  final String label;
}

/// Whether this game is safe in the cloud, as plain words, with a button for
/// whatever is left to do: turn it on, back up, restore, or choose.
class CloudLine extends StatefulWidget {
  const CloudLine({
    super.key,
    required this.store,
    required this.diner,
    this.onRestore,
    this.prefix = '',
    this.quiet = false,
  });

  final CloudStore store;

  /// Put before the message, such as "Game 2: ", when several are shown.
  final String prefix;

  /// Say nothing unless there is a backup to report or restore: for a list of
  /// places where most have none, and signing in is offered once, not each.
  final bool quiet;

  /// The game on this phone, or null if the place is empty.
  final Diner? diner;

  /// Carries on with a game restored from the backup.
  final ValueChanged<Diner>? onRestore;

  @override
  State<CloudLine> createState() => _CloudLineState();
}

class _CloudLineState extends State<CloudLine> {
  late Future<_Backup> _status = _check();
  bool _busy = false;

  CloudStore get store => widget.store;
  SaveInfo? get _local =>
      widget.diner == null ? null : SaveInfo.of(widget.diner!);

  Future<_Backup> _check() async {
    final n = store.name;
    try {
      if (!await store.signedIn) {
        return _Backup(
          'Backup to $n is off.',
          Pal.gold,
          BackupAction.signIn,
          'Turn on backup',
        );
      }
      final cloud = await store.read();
      return switch (planSync(_local, cloud?.info)) {
        SyncAction.nothing when cloud == null => _Backup(
          'Nothing to back up yet.',
          Pal.dim,
        ),
        SyncAction.nothing => _Backup('Backed up to $n.', Pal.green),
        SyncAction.upload => _Backup(
          'Your latest progress is not backed up.',
          Pal.gold,
          BackupAction.backUp,
          'Back up now',
        ),
        SyncAction.download => _Backup(
          'A newer save is backed up in $n.',
          Pal.gold,
          BackupAction.restore,
          'Restore it',
        ),
        SyncAction.conflict => _Backup(
          'The backup in $n is different from this phone.',
          Pal.gold,
          BackupAction.choose,
          'Choose which to keep',
        ),
      };
    } catch (_) {
      return _Backup('Could not reach $n.', Pal.red);
    }
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = _check();
    });
  }

  Future<void> _act(BackupAction action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (action == BackupAction.signIn) {
        await store.available;
      } else {
        final local = widget.diner;
        if (action == BackupAction.restore) {
          final cloud = await store.read();
          if (!mounted) return;
          final ok = await askPixel(
            context,
            title: 'Restore this backup?',
            body:
                'On this phone: ${_local?.summary ?? 'nothing'}.\n'
                'In the backup: ${cloud?.info.summary ?? 'nothing'}.\n'
                'Restoring replaces what is on this phone.',
            yes: 'Restore it',
            no: 'Keep mine',
            yesKey: const ValueKey('confirm-restore'),
          );
          if (!ok) return _refresh();
        }
        final r = await SaveSync(store).run(
          local,
          ask: (mine, theirs) async => await askPixel(
            context,
            title: 'Which save do you want to keep?',
            body:
                'On this phone: ${mine.summary}.\n'
                'In the backup: ${theirs.summary}.',
            yes: 'Use the backup',
            no: 'Use this phone',
            yesKey: const ValueKey('use-backup'),
          ),
        );
        if (r.diner != null) widget.onRestore?.call(r.diner!);
      }
    } catch (_) {}
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Backup>(
      future: _status,
      builder: (context, snap) {
        final b = snap.data ?? _Backup('Checking ${store.name}...', Pal.dim);
        final action = b.action;
        if (widget.quiet &&
            snap.hasData &&
            (b.color == Pal.dim || action == BackupAction.signIn)) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PxText(
              _busy
                  ? ':cloud: Working...'
                  : '${b.icon}${widget.prefix}${b.text}',
              key: const ValueKey('cloud-status'),
              style: TextStyle(color: _busy ? Pal.dim : b.color, fontSize: 14),
            ),
            if (action != null) ...[
              const SizedBox(height: 8),
              GoldButton(
                key: const ValueKey('cloud-action'),
                label: b.label,
                filled: false,
                color: Pal.gold,
                onTap: _busy ? null : () => _act(action),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// The games kept on this phone, three places side by side.
class SavesScreen extends StatefulWidget {
  const SavesScreen({
    super.key,
    this.cloudFor = defaultCloudFor,
    this.note = '',
  });

  final CloudFor cloudFor;

  /// Something to say at the top, such as why a new game could not start.
  final String note;

  @override
  State<SavesScreen> createState() => _SavesScreenState();
}

class _SavesScreenState extends State<SavesScreen> {
  Future<void> _open(int n) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SlotScreen(game: n, cloudFor: widget.cloudFor),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      title: 'Saved games',
      subtitle: 'Kept on this phone',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          if (widget.note.isNotEmpty) ...[
            PxText(
              widget.note,
              key: const ValueKey('saves-note'),
              style: const TextStyle(color: Pal.gold, fontSize: 14),
            ),
            const SizedBox(height: 12),
          ],
          for (var n = 1; n <= Storage.slots; n++) ...[
            _row(n),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _row(int n) {
    final info = Storage.slotInfo(n);
    final diner = info != null ? Storage.slotDiner(n) : null;
    final playing = n == Storage.slot && info != null;
    return Panel(
      key: ValueKey('game-$n'),
      onTap: () => _open(n),
      glow: playing ? Pal.gold : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PxText(
                  info == null ? 'Empty' : (diner?.name ?? 'My Diner'),
                  style: const TextStyle(color: Pal.text, fontSize: 17),
                ),
                PxText(
                  info == null ? '' : info.summary,
                  style: const TextStyle(color: Pal.dim, fontSize: 14),
                ),
                if (info != null && savedAgo(info.savedAt).isNotEmpty)
                  PxText(
                    'Saved ${savedAgo(info.savedAt)}',
                    style: const TextStyle(color: Pal.dim, fontSize: 14),
                  ),
              ],
            ),
          ),
          if (playing)
            const PxText(
              'Last played',
              style: TextStyle(color: Pal.gold, fontSize: 14),
            ),
        ],
      ),
    );
  }
}

/// One of the games: play it, keep a copy safe, load into it, or delete it.
class SlotScreen extends StatefulWidget {
  const SlotScreen({
    super.key,
    required this.game,
    this.cloudFor = defaultCloudFor,
  });

  final int game;
  final CloudFor cloudFor;

  @override
  State<SlotScreen> createState() => _SlotScreenState();
}

class _SlotScreenState extends State<SlotScreen> {
  int get n => widget.game;

  Future<void> _delete() async {
    final ok = await askPixel(
      context,
      title: 'Delete game $n?',
      body:
          'This erases it from this phone. A copy kept in the cloud stays '
          'there.',
      yes: 'Delete it',
      no: 'Keep it',
      yesKey: const ValueKey('confirm-delete'),
    );
    if (!ok || !mounted) return;
    Storage.clearSlot(n);
    setState(() {});
  }

  /// Fills this place with a game that came from a code or the cloud.
  void _fill(Diner d) {
    Storage.saveSlot(n, d);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final d = Storage.slotDiner(n);
    final store = widget.cloudFor(n);
    return ScreenFrame(
      title: 'Game $n',
      subtitle: d == null ? 'Empty' : SaveInfo.of(d).summary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          GoldButton(
            key: ValueKey(d == null ? 'start-here' : 'play-$n'),
            label: d == null ? 'New game here' : 'Play this game',
            onTap: () async {
              if (d == null) {
                final ctx = context;
                final name = await askDinerName(ctx);
                if (!mounted) return;
                // ignore: use_build_context_synchronously
                await _play(ctx, n, fresh: true, name: name);
              } else {
                await _play(context, n);
              }
              if (mounted) setState(() {});
            },
          ),
          if (store != null) ...[
            const SizedBox(height: 12),
            CloudLine(
              key: ValueKey('slot-cloud-$n-${d?.savedAt}'),
              store: store,
              diner: d,
              onRestore: _fill,
            ),
          ],
          const SizedBox(height: 16),
          const Eyebrow('Keep it safe'),
          SavePanel(
            key: ValueKey('slot-panel-$n-${d?.savedAt}'),
            diner: d,
            onLoad: _fill,
          ),
          if (d != null) ...[
            const SizedBox(height: 24),
            GoldButton(
              key: const ValueKey('delete-game'),
              label: 'Delete this game',
              filled: false,
              color: Pal.red,
              onTap: _delete,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Daily reward button ───────────────────────────────────────────────────

class _DailyRewardButton extends StatelessWidget {
  const _DailyRewardButton({required this.ready, required this.onTap});

  final bool ready;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: PixelBox(
        key: const ValueKey('daily-reward-button'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        border: enabled && ready ? Pal.gold : Pal.ink,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PxText(
              ':coin:',
              style: TextStyle(
                color: enabled && ready ? Pal.gold : Pal.dim,
                fontSize: 14,
              ),
            ),
            PxText(
              enabled && ready ? 'Claim' : 'Daily',
              style: TextStyle(
                color: enabled && ready ? Pal.gold : Pal.dim,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

