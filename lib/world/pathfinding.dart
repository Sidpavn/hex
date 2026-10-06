import '../game/hex.dart';
import 'zone.dart';

/// Cheapest walkable path from [from] to [to] (excluding [from]), or null.
/// Forests and fords cost 2.
///
/// [blocked] marks hexes that are temporarily impassable (other creatures).
/// The destination itself is always allowed.
List<Hex>? findPath(
  Zone zone,
  Hex from,
  Hex to, {
  bool Function(Hex)? blocked,
}) {
  final goal = zone.tiles[to];
  if (goal == null || !goal.walkable) return null;
  if (from == to) return const [];
  final cost = <Hex, int>{from: 0};
  final parent = <Hex, Hex>{};
  final open = <Hex>[from];
  final score = <Hex, int>{from: from.distanceTo(to)};
  while (open.isNotEmpty) {
    var best = 0;
    for (var i = 1; i < open.length; i++) {
      if (score[open[i]]! < score[open[best]]!) best = i;
    }
    final cur = open.removeAt(best);
    if (cur == to) {
      final path = <Hex>[];
      var h = to;
      while (h != from) {
        path.add(h);
        h = parent[h]!;
      }
      return path.reversed.toList();
    }
    for (final n in cur.neighbors) {
      final tile = zone.tiles[n];
      if (tile == null || !tile.walkable) continue;
      if (n != to && blocked != null && blocked(n)) continue;
      final c = cost[cur]! + tile.cost;
      final known = cost[n];
      if (known == null || c < known) {
        cost[n] = c;
        parent[n] = cur;
        score[n] = c + n.distanceTo(to);
        if (!open.contains(n)) open.add(n);
      }
    }
  }
  return null;
}
