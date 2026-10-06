import '../game/hex.dart';
import '../game/models.dart';
import 'items.dart';

/// One slot's worth of an item in the bag.
class ItemStack {
  ItemStack(this.id, this.count);

  final String id;
  int count;

  ItemDef get def => itemOf(id);
}

/// Things the hero carries and has learned, across zones.
class WorldState {
  WorldState() {
    addItem('potion', 2);
  }

  static final int maxHp = unitStats[UnitType.hero]!.maxHp;
  static const int maxMana = 4;
  static const int maxUpgrade = 2;
  static const int bagSize = 16;

  int hp = maxHp;
  int mana = maxMana;
  int tokens = 0;

  // ───────────────────────── equipment ─────────────────────────

  /// Two weapon slots: swap between them freely.
  final List<String?> weaponSlots = ['sword', 'bow'];
  int activeWeapon = 0;

  /// Two spell slots, filled from [knownSpells].
  final List<String?> spellSlots = ['fireball', null];
  final Set<String> knownSpells = {'fireball'};

  /// Weapon id to upgrade level (0 to [maxUpgrade]).
  final Map<String, int> upgrades = {};

  // ───────────────────────── the bag ─────────────────────────

  final List<ItemStack?> bag = List.filled(bagSize, null);

  /// Enemies killed since the last rest, as `zone#index`.
  final Set<String> slain = {};

  /// Pickups already taken, as `zone#id`.
  final Set<String> collected = {};

  /// Quest id to stage.
  final Map<String, int> quests = {};

  /// The last campsite rested at. Falling returns you here.
  ({String zone, Hex hex})? camp;

  // ───────────────────────── weapons ─────────────────────────

  String get weaponId => weaponSlots[activeWeapon] ?? 'fists';
  ItemDef get weapon => itemOf(weaponId);

  /// Convenience for tests and quick-swaps: makes [id] the active weapon,
  /// putting it in the active slot if it isn't equipped yet.
  set equipped(String id) {
    final at = weaponSlots.indexOf(id);
    if (at >= 0) {
      activeWeapon = at;
    } else {
      weaponSlots[activeWeapon] = id;
    }
  }

  String get equipped => weaponId;

  int level(String id) => upgrades[id] ?? 0;
  int damageOf(String id) => itemOf(id).damage + level(id);

  /// Tokens needed for the next upgrade of [id] (1, then 2).
  int upgradeCost(String id) => level(id) + 1;

  bool canUpgrade(String id) =>
      itemOf(id).isWeapon &&
      level(id) < maxUpgrade &&
      tokens >= upgradeCost(id);

  bool upgrade(String id) {
    if (!canUpgrade(id)) return false;
    tokens -= upgradeCost(id);
    upgrades[id] = level(id) + 1;
    return true;
  }

  // ───────────────────────── bag operations ─────────────────────────

  /// How many of [id] you hold (bag plus equipped weapons).
  int countOf(String id) {
    var n = weaponSlots.where((w) => w == id).length;
    for (final s in bag) {
      if (s != null && s.id == id) n += s.count;
    }
    return n;
  }

  bool hasItem(String id) => countOf(id) > 0;

  bool get bagFull => bag.every((s) => s != null);

  /// Whether [count] of [id] would fit.
  bool canAdd(String id, [int count = 1]) {
    final def = itemOf(id);
    var room = 0;
    for (final s in bag) {
      if (s == null) {
        room += def.stack;
      } else if (s.id == id) {
        room += def.stack - s.count;
      }
    }
    return room >= count;
  }

  /// Puts [count] of [id] in the bag, stacking where it can. Returns how many
  /// did not fit.
  int addItem(String id, [int count = 1]) {
    final def = itemOf(id);
    var left = count;
    for (final s in bag) {
      if (left == 0) break;
      if (s != null && s.id == id && s.count < def.stack) {
        final put = (def.stack - s.count).clamp(0, left);
        s.count += put;
        left -= put;
      }
    }
    for (var i = 0; i < bag.length && left > 0; i++) {
      if (bag[i] == null) {
        final put = left.clamp(0, def.stack);
        bag[i] = ItemStack(id, put);
        left -= put;
      }
    }
    return left;
  }

  /// Takes [count] of [id] out of the bag. False (and nothing taken) if the
  /// bag doesn't hold that many.
  bool removeItem(String id, [int count = 1]) {
    var have = 0;
    for (final s in bag) {
      if (s != null && s.id == id) have += s.count;
    }
    if (have < count) return false;
    var left = count;
    for (var i = bag.length - 1; i >= 0 && left > 0; i--) {
      final s = bag[i];
      if (s == null || s.id != id) continue;
      final take = left.clamp(0, s.count);
      s.count -= take;
      left -= take;
      if (s.count == 0) bag[i] = null;
    }
    return true;
  }

  /// Bag slot [index] into weapon slot [slot]; whatever was there goes to
  /// that bag slot.
  bool equipFromBag(int index, int slot) {
    final s = bag[index];
    if (s == null || !s.def.isWeapon) return false;
    final old = weaponSlots[slot];
    weaponSlots[slot] = s.id;
    bag[index] = old == null ? null : ItemStack(old, 1);
    return true;
  }

  /// Weapon slot [slot] back into the bag. At least one weapon stays equipped.
  bool unequip(int slot) {
    final id = weaponSlots[slot];
    if (id == null) return false;
    if (weaponSlots.where((w) => w != null).length <= 1) return false;
    if (!canAdd(id)) return false;
    addItem(id);
    weaponSlots[slot] = null;
    if (activeWeapon == slot) {
      activeWeapon = weaponSlots.indexWhere((w) => w != null);
    }
    return true;
  }

  /// Throws a bag slot away. Quest items can't be dropped.
  bool drop(int index) {
    final s = bag[index];
    if (s == null || s.def.isQuest) return false;
    bag[index] = null;
    return true;
  }

  // ───────────────────────── spells ─────────────────────────

  void learn(String spell) {
    knownSpells.add(spell);
    if (!spellSlots.contains(spell)) {
      final empty = spellSlots.indexOf(null);
      if (empty >= 0) spellSlots[empty] = spell;
    }
  }

  void slotSpell(int slot, String? spell) {
    if (spell != null && !knownSpells.contains(spell)) return;
    // A spell lives in one slot at a time.
    for (var i = 0; i < spellSlots.length; i++) {
      if (spellSlots[i] == spell) spellSlots[i] = null;
    }
    spellSlots[slot] = spell;
  }
}
