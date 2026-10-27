import 'package:flutter/material.dart';

import '../ui/widgets.dart';
import 'catalog.dart';
import 'diner.dart';
import 'diner_painter.dart' show spriteName;
import 'diner_sprite.dart';

/// The build popup: everything that can be bought, in groups. Tapping one
/// closes it with that kind chosen.
class ShelfPopup extends StatefulWidget {
  const ShelfPopup({
    super.key,
    required this.diner,
    required this.chosen,
    this.start = Category.seating,
    this.onTab,
  });

  final Diner diner;

  /// What is being placed now, if anything.
  final Kind? chosen;

  /// The group showing first.
  final Category start;

  /// Told when another group is opened, so the next popup opens on it.
  final void Function(Category)? onTab;

  @override
  State<ShelfPopup> createState() => _ShelfPopupState();
}

class _ShelfPopupState extends State<ShelfPopup> {
  late Category _tab = widget.start;

  @override
  Widget build(BuildContext context) {
    final d = widget.diner;
    final size = MediaQuery.of(context).size;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: size.height * 0.8),
        child: PixelBox(
          key: const ValueKey('shelf-popup'),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PxText(
                'Build',
                style: const TextStyle(color: Pal.gold, fontSize: 22),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in Category.values)
                    Choice(
                      key: ValueKey('shelf-tab-${c.name}'),
                      label: c.label,
                      selected: _tab == c,
                      onTap: () {
                        widget.onTab?.call(c);
                        setState(() => _tab = c);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: LayoutBuilder(
                  builder: (_, box) {
                    // Three to a row.
                    final w = ((box.maxWidth - 16) / 3).floorToDouble();
                    return SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final def in defsIn(_tab))
                            SizedBox(
                              width: w,
                              child: FixtureTile(
                                key: ValueKey('fixture-${def.kind.name}'),
                                def: def,
                                selected: widget.chosen == def.kind,
                                affordable: d.coins >= def.cost,
                                locked: def.unlock > d.progress.level,
                                onTap: () => Navigator.pop(context, def.kind),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              GoldButton(
                key: const ValueKey('shelf-close'),
                label: 'Close',
                filled: false,
                color: Pal.dim,
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One thing to build: its picture, its name and its price.
class FixtureTile extends StatelessWidget {
  const FixtureTile({
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
      // A tall-enough floor that a one-word and a two-word name land on the
      // same height in practice, so the tiles read as a uniform grid: it is
      // a minimum, not a cap, so a longer name only ever grows it further
      // rather than being cut off.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 108),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              height: 40,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: DinerSprite(spriteName(def.kind, Dir.sw)),
              ),
            ),
            const SizedBox(height: 4),
            PxText(
              def.name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Pal.text,
                fontSize: 13,
                height: 1.05,
              ),
            ),
            PxText(
              locked ? ':lock: Lv ${def.unlock}' : ':coin: ${def.cost}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: affordable && !locked ? Pal.text : Pal.dimmer,
                fontSize: 13,
                height: 1.05,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
