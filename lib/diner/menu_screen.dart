import 'package:flutter/material.dart';

import '../data/storage.dart';
import '../ui/widgets.dart';
import 'build_screen.dart' show DinerSprite;
import 'diner.dart';
import 'dish_screen.dart';
import 'prep_screen.dart';
import 'recipes.dart';

/// What the restaurant sells: one line per dish, switched on or off. A dish
/// has its own page for its ingredients and recipe, and the day's shopping
/// has one too.
class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key, required this.diner});

  final Diner diner;

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  Diner get diner => widget.diner;
  String _note = '';

  void _toggle(Dish d) {
    setState(() {
      final ok = diner.toggleOffer(d);
      _note = ok ? '' : 'The menu is full: take something off first';
    });
    Storage.saveDiner(diner);
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) setState(() => _note = '');
  }

  @override
  Widget build(BuildContext context) {
    final menu = diner.menu();
    final cost = diner.prepCost();
    return ScreenFrame(
      title: 'Menu',
      subtitle: '${menu.length} of ${diner.menuSlots} places on the menu',
      trailing: PxText(
        ':coin: ${diner.coins}',
        style: const TextStyle(color: Pal.text, fontSize: 20),
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                for (final c in Course.values) ...[
                  Eyebrow(c.label),
                  for (final r in recipes.values.where(
                    (r) => r.course == c,
                  )) ...[
                    _row(r, menu.contains(r.dish)),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 4),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_note.isNotEmpty) ...[
                  PxText(
                    _note,
                    key: const ValueKey('menu-note'),
                    style: const TextStyle(color: Pal.red, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                ],
                Panel(
                  key: const ValueKey('open-prep'),
                  onTap: () => _open(PrepScreen(diner: diner)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const PxText(
                              "Today's portions",
                              style: TextStyle(color: Pal.text, fontSize: 17),
                            ),
                            const PxText(
                              'How many of each to prepare',
                              style: TextStyle(color: Pal.dim, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const PxText(
                            'Projected cost',
                            style: TextStyle(color: Pal.dim, fontSize: 13),
                          ),
                          PxText(
                            ':coin: $cost',
                            key: const ValueKey('projected-cost'),
                            style: TextStyle(
                              color: cost > diner.coins ? Pal.red : Pal.text,
                              fontSize: 17,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The price as a bar, its length the price against the dearest dish on
  /// the menu. Grey is what the ingredients cost, green is what is left, and
  /// the number at the end is that profit.
  Widget _priceBar(Dish d, double price, double cost, double profit) {
    final dearest = [
      for (final r in recipes.values)
        diner.progress.price(r.dish) * diner.tierOf(r.dish).priceMul,
    ].reduce((a, b) => a > b ? a : b);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: (price / dearest).clamp(0.1, 1.0),
                child: SizedBox(
                  key: ValueKey('price-bar-${d.name}'),
                  height: 8,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: (cost * 100).round().clamp(1, 100000),
                        child: const ColoredBox(color: Pal.dimmer),
                      ),
                      Expanded(
                        flex: (profit * 100).round().clamp(1, 100000),
                        child: const ColoredBox(color: Pal.green),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          PxText(
            '+${profit.toStringAsFixed(1)}',
            key: ValueKey('profit-${d.name}'),
            style: const TextStyle(color: Pal.green, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _row(Recipe r, bool on) {
    final why = diner.whyNot(r.dish);
    final tier = diner.tierOf(r.dish);
    final sells = diner.progress.price(r.dish) * tier.priceMul;
    final cost = diner.unitCost(r.dish);
    final profit = sells - cost;
    final lvl = diner.progress.recipeLvl(r.dish);
    return Panel(
      key: ValueKey('dish-${r.dish.name}'),
      dim: why != null,
      padding: const EdgeInsets.all(12),
      onTap: () => _open(DishScreen(diner: diner, dish: r.dish)),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Center(child: DinerSprite('plate_${r.dish.name}', mult: 3)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PxText(
                  '${r.name}   level $lvl',
                  style: const TextStyle(color: Pal.text, fontSize: 17),
                ),
                if (why != null)
                  PxText(
                    why,
                    style: const TextStyle(color: Pal.red, fontSize: 14),
                  )
                else
                  _priceBar(r.dish, sells, cost, profit),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 72,
            child: GoldButton(
              key: ValueKey('offer-${r.dish.name}'),
              label: on ? 'On' : 'Off',
              filled: on,
              color: on ? Pal.gold : Pal.dim,
              onTap: why != null && !on ? null : () => _toggle(r.dish),
            ),
          ),
        ],
      ),
    );
  }
}
