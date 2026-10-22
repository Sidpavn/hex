/// What a wallpaper or a floor is for: the walls round the room, or its tiles.
enum StyleKind { wall, floor }

/// A look for the walls or the floor. Some come with the diner; the rest are
/// bought with gems and are the player's for good. The ids are the ones the
/// art is generated for (see `tools/gen_diner_art.py`).
class Style {
  const Style(this.id, this.name, this.kind, [this.gems = 0]);

  final String id;
  final String name;
  final StyleKind kind;

  /// Gems to buy it; none for the ones that come free.
  final int gems;

  bool get free => gems == 0;

  /// The sprite suffix: the diner's own look has none.
  String get suffix =>
      (kind == StyleKind.wall && id == wallDefault) ||
          (kind == StyleKind.floor && id == floorDefault)
      ? ''
      : '_s_$id';
}

/// What the diner starts with.
const wallDefault = 'mint';
const floorDefault = 'peach';

const styles = [
  Style(wallDefault, 'Mint', StyleKind.wall),
  Style('cream', 'Cream', StyleKind.wall),
  Style('sage', 'Sage', StyleKind.wall),
  Style('rose', 'Rose', StyleKind.wall, 30),
  Style('navy', 'Navy', StyleKind.wall, 30),
  Style('stripe', 'Striped', StyleKind.wall, 50),
  Style('brick', 'Brick', StyleKind.wall, 50),
  Style(floorDefault, 'Peach', StyleKind.floor),
  Style('slate', 'Slate', StyleKind.floor),
  Style('wood', 'Wood', StyleKind.floor, 30),
  Style('terra', 'Terracotta', StyleKind.floor, 30),
  Style('mint', 'Mint tile', StyleKind.floor, 30),
  Style('checker', 'Black and white', StyleKind.floor, 40),
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
