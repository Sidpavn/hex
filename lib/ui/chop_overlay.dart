import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'widgets.dart';
import 'zone_overlays.dart' show ModalFrame;

/// The timing strike for felling a tree. A marker steps along a bar; tap
/// Strike while it is over the gold cells. Three swings, each harder than the
/// last (a narrower zone, a faster marker), and each hit is one wood. Miss all
/// three and the tree stays standing. Nothing here can hurt you.
class ChopOverlay extends StatefulWidget {
  const ChopOverlay({
    super.key,
    required this.onDone,
    required this.onCancel,
    this.random,
  });

  /// Source for the zone positions; tests pass a seeded one.
  final Random? random;

  /// Called with the number of hits (0 to 3) once the last swing has landed.
  final void Function(int hits) onDone;

  final VoidCallback onCancel;

  static const cells = 21;
  static const swings = 3;

  /// Gold cells either side of a swing's centre: wide, then narrow, then
  /// narrowest.
  static const zoneHalf = [3, 2, 1];

  /// How long the marker rests on a cell. Later swings are faster.
  static const stepMs = [60, 50, 42];

  /// Fresh zone centres for one tree. Each sits fully on the bar and at least
  /// [minGap] cells from the one before, so the target always moves.
  static const minGap = 6;
  static List<int> pickCenters(Random r) {
    final out = <int>[];
    for (var i = 0; i < swings; i++) {
      final lo = zoneHalf[i];
      final hi = cells - 1 - zoneHalf[i];
      int c;
      do {
        c = lo + r.nextInt(hi - lo + 1);
      } while (out.isNotEmpty && (c - out.last).abs() < minGap);
      out.add(c);
    }
    return out;
  }

  /// Chips thrown off the trunk by a strike: whole-pixel velocity (x, y) per
  /// frame. A hit throws wood; a miss only kicks up a few grey flecks.
  static const _chips = [
    (-5, -9),
    (-3, -12),
    (-1, -8),
    (2, -11),
    (4, -9),
    (6, -7),
    (-6, -5),
    (3, -6),
  ];
  static const _chipFrames = 7;
  static const _chipMs = 45;

  /// Whether a strike with the marker on [cell] hits swing [swing] of [centers].
  static bool hits(List<int> centers, int swing, int cell) =>
      (cell - centers[swing]).abs() <= zoneHalf[swing];

  @override
  State<ChopOverlay> createState() => _ChopOverlayState();
}

class _ChopOverlayState extends State<ChopOverlay> {
  late final List<int> _centers = ChopOverlay.pickCenters(
    widget.random ?? Random(),
  );
  int _swing = 0;
  int _pos = 0;
  int _dir = 1;
  final List<bool> _results = [];

  /// The marker stops for a moment after each strike so you can see it.
  bool _resting = false;
  bool _jolt = false;
  Timer? _timer;
  Timer? _after;
  Timer? _chipTimer;

  /// Frame of the chip burst, or null when none is showing.
  int? _chipFrame;
  bool _chipHit = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _after?.cancel();
    _chipTimer?.cancel();
    super.dispose();
  }

  void _run() {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(milliseconds: ChopOverlay.stepMs[_swing]),
      (_) => setState(() {
        _pos += _dir;
        if (_pos >= ChopOverlay.cells - 1) {
          _pos = ChopOverlay.cells - 1;
          _dir = -1;
        } else if (_pos <= 0) {
          _pos = 0;
          _dir = 1;
        }
      }),
    );
  }

  bool get _over => _results.length >= ChopOverlay.swings;
  int get _hitCount => _results.where((h) => h).length;

  void _strike() {
    if (_resting || _over) return;
    _timer?.cancel();
    final hit = ChopOverlay.hits(_centers, _swing, _pos);
    if (hit) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.lightImpact();
    }
    setState(() {
      _results.add(hit);
      _resting = true;
      _jolt = true;
    });
    _burst(hit);
    _after = Timer(const Duration(milliseconds: 140), () {
      if (mounted) setState(() => _jolt = false);
    });
    if (_over) {
      _after = Timer(
        const Duration(milliseconds: 800),
        () => widget.onDone(_hitCount),
      );
      return;
    }
    _after = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() {
        _swing++;
        _pos = 0;
        _dir = 1;
        _resting = false;
      });
      _run();
    });
  }

  void _burst(bool hit) {
    _chipTimer?.cancel();
    setState(() {
      _chipFrame = 0;
      _chipHit = hit;
    });
    _chipTimer = Timer.periodic(
      const Duration(milliseconds: ChopOverlay._chipMs),
      (t) {
        if (!mounted) return;
        setState(() {
          final f = (_chipFrame ?? 0) + 1;
          if (f >= ChopOverlay._chipFrames) {
            _chipFrame = null;
            t.cancel();
          } else {
            _chipFrame = f;
          }
        });
      },
    );
  }

  /// Chips fly out on whole-pixel steps and fall under a fixed gravity.
  List<Widget> _chipWidgets(double u) {
    final f = _chipFrame;
    if (f == null) return const [];
    final chips = _chipHit
        ? ChopOverlay._chips
        : ChopOverlay._chips.sublist(0, 3);
    return [
      for (var i = 0; i < chips.length; i++)
        Transform.translate(
          offset: Offset(
            (chips[i].$1 * f ~/ 2) * u,
            ((chips[i].$2 * f + f * f * 2) ~/ 2) * u,
          ),
          child: Container(
            width: (i.isEven ? 3 : 2) * u,
            height: (i.isEven ? 3 : 2) * u,
            color: _chipHit
                ? (i % 3 == 0 ? Pal.goldLight : Pal.goldDark)
                : Pal.dim,
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final u = PixelUi.unit(context);
    final last = _results.isEmpty ? null : _results.last;
    return ModalFrame(
      onDismiss: widget.onCancel,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: PixelBox(
            border: Pal.gold,
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Chop tree',
                  style: TextStyle(color: Pal.gold, fontSize: 26, height: 1),
                ),
                const SizedBox(height: 6),
                Text(
                  _over
                      ? (_hitCount > 0 ? '$_hitCount wood' : 'Missed all three')
                      : 'Swing ${_swing + 1} of ${ChopOverlay.swings}. Hit the gold.',
                  style: TextStyle(
                    color: _over ? Pal.goldLight : Pal.dim,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Padding(
                    padding: EdgeInsets.only(left: _jolt ? 2 * u : 0),
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        const PxIcon('tree', mult: 5),
                        ..._chipWidgets(u),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _bar(u, last),
                const SizedBox(height: 10),
                _pips(u),
                const SizedBox(height: 14),
                GoldButton(
                  label: 'Strike',
                  onTap: _resting || _over ? null : _strike,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bar(double u, bool? last) {
    final level = _over ? ChopOverlay.swings - 1 : _swing;
    final zone = _centers[level];
    final half = ChopOverlay.zoneHalf[level];
    Color cell(int i) {
      if (i == _pos) {
        if (_resting && last != null) return last ? Pal.green : Pal.red;
        return Pal.text;
      }
      return (i - zone).abs() <= half ? Pal.goldDark : Pal.panelHi;
    }

    return Center(
      child: Container(
        padding: EdgeInsets.all(u),
        color: Pal.ink,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < ChopOverlay.cells; i++)
              Container(width: 4 * u, height: 8 * u, color: cell(i)),
          ],
        ),
      ),
    );
  }

  Widget _pips(double u) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < ChopOverlay.swings; i++)
          Container(
            width: 6 * u,
            height: 6 * u,
            margin: EdgeInsets.symmetric(horizontal: u),
            decoration: BoxDecoration(
              color: i >= _results.length
                  ? Pal.panelLo
                  : (_results[i] ? Pal.gold : Pal.red),
              border: Border.all(color: Pal.ink, width: u),
            ),
          ),
      ],
    );
  }
}
