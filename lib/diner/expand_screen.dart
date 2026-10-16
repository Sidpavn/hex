import 'package:flutter/material.dart';

import '../data/storage.dart';
import '../ui/widgets.dart';
import 'diner.dart';

/// The plot as a map: the restaurant at the front, and the sections behind
/// and beside it that can be bought one at a time. Tap a section to see what
/// it adds and what it costs.
class ExpandScreen extends StatefulWidget {
  const ExpandScreen({super.key, required this.diner});

  final Diner diner;

  @override
  State<ExpandScreen> createState() => _ExpandScreenState();
}

class _ExpandScreenState extends State<ExpandScreen> {
  Diner get diner => widget.diner;

  int? _sel;
  String _note = '';

  @override
  void initState() {
    super.initState();
    _sel = diner.nextPlots.firstOrNull;
  }

  void _buy(int i) {
    setState(() {
      if (diner.unlock(i)) {
        _note = '${Diner.plots[i].name} is yours.';
        Storage.saveDiner(diner);
        _sel = diner.nextPlots.firstOrNull;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Furthest back at the top, the street at the bottom, as it is on screen.
    const rows = [
      [4, 5],
      [2, 3],
      [0, 1],
    ];
    return ScreenFrame(
      title: 'Expand',
      subtitle: 'Your plot, from the back to the street',
      trailing: PxText(
        ':coin: ${diner.coins}',
        style: const TextStyle(color: Pal.text, fontSize: 20),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          for (final r in rows) ...[
            Row(
              children: [
                for (var k = 0; k < r.length; k++) ...[
                  if (k > 0) const SizedBox(width: 6),
                  Expanded(flex: Diner.plots[r[k]].width, child: _tile(r[k])),
                ],
              ],
            ),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: 6),
          _detail(),
        ],
      ),
    );
  }

  Widget _tile(int i) {
    final p = Diner.plots[i];
    final mine = diner.owned.contains(i);
    final next = diner.nextPlots.contains(i);
    final selected = _sel == i;
    return GestureDetector(
      key: ValueKey('plot-$i'),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        _sel = i;
        _note = '';
      }),
      child: SizedBox(
        height: p.height * 16.0,
        child: PixelBox(
          color: mine ? Pal.panelHi : Pal.panel,
          border: selected ? Pal.gold : Pal.ink,
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PxText(
                '${p.width} by ${p.height}',
                style: TextStyle(
                  color: mine || next ? Pal.text : Pal.dim,
                  fontSize: 14,
                ),
              ),
              PxText(
                mine ? 'Yours' : ':coin: ${diner.unlockCost(i)}',
                style: TextStyle(
                  color: mine
                      ? Pal.green
                      : next
                      ? Pal.gold
                      : Pal.dim,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail() {
    final i = _sel;
    if (i == null) {
      return const PxText(
        'All of the plot is yours.',
        style: TextStyle(color: Pal.green, fontSize: 14),
      );
    }
    final p = Diner.plots[i];
    final mine = diner.owned.contains(i);
    final why = diner.whyLocked(i);
    return Panel(
      key: const ValueKey('plot-detail'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PxText(p.name, style: const TextStyle(color: Pal.text, fontSize: 17)),
          PxText(
            mine
                ? '${p.width} by ${p.height} tiles, part of the restaurant.'
                : '${p.tiles} more tiles of floor, ${p.width} by ${p.height}.',
            style: const TextStyle(color: Pal.dim, fontSize: 14),
          ),
          if (!mine) ...[
            const SizedBox(height: 8),
            GoldButton(
              key: const ValueKey('buy-plot'),
              label: why ?? 'Buy  :coin: ${diner.unlockCost(i)}',
              filled: why == null,
              onTap: why == null ? () => _buy(i) : null,
            ),
          ],
          if (_note.isNotEmpty) ...[
            const SizedBox(height: 8),
            PxText(
              _note,
              key: const ValueKey('expand-note'),
              style: const TextStyle(color: Pal.green, fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }
}
