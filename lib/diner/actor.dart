import 'diner.dart';

enum Meter { patience, cooking }

/// Something drawn standing on the floor: a person, a plate, a coin. [x] and
/// [y] are in cell units (the middle of cell 3,4 is 3.5,4.5), so people can be
/// between cells while they walk. [lift] raises it off the floor in art
/// pixels.
class Actor {
  const Actor(
    this.sprite,
    this.x,
    this.y, {
    this.dir,
    this.frame,
    this.lift = 0,
    this.row,
    this.badge,
    this.items = const [],
    this.meter,
    this.meterKind = Meter.patience,
  });

  /// Standing in the middle of [c].
  Actor.at(this.sprite, Cell c, {this.dir, this.frame, this.badge})
    : x = c.x + 0.5,
      y = c.y + 0.5,
      lift = 0,
      row = null,
      items = const [],
      meter = null,
      meterKind = Meter.patience;

  /// A person's name (`chef`) with [dir] and [frame], or a prop's sprite name
  /// when [dir] is null.
  final String sprite;
  final double x;
  final double y;
  final Dir? dir;

  /// `0`, `1` for walking, `s0`, `s1` for standing, `sit` for seated.
  final String? frame;
  final double lift;

  /// Depth key: larger draws later. Defaults to `x + y`.
  final double? row;

  /// A small sprite floating above the head (an order waiting).
  final String? badge;

  /// Dishes, by name, shown together in a bubble over a guest who is waiting
  /// for their meal.
  final List<String> items;

  /// A bar above the head, 0 to 1, for patience or cooking progress.
  final double? meter;
  final Meter meterKind;

  /// The sprite to draw. Empty when this only carries a [meter].
  String get name =>
      dir == null ? sprite : '${sprite}_${dir!.art}_${frame ?? 's0'}';

  bool get hasSprite => sprite.isNotEmpty;

  bool get flip => dir?.mirrored ?? false;

  double get depth => row ?? (x + y);
}
