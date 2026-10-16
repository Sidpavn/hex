import 'package:flutter/material.dart';

import '../data/storage.dart';
import '../ui/widgets.dart';
import 'build_screen.dart' show DinerSprite;
import 'diner.dart';
import 'guests.dart';
import 'recipes.dart';

/// One dish: what it is made from, and how good the recipe is.
class DishScreen extends StatefulWidget {
  const DishScreen({super.key, required this.diner, required this.dish});

  final Diner diner;
  final Dish dish;

  @override
  State<DishScreen> createState() => _DishScreenState();
}

class _DishScreenState extends State<DishScreen> {
  Diner get diner => widget.diner;
  Dish get dish => widget.dish;
  Recipe get r => recipes[dish]!;

  void _tier(Tier t) {
    setState(() => diner.tiers[dish] = t);
    Storage.saveDiner(diner);
  }

  void _levelUp() {
    final cost = diner.progress.recipeUpgradeCost(dish);
    if (diner.coins < cost || !diner.progress.canLevelRecipe(dish)) return;
    setState(() {
      diner.coins -= cost;
      diner.progress.recipeLevel[dish] = diner.progress.recipeLvl(dish) + 1;
    });
    Storage.saveDiner(diner);
  }

  void _price_(int steps) {
    setState(() => diner.nudgePrice(dish, steps));
    Storage.saveDiner(diner);
  }

  /// What the player charges: a step up or down from the usual, and which
  /// kinds of guest will pay it.
  Widget _price() {
    final m = diner.markupOf(dish);
    final ratio = diner.priceRatio(dish);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 56,
                child: GoldButton(
                  key: const ValueKey('price-minus'),
                  label: '-',
                  filled: false,
                  color: Pal.text,
                  onTap: m > Diner.markupMin ? () => _price_(-1) : null,
                ),
              ),
              Expanded(
                child: PxText(
                  m == 0 ? 'Usual price' : '${m > 0 ? '+' : ''}$m%',
                  key: const ValueKey('price-shown'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Pal.text, fontSize: 17),
                ),
              ),
              SizedBox(
                width: 56,
                child: GoldButton(
                  key: const ValueKey('price-plus'),
                  label: '+',
                  filled: false,
                  color: Pal.text,
                  onTap: m < Diner.markupMax ? () => _price_(1) : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final w in Wallet.values)
                Tag(
                  key: ValueKey('accepts-${w.name}'),
                  w.accepts(ratio) ? '${w.label} buys' : '${w.label} walks out',
                  color: w.accepts(ratio) ? Pal.green : Pal.red,
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _toggleSpecial() {
    setState(() => diner.toggleSpecial(dish));
    Storage.saveDiner(diner);
  }

  /// Chalking the dish up on the board outside the door.
  Widget _special() {
    final on = diner.isSpecial(dish);
    final other = diner.special != null && diner.special != dish;
    final available = diner.offered.contains(dish);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PxText(
            on
                ? 'On the board outside: ${((1 - Diner.specialMul) * 100).round()}% off, '
                      'asked for more, and a few more people stop.'
                : available
                ? 'Put it on the board outside: '
                      '${((1 - Diner.specialMul) * 100).round()}% off, asked for '
                      'more, and a few more people stop.'
                : 'Only a dish on the menu can be the special.',
            key: const ValueKey('special-help'),
            style: const TextStyle(color: Pal.dim, fontSize: 14),
          ),
          if (other)
            PxText(
              'This replaces ${recipes[diner.special!]!.name}.',
              style: const TextStyle(color: Pal.dim, fontSize: 14),
            ),
          const SizedBox(height: 8),
          GoldButton(
            key: const ValueKey('special'),
            label: on ? 'Take off the board' : 'Make it the special',
            filled: !on,
            color: on ? Pal.text : Pal.gold,
            onTap: on || available ? _toggleSpecial : null,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lvl = diner.progress.recipeLvl(dish);
    final tier = diner.tierOf(dish);
    final up = diner.progress.canLevelRecipe(dish);
    final upCost = diner.progress.recipeUpgradeCost(dish);
    final sells = diner.sellPrice(dish);
    final cost = diner.unitCost(dish);
    final best = diner.roster.employees
        .map((s) => s.masteryLevel(dish))
        .fold(0, (a, b) => a > b ? a : b);
    return ScreenFrame(
      title: r.name,
      subtitle: 'Recipe level $lvl',
      trailing: PxText(
        ':coin: ${diner.coins}',
        style: const TextStyle(color: Pal.text, fontSize: 20),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          Panel(
            child: Row(
              children: [
                DinerSprite('plate_${dish.name}', mult: 2),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PxText(
                        'Price ${sells.toStringAsFixed(1)}',
                        style: const TextStyle(color: Pal.text, fontSize: 17),
                      ),
                      PxText(
                        'Ingredients ${cost.toStringAsFixed(1)}',
                        style: const TextStyle(color: Pal.dim, fontSize: 14),
                      ),
                      PxText(
                        'Profit ${(sells - cost).toStringAsFixed(1)} a portion',
                        key: const ValueKey('dish-profit'),
                        style: const TextStyle(color: Pal.gold, fontSize: 14),
                      ),
                      const PxText(
                        'What a guest pays, less the ingredients. Wages come '
                        'out separately.',
                        style: TextStyle(color: Pal.dim, fontSize: 13),
                      ),
                      if (r.skilled)
                        PxText(
                          best >= 3
                              ? 'Someone has mastered it.'
                              : 'Takes a trained cook.',
                          style: const TextStyle(color: Pal.dim, fontSize: 14),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Eyebrow('Ingredients'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in Tier.values)
                      Choice(
                        key: ValueKey('tier-${dish.name}-${t.name}'),
                        label: t.label,
                        selected: tier == t,
                        onTap: t == Tier.premium && lvl < Diner.premiumLevel
                            ? null
                            : () => _tier(t),
                      ),
                  ],
                ),
                if (lvl < Diner.premiumLevel) ...[
                  const SizedBox(height: 8),
                  const PxText(
                    'Premium needs recipe level 3.',
                    style: TextStyle(color: Pal.dim, fontSize: 14),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Eyebrow('Price'),
          _price(),
          const SizedBox(height: 12),
          const Eyebrow('Recipe'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (up)
                  PxText(
                    'Level ${lvl + 1}: sells for '
                    '${(r.price * (1 + 0.25 * lvl)).round()}, cooks 6% faster.',
                    key: ValueKey('next-level-${dish.name}'),
                    style: const TextStyle(color: Pal.text, fontSize: 14),
                  )
                else
                  const PxText(
                    'The recipe is as good as it gets.',
                    style: TextStyle(color: Pal.green, fontSize: 14),
                  ),
                if (up) ...[
                  const SizedBox(height: 8),
                  GoldButton(
                    key: ValueKey('level-${dish.name}'),
                    label: 'Improve recipe  :coin: $upCost',
                    onTap: diner.coins >= upCost ? _levelUp : null,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Eyebrow('Special'),
          _special(),
        ],
      ),
    );
  }
}
