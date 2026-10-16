import 'package:flutter/material.dart';

import '../data/storage.dart';
import '../ui/widgets.dart';
import 'build_screen.dart' show DinerSprite;
import 'diner.dart';
import 'events.dart';
import 'recipes.dart';
import 'suppliers.dart';

/// The morning's shopping: how many portions of each dish to prepare. What is
/// not sold is thrown away.
class PrepScreen extends StatefulWidget {
  const PrepScreen({super.key, required this.diner});

  final Diner diner;

  @override
  State<PrepScreen> createState() => _PrepScreenState();
}

class _PrepScreenState extends State<PrepScreen> {
  Diner get diner => widget.diner;

  void _portions(Dish d, int by) {
    setState(() {
      final now = diner.portions(d);
      diner.plan[d] = (now + by).clamp(0, 99);
    });
    Storage.saveDiner(diner);
  }

  void _supplier(Supplier s) {
    setState(() => diner.supplier = s);
    Storage.saveDiner(diner);
  }

  /// Who the ingredients are bought from: three choices, and what the one
  /// chosen means.
  Widget _suppliers() {
    final s = diner.supplier;
    final lost = s.spoiledShare(diner.progress.day);
    return Panel(
      key: const ValueKey('suppliers'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final o in Supplier.values)
                Choice(
                  key: ValueKey('supplier-${o.name}'),
                  label: o.label,
                  selected: s == o,
                  locked: o.unlock > diner.progress.level,
                  onTap: () => _supplier(o),
                ),
            ],
          ),
          const SizedBox(height: 8),
          PxText(
            s.blurb,
            key: const ValueKey('supplier-blurb'),
            style: const TextStyle(color: Pal.dim, fontSize: 14),
          ),
          if (lost > 0.2)
            PxText(
              'A bad delivery is due today: about ${(lost * 100).round()}% '
              'of it will be spoiled.',
              key: const ValueKey('supplier-warning'),
              style: const TextStyle(color: Pal.red, fontSize: 14),
            ),
          if (Supplier.values.any((o) => o.unlock > diner.progress.level))
            PxText(
              'The farm opens at level ${Supplier.farm.unlock}.',
              style: const TextStyle(color: Pal.dim, fontSize: 14),
            ),
        ],
      ),
    );
  }

  void _useForecast() {
    setState(() => diner.plan.clear());
    Storage.saveDiner(diner);
  }

  @override
  Widget build(BuildContext context) {
    final menu = diner.menu();
    final cost = diner.prepCost();
    final short = cost - diner.coins;
    return ScreenFrame(
      title: "Today's portions",
      subtitle: diner.today == DayEvent.none
          ? 'About ${diner.expectedToday} guests expected'
          : 'About ${diner.expectedToday} guests, ${diner.today.label.toLowerCase()}',
      trailing: PxText(
        ':coin: ${diner.coins}',
        style: const TextStyle(color: Pal.text, fontSize: 20),
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              children: [
                const Eyebrow('Supplier'),
                _suppliers(),
                const SizedBox(height: 12),
                const Eyebrow('Portions'),
                Panel(
                  key: const ValueKey('prep'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [for (final d in menu) _row(d)],
                  ),
                ),
                const SizedBox(height: 8),
                const PxText(
                  'How many of each to prepare. The ingredients are paid for '
                  'when the day starts, and whatever is not sold is thrown '
                  'away.',
                  style: TextStyle(color: Pal.dim, fontSize: 14),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PxText(
                  short > 0
                      ? 'Projected cost :coin: $cost, but only ${diner.coins} '
                            'in the till: some will be left out.'
                      : 'Projected cost :coin: $cost',
                  key: const ValueKey('prep-total'),
                  style: TextStyle(
                    color: short > 0 ? Pal.red : Pal.text,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 8),
                GoldButton(
                  key: const ValueKey('prep-forecast'),
                  label: 'Use the forecast',
                  filled: false,
                  color: Pal.text,
                  onTap: diner.plan.isEmpty ? null : _useForecast,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(Dish d) {
    final n = diner.portions(d);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 28, child: DinerSprite('ico_${d.name}', mult: 3)),
          const SizedBox(width: 8),
          Expanded(
            child: PxText(
              recipes[d]!.name,
              style: const TextStyle(color: Pal.text, fontSize: 15),
            ),
          ),
          SizedBox(
            width: 44,
            child: GoldButton(
              key: ValueKey('prep-minus-${d.name}'),
              label: '-',
              filled: false,
              color: Pal.text,
              onTap: n > 0 ? () => _portions(d, -1) : null,
            ),
          ),
          SizedBox(
            width: 44,
            child: PxText(
              '$n',
              key: ValueKey('prep-count-${d.name}'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Pal.text, fontSize: 18),
            ),
          ),
          SizedBox(
            width: 44,
            child: GoldButton(
              key: ValueKey('prep-plus-${d.name}'),
              label: '+',
              filled: false,
              color: Pal.text,
              onTap: () => _portions(d, 1),
            ),
          ),
          SizedBox(
            width: 56,
            child: PxText(
              ':coin: ${(n * diner.unitCost(d)).round()}',
              textAlign: TextAlign.right,
              style: const TextStyle(color: Pal.dim, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
