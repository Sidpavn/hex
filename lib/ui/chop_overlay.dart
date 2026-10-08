import 'dart:async';

import 'package:flutter/material.dart';

import 'widgets.dart';
import 'zone_overlays.dart' show ModalFrame;

/// The timing strike for felling a tree. A marker steps along a bar; tap
/// Strike while it is over the gold cells. Three swings, and each hit is one
/// more wood (a tree always gives at least one). Nothing here can hurt you.
class ChopOverlay extends StatefulWidget {
  const ChopOverlay({
    super.key,
    required this.onDone,
    required this.onQuick,
    required this.onCancel,
  });

  /// Called with the number of hits (0 to 3) once the last swing has landed.
  final void Function(int hits) onDone;

  /// Skip the game: chop for the minimum.
  final VoidCallback onQuick;
  final VoidCallback onCancel;

  static const cells = 21;
  static const swings = 3;

  /// Gold cells either side of a swing's centre.
  static const zoneHalf = 2;

  /// Where each swing's gold cells sit, and how long the marker rests on a
  /// cell. Later swings are faster.
  static const centers = [10, 4, 16];
  static const stepMs = [60, 50, 42];

  /// Whether a strike with the marker on [cell] hits swing [swing].
  static bool hits(int swing, int cell) =>
      (cell - centers[swing]).abs() <= zoneHalf;

  @override
  State<ChopOverlay> createState() => _ChopOverlayState();
}

class _ChopOverlayState extends State<ChopOverlay> {
  int _swing = 0;
  int _pos = 0;
  int _dir = 1;
  final List<bool> _results = [];

  /// The marker stops for a moment after each strike so you can see it.
  bool _resting = false;
  bool _jolt = false;
  Timer? _timer;
  Timer? _after;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _after?.cancel();
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
    setState(() {
      _results.add(ChopOverlay.hits(_swing, _pos));
      _resting = true;
      _jolt = true;
    });
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
                      ? '${_hitCount > 0 ? _hitCount : 1} wood'
                      : 'Strike when the marker is over the gold.',
                  style: TextStyle(
                    color: _over ? Pal.goldLight : Pal.dim,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Padding(
                    padding: EdgeInsets.only(left: _jolt ? 2 * u : 0),
                    child: const PxIcon('tree', mult: 5),
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
                const SizedBox(height: 6),
                GoldButton(
                  label: 'Quick chop (1 wood)',
                  filled: false,
                  onTap: _over ? null : widget.onQuick,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bar(double u, bool? last) {
    final zone = ChopOverlay.centers[_over ? ChopOverlay.swings - 1 : _swing];
    Color cell(int i) {
      if (i == _pos) {
        if (_resting && last != null) return last ? Pal.green : Pal.red;
        return Pal.text;
      }
      return (i - zone).abs() <= ChopOverlay.zoneHalf
          ? Pal.goldDark
          : Pal.panelHi;
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
