import 'diner.dart';

/// Shortest walk from [from] to [to], not including [from], or null if there
/// is none. [to] may be a cell nobody can normally stand on (a chair), and
/// [from] may be too (the chair someone is leaving). The pavement outside the
/// door counts as walkable.
List<Cell>? route(Diner d, Cell from, Cell to) {
  if (from == to) return const [];
  bool open(Cell c) => c == to || c == d.street || d.walkable(c);
  final parent = <Cell, Cell>{};
  final seen = {from};
  final queue = [from];
  for (var i = 0; i < queue.length; i++) {
    final c = queue[i];
    for (final n in c.neighbors) {
      if (seen.contains(n) || !open(n)) continue;
      seen.add(n);
      parent[n] = c;
      if (n == to) {
        final path = <Cell>[];
        for (var at = to; at != from; at = parent[at]!) {
          path.add(at);
        }
        return path.reversed.toList();
      }
      queue.add(n);
    }
  }
  return null;
}

/// The cheapest of [spots] to walk to from [from], with the route there.
(Cell, List<Cell>)? nearest(Diner d, Cell from, Iterable<Cell> spots) {
  (Cell, List<Cell>)? best;
  for (final spot in spots) {
    final r = route(d, from, spot);
    if (r == null) continue;
    if (best == null || r.length < best.$2.length) best = (spot, r);
  }
  return best;
}
