/// The first day's tips, one at a time. A new game starts at the first; each
/// is done by doing the thing it says, and the game keeps its place so a
/// restart does not begin the tips again. An older save has none.
enum Coach {
  openBuild(
    'Welcome. Tap Build to see what you can put in the diner.',
    phase: CoachPhase.build,
  ),
  place(
    'Pick a table or a chair, tap the floor where it goes, then press Place.',
    phase: CoachPhase.build,
  ),
  startDay(
    'Ready? Press Start day. Guests come in, sit down and wait for food.',
    phase: CoachPhase.build,
  ),
  watch(
    'The bar over a guest\'s head is their patience. Tap them to rush it.',
    phase: CoachPhase.service,
  ),
  nextDay(
    'That was a day. See what you earned, then press Next day.',
    phase: CoachPhase.summary,
  );

  const Coach(this.text, {required this.phase});

  final String text;
  final CoachPhase phase;
}

enum CoachPhase { build, service, summary }
