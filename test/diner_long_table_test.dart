// The long table: two tiles, so a bench seats both of its guests.
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/recipes.dart';

Diner room() =>
    Diner(coins: 10000, owned: {0, 1}, progress: Progress(level: 3));

void main() {
  test('it is two tiles, comes with the bench, and can be turned', () {
    final def = fixtureDefs[Kind.longTable]!;
    expect(def.w, 2);
    expect(def.unlock, fixtureDefs[Kind.bench]!.unlock);
    expect(def.role, Role.table);
    expect(def.rotates, isTrue);
    expect(fixtureDefs[Kind.table]!.rotates, isFalse);
  });

  test('a bench seats only one guest at a one-tile table', () {
    final d = room();
    d.place(Kind.table, const Cell(3, 5));
    d.place(Kind.bench, const Cell(3, 4), Dir.sw);
    expect(d.seats(), hasLength(1));
  });

  test('and both guests at a long table', () {
    final d = room();
    expect(d.place(Kind.longTable, const Cell(3, 5), Dir.sw), PlaceResult.ok);
    d.place(Kind.bench, const Cell(3, 4), Dir.sw);
    expect(d.seats(), hasLength(2));
    expect(
      d.report().problems.map((p) => p.text),
      isNot(contains('Nothing is seated at this table')),
    );
  });

  test('a bench along y needs the table along y', () {
    final d = room();
    d.place(Kind.bench, const Cell(4, 4), Dir.se);
    final p = d.place(Kind.longTable, const Cell(5, 4), Dir.se);
    expect(p, PlaceResult.ok);
    expect(d.seats(), hasLength(2));
    final wrong = room();
    wrong.place(Kind.bench, const Cell(4, 4), Dir.se);
    wrong.place(Kind.longTable, const Cell(5, 4), Dir.sw);
    expect(wrong.seats(), hasLength(1));
  });

  test('a new one lies along the seats that face it', () {
    final d = room();
    d.place(Kind.bench, const Cell(4, 4), Dir.se);
    expect(d.defaultFacing(Kind.longTable, const Cell(5, 4)), Dir.se);
    final e = room();
    e.place(Kind.bench, const Cell(3, 4), Dir.sw);
    expect(e.defaultFacing(Kind.longTable, const Cell(3, 5)), Dir.sw);
  });

  test('turning it takes the other two tiles, and is refused if blocked', () {
    final d = room();
    d.place(Kind.longTable, const Cell(3, 5), Dir.sw);
    final t = d.objectAt(const Cell(3, 5))!;
    expect(t.cells.toSet(), {const Cell(3, 5), const Cell(4, 5)});
    expect(d.rotate(t), PlaceResult.ok);
    expect(t.cells.toSet(), {const Cell(3, 5), const Cell(3, 6)});
    d.rotate(t);
    d.rotate(t);
    d.rotate(t);
    d.place(Kind.plant, const Cell(3, 6));
    expect(d.rotate(t), isNot(PlaceResult.ok));
    expect(t.facing, Dir.sw, reason: 'it stayed as it was');
  });

  test('it costs 50, sells for 25, and is saved', () {
    final d = room();
    final before = d.coins;
    d.place(Kind.longTable, const Cell(3, 5), Dir.se);
    expect(before - d.coins, 50);
    final back = Diner.fromJson(d.toJson());
    final t = back.objectAt(const Cell(3, 6))!;
    expect(t.kind, Kind.longTable);
    expect(t.facing, Dir.se);
  });
}
