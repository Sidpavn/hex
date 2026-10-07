import '../game/hex.dart';
import '../game/models.dart';
import 'items.dart';

/// Keys for [WorldState.counts]. Anything the player does that a quest might
/// care about is counted under one of these.
abstract final class Counts {
  static String hit(UnitType unit, {required bool ranged}) =>
      'hit:${unit.name}:${ranged ? 'ranged' : 'melee'}';
  static String kill(UnitType unit) => 'kill:${unit.name}';
  static String cast(String spell) => 'cast:$spell';

  static const postMelee = 'hit:post:melee';
  static const postRanged = 'hit:post:ranged';
  static const castMend = 'cast:mend';
}

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

  /// A new Explore game: bare hands and no spells. Everything is earned in
  /// the training ground.
  WorldState.newGame() {
    weaponSlots.fillRange(0, weaponSlots.length, null);
    spellSlots.fillRange(0, spellSlots.length, null);
    knownSpells.clear();
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

  /// Things done so far, by [Counts] key. Quests read these.
  final Map<String, int> counts = {};

  int count(String key) => counts[key] ?? 0;
  void bump(String key) => counts[key] = count(key) + 1;

  /// The last campsite rested at. Falling returns you here.
  ({String zone, Hex hex})? camp;

  /// Where the game was last saved, so Continue picks up there.
  ({String zone, Hex hex})? resume;

  // ───────────────────────── saving ─────────────────────────

  Map<String, dynamic> toJson() {
    Map<String, dynamic> where(({String zone, Hex hex}) w) => {
      'zone': w.zone,
      'q': w.hex.q,
      'r': w.hex.r,
    };
    return {
      'hp': hp,
      'mana': mana,
      'tokens': tokens,
      'weapons': weaponSlots,
      'activeWeapon': activeWeapon,
      'spells': spellSlots,
      'known': knownSpells.toList(),
      'upgrades': upgrades,
      'bag': [
        for (final s in bag) s == null ? null : {'id': s.id, 'n': s.count},
      ],
      'slain': slain.toList(),
      'collected': collected.toList(),
      'quests': quests,
      'counts': counts,
      if (camp != null) 'camp': where(camp!),
      if (resume != null) 'resume': where(resume!),
    };
  }

  /// Rebuilds a world from [toJson]. Throws if the data is malformed; callers
  /// treat that as "no save".
  factory WorldState.fromJson(Map<String, dynamic> j) {
    ({String zone, Hex hex}) where(dynamic m) =>
        (zone: m['zone'] as String, hex: Hex(m['q'] as int, m['r'] as int));
    Map<String, int> ints(dynamic m) => {
      for (final e in (m as Map).entries) e.key as String: e.value as int,
    };
    List<String?> slots(dynamic l, int n) => [
      for (var i = 0; i < n; i++)
        i < (l as List).length ? l[i] as String? : null,
    ];

    final w = WorldState.newGame();
    w.hp = j['hp'] as int;
    w.mana = j['mana'] as int;
    w.tokens = j['tokens'] as int;
    w.weaponSlots.setAll(0, slots(j['weapons'], w.weaponSlots.length));
    w.activeWeapon = (j['activeWeapon'] as int).clamp(
      0,
      w.weaponSlots.length - 1,
    );
    w.spellSlots.setAll(0, slots(j['spells'], w.spellSlots.length));
    w.knownSpells.addAll((j['known'] as List).cast<String>());
    w.upgrades.addAll(ints(j['upgrades']));
    final bag = j['bag'] as List;
    for (var i = 0; i < bagSize && i < bag.length; i++) {
      final b = bag[i];
      if (b != null) w.bag[i] = ItemStack(b['id'] as String, b['n'] as int);
    }
    w.slain.addAll((j['slain'] as List).cast<String>());
    w.collected.addAll((j['collected'] as List).cast<String>());
    w.quests.addAll(ints(j['quests']));
    w.counts.addAll(ints(j['counts']));
    if (j['camp'] != null) w.camp = where(j['camp']);
    if (j['resume'] != null) w.resume = where(j['resume']);
    return w;
  }

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

  /// Moves a freshly picked-up weapon from the bag into an empty weapon slot,
  /// and holds it if your hands were empty. Does nothing if both are full.
  void autoEquip(String id) {
    final slot = weaponSlots.indexOf(null);
    if (slot < 0 || !itemOf(id).isWeapon || !removeItem(id)) return;
    weaponSlots[slot] = id;
    if (weaponSlots[activeWeapon] == null) activeWeapon = slot;
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
