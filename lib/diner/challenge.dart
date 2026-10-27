import 'luck.dart';
import 'service.dart';

/// One per-day challenge. Deterministic for a given day and level, so the
/// morning card always shows the same target.
class DailyChallenge {
  const DailyChallenge({
    required ChallengeType type,
    required this.description,
    required this.reward,
    required this.target,
  }) : _type = type;

  final ChallengeType _type;

  /// What to show in the pre-service card and the summary.
  final String description;

  /// Coins paid out for meeting it.
  final int reward;

  /// The numeric target, for display (e.g. "8 guests").
  final int target;

  /// Whether the challenge was met by the day's report.
  bool met(DayReport r) => _type.met(r, target);

  /// Returns null on day 1 (no challenge before the player finds their feet).
  static DailyChallenge? forDay(int day, int level, {bool hasWindow = false}) {
    if (day <= 1) return null;
    final pool = _pool(level, hasWindow: hasWindow);
    if (pool.isEmpty) return null;
    final pick = (dayLuck(day, 10) * pool.length).floor();
    return pool[pick].build(day, level);
  }
}

// --------------------------------------------------------- challenge types

enum ChallengeType {
  noWalkouts,
  serveN,
  earnN,
  profitN,
  carsN;

  bool met(DayReport r, int target) => switch (this) {
    ChallengeType.noWalkouts => r.served >= 6 && r.walkouts == 0,
    ChallengeType.serveN => r.served >= target,
    ChallengeType.earnN => r.earned >= target,
    ChallengeType.profitN => r.earned - r.ingredients - r.wages >= target,
    ChallengeType.carsN => r.cars >= target,
  };
}

// --------------------------------------------------------- challenge specs

class _Spec {
  const _Spec(this.type, this.weight);

  final ChallengeType type;
  final int weight;

  DailyChallenge build(int day, int level) {
    final int target;
    final String description;
    final int reward;
    switch (type) {
      case ChallengeType.noWalkouts:
        target = 0;
        description = 'No walkouts today (serve at least 6)';
        reward = 80;
      case ChallengeType.serveN:
        target = 5 + level * 3;
        description = 'Serve at least $target guests';
        reward = 60;
      case ChallengeType.earnN:
        target = 30 + level * 20;
        description = 'Take in at least $target coins';
        reward = 70;
      case ChallengeType.profitN:
        target = 10 + level * 15;
        description = 'Keep at least $target profit';
        reward = 100;
      case ChallengeType.carsN:
        target = 2 + level ~/ 2;
        description = 'Serve at least $target cars at the window';
        reward = 80;
    }
    return DailyChallenge(
      type: type,
      description: description,
      reward: reward,
      target: target,
    );
  }
}

List<_Spec> _pool(int level, {required bool hasWindow}) => [
  const _Spec(ChallengeType.noWalkouts, 20),
  const _Spec(ChallengeType.serveN, 25),
  const _Spec(ChallengeType.earnN, 20),
  const _Spec(ChallengeType.profitN, 20),
  if (hasWindow) const _Spec(ChallengeType.carsN, 15),
];
