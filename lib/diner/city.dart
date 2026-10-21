import 'diner.dart';

/// The ground around the restaurant: what each tile is made of, and the
/// street furniture standing on it. Pure data, so it can be tested without
/// drawing.

/// Whether [c] is on the plot, bought or not: inside any of its sections.
bool onPlot(Cell c) => Diner.plots.any((p) => p.contains(c));

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

/// The buildings round the plot, each one sprite: on the left and right of
/// it beyond the pavements, and across the main road. Their sizes match the
/// sprites made by `gen_diner_art.py`. Across the road they are low, so they
/// never climb over the restaurant or the road, and they stand two rows back
/// from the far pavement.
const buildings = [
  // The left: the old shopfront at the front, then a bakery and two blocks
  // of flats, and a second row of taller ones behind.
  Building('block_lf', -13, 1, 8, 7),
  Building('shop_bakery', -9, -3, 4, 4),
  Building('flats_a', -9, -8, 4, 5),
  Building('flats_b', -9, -13, 4, 5),
  Building('shop_cafe', -14, -3, 4, 4),
  Building('office', -14, -9, 4, 4),
  // The right, across the side street.
  Building('block_rf', 15, 1, 4, 7),
  Building('warehouse', 15, -4, 6, 5),
  Building('shop_arcade', 15, -9, 5, 4),
  Building('shop_laundry', 15, -13, 5, 4),
  Building('office', 21, -9, 4, 4),
  // Across the main road, with a park and a car park between them.
  Building('shop_cafe', -12, 16, 4, 4),
  Building('shop_laundry', -8, 16, 5, 4),
  Building('shop_bakery', 6, 16, 4, 4),
  Building('warehouse', 16, 16, 6, 5),
];

/// Something small standing on the ground: a tree, a bin, a car. It goes in
/// the cached picture of the town, so it costs nothing each frame.
class Scenery {
  const Scenery(this.sprite, this.x, this.y);

  final String sprite;
  final int x;
  final int y;

  /// Cars are drawn from the middle of their cell.
  bool get isCar => sprite.startsWith('car_');
}

/// The park across the road, with a fountain, and the car park beside it.
const parkX0 = -2, parkX1 = 4, parkY0 = 14, parkY1 = 21;
const carParkX0 = 11, carParkX1 = 14, carParkY0 = 14, carParkY1 = 21;

/// Everything small in the town. Fixed, so the street is the same each time.
const scenery = [
  // Across the main road, on the far pavement.
  Scenery('bus_stop', -6, 12),
  Scenery('lamp', -10, 12),
  Scenery('postbox', -2, 12),
  Scenery('lamp', 2, 12),
  Scenery('bin', 5, 13),
  Scenery('hydrant', 9, 12),
  Scenery('lamp', 13, 12),
  Scenery('bike_rack', 18, 13),
  Scenery('bollards', 10, 13),
  // The park: a hedge along the road with a gap for the path, trees,
  // benches, flower beds and a fountain.
  Scenery('hedge', -2, 14),
  Scenery('hedge', -1, 14),
  Scenery('hedge', 0, 14),
  Scenery('hedge', 3, 14),
  Scenery('hedge', 4, 14),
  Scenery('tree_broad', -1, 16),
  Scenery('tree_broad', 4, 16),
  Scenery('bench_park', -1, 18),
  Scenery('fountain', 1, 18),
  Scenery('bench_park', 3, 18),
  Scenery('flower_bed', 0, 20),
  Scenery('flower_bed', 2, 20),
  Scenery('tree_pine', -2, 21),
  Scenery('tree_broad', 4, 21),
  // The car park.
  Scenery('car_red_sw', 12, 15),
  Scenery('car_blue_sw', 12, 19),
  Scenery('car_sun_sw', 14, 20),
  Scenery('bin', 11, 14),
  // The left verge, along the pavement.
  Scenery('lamp', -5, 5),
  Scenery('tree', -5, 2),
  Scenery('bin', -5, -1),
  Scenery('lamp', -5, -6),
  Scenery('hydrant', -5, -9),
  Scenery('tree', -5, -12),
  // The right verge, along the side street's far pavement.
  Scenery('lamp', 14, 5),
  Scenery('bin', 14, 2),
  Scenery('tree', 14, -2),
  Scenery('lamp', 14, -6),
  Scenery('hydrant', 14, -8),
  Scenery('tree', 14, -12),
  // Trees and hedges in the gaps beyond the buildings.
  Scenery('tree_pine', -16, 4),
  Scenery('tree_broad', -17, -1),
  Scenery('tree_pine', 26, 3),
  Scenery('tree_broad', 25, -3),
  Scenery('tree_broad', -14, 14),
  Scenery('tree_pine', 24, 15),
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
        _ => _lawn(c),
      };
    }
    return switch (row) {
      1 => c.x.isEven ? 'sidewalk_a' : 'sidewalk_b',
      2 => 'curb',
      3 => 'road_a',
      4 => 'road_b',
      5 || 6 => c.x.isEven ? 'sidewalk_a' : 'sidewalk_b',
      _ => _lawn(c),
    };
  }
  if (c.y >= Diner.plotTop - 1) {
    // Beside the plot: a pavement, the side street, and its far pavement.
    if (side == 1 || side == 4) return c.y.isEven ? 'sidewalk_a' : 'sidewalk_b';
    if (side == 2) return 'road_v';
    if (side == 3) return 'road_b';
    // A pavement runs along the plot's left, between it and the buildings.
    if (c.x == Diner.plotLeft - 1 || c.x == Diner.plotLeft - 2) {
      return (c.x + c.y).isEven ? 'sidewalk_a' : 'sidewalk_b';
    }
    // Under the buildings, which hide it.
    if (buildings.any((b) => b.contains(c))) {
      return (c.x + c.y).isEven ? 'concrete_a' : 'concrete_b';
    }
  }
  return _grass(c);
}

/// The ground across the main road: the park, the car park, or grass.
String _lawn(Cell c) {
  if (c.x >= parkX0 && c.x <= parkX1 && c.y >= parkY0 && c.y <= parkY1) {
    // A paved path up the middle, round the fountain.
    if ((c.x == 1 || c.x == 2) && c.y <= 19 ||
        (c.x - 1).abs() <= 1 && c.y >= 17 && c.y <= 19) {
      return (c.x + c.y).isEven ? 'plaza_a' : 'plaza_b';
    }
    return (c.x + c.y).isEven ? 'park_a' : 'park_b';
  }
  if (c.x >= carParkX0 &&
      c.x <= carParkX1 &&
      c.y >= carParkY0 &&
      c.y <= carParkY1) {
    return c.x.isEven && c.y >= carParkY0 + 1 ? 'carpark_bay' : 'carpark';
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
      (
        'vending${d.vendingOn ? '' : '_off'}${d.vendCash > 0 ? '_cash' : ''}',
        Cell(door + 2 + 2 * i, kerb),
      ),
    // The day's special, chalked up beside the door.
    if (d.specialActive) ('special_board', Cell(door - 1, kerb)),
  ];
}
