import 'actor.dart';
import 'diner.dart';

/// People strolling along the pavement across the road. They are only for
/// the street: they never come in, and they are a plain function of [step], so
/// the same step always shows the same street. A step is a tenth of a second.
List<Actor> pedestrians(Diner d, int step) {
  const people = ['cust_a', 'cust_b', 'cust_c', 'cust_d', 'cust_e', 'cust_f'];
  // The far pavement is two rows wide: one lane each way.
  final y0 = d.bottom + 5;
  const reach = 30;
  const speed = 0.11;
  final from = Diner.left - 12;
  final out = <Actor>[];
  for (var i = 0; i < people.length; i++) {
    final east = i.isEven;
    // Each person starts somewhere along the lane, so the street is never
    // empty and never in step.
    final along = (step * speed + i * reach / people.length * 1.7) % reach;
    final x = east ? from + along : from + reach - along;
    out.add(
      Actor(
        people[i],
        x,
        y0 + (east ? 0.5 : 1.5),
        dir: east ? Dir.se : Dir.nw,
        frame: '${(step ~/ 3 + i) % 4}',
      ),
    );
  }
  return out;
}
