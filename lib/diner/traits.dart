/// Quirks that make each person more than four numbers. A trait is a short
/// rule with an upside, a downside, or both. Pure data.
library;

enum Trait {
  quickHands,
  cheerful,
  perfectionist,
  fastLearner,
  frugal,
  teamPlayer,
  clumsy,
  hotHeaded,
  loyal,
  lateBloomer,
}

/// Whether a trait is good news, bad news, or a bit of both.
enum Tone { good, bad, mixed }

class TraitInfo {
  const TraitInfo(this.name, this.info, this.tone, this.salary);

  final String name;
  final String info;
  final Tone tone;

  /// What it does to their wage: the market prices quirks in.
  final double salary;
}

const Map<Trait, TraitInfo> traitInfo = {
  Trait.quickHands: TraitInfo(
    'Quick hands',
    'Handles plates 30% faster.',
    Tone.good,
    1.08,
  ),
  Trait.cheerful: TraitInfo(
    'Cheerful',
    'Guests lose patience more slowly when this person is on the team.',
    Tone.good,
    1.08,
  ),
  Trait.perfectionist: TraitInfo(
    'Perfectionist',
    'Food sells for 12% more, but every plate takes 10% longer to hand over.',
    Tone.mixed,
    1.05,
  ),
  Trait.fastLearner: TraitInfo(
    'Fast learner',
    'Training costs 30% less.',
    Tone.good,
    1.05,
  ),
  Trait.frugal: TraitInfo(
    'Frugal',
    'Happy with a wage 15% lower than the going rate.',
    Tone.good,
    0.85,
  ),
  Trait.teamPlayer: TraitInfo(
    'Team player',
    'Everyone else on the team walks 5% faster.',
    Tone.good,
    1.05,
  ),
  Trait.clumsy: TraitInfo(
    'Clumsy',
    'Now and then drops a plate. The meal is lost and has to be cooked again.',
    Tone.bad,
    0.9,
  ),
  Trait.hotHeaded: TraitInfo(
    'Hot-headed',
    'Takes unpaid wages badly: loses two points of morale, not one.',
    Tone.bad,
    0.92,
  ),
  Trait.loyal: TraitInfo(
    'Loyal',
    'Puts up with a missed payday: loses morale half as fast.',
    Tone.good,
    1.0,
  ),
  Trait.lateBloomer: TraitInfo(
    'Late bloomer',
    'Starts a little weaker, but after ten days on the job improves in '
        'everything.',
    Tone.mixed,
    0.9,
  ),
};
