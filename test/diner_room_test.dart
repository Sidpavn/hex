// The staff room behind a door in the back wall: a computer with programs, a
// sofa for tired staff, and a bank that lends and is paid back each night.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/data/storage.dart';
import 'package:hex/diner/advice.dart';
import 'package:hex/diner/bank.dart';
import 'package:hex/diner/build_screen.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/traits.dart';
import 'package:hex/diner/goals.dart';
import 'package:hex/diner/recipes.dart';
import 'package:hex/diner/service.dart';
import 'package:hex/diner/room_screen.dart';
import 'package:hex/diner/staff.dart';
import 'package:hex/diner/terminal_screen.dart';
import 'package:hex/diner/room.dart';
import 'package:hex/diner/staff_room.dart';
import 'package:hex/main.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';
import 'package:hex/ui/pixel/pixel_ui.dart' show PxText;
import 'support/office.dart';

Diner cafe({int level = 5, int lounge = 0, int cooks = 2, int day = 3}) {
  final d = Diner(
    coins: 100000,
    owned: {0, 1},
    progress: Progress(level: level, reputation: 70, day: day),
  );
  d.progress.upgrades[Upgrade.lounge] = lounge;
  d.roster.employees.clear();
  d.progress.upgrades[Upgrade.staff] = cooks - 1;
  for (var i = 0; i < cooks; i++) {
    d.roster.employees.add(
      Staff(
        id: 70 + i,
        name: 'S$i',
        stats: {Stat.cooking: 5, Stat.speed: 5, Stat.service: 5, Stat.charm: 5},
        potential: {for (final s in Stat.values) s: 10},
      ),
    );
  }
  d.place(Kind.grill, const Cell(1, 3), Dir.sw);
  d.place(Kind.grill, const Cell(2, 3), Dir.sw);
  d.place(Kind.counter, const Cell(10, 7), Dir.nw);
  d.place(Kind.counter, const Cell(10, 6), Dir.nw);
  for (final t in const [Cell(3, 5), Cell(7, 5)]) {
    d.place(Kind.table, t);
    d.place(Kind.chair, Cell(t.x - 1, t.y), Dir.se);
    d.place(Kind.chair, Cell(t.x + 1, t.y), Dir.nw);
  }
  d.menu();
  d.ensureDoor();
  d.syncSofas();
  d.clearUndo();
  return d;
}

DinerSim play(Diner d, {int seed = 1}) {
  final sim = DinerSim(d, seed: seed);
  while (!sim.finished && sim.ticks < 2500) {
    sim.tick();
  }
  return sim;
}

void main() {
  group('the room', () {
    test('the sofas are an upgrade with three levels', () {
      final def = upgradeDefs[Upgrade.lounge]!;
      expect(def.name, 'Staff sofas');
      expect(def.max, 3);
      expect(cafe().loungeLevel, 0);
      expect(cafe(lounge: 2).loungeLevel, 2);
      expect(upgradeDefs[Upgrade.staff]!.name, 'Bigger team');
    });

    test('every restaurant has a door, from the start', () {
      expect(Diner.starter().staffDoor, isNotNull);
      final d = cafe();
      final door = d.staffDoorItem!;
      expect(door.kind, Kind.staffDoor);
      expect(door.facing, Dir.sw);
      expect(d.isInside(door.at), isTrue);
      expect(d.isInside(Cell(door.at.x, door.at.y - 1)), isFalse);
    });

    test('it goes nearest the middle that is free', () {
      final d = cafe();
      expect(d.staffDoor!.x, (Diner.left + d.right) ~/ 2);
      final e = Diner(coins: 1000, owned: {0, 1});
      final spot = e.doorSpot()!;
      e.place(Kind.counter, spot);
      final next = e.doorSpot()!;
      expect(next, isNot(spot));
      expect((next.x - spot.x).abs(), 1);
    });

    test('it can be hung anywhere along the back wall', () {
      final d = cafe();
      final door = d.staffDoorItem!;
      for (var x = Diner.left; x <= d.right; x++) {
        final c = Cell(x, 3);
        if (d.objectAt(c) != null) continue;
        expect(d.moveTo(door, c), PlaceResult.ok, reason: 'column $x');
        expect(d.staffDoor, c);
      }
    });

    test('but not away from it', () {
      final d = cafe();
      final door = d.staffDoorItem!;
      expect(d.moveTo(door, Cell(door.at.x, 5)), PlaceResult.backWallOnly);
      expect(d.relocate(door, Cell(1, 6), Dir.se), PlaceResult.backWallOnly);
      expect(
        PlaceResult.backWallOnly.message,
        'The door goes in the back wall',
      );
    });

    test('one door only', () {
      expect(cafe().check(Kind.staffDoor, Cell(2, 3)), PlaceResult.oneDoor);
    });

    test('it is moved, not sold, and cannot be turned or grouped', () {
      final d = cafe();
      final door = d.staffDoorItem!;
      d.sell(door);
      expect(d.staffDoorItem, door);
      d.sellGroup([door]);
      expect(d.staffDoorItem, door);
      expect(d.checkGroup([door], const GroupMove(dx: 1)), PlaceResult.hang);
      expect(fixtureDefs[Kind.staffDoor]!.turns, isFalse);
      expect(d.rotate(door), PlaceResult.backWallOnly);
    });

    test('nothing can stand in front of it, or hang on it', () {
      final d = cafe();
      final door = d.staffDoor!;
      expect(d.check(Kind.counter, door), PlaceResult.entrance);
      expect(d.check(Kind.tv, door), PlaceResult.taken);
      expect(d.check(Kind.tv, Cell(door.x + 1, door.y)), PlaceResult.ok);
    });

    test('and it cannot be hung over something standing there', () {
      final d = cafe();
      final door = d.staffDoorItem!;
      final c = Cell(door.at.x + 1, 3);
      d.place(Kind.counter, c);
      expect(d.moveTo(door, c), PlaceResult.taken);
    });

    test('a group cannot be moved onto it either', () {
      final d = cafe();
      final p = d.objectAt(const Cell(2, 3))!;
      final move = GroupMove(dx: d.staffDoor!.x - p.at.x, dy: 0);
      expect(d.checkGroup([p], move), PlaceResult.entrance);
    });

    test('it moves back with the wall when the room grows', () {
      final d = cafe(level: 9);
      final door = d.staffDoorItem!;
      final x = door.at.x;
      expect(door.at.y, 3);
      d.owned.add(2);
      d.unlock(4);
      expect(d.hangs(door.at, Dir.sw), isTrue);
      expect(door.at.x, x);
      expect(door.at.y, lessThan(3));
    });

    test('so does a TV', () {
      final d = cafe(level: 9);
      d.coins = 100000;
      d.place(Kind.tv, Cell(6, 3));
      final tv = d.items.last;
      d.unlock(2);
      expect(d.hangs(tv.at, tv.facing), isTrue);
      expect(tv.at.y, -1);
      expect(tv.at.x, 6);
    });

    test('an old save with no door or room gets them', () {
      final d = cafe();
      final json = d.toJson();
      (json['items'] as List).removeWhere(
        (e) => (e as Map)['k'] == 'staffDoor',
      );
      json.remove('room');
      final back = Diner.fromJson(json);
      expect(back.staffDoorItem, isNotNull);
      expect(back.room.computer, isNotNull);
      final fine = Diner.fromJson(cafe(lounge: 2).toJson());
      expect(fine.items.where((p) => p.kind == Kind.staffDoor).length, 1);
      expect(fine.room.sofaCount, 2);
    });

    test('it has pictures', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final art = await DinerArt.load();
      for (final n in [
        'staff_door',
        'office_pc_sw',
        'office_pc_se',
        'office_pc_nw',
        'office_pc_ne',
        'sofa_sw',
        'sofa_se',
        'sofa_nw',
        'sofa_ne',
      ]) {
        expect(art.sprite(n).blank, isFalse, reason: n);
      }
    });
  });

  group('what is in the room', () {
    StaffRoom fresh() => StaffRoom.starter();

    test('it starts with a computer, a plant and a rug', () {
      final r = fresh();
      expect(r.computer, isNotNull);
      expect(
        r.items.map((i) => i.kind),
        containsAll([RoomKind.computer, RoomKind.plant, RoomKind.rug]),
      );
      expect(r.sofaCount, 0);
      expect(StaffRoom.cols, 4);
      expect(StaffRoom.rows, 5);
    });

    test('things stay inside, and do not stack', () {
      final r = fresh();
      expect(
        r.check(RoomKind.plant, const Cell(4, 0), sofas: 1),
        RoomResult.outside,
      );
      expect(
        r.check(RoomKind.plant, const Cell(-1, 2), sofas: 1),
        RoomResult.outside,
      );
      expect(
        r.check(RoomKind.plant, const Cell(3, 0), sofas: 1),
        RoomResult.taken,
      );
      expect(
        r.check(RoomKind.plant, const Cell(2, 2), sofas: 1),
        RoomResult.ok,
      );
    });

    test('a rug lies under things, but not under another rug', () {
      final r = fresh();
      expect(r.check(RoomKind.sofa, const Cell(1, 3), sofas: 1), RoomResult.ok);
      expect(
        r.check(RoomKind.rug, const Cell(1, 3), sofas: 1),
        RoomResult.taken,
      );
      expect(r.pickAt(const Cell(1, 3))!.kind, RoomKind.rug);
      r.put(RoomKind.sofa, const Cell(1, 3));
      expect(r.pickAt(const Cell(1, 3))!.kind, RoomKind.sofa);
    });

    test('there is one computer, and as many sofas as the upgrade gives', () {
      final r = fresh();
      expect(
        r.check(RoomKind.computer, const Cell(0, 4), sofas: 3),
        RoomResult.onlyOne,
      );
      expect(
        r.check(RoomKind.sofa, const Cell(0, 4), sofas: 0),
        RoomResult.full,
      );
      r.put(RoomKind.sofa, const Cell(0, 4));
      expect(
        r.check(RoomKind.sofa, const Cell(1, 4), sofas: 1),
        RoomResult.full,
      );
      expect(r.check(RoomKind.sofa, const Cell(1, 4), sofas: 2), RoomResult.ok);
    });

    test('the computer and sofas are moved and turned, not sold', () {
      final d = cafe(lounge: 1);
      final pc = d.room.computer!;
      final sofa = d.room.items.firstWhere((i) => i.kind == RoomKind.sofa);
      final coins = d.coins;
      d.roomSell(pc);
      d.roomSell(sofa);
      expect(d.room.items, contains(pc));
      expect(d.room.items, contains(sofa));
      expect(d.coins, coins);
      expect(d.roomMove(pc, const Cell(0, 2), Dir.se), RoomResult.ok);
      expect(pc.at, const Cell(0, 2));
      expect(pc.facing, Dir.se);
    });

    test('a plant is bought and sold at half', () {
      final d = cafe();
      final before = d.coins;
      expect(
        d.roomPlace(RoomKind.plant, const Cell(2, 2), Dir.sw),
        RoomResult.ok,
      );
      expect(d.coins, before - 15);
      final plant = d.room.pickAt(const Cell(2, 2))!;
      d.roomSell(plant);
      expect(d.coins, before - 15 + 7);
      expect(d.room.pickAt(const Cell(2, 2)), isNull);
      d.coins = 3;
      expect(
        d.roomPlace(RoomKind.plant, const Cell(2, 2), Dir.sw),
        RoomResult.broke,
      );
    });

    test('things that do not turn keep facing the same way', () {
      final d = cafe();
      d.roomPlace(RoomKind.plant, const Cell(2, 2), Dir.ne);
      expect(d.room.pickAt(const Cell(2, 2))!.facing, Dir.sw);
      expect(roomDefs[RoomKind.computer]!.turns, isTrue);
      expect(roomDefs[RoomKind.sofa]!.turns, isTrue);
      expect(roomDefs[RoomKind.plant]!.turns, isFalse);
    });

    test('a new sofa from the upgrade is put in the room by itself', () {
      final d = cafe();
      expect(d.room.sofaCount, 0);
      d.progress.upgrades[Upgrade.lounge] = 1;
      d.syncSofas();
      expect(d.room.sofaCount, 1);
      d.progress.upgrades[Upgrade.lounge] = 3;
      d.syncSofas();
      expect(d.room.sofaCount, 3);
      d.syncSofas();
      expect(d.room.sofaCount, 3);
    });

    test('the room is saved, turned things and all', () {
      final d = cafe(lounge: 2);
      final sofa = d.room.items.firstWhere((i) => i.kind == RoomKind.sofa);
      d.roomMove(sofa, const Cell(2, 4), Dir.ne);
      final back = Diner.fromJson(d.toJson());
      final s = back.room.pickAt(const Cell(2, 4))!;
      expect(s.kind, RoomKind.sofa);
      expect(s.facing, Dir.ne);
      expect(back.room.sofaCount, 2);
      expect(back.room.computer, isNotNull);
    });

    test('a damaged room cannot put things outside it', () {
      final r = StaffRoom.fromJson({
        'items': [
          {'k': 'plant', 'x': 9, 'y': 9, 'f': 'sw'},
          {'k': 'plant', 'x': 1, 'y': 1, 'f': 'sw'},
          {'k': 'nonsense', 'x': 0, 'y': 0},
          {'k': 'sofa', 'x': 2, 'y': 2, 'f': 'se'},
        ],
      }, sofas: 0);
      expect(r.items.where((i) => i.kind == RoomKind.plant).length, 1);
      expect(r.sofaCount, 0, reason: 'no sofa is allowed');
      expect(r.computer, isNotNull, reason: 'a computer is put back');
    });
  });

  group('the picture', () {
    test('the room fills its box evenly, so it is centred', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final art = await DinerArt.load();
      final size = StaffRoomPainter.size(art);
      final o = StaffRoomPainter.origin(art);
      double left = 1e9, right = -1e9, top = 1e9, bottom = -1e9;
      void take(String name, Offset at) {
        final s = art.sprite(name);
        final x = o.dx + at.dx - s.ax;
        final y = o.dy + at.dy - s.ay;
        left = x < left ? x : left;
        top = y < top ? y : top;
        right = x + s.width > right ? x + s.width : right;
        bottom = y + s.height > bottom ? y + s.height : bottom;
      }

      for (final (n, c) in StaffRoomPainter.shell()) {
        take(n, StaffRoomPainter.vertex(c.x, c.y));
      }
      expect(left, greaterThanOrEqualTo(0));
      expect(top, greaterThanOrEqualTo(0));
      expect(right, lessThanOrEqualTo(size.width));
      expect(bottom, lessThanOrEqualTo(size.height));
      expect(
        left,
        closeTo(size.width - right, 0.5),
        reason: 'same either side',
      );
    });

    test('a tap on a tile finds that tile', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final art = await DinerArt.load();
      for (var y = 0; y < StaffRoom.rows; y++) {
        for (var x = 0; x < StaffRoom.cols; x++) {
          final p = StaffRoomPainter.centre(art, Cell(x, y));
          expect(StaffRoomPainter.cellAt(art, p), Cell(x, y));
        }
      }
    });
  });

  group('tiring', () {
    test('everyone starts a day full of energy, and work wears it down', () {
      final sim = DinerSim(cafe(cooks: 1), seed: 2);
      expect(sim.workers.single.energy, 100);
      for (var i = 0; i < 120; i++) {
        sim.tick();
      }
      expect(sim.workers.single.energy, lessThan(100));
      expect(sim.workers.single.energy, greaterThan(0));
    });

    test('busy people tire faster than idle ones', () {
      final busy = DinerSim(cafe(cooks: 1), seed: 2);
      for (var i = 0; i < 200; i++) {
        busy.tick();
      }
      final idle = DinerSim(cafe(cooks: 1, day: 3), seed: 2);
      // Nobody comes: close the doors by marking the layout unfit.
      idle.workers.single.energy = 100;
      for (var i = 0; i < 5; i++) {
        idle.tick();
      }
      expect(idle.workers.single.energy, greaterThan(99));
    });

    test('hot-headed people tire faster, loyal ones slower', () {
      double after(Trait? t) {
        final d = cafe(cooks: 1);
        if (t != null) d.roster.employees.single.traits.add(t);
        final sim = DinerSim(d, seed: 2);
        for (var i = 0; i < 150; i++) {
          sim.tick();
        }
        return sim.workers.single.energy;
      }

      expect(after(Trait.hotHeaded), lessThan(after(null)));
      expect(after(Trait.loyal), greaterThan(after(null)));
    });

    test('below 40 they walk and handle plates more slowly', () {
      final sim = DinerSim(cafe(cooks: 1), seed: 2);
      final w = sim.workers.single;
      w.energy = 80;
      expect(w.isTired, isFalse);
      w.energy = 39;
      expect(w.isTired, isTrue);
      // A fresh worker and a tired one, over the same ten steps.
      double paceOf(Worker w) {
        var steps = 0;
        for (var i = 0; i < 100; i++) {
          w.path = [const Cell(1, 1), const Cell(1, 2)];
          if (w.walk()) steps++;
        }
        return steps.toDouble();
      }

      final fresh = Worker(w.staff, w.cell)..energy = 100;
      final tired = Worker(w.staff, w.cell)..energy = 20;
      expect(paceOf(tired), lessThan(paceOf(fresh)));
    });
  });

  group('resting', () {
    test('with no sofa nobody goes anywhere to rest', () {
      final sim = DinerSim(cafe(lounge: 0), seed: 2);
      sim.workers.first.energy = 20;
      for (var i = 0; i < 30; i++) {
        sim.tick();
        expect(
          sim.workers.every(
            (w) => w.state != WorkState.toRest && w.state != WorkState.resting,
          ),
          isTrue,
        );
      }
    });

    test('a tired person with nothing to do walks to the door and goes in', () {
      final sim = DinerSim(cafe(lounge: 1), seed: 2);
      final w = sim.workers.first;
      w.energy = 30;
      var went = false;
      var rested = false;
      for (var i = 0; i < 40; i++) {
        sim.tick();
        if (w.state == WorkState.toRest) went = true;
        if (w.state == WorkState.resting) {
          rested = true;
          break;
        }
      }
      expect(went, isTrue);
      expect(rested, isTrue);
      expect(w.cell, sim.diner.staffDoor!, reason: 'at the door');
    });

    test('inside, they cannot be seen on the floor', () {
      final sim = DinerSim(cafe(lounge: 1), seed: 2);
      final w = sim.workers.first;
      w.energy = 30;
      while (w.state != WorkState.resting && sim.ticks < 60) {
        sim.tick();
      }
      expect(w.state, WorkState.resting);
      final seen = sim.actors(1).where((a) => a.name.startsWith('chef'));
      expect(
        seen.length,
        lessThan(sim.workers.where((x) => x.sprite == 'chef').length),
      );
    });

    test('they come back out rested, when nobody is waiting for food', () {
      // A restaurant that cannot open has nobody to wait on.
      final d = cafe(lounge: 1)
        ..items.removeWhere((p) => p.kind == Kind.counter);
      final sim = DinerSim(d, seed: 2);
      final w = sim.workers.first;
      w.energy = 30;
      while (w.state != WorkState.resting && sim.ticks < 60) {
        sim.tick();
      }
      var ticks = 0;
      while (w.state == WorkState.resting && ticks < 200) {
        sim.tick();
        ticks++;
      }
      expect(w.state, isNot(WorkState.resting));
      expect(w.energy, greaterThanOrEqualTo(85));
      expect(ticks, inInclusiveRange(40, 80), reason: 'about a minute of rest');
    });

    test('and sooner if there is food nobody is cooking', () {
      final sim = DinerSim(cafe(lounge: 1, cooks: 1), seed: 2);
      final w = sim.workers.first;
      w.energy = 30;
      var cut = false;
      for (var i = 0; i < 200 && !cut; i++) {
        final was = w.state == WorkState.resting;
        sim.tick();
        if (was && w.state != WorkState.resting && w.energy < 85) cut = true;
      }
      expect(cut, isTrue);
      expect(w.energy, greaterThanOrEqualTo(Worker.tired));
    });

    test('only as many as there are sofas', () {
      final sim = DinerSim(cafe(lounge: 1, cooks: 3), seed: 2);
      for (final w in sim.workers) {
        w.energy = 20;
      }
      var most = 0;
      for (var i = 0; i < 30; i++) {
        sim.tick();
        most = most < _inRoom(sim) ? _inRoom(sim) : most;
      }
      expect(most, 1);
      final big = DinerSim(cafe(lounge: 3, cooks: 3), seed: 2);
      for (final w in big.workers) {
        w.energy = 20;
      }
      var many = 0;
      for (var i = 0; i < 30; i++) {
        big.tick();
        many = many < _inRoom(big) ? _inRoom(big) : many;
      }
      expect(many, greaterThan(1));
    });

    test('someone on the window does not leave it', () {
      final d = cafe(lounge: 1, cooks: 2);
      d.owned.add(1);
      d.place(Kind.window, Cell(d.right, 3));
      d.roster.employees.first.duty = Kind.window;
      final sim = DinerSim(d, seed: 2);
      sim.workers.first.energy = 10;
      for (var i = 0; i < 40; i++) {
        sim.tick();
        expect(sim.workers.first.state, isNot(WorkState.resting));
      }
    });

    test('a busy day with a room ends with a better rested team', () {
      double left(int lounge) {
        var e = 0.0;
        for (final seed in [1, 2, 3]) {
          final sim = play(cafe(lounge: lounge, cooks: 1, day: 5), seed: seed);
          e += sim.workers.fold(0.0, (a, w) => a + w.energy);
        }
        return e;
      }

      expect(left(2), greaterThan(left(0)));
    });
  });

  group('the bank', () {
    test('three loans, each opening at a higher level', () {
      expect(Bank.offers.map((o) => o.amount), [100, 250, 500]);
      expect(Bank.offers.map((o) => o.level), [2, 3, 5]);
      expect(Bank.offers.first.owed, 115);
      expect(Bank.feeOn(Bank.offers.last), 75);
    });

    test('a fifth is due each night, at least ten, never more than owed', () {
      expect(Bank.due(0), 0);
      expect(Bank.due(115), 23);
      expect(Bank.due(30), 10);
      expect(Bank.due(6), 6);
    });

    test('borrowing puts coins in the till and the debt on the books', () {
      final d = cafe(level: 3)..coins = 50;
      final o = Bank.offers[1];
      expect(d.whyNotLend(o), isNull);
      expect(d.borrow(o), isTrue);
      expect(d.coins, 300);
      expect(d.loan, 288);
    });

    test('one loan at a time, and only at the right level', () {
      final d = cafe(level: 2);
      expect(d.whyNotLend(Bank.offers[1]), 'Opens at level 3');
      expect(d.borrow(Bank.offers[1]), isFalse);
      expect(d.borrow(Bank.offers[0]), isTrue);
      expect(d.whyNotLend(Bank.offers[0]), 'Pay off what you owe first');
      expect(d.borrow(Bank.offers[0]), isFalse);
      expect(cafe(level: 1).whyNotLend(Bank.offers[0]), 'Opens at level 2');
    });

    test('paying back takes only what there is', () {
      final d = cafe(level: 2)..coins = 0;
      d.borrow(Bank.offers[0]);
      d.coins = 40;
      expect(d.repay(100), 40);
      expect(d.loan, 75);
      expect(d.coins, 0);
      expect(d.repay(10), 0);
      d.coins = 500;
      expect(d.repay(1000), 75);
      expect(d.loan, 0);
      expect(d.loanLate, 0);
    });

    test('each night the bank takes its fifth, after the wages', () {
      final d = cafe(level: 3, day: 4)..coins = 1000;
      d.borrow(Bank.offers[0]);
      final owed = d.loan;
      final sim = play(d, seed: 2);
      final r = sim.result!;
      expect(r.loanPaid, Bank.due(owed));
      expect(r.loanMissed, isFalse);
      expect(d.loan, owed - Bank.due(owed));
      expect(
        sim.story.any((l) => l.text.contains('loan')),
        isFalse,
        reason: 'only the end of the loan is told',
      );
    });

    test('the last payment ends it, and says so', () {
      final d = cafe(level: 3, day: 4)..coins = 1000;
      d.loan = 8;
      final sim = play(d, seed: 2);
      expect(d.loan, 0);
      expect(sim.result!.loanPaid, 8);
      expect(sim.story.any((l) => l.text == 'The loan is paid off.'), isTrue);
    });

    test('a missed night adds a twentieth and costs rating', () {
      final d = cafe(level: 3, day: 4)..coins = 0;
      d.loan = 200;
      d.progress.reputation = 60;
      // No money to shop with or pay wages: the day earns nothing.
      d.roster.employees.clear();
      d.progress.upgrades[Upgrade.staff] = 0;
      d.roster.employees.add(
        Staff(
          id: 99,
          name: 'Lone',
          stats: {
            Stat.cooking: 5,
            Stat.speed: 5,
            Stat.service: 5,
            Stat.charm: 5,
          },
          potential: {for (final s in Stat.values) s: 10},
        ),
      );
      final sim = DinerSim(d, seed: 2);
      while (!sim.finished && sim.ticks < 40) {
        sim.tick();
      }
      sim.finishDay();
      expect(sim.result!.loanMissed, isTrue);
      expect(d.loan, 210);
      expect(d.loanLate, 1);
      expect(sim.result!.loanPaid, 0);
      expect(
        sim.story.any((l) => l.text.startsWith('The bank did not get')),
        isTrue,
      );
    });

    test('it comes first in what to fix', () {
      final r = DayReport(
        day: 3,
        served: 5,
        walkouts: 9,
        earned: 50,
        tips: 0,
        wasted: 0,
        avgWait: 3,
        stars: 1,
        xp: 1,
        levelsGained: 0,
        reputation: 40,
        reputationBefore: 42,
        tomorrow: 5,
        wages: 0,
        unpaid: 0,
        quit: const [],
        story: const [],
        moods: const [],
        soldOut: 9,
        loanMissed: true,
      );
      expect(fixFirst(r), startsWith('The bank did not get its payment'));
    });

    test('what is owed is saved', () {
      final d = cafe(level: 3)..coins = 0;
      d.borrow(Bank.offers[0]);
      d.loanLate = 2;
      final back = Diner.fromJson(d.toJson());
      expect(back.loan, 115);
      expect(back.loanLate, 2);
      expect(Diner.fromJson(cafe().toJson()).loan, 0);
    });
  });

  group('on screen', () {
    Future<Diner> open(WidgetTester tester, Diner d) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
      });
      Storage.clearMemory();
      d.goalsDone.addAll([for (final g in goals) g.id]);
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(HexApp(home: BuildScreen(diner: d)));
      await tester.pump();
      return d;
    }

    Future<void> beat(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
    }

    Future<void> tapKey(WidgetTester tester, String key) async {
      final f = find.byKey(ValueKey(key));
      await tester.ensureVisible(f);
      await tester.pump();
      await tester.tap(f);
      await beat(tester);
    }

    /// The tile on the staff room page, tapped.
    Future<void> tapTile(WidgetTester tester, Cell c) async {
      final art = DinerArt.instance!;
      final box = tester.getRect(find.byKey(const ValueKey('room-scene')));
      final unit = box.width / StaffRoomPainter.size(art).width;
      await tester.tapAt(box.topLeft + StaffRoomPainter.centre(art, c) * unit);
      await beat(tester);
    }

    testWidgets('the buttons that opened the pages are gone', (tester) async {
      await open(tester, cafe());
      for (final k in [
        'menu',
        'staff',
        'stats',
        'upgrades',
        'goals',
        'expand',
      ]) {
        expect(find.byKey(ValueKey(k)), findsNothing, reason: k);
      }
    });

    testWidgets('tapping the door opens the staff room on its own page', (
      tester,
    ) async {
      await open(tester, cafe(lounge: 2));
      await openRoom(tester);
      expect(find.byKey(const ValueKey('room-scene')), findsOneWidget);
      expect(find.text('Staff room'), findsOneWidget);
      expect(find.text('Tap the computer'), findsOneWidget);
      expect(find.text('2 sofas. Tired staff rest here.'), findsOneWidget);
      expect(find.byKey(const ValueKey('start-day')), findsNothing);
    });

    testWidgets('and Leave goes back to the restaurant', (tester) async {
      await open(tester, cafe());
      await openRoom(tester);
      await tapKey(tester, 'room-done');
      expect(find.byKey(const ValueKey('room-scene')), findsNothing);
      expect(find.byKey(const ValueKey('start-day')), findsOneWidget);
    });

    testWidgets(
      'tapping the computer opens the terminal, a window of programs',
      (tester) async {
        await open(tester, cafe(level: 5));
        await openRoom(tester);
        await openComputer(tester);
        expect(find.byKey(const ValueKey('programs')), findsOneWidget);
        expect(find.byKey(const ValueKey('notes')), findsOneWidget);
        for (final a in DeskApp.values) {
          if (a == DeskApp.reset || a == DeskApp.moveDoor) continue;
          expect(
            find.byKey(ValueKey('app-${a.name}')),
            findsOneWidget,
            reason: a.name,
          );
        }
        expect(find.text('Day 3   :coin: ${100000}'), findsNothing);
        expect(find.byKey(const ValueKey('terminal-clock')), findsOneWidget);
      },
    );

    test('every program has a sixteen by sixteen picture', () {
      for (final a in DeskApp.values) {
        if (a == DeskApp.reset || a == DeskApp.moveDoor) continue;
        final rows = terminalIcons[a]!;
        expect(rows.length, 16, reason: a.name);
        expect(rows.every((r) => r.length == 16), isTrue, reason: a.name);
        expect(rows.join().contains('#'), isTrue);
      }
    });

    testWidgets('a program opens its page, and back returns to the terminal', (
      tester,
    ) async {
      await open(tester, cafe());
      await openApp(tester, 'menu');
      expect(find.byKey(const ValueKey('open-prep')), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await beat(tester);
      expect(find.byKey(const ValueKey('programs')), findsOneWidget);
    });

    testWidgets('the close box leaves the terminal', (tester) async {
      await open(tester, cafe());
      await openRoom(tester);
      await openComputer(tester);
      await tapKey(tester, 'close-programs');
      expect(find.byKey(const ValueKey('programs')), findsNothing);
      expect(find.byKey(const ValueKey('room-scene')), findsOneWidget);
    });

    testWidgets('the bank is locked until level 2, and says so', (
      tester,
    ) async {
      await open(tester, cafe(level: 1));
      await openRoom(tester);
      await openComputer(tester);
      await tapKey(tester, 'app-bank');
      expect(find.byKey(const ValueKey('programs')), findsOneWidget);
      expect(find.text('> The bank opens at level 2'), findsOneWidget);
    });

    testWidgets('Expand goes back to the restaurant and starts expanding', (
      tester,
    ) async {
      await open(tester, cafe(level: 5));
      await openApp(tester, 'expand');
      expect(find.byKey(const ValueKey('programs')), findsNothing);
      expect(find.byKey(const ValueKey('room-scene')), findsNothing);
      expect(find.byKey(const ValueKey('start-day')), findsNothing);
    });

    testWidgets('the notes say what needs doing', (tester) async {
      final d = cafe();
      d.coins = 3;
      d.loan = 100;
      await open(tester, d);
      await openRoom(tester);
      await openComputer(tester);
      expect(find.textContaining('> Wages tonight are'), findsOneWidget);
      expect(find.textContaining('> You owe 100'), findsOneWidget);
      expect(find.text('Staff !'), findsOneWidget);
    });

    testWidgets('Edit room shows what can be put in it', (tester) async {
      await open(tester, cafe(lounge: 1));
      await openRoom(tester);
      await tapKey(tester, 'room-edit');
      expect(find.text('Arranging the room'), findsOneWidget);
      for (final k in ['sofa', 'plant', 'rug']) {
        expect(find.byKey(ValueKey('room-pick-$k')), findsOneWidget);
      }
      // The one sofa the upgrade gives is already in the room.
      expect(find.text('Sofa'), findsOneWidget);
    });

    testWidgets('a plant is aimed at a tile, placed, and paid for', (
      tester,
    ) async {
      final d = await open(tester, cafe());
      final before = d.coins;
      await openRoom(tester);
      await tapKey(tester, 'room-edit');
      await tapKey(tester, 'room-pick-plant');
      await tapTile(tester, const Cell(2, 3));
      await tapKey(tester, 'room-place');
      expect(d.room.pickAt(const Cell(2, 3))!.kind, RoomKind.plant);
      expect(d.coins, before - 15);
    });

    testWidgets('a spot that is taken cannot be placed on, and says why', (
      tester,
    ) async {
      final d = await open(tester, cafe());
      final before = d.coins;
      await openRoom(tester);
      await tapKey(tester, 'room-edit');
      await tapKey(tester, 'room-pick-plant');
      final pc = d.room.computer!.at;
      await tapTile(tester, pc);
      expect(find.text('That spot is taken'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('room-place')),
        warnIfMissed: false,
      );
      await beat(tester);
      expect(d.coins, before);
      await tapKey(tester, 'room-cancel');
      expect(find.byKey(const ValueKey('room-place')), findsNothing);
    });

    testWidgets('something in the room is selected, moved and turned', (
      tester,
    ) async {
      final d = await open(tester, cafe(lounge: 1));
      await openRoom(tester);
      await tapKey(tester, 'room-edit');
      final sofa = d.room.items.firstWhere((i) => i.kind == RoomKind.sofa);
      await tapTile(tester, sofa.at);
      expect(find.byKey(const ValueKey('room-move')), findsOneWidget);
      final facing = sofa.facing;
      await tapKey(tester, 'room-turn');
      expect(sofa.facing, facing.cw);
      await tapKey(tester, 'room-move');
      await tapTile(tester, const Cell(0, 4));
      await tapKey(tester, 'room-place');
      expect(sofa.at, const Cell(0, 4));
    });

    testWidgets('a plant can be sold, the computer cannot', (tester) async {
      final d = await open(tester, cafe());
      await openRoom(tester);
      await tapKey(tester, 'room-edit');
      final plant = d.room.items.firstWhere((i) => i.kind == RoomKind.plant);
      final coins = d.coins;
      await tapTile(tester, plant.at);
      await tapKey(tester, 'room-sell');
      expect(d.room.items, isNot(contains(plant)));
      expect(d.coins, coins + 7);
      await tapTile(tester, d.room.computer!.at);
      expect(find.byKey(const ValueKey('room-sell')), findsNothing);
      expect(find.byKey(const ValueKey('room-turn')), findsOneWidget);
    });

    testWidgets('in edit mode the computer is something to move, not to use', (
      tester,
    ) async {
      final d = await open(tester, cafe());
      await openRoom(tester);
      await tapKey(tester, 'room-edit');
      await tapTile(tester, d.room.computer!.at);
      expect(find.byKey(const ValueKey('programs')), findsNothing);
      expect(find.byKey(const ValueKey('room-move')), findsOneWidget);
    });

    testWidgets('Move the door goes back and picks the door up', (
      tester,
    ) async {
      await open(tester, cafe());
      await openRoom(tester);
      await tapKey(tester, 'move-door');
      expect(find.byKey(const ValueKey('room-scene')), findsNothing);
      expect(find.text('Put down'), findsOneWidget);
    });

    testWidgets('during a day the computer is locked, and who rests is shown', (
      tester,
    ) async {
      final d = await open(tester, cafe(lounge: 1));
      await tester.tap(find.byKey(const ValueKey('start-day')));
      await tester.pump();
      await openRoom(tester);
      expect(find.text('The day is running'), findsOneWidget);
      expect(find.byKey(const ValueKey('room-edit')), findsNothing);
      expect(find.byKey(const ValueKey('move-door')), findsNothing);
      expect(
        find.byKey(ValueKey('energy-${d.roster.employees.first.id}')),
        findsOneWidget,
      );
      await openComputer(tester);
      expect(find.text('The computer is for between days.'), findsOneWidget);
      expect(find.byKey(const ValueKey('programs')), findsNothing);
    });

    testWidgets('someone resting is on the sofa, and counted', (tester) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
      });
      final d = cafe(lounge: 1);
      final sim = DinerSim(d, seed: 2);
      sim.workers.first
        ..energy = 30
        ..state = WorkState.resting;
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        HexApp(
          home: RoomScreen(diner: d, sim: sim),
        ),
      );
      await tester.pump();
      expect(find.text('1 of 1 sofa in use: S0'), findsOneWidget);
      expect(find.text('resting'), findsOneWidget);
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((c) => c.painter)
          .whereType<StaffRoomPainter>()
          .first;
      expect(painter.resters.single.name, 'S0');
    });

    testWidgets('sofas are bought from Upgrades, and appear in the room', (
      tester,
    ) async {
      final d = await open(tester, cafe());
      await openApp(tester, 'upgrades');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('buy-lounge')),
        200,
      );
      await tapKey(tester, 'buy-lounge');
      expect(d.loungeLevel, 1);
      expect(d.room.sofaCount, 1);
    });

    testWidgets('the bank lends, and says what it will cost', (tester) async {
      final d = cafe(level: 3)..coins = 20;
      await open(tester, d);
      await openApp(tester, 'bank');
      expect(find.text('You owe nothing'), findsOneWidget);
      expect(
        find.text('Pay back 115: 23 a night, 15 for the bank'),
        findsOneWidget,
      );
      expect(find.text('Opens at level 5'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('borrow-100')));
      await tester.pump();
      expect(d.coins, 120);
      expect(d.loan, 115);
      expect(find.byKey(const ValueKey('owed')), findsOneWidget);
      expect(find.text('Pay off all 115'), findsOneWidget);
      expect(find.text('Pay off what you owe first'), findsWidgets);
    });

    testWidgets('and can be paid off', (tester) async {
      final d = cafe(level: 3)..coins = 500;
      d.borrow(Bank.offers[0]);
      await open(tester, d);
      await openRoom(tester);
      await openComputer(tester);
      expect(
        find.textContaining('> You owe 115. 23 is due tonight.'),
        findsOneWidget,
      );
      await tapKey(tester, 'app-bank');
      await tester.tap(find.byKey(const ValueKey('repay-all')));
      await tester.pump();
      expect(d.loan, 0);
      expect(find.text('Paid off.'), findsOneWidget);
    });

    testWidgets('a short till cannot pay it all', (tester) async {
      final d = cafe(level: 3)..coins = 0;
      d.borrow(Bank.offers[0]);
      d.coins = 30;
      await open(tester, d);
      await openApp(tester, 'bank');
      await tester.tap(
        find.byKey(const ValueKey('repay-all')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(d.loan, 115);
      await tester.tap(find.byKey(const ValueKey('repay-some')));
      await tester.pump();
      expect(d.loan, 92);
      expect(d.coins, 7);
      expect(find.byType(PxText), findsWidgets);
    });
  });
}

int _inRoom(DinerSim sim) => sim.workers
    .where((w) => w.state == WorkState.toRest || w.state == WorkState.resting)
    .length;
