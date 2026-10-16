import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../data/storage.dart';
import '../ui/pixel_dialog.dart';
import '../ui/widgets.dart';
import 'clock.dart';
import 'contracts.dart';
import 'city.dart';
import 'diner.dart';
import 'order_screen.dart';
import 'vending_dialog.dart';
import 'advice.dart';
import 'events.dart';
import 'goals.dart';
import 'goals_screen.dart';
import 'diner_art.dart';
import 'diner_painter.dart';
import 'iso.dart';
import 'menu_screen.dart';
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
  const BuildScreen({super.key, this.diner});

  /// Start from this diner instead of the saved one (tests).
  final Diner? diner;

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
  final List<Placed> _group = [];
  _GroupOp _op = _GroupOp.none;
  int _gturns = 0;

  /// Something is being aimed with the ghost: a new fixture, one being moved,
  /// or a group being moved or copied.
  bool get _aiming => _placing != null || _op != _GroupOp.none;

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
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker((elapsed) {
      _now = elapsed;
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
    if (state != AppLifecycleState.resumed && _unsaved) _save(_savedAt);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_unsaved) _save();
    _ticker.dispose();
    clock.dispose();
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
    if (day != null) _dayGoals = [..._dayGoals, ...met];
    _note = met.length == 1
        ? 'Goal done: ${met.first.title}. +${met.first.reward}'
        : 'Goals done: ${met.map((g) => g.title).join(', ')}. '
              '+${met.fold(0, (a, g) => a + g.reward)}';
    _save(_savedAt);
  }

  void _changed() {
    _revision++;
    _checkGoals();
    sim.layoutChanged();
    _save(_savedAt);
  }

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
      _speed = 1;
      _k = null;
      _focus = null;
      _note = '';
    });
  }

  void _endDay() {
    final report = sim.result ?? sim.finishDay();
    setState(() {
      _checkGoals(report);
      _save(_savedAt);
      _report = report;
      _phase = Phase.summary;
      _revision++;
    });
  }

  void _nextDay() {
    setState(() {
      sim = DinerSim(diner);
      _toasts.clear();
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
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            GoalsScreen(diner: diner, onReset: () => startOver = true),
      ),
    );
    if (!mounted) return;
    setState(() {});
    if (startOver) await _reset();
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
      _hover = _defaultSpot(kind);
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
        if (kind != null && fixtureDefs[kind]!.hung) {
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
      } else {
        _note = result.message;
      }
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
      diner = Diner.starter();
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
    return Scaffold(
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
        if (!_selecting && !editing && _orderCard() != null) ...[
          _orderCard()!,
          const SizedBox(height: 12),
        ],
        if (!_selecting) ...[_shelf(), const SizedBox(height: 12)],
        if (editing)
          ..._placingRows(result, cost)
        else if (_selecting)
          ..._groupRows()
        else ...[
          if (sel != null) _selectedRow(sel) else _idleRow(),
          const SizedBox(height: 8),
          _bottomRow(),
        ],
      ],
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

  /// The fixtures that can be bought, to pick one to place.
  Widget _shelf() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final def in fixtureDefs.values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _FixtureTile(
              key: ValueKey('fixture-${def.kind.name}'),
              def: def,
              selected: _placing == def.kind,
              affordable: diner.coins >= def.cost,
              locked: def.unlock > diner.progress.level,
              onTap: () => _pick(def.kind),
            ),
          ),
      ],
    ),
  );

  /// The controls while something is being aimed with the ghost: nudge it a
  /// tile, turn it, then put it down or be done.
  List<Widget> _placingRows(PlaceResult? result, int cost) {
    final group = _op != _GroupOp.none;
    final label = group
        ? (_op == _GroupOp.move ? 'Put down' : 'Place  :coin: $cost')
        : _moving != null
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
      if (sel.def.turns) ...[
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
          key: const ValueKey('expand'),
          label: 'Expand',
          filled: false,
          color: Pal.text,
          onTap: _startExpanding,
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
          key: const ValueKey('staff'),
          // A red flag when tonight's wages are more than is in the till:
          // the takings may still cover it, but it is worth a look.
          label: diner.coins < diner.roster.wages ? 'Staff !' : 'Staff',
          filled: false,
          color: diner.coins < diner.roster.wages ? Pal.red : Pal.text,
          onTap: _openStaff,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: GoldButton(
          key: const ValueKey('menu'),
          label: 'Menu',
          filled: false,
          color: Pal.text,
          onTap: _openMenu,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: GoldButton(
          key: const ValueKey('stats'),
          label: 'Stats',
          filled: false,
          color: Pal.text,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => StatsScreen(diner: diner)),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        flex: 2,
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
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: PxText(
                  'kept today',
                  style: TextStyle(color: Pal.dim, fontSize: 14),
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
            '${unlocked.isEmpty ? '' : ' New: ${unlocked.join(', ')}.'}',
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
    final fit = BoardFit.of(
      diner,
      canvas,
      dpr,
      k: _k,
      focus: _focus,
      whole: _expanding,
    );
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
                _tapSelect(pickCell(d.localPosition));
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
            onScaleEnd: (_) {
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
              ),
            ),
          ),
        ),
        if (_phase == Phase.service)
          Positioned(left: 8, top: 8, child: ToastStack(toasts: _toasts.shown)),
        if (_phase == Phase.service && _guestSel != null && !_guestSel!.gone)
          Positioned(left: 8, bottom: 8, child: _guestCard(_guestSel!)),
        if (_phase == Phase.build && _infoLine().isNotEmpty)
          Positioned(
            left: 8,
            top: 8,
            child: IgnorePointer(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 232),
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

/// A fixture in the picker: its sprite and price.
class _FixtureTile extends StatelessWidget {
  const _FixtureTile({
    super.key,
    required this.def,
    required this.selected,
    required this.affordable,
    required this.locked,
    required this.onTap,
  });

  final FixtureDef def;
  final bool selected;
  final bool affordable;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Panel(
      onTap: onTap,
      dim: (locked || !affordable) && !selected,
      glow: selected ? Pal.gold : null,
      padding: const EdgeInsets.all(6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 52),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 44,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: DinerSprite(spriteName(def.kind, Dir.sw)),
              ),
            ),
            const SizedBox(height: 4),
            PxText(
              locked ? ':lock: Lv ${def.unlock}' : ':coin: ${def.cost}',
              style: TextStyle(
                color: affordable && !locked ? Pal.text : Pal.dimmer,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A fixture's sprite for the picker: just the part with pixels in it, one
/// art pixel per whole device-pixel multiple.
class DinerSprite extends StatelessWidget {
  const DinerSprite(this.name, {super.key, this.mult = 1});

  final String name;

  /// Whole-number size multiple.
  final int mult;

  @override
  Widget build(BuildContext context) {
    final art = DinerArt.instance;
    if (art == null) return const SizedBox.shrink();
    final spr = art.sprite(name);
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final u = math.max(1, dpr.floor()) / dpr * mult;
    return SizedBox(
      width: spr.trim.width * u,
      height: spr.trim.height * u,
      child: CustomPaint(painter: _SpritePainter(spr)),
    );
  }
}

class _SpritePainter extends CustomPainter {
  _SpritePainter(this.spr);

  final Spr spr;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      spr.image,
      spr.trim,
      Offset.zero & size,
      Paint()
        ..filterQuality = FilterQuality.none
        ..isAntiAlias = false,
    );
  }

  @override
  bool shouldRepaint(covariant _SpritePainter old) => old.spr != spr;
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
