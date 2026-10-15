import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../data/storage.dart';
import '../ui/widgets.dart';
import 'clock.dart';
import 'diner.dart';
import 'diner_art.dart';
import 'diner_painter.dart';
import 'iso.dart';
import 'service.dart';

/// Where the player lays out the restaurant: pick a fixture, drag it onto the
/// floor, let go to place it. Tap a fixture to select it and sell it.
class BuildScreen extends StatefulWidget {
  const BuildScreen({super.key, this.diner});

  /// Start from this diner instead of the saved one (tests).
  final Diner? diner;

  @override
  State<BuildScreen> createState() => _BuildScreenState();
}

class _BuildScreenState extends State<BuildScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Diner diner = widget.diner ?? Storage.diner ?? Diner.starter();

  Kind? _placing;
  Placed? _selected;
  Cell? _hover;
  String _note = '';
  int _revision = 0;

  late final DinerSim sim = DinerSim(diner);
  late final TickClock clock = TickClock(
    sim.tick,
    step: Pace.tickSeconds,
    animating: () => sim.animating,
  );
  final StaticLayer _layer = StaticLayer();
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  int _coins = 0;

  /// Earnings arrive every few seconds; writing the save each time is
  /// wasteful, so they are written at most this often, and on pause or exit.
  static const _saveEvery = Duration(seconds: 10);
  bool _unsaved = false;
  Duration _savedAt = Duration.zero;

  @override
  void initState() {
    super.initState();
    _coins = diner.coins;
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker((elapsed) {
      final dt = (elapsed - _last).inMicroseconds / 1e6;
      _last = elapsed;
      // A stalled frame (app was backgrounded) must not replay as a rush.
      clock.advance(dt.clamp(0.0, 0.25));
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

  void _changed() {
    _revision++;
    sim.layoutChanged();
    _save(_savedAt);
  }

  void _pick(Kind kind) => setState(() {
    _selected = null;
    _hover = null;
    if (_placing == kind) {
      _placing = null;
      _note = '';
      return;
    }
    _placing = kind;
    final def = fixtureDefs[kind]!;
    _note = diner.coins < def.cost
        ? PlaceResult.broke.message
        : 'Drag onto the floor, let go to place';
  });

  void _commit() {
    final at = _hover;
    final kind = _placing;
    setState(() {
      _hover = null;
      if (kind == null || at == null) return;
      final def = fixtureDefs[kind]!;
      final cells = Placed(0, kind, at).cells;
      final result = !def.floor && cells.any(sim.occupied)
          ? PlaceResult.occupied
          : diner.place(kind, at);
      if (result == PlaceResult.ok) {
        _note = '${fixtureDefs[kind]!.name} placed';
        _changed();
      } else {
        _note = result.message;
      }
    });
  }

  void _tapSelect(Cell at) => setState(() {
    final hit = diner.isInside(at) ? diner.pickAt(at) : null;
    _selected = hit;
    final problem = hit == null ? null : sim.report.problemFor(hit);
    _note = hit == null
        ? ''
        : problem != null
        ? problem.text
        : '${hit.def.name}: sells for ${hit.def.refund}';
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

  void _expand() {
    final next = diner.nextStage;
    if (next == null) return;
    setState(() {
      if (diner.expand()) {
        _note = 'Room is now ${next.width} by ${next.height}';
        _changed();
      } else {
        _note = PlaceResult.broke.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final art = DinerArt.instance;
    final next = diner.nextStage;
    return Scaffold(
      backgroundColor: Pal.bgTop,
      body: Backdrop(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 16, 6),
                child: Row(
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const PxText(
                            'Diner',
                            style: TextStyle(
                              color: Pal.gold,
                              fontSize: 26,
                              height: 1,
                            ),
                          ),
                          PxText(
                            sim.report.ready
                                ? 'Open, ${sim.report.seats} seats'
                                : 'Closed: ${sim.report.missing.first}',
                            style: TextStyle(
                              color: sim.report.ready ? Pal.green : Pal.red,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PxText(
                      ':coin: ${diner.coins}',
                      style: const TextStyle(color: Pal.text, fontSize: 20),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ColoredBox(
                  color: DinerPainter.grass,
                  child: art == null
                      ? const SizedBox.shrink()
                      : LayoutBuilder(builder: (_, box) => _board(art, box)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: PixelBox(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 20,
                        child: PxText(
                          _note.isEmpty ? 'Choose a fixture to place' : _note,
                          maxLines: 1,
                          style: TextStyle(
                            color: _note.isEmpty ? Pal.dim : Pal.text,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
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
                                  onTap: () => _pick(def.kind),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: next == null
                                ? const SizedBox.shrink()
                                : GoldButton(
                                    label: 'Expand room  :coin: ${next.cost}',
                                    onTap: diner.canExpand ? _expand : null,
                                  ),
                          ),
                          if (_selected != null) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: GoldButton(
                                label: 'Sell  +${_selected!.def.refund}',
                                filled: false,
                                color: Pal.dim,
                                onTap: _sell,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _board(DinerArt art, BoxConstraints box) {
    final canvas = Size(box.maxWidth, box.maxHeight);
    final fit = BoardFit.of(
      diner,
      canvas,
      MediaQuery.of(context).devicePixelRatio,
    );
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
      if (_placing == null) return;
      final c = cellAt(p);
      if (c != _hover) setState(() => _hover = c);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) {
        if (_placing == null) {
          _tapSelect(pickCell(d.localPosition));
        } else {
          aim(d.localPosition);
        }
      },
      onTapUp: (_) => _commit(),
      onTapCancel: () => setState(() => _hover = null),
      onPanStart: (d) => aim(d.localPosition),
      onPanUpdate: (d) => aim(d.localPosition),
      onPanEnd: (_) => _commit(),
      child: CustomPaint(
        key: const ValueKey('diner-board'),
        size: canvas,
        painter: DinerPainter(
          diner: diner,
          art: art,
          fit: fit,
          grid: _placing != null,
          placing: _placing,
          hover: _hover,
          selected: _selected,
          revision: _revision,
          sim: sim,
          clock: clock,
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
    required this.onTap,
  });

  final FixtureDef def;
  final bool selected;
  final bool affordable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Panel(
      onTap: onTap,
      dim: !affordable && !selected,
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
                child: DinerSprite(
                  def.kind == Kind.chair ? 'chair_sw' : def.kind.name,
                ),
              ),
            ),
            const SizedBox(height: 4),
            PxText(
              ':coin: ${def.cost}',
              style: TextStyle(
                color: affordable ? Pal.text : Pal.dimmer,
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
  const DinerSprite(this.name, {super.key});

  final String name;

  @override
  Widget build(BuildContext context) {
    final art = DinerArt.instance;
    if (art == null) return const SizedBox.shrink();
    final spr = art.sprite(name);
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final u = math.max(1, dpr.floor()) / dpr;
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
