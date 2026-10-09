import 'dart:math' as math;
import 'dart:ui';

import '../game/hex.dart';
import '../game/models.dart';
import 'boss.dart';
import 'pathfinding.dart';
import 'items.dart';
import 'quests.dart';
import 'world_state.dart';
import 'zone.dart';

/// What an enemy is doing right now. Shown above its head.
enum Awareness {
  /// Asleep ("z").
  asleep,

  /// Going about its business: patrolling, guarding or wandering.
  idle,

  /// Has noticed the hero and is coming ("!").
  alert,

  /// Lost sight of the hero and is checking the last place it saw them ("?").
  search,

  /// Gave up and is walking back to its post.
  returning,
}

class Enemy {
  Enemy(this.id, this.key, EnemySpawn s)
    : type = s.type,
      home = s.hex,
      route = s.route,
      behavior = s.behavior,
      hex = s.hex,
      maxHp = bossKits[s.type]?.hp ?? unitStats[s.type]!.maxHp,
      hp = bossKits[s.type]?.hp ?? unitStats[s.type]!.maxHp,
      awareness = s.behavior == Behavior.sleep
          ? Awareness.asleep
          : Awareness.idle,
      vis = hexWorld(s.hex);

  final int id;

  /// Stable id (`zone#index`) used to remember kills.
  final String key;
  final UnitType type;
  final Hex home;
  final List<Hex> route;
  final Behavior behavior;

  Hex hex;
  final int maxHp;
  int hp;
  Awareness awareness;

  /// A boss's spell in the making: the hexes it will hit, the hex it aimed
  /// at, the turns left before it fires and the turns before the next cast.
  Set<Hex> telegraph = {};
  Hex? aim;
  int charge = 0;
  int cool = 0;

  /// Turns of burning left. Each turn end it deals 1 damage. Reapplying
  /// refreshes it, it does not stack.
  int burn = 0;

  /// Where it was last seen the hero, while alert or searching.
  Hex? lastSeen;
  int _lost = 0;
  int _wait = 0;
  int _routeIdx = 0;
  double _moveAcc = 0;

  /// Visual position in world pixels, eased by the view toward [hex].
  Offset vis;

  /// Seconds the hurt flash has left (view state).
  double flash = 0;

  /// A quick shove toward whatever it just hit, decaying (view state).
  Offset kick = Offset.zero;

  UnitStats get stats => unitStats[type]!;
  bool get alive => hp > 0;
  bool get hostile => awareness == Awareness.alert;
}

enum SimEventKind {
  /// An enemy noticed the hero.
  noticed,

  /// An enemy gave up the chase.
  lostTrack,

  /// The hero hurt an enemy.
  hitEnemy,

  /// The hero killed an enemy.
  killedEnemy,

  /// An enemy hurt the hero.
  hitHero,

  /// The hero fell.
  heroDown,

  /// The hero recovered a little.
  regen,

  /// The hero cast a spell at [SimEvent.hex].
  spell,

  /// The hero picked something up.
  pickup,

  /// There was something to pick up but the bag is full.
  bagFull,

  /// The hero walked into a portal that is still shut.
  gateClosed,

  /// A boss started a spell: [SimEvent.hex] is the aimed hex, [SimEvent.from]
  /// the boss, [SimEvent.note] the spell.
  telegraph,

  /// The hero learned the spell named in [SimEvent.note].
  learned,

  /// The hero swung or shot at [SimEvent.hex] (from [SimEvent.from]).
  heroSwing,

  /// An enemy attacked the hero (from [SimEvent.from]).
  enemySwing,

  /// The hero chopped the tree at [SimEvent.hex] for [SimEvent.amount] wood.
  chopped,

  /// The hero mended the bridge touching [SimEvent.hex].
  repaired,

  /// The hero's shield soaked [SimEvent.amount] damage.
  blocked,

  /// The hero picked up the scroll named in [SimEvent.note] and reads it.
  scroll,

  /// A charge went off at [SimEvent.hex], clearing [SimEvent.amount] hexes of
  /// rubble.
  blasted,
}

class SimEvent {
  const SimEvent(
    this.kind,
    this.hex, [
    this.amount = 0,
    this.sneak = false,
    this.from,
    this.ranged = false,
    this.unit,
    this.note,
  ]);

  final SimEventKind kind;
  final Hex hex;
  final int amount;
  final bool sneak;

  /// Where an attack or spell came from.
  final Hex? from;

  /// A shot or thrown spell rather than a melee blow.
  final bool ranged;

  /// The enemy type involved, when there is one.
  final UnitType? unit;

  /// A spell id, for [SimEventKind.telegraph] and [SimEventKind.learned].
  final String? note;
}

/// The rules of moving around a zone: turn-based, with awake enemies reacting
/// to the hero. No drawing here, so it can be tested on its own.
class ZoneSim {
  ZoneSim(this.source, {WorldState? world, Hex? heroAt, math.Random? rng})
    : zone = source.copy(),
      world = world ?? WorldState(),
      rng = rng ?? math.Random(),
      hero = heroAt ?? source.spawn {
    _applyWorld();
    _spawn();
  }

  static final int heroMaxHp = WorldState.maxHp;

  /// Hexes the hero can be spotted from at best.
  static const _sight = {
    UnitType.knight: 5,
    UnitType.archer: 6,
    UnitType.golem: 4,
    UnitType.cavalry: 6,
    UnitType.mage: 6,
    UnitType.healer: 3,
    UnitType.warlord: 6,
    UnitType.pyromancer: 6,
    UnitType.titan: 7,
  };

  /// Hexes per turn.
  static const _speed = {
    UnitType.golem: 0.5,
    UnitType.titan: 0.5,
    UnitType.cavalry: 2.0,
  };

  /// Sleepers only notice you this close.
  static const wakeRadius = 2;

  /// Turns without line of sight before an alert enemy starts searching.
  static const loseSightAfter = 4;

  /// Turns an enemy waits at the last known position.
  static const searchWait = 2;

  /// A noticed enemy alerts friends this close to it.
  static const packRadius = 5;

  /// Turns of calm needed to recover one HP.
  static const regenEvery = 6;

  /// Turns per point of mana.
  static const manaEvery = 4;

  static const fireballCost = 2;
  static const fireballRange = 4;

  /// Turns a hex keeps burning.
  static const burnTurns = 2;

  /// Turns the burn status lasts on a unit.
  static const burnStatusTurns = 3;

  static const shieldCost = 2;
  static const shieldAbsorb = 3;
  static const shieldLasts = 5;

  /// Chance a burning forest lights a neighbouring forest each turn.
  static const fireSpread = 0.5;

  /// The zone as loaded; [zone] is this session's copy (forests can burn).
  final Zone source;
  final Zone zone;
  final WorldState world;
  final math.Random rng;

  Hex hero;
  int turn = 0;
  final List<Enemy> enemies = [];
  final List<SimEvent> events = [];

  /// Burning hexes and the turns they have left.
  final Map<Hex, int> fire = {};
  int _calm = 0;

  int get heroHp => world.hp;
  set heroHp(int v) => world.hp = v;
  int get mana => world.mana;

  bool get heroDown => world.hp <= 0;
  bool get danger => enemies.any((e) => e.alive && e.hostile);

  void _spawn() {
    enemies.clear();
    for (final (i, s) in source.enemies.indexed) {
      final key = '${source.id}#$i';
      if (world.slain.contains(key)) continue;
      enemies.add(Enemy(i, key, s));
    }
  }

  /// Back at [at] with full health and mana, everything respawned.
  void rest(Hex at) {
    hero = at;
    world
      ..hp = WorldState.maxHp
      ..mana = WorldState.maxMana
      ..shield = 0
      ..shieldTurns = 0
      ..burn = 0
      ..slain.clear();
    fire.clear();
    zone.tiles
      ..clear()
      ..addAll(source.tiles);
    _applyWorld();
    _calm = 0;
    events.clear();
    _spawn();
  }

  /// Lays the permanent changes (mended bridges, felled trees) over [zone].
  void _applyWorld() {
    for (final bridge in source.bridges) {
      if (world.repaired.contains(source.bridgeId(bridge))) {
        for (final h in bridge) {
          zone.tiles[h] = const ZoneTile(Terrain.water, ford: true);
        }
      }
    }
    for (final c in source.charges) {
      if (world.blasted.contains(source.chargeId(c))) _clearBlast(c);
    }
    for (final key in world.chopped) {
      if (!key.startsWith('${source.id}#')) continue;
      final qr = key.substring(source.id.length + 1).split(',');
      final h = Hex(int.parse(qr[0]), int.parse(qr[1]));
      if (zone.tiles[h]?.terrain == Terrain.forest) {
        zone.tiles[h] = const ZoneTile(Terrain.grass);
      }
    }
  }

  // ───────────────────────── charges and rockfalls ─────────────────────────

  /// Hexes around a charge that the blast hurts, and how much it hurts.
  static const chargeRadius = 1;
  static const chargeDamage = 3;

  /// Rubble this close to a charge is cleared by it.
  static const chargeReach = 2;

  /// Turns the charge at [c] and every run of rubble touching its reach into
  /// floor. Returns how many hexes of rubble went.
  int _clearBlast(Hex c) {
    zone.tiles[c] = const ZoneTile(Terrain.grass);
    final todo = [
      for (final e in zone.tiles.entries)
        if (e.value.rubble && e.key.distanceTo(c) <= chargeReach) e.key,
    ];
    var cleared = 0;
    while (todo.isNotEmpty) {
      final h = todo.removeLast();
      if (zone.tiles[h]?.rubble != true) continue;
      zone.tiles[h] = const ZoneTile(Terrain.grass);
      cleared++;
      todo.addAll(h.neighbors);
    }
    return cleared;
  }

  /// Sets off the charge at [c]: hurts everything beside it, clears the
  /// rubble and remembers it for good.
  void _detonate(Hex c) {
    world.blasted.add(source.chargeId(c));
    world.bump(Counts.blast);
    fire.remove(c);
    for (final h in [c, ...c.neighbors]) {
      final e = enemyAt(h);
      if (e != null) _damageEnemy(e, chargeDamage);
      if (h == hero) _hurtHero(chargeDamage);
    }
    events.add(SimEvent(SimEventKind.blasted, c, _clearBlast(c)));
  }

  // ───────────────────────── trees and bridges ─────────────────────────

  /// Wood a bridge takes.
  static const woodPerBridge = 30;

  /// A tree next to the hero that the hatchet can fell, or null.
  Hex? treeNear() {
    if (heroDown || !world.hasItem('hatchet')) return null;
    for (final h in hero.neighbors) {
      if (zone.tiles[h]?.terrain == Terrain.forest && enemyAt(h) == null) {
        return h;
      }
    }
    return null;
  }

  /// A broken bridge touching the hero's hex, or null.
  Set<Hex>? bridgeNear() {
    if (heroDown) return null;
    for (final b in source.bridges) {
      if (world.repaired.contains(source.bridgeId(b))) continue;
      if (hero.neighbors.any(b.contains)) return b;
    }
    return null;
  }

  /// Chops the tree at [tree]. Each of the [hits] (0 to 3) from the timing
  /// game is a piece of wood. With no hits the swings still cost a turn but
  /// the tree stays standing; otherwise it is gone for good.
  bool chop(Hex tree, {int hits = 1}) {
    if (treeNear() == null ||
        hero.distanceTo(tree) != 1 ||
        zone.tiles[tree]?.terrain != Terrain.forest) {
      return false;
    }
    if (!world.canAdd('wood')) {
      events.add(SimEvent(SimEventKind.bagFull, hero));
      return false;
    }
    final n = hits.clamp(0, 3);
    if (n == 0) {
      events.add(SimEvent(SimEventKind.chopped, tree, 0));
      tick();
      return true;
    }
    final got = n - world.addItem('wood', n);
    zone.tiles[tree] = const ZoneTile(Terrain.grass);
    world.chopped.add('${source.id}#${tree.q},${tree.r}');
    world.bump(Counts.chop);
    events.add(SimEvent(SimEventKind.chopped, tree, got));
    tick();
    return true;
  }

  /// Mends the broken bridge by the hero with [woodPerBridge] wood.
  bool repair() {
    final bridge = bridgeNear();
    if (bridge == null || world.countOf('wood') < woodPerBridge) return false;
    world.removeItem('wood', woodPerBridge);
    for (final h in bridge) {
      zone.tiles[h] = const ZoneTile(Terrain.water, ford: true);
    }
    world.repaired.add(source.bridgeId(bridge));
    world.bump(Counts.repair);
    events.add(SimEvent(SimEventKind.repaired, bridge.first));
    tick();
    return true;
  }

  /// Falls back to the zone start (used when there is no campsite yet).
  void respawn() => rest(source.spawn);

  NpcSpawn? npcAt(Hex h) {
    for (final n in source.npcs) {
      if (n.hex == h) return n;
    }
    return null;
  }

  /// Whether [h] has a campsite.
  bool isCamp(Hex h) => source.camps.contains(h);

  /// Items on the ground here that haven't been taken yet.
  Iterable<ItemSpawn> get groundItems => source.items.where(
    (i) => !world.collected.contains('${source.id}#${i.id}'),
  );

  ItemSpawn? itemAt(Hex h) {
    for (final i in groundItems) {
      if (i.hex == h) return i;
    }
    return null;
  }

  Enemy? enemyAt(Hex h) {
    for (final e in enemies) {
      if (e.alive && e.hex == h) return e;
    }
    return null;
  }

  // ───────────────────────── perception ─────────────────────────

  /// Whether a straight line from [a] to [b] is clear of mountains and (unless
  /// [treesBlock] is false, as for arcing spells) forests in between.
  bool lineOfSight(Hex a, Hex b, {bool treesBlock = true}) {
    final n = a.distanceTo(b);
    for (var i = 1; i < n; i++) {
      final t = i / n;
      // The tiny nudge keeps the line off hex edges so rounding is stable.
      final h = BoardLayout.roundHex(
        a.q + (b.q - a.q) * t + 1e-6,
        a.r + (b.r - a.r) * t + 2e-6,
      );
      final tile = zone.tiles[h];
      if (tile == null ||
          tile.terrain == Terrain.mountain ||
          (treesBlock && tile.terrain == Terrain.forest)) {
        return false;
      }
    }
    return true;
  }

  /// How far [e] can spot the hero right now.
  int sightOf(Enemy e) {
    var r = _sight[e.type] ?? 5;
    // Hiding in a forest or in a dark place shortens it.
    if (zone.tiles[hero]?.terrain == Terrain.forest) r -= 2;
    if (zone.dark) r -= 1;
    return math.max(1, r);
  }

  bool sees(Enemy e) =>
      e.hex.distanceTo(hero) <= sightOf(e) && lineOfSight(e.hex, hero);

  // ───────────────────────── hero actions ─────────────────────────

  /// Moves the hero one hex. Returns false if something is in the way.
  bool moveHero(Hex to) {
    if (hero.distanceTo(to) != 1) return false;
    final tile = zone.tiles[to];
    if (tile == null ||
        !tile.walkable ||
        enemyAt(to) != null ||
        npcAt(to) != null) {
      return false;
    }
    final portal = tile.portal;
    if (portal != null && closedGate(source.id, portal, world) != null) {
      events.add(SimEvent(SimEventKind.gateClosed, to));
      return false;
    }
    hero = to;
    final item = itemAt(to);
    if (item != null) {
      if (itemOf(item.itemId).isLore) {
        // Scrolls are read where they lie and filed in the journal, so they
        // never need a bag slot.
        if (!world.scrolls.contains(item.itemId)) {
          world.scrolls.add(item.itemId);
        }
        world.collected.add('${source.id}#${item.id}');
        events.add(
          SimEvent(
            SimEventKind.scroll,
            to,
            0,
            false,
            null,
            false,
            null,
            item.itemId,
          ),
        );
      } else if (world.canAdd(item.itemId)) {
        world.addItem(item.itemId);
        world.autoEquip(item.itemId);
        world.collected.add('${source.id}#${item.id}');
        events.add(SimEvent(SimEventKind.pickup, to));
      } else {
        events.add(SimEvent(SimEventKind.bagFull, to));
      }
    }
    tick();
    return true;
  }

  /// Spends a turn doing nothing.
  void wait() => tick();

  /// Whether the equipped weapon can hit [e] from where the hero stands.
  bool reaches(Enemy e) {
    final w = world.weapon;
    final d = hero.distanceTo(e.hex);
    if (!e.alive || d < w.minRange || d > w.maxRange) return false;
    return d <= 1 || lineOfSight(hero, e.hex);
  }

  /// Strikes [e] with the equipped weapon if it is in reach. Unaware enemies
  /// take double damage.
  bool attack(Enemy e) {
    if (!reaches(e)) return false;
    events.add(
      SimEvent(
        SimEventKind.heroSwing,
        e.hex,
        0,
        false,
        hero,
        world.weapon.ranged,
      ),
    );
    _damageEnemy(
      e,
      world.damageOf(world.weaponId),
      sneakable: true,
      sneakMult: world.weapon.sneak,
    );
    world.bump(Counts.hit(e.type, ranged: world.weapon.ranged));
    tick();
    return true;
  }

  void _damageEnemy(
    Enemy e,
    int dmg, {
    bool sneakable = false,
    int sneakMult = 2,
  }) {
    final sneak = sneakable && !e.hostile;
    final total = dmg * (sneak ? sneakMult : 1);
    if (e.stats.inert) {
      events.add(
        SimEvent(
          SimEventKind.hitEnemy,
          e.hex,
          total,
          false,
          null,
          false,
          e.type,
        ),
      );
      return;
    }
    e.hp -= total;
    if (!e.alive) {
      world.slain.add(e.key);
      world.bump(Counts.kill(e.type));
      final kit = bossKits[e.type];
      if (kit != null && !world.knownSpells.contains(kit.spell)) {
        world.learn(kit.spell);
        events.add(
          SimEvent(
            SimEventKind.learned,
            e.hex,
            0,
            false,
            null,
            false,
            e.type,
            kit.spell,
          ),
        );
      }
    }
    events.add(
      SimEvent(
        e.alive ? SimEventKind.hitEnemy : SimEventKind.killedEnemy,
        e.hex,
        total,
        sneak,
        null,
        false,
        e.type,
      ),
    );
    if (e.alive) _noticeHero(e);
  }

  /// Whether Fireball can be thrown at [target] right now.
  bool canCastFireball(Hex target) {
    if (mana < fireballCost) return false;
    final d = hero.distanceTo(target);
    if (d < 1 || d > fireballRange || !zone.tiles.containsKey(target)) {
      return false;
    }
    return d <= 1 || lineOfSight(hero, target, treesBlock: false);
  }

  bool _burnable(Hex h) {
    final t = zone.tiles[h]?.terrain;
    return t != null &&
        t != Terrain.water &&
        t != Terrain.lava &&
        t != Terrain.mountain;
  }

  /// Blasts [target] for 2 and its ring for 1, and sets the ground alight.
  /// Anyone caught in it is hurt, the hero included.
  bool castFireball(Hex target) {
    if (!canCastFireball(target)) return false;
    world.mana -= fireballCost;
    world.bump(Counts.cast('fireball'));
    events.add(SimEvent(SimEventKind.spell, target, 0, false, hero, true));
    for (final h in [target, ...target.neighbors]) {
      if (!zone.tiles.containsKey(h)) continue;
      if (_burnable(h)) fire[h] = burnTurns;
      final dmg = h == target ? 2 : 1;
      final e = enemyAt(h);
      if (e != null && !e.stats.fireImmune) {
        _damageEnemy(e, dmg);
        if (e.alive) _ignite(e);
      }
      if (h == hero) _hurtHero(dmg);
    }
    // Only the hero's own Fireball sets a charge off: boss fire and weapons
    // do not.
    for (final h in [target, ...target.neighbors]) {
      if (zone.tiles[h]?.charge ?? false) _detonate(h);
    }
    tick();
    return true;
  }

  static const mendCost = 2;
  static const mendHeal = 3;

  /// Heals the hero. Only when hurt and with the mana for it.
  bool castMend() {
    if (mana < mendCost || heroHp >= heroMaxHp || heroDown) return false;
    world.mana -= mendCost;
    world.bump(Counts.castMend);
    _heal(mendHeal);
    tick();
    return true;
  }

  /// Raises a shield that soaks the next [shieldAbsorb] damage. Not while
  /// the one you have is still full.
  bool castShield() {
    if (mana < shieldCost || heroDown || world.shield >= shieldAbsorb) {
      return false;
    }
    world.mana -= shieldCost;
    world.bump(Counts.castShield);
    world.shield = shieldAbsorb;
    world.shieldTurns = shieldLasts;
    tick();
    return true;
  }

  /// Drinks one [id] from the bag. Does nothing if it wouldn't help.
  bool useItem(String id) {
    final def = itemOf(id);
    if (!def.isConsumable || !world.hasItem(id) || heroDown) return false;
    final helps =
        (def.heal > 0 && heroHp < heroMaxHp) ||
        (def.mana > 0 && world.mana < WorldState.maxMana);
    if (!helps) return false;
    world.removeItem(id);
    if (def.heal > 0) _heal(def.heal);
    if (def.mana > 0) {
      world.mana = (world.mana + def.mana).clamp(0, WorldState.maxMana);
    }
    tick();
    return true;
  }

  void _heal(int n) {
    final before = world.hp;
    world.hp = (world.hp + n).clamp(0, heroMaxHp);
    events.add(SimEvent(SimEventKind.regen, hero, world.hp - before));
  }

  void _hurtHero(int dmg) {
    final soaked = math.min(world.shield, dmg);
    if (soaked > 0) {
      world.shield -= soaked;
      dmg -= soaked;
      if (world.shield == 0) world.shieldTurns = 0;
      events.add(SimEvent(SimEventKind.blocked, hero, soaked));
      if (dmg <= 0) return;
    }
    world.hp -= dmg;
    events.add(SimEvent(SimEventKind.hitHero, hero, dmg));
    if (heroDown) events.add(SimEvent(SimEventKind.heroDown, hero));
  }

  // ───────────────────────── the enemy turn ─────────────────────────

  void tick() {
    turn++;
    for (final e in List.of(enemies)) {
      if (!e.alive || e.stats.inert) continue;
      if (!_bossTurn(e)) _act(e);
      if (heroDown) break;
    }
    _fireStep();
    _statusStep();
    enemies.removeWhere((e) => !e.alive);
    _regen();
  }

  /// A boss spends its turn charging or firing a spell instead of acting
  /// normally. Returns whether it did.
  bool _bossTurn(Enemy e) {
    final kit = bossKits[e.type];
    if (kit == null) return false;
    if (e.charge > 0) {
      if (--e.charge == 0) _release(e, kit);
      return true;
    }
    if (e.cool > 0) e.cool--;
    if (e.awareness == Awareness.alert &&
        e.cool == 0 &&
        e.hex.distanceTo(hero) <= kit.range &&
        sees(e)) {
      // Aim where the hero stands now; moving away is the answer.
      e.aim = hero;
      e.telegraph = {
        for (final h in [hero, ...hero.neighbors])
          if (zone.tiles[h]?.walkable ?? false) h,
      };
      e.charge = kit.warn;
      events.add(
        SimEvent(
          SimEventKind.telegraph,
          hero,
          0,
          false,
          e.hex,
          true,
          e.type,
          kit.spell,
        ),
      );
      return true;
    }
    return false;
  }

  /// The blast lands on whatever is still in the marked hexes.
  void _release(Enemy e, BossKit kit) {
    final target = e.aim!;
    events.add(
      SimEvent(SimEventKind.spell, target, 0, false, e.hex, true, e.type),
    );
    for (final h in e.telegraph) {
      if (kit.fire && _burnable(h)) fire[h] = burnTurns;
      if (h == hero) _hurtHero(h == target ? kit.center : kit.ring);
    }
    e.telegraph = {};
    e.aim = null;
    e.cool = kit.cooldown;
  }

  /// Fire hurts what stands in it, spreads through forests and burns them
  /// down to grass.
  void _fireStep() {
    if (fire.isEmpty) return;
    final burning = fire.keys.toList();
    for (final h in burning) {
      final e = enemyAt(h);
      if (e != null && !e.stats.fireImmune) _ignite(e);
      if (h == hero && !heroDown) world.burn = burnStatusTurns;
    }
    final lit = <Hex>[];
    for (final h in burning) {
      if (zone.tiles[h]?.terrain != Terrain.forest) continue;
      for (final n in h.neighbors) {
        if (zone.tiles[n]?.terrain == Terrain.forest &&
            !fire.containsKey(n) &&
            rng.nextDouble() < fireSpread) {
          lit.add(n);
        }
      }
    }
    for (final h in burning) {
      final left = fire[h]! - 1;
      if (left <= 0) {
        fire.remove(h);
        if (zone.tiles[h]?.terrain == Terrain.forest) {
          zone.tiles[h] = const ZoneTile(Terrain.grass);
        }
      } else {
        fire[h] = left;
      }
    }
    for (final h in lit) {
      fire[h] = burnTurns;
    }
  }

  /// Sets [e] burning, or refreshes it if it already is.
  void _ignite(Enemy e) {
    if (e.stats.fireImmune || !e.alive) return;
    e.burn = burnStatusTurns;
  }

  /// Turn-end statuses: damage first, then tick the duration down.
  void _statusStep() {
    if (!heroDown && world.burn > 0) {
      _hurtHero(1);
      world.burn--;
    }
    if (world.shieldTurns > 0 && --world.shieldTurns == 0) world.shield = 0;
    for (final e in enemies) {
      if (!e.alive || e.burn <= 0) continue;
      _damageEnemy(e, 1);
      e.burn--;
    }
  }

  void _regen() {
    if (heroDown) return;
    if (turn % manaEvery == 0 && world.mana < WorldState.maxMana) {
      world.mana++;
    }
    if (danger) {
      _calm = 0;
      return;
    }
    if (heroHp >= heroMaxHp) return;
    if (++_calm >= regenEvery) {
      _calm = 0;
      heroHp++;
      events.add(SimEvent(SimEventKind.regen, hero, 1));
    }
  }

  void _noticeHero(Enemy e) {
    if (e.awareness != Awareness.alert) {
      e.awareness = Awareness.alert;
      events.add(SimEvent(SimEventKind.noticed, e.hex));
      // A pack moves together.
      for (final o in enemies) {
        if (o == e ||
            !o.alive ||
            o.stats.inert ||
            o.awareness == Awareness.alert) {
          continue;
        }
        if (o.hex.distanceTo(e.hex) <= packRadius) {
          o.awareness = Awareness.alert;
          events.add(SimEvent(SimEventKind.noticed, o.hex));
        }
      }
    }
    e.lastSeen = hero;
    e._lost = 0;
  }

  void _act(Enemy e) {
    final sawHero = sees(e);
    switch (e.awareness) {
      case Awareness.asleep:
        if (hero.distanceTo(e.hex) <= wakeRadius && sawHero) _noticeHero(e);
      case Awareness.idle:
      case Awareness.returning:
        if (sawHero) {
          _noticeHero(e);
          _fight(e);
        } else if (e.awareness == Awareness.returning) {
          _returnHome(e);
        } else {
          _behave(e);
        }
      case Awareness.alert:
        if (sawHero) {
          e.lastSeen = hero;
          e._lost = 0;
        } else if (++e._lost >= loseSightAfter) {
          e.awareness = Awareness.search;
          e._wait = searchWait;
          events.add(SimEvent(SimEventKind.lostTrack, e.hex));
          return;
        }
        _fight(e);
      case Awareness.search:
        if (sawHero) {
          _noticeHero(e);
          _fight(e);
          return;
        }
        final spot = e.lastSeen ?? e.home;
        if (e.hex != spot) {
          _walk(e, spot);
        } else if (--e._wait <= 0) {
          e.awareness = Awareness.returning;
        }
    }
  }

  /// Attack if in reach, otherwise close the distance.
  void _fight(Enemy e) {
    final s = e.stats;
    final d = e.hex.distanceTo(hero);
    final inReach = d >= s.minRange && d <= s.maxRange;
    final clear = d <= 1 || lineOfSight(e.hex, hero);
    if (inReach && clear) {
      _hitHero(e);
      return;
    }
    // Ranged units back off when too close.
    if (d < s.minRange) {
      _stepAway(e);
      return;
    }
    _walk(e, hero);
  }

  /// Whether [e] could hit the hero this very turn, so the screen can warn.
  bool threatens(Enemy e) {
    if (!e.alive || !e.hostile) return false;
    final s = e.stats;
    final d = e.hex.distanceTo(hero);
    return d >= s.minRange &&
        d <= s.maxRange &&
        (d <= 1 || lineOfSight(e.hex, hero));
  }

  void _hitHero(Enemy e) {
    events.add(
      SimEvent(
        SimEventKind.enemySwing,
        hero,
        0,
        false,
        e.hex,
        e.stats.maxRange > 1,
        e.type,
      ),
    );
    _hurtHero(e.stats.damage);
  }

  void _stepAway(Enemy e) {
    Hex? best;
    var bestD = e.hex.distanceTo(hero);
    for (final n in e.hex.neighbors) {
      final tile = zone.tiles[n];
      if (tile == null || !tile.walkable || enemyAt(n) != null || n == hero) {
        continue;
      }
      final d = n.distanceTo(hero);
      if (d > bestD) {
        bestD = d;
        best = n;
      }
    }
    if (best != null) e.hex = best;
  }

  /// Moves up to its speed in hexes toward [goal].
  void _walk(Enemy e, Hex goal) {
    e._moveAcc += _speed[e.type] ?? 1.0;
    while (e._moveAcc >= 1) {
      e._moveAcc -= 1;
      if (e.hex == goal) return;
      final path = findPath(
        zone,
        e.hex,
        goal,
        blocked: (h) =>
            h == hero ||
            enemyAt(h) != null ||
            npcAt(h) != null ||
            (fire.containsKey(h) && !e.stats.fireImmune),
      );
      if (path == null || path.isEmpty) return;
      final next = path.first;
      if (next == hero || enemyAt(next) != null || npcAt(next) != null) return;
      e.hex = next;
    }
  }

  void _returnHome(Enemy e) {
    if (e.hex == e.home) {
      e.awareness = e.behavior == Behavior.sleep
          ? Awareness.asleep
          : Awareness.idle;
      e.lastSeen = null;
      return;
    }
    _walk(e, e.home);
  }

  void _behave(Enemy e) {
    switch (e.behavior) {
      case Behavior.sleep:
      case Behavior.guard:
        if (e.hex != e.home) _walk(e, e.home);
      case Behavior.patrol:
        if (e.route.length < 2) return;
        final goal = e.route[e._routeIdx % e.route.length];
        if (e.hex == goal) {
          e._routeIdx = (e._routeIdx + 1) % e.route.length;
        } else {
          _walk(e, goal);
        }
      case Behavior.wander:
        if (rng.nextDouble() > 0.35) return;
        final options = [
          for (final n in e.hex.neighbors)
            if ((zone.tiles[n]?.walkable ?? false) &&
                enemyAt(n) == null &&
                n != hero &&
                n.distanceTo(e.home) <= 3)
              n,
        ];
        if (options.isNotEmpty) e.hex = options[rng.nextInt(options.length)];
    }
  }
}
