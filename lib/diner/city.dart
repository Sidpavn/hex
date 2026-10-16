import 'diner.dart';

/// The ground around the restaurant: what each tile is made of, and the
/// street furniture standing on it. Pure data, so it can be tested without
/// drawing.

/// Whether [c] is on the plot, bought or not.
bool onPlot(Cell c) =>
    c.x >= Diner.left &&
    c.x <= Diner.plotRight &&
    c.y >= Diner.plotTop &&
    c.y <= Diner.plots[0].y1;

/// A neighbouring building: one sprite standing on a rectangle of the ground,
/// its first cell at ([x0], [y0]).
class Building {
  const Building(this.sprite, this.x0, this.y0, this.w, this.d);

  final String sprite;
  final int x0;
  final int y0;

  /// Cells along x and along y.
  final int w;
  final int d;

  bool contains(Cell c) =>
      c.x >= x0 && c.x < x0 + w && c.y >= y0 && c.y < y0 + d;
}

/// The buildings either side of the plot: two on the left, two across the
/// side street. Their sizes match the sprites made by `gen_diner_art.py`.
const buildings = [
  Building('block_lf', -9, 1, 8, 7),
  Building('block_lb', -9, -6, 8, 7),
  Building('block_rf', 15, 1, 4, 7),
  Building('block_rb', 15, -6, 4, 7),
];

/// What the ground at [c] is made of. The restaurant is floor; the rest of
/// the plot is bare earth until bought. Beside it, where neighbours' buildings
/// would be, is concrete. Going away from the shop along the front: pavement
/// (where guests queue), the kerb, two lanes of road, then the pavement on the
/// far side. A side street runs up the right-hand side of the plot.
String groundTile(Diner d, Cell c) {
  if (d.isInside(c)) return (c.x + c.y).isEven ? 'floor_a' : 'floor_b';
  if (d.isLocked(c)) return 'lot';
  final row = c.y - d.bottom;
  final side = c.x - Diner.plotRight;
  if (row >= 1) {
    // The side street joins the road, with a crossing over its mouth.
    if (side == 2 || side == 3) {
      return switch (row) {
        1 => 'crosswalk_h',
        2 => side == 2 ? 'road_v' : 'road_b',
        3 => 'road_a',
        4 => 'road_b',
        5 || 6 => c.x.isEven ? 'sidewalk_a' : 'sidewalk_b',
        _ => _grass(c),
      };
    }
    return switch (row) {
      1 => c.x.isEven ? 'sidewalk_a' : 'sidewalk_b',
      2 => 'curb',
      3 => 'road_a',
      4 => 'road_b',
      5 || 6 => c.x.isEven ? 'sidewalk_a' : 'sidewalk_b',
      _ => _grass(c),
    };
  }
  if (c.y >= Diner.plotTop - 1) {
    // Beside the plot: a pavement, the side street, and its far pavement.
    if (side == 1 || side == 4) return c.y.isEven ? 'sidewalk_a' : 'sidewalk_b';
    if (side == 2) return 'road_v';
    if (side == 3) return 'road_b';
    // A pavement runs along the plot's left, between it and the buildings.
    if (c.x == Diner.left - 1 || c.x == Diner.left - 2) {
      return (c.x + c.y).isEven ? 'sidewalk_a' : 'sidewalk_b';
    }
    // Under the buildings, which hide it.
    if (buildings.any((b) => b.contains(c))) {
      return (c.x + c.y).isEven ? 'concrete_a' : 'concrete_b';
    }
  }
  return _grass(c);
}

String _grass(Cell c) => (c.x * 7 + c.y * 13) % 5 == 0 ? 'grass_b' : 'grass_a';

/// Lamps and trees along the kerb.
List<(String, Cell)> streetProps(Diner d) {
  final door = d.entrance.x;
  final kerb = d.bottom + 2;
  return [
    ('lamp', Cell(door - 6, kerb)),
    ('tree', Cell(door - 3, kerb)),
    ('lamp', Cell(Diner.plotRight + 1, kerb)),
    ('tree', Cell(Diner.plotRight + 5, kerb)),
    // Vending machines, along the kerb to the right of the door.
    for (var i = 0; i < d.vendingMachines; i++)
      (d.vendingOn ? 'vending' : 'vending_off', Cell(door + 2 + 2 * i, kerb)),
    // The day's special, chalked up beside the door.
    if (d.specialActive) ('special_board', Cell(door - 1, kerb)),
  ];
}
