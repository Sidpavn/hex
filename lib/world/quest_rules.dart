import 'items.dart';
import 'world_state.dart';

/// Something about the world that is true or false. Quests, dialogue and
/// objectives are all gated by these, so a new quest only combines them.
sealed class Condition {
  const Condition();

  bool test(WorldState w);
}

/// Always true; the catch-all at the end of a rule list.
class Always extends Condition {
  const Always();

  @override
  bool test(WorldState w) => true;
}

/// You hold at least [count] of [item].
class HasItem extends Condition {
  const HasItem(this.item, [this.count = 1]);

  final String item;
  final int count;

  @override
  bool test(WorldState w) => w.countOf(item) >= count;
}

/// Quest [quest] is exactly at [stage] (0 is "not started").
class QuestAt extends Condition {
  const QuestAt(this.quest, this.stage);

  final String quest;
  final int stage;

  @override
  bool test(WorldState w) => (w.quests[quest] ?? 0) == stage;
}

/// Quest [quest] has reached [stage] or later.
class QuestFrom extends Condition {
  const QuestFrom(this.quest, this.stage);

  final String quest;
  final int stage;

  @override
  bool test(WorldState w) => (w.quests[quest] ?? 0) >= stage;
}

/// [key] (see `Counts`) has been counted at least [atLeast] times.
class Count extends Condition {
  const Count(this.key, this.atLeast);

  final String key;
  final int atLeast;

  @override
  bool test(WorldState w) => w.count(key) >= atLeast;
}

/// [item] is the weapon in hand.
class Holding extends Condition {
  const Holding(this.item);

  final String item;

  @override
  bool test(WorldState w) => w.weaponId == item;
}

/// A pickup was taken from the ground, as `zone#id` (see `ItemSpawn`).
class Collected extends Condition {
  const Collected(this.key);

  final String key;

  @override
  bool test(WorldState w) => w.collected.contains(key);
}

/// At least [atLeast] bridges in [zone] have been mended.
class Repaired extends Condition {
  const Repaired(this.zone, this.atLeast);

  final String zone;
  final int atLeast;

  @override
  bool test(WorldState w) =>
      w.repaired.where((id) => id.startsWith('$zone#')).length >= atLeast;
}

/// The hero has learned [spell].
class Knows extends Condition {
  const Knows(this.spell);

  final String spell;

  @override
  bool test(WorldState w) => w.knownSpells.contains(spell);
}

/// A charge in [zone] has gone off.
class Blasted extends Condition {
  const Blasted(this.zone);

  final String zone;

  @override
  bool test(WorldState w) => w.blasted.any((id) => id.startsWith('$zone#'));
}

/// The hero is hurt.
class Wounded extends Condition {
  const Wounded();

  @override
  bool test(WorldState w) => w.hp < WorldState.maxHp;
}

class Not extends Condition {
  const Not(this.inner);

  final Condition inner;

  @override
  bool test(WorldState w) => !inner.test(w);
}

class All extends Condition {
  const All(this.all);

  final List<Condition> all;

  @override
  bool test(WorldState w) => all.every((c) => c.test(w));
}

class Any extends Condition {
  const Any(this.any);

  final List<Condition> any;

  @override
  bool test(WorldState w) => any.any((c) => c.test(w));
}

/// A change to the world. Outcomes are lists of these, so they can be shown
/// to the player, tested and (later) saved, which a bare closure cannot.
sealed class Effect {
  const Effect();

  void apply(WorldState w);

  /// What to tell the player this gives them, or null if it is invisible.
  String? get summary => null;
}

class GiveItem extends Effect {
  const GiveItem(this.item, [this.count = 1]);

  final String item;
  final int count;

  @override
  void apply(WorldState w) {
    w.addItem(item, count);
    w.autoEquip(item);
  }

  @override
  String get summary {
    final name = itemOf(item).name.toLowerCase();
    return count == 1 ? name : '$count ${name}s';
  }
}

class TakeItem extends Effect {
  const TakeItem(this.item, [this.count = 1]);

  final String item;
  final int count;

  @override
  void apply(WorldState w) => w.removeItem(item, count);
}

class GiveTokens extends Effect {
  const GiveTokens(this.amount);

  final int amount;

  @override
  void apply(WorldState w) => w.tokens += amount;

  @override
  String get summary => '$amount tokens';
}

class LearnSpell extends Effect {
  const LearnSpell(this.spell);

  final String spell;

  @override
  void apply(WorldState w) => w.learn(spell);

  @override
  String get summary => spellDefs[spell]?.name ?? spell;
}

/// Moves quest [quest] to [stage].
class SetQuest extends Effect {
  const SetQuest(this.quest, this.stage);

  final String quest;
  final int stage;

  @override
  void apply(WorldState w) => w.quests[quest] = stage;
}

/// Marks a pickup as taken (`zone#id`) without picking it up, so its copy on
/// the ground is gone.
class Collect extends Effect {
  const Collect(this.key);

  final String key;

  @override
  void apply(WorldState w) => w.collected.add(key);
}

/// Zeroes a counter, so a lesson only counts what you do after it starts.
class ResetCount extends Effect {
  const ResetCount(this.key);

  final String key;

  @override
  void apply(WorldState w) => w.counts.remove(key);
}

/// Costs [amount] HP, but never the last one.
class Hurt extends Effect {
  const Hurt(this.amount);

  final int amount;

  @override
  void apply(WorldState w) => w.hp = (w.hp - amount).clamp(1, WorldState.maxHp);
}
