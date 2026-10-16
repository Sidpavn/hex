import 'package:flutter/material.dart';

import '../data/storage.dart';
import '../ui/widgets.dart';
import 'diner.dart';
import 'recipes.dart';

/// Where coins become a better kitchen and a bigger team. Recipes are
/// improved on the menu, next to what they sell for.
class UpgradeScreen extends StatefulWidget {
  const UpgradeScreen({super.key, required this.diner});

  final Diner diner;

  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen> {
  Diner get diner => widget.diner;
  Progress get progress => diner.progress;

  void _buy(Upgrade u, int cost) {
    if (diner.coins < cost) return;
    setState(() {
      diner.coins -= cost;
      progress.upgrades[u] = progress.upgradeLvl(u) + 1;
    });
    Storage.saveDiner(diner);
  }

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      title: 'Upgrades',
      subtitle:
          'Level ${progress.level}, ${progress.xp} of '
          '${progress.xpToNext} xp',
      trailing: PxText(
        ':coin: ${diner.coins}',
        style: const TextStyle(color: Pal.text, fontSize: 20),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          for (final u in Upgrade.values) ...[
            _upgrade(u),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _upgrade(Upgrade u) {
    final def = upgradeDefs[u]!;
    final lvl = progress.upgradeLvl(u);
    final cost = progress.upgradeCost(u);
    return Panel(
      key: ValueKey('upgrade-${u.name}'),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PxText(
                  def.name,
                  style: const TextStyle(color: Pal.text, fontSize: 17),
                ),
                PxText(
                  def.info,
                  style: const TextStyle(color: Pal.dim, fontSize: 14),
                ),
                const SizedBox(height: 4),
                PxText(
                  cost == null ? 'Fully upgraded' : 'Level $lvl of ${def.max}',
                  style: TextStyle(
                    color: cost == null ? Pal.green : Pal.dim,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          if (cost != null) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 96,
              child: GoldButton(
                key: ValueKey('buy-${u.name}'),
                label: ':coin: $cost',
                filled: false,
                color: Pal.text,
                onTap: diner.coins >= cost ? () => _buy(u, cost) : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
