import 'package:flutter/material.dart';

import '../game/models.dart';
import '../world/items.dart';
import '../world/world_state.dart';
import 'widgets.dart';
import 'zone_overlays.dart' show ModalFrame;

/// One square slot: an icon on a pixel panel, with an optional badge. Used in
/// the quick bar, the equipment row and the bag.
class ItemSlot extends StatelessWidget {
  const ItemSlot({
    super.key,
    required this.onTap,
    this.icon,
    this.badge,
    this.corner,
    this.selected = false,
    this.active = false,
    this.dim = false,
    this.accent,
    this.flag = false,
    this.mult = 2,
  });

  final VoidCallback? onTap;

  /// Pixel icon name, or null for an empty slot.
  final String? icon;

  /// Bottom-right text (a count, a damage value, a mana cost).
  final String? badge;

  /// Top-left text (an upgrade level).
  final String? corner;
  final bool selected;

  /// The weapon currently in hand.
  final bool active;
  final bool dim;

  /// Border colour for special items.
  final Color? accent;

  /// Marks the slot as the one a quest wants you to use.
  final bool flag;
  final int mult;

  @override
  Widget build(BuildContext context) {
    final u = PixelUi.unit(context);
    final size = (12 * mult + 4) * u;
    final border = selected || flag
        ? Pal.goldLight
        : active
        ? Pal.gold
        : (accent ?? Pal.ink);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Opacity(
          opacity: dim ? 0.45 : 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PixelBox(
                color: selected || active ? Pal.panelHi : Pal.panelLo,
                border: border,
                shadow: false,
                padding: EdgeInsets.zero,
                child: Center(
                  child: icon == null
                      ? const SizedBox.shrink()
                      : PxIcon(icon!, mult: mult),
                ),
              ),
              if (flag)
                Positioned(
                  right: 2 * u,
                  top: 2 * u,
                  child: const PxIcon('star_s'),
                ),
              if (corner != null)
                Positioned(
                  left: 3 * u,
                  top: 1 * u,
                  child: Text(
                    corner!,
                    style: const TextStyle(
                      color: Pal.goldLight,
                      fontSize: 11,
                      height: 1,
                    ),
                  ),
                ),
              if (badge != null)
                Positioned(
                  right: 3 * u,
                  bottom: 1 * u,
                  child: Text(
                    badge!,
                    style: const TextStyle(
                      color: Pal.text,
                      fontSize: 13,
                      height: 1,
                      shadows: [Shadow(color: Pal.ink, offset: Offset(1, 1))],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Border colour that shows how upgraded a weapon is.
Color? tierColor(int level) => switch (level) {
  1 => Pal.blue,
  >= 2 => Pal.gold,
  _ => null,
};

enum QuickKind { weapon, spell, item }

/// One slot on the quick bar. [slot] is the weapon or spell slot, [id] the
/// spell or item.
class QuickEntry {
  const QuickEntry(this.kind, this.id, [this.slot = 0]);

  final QuickKind kind;
  final String id;
  final int slot;

  String get key => '${kind.name}:$id:$slot';
}

/// Everything on the bar, weapons then spells then potions. A group only
/// appears once you have something for it.
List<QuickEntry> quickEntries(WorldState world) => [
  for (var i = 0; i < world.weaponSlots.length; i++)
    if (world.weaponSlots[i] case final id?)
      QuickEntry(QuickKind.weapon, id, i),
  for (var i = 0; i < world.spellSlots.length; i++)
    if (spellDefs[world.spellSlots[i]] case final def?)
      QuickEntry(QuickKind.spell, def.id, i),
  for (final id in const ['potion', 'ether'])
    if (world.countOf(id) > 0) QuickEntry(QuickKind.item, id),
];

/// The selected entry: the one named by [key], else the weapon in hand.
QuickEntry? selectedQuick(
  List<QuickEntry> entries,
  String? key,
  WorldState world,
) {
  if (entries.isEmpty) return null;
  for (final e in entries) {
    if (e.key == key) return e;
  }
  for (final e in entries) {
    if (e.kind == QuickKind.weapon && e.slot == world.activeWeapon) return e;
  }
  return entries.first;
}

/// The entry [dir] (+1 or -1) away from [from]. With [group] it jumps to the
/// first entry of the next or previous group instead. Stays put at the ends.
QuickEntry stepQuick(
  List<QuickEntry> entries,
  QuickEntry from,
  int dir, {
  bool group = false,
}) {
  final at = entries.indexWhere((e) => e.key == from.key);
  if (at < 0) return from;
  if (!group) return entries[(at + dir).clamp(0, entries.length - 1)];
  var i = at + dir;
  while (i >= 0 && i < entries.length && entries[i].kind == from.kind) {
    i += dir;
  }
  if (i < 0 || i >= entries.length) return from;
  final kind = entries[i].kind;
  while (i - dir >= 0 &&
      i - dir < entries.length &&
      entries[i - dir].kind == kind) {
    i -= dir;
  }
  return entries[i];
}

/// The strip of big slots under the world: weapons, then spells, then
/// potions, with a thin divider between groups. Swiping the screen moves the
/// selection one slot (a fling jumps a group); tapping the selected slot
/// uses it and tapping any other slot selects it.
class QuickBar extends StatelessWidget {
  const QuickBar({
    super.key,
    required this.world,
    required this.selected,
    required this.targeting,
    required this.onSelect,
    required this.onUse,
    required this.canCast,
    this.pointAt,
  });

  final WorldState world;

  /// Key of the selected [QuickEntry]; falls back to the weapon in hand.
  final String? selected;
  final bool targeting;
  final void Function(QuickEntry e) onSelect;
  final void Function(QuickEntry e) onUse;

  /// Whether the spell with the given id can be cast right now.
  final bool Function(String spell) canCast;

  /// Item or spell id a quest wants you to use, shown with a star.
  final String? pointAt;

  @override
  Widget build(BuildContext context) {
    final u = PixelUi.unit(context);
    final entries = quickEntries(world);
    final sel = selectedQuick(entries, selected, world);
    if (sel == null) return const SizedBox.shrink();
    final side = (12 * _mult + 4) * u;
    final rise = 2 * u;
    return SizedBox(
      width: double.infinity,
      height: side + rise,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0)
              entries[i].kind != entries[i - 1].kind
                  ? Container(
                      width: u,
                      height: side,
                      margin: EdgeInsets.symmetric(horizontal: 3 * u),
                      color: Pal.dimmer,
                    )
                  : SizedBox(width: 2 * u),
            _slot(entries[i], entries[i].key == sel.key, rise),
          ],
        ],
      ),
    );
  }

  static const _mult = 2;

  Widget _slot(QuickEntry e, bool isSel, double rise) {
    const mult = _mult;
    final slot = switch (e.kind) {
      QuickKind.weapon => ItemSlot(
        icon: itemOf(e.id).icon,
        badge: '${world.damageOf(e.id)}',
        corner: world.level(e.id) > 0 ? '+${world.level(e.id)}' : null,
        mult: mult,
        selected: isSel,
        active: world.activeWeapon == e.slot && !targeting,
        flag: pointAt == e.id && world.activeWeapon != e.slot,
        accent: tierColor(world.level(e.id)),
        onTap: () => isSel ? onUse(e) : onSelect(e),
      ),
      QuickKind.spell => ItemSlot(
        icon: spellDefs[e.id]!.icon,
        badge: '${spellDefs[e.id]!.cost}',
        mult: mult,
        selected: isSel,
        active: e.id == 'fireball' && targeting,
        dim: !canCast(e.id),
        flag: pointAt == e.id,
        onTap: () => isSel ? onUse(e) : onSelect(e),
      ),
      QuickKind.item => ItemSlot(
        icon: itemOf(e.id).icon,
        badge: '${world.countOf(e.id)}',
        mult: mult,
        selected: isSel,
        flag: pointAt == e.id,
        onTap: () => isSel ? onUse(e) : onSelect(e),
      ),
    };
    return Padding(
      padding: EdgeInsets.only(bottom: isSel ? rise : 0),
      child: slot,
    );
  }
}

/// A ruler showing which distances a weapon can hit: you, then 1 to 5 hexes.
class ReachRuler extends StatelessWidget {
  const ReachRuler({super.key, required this.min, required this.max});

  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    final u = PixelUi.unit(context);
    Widget cell(Widget child, Color color, Color border) => Container(
      width: 11 * u,
      height: 11 * u,
      margin: EdgeInsets.only(right: u),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: border, width: u),
      ),
      child: Center(child: child),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        cell(const PxIcon('crown'), Pal.panelHi, Pal.ink),
        for (var d = 1; d <= 5; d++)
          cell(
            Text(
              '$d',
              style: TextStyle(
                color: d >= min && d <= max ? Pal.ink : Pal.dimmer,
                fontSize: 12,
                height: 1,
              ),
            ),
            d >= min && d <= max ? Pal.gold : Pal.panelLo,
            d >= min && d <= max ? Pal.goldDark : Pal.ink,
          ),
      ],
    );
  }
}

enum _SelKind { bag, weapon, spell }

class _Sel {
  const _Sel(this.kind, this.index);

  final _SelKind kind;
  final int index;

  @override
  bool operator ==(Object other) =>
      other is _Sel && other.kind == kind && other.index == index;

  @override
  int get hashCode => Object.hash(kind, index);
}

/// The pack: what you wear and carry, with a detail panel for the selection.
class InventoryOverlay extends StatefulWidget {
  const InventoryOverlay({
    super.key,
    required this.world,
    required this.atCamp,
    required this.onChanged,
    required this.onClose,
    required this.onUse,
  });

  final WorldState world;

  /// Upgrades are only available while resting at a campfire.
  final bool atCamp;
  final VoidCallback onChanged;
  final VoidCallback onClose;

  /// Drink a potion through the game (so it takes a turn).
  final bool Function(String item) onUse;

  @override
  State<InventoryOverlay> createState() => _InventoryOverlayState();
}

class _InventoryOverlayState extends State<InventoryOverlay> {
  _Sel? _sel;
  String? _note;

  WorldState get w => widget.world;

  void _changed([String? note]) {
    setState(() => _note = note);
    widget.onChanged();
  }

  String? get _selectedItemId => switch (_sel) {
    null => null,
    _Sel(kind: _SelKind.bag, :final index) => w.bag[index]?.id,
    _Sel(kind: _SelKind.weapon, :final index) => w.weaponSlots[index],
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final u = PixelUi.unit(context);
    return ModalFrame(
      onDismiss: widget.onClose,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: PixelBox(
            border: Pal.gold,
            padding: const EdgeInsets.all(10),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(),
                  const SizedBox(height: 8),
                  _heroStrip(),
                  const SizedBox(height: 10),
                  _label('Equipped'),
                  _equipment(),
                  const SizedBox(height: 10),
                  _label('Bag'),
                  _bag(u),
                  const SizedBox(height: 10),
                  _detail(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(t, style: const TextStyle(color: Pal.gold, fontSize: 15)),
  );

  Widget _header() => Row(
    children: [
      const PxIcon('pack', mult: 2),
      const SizedBox(width: 8),
      const Expanded(
        child: Text(
          'Pack',
          style: TextStyle(color: Pal.gold, fontSize: 26, height: 1),
        ),
      ),
      PxText(
        ':token: ${w.tokens}',
        style: const TextStyle(color: Pal.goldLight, fontSize: 17),
      ),
      const SizedBox(width: 10),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onClose,
        child: const Padding(
          padding: EdgeInsets.all(6),
          child: PxIcon('close'),
        ),
      ),
    ],
  );

  Widget _heroStrip() {
    final wp = w.weapon;
    return PixelBox(
      color: Pal.panelLo,
      shadow: false,
      padding: const EdgeInsets.all(6),
      child: Row(
        children: [
          const UnitPortrait(UnitType.hero, mult: 2),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const PxIcon('heart'),
                    const SizedBox(width: 4),
                    Expanded(
                      child: PxBar(
                        value: w.hp / WorldState.maxHp,
                        color: Pal.red,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${w.hp}/${WorldState.maxHp}',
                      style: const TextStyle(color: Pal.text, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const PxIcon('bolt'),
                    const SizedBox(width: 4),
                    Expanded(
                      child: PxBar(
                        value: w.mana / WorldState.maxMana,
                        color: const Color(0xFF78E6F0),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${w.mana}/${WorldState.maxMana}',
                      style: const TextStyle(color: Pal.text, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'In hand: ${wp.name}  dmg ${w.damageOf(w.weaponId)}',
                  style: const TextStyle(color: Pal.dim, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _equipment() {
    final slots = <Widget>[];
    for (var i = 0; i < w.weaponSlots.length; i++) {
      final id = w.weaponSlots[i];
      slots.add(
        _slotWithLabel(
          i == 0 ? 'Weapon A' : 'Weapon B',
          ItemSlot(
            icon: id == null ? null : itemOf(id).icon,
            badge: id == null ? null : '${w.damageOf(id)}',
            corner: id != null && w.level(id) > 0 ? '+${w.level(id)}' : null,
            active: id != null && w.activeWeapon == i,
            selected: _sel == _Sel(_SelKind.weapon, i),
            accent: id == null ? null : tierColor(w.level(id)),
            onTap: () => setState(() {
              _sel = _Sel(_SelKind.weapon, i);
              _note = null;
            }),
          ),
        ),
      );
    }
    for (var i = 0; i < w.spellSlots.length; i++) {
      final id = w.spellSlots[i];
      final def = id == null ? null : spellDefs[id];
      slots.add(
        _slotWithLabel(
          'Spell ${i + 1}',
          ItemSlot(
            icon: def?.icon,
            badge: def == null ? null : '${def.cost}',
            selected: _sel == _Sel(_SelKind.spell, i),
            onTap: () => setState(() {
              _sel = _Sel(_SelKind.spell, i);
              _note = null;
            }),
          ),
        ),
      );
    }
    return Wrap(spacing: 8, runSpacing: 6, children: slots);
  }

  Widget _slotWithLabel(String label, Widget slot) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      slot,
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(color: Pal.dim, fontSize: 11)),
    ],
  );

  Widget _bag(double u) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < WorldState.bagSize; i++)
          ItemSlot(
            icon: w.bag[i]?.def.icon,
            badge: w.bag[i] != null && w.bag[i]!.def.stack > 1
                ? '${w.bag[i]!.count}'
                : null,
            corner:
                w.bag[i] != null &&
                    w.bag[i]!.def.isWeapon &&
                    w.level(w.bag[i]!.id) > 0
                ? '+${w.level(w.bag[i]!.id)}'
                : null,
            accent: w.bag[i] == null
                ? null
                : (w.bag[i]!.def.isKept
                      ? Pal.purple
                      : tierColor(w.level(w.bag[i]!.id))),
            selected: _sel == _Sel(_SelKind.bag, i),
            onTap: () => setState(() {
              _sel = _Sel(_SelKind.bag, i);
              _note = null;
            }),
          ),
      ],
    );
  }

  // ───────────────────────── detail ─────────────────────────

  Widget _detail() {
    final sel = _sel;
    Widget body;
    if (sel == null) {
      body = const Text(
        'Tap an item to see what it does.',
        style: TextStyle(color: Pal.dim, fontSize: 14),
      );
    } else if (sel.kind == _SelKind.spell) {
      body = _spellDetail(sel.index);
    } else {
      final id = _selectedItemId;
      body = id == null ? _emptySlot(sel) : _itemDetail(id, sel);
    }
    return PixelBox(
      color: Pal.panelLo,
      shadow: false,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          body,
          if (_note != null) ...[
            const SizedBox(height: 6),
            Text(
              _note!,
              style: const TextStyle(color: Pal.goldLight, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptySlot(_Sel sel) => Text(
    sel.kind == _SelKind.weapon
        ? 'Empty weapon slot. Pick a weapon in your bag and equip it here.'
        : 'Empty slot.',
    style: const TextStyle(color: Pal.dim, fontSize: 14),
  );

  Widget _itemDetail(String id, _Sel sel) {
    final def = itemOf(id);
    final level = w.level(id);
    final inBag = sel.kind == _SelKind.bag;
    final children = <Widget>[
      Row(
        children: [
          PxIcon(def.icon, mult: 2),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  def.name + (level > 0 ? '  +$level' : ''),
                  style: TextStyle(
                    color: tierColor(level) ?? Pal.text,
                    fontSize: 19,
                    height: 1,
                  ),
                ),
                Text(switch (def.kind) {
                  ItemKind.weapon => 'Weapon',
                  ItemKind.consumable => 'Consumable',
                  ItemKind.quest => 'Quest item',
                  ItemKind.tool => 'Tool',
                  ItemKind.material => 'Material',
                  ItemKind.lore => 'Scroll',
                }, style: const TextStyle(color: Pal.dim, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(def.desc, style: const TextStyle(color: Pal.text, fontSize: 14)),
    ];

    if (def.isWeapon) {
      children
        ..add(const SizedBox(height: 6))
        ..add(
          Row(
            children: [
              Text(
                'Damage ${w.damageOf(id)}',
                style: const TextStyle(color: Pal.gold, fontSize: 15),
              ),
              if (def.sneak > 2)
                Text(
                  '   Sneak x${def.sneak}',
                  style: const TextStyle(color: Pal.goldLight, fontSize: 13),
                ),
            ],
          ),
        )
        ..add(const SizedBox(height: 4))
        ..add(
          Row(
            children: [
              ReachRuler(min: def.minRange, max: def.maxRange),
              const SizedBox(width: 6),
              Text(
                def.minRange == def.maxRange
                    ? 'Reach ${def.maxRange}'
                    : 'Reach ${def.minRange}-${def.maxRange}',
                style: const TextStyle(color: Pal.dim, fontSize: 12),
              ),
            ],
          ),
        )
        ..add(const SizedBox(height: 6))
        ..add(_upgradeRow(id, def));
    }

    children.add(const SizedBox(height: 8));
    children.add(
      Wrap(spacing: 8, runSpacing: 6, children: _actions(id, def, sel, inBag)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _upgradeRow(String id, ItemDef def) {
    final level = w.level(id);
    final maxed = level >= WorldState.maxUpgrade;
    return Row(
      children: [
        for (var i = 0; i < WorldState.maxUpgrade; i++)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: PxIcon(
              'star_s',
              tint: i < level ? null : const Color(0xCC1A1C2C),
            ),
          ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            maxed
                ? 'Fully upgraded'
                : widget.atCamp
                ? 'Next: dmg ${w.damageOf(id) + 1}'
                : 'Upgrade at a campfire',
            style: const TextStyle(color: Pal.dim, fontSize: 12),
          ),
        ),
        if (widget.atCamp && !maxed)
          SizedBox(
            width: 92,
            child: GoldButton(
              label: ':token: ${w.upgradeCost(id)}',
              filled: w.canUpgrade(id),
              onTap: w.canUpgrade(id)
                  ? () {
                      w.upgrade(id);
                      _changed('${def.name} upgraded.');
                    }
                  : null,
            ),
          ),
      ],
    );
  }

  List<Widget> _actions(String id, ItemDef def, _Sel sel, bool inBag) {
    Widget btn(String label, VoidCallback? tap, {bool filled = false}) =>
        SizedBox(
          width: 120,
          child: GoldButton(label: label, filled: filled, onTap: tap),
        );
    final out = <Widget>[];
    if (def.isWeapon && inBag) {
      for (var slot = 0; slot < w.weaponSlots.length; slot++) {
        out.add(
          btn('Equip ${slot == 0 ? 'A' : 'B'}', () {
            w.equipFromBag(sel.index, slot);
            _sel = _Sel(_SelKind.weapon, slot);
            _changed('${def.name} equipped.');
          }, filled: slot == 0),
        );
      }
    }
    if (def.isWeapon && !inBag) {
      out.add(
        btn('Unequip', () {
          final ok = w.unequip(sel.index);
          _changed(
            ok
                ? '${def.name} put in the bag.'
                : 'You need one weapon in hand, and room in the bag.',
          );
        }),
      );
    }
    if (def.isConsumable) {
      out.add(
        btn('Use', () {
          final ok = widget.onUse(id);
          _changed(ok ? '${def.name} used.' : 'That would not help right now.');
        }, filled: true),
      );
    }
    if (inBag && !def.isKept) {
      out.add(
        btn('Drop', () {
          w.drop(sel.index);
          _sel = null;
          _changed('Dropped ${def.name}.');
        }),
      );
    }
    if (def.isKept) {
      out.add(
        Text(
          def.isTool
              ? 'Tools stay with you.'
              : 'Quest items stay with you until you hand them in.',
          style: TextStyle(color: Pal.dim, fontSize: 12),
        ),
      );
    }
    return out;
  }

  Widget _spellDetail(int slot) {
    final id = w.spellSlots[slot];
    final def = id == null ? null : spellDefs[id];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (def != null) ...[
          Row(
            children: [
              PxIcon(def.icon, mult: 2),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      def.name,
                      style: const TextStyle(
                        color: Pal.text,
                        fontSize: 19,
                        height: 1,
                      ),
                    ),
                    PxText(
                      ':bolt: ${def.cost} mana'
                      '${def.needsTarget ? '   Range ${def.range}' : '   Self'}',
                      style: const TextStyle(color: Pal.dim, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(def.desc, style: const TextStyle(color: Pal.text, fontSize: 14)),
        ] else
          const Text(
            'Empty spell slot.',
            style: TextStyle(color: Pal.dim, fontSize: 14),
          ),
        const SizedBox(height: 8),
        const Text(
          'Put a spell in this slot:',
          style: TextStyle(color: Pal.gold, fontSize: 14),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final s in w.knownSpells)
              SizedBox(
                width: 150,
                child: GoldButton(
                  label: spellDefs[s]?.name ?? s,
                  filled: w.spellSlots[slot] == s,
                  onTap: () {
                    w.slotSpell(slot, s);
                    _changed('${spellDefs[s]?.name} ready.');
                  },
                ),
              ),
            SizedBox(
              width: 150,
              child: GoldButton(
                label: 'Empty',
                filled: false,
                onTap: () {
                  w.slotSpell(slot, null);
                  _changed(null);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
