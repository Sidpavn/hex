/// What a wallpaper, floor or furniture piece is for: the walls round the
/// room, its tiles, or one kind of seating.
enum StyleKind { wall, floor, chair, bench, table, longTable }

/// A look for the walls, the floor, or a furniture piece. Some come with the
/// diner; some are unlocked by a goal; the rest are bought with gems and are
/// the player's for good. The ids are the ones the art is generated for (see
/// `tools/gen_diner_art.py`).
class Style {
  const Style(this.id, this.name, this.kind, {this.gems = 0, this.goal});

  final String id;
  final String name;
  final StyleKind kind;

  /// Gems to buy it; none for the ones that come free or are earned.
  final int gems;

  /// The id of the goal that unlocks it, if it is earned rather than bought.
  final String? goal;

  bool get free => gems == 0 && goal == null;

  /// The sprite suffix: the diner's own look has none.
  String get suffix => id == _defaultId[kind] ? '' : '_s_$id';
}

/// What the diner starts with.
const wallDefault = 'mint';
const floorDefault = 'peach';
const chairDefault = 'classic';
const benchDefault = 'classic';
const tableDefault = 'classic';
const longTableDefault = 'classic';

const Map<StyleKind, String> _defaultId = {
  StyleKind.wall: wallDefault,
  StyleKind.floor: floorDefault,
  StyleKind.chair: chairDefault,
  StyleKind.bench: benchDefault,
  StyleKind.table: tableDefault,
  StyleKind.longTable: longTableDefault,
};

/// The goal that unlocks the matching diner-themed furniture skins.
const furnitureGoal = 'seats10';

const styles = [
  Style(wallDefault, 'Mint', StyleKind.wall),
  Style('cream', 'Cream', StyleKind.wall),
  Style('sage', 'Sage', StyleKind.wall),
  Style('rose', 'Rose', StyleKind.wall, gems: 30),
  Style('navy', 'Navy', StyleKind.wall, gems: 30),
  Style('stripe', 'Striped', StyleKind.wall, gems: 50),
  Style('brick', 'Brick', StyleKind.wall, gems: 50),
  Style(floorDefault, 'Peach', StyleKind.floor),
  Style('slate', 'Slate', StyleKind.floor),
  Style('wood', 'Wood', StyleKind.floor, gems: 30),
  Style('terra', 'Terracotta', StyleKind.floor, gems: 30),
  Style('mint', 'Mint tile', StyleKind.floor, gems: 30),
  Style('checker', 'Black and white', StyleKind.floor, gems: 40),

  Style(chairDefault, 'Classic', StyleKind.chair),
  Style('mint', 'Mint', StyleKind.chair),
  Style('diner', 'Diner', StyleKind.chair, goal: furnitureGoal),
  Style('walnut', 'Walnut', StyleKind.chair, gems: 40),

  Style(benchDefault, 'Classic', StyleKind.bench),
  Style('mint', 'Mint', StyleKind.bench),
  Style('diner', 'Diner', StyleKind.bench, goal: furnitureGoal),
  Style('walnut', 'Walnut', StyleKind.bench, gems: 40),

  Style(tableDefault, 'Classic', StyleKind.table),
  Style('mint', 'Mint', StyleKind.table),
  Style('diner', 'Diner', StyleKind.table, goal: furnitureGoal),
  Style('walnut', 'Walnut', StyleKind.table, gems: 40),

  Style(longTableDefault, 'Classic', StyleKind.longTable),
  Style('mint', 'Mint', StyleKind.longTable),
  Style('diner', 'Diner', StyleKind.longTable, goal: furnitureGoal),
  Style('walnut', 'Walnut', StyleKind.longTable, gems: 40),
];

List<Style> stylesOf(StyleKind k) => [
  for (final s in styles)
    if (s.kind == k) s,
];

/// The style with [id] among [k], or null.
Style? styleById(StyleKind k, String id) {
  for (final s in styles) {
    if (s.kind == k && s.id == id) return s;
  }
  return null;
}
