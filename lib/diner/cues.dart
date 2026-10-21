/// Things that happen in a day that are worth a sound. The sim only records
/// them; the screen decides what, if anything, to play. See `lib/audio`.
enum Cue {
  /// A guest comes in through the door.
  enter,

  /// A machine starts a dish, and finishes one.
  cookStart,
  dishReady,

  /// A plate reaches a table.
  plate,

  /// A guest pays, with a tip of a quarter of the bill or more, or not.
  paid,
  paidWell,

  /// At least one guest left unserved or gave up this tick.
  walkout,
}
