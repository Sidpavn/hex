import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../audio/sound.dart';
import '../data/leaderboards.dart';
import '../data/play_games_store.dart';
import '../data/save_sync.dart';
import '../data/storage.dart';
import '../ui/pixel_dialog.dart';
import '../ui/widgets.dart';
import 'clock.dart';
import '../data/gem_shop.dart';
import 'catalog.dart';
import 'coach.dart';
import 'contracts.dart';
import 'city.dart';
import 'diner.dart';
import 'order_screen.dart';
import 'pause_menu.dart';
import 'vending_dialog.dart';
import 'advice.dart';
import 'events.dart';
import 'challenge.dart';
import 'goals.dart';
import 'goals_screen.dart';
import 'diner_art.dart';
import 'diner_painter.dart';
export 'diner_sprite.dart' show DinerSprite;
import 'shelf_popup.dart';
import 'style_popup.dart';
import 'iso.dart';
import 'menu_screen.dart';
import 'money.dart';
import 'recipes.dart';
import 'service.dart';
import 'report_screen.dart';
import 'staff_screen.dart';
import 'stats_screen.dart';
import 'toast.dart';
import 'traits.dart';
import 'upgrade_screen.dart';

/// Where the day is up to. The layout can only be changed while building:
/// once the doors open, you live with it.
enum Phase { build, service, summary }

/// Whether [kind] is put on an edge between tiles, not on a tile.
bool _onEdge(Kind? kind) => kind == Kind.wall || kind == Kind.pass;

/// What is being done to the selected group of fixtures.
enum _GroupOp { none, move, copy }

/// What a fixture does, for the player: its description plus numbers that
/// depend on what has been upgraded.
String describeFixture(FixtureDef d, Progress p) {
  String secs(int ticks) => (ticks * Pace.tickSeconds).toStringAsFixed(1);
  switch (d.role) {
    case Role.station:
      final r = recipes.values.firstWhere((r) => r.station == d.kind);
      return '${d.info} ${r.name} takes ${secs(p.cookTicks(r.dish))} s.';
    case Role.counter:
      return '${d.info} Each guest takes ${secs(p.checkoutTicks)} s.';
    case Role.decor when d.aura != null:
      return '${d.info} ${d.aura!.describe}';
    default:
      return d.info;
  }
}

/// Where the player runs the restaurant: lay it out, open for the day, watch
/// it run, then spend what was earned.
class BuildScreen extends StatefulWidget {
  const BuildScreen({
    super.key,
    this.diner,
    this.cloud,
    this.scores,
    this.gems,
  });

  /// Start from this diner instead of the saved one (tests).
  final Diner? diner;

  /// Where the save is also kept off the phone (tests). By default Google
  /// Play Games on Android.
  final CloudStore? cloud;

  /// Where the day's scores go (tests). By default the Play Games
  /// leaderboards on Android.
  final ScoreBoard? scores;

  /// Where gems are bought (tests). By default Google Play.
  final GemShop? gems;

  @override
  State<BuildScreen> createState() => _BuildScreenState();
}

class _BuildScreenState extends State<BuildScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late Diner diner = widget.diner ?? Storage.diner ?? Diner.starter();

  Phase _phase = Phase.build;
  DayReport? _report;
  int _levelBefore = 1;
  int _speed = 1;

  // Editing.
  Kind? _placing;
  Placed? _selected;
  Placed? _moving;
  Cell? _hover;
  Dir _facing = Dir.sw;
  bool _facingAuto = true;
  String _note = '';
  int _revision = 0;

  late DinerSim sim = DinerSim(diner);
  late final TickClock clock = TickClock(
    () => sim.tick(),
    step: Pace.tickSeconds,
    animating: () => sim.animating,
  );
  final StaticLayer _layer = StaticLayer();
  final ToastQueue _toasts = ToastQueue();
  late final Ticker _ticker;

  /// Tenths of a second since the screen opened, for the street's walkers.
  final ValueNotifier<int> _stroll = ValueNotifier(0);
  Duration _last = Duration.zero;
  int _coins = 0;

  /// Earnings arrive every few seconds; writing the save each time is
  /// wasteful, so they are written at most this often, and on pause or exit.
  static const _saveEvery = Duration(seconds: 10);
  bool _unsaved = false;
  Duration _savedAt = Duration.zero;

  /// Zoom (device pixels per art pixel) and the room point at the middle of
  /// the board. Null means the whole room, centred.
  int? _k;
  Offset? _focus;
  bool _gesturing = false;
  BoardFit? _fit;
  Size _canvas = Size.zero;

  // One drag or pinch: where it started, so the point under the fingers stays
  // put as they move and the scale changes.
  int _count = 0;
  int _startK = 0;
  double _baseScale = 1;
  Offset _anchor = Offset.zero;
  bool _multi = false;

  bool get _building => _phase == Phase.build;

  /// Choosing several fixtures to move, turn, copy or sell together, and the
  /// ones chosen. [_op] says what is being aimed: a move or a copy. The ghost
  /// is where the group's middle would go, and [_gturns] how far it is turned.
  bool _selecting = false;

  /// The group the build popup opened on last.
  Category _shelfTab = Category.seating;
  final List<Placed> _group = [];
  _GroupOp _op = _GroupOp.none;
  int _gturns = 0;

  /// Something is being aimed with the ghost: a new fixture, one being moved,
  /// or a group being moved or copied.
  bool get _aiming => _placing != null || _op != _GroupOp.none;

  /// A wall stands on an edge between tiles. While one is being placed, the
  /// edge it is aimed at; and a placed wall that has been tapped, to sell.
  Edge? _edge;
  Edge? _wallSel;

  /// The wall being carried to a new edge, while aiming.
  Edge? _wallFrom;

  /// Painting kitchen floor: whether a touch takes it off instead, whether a
  /// stroke has begun (so it is one undo), and the last tile it touched.
  bool _erasing = false;
  bool _stroke = false;
  Cell? _lastPaint;

  /// Looking at the plot to choose a section to buy, and the one chosen.
  bool _expanding = false;
  int? _plotSel;

  /// The guest tapped during service, to read about or rush.
  Guest? _guestSel;

  /// Goals met on the day that just ended, for the summary.
  List<Goal> _dayGoals = [];

  /// The section that just lit up, and how far its flash has faded: 3 down to
  /// 0, a step every tenth of a second.
  int? _flashPlot;
  int _flashStep = 0;
  Duration _flashAt = Duration.zero;
  Duration _now = Duration.zero;

  void _flash(int plot) {
    _flashPlot = plot;
    _flashStep = 3;
    _flashAt = _now;
  }

  @override
  void initState() {
    super.initState();
    _coins = diner.coins;
    // Gems that were paid for while no game was open, and any that arrive
    // from now on.
    diner.gems += _gemShop.takePending();
    _gemShop.onGems = _onGems;
    Sound.instance.music(Music.build);
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker((elapsed) {
      _now = elapsed;
      final tenth = elapsed.inMilliseconds ~/ 100;
      if (tenth != _stroll.value) _stroll.value = tenth;
      if (_flashStep > 0) {
        final step = (3 - (elapsed - _flashAt).inMilliseconds ~/ 100).clamp(
          0,
          3,
        );
        if (step != _flashStep) {
          _flashStep = step;
          if (mounted) setState(() {});
        }
      }
      final dt = (elapsed - _last).inMicroseconds / 1e6;
      _last = elapsed;
      if (_phase == Phase.service) {
        // A stalled frame (app was backgrounded) must not replay as a rush.
        clock.advance(dt.clamp(0.0, 0.25) * _speed);
        _playCues();
        final fed = _toasts.feed(sim.story, elapsed);
        final gone = _toasts.expire(elapsed);
        if ((fed || gone) && mounted) setState(() {});
        if (sim.finished) _endDay();
      }
      if (diner.coins != _coins) {
        _coins = diner.coins;
        _unsaved = true;
        setState(() {});
      }
      if (_unsaved && elapsed - _savedAt >= _saveEvery) _save(elapsed);
    })..start();
  }

  void _save([Duration at = Duration.zero]) {
    Storage.saveDiner(diner);
    _unsaved = false;
    _savedAt = at;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    if (_unsaved) _save(_savedAt);
    // Leaving the app is the moment a player might uninstall it, or switch
    // phones: put the latest in the backup too.
    _backUp();
  }

  DateTime _lastBackup = DateTime.fromMillisecondsSinceEpoch(0);

  /// Sends this phone's save up if it is the one to keep. Never waits, never
  /// shows anything, and at most once a minute.
  void _backUp() {
    final now = DateTime.now();
    if (!Storage.autoBackup) return;
    if (_syncing || now.difference(_lastBackup).inSeconds < 60) return;
    final store = widget.cloud ?? defaultCloudStore(slot: Storage.slot);
    if (store == null) return;
    _lastBackup = now;
    _syncing = true;
    SaveSync(store).quiet(diner).whenComplete(() => _syncing = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Sound.instance.music(null);
    _afterBell?.cancel();
    if (_unsaved) _save();
    _lastBackup = DateTime.fromMillisecondsSinceEpoch(0);
    _backUp();
    _ticker.dispose();
    if (identical(_gemShop.onGems, _onGems)) _gemShop.onGems = null;
    clock.dispose();
    _stroll.dispose();
    _layer.dispose();
    super.dispose();
  }

  /// The layout changed: redraw the still layer and re-plan the kitchen.
  /// Pays out any goal that is now met, and says so.
  void _checkGoals([DayReport? day]) {
    // Once the day is over its report counts, whoever asks.
    day ??= sim.result;
    final met = diner.checkGoals(day);
    if (met.isEmpty) return;
    _coins = diner.coins;
    Sound.instance.play(Sfx.jingleUp);
    if (day != null) _dayGoals = [..._dayGoals, ...met];
    _note = met.length == 1
        ? 'Goal done: ${met.first.title}. +${met.first.reward}'
        : 'Goals done: ${met.map((g) => g.title).join(', ')}. '
              '+${met.fold(0, (a, g) => a + g.reward)}';
    _save(_savedAt);
  }

  void _changed() {
    _revision++;
    _coachTo(Coach.startDay);
    _checkGoals();
    sim.layoutChanged();
    _save(_savedAt);
  }

  // ------------------------------------------------------------ the tips

  /// The tip showing now, if the game is on the first day's tips and the
  /// screen is the one the tip is about.
  Coach? get _coachNow {
    final i = diner.coach;
    if (i < 0 || i >= Coach.values.length) return null;
    final c = Coach.values[i];
    final here = switch (_phase) {
      Phase.build => CoachPhase.build,
      Phase.service => CoachPhase.service,
      Phase.summary => CoachPhase.summary,
    };
    return c.phase == here && !_expanding ? c : null;
  }

  /// Moves the tips on to [to], if they have not got that far already.
  void _coachTo(Coach to) {
    if (diner.coach < 0 || diner.coach >= to.index) return;
    diner.coach = to.index;
    _unsaved = true;
  }

  /// Ends the tips for good.
  void _coachEnd() {
    if (diner.coach < 0) return;
    setState(() => diner.coach = Coach.values.length);
    _save(_savedAt);
  }

  /// The tip, on the board's lower edge: what to do now, and a way out.
  Widget _coachCard(Coach c) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 300),
    child: PixelBox(
      key: const ValueKey('coach-card'),
      color: Pal.panel,
      border: Pal.gold,
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PxText(
            c.text,
            key: const ValueKey('coach-text'),
            style: const TextStyle(color: Pal.text, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 120,
              child: GoldButton(
                key: const ValueKey('coach-skip'),
                label: 'Skip tips',
                compact: true,
                filled: false,
                color: Pal.dim,
                onTap: _coachEnd,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  // ------------------------------------------------------------- the day

  Future<void> _startDay() async {
    if (!sim.report.ready) return;
    setState(() {
      _clearEdit();
      _levelBefore = diner.progress.level;
      diner.clearUndo();
      sim = DinerSim(diner);
      _guestSel = null;
      _toasts.clear();
      _phase = Phase.service;
      _coachTo(Coach.watch);
      _speed = 1;
      _k = null;
      _focus = null;
      _note = '';
    });
    Sound.instance
      ..play(Sfx.bellOpen)
      ..music(Music.service);
  }

  DinerSim? _cueSim;
  int _cuesSeen = 0;
  Timer? _afterBell;

  /// Plays what the sim has recorded since last time.
  void _playCues() {
    if (!identical(_cueSim, sim)) {
      _cueSim = sim;
      _cuesSeen = 0;
    }
    final cues = sim.cues;
    for (; _cuesSeen < cues.length; _cuesSeen++) {
      Sound.instance.cue(cues[_cuesSeen]);
    }
  }

  /// The closing bell, then a few notes for how the day went.
  void _dayEndSounds(DayReport r) {
    Sound.instance
      ..play(Sfx.bellClose)
      ..music(Music.build);
    _afterBell?.cancel();
    _afterBell = Timer(const Duration(milliseconds: 800), () {
      Sound.instance.play(
        r.unpaid > 0
            ? Sfx.warn
            : r.levelsGained > 0
            ? Sfx.jingleUp
            : r.stars >= 2
            ? Sfx.jingleGood
            : Sfx.jingleBad,
      );
    });
  }

  /// The pause menu. A running day is held while it is open, and carries on
  /// at the speed it had.
  Future<void> _openPauseMenu() async {
    final service = _phase == Phase.service;
    final was = _speed;
    if (service) setState(() => _speed = 0);
    final choice = await popupPixel<PauseChoice>(
      context,
      (_) => PauseMenu(diner: diner, inService: service),
    );
    if (!mounted) return;
    if (service) setState(() => _speed = was);
    if (choice == PauseChoice.title) {
      _save(_savedAt);
      // Back to the first screen, which is the title.
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  void _endDay() {
    final report = sim.result ?? sim.finishDay();
    _supplierHint = supplierHint(
      report,
      diner.supplier,
      diner.progress.level,
      farmSeen: diner.hintsSeen.contains('farm'),
    );
    if (_supplierHint?.startsWith('Farm delivery is open') ?? false) {
      diner.hintsSeen.add('farm');
    }
    _dayEndSounds(report);
    _postScores(report);
    diner.gems += report.levelsGained * Diner.levelGems;
    final challenge = DailyChallenge.forDay(
      report.day,
      diner.progress.level,
      hasWindow: diner.window != null,
    );
    if (challenge != null &&
        diner.challengeDayDone != report.day &&
        challenge.met(report)) {
      diner.challengeDayDone = report.day;
      diner.coins += challenge.reward;
    }
    setState(() {
      _checkGoals(report);
      _save(_savedAt);
      _report = report;
      _phase = Phase.summary;
      _coachTo(Coach.nextDay);
      _revision++;
    });
    _syncQuietly();
  }

  /// Sends the day's profit and the coins taken so far to the leaderboards,
  /// if they are new bests. It never waits and never asks anything.
  void _postScores(DayReport r) {
    final board = widget.scores ?? defaultScoreBoard();
    if (board == null) return;
    ScorePoster(
      board,
    ).post(kept: r.earned - r.ingredients - r.wages, total: diner.totalEarned);
  }

  /// A word about the supplier after the day, if there is one.
  String? _supplierHint;

  bool _syncing = false;

  /// What the quiet sync after the day had to say, shown on the summary.
  String _cloudNote = '';

  /// After each day, quietly keeps the cloud copy up to date. It only ever
  /// sends this phone's save up; if the cloud holds something different, it
  /// says so and leaves the choice to the Goals page.
  Future<void> _syncQuietly() async {
    if (!Storage.autoBackup) return;
    final store = widget.cloud ?? defaultCloudStore(slot: Storage.slot);
    if (store == null || _syncing) return;
    _syncing = true;
    final note = await SaveSync(store).quiet(diner);
    _syncing = false;
    if (note == null || !mounted) return;
    setState(() => _cloudNote = note);
  }

  void _nextDay() {
    setState(() {
      if (diner.coach >= 0) diner.coach = Coach.values.length;
      sim = DinerSim(diner);
      _toasts.clear();
      _cloudNote = '';
      _supplierHint = null;
      _dayGoals = [];
      _phase = Phase.build;
      _report = null;
      _revision++;
    });
  }

  Future<void> _openStaff() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => StaffScreen(diner: diner)));
    if (!mounted) return;
    // Who works here may have changed.
    setState(() {
      sim = DinerSim(diner);
      _coins = diner.coins;
      _revision++;
      _checkGoals();
    });
  }

  Future<void> _openGoals() async {
    var startOver = false;
    Diner? loaded;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GoalsScreen(
          diner: diner,
          onReset: () => startOver = true,
          onLoad: (d) => loaded = d,
          onTitle: _save,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {});
    if (loaded != null) {
      _adopt(loaded!);
    } else if (startOver) {
      await _reset();
    }
  }

  /// Carries on with [next] in place of the diner that was here, saving it.
  void _adopt(Diner next) {
    Storage.saveDiner(next);
    setState(() {
      diner = next;
      sim = DinerSim(diner);
      _clearEdit();
      _phase = Phase.build;
      _report = null;
      _k = null;
      _focus = null;
      _note = '';
      _coins = diner.coins;
      _unsaved = false;
      _revision++;
    });
  }

  Future<void> _openMenu() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => MenuScreen(diner: diner)));
    if (!mounted) return;
    setState(() {
      sim = DinerSim(diner);
      _coins = diner.coins;
      _revision++;
      _checkGoals();
    });
  }

  Future<void> _openUpgrades() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => UpgradeScreen(diner: diner)),
    );
    if (!mounted) return;
    // Staff and speeds may have changed.
    setState(() {
      sim = DinerSim(diner);
      _coins = diner.coins;
      _revision++;
      _checkGoals();
    });
  }

  // ------------------------------------------------------------- editing

  void _clearEdit() {
    _placing = null;
    _edge = null;
    _wallSel = null;
    _wallFrom = null;
    _selected = null;
    _moving = null;
    _selecting = false;
    _group.clear();
    _op = _GroupOp.none;
    _gturns = 0;
    _hover = null;
    _facing = Dir.sw;
    _facingAuto = true;
  }

  void _pick(Kind kind) {
    final def = fixtureDefs[kind]!;
    setState(() {
      _selected = null;
      _moving = null;
      _hover = null;
      _edge = null;
      _wallSel = null;
      _wallFrom = null;
      if (_placing == kind) {
        _placing = null;
        _note = '';
        return;
      }
      if (def.unlock > diner.progress.level) {
        _placing = null;
        _note = '${def.name} unlocks at level ${def.unlock}';
        return;
      }
      _placing = kind;
      _facing = Dir.sw;
      _facingAuto = true;
      _note = '';
      _wallSel = null;
      if (kind == Kind.kitchenFloor) {
        _hover = null;
        _erasing = false;
        _note = '';
      } else if (_onEdge(kind)) {
        _hover = null;
        _edge = _defaultEdge(kind);
      } else {
        _hover = _defaultSpot(kind);
      }
      Sound.instance.play(Sfx.tick);
    });
  }

  /// Which way the fixture being placed faces at [at]. Anything hung goes the
  /// way its wall says; the rest face as they were turned.
  Dir _faceAt(Kind kind, Cell at) {
    if (!fixtureDefs[kind]!.hung || diner.hangsKind(kind, at, _facing)) {
      return _facing;
    }
    return diner.defaultFacing(kind, at);
  }

  /// What would happen if the fixture being placed or moved were put down
  /// where the ghost is now. Null when there is no ghost.
  PlaceResult? get _placeResult {
    final kind = _placing;
    if (_onEdge(kind)) {
      if (_edge == null) return null;
      if (_wallFrom != null) return diner.checkMove(_wallFrom!, _edge!);
      return kind == Kind.pass
          ? diner.checkHatch(_edge!)
          : diner.checkWall(_edge!);
    }
    final at = _hover;
    if (kind == null || at == null) return null;
    return diner.check(
      kind,
      at,
      facing: kind == Kind.window ? Dir.se : _faceAt(kind, at),
      ignore: _moving,
      free: _moving != null,
    );
  }

  /// Where to aim a wall to begin with: the free edge nearest the middle of
  /// what is on screen.
  Edge? _defaultEdge(Kind kind) {
    final fit = _fit;
    final centre = fit == null
        ? const Cell(Diner.left + 3, Diner.top + 2)
        : fit.view.cellAt(Offset(_canvas.width, _canvas.height) / 2 / fit.s);
    Edge? best;
    var bestD = 1 << 30;
    for (final c in diner.insideCells()) {
      final d = (c.x - centre.x).abs() + (c.y - centre.y).abs();
      if (d >= bestD) continue;
      for (final e in [Edge(c.x, c.y, true), Edge(c.x, c.y, false)]) {
        final r = kind == Kind.pass
            ? diner.checkHatch(e, free: true)
            : diner.checkWall(e, free: true);
        if (r == PlaceResult.ok) {
          best = e;
          bestD = d;
          break;
        }
      }
    }
    return best;
  }

  /// Where to put the ghost to begin with: the free spot nearest the middle of
  /// what is on screen, so it is always in view and never on top of something.
  Cell? _defaultSpot(Kind kind) {
    final fit = _fit;
    final centre = fit == null
        ? const Cell(Diner.left + 3, Diner.top + 2)
        : fit.view.cellAt(Offset(_canvas.width, _canvas.height) / 2 / fit.s);
    if (kind == Kind.window) {
      final y = diner.windowRow(centre.y);
      return y == null ? null : Cell(diner.right, y);
    }
    Cell? best;
    var bestD = 1 << 30;
    for (final c in diner.insideCells()) {
      final d = (c.x - centre.x).abs() + (c.y - centre.y).abs();
      if (d >= bestD) continue;
      if (diner.check(kind, c, facing: _faceAt(kind, c), free: true) ==
          PlaceResult.ok) {
        best = c;
        bestD = d;
      }
    }
    return best;
  }

  /// Moves the ghost one tile in [d], so it can be put exactly where it
  /// belongs without dragging.
  void _nudge(Dir d) {
    if (_op != _GroupOp.none) {
      setState(() {
        _hover = (_hover ?? diner.groupPivot(_group)).step(d);
        _note = '';
      });
      return;
    }
    final kind = _placing;
    if (kind == null) return;
    if (_onEdge(kind)) {
      final e = _edge;
      if (e == null) return;
      setState(() {
        _edge = Edge(e.x + d.dx, e.y + d.dy, e.alongX);
        _note = '';
      });
      return;
    }
    setState(() {
      var at =
          (_hover ?? _defaultSpot(kind) ?? const Cell(Diner.left, Diner.top))
              .step(d);
      if (kind == Kind.window) {
        final y = diner.windowRow(at.y, ignore: _moving);
        if (y != null) at = Cell(diner.right, y);
      }
      _hover = at;
      _note = '';
    });
  }

  void _rotate() {
    if (_op != _GroupOp.none) {
      setState(() => _gturns = (_gturns + 1) % 4);
      return;
    }
    setState(() {
      final sel = _selected;
      if (sel != null && _moving == null) {
        final r = diner.rotate(sel);
        _note = r == PlaceResult.ok ? '' : "It won't turn here";
        if (r == PlaceResult.ok) _changed();
      } else {
        final kind = _placing;
        if (_onEdge(kind)) {
          // The other side of the same tile: the wall runs the other way.
          final e = _edge;
          if (e != null) _edge = Edge(e.x, e.y, !e.alongX);
        } else if (kind != null && fixtureDefs[kind]!.hung) {
          _facing = _facing == Dir.sw ? Dir.se : Dir.sw;
          final at = _hover;
          _note = at != null && !diner.hangsKind(kind, at, _facing)
              ? 'Only a corner has two walls to hang on'
              : '';
        } else {
          _facing = _facing.cw;
          _facingAuto = false;
        }
      }
    });
  }

  void _startMove() {
    final sel = _selected;
    if (sel == null) return;
    setState(() {
      _moving = sel;
      _placing = sel.kind;
      _facing = sel.facing;
      _facingAuto = false;
      _selected = null;
      _hover = null;
      _note = '';
    });
  }

  void _cancel() => setState(() {
    if (_op != _GroupOp.none) {
      // Back to choosing, with the same fixtures still chosen.
      _op = _GroupOp.none;
      _hover = null;
      _gturns = 0;
    } else {
      _clearEdit();
    }
    _note = '';
  });

  /// Puts the ghost down. A new fixture stays selected, with the ghost where
  /// it was, so the next one can be nudged along and placed; one being moved
  /// is done.
  void _commit() {
    final at = _hover;
    final kind = _placing;
    if (_onEdge(kind)) {
      _commitWall();
      return;
    }
    setState(() {
      if (kind == null || at == null) return;
      final moving = _moving;
      final result = moving != null
          ? diner.relocate(moving, at, _faceAt(kind, at))
          : diner.place(kind, at, _faceAt(kind, at));
      if (result == PlaceResult.ok) {
        _note = moving != null
            ? ''
            : kind == Kind.window
            ? 'Window placed. Anyone can serve it; set someone to it in Staff to keep them there'
            : '${fixtureDefs[kind]!.name} placed';
        if (moving != null) _clearEdit();
        _changed();
        final heavy =
            fixtureDefs[kind]!.role == Role.station || kind == Kind.counter;
        Sound.instance.play(heavy ? Sfx.thud : Sfx.place);
      } else {
        _note = result.message;
        Sound.instance.play(Sfx.no);
      }
    });
  }

  /// Puts a wall on the edge aimed at, and aims at the next one along, so a
  /// long wall is a run of taps.
  void _commitWall() {
    final e = _edge;
    if (e == null) return;
    final hatch = _placing == Kind.pass;
    final from = _wallFrom;
    if (from != null) {
      setState(() {
        final r = diner.moveWall(from, e);
        if (r == PlaceResult.ok) {
          _note = e == from ? '' : (hatch ? 'Pass moved' : 'Wall moved');
          if (e != from) _changed();
          Sound.instance.play(Sfx.place);
          _wallFrom = null;
          _placing = null;
          _edge = null;
          _wallSel = e;
        } else {
          _note = r == PlaceResult.blocksWay
              ? 'That would block off the red tiles. Leave a way to walk through.'
              : r.message;
          Sound.instance.play(Sfx.no);
        }
      });
      return;
    }
    setState(() {
      final result = hatch ? diner.placeHatch(e) : diner.placeWall(e);
      if (result == PlaceResult.ok) {
        _note = hatch ? 'Pass placed' : 'Wall placed';
        _coins = diner.coins;
        _changed();
        // A wall goes on to the next edge along; a pass is one of a kind.
        if (!hatch) {
          _edge = Edge(
            e.x + (e.alongX ? 1 : 0),
            e.y + (e.alongX ? 0 : 1),
            e.alongX,
          );
        }
        Sound.instance.play(hatch ? Sfx.thud : Sfx.place);
      } else {
        _note = result == PlaceResult.blocksWay
            ? 'That would block off the red tiles. Leave a way to walk through.'
            : result.message;
        Sound.instance.play(Sfx.no);
      }
    });
  }

  /// A tap on the board when nothing is being aimed: a fixture, or a wall
  /// nearest the finger, whichever is closer.
  void _tapBoard(Offset p, Cell cell, IsoView view, double s) {
    final near = view.nearestEdge(p / s);
    final wall = diner.walls.contains(near.edge) && near.dist < 0.3;
    final hit = diner.pickAt(cell);
    if (wall && (hit == null || near.dist < 0.12)) {
      setState(() {
        _wallSel = near.edge;
        _selected = null;
        _note = '';
      });
      return;
    }
    setState(() => _wallSel = null);
    _tapSelect(cell);
  }

  @visibleForTesting
  void debugSelectWall(Edge e) => setState(() => _wallSel = e);

  /// Turns the selected wall to run the other way round the same tile.
  void _turnWall() {
    final e = _wallSel;
    if (e == null) return;
    setState(() {
      final to = Edge(e.x, e.y, !e.alongX);
      final r = diner.moveWall(e, to);
      if (r == PlaceResult.ok) {
        _wallSel = to;
        _note = '';
        _changed();
        Sound.instance.play(Sfx.place);
      } else {
        _note = r == PlaceResult.taken
            ? 'There is a wall there already'
            : r == PlaceResult.blocksWay
            ? 'That would block off the red tiles'
            : "It won't turn here";
        Sound.instance.play(Sfx.no);
      }
    });
  }

  /// Picks the selected wall up, to put it on another edge.
  void _moveWall() {
    final e = _wallSel;
    if (e == null) return;
    setState(() {
      _placing = diner.hatches.contains(e) ? Kind.pass : Kind.wall;
      _wallFrom = e;
      _edge = e;
      _wallSel = null;
      _note = '';
    });
  }

  /// Lays or takes off kitchen floor on [c] as a finger passes over it.
  void _paint(Cell c) {
    if (c == _lastPaint) return;
    _lastPaint = c;
    setState(() {
      if (_erasing) {
        if (!diner.kitchen.contains(c)) return;
        if (!_stroke) diner.remember('Removed kitchen floor');
        _stroke = true;
        diner.eraseKitchen(c);
      } else {
        final r = diner.checkKitchen(c);
        if (r != PlaceResult.ok) {
          if (r != PlaceResult.taken) {
            _note = r.message;
            Sound.instance.play(Sfx.no);
          }
          return;
        }
        if (!_stroke) diner.remember('Kitchen floor');
        _stroke = true;
        diner.paintKitchen(c);
        _note = '';
      }
      _coins = diner.coins;
      _changed();
    });
  }

  void _endStroke() {
    if (_stroke) Sound.instance.play(Sfx.place);
    _stroke = false;
    _lastPaint = null;
  }

  void _sellWall() {
    final e = _wallSel;
    if (e == null) return;
    setState(() {
      final hatch = diner.hatches.contains(e);
      if (diner.sellWall(e)) {
        _note =
            '${hatch ? 'Pass' : 'Wall'} sold for '
            '${fixtureDefs[hatch ? Kind.pass : Kind.wall]!.refund}';
        _coins = diner.coins;
        _changed();
        Sound.instance.play(Sfx.coin);
      }
      _wallSel = null;
    });
  }

  // ----------------------------------------------------- several at once

  /// The middle of the chosen fixtures, which a turn is about and the ghost's
  /// position stands for.
  Cell get _pivot => diner.groupPivot(_group);

  /// How the group would be moved with the ghost where it is.
  GroupMove get _gm {
    final at = _hover ?? _pivot;
    return GroupMove(
      dx: at.x - _pivot.x,
      dy: at.y - _pivot.y,
      turns: _gturns,
      pivot: _pivot,
    );
  }

  /// Whether the group could be put down where the ghost is.
  PlaceResult? get _groupResult {
    if (_op == _GroupOp.none || _group.isEmpty || _hover == null) return null;
    return diner.checkGroup(_group, _gm, copy: _op == _GroupOp.copy);
  }

  /// The group as the ghost shows it.
  List<Placed> get _ghosts => _op == _GroupOp.none || _hover == null
      ? const []
      : diner.ghostsOf(_group, _gm);

  void _startSelecting() {
    final sel = _selected;
    if (sel == null) return;
    setState(() {
      _selecting = true;
      _group
        ..clear()
        ..add(sel);
      _selected = null;
      _note = '';
    });
  }

  /// A tap while choosing: add the fixture there, or take it out.
  void _toggleGroup(Cell at) {
    final p = diner.pickAt(at);
    if (p == null) return;
    setState(() {
      if (p.kind == Kind.window) {
        _note = 'The window is moved on its own';
        return;
      }
      _note = '';
      if (!_group.remove(p)) _group.add(p);
    });
  }

  /// Adds every fixture of the kinds already chosen.
  void _selectSameKind() {
    setState(() {
      final kinds = {for (final p in _group) p.kind};
      for (final p in diner.items) {
        if (kinds.contains(p.kind) && !_group.contains(p)) _group.add(p);
      }
      _note = '';
    });
  }

  void _stopSelecting() => setState(() {
    _clearEdit();
    _note = '';
  });

  void _beginOp(_GroupOp op) {
    if (_group.isEmpty) return;
    setState(() {
      _op = op;
      _gturns = 0;
      _note = '';
      _hover = op == _GroupOp.move ? _pivot : _copySpot();
    });
  }

  /// Where a copy could go to begin with: the nearest place it fits.
  Cell _copySpot() {
    final p = _pivot;
    for (var r = 1; r <= 10; r++) {
      for (var dy = -r; dy <= r; dy++) {
        for (var dx = -r; dx <= r; dx++) {
          if (dx.abs() != r && dy.abs() != r) continue;
          final m = GroupMove(dx: dx, dy: dy, pivot: p);
          if (diner.checkGroup(_group, m, copy: true) == PlaceResult.ok) {
            return Cell(p.x + dx, p.y + dy);
          }
        }
      }
    }
    return Cell(p.x, p.y + 2);
  }

  /// A quarter turn for the whole group, where it stands.
  void _turnGroup() {
    if (_group.isEmpty) return;
    setState(() {
      final r = diner.moveGroup(_group, GroupMove(turns: 1, pivot: _pivot));
      _note = r == PlaceResult.ok ? '' : "They won't turn here";
      if (r == PlaceResult.ok) _changed();
    });
  }

  /// Puts the ghost group down: a move is done; a copy leaves the ghost
  /// where it was, so another can be placed beside it.
  void _putDownGroup() {
    final op = _op;
    if (op == _GroupOp.none) return;
    setState(() {
      if (op == _GroupOp.move) {
        final r = diner.moveGroup(_group, _gm);
        if (r != PlaceResult.ok) {
          _note = r.message;
          return;
        }
        final n = _group.length;
        // Done: nothing stays chosen.
        _clearEdit();
        _note = n == 1 ? 'Moved' : 'Moved $n';
      } else {
        final made = diner.copyGroup(_group, _gm);
        _note = made.isEmpty ? 'Nothing placed' : 'Copied ${made.length}';
      }
      _coins = diner.coins;
      _changed();
    });
  }

  void _sellGroup() {
    if (_group.isEmpty) return;
    setState(() {
      final n = _group.length;
      final back = diner.groupRefund(_group);
      diner.sellGroup(_group);
      _clearEdit();
      _note = 'Sold $n for $back';
      _coins = diner.coins;
      _changed();
      Sound.instance.play(Sfx.coin);
    });
  }

  /// A tap on the board during service: pick the guest standing there.
  void _tapGuest(Cell near, Cell exact) {
    // A person is drawn above the tile they stand on, so look a tile toward
    // the viewer first.
    final front = Cell(exact.x + 1, exact.y + 1);
    final g = sim.guestAt(front) ?? sim.guestAt(exact) ?? sim.guestAt(near);
    setState(() {
      _guestSel = g;
      if (g != null) _coachTo(Coach.nextDay);
      // No guest there: a tap on a table with a mess on it clears it.
      if (g == null) {
        sim.cleanAt(front);
        sim.cleanAt(exact);
        sim.cleanAt(near);
      }
    });
  }

  void _rushGuest() {
    final g = _guestSel;
    if (g == null) return;
    setState(() => sim.rush(g));
  }

  void _undo() {
    setState(() {
      final what = diner.undo();
      if (what == null) return;
      _clearEdit();
      _note = 'Undid: ${what.toLowerCase()}';
      _coins = diner.coins;
      _changed();
      Sound.instance.play(Sfx.coin);
    });
  }

  void _tapSelect(Cell at) => setState(() {
    final hit = diner.pickAt(at);
    _selected = hit;
    _note = '';
  });

  void _sell() {
    final p = _selected;
    if (p == null) return;
    setState(() {
      diner.sell(p);
      _selected = null;
      _note = '${p.def.name} sold for ${p.def.refund}';
      _changed();
      Sound.instance.play(Sfx.coin);
    });
  }

  void _startExpanding() {
    setState(() {
      _clearEdit();
      _expanding = true;
      _plotSel = diner.nextPlots.firstOrNull;
      if (_plotSel != null) _flash(_plotSel!);
      _note = '';
      _k = null;
      _focus = null;
      _revision++;
    });
  }

  void _stopExpanding() {
    setState(() {
      _expanding = false;
      _plotSel = null;
      _note = '';
      _k = null;
      _focus = null;
      _revision++;
    });
  }

  /// A tap on the board while expanding: pick the section under it.
  void _pickPlot(Cell at) {
    final i = [
      for (var i = 0; i < Diner.plots.length; i++)
        if (!diner.owned.contains(i) && Diner.plots[i].contains(at)) i,
    ].firstOrNull;
    if (i == null) return;
    setState(() {
      _plotSel = i;
      _flash(i);
      _note = '';
    });
  }

  void _buyPlot() {
    final i = _plotSel;
    if (i == null || !diner.unlock(i)) return;
    setState(() {
      _note = '${Diner.plots[i].name} is yours.';
      _flash(i);
      _plotSel = diner.nextPlots.firstOrNull;
      _coins = diner.coins;
      _k = null;
      _focus = null;
      _changed();
    });
  }

  /// Wipes the saved restaurant and starts over. For testing.
  Future<void> _reset() async {
    final ok = await askPixel(
      context,
      title: 'Start over?',
      body: 'This erases the diner: layout, coins, rating, level and upgrades.',
      yes: 'Erase it',
      no: 'Keep it',
      yesKey: const ValueKey('confirm-reset'),
    );
    if (!ok || !mounted) return;
    Storage.clearDiner();
    setState(() {
      diner = Diner.fresh();
      sim = DinerSim(diner);
      _clearEdit();
      _phase = Phase.build;
      _report = null;
      _k = null;
      _focus = null;
      _note = '';
      _coins = diner.coins;
      _unsaved = false;
      _revision++;
    });
  }

  // ---------------------------------------------------------------- view

  @override
  Widget build(BuildContext context) {
    final art = DinerArt.instance;
    // Back, from the arrow or by swiping, opens the pause menu on every
    // screen of a game: a day is never left half way, and leaving between
    // days is a choice in the menu.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _openPauseMenu();
      },
      child: Scaffold(
        backgroundColor: Pal.bgTop,
        body: Backdrop(
          child: SafeArea(
            child: Column(
              children: [
                _header(),
                Expanded(
                  child: ColoredBox(
                    color: DinerPainter.grass,
                    child: art == null
                        ? const SizedBox.shrink()
                        : LayoutBuilder(builder: (_, box) => _board(art, box)),
                  ),
                ),
                // Never more than half the screen, so the board always has room:
                // on a small phone the panel scrolls.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.5,
                  ),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      child: PixelBox(
                        padding: const EdgeInsets.all(12),
                        child: switch (_phase) {
                          Phase.build =>
                            _expanding ? _expandPanel() : _buildPanel(),
                          Phase.service => _servicePanel(),
                          Phase.summary => _summaryPanel(),
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final progress = diner.progress;
    final String line;
    final Color colour;
    if (_phase == Phase.build) {
      final r = sim.report;
      line = r.ready
          ? 'Rating ${progress.rating.toStringAsFixed(1)} :star:   '
                'about ${progress.expectedGuests} guests'
          : 'Closed: ${r.missing.first}';
      colour = r.ready ? Pal.green : Pal.red;
    } else if (_phase == Phase.service) {
      line = 'Open';
      colour = Pal.green;
    } else {
      line = 'Closed for the day';
      colour = Pal.dim;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GestureDetector(
                key: const ValueKey('header-back'),
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: PxIcon('back'),
                ),
              ),
              Expanded(
                child: PxText(
                  'Day ${_phase == Phase.summary ? progress.day - 1 : progress.day}',
                  style: const TextStyle(
                    color: Pal.gold,
                    fontSize: 26,
                    height: 1,
                  ),
                ),
              ),
              if (_phase == Phase.build) ...[
                GestureDetector(
                  key: const ValueKey('goals'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _openGoals,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    child: PxText(
                      'Goals',
                      style: TextStyle(color: Pal.gold, fontSize: 14),
                    ),
                  ),
                ),
              ],
              PxText(
                ':coin: ${diner.coins}',
                style: const TextStyle(color: Pal.text, fontSize: 20),
              ),
            ],
          ),
          // Under the title, the whole width: a long line wraps here instead
          // of squeezing the title into a sliver on a narrow phone.
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: PxText(line, style: TextStyle(color: colour, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- panels

  String _infoLine() {
    if (_note.isNotEmpty) return _note;
    final progress = diner.progress;
    if (_wallSel != null) {
      final hatch = diner.hatches.contains(_wallSel);
      return hatch
          ? 'A serving hatch. Sell it for ${fixtureDefs[Kind.pass]!.refund}, '
                'or tap Done.'
          : 'A low wall. Sell it for ${fixtureDefs[Kind.wall]!.refund}, or '
                'tap Done.';
    }
    final sel = _selected;
    if (sel != null) {
      final problem = sim.report.problemFor(sel);
      final text = describeFixture(sel.def, progress);
      return problem != null ? '${problem.text}. $text' : text;
    }
    if (_selecting) {
      final n = _group.length;
      if (_op == _GroupOp.none) {
        return n == 0
            ? 'Nothing chosen. Tap a fixture to add it.'
            : '$n chosen. Tap fixtures to add or remove them.';
      }
      final r = _groupResult;
      if (r != null && r != PlaceResult.ok) return r.message;
      return _op == _GroupOp.copy
          ? 'Copy costs ${diner.groupCost(_group)}. Aim, then Place.'
          : 'Aim, then Put down. Rotate turns the group.';
    }
    final kind = _placing;
    if (kind == Kind.kitchenFloor) {
      return _erasing
          ? 'Tap or drag over kitchen tiles to take them off. You get '
                '${fixtureDefs[kind]!.refund} back for each.'
          : 'Tap or drag over tiles to lay kitchen floor, '
                '${fixtureDefs[kind]!.cost} a tile. Guests will not walk on '
                'it.';
    }
    if (_onEdge(kind)) {
      final r = _placeResult;
      if (r == null) {
        return 'Tap near a tile edge to aim, then Place. It takes no floor '
            'space.';
      }
      if (r == PlaceResult.blocksWay) {
        return 'That would block off the red tiles. Leave a way to walk '
            'through.';
      }
      if (r != PlaceResult.ok) return r.message;
      if (_wallFrom != null) {
        return 'Tap Place to move it here. Moving is free.';
      }
      return '${describeFixture(fixtureDefs[kind!]!, progress)} Tap Place '
          'to put it down.';
    }
    if (kind == Kind.window) {
      return 'Tap the right-hand wall where the window goes. Cars pull up in '
          'the side street outside.';
    }
    if (kind != null) {
      final def = fixtureDefs[kind]!;
      final r = _placeResult;
      if (r == null) return 'Tap the floor to aim, then Place.';
      if (r == PlaceResult.blocksWay) {
        return 'That would block off the red tiles. Leave a way to walk '
            'through.';
      }
      if (r != PlaceResult.ok) return r.message;
      return '${describeFixture(def, progress)} '
          '${_moving == null ? 'Tap Place to put it down.' : 'Tap Put down.'}';
    }
    // Nothing else to say: what is special about today.
    final today = diner.today;
    if (today != DayEvent.none && !_expanding) {
      return 'Today: ${today.label}. ${today.blurb}';
    }
    if (!_expanding) return diner.hint ?? '';
    return '';
  }

  Color _infoColour() {
    if (_note.isNotEmpty) {
      final bad = PlaceResult.values.any(
        (r) => r != PlaceResult.ok && r.message == _note,
      );
      return bad || _note.startsWith('It won') ? Pal.red : Pal.text;
    }
    final g = _groupResult;
    if (_op != _GroupOp.none && g != null && g != PlaceResult.ok) {
      return Pal.red;
    }
    final r = _placeResult;
    if (_placing != null && r != null && r != PlaceResult.ok) return Pal.red;
    final sel = _selected;
    if (sel != null && sim.report.problemFor(sel) != null) return Pal.red;
    return Pal.dim;
  }

  /// The panel while choosing a section of the plot to buy: what the chosen
  /// one adds, one button to buy it, and one to finish.
  Widget _expandPanel() {
    final i = _plotSel;
    final p = i == null ? null : Diner.plots[i];
    final why = i == null ? null : diner.whyLocked(i);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (p == null)
          const PxText(
            'All of the plot is yours.',
            key: ValueKey('plot-detail'),
            style: TextStyle(color: Pal.green, fontSize: 17),
          )
        else ...[
          PxText(
            p.name,
            key: const ValueKey('plot-detail'),
            style: const TextStyle(color: Pal.text, fontSize: 17),
          ),
          PxText(
            '${p.tiles} more tiles of floor, ${p.width} by ${p.height}.',
            style: const TextStyle(color: Pal.dim, fontSize: 14),
          ),
          if (why != null)
            PxText(
              why,
              key: const ValueKey('plot-why'),
              style: const TextStyle(color: Pal.red, fontSize: 14),
            ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: GoldButton(
                key: const ValueKey('done-expanding'),
                label: 'Done',
                filled: false,
                color: Pal.text,
                onTap: _stopExpanding,
              ),
            ),
            if (i != null) ...[
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: GoldButton(
                  key: const ValueKey('buy-plot'),
                  label: 'Buy  :coin: ${diner.unlockCost(i)}',
                  filled: why == null,
                  onTap: why == null ? _buyPlot : null,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildPanel() {
    final editing = _aiming;
    final sel = _selected;
    final result = _op != _GroupOp.none ? _groupResult : _placeResult;
    final cost = _op == _GroupOp.copy
        ? diner.groupCost(_group)
        : _placing == null
        ? 0
        : fixtureDefs[_placing!]!.cost;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_selecting && !editing && _challengeCard() != null) ...[
          _challengeCard()!,
          const SizedBox(height: 8),
        ],
        if (!_selecting && !editing && _orderCard() != null) ...[
          _orderCard()!,
          const SizedBox(height: 12),
        ],
        if (editing && _placing == Kind.kitchenFloor)
          ..._paintRows()
        else if (editing)
          ..._placingRows(result, cost)
        else if (_selecting)
          ..._groupRows()
        else ...[
          if (sel != null)
            _selectedRow(sel)
          else if (_wallSel != null)
            _wallRow()
          else
            _idleRow(),
          const SizedBox(height: 8),
          _bottomRow(),
        ],
      ],
    );
  }

  /// Today's daily challenge, shown before service starts.
  Widget? _challengeCard() {
    final c = DailyChallenge.forDay(
      diner.progress.day,
      diner.progress.level,
      hasWindow: diner.window != null && diner.windowOn,
    );
    if (c == null) return null;
    final done = diner.challengeDayDone == diner.progress.day;
    return Panel(
      key: const ValueKey('challenge-card'),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PxText(
            done ? 'Challenge done' : 'Challenge',
            style: TextStyle(
              color: done ? Pal.green : Pal.gold,
              fontSize: 16,
            ),
          ),
          PxText(
            '${c.description}. +${c.reward}',
            style: const TextStyle(color: Pal.dim, fontSize: 14),
          ),
        ],
      ),
    );
  }

  /// Today's catering order, on offer or taken, as a short card that opens it.
  Widget? _orderCard() {
    final taken = diner.takenContract;
    final c = taken ?? diner.offer;
    if (c == null) return null;
    return Panel(
      key: const ValueKey('order-card'),
      padding: const EdgeInsets.all(8),
      onTap: _openOrder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PxText(
            taken != null
                ? 'Catering for ${c.client}: taken'
                : 'Catering order from ${c.client}',
            style: TextStyle(
              color: taken != null ? Pal.green : Pal.gold,
              fontSize: 16,
            ),
          ),
          PxText(
            '${c.summary}. Pays ${c.reward}.'
            '${taken != null && diner.closedForOrder ? ' Doors shut.' : ''}',
            style: const TextStyle(color: Pal.dim, fontSize: 14),
          ),
        ],
      ),
    );
  }

  /// Whether a tap at [c] is on one of the vending machines out front. They
  /// are tall, so a tap above one lands on the tiles behind it.
  bool _onVending(Cell c) {
    for (final (name, at) in streetProps(diner)) {
      if (!name.startsWith('vending')) continue;
      if (c == at ||
          c == Cell(at.x - 1, at.y - 1) ||
          c == Cell(at.x - 2, at.y - 2)) {
        return true;
      }
    }
    return false;
  }

  void _toggleWindow() {
    setState(() => diner.windowOn = !diner.windowOn);
    Storage.saveDiner(diner);
  }

  Future<void> _openVending() async {
    await popupPixel<void>(context, (_) => VendingDialog(diner: diner));
    if (!mounted) return;
    setState(() {
      sim = DinerSim(diner);
      _revision++;
    });
  }

  Future<void> _openOrder() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => OrderScreen(diner: diner)));
    if (!mounted) return;
    setState(() {
      sim = DinerSim(diner);
      _coins = diner.coins;
    });
  }

  GemShop get _gemShop => widget.gems ?? GemShop.instance;

  void _onGems(int n) {
    if (!mounted) return;
    setState(() => diner.gems += n);
    _save(_savedAt);
  }

  Future<void> _openGemShop() =>
      popupPixel<void>(context, (_) => GemShopPopup(shop: _gemShop));

  /// Opens the style popup: wallpapers and floors.
  Future<void> _openStyle() async {
    await popupPixel<void>(
      context,
      (_) => StylePopup(
        diner: diner,
        shop: _openGemShop,
        onChanged: () {
          setState(() => _revision++);
          _save(_savedAt);
        },
      ),
    );
    if (mounted) setState(() {});
  }

  /// Opens the build popup, and starts placing whatever is chosen in it.
  Future<void> _openShelf() async {
    setState(() => _coachTo(Coach.place));
    final kind = await popupPixel<Kind>(
      context,
      (_) => ShelfPopup(
        diner: diner,
        chosen: _placing,
        start: _shelfTab,
        onTab: (c) => _shelfTab = c,
      ),
    );
    if (kind != null && mounted && kind != _placing) _pick(kind);
  }

  /// The controls while painting kitchen floor: paint or erase, and done.
  List<Widget> _paintRows() => [
    Row(
      children: [
        Expanded(
          child: GoldButton(
            key: const ValueKey('paint-on'),
            label: 'Paint',
            filled: !_erasing,
            color: Pal.text,
            onTap: () => setState(() => _erasing = false),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GoldButton(
            key: const ValueKey('paint-off'),
            label: 'Erase',
            filled: _erasing,
            color: Pal.text,
            onTap: () => setState(() => _erasing = true),
          ),
        ),
      ],
    ),
    const SizedBox(height: 8),
    GoldButton(
      key: const ValueKey('cancel-edit'),
      label: 'Done',
      filled: false,
      color: Pal.dim,
      onTap: _cancel,
    ),
  ];

  /// The controls while something is being aimed with the ghost: nudge it a
  /// tile, turn it, then put it down or be done.
  List<Widget> _placingRows(PlaceResult? result, int cost) {
    final group = _op != _GroupOp.none;
    final label = group
        ? (_op == _GroupOp.move ? 'Put down' : 'Place  :coin: $cost')
        : _moving != null || _wallFrom != null
        ? 'Put down'
        : 'Place  :coin: $cost';
    return [
      Row(
        children: [
          for (final d in const [Dir.nw, Dir.ne, Dir.sw, Dir.se]) ...[
            _NudgeButton(
              key: ValueKey('nudge-${d.name}'),
              dir: d,
              onTap: () => _nudge(d),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: GoldButton(
              key: const ValueKey('rotate'),
              label: 'Rotate',
              filled: false,
              color: Pal.text,
              onTap: _rotate,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: GoldButton(
              key: const ValueKey('cancel-edit'),
              label: 'Done',
              filled: false,
              color: Pal.dim,
              onTap: _cancel,
            ),
          ),
          if (!group && _moving == null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: GoldButton(
                key: const ValueKey('another'),
                label: 'Another',
                filled: false,
                color: Pal.text,
                onTap: _openShelf,
              ),
            ),
          ],
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: GoldButton(
              key: const ValueKey('place'),
              label: label,
              onTap: result == PlaceResult.ok
                  ? (group ? _putDownGroup : _commit)
                  : null,
            ),
          ),
        ],
      ),
    ];
  }

  /// The controls while choosing several fixtures: what to do with them.
  List<Widget> _groupRows() {
    final some = _group.isNotEmpty;
    GoldButton button(
      String key,
      String label,
      VoidCallback? onTap, {
      Color color = Pal.text,
    }) => GoldButton(
      key: ValueKey(key),
      label: label,
      filled: false,
      color: color,
      onTap: some ? onTap : null,
    );
    return [
      Row(
        children: [
          Expanded(
            child: button('group-move', 'Move', () => _beginOp(_GroupOp.move)),
          ),
          const SizedBox(width: 8),
          Expanded(child: button('group-turn', 'Turn', _turnGroup)),
          const SizedBox(width: 8),
          Expanded(
            child: button('group-copy', 'Copy', () => _beginOp(_GroupOp.copy)),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(child: button('group-same', 'Same kind', _selectSameKind)),
          const SizedBox(width: 8),
          Expanded(
            child: button(
              'group-sell',
              'Sell +${diner.groupRefund(_group)}',
              _sellGroup,
              color: Pal.dim,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GoldButton(
              key: const ValueKey('group-done'),
              label: 'Done',
              onTap: _stopSelecting,
            ),
          ),
        ],
      ),
    ];
  }

  Widget _selectedRow(Placed sel) => Row(
    children: [
      if (sel.kind == Kind.window) ...[
        Expanded(
          child: GoldButton(
            key: const ValueKey('window-toggle'),
            label: diner.windowOn ? 'Close window' : 'Open window',
            filled: !diner.windowOn,
            color: diner.windowOn ? Pal.text : Pal.gold,
            onTap: _toggleWindow,
          ),
        ),
        const SizedBox(width: 8),
      ],
      if (sel.def.rotates) ...[
        Expanded(
          child: GoldButton(
            key: const ValueKey('rotate'),
            label: 'Rotate',
            filled: false,
            color: Pal.text,
            onTap: _rotate,
          ),
        ),
        const SizedBox(width: 8),
      ],
      Expanded(
        child: GoldButton(
          key: const ValueKey('move'),
          label: 'Move',
          filled: false,
          color: Pal.text,
          onTap: _startMove,
        ),
      ),
      if (sel.kind != Kind.window) ...[
        const SizedBox(width: 8),
        Expanded(
          child: GoldButton(
            key: const ValueKey('select-more'),
            label: 'Select',
            filled: false,
            color: Pal.text,
            onTap: _startSelecting,
          ),
        ),
      ],
      const SizedBox(width: 8),
      Expanded(
        child: GoldButton(
          key: const ValueKey('sell'),
          label: 'Sell +${sel.def.refund}',
          filled: false,
          color: Pal.dim,
          onTap: _sell,
        ),
      ),
    ],
  );

  /// The controls for a wall that has been tapped.
  Widget _wallRow() => Row(
    children: [
      Expanded(
        child: GoldButton(
          key: const ValueKey('wall-done'),
          label: 'Done',
          filled: false,
          color: Pal.text,
          onTap: () => setState(() => _wallSel = null),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: GoldButton(
          key: const ValueKey('turn-wall'),
          label: 'Rotate',
          filled: false,
          color: Pal.text,
          onTap: _turnWall,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: GoldButton(
          key: const ValueKey('move-wall'),
          label: 'Move',
          filled: false,
          color: Pal.text,
          onTap: _moveWall,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: GoldButton(
          key: const ValueKey('sell-wall'),
          label:
              'Sell +${fixtureDefs[diner.hatches.contains(_wallSel) ? Kind.pass : Kind.wall]!.refund}',
          filled: false,
          color: Pal.dim,
          onTap: _sellWall,
        ),
      ),
    ],
  );

  Widget _idleRow() => Row(
    children: [
      Expanded(
        child: GoldButton(
          key: const ValueKey('undo'),
          label: 'Undo',
          filled: false,
          color: diner.canUndo ? Pal.text : Pal.dim,
          onTap: diner.canUndo ? _undo : null,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: GoldButton(
          key: const ValueKey('upgrades'),
          label: 'Upgrades',
          filled: false,
          color: Pal.text,
          onTap: _openUpgrades,
        ),
      ),
    ],
  );

  Widget _bottomRow() => Row(
    children: [
      Expanded(
        child: GoldButton(
          key: const ValueKey('start-day'),
          label: diner.takenContract != null && diner.closedForOrder
              ? 'Start catering day'
              : 'Start day ${diner.progress.day}',
          onTap: sim.report.ready ? _startDay : null,
        ),
      ),
    ],
  );

  /// Who a tapped guest is, how they are doing, and the button to rush them.
  Widget _guestCard(Guest g) => ListenableBuilder(
    listenable: clock,
    builder: (context, _) => _guestCardBody(g),
  );

  Widget _guestCardBody(Guest g) {
    if (g.gone) return const SizedBox.shrink();
    final String status;
    if (g.state == GuestState.waiting) {
      status = g.rushed ? 'Being rushed' : 'Waiting for food';
    } else if (g.state == GuestState.eating) {
      status = 'Eating';
    } else if (g.inQueue || g.state == GuestState.arriving) {
      status = 'In the queue';
    } else {
      status = 'On their way';
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: PixelBox(
        key: const ValueKey('guest-card'),
        color: Pal.panel,
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PxText(
              g.name,
              style: const TextStyle(color: Pal.text, fontSize: 17),
            ),
            PxText(
              g.critic
                  ? 'Food critic. Wants a premium dish.'
                  : g.blogger
                  ? 'Food blogger. Wants a fair price and a short wait.'
                  : '${g.gender.singular[0].toUpperCase()}${g.gender.singular.substring(1)}, '
                        '${g.temper.label.toLowerCase()}, '
                        '${g.wallet.label.toLowerCase()}',
              key: const ValueKey('guest-kind'),
              style: const TextStyle(color: Pal.dim, fontSize: 14),
            ),
            if (g.regular != null)
              PxText(
                'Regular, ${g.regular!.hearts} '
                '${g.regular!.hearts == 1 ? 'heart' : 'hearts'}. Likes '
                '${recipes[g.regular!.favourite]!.name.toLowerCase()}.',
                key: const ValueKey('guest-regular'),
                style: const TextStyle(color: Pal.gold, fontSize: 14),
              ),
            PxText(
              status,
              style: const TextStyle(color: Pal.dim, fontSize: 14),
            ),
            const SizedBox(height: 4),
            PxBar(
              value: g.mood,
              color: g.mood > 0.66
                  ? Pal.green
                  : g.mood > 0.33
                  ? Pal.gold
                  : Pal.red,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: GoldButton(
                    key: const ValueKey('guest-close'),
                    label: 'Close',
                    filled: false,
                    color: Pal.dim,
                    onTap: () => setState(() => _guestSel = null),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: GoldButton(
                    key: const ValueKey('guest-rush'),
                    label: 'Rush  ${sim.rushLeft} left',
                    onTap: sim.canRush(g) ? _rushGuest : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _servicePanel() {
    return ListenableBuilder(
      listenable: clock,
      builder: (context, _) {
        final left = ((Pace.dayTicks - sim.ticks) * Pace.tickSeconds).clamp(
          0,
          9999,
        );
        final m = left ~/ 60;
        final sec = (left % 60).floor().toString().padLeft(2, '0');
        final closing = !sim.open;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: PxText(
                    closing
                        ? 'Last guests finishing up'
                        : _speed == 0
                        ? 'Paused  $m:$sec left'
                        : 'Open  $m:$sec left',
                    style: const TextStyle(color: Pal.text, fontSize: 17),
                  ),
                ),
                PxText(
                  ':coin: +${sim.earned}',
                  style: const TextStyle(color: Pal.gold, fontSize: 17),
                ),
              ],
            ),
            const SizedBox(height: 8),
            PxBar(value: sim.dayProgress, color: Pal.gold),
            if (sim.contract != null) ...[
              const SizedBox(height: 8),
              PxText(
                switch (sim.cateringState) {
                  ContractState.done =>
                    'Catering sent: ${sim.contract!.client}. '
                        '+${sim.cateringPaid}',
                  ContractState.missed => 'Catering missed: not out in time',
                  ContractState.voided => 'Catering called off',
                  _ =>
                    'Catering: ${sim.cateringMade} of '
                        '${sim.contract!.portions} out',
                },
                key: const ValueKey('catering-progress'),
                style: TextStyle(
                  color: switch (sim.cateringState) {
                    ContractState.done => Pal.green,
                    ContractState.missed => Pal.red,
                    ContractState.voided => Pal.dim,
                    _ => Pal.text,
                  },
                  fontSize: 14,
                ),
              ),
              if (sim.cateringOpen)
                PxBar(
                  value: sim.cateringMade / sim.contract!.portions,
                  color: Pal.green,
                ),
            ],
            const SizedBox(height: 8),
            const SizedBox(height: 4),
            Row(
              children: [
                _stat('Served', '${sim.served}', Pal.green),
                _stat('Left angry', '${sim.walkouts}', Pal.red),
                _stat(
                  'In queue',
                  '${sim.guests.where((g) => g.inQueue).length}',
                  Pal.dim,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final s in const [0, 1, 2, 3]) ...[
                  Expanded(
                    flex: s == 0 ? 5 : 3,
                    child: Choice(
                      key: ValueKey(s == 0 ? 'pause' : 'speed-$s'),
                      label: s == 0 ? 'Pause' : '${s}x',
                      selected: _speed == s,
                      onTap: () => setState(() => _speed = s),
                    ),
                  ),
                  if (s != 3) const SizedBox(width: 8),
                ],
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _stat(String label, String value, Color colour) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PxText(value, style: TextStyle(color: colour, fontSize: 22)),
        PxText(label, style: const TextStyle(color: Pal.dim, fontSize: 13)),
      ],
    ),
  );

  /// What kind of day it was, in a word, from how well it went.
  static String _verdict(int stars) => switch (stars) {
    3 => 'Great day',
    2 => 'Good day',
    1 => 'Rough day',
    _ => 'Bad day',
  };

  Widget _summaryPanel() {
    final r = _report;
    if (r == null) return const SizedBox.shrink();
    final progress = diner.progress;
    final kept = r.earned - r.ingredients - r.wages;
    final unlocked = <String>[
      for (final d in Dish.values)
        if (recipes[d]!.unlock > _levelBefore &&
            recipes[d]!.unlock <= progress.level)
          recipes[d]!.name,
      for (final f in fixtureDefs.values)
        if (f.unlock > _levelBefore && f.unlock <= progress.level) f.name,
    ];
    final fix = r.unpaid > 0 ? null : fixFirst(r);
    final best = fix == null ? r.highlights(1).firstOrNull : null;
    final ratingColour = r.reputation > r.reputationBefore
        ? Pal.green
        : r.reputation < r.reputationBefore
        ? Pal.red
        : Pal.dim;
    final dayColour = switch (r.stars) {
      3 || 2 => Pal.green,
      1 => Pal.gold,
      _ => Pal.red,
    };
    final guests = r.served + r.walkouts;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: PxText(
                'Day ${r.day}',
                style: const TextStyle(color: Pal.dim, fontSize: 17),
              ),
            ),
            PxText(
              _verdict(r.stars),
              key: const ValueKey('verdict'),
              style: TextStyle(color: dayColour, fontSize: 17),
            ),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            PxText(
              '${kept >= 0 ? '+' : ''}$kept',
              key: const ValueKey('kept'),
              style: TextStyle(
                color: kept >= 0 ? Pal.gold : Pal.red,
                fontSize: 32,
                height: 1.1,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PxText(
                      'kept today',
                      style: TextStyle(color: Pal.dim, fontSize: 14),
                    ),
                    PxText(
                      profitLine(r),
                      key: const ValueKey('profit-line'),
                      style: const TextStyle(color: Pal.text, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // How the guests went, as one bar: served against left angry.
        SizedBox(
          key: const ValueKey('serve-bar'),
          height: 8,
          child: guests == 0
              ? const ColoredBox(color: Pal.panelLo)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (r.served > 0)
                      Expanded(
                        flex: r.served,
                        child: const ColoredBox(color: Pal.green),
                      ),
                    if (r.served > 0 && r.walkouts > 0)
                      const SizedBox(width: 2),
                    if (r.walkouts > 0)
                      Expanded(
                        flex: r.walkouts,
                        child: const ColoredBox(color: Pal.red),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: PxText(
                '${r.served} served',
                style: const TextStyle(color: Pal.green, fontSize: 14),
              ),
            ),
            PxText(
              '${r.walkouts} left angry',
              style: TextStyle(
                color: r.walkouts == 0 ? Pal.dim : Pal.red,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Stars((r.reputation / 20).round(), of: 5),
            const SizedBox(width: 8),
            Expanded(
              child: PxText(
                '${(r.reputationBefore / 20).toStringAsFixed(1)} to '
                '${(r.reputation / 20).toStringAsFixed(1)}',
                key: const ValueKey('rating-line'),
                style: TextStyle(color: ratingColour, fontSize: 14),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        () {
          final c = DailyChallenge.forDay(
            r.day,
            progress.level,
            hasWindow: diner.window != null,
          );
          if (c == null) return const SizedBox.shrink();
          final done = diner.challengeDayDone == r.day;
          return PxText(
            done
                ? 'Challenge done: ${c.description}. +${c.reward}'
                : 'Challenge missed: ${c.description}',
            key: const ValueKey('challenge-line'),
            style: TextStyle(
              color: done ? Pal.green : Pal.dim,
              fontSize: 14,
            ),
          );
        }(),
        const SizedBox(height: 8),
        if (r.unpaid > 0)
          PxText(
            r.quit.isEmpty
                ? 'Wages short by ${r.unpaid}. Staff are unhappy.'
                : '${r.quit.join(', ')} quit over unpaid wages.',
            key: const ValueKey('unpaid-line'),
            style: const TextStyle(color: Pal.red, fontSize: 14),
          )
        else if (r.catering != null && r.cateringState != ContractState.open)
          PxText(
            switch (r.cateringState) {
              ContractState.done =>
                'Catering sent to ${r.catering!.client}: +${r.cateringReward}.',
              ContractState.missed =>
                'The catering order was not ready. The ingredients are lost '
                    'and the rating dropped ${ContractBook.missedRating}.',
              _ => 'The catering order was called off.',
            },
            key: const ValueKey('catering-line'),
            style: TextStyle(
              color: r.cateringState == ContractState.done
                  ? Pal.green
                  : r.cateringState == ContractState.missed
                  ? Pal.red
                  : Pal.dim,
              fontSize: 14,
            ),
          )
        else if (_dayGoals.isNotEmpty)
          PxText(
            _dayGoals.length == 1
                ? 'Goal done: ${_dayGoals.first.title}. '
                      '+${_dayGoals.first.reward}'
                : '${_dayGoals.length} goals done. '
                      '+${_dayGoals.fold(0, (a, g) => a + g.reward)}',
            key: const ValueKey('goal-line'),
            style: const TextStyle(color: Pal.gold, fontSize: 14),
          )
        else if (r.levelsGained > 0)
          PxText(
            'Level ${progress.level}!'
            '${unlocked.isEmpty ? '' : ' New: ${unlocked.join(', ')}.'}'
            ' +${r.levelsGained * Diner.levelGems} gems.',
            key: const ValueKey('level-line'),
            style: const TextStyle(color: Pal.gold, fontSize: 14),
          )
        else if (best != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 5, right: 8),
                child: SizedBox(
                  width: 6,
                  height: 6,
                  child: ColoredBox(
                    color: switch (best.tone) {
                      Tone.good => Pal.green,
                      Tone.bad => Pal.red,
                      Tone.mixed => Pal.gold,
                    },
                  ),
                ),
              ),
              Expanded(
                child: PxText(
                  best.text,
                  key: const ValueKey('story-line'),
                  style: const TextStyle(color: Pal.text, fontSize: 14),
                ),
              ),
            ],
          ),
        if (fix != null) ...[
          const SizedBox(height: 8),
          PxText(
            'Fix first: $fix',
            key: const ValueKey('fix-first'),
            style: const TextStyle(color: Pal.text, fontSize: 14),
          ),
        ],
        if (_supplierHint != null) ...[
          const SizedBox(height: 8),
          PxText(
            _supplierHint!,
            key: const ValueKey('supplier-hint'),
            style: const TextStyle(color: Pal.dim, fontSize: 14),
          ),
        ],
        if (_cloudNote.isNotEmpty) ...[
          const SizedBox(height: 8),
          PxText(
            _cloudNote,
            key: const ValueKey('cloud-note'),
            style: const TextStyle(color: Pal.dim, fontSize: 14),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 7,
              child: GoldButton(
                key: const ValueKey('details'),
                label: 'Details',
                filled: false,
                color: Pal.text,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        DayReportScreen(report: r, progress: progress),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 5,
              child: GoldButton(
                key: const ValueKey('next-day'),
                label: 'Next day',
                onTap: _nextDay,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --------------------------------------------------------------- board

  Widget _board(DinerArt art, BoxConstraints box) {
    final canvas = Size(box.maxWidth, box.maxHeight);
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final fit = BoardFit.of(diner, canvas, dpr, k: _k, focus: _focus);
    _fit = fit;
    _canvas = canvas;
    final s = fit.s;

    Cell cellAt(Offset p) => fit.view.cellAt(p / s);

    /// What a tap on [p] means: tall fixtures are drawn above the cell they
    /// stand on, so look one cell toward the viewer first.
    Cell pickCell(Offset p) {
      final c = cellAt(p);
      final front = Cell(c.x + 1, c.y + 1);
      return diner.isInside(front) && diner.pickAt(front) != null ? front : c;
    }

    void aim(Offset p) {
      if (!_aiming || !_building) return;
      if (_placing == Kind.kitchenFloor) {
        _paint(cellAt(p));
        return;
      }
      if (_onEdge(_placing)) {
        final e = fit.view.nearestEdge(p / s).edge;
        if (e != _edge) setState(() => _edge = e);
        return;
      }
      var c = cellAt(p);
      if (_placing == Kind.window) {
        // The window only goes in the right-hand wall: wherever it is aimed,
        // it snaps to the nearest place along it that works.
        final y = diner.windowRow(c.y, ignore: _moving);
        if (y != null) c = Cell(diner.right, y);
      }
      if (_placing != null &&
          fixtureDefs[_placing!]!.hung &&
          !diner.isInside(c)) {
        // Aimed at the wall itself: hang it on the floor edge just in front.
        for (final n in [Cell(c.x, c.y + 1), Cell(c.x + 1, c.y)]) {
          if (diner.isInside(n)) {
            c = n;
            break;
          }
        }
      }
      if (c == _hover) return;
      setState(() {
        _hover = c;
        if (_op == _GroupOp.none && _facingAuto && _moving == null) {
          _facing = diner.defaultFacing(_placing!, c);
        } else if (_placing != null && fixtureDefs[_placing!]!.hung) {
          _facing = _faceAt(_placing!, c);
        }
      });
    }

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              // A vending machine on the street, between days: what it sells,
              // and whether it is on.
              if (_phase == Phase.build &&
                  !_expanding &&
                  !_selecting &&
                  !_aiming &&
                  _onVending(cellAt(d.localPosition))) {
                _openVending();
                return;
              }
              if (_phase == Phase.service) {
                _tapGuest(pickCell(d.localPosition), cellAt(d.localPosition));
                return;
              }
              if (!_building) return;
              if (_expanding) {
                _pickPlot(cellAt(d.localPosition));
              } else if (_selecting && _op == _GroupOp.none) {
                _toggleGroup(pickCell(d.localPosition));
              } else if (!_aiming) {
                _tapBoard(
                  d.localPosition,
                  pickCell(d.localPosition),
                  fit.view,
                  s,
                );
              } else {
                aim(d.localPosition);
              }
            },
            onScaleStart: (d) {
              _rebase(d.localFocalPoint, 1, d.pointerCount);
              _multi = d.pointerCount > 1;
              if (_aiming && !_multi) aim(d.localFocalPoint);
            },
            onScaleUpdate: (d) {
              if (d.pointerCount != _count) {
                _rebase(d.localFocalPoint, d.scale, d.pointerCount);
              }
              if (d.pointerCount > 1) {
                _multi = true;
                if (_hover != null) setState(() => _hover = null);
              }
              // One finger moves the fixture being placed; otherwise it moves
              // the view. Two fingers always move and zoom the view.
              if (_aiming && !_multi && _building) {
                aim(d.localFocalPoint);
              } else {
                _moveView(d, dpr);
              }
            },
            onTapUp: (_) => _endStroke(),
            onTapCancel: _endStroke,
            onScaleEnd: (_) {
              _endStroke();
              _multi = false;
              setState(() => _gesturing = false);
            },
            child: CustomPaint(
              key: const ValueKey('diner-board'),
              size: canvas,
              painter: DinerPainter(
                diner: diner,
                art: art,
                fit: fit,
                layer: _layer,
                gesturing: _gesturing,
                doorOpen: () => _phase == Phase.service && sim.open,
                grid: _aiming && _building,
                group: _selecting ? _group : const [],
                groupMoving: _op == _GroupOp.move,
                ghostGroup: _ghosts,
                expanding: _expanding && _building,
                plotSel: _plotSel,
                flashPlot: _flashPlot,
                flash: _flashStep,
                placing: _building ? _placing : null,
                hover: _hover,
                hoverEdge: _building && _onEdge(_placing) ? _edge : null,
                selectedEdge: _building ? _wallSel : null,
                guestSel: _phase == Phase.service ? _guestSel : null,
                placeOk: _op != _GroupOp.none
                    ? _groupResult == PlaceResult.ok
                    : _placeResult == PlaceResult.ok,
                selected: _building ? _selected : null,
                facing: _placing == null
                    ? _facing
                    : _faceAt(_placing!, _hover ?? const Cell(0, 0)),
                moving: _moving,
                revision: _revision,
                showProblems: _building,
                sim: sim,
                clock: clock,
                stroll: _stroll,
              ),
            ),
          ),
        ),
        if (_phase == Phase.service)
          Positioned(left: 8, top: 8, child: ToastStack(toasts: _toasts.shown)),
        if (_phase == Phase.service && _guestSel != null && !_guestSel!.gone)
          Positioned(left: 8, bottom: 8, child: _guestCard(_guestSel!)),
        if (_coachNow case final c?)
          Positioned(left: 8, right: 56, bottom: 8, child: _coachCard(c)),
        if (_phase == Phase.build && _infoLine().isNotEmpty)
          Positioned(
            // Beside the square buttons, not under them.
            left: _railShown ? 68 : 8,
            top: 8,
            child: IgnorePointer(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: _railShown ? 176 : 232),
                child: PixelBox(
                  key: const ValueKey('hint'),
                  color: Pal.panel,
                  border: _infoColour() == Pal.red ? Pal.red : Pal.ink,
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 8,
                  ),
                  child: PxText(
                    _infoLine(),
                    key: const ValueKey('info-line'),
                    style: TextStyle(
                      color: _infoColour() == Pal.dim
                          ? Pal.text
                          : _infoColour(),
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (_railShown) Positioned(left: 8, top: 8, bottom: 8, child: _rail()),
        Positioned(
          right: 8,
          top: 8,
          child: Column(
            children: [
              _ZoomButton(
                key: const ValueKey('zoom-in'),
                label: '+',
                onTap: fit.k < fit.kMax ? () => _zoomBy(1) : null,
              ),
              const SizedBox(height: 8),
              _ZoomButton(
                key: const ValueKey('zoom-out'),
                label: '-',
                onTap: fit.zoomed ? () => _zoomBy(-1) : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool get _railShown =>
      _phase == Phase.build && !_expanding && !_aiming && !_selecting;

  /// Square buttons down the left of the board: what you do between days.
  /// They wrap into a second column if the board is short.
  Widget _rail() {
    final wages = diner.coins < diner.roster.wages;
    return Wrap(
      direction: Axis.vertical,
      spacing: 8,
      runSpacing: 8,
      children: [
        _RailButton(
          key: const ValueKey('build-mode'),
          icon: 'hammer',
          label: 'Build',
          active: false,
          hint: _coachNow == Coach.openBuild,
          onTap: _openShelf,
        ),
        _RailButton(
          key: const ValueKey('style'),
          icon: 'brush',
          label: 'Style',
          onTap: _openStyle,
        ),
        _RailButton(
          key: const ValueKey('expand'),
          icon: 'expand',
          label: 'Expand',
          onTap: _startExpanding,
        ),
        _RailButton(
          key: const ValueKey('menu'),
          icon: 'scroll',
          label: 'Menu',
          onTap: _openMenu,
        ),
        _RailButton(
          key: const ValueKey('staff'),
          icon: 'people',
          label: 'Staff',
          // Tonight's wages are more than is in the till: worth a look.
          warn: wages,
          onTap: _openStaff,
        ),
        _RailButton(
          key: const ValueKey('stats'),
          icon: 'chart',
          label: 'Stats',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => StatsScreen(diner: diner)),
          ),
        ),
      ],
    );
  }

  /// Remember where a drag or pinch began, in room coordinates.
  void _rebase(Offset focal, double scale, int count) {
    final fit = _fit!;
    _count = count;
    _startK = fit.k;
    _baseScale = scale;
    final centre = Offset(_canvas.width / 2, _canvas.height / 2);
    _anchor = fit.focus + (focal - centre) / fit.s;
  }

  void _moveView(ScaleUpdateDetails d, double dpr) {
    final fit = _fit!;
    final wanted = d.pointerCount > 1
        ? (_startK * d.scale / _baseScale).round()
        : _startK;
    final k = wanted.clamp(fit.kFit, fit.kMax);
    final centre = Offset(_canvas.width / 2, _canvas.height / 2);
    setState(() {
      _k = k;
      _focus = _anchor - (d.localFocalPoint - centre) / (k / dpr);
      _gesturing = true;
    });
  }

  /// Zoom a step with the buttons: a bigger jump at larger sizes, and always
  /// by at least one whole pixel.
  void _zoomBy(int dir) {
    final fit = _fit!;
    final next = dir > 0
        ? math.max(fit.k + 1, (fit.k * 1.5).round())
        : math.min(fit.k - 1, (fit.k / 1.5).round());
    setState(() {
      _k = next.clamp(fit.kFit, fit.kMax);
      _focus = _k == fit.kFit ? null : fit.focus;
    });
  }
}

/// A square icon button with its name under it, on the board's edge.
class _RailButton extends StatelessWidget {
  const _RailButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.warn = false,
    this.hint = false,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool warn;

  /// The tip is about this button: a gold border says so.
  final bool hint;

  @override
  Widget build(BuildContext context) {
    // The biggest whole multiple of the icon that leaves room for the name.
    final mult = PixelUi.unit(context) * 24 <= 34 ? 2 : 1;
    return Panel(
      onTap: onTap,
      glow: warn ? Pal.red : (active || hint ? Pal.gold : null),
      padding: EdgeInsets.zero,
      child: SizedBox(
        width: 52,
        height: 52,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Transform.scale(
              scale: 1.2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PxIcon(icon, mult: mult),
                  PxText(
                    label,
                    style: TextStyle(
                      color: warn ? Pal.red : (active ? Pal.gold : Pal.dim),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small square button over the board.
class _ZoomButton extends StatelessWidget {
  const _ZoomButton({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Panel(
      onTap: onTap,
      dim: onTap == null,
      padding: EdgeInsets.zero,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Center(
          child: PxText(
            label,
            style: const TextStyle(color: Pal.text, fontSize: 24),
          ),
        ),
      ),
    );
  }
}

/// A small square button with an arrow pointing one way along the grid, which
/// on the isometric board is a diagonal.
class _NudgeButton extends StatelessWidget {
  const _NudgeButton({super.key, required this.dir, required this.onTap});

  final Dir dir;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 44,
    child: Panel(
      onTap: onTap,
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        height: 24,
        child: CustomPaint(painter: _ArrowPainter(dir)),
      ),
    ),
  );
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter(this.dir);

  final Dir dir;

  @override
  void paint(Canvas canvas, Size size) {
    // Screen direction of a step along the grid: x runs down-right, y runs
    // down-left.
    final sx = (dir.dx - dir.dy).toDouble();
    final sy = (dir.dx + dir.dy).toDouble();
    final c = size.center(Offset.zero);
    final n = Offset(sx, sy) / 1.4142;
    final side = Offset(-n.dy, n.dx);
    const r = 8.0;
    final path = Path()
      ..moveTo(c.dx + n.dx * r, c.dy + n.dy * r)
      ..lineTo(
        c.dx - n.dx * r + side.dx * r * 0.8,
        c.dy - n.dy * r + side.dy * r * 0.8,
      )
      ..lineTo(c.dx - n.dx * r * 0.2, c.dy - n.dy * r * 0.2)
      ..lineTo(
        c.dx - n.dx * r - side.dx * r * 0.8,
        c.dy - n.dy * r - side.dy * r * 0.8,
      )
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = Pal.text
        ..isAntiAlias = false,
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.dir != dir;
}
