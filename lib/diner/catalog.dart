import 'diner.dart';

/// The groups the build popup sorts things into.
enum Category {
  seating('Seating'),
  tables('Tables'),
  kitchen('Kitchen'),
  structure('Walls and floors'),
  decor('Decor');

  const Category(this.label);

  final String label;
}

/// Which group each thing you can build belongs to.
const Map<Kind, Category> categoryOf = {
  Kind.chair: Category.seating,
  Kind.bench: Category.seating,
  Kind.table: Category.tables,
  Kind.longTable: Category.tables,
  Kind.grill: Category.kitchen,
  Kind.fryer: Category.kitchen,
  Kind.soda: Category.kitchen,
  Kind.espresso: Category.kitchen,
  Kind.oven: Category.kitchen,
  Kind.freezer: Category.kitchen,
  Kind.counter: Category.kitchen,
  Kind.pass: Category.kitchen,
  Kind.kitchenFloor: Category.kitchen,
  Kind.wall: Category.structure,
  Kind.window: Category.structure,
  Kind.plant: Category.decor,
  Kind.jukebox: Category.decor,
  Kind.tv: Category.decor,
  Kind.rug: Category.decor,
};

/// What belongs to [c], in the order they are bought.
List<FixtureDef> defsIn(Category c) => [
  for (final d in fixtureDefs.values)
    if (categoryOf[d.kind] == c) d,
];
