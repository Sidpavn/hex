/// What kind of thing an item is, which decides where it can go.
enum ItemKind { weapon, consumable, quest, tool, material, lore }

/// A kind of item. Weapons are fixed and hand-made (no random stats); you make
/// them stronger by spending tokens at a campfire.
class ItemDef {
  const ItemDef(
    this.id,
    this.name,
    this.kind,
    this.icon,
    this.desc, {
    this.damage = 0,
    this.minRange = 1,
    this.maxRange = 1,
    this.sneak = 2,
    this.stack = 1,
    this.heal = 0,
    this.mana = 0,
  });

  final String id;
  final String name;
  final ItemKind kind;

  /// Pixel icon name.
  final String icon;
  final String desc;

  // Weapons
  final int damage;
  final int minRange;
  final int maxRange;

  /// Damage multiplier against an enemy that hasn't noticed you.
  final int sneak;

  /// How many fit in one bag slot.
  final int stack;

  // Consumables
  final int heal;
  final int mana;

  bool get ranged => maxRange > 1;
  bool get isWeapon => kind == ItemKind.weapon;
  bool get isConsumable => kind == ItemKind.consumable;
  bool get isQuest => kind == ItemKind.quest;
  bool get isTool => kind == ItemKind.tool;

  /// A scroll: read on pickup and kept in the journal, never in the bag.
  bool get isLore => kind == ItemKind.lore;

  /// Quest items and tools stay with you: they can't be dropped.
  bool get isKept => isQuest || isTool;
}

/// A spell the hero can learn and slot.
class SpellDef {
  const SpellDef(
    this.id,
    this.name,
    this.icon,
    this.cost,
    this.range,
    this.desc,
  );

  final String id;
  final String name;
  final String icon;
  final int cost;

  /// 0 means it targets the caster (no aiming).
  final int range;
  final String desc;

  bool get needsTarget => range > 0;
}

/// Every item in the game, by id.
const Map<String, ItemDef> itemDefs = {
  'fists': ItemDef(
    'fists',
    'Bare Hands',
    ItemKind.weapon,
    'swords',
    'Better than nothing.',
    damage: 1,
  ),
  'sword': ItemDef(
    'sword',
    'Iron Sword',
    ItemKind.weapon,
    'swords',
    'A sturdy blade. Hits hard, but only up close.',
    damage: 3,
  ),
  'bow': ItemDef(
    'bow',
    'Short Bow',
    ItemKind.weapon,
    'bow',
    'Shoots 2 to 4 hexes. Needs a clear line of sight.',
    damage: 2,
    minRange: 2,
    maxRange: 4,
  ),
  'spear': ItemDef(
    'spear',
    "Hunter's Spear",
    ItemKind.weapon,
    'spear',
    'Reaches 2 hexes, so you can strike before they close in.',
    damage: 3,
    maxRange: 2,
  ),
  'axe': ItemDef(
    'axe',
    'War Axe',
    ItemKind.weapon,
    'axe',
    'Slow and brutal. The hardest hitter you can carry.',
    damage: 4,
  ),
  'longbow': ItemDef(
    'longbow',
    'Long Bow',
    ItemKind.weapon,
    'bow',
    'Shoots 3 to 5 hexes. Strong, but useless up close.',
    damage: 3,
    minRange: 3,
    maxRange: 5,
  ),
  'dagger': ItemDef(
    'dagger',
    'Night Dagger',
    ItemKind.weapon,
    'dagger',
    'Weak in a fair fight, but triples damage against unaware foes.',
    damage: 2,
    sneak: 3,
  ),
  'potion': ItemDef(
    'potion',
    'Healing Potion',
    ItemKind.consumable,
    'potion',
    'Restores 4 HP.',
    stack: 5,
    heal: 4,
  ),
  'ether': ItemDef(
    'ether',
    'Mana Potion',
    ItemKind.consumable,
    'ether',
    'Restores 2 mana.',
    stack: 5,
    mana: 2,
  ),
  'wood': ItemDef(
    'wood',
    'Wood',
    ItemKind.material,
    'wood',
    'Cut from trees. Thirty mend a broken bridge.',
    stack: 10,
  ),
  'hatchet': ItemDef(
    'hatchet',
    'Hatchet',
    ItemKind.tool,
    'hatchet',
    'Stand next to a tree and chop it for wood.',
  ),
  'pickaxe': ItemDef(
    'pickaxe',
    'Pickaxe',
    ItemKind.tool,
    'pickaxe',
    'Breaks rockfalls that block the way.',
  ),
  'lantern': ItemDef(
    'lantern',
    "Mara's Lantern",
    ItemKind.quest,
    'lantern',
    'Mara would like this back.',
  ),
  'scroll_orders': ItemDef(
    'scroll_orders',
    'Scroll',
    ItemKind.lore,
    'scroll',
    'Read it in the journal.',
  ),
  'scroll_survey': ItemDef(
    'scroll_survey',
    'Scroll',
    ItemKind.lore,
    'scroll',
    'Read it in the journal.',
  ),
  'scroll_woodcutter': ItemDef(
    'scroll_woodcutter',
    'Scroll',
    ItemKind.lore,
    'scroll',
    'Read it in the journal.',
  ),
};

const Map<String, SpellDef> spellDefs = {
  'fireball': SpellDef(
    'fireball',
    'Fireball',
    'fire',
    2,
    4,
    'Blast a hex for 2 and its ring for 1. Sets forests alight.',
  ),
  'mend': SpellDef('mend', 'Mend', 'heal', 2, 0, 'Restore 3 HP to yourself.'),
  'shield': SpellDef(
    'shield',
    'Shield',
    'shield',
    2,
    0,
    'Absorb the next 3 damage, for up to 5 turns.',
  ),
};

ItemDef itemOf(String id) => itemDefs[id] ?? itemDefs['fists']!;
