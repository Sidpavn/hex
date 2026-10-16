// The TV is flat and hangs on a wall: it takes no floor, goes only where the
// room has a wall, and turns between the back wall and the left one.
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/recipes.dart';

Diner room() => Diner(coins: 5000, owned: {0, 1}, progress: Progress(level: 5));

void main() {
  test('it goes on the back wall facing in, and on the left wall', () {
    final d = room();
    expect(d.place(Kind.tv, const Cell(5, 3)), PlaceResult.ok);
    expect(d.items.last.facing, Dir.sw);
    expect(d.place(Kind.tv, const Cell(1, 6)), PlaceResult.ok);
    expect(d.items.last.facing, Dir.se, reason: 'the left wall faces east');
  });

  test('not in the middle of the room, where there is no wall', () {
    final d = room();
    expect(d.place(Kind.tv, const Cell(5, 5)), PlaceResult.hang);
    expect(
      d.check(Kind.tv, const Cell(5, 3), facing: Dir.se),
      PlaceResult.hang,
    );
    expect(
      d.check(Kind.tv, const Cell(5, 3), facing: Dir.ne),
      PlaceResult.hang,
    );
    expect(PlaceResult.hang.message, 'Hangs on the back or left wall');
  });

  test('it takes no floor: things stand under it, and people walk there', () {
    final d = room();
    d.place(Kind.counter, const Cell(5, 3), Dir.sw);
    expect(d.place(Kind.tv, const Cell(5, 3)), PlaceResult.ok);
    expect(d.objectAt(const Cell(5, 3))?.kind, Kind.counter);
    expect(d.walkable(const Cell(6, 3)), isTrue);
    final bare = room();
    bare.place(Kind.tv, const Cell(6, 3));
    expect(bare.walkable(const Cell(6, 3)), isTrue);
    expect(bare.reachable().length, room().reachable().length);
  });

  test('one to a spot on a wall', () {
    final d = room();
    d.place(Kind.tv, const Cell(5, 3));
    expect(d.place(Kind.tv, const Cell(5, 3)), PlaceResult.taken);
  });

  test('turning moves it to the other wall, in the corner only', () {
    final d = room();
    d.place(Kind.tv, const Cell(1, 3));
    final tv = d.items.last;
    expect(tv.facing, Dir.sw);
    expect(d.rotate(tv), PlaceResult.ok);
    expect(tv.facing, Dir.se);
    expect(d.rotate(tv), PlaceResult.ok);
    expect(tv.facing, Dir.sw);
    d.place(Kind.tv, const Cell(5, 3));
    final mid = d.items.last;
    expect(d.rotate(mid), PlaceResult.hang);
    expect(mid.facing, Dir.sw);
  });

  test('it can be turned, so it says so', () {
    expect(fixtureDefs[Kind.tv]!.turns, isTrue);
    expect(fixtureDefs[Kind.tv]!.name, 'Wall TV');
  });

  test('tapping the TV, or the wall it hangs on, picks it', () {
    final d = room();
    d.place(Kind.tv, const Cell(5, 3));
    final tv = d.items.last;
    expect(d.pickAt(const Cell(5, 3)), tv);
    expect(d.pickAt(const Cell(5, 2)), tv, reason: 'the wall behind');
    expect(d.pickAt(const Cell(6, 2)), isNull);
    d.place(Kind.counter, const Cell(5, 3), Dir.sw);
    expect(d.pickAt(const Cell(5, 3))?.kind, Kind.counter);
    expect(d.pickAt(const Cell(5, 2)), tv);
  });

  test('moved, sold, saved and loaded like anything else', () {
    final d = room();
    d.place(Kind.tv, const Cell(5, 3));
    final tv = d.items.last;
    expect(d.moveTo(tv, const Cell(6, 4)), PlaceResult.hang);
    expect(d.moveTo(tv, const Cell(7, 3)), PlaceResult.ok);
    final back = Diner.fromJson(d.toJson());
    expect(back.hungAt(const Cell(7, 3))?.facing, Dir.sw);
    d.sell(tv);
    expect(d.hungAt(const Cell(7, 3)), isNull);
  });

  test('an old save with a TV standing in the room gets its money back', () {
    final d = room();
    final json = d.toJson();
    (json['items'] as List).add({'k': 'tv', 'x': 5, 'y': 5, 'f': 'sw'});
    final before = Diner.fromJson(json).coins;
    expect(before, d.coins + 150);
    expect(Diner.fromJson(json).items.where((p) => p.kind == Kind.tv), isEmpty);
  });

  test('a group with a TV on the wall can be moved along it', () {
    final d = room();
    d.place(Kind.tv, const Cell(5, 3));
    final tv = d.items.last;
    expect(d.checkGroup([tv], const GroupMove(dx: 1, dy: 0)), PlaceResult.ok);
    expect(d.checkGroup([tv], const GroupMove(dx: 0, dy: 1)), PlaceResult.hang);
  });
}
