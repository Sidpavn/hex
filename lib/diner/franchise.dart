import 'dart:math';

// ── upgrade categories ────────────────────────────────────────────────────────

enum FranchiseUpgrade { staff, menu, exterior, marketing, seating }

const Map<FranchiseUpgrade, String> upgradeNames = {
  FranchiseUpgrade.staff: 'Staff',
  FranchiseUpgrade.menu: 'Menu',
  FranchiseUpgrade.exterior: 'Exterior',
  FranchiseUpgrade.marketing: 'Marketing',
  FranchiseUpgrade.seating: 'Seating',
};

/// Cost to go from level n to n+1 (index = current level, 0-based).
const List<int> upgradeCosts = [500, 1000, 2000, 4000, 8000];

const int maxUpgradeLevel = 5;

// ── franchise definitions ─────────────────────────────────────────────────────

class FranchiseDef {
  const FranchiseDef({
    required this.id,
    required this.name,
    required this.tagline,
    required this.unlockLevel,
    required this.openCost,
    required this.baseIncome,
  });

  final String id;
  final String name;
  final String tagline;
  final int unlockLevel;
  final int openCost;

  /// Coins per day at all upgrades level 0, reputation 50.
  final int baseIncome;
}

const List<FranchiseDef> franchiseDefs = [
  FranchiseDef(
    id: 'piazza',
    name: 'La Piazza',
    tagline: 'Italian kitchen',
    unlockLevel: 15,
    openCost: 4000,
    baseIncome: 40,
  ),
  FranchiseDef(
    id: 'sakura',
    name: 'Sakura Express',
    tagline: 'Sushi bar',
    unlockLevel: 20,
    openCost: 10000,
    baseIncome: 95,
  ),
  FranchiseDef(
    id: 'taco',
    name: 'Taco Fiesta',
    tagline: 'Mexican street food',
    unlockLevel: 25,
    openCost: 20000,
    baseIncome: 190,
  ),
  FranchiseDef(
    id: 'bao',
    name: 'The Bao House',
    tagline: 'Dim sum and noodles',
    unlockLevel: 30,
    openCost: 40000,
    baseIncome: 380,
  ),
];

FranchiseDef? franchiseDefById(String id) =>
    franchiseDefs.where((d) => d.id == id).firstOrNull;

// ── event system ──────────────────────────────────────────────────────────────

class FranchiseOption {
  const FranchiseOption({
    required this.label,
    required this.tag,
    this.coinCost = 0,
    this.repDelta = 0,
    this.incomeMod = 1.0,
    this.modDays = 0,
  });

  final String label;
  final String tag;

  /// Coins spent (negative = coins gained).
  final int coinCost;
  final int repDelta;

  /// Income multiplier while the mod is active (1.0 = no change).
  final double incomeMod;

  /// Days the multiplier lasts; 0 = no mod, -1 = permanent.
  final int modDays;
}

class FranchiseEvent {
  const FranchiseEvent({
    required this.id,
    required this.title,
    required this.options,
  });

  final String id;
  final String title;
  final List<FranchiseOption> options;
}

const List<FranchiseEvent> franchiseEventPool = [
  FranchiseEvent(
    id: 'raise',
    title: 'Chef wants a raise',
    options: [
      FranchiseOption(
        label: 'Give raise',
        tag: '+20% for 7 days',
        coinCost: 200,
        incomeMod: 1.2,
        modDays: 7,
      ),
      FranchiseOption(label: 'Negotiate', tag: 'No change', coinCost: 100),
      FranchiseOption(
        label: 'Decline',
        tag: '-30% for 5 days',
        incomeMod: 0.7,
        modDays: 5,
        repDelta: -5,
      ),
    ],
  ),
  FranchiseEvent(
    id: 'blogger',
    title: 'Food blogger visiting',
    options: [
      FranchiseOption(
        label: 'Prepare special',
        tag: '+25% for 3 days',
        coinCost: 100,
        incomeMod: 1.25,
        modDays: 3,
        repDelta: 10,
      ),
      FranchiseOption(label: 'Normal day', tag: 'No change'),
    ],
  ),
  FranchiseEvent(
    id: 'ad',
    title: 'Ad campaign available',
    options: [
      FranchiseOption(
        label: 'Run campaign',
        tag: '+30% for 10 days',
        coinCost: 500,
        incomeMod: 1.3,
        modDays: 10,
      ),
      FranchiseOption(label: 'Skip', tag: 'No change'),
    ],
  ),
  FranchiseEvent(
    id: 'bad_review',
    title: 'Negative review posted',
    options: [
      FranchiseOption(
        label: 'Address it',
        tag: 'Reputation holds',
        coinCost: 200,
        repDelta: 5,
      ),
      FranchiseOption(
        label: 'Ignore',
        tag: '-15 reputation',
        repDelta: -15,
        incomeMod: 0.85,
        modDays: 5,
      ),
    ],
  ),
  FranchiseEvent(
    id: 'bulk',
    title: 'Bulk supply deal',
    options: [
      FranchiseOption(
        label: 'Buy in bulk',
        tag: '+20% for 14 days',
        coinCost: 300,
        incomeMod: 1.2,
        modDays: 14,
      ),
      FranchiseOption(label: 'Pass', tag: 'No change'),
    ],
  ),
  FranchiseEvent(
    id: 'repair',
    title: 'Equipment needs repair',
    options: [
      FranchiseOption(
        label: 'Fix now',
        tag: 'Back to normal',
        coinCost: 400,
      ),
      FranchiseOption(
        label: 'Delay',
        tag: '-15% for 2 days',
        incomeMod: 0.85,
        modDays: 2,
      ),
    ],
  ),
  FranchiseEvent(
    id: 'training',
    title: 'Staff training offer',
    options: [
      FranchiseOption(
        label: 'Pay for it',
        tag: '+10% for 14 days',
        coinCost: 150,
        incomeMod: 1.1,
        modDays: 14,
      ),
      FranchiseOption(label: 'Skip', tag: 'No change'),
    ],
  ),
  FranchiseEvent(
    id: 'festival',
    title: 'Local festival nearby',
    options: [
      FranchiseOption(
        label: 'Extend hours',
        tag: '+40% today',
        coinCost: 150,
        incomeMod: 1.4,
        modDays: 1,
      ),
      FranchiseOption(
        label: 'Normal day',
        tag: '+15% anyway',
        incomeMod: 1.15,
        modDays: 1,
      ),
    ],
  ),
  FranchiseEvent(
    id: 'inspection',
    title: 'Health inspection coming',
    options: [
      FranchiseOption(
        label: 'Deep clean',
        tag: '+20 reputation',
        coinCost: 200,
        repDelta: 20,
      ),
      FranchiseOption(
        label: 'Normal prep',
        tag: 'Risk: -15 reputation',
        repDelta: -15,
      ),
    ],
  ),
  FranchiseEvent(
    id: 'expand',
    title: 'Chance to expand seating',
    options: [
      FranchiseOption(
        label: 'Invest',
        tag: '+20% income forever',
        coinCost: 800,
        incomeMod: 1.2,
        modDays: -1,
      ),
      FranchiseOption(label: 'Not now', tag: 'No change'),
    ],
  ),
  FranchiseEvent(
    id: 'staff_leave',
    title: 'Key staff member leaving',
    options: [
      FranchiseOption(
        label: 'Match offer',
        tag: 'Staff stays',
        coinCost: 250,
        repDelta: 5,
      ),
      FranchiseOption(
        label: 'Let them go',
        tag: '-20% for 7 days',
        incomeMod: 0.8,
        modDays: 7,
        repDelta: -10,
      ),
    ],
  ),
  FranchiseEvent(
    id: 'menu_refresh',
    title: 'Menu refresh opportunity',
    options: [
      FranchiseOption(
        label: 'Refresh menu',
        tag: '+15% for 10 days',
        coinCost: 250,
        incomeMod: 1.15,
        modDays: 10,
      ),
      FranchiseOption(label: 'Keep it', tag: 'No change'),
    ],
  ),
  FranchiseEvent(
    id: 'regulars',
    title: 'Regulars hit a milestone',
    options: [
      FranchiseOption(
        label: 'Celebrate them',
        tag: '+15 reputation',
        coinCost: 100,
        repDelta: 15,
      ),
      FranchiseOption(
        label: 'Just note it',
        tag: '+5 reputation',
        repDelta: 5,
      ),
    ],
  ),
  FranchiseEvent(
    id: 'price_hike',
    title: 'Supplier raising prices',
    options: [
      FranchiseOption(
        label: 'Find new supplier',
        tag: '-5% for 3 days',
        incomeMod: 0.95,
        modDays: 3,
      ),
      FranchiseOption(
        label: 'Accept hike',
        tag: '-10% for 7 days',
        incomeMod: 0.9,
        modDays: 7,
      ),
    ],
  ),
  FranchiseEvent(
    id: 'quiet',
    title: 'Slow period ahead',
    options: [
      FranchiseOption(
        label: 'Reduce staff',
        tag: 'Save 100 coins, -10% income',
        coinCost: -100,
        incomeMod: 0.9,
        modDays: 7,
      ),
      FranchiseOption(label: 'Keep full team', tag: 'No change'),
    ],
  ),
];

// ── active income mod ─────────────────────────────────────────────────────────

class IncomeMod {
  IncomeMod({required this.multiplier, required this.daysLeft});

  final double multiplier;
  int daysLeft; // 999 = permanent
}

// ── owned franchise ───────────────────────────────────────────────────────────

class OwnedFranchise {
  OwnedFranchise({
    required this.defId,
    this.reputation = 50,
    Map<FranchiseUpgrade, int>? upgrades,
    List<IncomeMod>? activeMods,
    this.pendingEvent,
    this.eventDecided = false,
    this.lastIncome = 0,
    this.totalEarned = 0,
    List<String>? seenEvents,
  }) : upgrades = upgrades ?? {},
       activeMods = activeMods ?? [],
       seenEvents = seenEvents ?? [];

  final String defId;
  int reputation; // 0–100
  final Map<FranchiseUpgrade, int> upgrades;
  final List<IncomeMod> activeMods;
  FranchiseEvent? pendingEvent;
  bool eventDecided;
  int lastIncome;
  int totalEarned;
  final List<String> seenEvents;

  FranchiseDef get def => franchiseDefById(defId)!;

  int upgradeLevel(FranchiseUpgrade u) => upgrades[u] ?? 0;

  bool canUpgrade(FranchiseUpgrade u) => upgradeLevel(u) < maxUpgradeLevel;

  int upgradeCost(FranchiseUpgrade u) {
    final lvl = upgradeLevel(u);
    return lvl < maxUpgradeLevel ? upgradeCosts[lvl] : 0;
  }

  int dailyIncome() {
    final upgradeFactor =
        1.0 +
        FranchiseUpgrade.values.fold(
          0.0,
          (s, u) => s + 0.15 * upgradeLevel(u),
        );
    final modFactor = activeMods.fold(1.0, (s, m) => s * m.multiplier);
    final repFactor = 0.5 + reputation / 100.0;
    return (def.baseIncome * upgradeFactor * modFactor * repFactor)
        .round()
        .clamp(0, 9999);
  }

  /// Applies the player's choice: reputation and income mods. Coin cost is
  /// handled by the caller.
  void decide(FranchiseOption option) {
    if (eventDecided) return;
    eventDecided = true;
    reputation = (reputation + option.repDelta).clamp(0, 100);
    if (option.incomeMod != 1.0 && option.modDays != 0) {
      activeMods.add(IncomeMod(
        multiplier: option.incomeMod,
        daysLeft: option.modDays < 0 ? 999 : option.modDays,
      ));
    }
  }

  /// Called at the end of a day: ticks mods, earns income, queues next event.
  int endDay(Random rng) {
    for (final m in activeMods) {
      if (m.daysLeft != 999) m.daysLeft--;
    }
    activeMods.removeWhere((m) => m.daysLeft <= 0);
    if (reputation < 60) reputation = (reputation + 1).clamp(0, 100);
    final income = dailyIncome();
    lastIncome = income;
    totalEarned += income;
    pendingEvent = _pickEvent(rng);
    eventDecided = false;
    return income;
  }

  FranchiseEvent _pickEvent(Random rng) {
    final unseen =
        franchiseEventPool
            .where((e) => !seenEvents.contains(e.id))
            .toList();
    final pool = unseen.isEmpty ? franchiseEventPool : unseen;
    final event = pool[rng.nextInt(pool.length)];
    seenEvents.add(event.id);
    if (seenEvents.length > franchiseEventPool.length ~/ 2) {
      seenEvents.removeAt(0);
    }
    return event;
  }

  Map<String, Object?> toJson() => {
    'def': defId,
    'rep': reputation,
    'upgrades': {for (final e in upgrades.entries) e.key.name: e.value},
    'mods': [
      for (final m in activeMods) {'mul': m.multiplier, 'd': m.daysLeft},
    ],
    if (pendingEvent != null) 'event': pendingEvent!.id,
    'decided': eventDecided,
    'income': lastIncome,
    'total': totalEarned,
    'seen': seenEvents,
  };

  factory OwnedFranchise.fromJson(Map<String, Object?> j) {
    final f = OwnedFranchise(
      defId: j['def'] as String,
      reputation: (j['rep'] as int?) ?? 50,
      eventDecided: (j['decided'] as bool?) ?? false,
      lastIncome: (j['income'] as int?) ?? 0,
      totalEarned: (j['total'] as int?) ?? 0,
      seenEvents: [
        for (final s in (j['seen'] as List? ?? const [])) '$s',
      ],
    );
    final rawUpg = j['upgrades'] as Map? ?? {};
    for (final e in rawUpg.entries) {
      final u =
          FranchiseUpgrade.values
              .where((x) => x.name == '${e.key}')
              .firstOrNull;
      if (u != null) f.upgrades[u] = e.value as int;
    }
    for (final raw in (j['mods'] as List? ?? const [])) {
      final m = raw as Map;
      f.activeMods.add(IncomeMod(
        multiplier: (m['mul'] as num).toDouble(),
        daysLeft: m['d'] as int,
      ));
    }
    final eventId = j['event'] as String?;
    if (eventId != null) {
      f.pendingEvent =
          franchiseEventPool.where((e) => e.id == eventId).firstOrNull;
    }
    return f;
  }
}
