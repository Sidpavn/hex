import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../game/hex.dart';
import '../data/storage.dart';
import '../game/models.dart';
import '../world/items.dart';
import '../world/pathfinding.dart';
import '../world/quests.dart';
import '../world/sim.dart';
import '../world/world_state.dart';
import '../world/zone.dart';
import 'pixel/hex_art.dart';
import 'pixel/pixel_assets.dart';
import 'pixel/terrain_draw.dart';
import 'widgets.dart';
import 'inventory_ui.dart';
import 'zone_fx.dart';
import 'zone_overlays.dart';

/// Maps a zone's world space (art pixels) onto the screen with a fixed,
/// integer pixel scale and a camera that follows the hero.
class ZoneView {
  /// [inset] is the part of the screen covered by the HUD. The zone is framed
  /// inside what is left, so its outermost hexes can be reached and tapped.
  ZoneView(
    Size size,
    double dpr,
    Offset cam,
    Zone zone, [
    EdgeInsets inset = EdgeInsets.zero,
  ]) {
    // About eight hexes across, whole device pixels per art pixel.
    final k = math.max(2, (size.width * dpr / (8 * BoardLayout.hexW)).round());
    scale = k / dpr;
    final area = Rect.fromLTRB(
      inset.left,
      inset.top,
      size.width - inset.right,
      size.height - inset.bottom,
    );
    final halfW = area.width / scale / 2;
    final halfH = area.height / scale / 2;
    double clamp(double v, double lo, double hi) =>
        lo > hi ? (lo + hi) / 2 : v.clamp(lo, hi);
    final b = zone.bounds;
    final c = Offset(
      clamp(cam.dx, b.left + halfW, b.right - halfW),
      clamp(cam.dy, b.top + halfH, b.bottom - halfH),
    );
    final o = area.center - c * scale;
    origin = Offset(
      (o.dx * dpr).roundToDouble() / dpr,
      (o.dy * dpr).roundToDouble() / dpr,
    );
  }

  late final double scale;
  late final Offset origin;

  Offset toScreen(Offset world) => origin + world * scale;
  Offset toWorld(Offset screen) => (screen - origin) / scale;
}

class _FloatText {
  _FloatText(this.world, this.text, this.color, {this.delay = 0});

  final Offset world;
  final String text;
  final Color color;

  /// Waits this long before appearing, so it lands with its blow.
  final double delay;
  double age = 0;
}

/// Explore a zone: tap a hex to travel there, tap an enemy to attack it, tap
/// yourself to wait. Every step is a turn, and awake enemies react.
class ZoneScreen extends StatefulWidget {
  const ZoneScreen({
    super.key,
    this.startZone = 'training',
    this.world,
    this.autosave = false,
  });

  final String startZone;

  /// A game to carry on with. Without one, a new game starts.
  final WorldState? world;

  /// Write progress to [Storage] at zone changes, camps and conversations.
  final bool autosave;

  @override
  State<ZoneScreen> createState() => _ZoneScreenState();
}

class _ZoneScreenState extends State<ZoneScreen>
    with SingleTickerProviderStateMixin, ReloadsPixelAssets {
  Zone? zone;
  ZoneSim? sim;
  late final WorldState world = widget.world ?? WorldState.newGame();
  Map<String, Zone> zones = {};

  /// Spell targeting: the next tap on a valid hex throws a Fireball.
  bool targeting = false;
  NpcSpawn? talking;
  Dialogue? dialogue;
  bool campOpen = false;
  bool journalOpen = false;
  bool packOpen = false;
  bool packAtCamp = false;

  /// What the current route is for: an enemy to strike, an NPC to talk to, or
  /// a campfire to sit at.
  Enemy? _chasing;
  NpcSpawn? _toTalk;
  Hex? _toCamp;
  Offset heroWorld = Offset.zero;
  Offset cam = Offset.zero;
  List<Hex> path = [];
  Hex? destination;
  double time = 0;
  double heroFlash = 0;
  final texts = <_FloatText>[];
  final fx = ZoneFx();
  Offset heroKick = Offset.zero;
  final tick = ValueNotifier<int>(0);
  final turn = ValueNotifier<int>(0);
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _dpr = 1;

  static const _hexesPerSecond = 8.0;

  /// Screen covered by the HUD, measured after layout so the camera can frame
  /// the zone in the space that is left.
  EdgeInsets _inset = const EdgeInsets.all(8);
  final _topKey = GlobalKey();
  final _barKey = GlobalKey();

  void _measure() {
    final root = context.findRenderObject();
    if (!mounted || root is! RenderBox || !root.hasSize) return;
    double edge(GlobalKey k, {required bool bottomEdge}) {
      final box = k.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return 0;
      final at = box.localToGlobal(
        Offset(0, bottomEdge ? box.size.height : 0),
        ancestor: root,
      );
      return bottomEdge ? at.dy : root.size.height - at.dy;
    }

    const gap = 8.0;
    final next = EdgeInsets.fromLTRB(
      gap,
      edge(_topKey, bottomEdge: true) + gap,
      gap,
      edge(_barKey, bottomEdge: false) + gap,
    );
    final d = next.top - _inset.top;
    final e = next.bottom - _inset.bottom;
    if (d.abs() > 0.5 || e.abs() > 0.5) setState(() => _inset = next);
  }

  Hex get heroHex => sim?.hero ?? const Hex(0, 0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    final resume = widget.autosave ? world.resume : null;
    if (resume != null) {
      _enter(resume.zone, at: resume.hex);
    } else {
      _enter(widget.startZone);
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    // Hot reload: re-read the zone files too, keeping the hero where they are.
    assert(() {
      final z = zone;
      final s = sim;
      ZoneRepo.clear();
      if (z != null && s != null) _enter(z.id, at: s.hero);
      return true;
    }());
  }

  @override
  void dispose() {
    _ticker.dispose();
    tick.dispose();
    turn.dispose();
    super.dispose();
  }

  Future<void> _enter(
    String id, {
    String? portal,
    Hex? at,
    bool rest = false,
  }) async {
    zones = await ZoneRepo.loadAll();
    final z = zones[id] ?? await ZoneRepo.load(id);
    if (!mounted) return;
    setState(() {
      final where =
          at ?? (portal == null ? z.spawn : (z.portalHex[portal] ?? z.spawn));
      final s = ZoneSim(z, world: world, heroAt: where);
      if (rest) s.rest(where);
      sim = s;
      zone = z;
      heroWorld = hexWorld(where);
      cam = heroWorld;
      _clearRoute();
      texts.clear();
      fx.clear();
      targeting = false;
    });
    _save();
  }

  /// Writes the game down, if this screen was opened to keep one.
  void _save() {
    final z = zone;
    final s = sim;
    if (!widget.autosave || z == null || s == null || s.heroDown) return;
    world.resume = (zone: z.id, hex: s.hero);
    Storage.saveExplore(world);
  }

  void _clearRoute() {
    path = [];
    destination = null;
    _chasing = null;
    _toTalk = null;
    _toCamp = null;
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    time += dt;
    final z = zone;
    final s = sim;
    if (z != null && s != null) {
      if (!s.heroDown) _walk(z, s, dt);
      _glide(s, dt);
      cam += (heroWorld - cam) * (1 - math.exp(-dt * 7));
      heroFlash = math.max(0, heroFlash - dt);
      fx.update(dt);
      final settle = math.exp(-dt * 18);
      heroKick *= settle;
      for (final e in s.enemies) {
        e.kick *= settle;
      }
      for (final t in List.of(texts)) {
        t.age += dt;
        if (t.age > t.delay + 0.9) texts.remove(t);
      }
    }
    tick.value++;
  }

  /// Eases creatures toward the hex they now stand on.
  void _glide(ZoneSim s, double dt) {
    final step = BoardLayout.hexW * _hexesPerSecond * dt;
    for (final e in s.enemies) {
      final delta = hexWorld(e.hex) - e.vis;
      e.vis = delta.distance <= step
          ? hexWorld(e.hex)
          : e.vis + delta / delta.distance * step;
      e.flash = math.max(0, e.flash - dt);
    }
  }

  void _walk(Zone z, ZoneSim s, double dt) {
    if (path.isEmpty) return;
    final atRest = (heroWorld - hexWorld(s.hero)).distance < 0.01;
    if (atRest) {
      // Something we were heading for may now be in reach.
      final foe = _chasing;
      if (foe != null) {
        if (!foe.alive) {
          _clearRoute();
          return;
        }
        if (s.reaches(foe)) {
          _clearRoute();
          s.attack(foe);
          afterTurn(s);
          return;
        }
      }
      final next = path.first;
      final npc = s.npcAt(next);
      if (npc != null) {
        final talk = path.length == 1 && _toTalk == npc;
        _clearRoute();
        if (talk) _startTalk(npc);
        return;
      }
      if (s.enemyAt(next) != null || s.fire.containsKey(next)) {
        _clearRoute();
        return;
      }
    }
    final target = hexWorld(path.first);
    final delta = target - heroWorld;
    final step = BoardLayout.hexW * _hexesPerSecond * dt;
    if (delta.distance <= step) {
      heroWorld = target;
      final next = path.removeAt(0);
      if (s.moveHero(next)) {
        afterTurn(s);
      } else {
        _clearRoute();
        if (s.events.isNotEmpty) afterTurn(s);
      }
      if (path.isEmpty && !s.heroDown) {
        final camp = _toCamp;
        _clearRoute();
        final portal = z.portalAt(s.hero);
        if (portal != null) {
          _enter(portal.toZone, portal: portal.toPortal);
        } else if (camp != null && camp == s.hero) {
          setState(() => campOpen = true);
        }
      }
    } else {
      heroWorld += delta / delta.distance * step;
    }
  }

  void _startTalk(NpcSpawn npc) {
    setState(() {
      talking = npc;
      dialogue = talkTo(npc, world);
    });
  }

  /// Reacts to everything that happened this turn.
  void afterTurn(ZoneSim s) {
    turn.value = s.turn;
    // A turn resolves instantly; play it back in order. [cursor] is when the
    // next action starts, [impact] when the current blow lands.
    var cursor = 0.0;
    var impact = 0.0;
    const sparkWhite = [Colors.white, Color(0xFFFFF1A0), Color(0xFFF4C846)];
    const sparkGold = [Color(0xFFFFE08A), Color(0xFFFA9632), Colors.white];
    const sparkRed = [Color(0xFFE25454), Colors.white, Color(0xFFFA9632)];
    const puff = [Color(0xFFA0AABE), Color(0xFF68728C), Colors.white];
    Offset chest(Hex h) => hexWorld(h) + const Offset(0, -8);

    for (final ev in s.events) {
      final at = hexWorld(ev.hex) + const Offset(0, -10);
      switch (ev.kind) {
        case SimEventKind.noticed:
          // Stop auto-travel the moment something spots you.
          _clearRoute();
        case SimEventKind.heroSwing:
          final from = hexWorld(ev.from!);
          final dir = hexWorld(ev.hex) - from;
          final unit = dir / math.max(1, dir.distance);
          final angle = math.atan2(dir.dy, dir.dx);
          if (ev.ranged) {
            fx.projectile(
              chest(ev.from!),
              chest(ev.hex),
              ProjectileKind.arrow,
              cursor,
              0.2,
            );
            fx.at(cursor, () => heroKick = unit * -3);
            impact = cursor + 0.2;
          } else {
            fx.slash(from + unit * 12 + const Offset(0, -6), angle, cursor);
            fx.at(cursor, () => heroKick = unit * 7);
            impact = cursor + 0.09;
          }
        case SimEventKind.hitEnemy:
          final foe = s.enemyAt(ev.hex);
          final when = impact;
          fx.at(when, () {
            if (foe != null) {
              foe.flash = 0.18;
              final d = hexWorld(ev.hex) - hexWorld(s.hero);
              foe.kick = d / math.max(1, d.distance) * 4;
            }
            fx.shake = math.max(fx.shake, ev.sneak ? 0.45 : 0.25);
          });
          fx.burst(
            at,
            ev.sneak ? sparkGold : sparkWhite,
            when,
            count: ev.sneak ? 14 : 8,
            speed: ev.sneak ? 90 : 65,
          );
          texts.add(
            _FloatText(
              at,
              ev.sneak ? 'Sneak -${ev.amount}' : '-${ev.amount}',
              Pal.gold,
              delay: when,
            ),
          );
        case SimEventKind.killedEnemy:
          final when = impact;
          fx.ghost(
            ev.unit ?? UnitType.knight,
            Team.enemy,
            hexWorld(ev.hex),
            when,
          );
          fx.at(when, () => fx.shake = math.max(fx.shake, 0.5));
          fx.burst(
            at,
            ev.sneak ? sparkGold : sparkWhite,
            when,
            count: 12,
            speed: 85,
          );
          fx.burst(
            at,
            puff,
            when + 0.08,
            count: 10,
            speed: 40,
            life: 0.5,
            size: 3,
          );
          texts.add(
            _FloatText(
              at,
              ev.sneak ? 'Sneak kill!' : 'Slain!',
              Pal.gold,
              delay: when,
            ),
          );
        case SimEventKind.enemySwing:
          // Each enemy goes in turn, after whatever came before it.
          cursor = math.max(cursor, impact) + 0.2;
          final from = hexWorld(ev.from!);
          final dir = hexWorld(ev.hex) - from;
          final unit = dir / math.max(1, dir.distance);
          final foe = s.enemyAt(ev.from!);
          final big =
              ev.unit == UnitType.golem ||
              ev.unit == UnitType.titan ||
              ev.unit == UnitType.warlord;
          if (ev.ranged) {
            final magic =
                ev.unit == UnitType.mage || ev.unit == UnitType.pyromancer;
            fx.projectile(
              chest(ev.from!),
              chest(ev.hex),
              magic ? ProjectileKind.bolt : ProjectileKind.arrow,
              cursor,
              0.22,
            );
            impact = cursor + 0.22;
            fx.at(cursor, () => foe?.kick = unit * -3);
          } else {
            fx.slash(
              from + unit * 12 + const Offset(0, -6),
              math.atan2(dir.dy, dir.dx),
              cursor,
              big: big,
            );
            fx.at(cursor, () => foe?.kick = unit * 8);
            impact = cursor + 0.09;
          }
        case SimEventKind.hitHero:
          _clearRoute();
          final when = impact;
          fx.at(when, () {
            heroFlash = 0.2;
            fx.shake = math.max(fx.shake, 0.6);
            HapticFeedback.mediumImpact();
          });
          fx.burst(at, sparkRed, when, count: 10, speed: 70);
          texts.add(_FloatText(at, '-${ev.amount}', Pal.red, delay: when));
        case SimEventKind.regen:
          texts.add(_FloatText(at, '+${ev.amount}', Pal.green));
        case SimEventKind.heroDown:
          _clearRoute();
        case SimEventKind.spell:
          HapticFeedback.lightImpact();
          fx.projectile(
            chest(ev.from!),
            hexWorld(ev.hex),
            ProjectileKind.fireball,
            cursor,
            0.34,
          );
          impact = cursor + 0.34;
          fx.at(impact, () => fx.shake = math.max(fx.shake, 0.7));
          fx.ring(hexWorld(ev.hex), 20, const Color(0xFFFA9632), impact, 0.35);
          fx.ring(hexWorld(ev.hex), 12, const Color(0xFFFFE08A), impact, 0.25);
          fx.burst(
            hexWorld(ev.hex),
            const [Color(0xFFFA9632), Color(0xFFFFE08A), Color(0xFFE6503C)],
            impact,
            count: 18,
            speed: 95,
            life: 0.5,
            size: 3,
          );
          texts.add(_FloatText(at, 'Fireball!', Pal.goldLight, delay: cursor));
        case SimEventKind.pickup:
          final item = s.source.items.firstWhere((i) => i.hex == ev.hex);
          texts.add(
            _FloatText(at, 'Got ${itemOf(item.itemId).name}', Pal.goldLight),
          );
          fx.burst(at, sparkGold, 0, count: 12, speed: 55);
          HapticFeedback.selectionClick();
        case SimEventKind.bagFull:
          texts.add(_FloatText(at, 'Bag full', Pal.red));
        case SimEventKind.telegraph:
          // Stop auto-travel: the player has to choose where to stand.
          _clearRoute();
          final name = spellDefs[ev.note]?.name ?? 'Spell';
          texts.add(
            _FloatText(
              hexWorld(ev.from!) + const Offset(0, -16),
              '$name incoming',
              Pal.red,
              delay: cursor,
            ),
          );
          HapticFeedback.mediumImpact();
        case SimEventKind.learned:
          final spell = spellDefs[ev.note];
          if (spell != null) {
            talking = NpcSpawn('boss', 'Pyromancer', ev.hex, ev.unit!);
            dialogue = Dialogue(spell.name, [
              'You learned ${spell.name}. ${spell.desc}',
              'It costs ${spell.cost} mana. Tap it on the quick bar, then '
                  'tap a hex up to ${ZoneSim.fireballRange} away.',
            ]);
          }
        case SimEventKind.gateClosed:
          final gate = closedGate(
            s.source.id,
            s.zone.tiles[ev.hex]?.portal ?? '',
            world,
          );
          if (gate != null) {
            texts.add(_FloatText(at, gate.message, Pal.goldLight));
          }
        case SimEventKind.lostTrack:
          break;
      }
    }
    s.events.clear();
    setState(() {});
  }

  void _tap(Offset local, Size size) {
    final z = zone;
    final s = sim;
    if (z == null || s == null || s.heroDown) return;
    final view = ZoneView(size, _dpr, cam, z, _inset);
    final target = hexAtWorld(view.toWorld(local));

    // Aiming a spell: a valid hex fires it, anything else cancels.
    if (targeting) {
      setState(() => targeting = false);
      if (s.castFireball(target)) afterTurn(s);
      return;
    }

    final moving = path.isNotEmpty;
    if (target == s.hero && !moving) {
      if (s.isCamp(target)) {
        setState(() => campOpen = true);
      } else {
        s.wait();
        afterTurn(s);
      }
      return;
    }
    if (!(z.tiles[target]?.walkable ?? false)) return;

    final foe = s.enemyAt(target);
    if (foe != null && !moving && s.reaches(foe)) {
      s.attack(foe);
      afterTurn(s);
      return;
    }
    final npc = s.npcAt(target);
    if (npc != null && !moving && s.hero.distanceTo(target) <= 1) {
      _startTalk(npc);
      return;
    }
    if (s.isCamp(target) && !moving && s.hero.distanceTo(target) <= 1) {
      // Step onto the fire's hex to sit at it.
      path = [target];
      destination = target;
      _toCamp = target;
      return;
    }

    // If already walking, carry on to the next hex before turning.
    final start = moving ? path.first : s.hero;
    final route = findPath(
      z,
      start,
      target,
      blocked: (h) =>
          h != target &&
          (s.enemyAt(h) != null || s.npcAt(h) != null || s.fire.containsKey(h)),
    );
    if (route == null) return;
    setState(() {
      path = [if (moving) path.first, ...route];
      destination = target;
      _chasing = foe;
      _toTalk = npc;
      _toCamp = s.isCamp(target) ? target : null;
    });
  }

  /// Spell slot tapped on the quick bar.
  void _useSpell(int slot) {
    final s = sim;
    final id = world.spellSlots[slot];
    if (s == null || s.heroDown || id == null) return;
    switch (id) {
      case 'fireball':
        setState(() {
          targeting = !targeting && s.mana >= ZoneSim.fireballCost;
          if (targeting) _clearRoute();
        });
      case 'mend':
        setState(() => targeting = false);
        if (s.castMend()) afterTurn(s);
    }
  }

  bool _spellReady(String id) {
    final s = sim;
    if (s == null || s.heroDown) return false;
    return switch (id) {
      'fireball' => s.mana >= ZoneSim.fireballCost,
      'mend' => s.mana >= ZoneSim.mendCost && s.heroHp < ZoneSim.heroMaxHp,
      _ => false,
    };
  }

  /// Key of the selected quick-bar entry (null: the weapon in hand).
  String? _quickKey;
  double _swipe = 0;
  bool _swiped = false;

  /// Selects a quick-bar slot. Choosing a weapon puts it in hand; moving the
  /// selection off the spell being aimed ends the aim.
  void _selectQuick(QuickEntry e) {
    if (e.kind == QuickKind.weapon && world.weaponSlots[e.slot] == null) return;
    setState(() {
      _quickKey = e.key;
      targeting = false;
      if (e.kind == QuickKind.weapon) world.activeWeapon = e.slot;
    });
  }

  /// Uses the selected slot: aims or casts a spell, drinks a potion. A
  /// weapon is already in hand, so tapping it does nothing.
  void _useQuick(QuickEntry e) {
    switch (e.kind) {
      case QuickKind.weapon:
        break;
      case QuickKind.spell:
        _useSpell(e.slot);
      case QuickKind.item:
        _drink(e.id);
    }
  }

  void _moveQuick(int dir, {bool group = false}) {
    final entries = quickEntries(world);
    final cur = selectedQuick(entries, _quickKey, world);
    if (cur == null) return;
    final next = stepQuick(entries, cur, dir, group: group);
    if (next.key != cur.key) _selectQuick(next);
  }

  /// Swipe anywhere on the world: left moves the selection on, right back.
  void _swipeUpdate(double dx) {
    _swipe += dx;
    if (_swipe.abs() >= _swipeStep) {
      _moveQuick(_swipe < 0 ? 1 : -1);
      _swipe = 0;
      _swiped = true;
    }
  }

  void _swipeEnd(double velocity) {
    if (!_swiped) {
      if (velocity.abs() > _flingSpeed) {
        _moveQuick(velocity < 0 ? 1 : -1, group: true);
      } else if (_swipe.abs() > _swipeStep / 3) {
        _moveQuick(_swipe < 0 ? 1 : -1);
      }
    }
    _swipe = 0;
    _swiped = false;
  }

  static const _swipeStep = 40.0;
  static const _flingSpeed = 1500.0;

  /// Drinks a potion through the game, so it takes a turn.
  bool _drink(String id) {
    final s = sim;
    if (s == null) return false;
    final ok = s.useItem(id);
    if (ok) afterTurn(s);
    return ok;
  }

  void _rest() {
    final s = sim;
    final z = zone;
    if (s == null || z == null) return;
    setState(() {
      world.camp = (zone: z.id, hex: s.hero);
      s.rest(s.hero);
      heroWorld = hexWorld(s.hero);
      campOpen = false;
      texts
        ..clear()
        ..add(
          _FloatText(heroWorld + const Offset(0, -12), 'Rested', Pal.green),
        );
    });
    _save();
  }

  void _wakeUp() {
    final s = sim;
    final z = zone;
    if (s == null || z == null) return;
    final camp = world.camp;
    if (camp != null && camp.zone != z.id) {
      _enter(camp.zone, at: camp.hex, rest: true);
      return;
    }
    setState(() {
      s.rest(camp?.hex ?? z.spawn);
      heroWorld = hexWorld(s.hero);
      cam = heroWorld;
      _clearRoute();
      texts.clear();
      fx.clear();
      targeting = false;
    });
  }

  void _endTalk(DialogueChoice? choice) {
    setState(() {
      choice?.apply(world);
      talking = null;
      dialogue = null;
    });
    _save();
  }

  @override
  Widget build(BuildContext context) {
    _dpr = MediaQuery.of(context).devicePixelRatio;
    final z = zone;
    final s = sim;
    final objective = currentObjective(world);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return Scaffold(
      backgroundColor: const Color(0xFF10181C),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, cons) {
                final size = Size(cons.maxWidth, cons.maxHeight);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _tap(d.localPosition, size),
                  onHorizontalDragUpdate: (d) => _swipeUpdate(d.delta.dx),
                  onHorizontalDragEnd: (d) =>
                      _swipeEnd(d.velocity.pixelsPerSecond.dx),
                  child: CustomPaint(size: size, painter: _ZonePainter(this)),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Column(
                    key: _topKey,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => Navigator.of(context).maybePop(),
                            child: const Padding(
                              padding: EdgeInsets.all(8),
                              child: PxIcon('back'),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(child: _hud(z, s)),
                          const SizedBox(width: 8),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(() {
                              packOpen = true;
                              packAtCamp = false;
                            }),
                            child: PixelBox(
                              padding: const EdgeInsets.all(6),
                              child: const PxIcon('pack'),
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(() => journalOpen = true),
                            child: PixelBox(
                              padding: const EdgeInsets.all(6),
                              child: const PxIcon('book'),
                            ),
                          ),
                        ],
                      ),
                      if (objective != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: PixelBox(
                              color: Pal.panelLo,
                              shadow: false,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              child: PxText(
                                ':star: ${objective.text}',
                                style: const TextStyle(
                                  color: Pal.goldLight,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  if (s != null) _actionBar(s),
                ],
              ),
            ),
          ),
          if (s != null && s.heroDown) _fallenOverlay(),
          if (campOpen && s != null)
            CampOverlay(
              world: world,
              onRest: _rest,
              onPack: () => setState(() {
                campOpen = false;
                packOpen = true;
                packAtCamp = true;
              }),
              onClose: () => setState(() => campOpen = false),
            ),
          if (packOpen)
            InventoryOverlay(
              world: world,
              atCamp: packAtCamp,
              onChanged: () => setState(() {}),
              onUse: _drink,
              onClose: () => setState(() => packOpen = false),
            ),
          if (journalOpen)
            QuestLogOverlay(
              world: world,
              onClose: () => setState(() => journalOpen = false),
            ),
          if (dialogue != null && talking != null)
            DialogueOverlay(
              npc: talking!,
              dialogue: dialogue!,
              onClose: _endTalk,
            ),
        ],
      ),
    );
  }

  Widget _hud(Zone? z, ZoneSim? s) {
    return PixelBox(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ValueListenableBuilder<int>(
        valueListenable: turn,
        builder: (context, t, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    z?.name ?? '...',
                    style: const TextStyle(
                      color: Pal.gold,
                      fontSize: 18,
                      height: 1,
                    ),
                  ),
                ),
                PxText(
                  ':token: ${world.tokens}',
                  style: const TextStyle(color: Pal.goldLight, fontSize: 15),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Health and mana on one line, just above the quick bar.
  Widget _vitals() {
    return ValueListenableBuilder<int>(
      valueListenable: turn,
      builder: (context, t, _) => Row(
        children: [
          const PxIcon('heart'),
          const SizedBox(width: 4),
          Expanded(
            child: PxBar(
              value: world.hp / WorldState.maxHp,
              color: Pal.red,
              rows: 7,
            ),
          ),
          const SizedBox(width: 12),
          for (var i = 0; i < WorldState.maxMana; i++)
            Padding(
              padding: const EdgeInsets.only(left: 3),
              child: _ManaPip(filled: i < world.mana),
            ),
        ],
      ),
    );
  }

  Widget _actionBar(ZoneSim s) {
    return Padding(
      key: _barKey,
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _vitals(),
          const SizedBox(height: 6),
          QuickBar(
            pointAt: currentObjective(world)?.hint,
            world: world,
            selected: _quickKey,
            targeting: targeting,
            canCast: _spellReady,
            onSelect: _selectQuick,
            onUse: _useQuick,
          ),
        ],
      ),
    );
  }

  Widget _fallenOverlay() {
    final camp = world.camp;
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xCC1A1C2C),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PxIcon('skull', mult: 4),
              const SizedBox(height: 10),
              const Text(
                'You fell',
                style: TextStyle(color: Pal.red, fontSize: 40, height: 1),
              ),
              const SizedBox(height: 4),
              Text(
                camp == null
                    ? 'You wake at the edge of the meadow.'
                    : 'You wake by the last fire you rested at.',
                style: const TextStyle(color: Pal.dim, fontSize: 15),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: 200,
                child: GoldButton(label: 'Wake up', onTap: _wakeUp),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManaPip extends StatelessWidget {
  const _ManaPip({required this.filled});

  final bool filled;

  @override
  Widget build(BuildContext context) {
    final u = PixelUi.unit(context);
    return Container(
      width: 7 * u,
      height: 7 * u,
      decoration: BoxDecoration(
        color: filled ? const Color(0xFF78E6F0) : const Color(0xFF2C4A56),
        border: Border.all(color: Pal.ink, width: u),
      ),
    );
  }
}

class _ZonePainter extends CustomPainter {
  _ZonePainter(this.s) : super(repaint: s.tick);

  final _ZoneScreenState s;
  TerrainDraw? _terrain;
  final Map<String, TextPainter> _text = {};

  @override
  bool shouldRepaint(covariant _ZonePainter old) => true;

  TextPainter _pixelText(String t, double size, Color c) {
    if (_text.length > 80) _text.clear();
    return _text.putIfAbsent(
      '$t@$size@${c.toARGB32()}',
      () => TextPainter(
        text: TextSpan(
          text: t,
          style: TextStyle(
            fontFamily: 'VT323',
            fontSize: size,
            height: 1,
            color: c,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final art = PixelAssets.instance;
    final zone = s.zone;
    final sim = s.sim;
    if (art == null || zone == null || sim == null) return;
    final td = _terrain ??= TerrainDraw(art);
    final v = ZoneView(size, s._dpr, s.cam, zone, s._inset);
    final sc = v.scale;
    final time = s.time;
    // Screen shake, in whole art pixels.
    final amp = s.fx.shake * 3;
    final k = (time * 45).floor();
    canvas.save();
    if (amp > 0.3) {
      canvas.translate(
        ((hash01(k, 1, 5) * 2 - 1) * amp).round() * sc,
        ((hash01(k, 2, 5) * 2 - 1) * amp).round() * sc,
      );
    }
    final tint = zone.dark
        ? const ColorFilter.mode(Color(0xFF8C9CC0), BlendMode.modulate)
        : null;
    Offset snap(Offset p) => Offset(
      (p.dx * s._dpr).roundToDouble() / s._dpr,
      (p.dy * s._dpr).roundToDouble() / s._dpr,
    );

    // Which hexes could be on screen.
    final tl = v.toWorld(Offset.zero);
    final br = v.toWorld(size.bottomRight(Offset.zero));
    final r0 = (tl.dy / BoardLayout.rowH).floor() - 2;
    final r1 = (br.dy / BoardLayout.rowH).ceil() + 2;
    final visible = <Hex>[];
    for (var r = r0; r <= r1; r++) {
      final q0 = (tl.dx / BoardLayout.hexW - r / 2).floor() - 1;
      final q1 = (br.dx / BoardLayout.hexW - r / 2).ceil() + 1;
      for (var q = q0; q <= q1; q++) {
        if (sim.zone.tiles.containsKey(Hex(q, r))) visible.add(Hex(q, r));
      }
    }

    for (final h in visible) {
      final tile = sim.zone.tiles[h]!;
      final c = v.toScreen(hexWorld(h));
      final (cliffSE, cliffSW) = cliffsFor(
        (q, r) => sim.zone.tiles[Hex(q, r)]?.terrain,
        h.q,
        h.r,
        tile.terrain,
      );
      td.draw(
        canvas,
        c,
        sc,
        tile.terrain,
        h.q,
        h.r,
        time,
        filter: tint,
        cliffSE: cliffSE,
        cliffSW: cliffSW,
        openEdges: openEdgesFor(
          (q, r) => sim.zone.tiles.containsKey(Hex(q, r)),
          h.q,
          h.r,
        ),
      );
      if (tile.ford) {
        // A plank bridge laid over the water, with a post at each real end.
        td.blit(canvas, art.sprite('bridge'), c, -12, -8, sc);
        bool bridgeAt(int q, int r) => sim.zone.tiles[Hex(q, r)]?.ford ?? false;
        final post = art.sprite('bridge_post');
        if (!bridgeAt(h.q - 1, h.r)) td.blit(canvas, post, c, -12, -6, sc);
        if (!bridgeAt(h.q + 1, h.r)) td.blit(canvas, post, c, 8, -6, sc);
      }
      final portal = zone.portalAt(h);
      if (portal != null) {
        td.blit(canvas, art.sprite(portal.sprite), c, -8, -9, sc);
      }
    }

    void ringAt(Hex h, Color color) {
      final c = v.toScreen(hexWorld(h));
      final img = art.mask('ring');
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH(
          c.dx - HexArt.w / 2 * sc,
          c.dy - HexArt.h / 2 * sc,
          img.width * sc,
          img.height * sc,
        ),
        Paint()
          ..filterQuality = FilterQuality.none
          ..isAntiAlias = false
          ..colorFilter = ColorFilter.mode(color, BlendMode.srcIn),
      );
    }

    // Spell range: every hex a Fireball can reach.
    if (s.targeting) {
      final fill = art.mask((time * 3).floor().isEven ? 'fillA' : 'fillB');
      for (final h in visible) {
        if (!sim.canCastFireball(h)) continue;
        final c = v.toScreen(hexWorld(h));
        canvas.drawImageRect(
          fill,
          Rect.fromLTWH(0, 0, fill.width.toDouble(), fill.height.toDouble()),
          Rect.fromLTWH(
            c.dx - HexArt.w / 2 * sc,
            c.dy - HexArt.h / 2 * sc,
            fill.width * sc,
            fill.height * sc,
          ),
          Paint()
            ..filterQuality = FilterQuality.none
            ..isAntiAlias = false
            ..colorFilter = const ColorFilter.mode(
              Color(0x88FFA030),
              BlendMode.srcIn,
            ),
        );
        ringAt(h, const Color(0xFFFFA030));
      }
    }

    // A boss's spell in the making: the hexes it will hit blink red, faster
    // on the turn it fires.
    for (final e in sim.enemies) {
      if (e.telegraph.isEmpty) continue;
      final last = e.charge <= 1;
      final fill = art.mask(
        (time * (last ? 8 : 4)).floor().isEven ? 'fillA' : 'fillB',
      );
      for (final h in e.telegraph) {
        if (!visible.contains(h)) continue;
        final c = v.toScreen(hexWorld(h));
        canvas.drawImageRect(
          fill,
          Rect.fromLTWH(0, 0, fill.width.toDouble(), fill.height.toDouble()),
          Rect.fromLTWH(
            c.dx - HexArt.w / 2 * sc,
            c.dy - HexArt.h / 2 * sc,
            fill.width * sc,
            fill.height * sc,
          ),
          Paint()
            ..filterQuality = FilterQuality.none
            ..isAntiAlias = false
            ..colorFilter = ColorFilter.mode(
              Pal.red.withAlpha(0xAA),
              BlendMode.srcIn,
            ),
        );
        ringAt(h, Pal.red);
      }
    }

    // Campfires and things lying on the ground.
    for (final h in sim.source.camps) {
      if (!visible.contains(h)) continue;
      final c = v.toScreen(hexWorld(h));
      td.blit(canvas, art.sprite('campfire'), c, -6, -2, sc);
      final f = (time * 8).floor() % 3;
      td.blit(canvas, art.sprite('flame', 'f$f'), c, -6, -12, sc);
    }
    for (final item in sim.groundItems) {
      if (!visible.contains(item.hex)) continue;
      final c = v.toScreen(hexWorld(item.hex));
      final bob = (time * 3).floor().isEven ? 0.0 : 1.0;
      td.blit(canvas, art.icon(itemOf(item.itemId).icon), c, -6, -9 - bob, sc);
      if ((time * 2).floor() % 4 == 0) {
        td.rect(canvas, c, 4, -9, 1, 1, sc, Colors.white);
      }
    }
    for (final h in sim.fire.keys) {
      if (!visible.contains(h)) continue;
      final c = v.toScreen(hexWorld(h));
      const spots = [Offset(-11, -4), Offset(-2, -9), Offset(1, -2)];
      for (var i = 0; i < spots.length; i++) {
        final f = ((time * 8) + i * 1.3 + h.q).floor() % 3;
        td.blit(
          canvas,
          art.sprite('flame', 'f$f'),
          c,
          spots[i].dx,
          spots[i].dy,
          sc,
        );
      }
    }

    // Travel route.
    final dest = s.destination;
    if (dest != null) {
      for (final h in s.path) {
        td.rect(canvas, v.toScreen(hexWorld(h)), -1, -1, 2, 2, sc, Pal.gold);
      }
      final c = v.toScreen(hexWorld(dest));
      final img = art.mask('ring');
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH(
          c.dx - HexArt.w / 2 * sc,
          c.dy - HexArt.h / 2 * sc,
          img.width * sc,
          img.height * sc,
        ),
        Paint()
          ..filterQuality = FilterQuality.none
          ..isAntiAlias = false
          ..colorFilter = const ColorFilter.mode(Pal.gold, BlendMode.srcIn),
      );
    }

    // Creatures, back to front.
    final order = <({double y, void Function() draw})>[];
    final walking = s.path.isNotEmpty;
    for (final e in sim.enemies) {
      order.add((
        y: e.vis.dy,
        draw: () => _enemy(canvas, td, art, v, e, snap, time),
      ));
    }
    for (final n in sim.source.npcs) {
      if (!visible.contains(n.hex)) continue;
      order.add((
        y: hexWorld(n.hex).dy,
        draw: () {
          final ground = snap(v.toScreen(hexWorld(n.hex)));
          final img = art.unit(
            n.unit,
            Team.player,
            (time * 1.5 + n.hex.q).floor().isEven ? 'idle0' : 'idle1',
          );
          final shadow = art.mask('shadowS');
          td.blit(
            canvas,
            shadow,
            ground,
            -(shadow.width / 2).floorToDouble(),
            4,
            sc,
          );
          td.blit(
            canvas,
            img,
            ground,
            -(img.width / 2).floorToDouble(),
            6 - img.height.toDouble(),
            sc,
          );
          final mark = npcMark(n, s.world);
          if (mark != null) {
            final m = art.sprite(mark);
            final bounce = (time * 4).floor().isOdd ? 1.0 : 0.0;
            td.blit(
              canvas,
              m,
              ground,
              -(m.width / 2).floorToDouble(),
              6 - img.height - 3 - m.height - bounce,
              sc,
            );
          }
        },
      ));
    }
    order.add((
      y: s.heroWorld.dy,
      draw: () {
        final ground = snap(v.toScreen(s.heroWorld + s.heroKick));
        final bob = walking && (time * 12).floor().isOdd ? 1.0 : 0.0;
        final frame = (time * 2).floor().isEven ? 'idle0' : 'idle1';
        final img = art.unit(UnitType.hero, Team.player, frame);
        final shadow = art.mask('shadowS');
        td.blit(
          canvas,
          shadow,
          ground,
          -(shadow.width / 2).floorToDouble(),
          4,
          sc,
        );
        td.blit(
          canvas,
          img,
          ground,
          -(img.width / 2).floorToDouble(),
          6 - img.height - bob,
          sc,
          filter: s.heroFlash > 0
              ? const ColorFilter.mode(Colors.white, BlendMode.srcATop)
              : null,
        );
      },
    ));
    order.sort((a, b) => a.y.compareTo(b.y));
    for (final o in order) {
      o.draw();
    }

    // Corner brackets: a reticle around a world position.
    void brackets(Offset centre, double half, Color color) {
      for (final sx in const [-1, 1]) {
        for (final sy in const [-1, 1]) {
          final corner = Offset(
            (centre.dx + sx * half).roundToDouble(),
            (centre.dy + sy * half).roundToDouble(),
          );
          final c = v.toScreen(corner);
          td.rect(canvas, c, sx < 0 ? 0 : -2, 0, 3, 1, sc, color);
          td.rect(canvas, c, 0, sy < 0 ? 0 : -2, 1, 3, sc, color);
        }
      }
    }

    // Warnings: who can hit you this turn, and who you can hit.
    if (!sim.heroDown) {
      final heroChest = s.heroWorld + s.heroKick + const Offset(0, -8);
      final blink = (time * 6).floor().isEven;
      var aimed = false;
      for (final e in sim.enemies) {
        if (!sim.threatens(e)) continue;
        if (e.stats.maxRange > 1) {
          // A marching dotted aim line from the archer to you.
          final from = e.vis + const Offset(0, -8);
          final d = heroChest - from;
          final steps = math.max(2, (d.distance / 4).floor());
          final march = (time * 10).floor();
          for (var i = 1; i < steps; i++) {
            if ((i + march) % 2 != 0) continue;
            final p = from + d * (i / steps);
            td.rect(
              canvas,
              v.toScreen(Offset(p.dx.roundToDouble(), p.dy.roundToDouble())),
              0,
              0,
              2,
              2,
              sc,
              blink ? const Color(0xFFE86A5A) : const Color(0xFFFFB142),
            );
          }
          aimed = true;
        } else {
          // Melee: a pulsing red hex under whoever is about to strike.
          final c = v.toScreen(hexWorld(e.hex));
          final img = art.mask('ring');
          canvas.drawImageRect(
            img,
            Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
            Rect.fromLTWH(
              c.dx - HexArt.w / 2 * sc,
              c.dy - HexArt.h / 2 * sc,
              img.width * sc,
              img.height * sc,
            ),
            Paint()
              ..filterQuality = FilterQuality.none
              ..isAntiAlias = false
              ..colorFilter = ColorFilter.mode(
                blink ? const Color(0xFFE86A5A) : const Color(0xFF962832),
                BlendMode.srcIn,
              ),
          );
          aimed = true;
        }
      }
      if (aimed) {
        brackets(heroChest, blink ? 10 : 11, const Color(0xFFE86A5A));
      }
      // Targets in reach of the equipped weapon.
      for (final e in sim.enemies) {
        if (!sim.reaches(e) || s.targeting) continue;
        final centre = e.vis + e.kick + const Offset(0, -8);
        brackets(centre, 9, Pal.gold);
        if (!e.hostile && !e.stats.inert) {
          final fs = 16 * sc;
          final label = _pixelText('x2', fs, Pal.goldLight);
          final line = _pixelText('x2', fs, Pal.ink);
          final top =
              v.toScreen(e.vis + e.kick) +
              Offset(0, (-e.stats.maxHp.clamp(0, 99) * 0 - 30) * sc);
          final o =
              top - Offset((label.width / 2).floorToDouble(), label.height / 2);
          for (final d in const [
            Offset(-1, 0),
            Offset(1, 0),
            Offset(0, -1),
            Offset(0, 1),
          ]) {
            line.paint(canvas, o + d * sc);
          }
          label.paint(canvas, o);
        }
      }
    }

    // Swings, arrows, spells, sparks and dying creatures.
    s.fx.paint(canvas, td, art, v.toScreen, sc);

    // Darkness closes in around the hero in caves, in whole-hex steps.
    if (zone.dark) {
      final fa = art.mask('fillA');
      final fb = art.mask('fillB');
      final solid = Paint()
        ..filterQuality = FilterQuality.none
        ..isAntiAlias = false
        ..colorFilter = const ColorFilter.mode(
          Color(0xFF080A12),
          BlendMode.srcIn,
        );
      void drawMask(ui.Image mask, Offset c) {
        canvas.drawImageRect(
          mask,
          Rect.fromLTWH(0, 0, mask.width.toDouble(), mask.height.toDouble()),
          Rect.fromLTWH(
            c.dx - HexArt.w / 2 * sc,
            c.dy - HexArt.h / 2 * sc,
            mask.width * sc,
            mask.height * sc,
          ),
          solid,
        );
      }

      for (final h in visible) {
        final d = h.distanceTo(sim.hero);
        if (d <= 3) continue;
        final c = v.toScreen(hexWorld(h));
        drawMask(fa, c);
        if (d > 4) drawMask(fb, c);
      }
    }

    // Where the active quest wants you to go.
    final objective = currentObjective(sim.world);
    final goal = objective == null ? null : markerHex(zone, objective, s.zones);
    if (goal != null) {
      final p = v.toScreen(hexWorld(goal));
      final inset = Rect.fromLTWH(0, 0, size.width, size.height).deflate(30);
      if (inset.contains(p)) {
        final bob = (time * 4).floor().isOdd ? 2.0 : 0.0;
        td.blit(canvas, art.sprite('cursor'), snap(p), -5, -30 + bob, sc);
      } else {
        // An arrow on the screen edge, pointing the way.
        final centre = size.center(Offset.zero);
        final dir = p - centre;
        final k = (math.atan2(dir.dy, dir.dx) / (math.pi / 2)).round();
        final edge = Offset(
          p.dx.clamp(inset.left, inset.right),
          p.dy.clamp(inset.top, inset.bottom),
        );
        final arrow = art.sprite('back');
        canvas.save();
        canvas.translate(snap(edge).dx, snap(edge).dy);
        // The sprite points left; turn it in quarter turns so it stays crisp.
        canvas.rotate(k * math.pi / 2 - math.pi);
        td.blit(
          canvas,
          arrow,
          Offset.zero,
          -arrow.width / 2,
          -arrow.height / 2,
          sc,
        );
        canvas.restore();
      }
    }

    // Floating numbers.
    for (final t in s.texts) {
      if (t.age < t.delay) continue;
      final age = t.age - t.delay;
      final pos = snap(v.toScreen(t.world + Offset(0, -age * 18)));
      final fs = 16 * sc;
      final fill = _pixelText(t.text, fs, t.color);
      final line = _pixelText(t.text, fs, Pal.ink);
      final o = pos - Offset((fill.width / 2).floorToDouble(), fill.height / 2);
      for (final d in const [
        Offset(-1, 0),
        Offset(1, 0),
        Offset(0, -1),
        Offset(0, 1),
      ]) {
        line.paint(canvas, o + d * sc);
      }
      fill.paint(canvas, o);
    }
    canvas.restore();
  }

  void _enemy(
    Canvas canvas,
    TerrainDraw td,
    PixelAssets art,
    ZoneView v,
    Enemy e,
    Offset Function(Offset) snap,
    double time,
  ) {
    final sc = v.scale;
    final ground = snap(v.toScreen(e.vis + e.kick));
    final asleep = e.awareness == Awareness.asleep;
    final frame = !asleep && (time * 2 + e.id * 0.37).floor().isEven
        ? 'idle0'
        : 'idle1';
    final img = art.unit(e.type, Team.enemy, frame);
    final shadow = art.mask(img.width > 16 ? 'shadowL' : 'shadowS');
    td.blit(canvas, shadow, ground, -(shadow.width / 2).floorToDouble(), 4, sc);
    // Sleepers are drawn dimmed; the hurt flash is white.
    final filter = e.flash > 0
        ? const ColorFilter.mode(Colors.white, BlendMode.srcATop)
        : asleep
        ? const ColorFilter.mode(Color(0x8826363E), BlendMode.srcATop)
        : null;
    final top = 6 - img.height.toDouble();
    td.blit(
      canvas,
      img,
      ground,
      -(img.width / 2).floorToDouble(),
      top,
      sc,
      filter: filter,
    );

    // Health pips once it has been hurt.
    final max = e.maxHp;
    var iconTop = top - 4;
    if (e.hp < max) {
      final w = max * 2 + 2;
      td.rect(
        canvas,
        ground,
        -(w / 2).floorToDouble(),
        top - 4,
        w,
        4,
        sc,
        Pal.ink,
      );
      for (var i = 0; i < max; i++) {
        td.rect(
          canvas,
          ground,
          -(w / 2).floorToDouble() + 1 + i * 2,
          top - 3,
          1,
          2,
          sc,
          i < e.hp ? Pal.red : const Color(0xFF3A3E52),
        );
      }
      iconTop -= 5;
    }

    // Burning: a flame beside it, one pip per turn left.
    if (e.burn > 0) {
      final b = art.sprite('burn');
      final x = (img.width / 2).ceilToDouble() + 1;
      td.blit(canvas, b, ground, x, top, sc);
      for (var i = 0; i < e.burn; i++) {
        td.rect(
          canvas,
          ground,
          x + i * 2,
          top + b.height + 1,
          1,
          1,
          sc,
          Pal.gold,
        );
      }
    }

    // What it is thinking.
    final mark = switch (e.awareness) {
      Awareness.alert => 'alert',
      Awareness.search => 'search',
      Awareness.asleep => 'sleep',
      _ => null,
    };
    if (mark != null) {
      final m = art.sprite(mark);
      final bounce = e.awareness == Awareness.alert && (time * 6).floor().isOdd
          ? 1.0
          : 0.0;
      td.blit(
        canvas,
        m,
        ground,
        -(m.width / 2).floorToDouble(),
        iconTop - m.height - bounce,
        sc,
      );
    }
  }
}
