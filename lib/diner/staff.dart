/// The people who work in the restaurant: what they are good at, what they
/// cost, how they improve, and where new ones come from. Pure Dart.
library;

import 'dart:math' as math;

import 'diner.dart' show Kind;
import 'recipes.dart';
import 'traits.dart';

enum Stat { cooking, speed, service, charm }

/// How their last payday went.
enum Pay { none, paid, missed }

class StatInfo {
  const StatInfo(this.name, this.info);

  final String name;
  final String info;
}

const Map<Stat, StatInfo> statInfo = {
  Stat.cooking: StatInfo(
    'Cooking',
    'Food they cook sells for more, and so tips more: about 4% on the price '
        'for every point above 3.',
  ),
  Stat.speed: StatInfo(
    'Speed',
    'Walks faster. At 5 they cover a tile a tick; every point is a little '
        'quicker or slower than that.',
  ),
  Stat.service: StatInfo(
    'Service',
    'Spends less time handling each plate, every time they load, collect or '
        'serve one.',
  ),
  Stat.charm: StatInfo(
    'Charm',
    'Guests wait longer before they give up, and tip more when this person '
        'serves them.',
  ),
};

/// One employee, or one candidate for a job.
/// What a member of staff can be set to do besides cooking.
enum Task { serve, clear, window }

class Staff {
  Staff({
    required this.id,
    required this.name,
    required Map<Stat, int> stats,
    required Map<Stat, int> potential,
    this.morale = maxMorale,
    this.trainedToday = false,
    this.daysWorked = 0,
    List<Trait>? traits,
    Set<Trait>? known,
    this.grudge = 0,
    this.bloomed = false,
    List<String>? memories,
    this.plates = 0,
    this.drops = 0,
    this.lastPay = Pay.none,
    Map<Dish, int>? mastery,
    this.specialty,
    Kind? duty,
    Set<Task>? tasks,
    this.cooksAt,
    this.focus,
    this.walkIn = false,
  }) : mastery = mastery ?? {},
       traits = traits ?? [],
       known = known ?? {},
       memories = memories ?? [],
       stats = Map.of(stats),
       potential = Map.of(potential),
       tasks = tasks ?? {Task.serve} {
    // A person made with a single old-style duty.
    if (duty != null) this.duty = duty;
  }

  static const maxStat = 10;
  static const maxMorale = 3;

  final int id;
  final String name;
  final Map<Stat, int> stats;

  /// The most each stat can ever reach through training.
  final Map<Stat, int> potential;

  /// Unpaid wages sour people; at nothing they quit.
  int morale;

  /// Training takes the day: one stat, once a day.
  bool trainedToday;
  int daysWorked;

  /// Their quirks, and which of them the player has found out about. A
  /// candidate shows one; the rest come out over time, or when they bite.
  final List<Trait> traits;
  final Set<Trait> known;

  /// A missed payday not yet felt: loyal people take two to lose heart.
  int grudge;
  bool bloomed;

  /// The last few things that happened to them, newest first.
  final List<String> memories;

  /// Whether the last payday came through.
  Pay lastPay;

  /// How many of each dish they have made. The more, the better they get.
  final Map<Dish, int> mastery;

  /// The dish they came here knowing how to make, if any.
  final Dish? specialty;

  /// What they do besides cook: carry food out, clear tables, run the
  /// takeaway window. Everyone starts by carrying food out.
  Set<Task> tasks;

  /// The machines they cook at. Null means every machine, including any
  /// bought later; an empty set means they do not cook.
  Set<Kind>? cooksAt;

  /// The machine they look after first, and help elsewhere when it needs
  /// nothing. Null means no preference.
  Kind? focus;

  /// Whether they cook at all.
  bool get cooks => cooksAt == null || cooksAt!.isNotEmpty;

  bool does(Task t) => tasks.contains(t);

  /// Whether they may cook at a machine of [kind].
  bool cooksAtKind(Kind kind) => cooksAt == null || cooksAt!.contains(kind);

  /// The old single duty, for saves from before tasks and for short ways of
  /// setting a person up: a machine they prefer, clearing tables, the window,
  /// or serving food, or null for the usual work.
  Kind? get duty {
    if (tasks.length == 1 && cooksAt != null && cooksAt!.isEmpty) {
      return switch (tasks.first) {
        Task.clear => Kind.table,
        Task.window => Kind.window,
        Task.serve => Kind.pass,
      };
    }
    return focus;
  }

  set duty(Kind? k) {
    focus = null;
    switch (k) {
      case null:
        tasks = {Task.serve};
        cooksAt = null;
      case Kind.table:
        tasks = {Task.clear};
        cooksAt = {};
      case Kind.window:
        tasks = {Task.window};
        cooksAt = {};
      case Kind.pass:
        tasks = {Task.serve};
        cooksAt = {};
      default:
        tasks = {Task.serve};
        cooksAt = null;
        focus = k;
    }
  }

  /// Dishes made to reach each level of mastery.
  static const masteryAt = [8, 25, 60];

  int made(Dish d) => mastery[d] ?? 0;

  /// 0 to 3: how well they know the dish. Specialists start at 2.
  int masteryLevel(Dish d) {
    var n = made(d);
    if (specialty == d) n += masteryAt[1];
    var lvl = 0;
    for (final t in masteryAt) {
      if (n >= t) lvl++;
    }
    return lvl;
  }

  /// Whether they know how to make [d] at all.
  bool canCook(Dish d) => !recipes[d]!.skilled || masteryLevel(d) >= 1;

  /// Teaches them the basics of [d], so they can start making it.
  void teach(Dish d) {
    if (made(d) < masteryAt[0]) mastery[d] = masteryAt[0];
  }

  /// What a dish sells for when they make it, as a multiple.
  double masteryPrice(Dish d) => 1 + 0.04 * masteryLevel(d);

  /// How much quicker they cook a dish they know well.
  double masteryTime(Dish d) => 1 - 0.08 * masteryLevel(d);

  /// Plates served and plates dropped, over their whole time here.
  int plates;
  int drops;

  bool has(Trait t) => traits.contains(t);

  /// How they feel, in a word.
  String get mood => switch (morale) {
    >= 3 => 'Happy',
    2 => 'Content',
    1 => 'Fed up',
    _ => 'Leaving',
  };

  /// Why, and what happens next: the thing a manager would want to know.
  String get moodNote {
    final loyalNote = has(Trait.loyal)
        ? 'Loyal, so they will put up with one more.'
        : has(Trait.hotHeaded)
        ? 'Hot-headed: one more and they walk out.'
        : 'Another missed payday and they quit.';
    return switch (morale) {
      >= 3 =>
        lastPay == Pay.paid ? 'Paid on time. Feels valued.' : 'Settling in.',
      2 =>
        lastPay == Pay.missed
            ? 'Missed a payday. Still hanging on.'
            : 'Fine for now.',
      1 => 'Fed up with the money. $loyalNote',
      _ => 'About to leave.',
    };
  }

  /// Traits the player can see, and how many are still hidden.
  List<Trait> get visibleTraits => [
    for (final t in traits)
      if (known.contains(t)) t,
  ];
  int get hiddenTraits => traits.length - visibleTraits.length;

  /// Makes [t] known. Returns true if it was news.
  bool reveal(Trait t) => traits.contains(t) && known.add(t);

  void revealAll() => known.addAll(traits);

  void remember(int day, String what) {
    memories.insert(0, 'Day $day: $what');
    if (memories.length > 5) memories.removeLast();
  }

  int stat(Stat s) => stats[s] ?? 1;
  int cap(Stat s) => potential[s] ?? stat(s);

  int get total => Stat.values.fold(0, (a, s) => a + stat(s));
  int get headroom => Stat.values.fold(0, (a, s) => a + cap(s) - stat(s));

  /// What they are paid each day: more for the skilled, and a little more for
  /// those who could still become something.
  int get salary {
    var pay = 2 + 0.5 * total + 0.25 * headroom;
    for (final t in traits) {
      pay *= traitInfo[t]!.salary;
    }
    // A specialist is worth a little more.
    if (specialty != null) pay *= 1.15;
    return pay.round();
  }

  /// They came in off the street asking for work, so they ask for less: two
  /// days' wages instead of four.
  final bool walkIn;

  /// What it costs to take them on: four days' wages.
  int get fee => salary * (walkIn ? 2 : 4);

  /// Paid to let them go: a day's wages.
  int get severance => salary;

  /// Whether they work the kitchen or the floor, by what they are best at.
  /// Cooks stay by the machines; floor staff carry.
  bool get kitchen =>
      stat(Stat.cooking) >= math.max(stat(Stat.service), stat(Stat.speed));

  String get role => kitchen ? 'Kitchen' : 'Floor';

  bool canTrain(Stat s) => !trainedToday && stat(s) < cap(s);

  /// What raising [s] by a point costs.
  int trainCost(Stat s) =>
      (15 * stat(s) * (has(Trait.fastLearner) ? 0.7 : 1.0)).round();

  void train(Stat s) {
    stats[s] = stat(s) + 1;
    trainedToday = true;
  }

  /// What a guest pays, as a multiple of the menu price, for food this
  /// person cooked.
  double get priceFactor =>
      (1 + 0.04 * (stat(Stat.cooking) - 3)).clamp(0.85, 1.3) *
      (has(Trait.perfectionist) ? 1.12 : 1.0);

  /// Tiles walked per tick.
  double get pace => 0.6 + 0.08 * stat(Stat.speed);

  /// Ticks spent handling a plate: a fraction, so every point of service
  /// counts. Over many plates it averages out exactly.
  double get handlingTicks =>
      ((2.5 - 0.22 * stat(Stat.service)).clamp(0.2, 2.5) *
              (has(Trait.quickHands) ? 0.7 : 1.0) *
              (has(Trait.perfectionist) ? 1.1 : 1.0))
          .clamp(0.1, 3.5);

  /// Extra fraction of the price tipped.
  double get tipBonus => 0.02 * (stat(Stat.charm) - 3);

  /// How much slower guests lose patience while this person is on the team,
  /// as a fraction of the usual rate.
  double get calm =>
      0.03 * (stat(Stat.charm) - 3) + (has(Trait.cheerful) ? 0.06 : 0);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'stats': {for (final e in stats.entries) e.key.name: e.value},
    'cap': {for (final e in potential.entries) e.key.name: e.value},
    'morale': morale,
    'trained': trainedToday,
    'days': daysWorked,
    'traits': [for (final t in traits) t.name],
    'known': [for (final t in known) t.name],
    'grudge': grudge,
    'bloomed': bloomed,
    'memories': memories,
    'plates': plates,
    'drops': drops,
    'pay': lastPay.name,
    'mastery': {for (final e in mastery.entries) e.key.name: e.value},
    'specialty': specialty?.name,
    'tasks': [for (final t in tasks) t.name],
    if (cooksAt != null) 'cooks': [for (final k in cooksAt!) k.name],
    if (focus != null) 'focus': focus!.name,
    if (walkIn) 'walkIn': true,
  };

  static List<Trait> readTraits(Object? raw) => [
    if (raw is List)
      for (final n in raw) ...Trait.values.where((t) => t.name == n),
  ];

  static Staff? fromJson(Object? raw) {
    if (raw is! Map) return null;
    Map<Stat, int> read(Object? m, int fallback) {
      final out = <Stat, int>{};
      for (final s in Stat.values) {
        final v = m is Map ? m[s.name] : null;
        out[s] = (v is int ? v : fallback).clamp(1, maxStat);
      }
      return out;
    }

    final stats = read(raw['stats'], 3);
    final caps = read(raw['cap'], 5);
    for (final s in Stat.values) {
      if (caps[s]! < stats[s]!) caps[s] = stats[s]!;
    }
    return Staff(
      id: (raw['id'] as int?) ?? 0,
      name: (raw['name'] as String?) ?? 'Staff',
      stats: stats,
      potential: caps,
      morale: ((raw['morale'] as int?) ?? maxMorale).clamp(0, maxMorale),
      trainedToday: raw['trained'] == true,
      daysWorked: (raw['days'] as int?) ?? 0,
      traits: readTraits(raw['traits']),
      known: readTraits(raw['known']).toSet(),
      grudge: (raw['grudge'] as int?) ?? 0,
      bloomed: raw['bloomed'] == true,
      memories: [
        for (final m in (raw['memories'] as List?) ?? const [])
          if (m is String) m,
      ],
      plates: (raw['plates'] as int?) ?? 0,
      drops: (raw['drops'] as int?) ?? 0,
      lastPay:
          Pay.values.where((p) => p.name == raw['pay']).firstOrNull ?? Pay.none,
      mastery: {
        if (raw['mastery'] is Map)
          for (final d in Dish.values)
            if ((raw['mastery'] as Map)[d.name] is int)
              d: (raw['mastery'] as Map)[d.name] as int,
      },
      specialty: Dish.values
          .where((d) => d.name == raw['specialty'])
          .firstOrNull,
      // Older saves have one duty; newer ones have tasks and machines.
      duty: raw['tasks'] is List
          ? null
          : Kind.values.where((k) => k.name == raw['duty']).firstOrNull,
      tasks: raw['tasks'] is List
          ? {
              for (final n in raw['tasks'] as List)
                ...Task.values.where((t) => t.name == n),
            }
          : null,
      cooksAt: raw['tasks'] is List && raw['cooks'] is List
          ? {
              for (final n in raw['cooks'] as List)
                ...Kind.values.where((k) => k.name == n),
            }
          : null,
      focus: raw['tasks'] is List
          ? Kind.values.where((k) => k.name == raw['focus']).firstOrNull
          : null,
      walkIn: raw['walkIn'] == true,
    );
  }
}

const _names = [
  'Ana',
  'Ben',
  'Cleo',
  'Dev',
  'Eli',
  'Faye',
  'Gus',
  'Hana',
  'Ivo',
  'Jade',
  'Kofi',
  'Lena',
  'Milo',
  'Nia',
  'Omar',
  'Pia',
  'Quin',
  'Rosa',
  'Sven',
  'Tess',
  'Uma',
  'Vik',
  'Wren',
  'Xan',
  'Yara',
  'Zed',
  'Bo',
  'Cass',
  'Dora',
  'Finn',
];

/// Who works here, and who is looking for work.
/// Where to look for staff, and what each way of looking costs and brings.
enum Ad { notice, paper, agency }

class AdDef {
  const AdDef(
    this.name,
    this.cost,
    this.count,
    this.bonus,
    this.specialist,
    this.gift,
    this.info,
  );

  final String name;
  final int cost;

  /// How many people answer.
  final int count;

  /// Added to how good applicants are likely to be.
  final double bonus;

  /// Chances that someone comes knowing a hard dish, and has a real gift.
  final double specialist;
  final double gift;
  final String info;
}

const Map<Ad, AdDef> adDefs = {
  Ad.notice: AdDef(
    'Notice board',
    30,
    2,
    -0.6,
    0.08,
    0.05,
    'Two applicants, mostly beginners.',
  ),
  Ad.paper: AdDef(
    'Local paper',
    90,
    3,
    0,
    0.22,
    0.12,
    'Three applicants of the usual sort.',
  ),
  Ad.agency: AdDef(
    'Hiring agency',
    240,
    3,
    1.4,
    0.45,
    0.3,
    'Three experienced applicants, many with a speciality.',
  ),
};

class Roster {
  Roster({List<Staff>? employees, List<Staff>? candidates})
    : employees = employees ?? [],
      candidates = candidates ?? [];

  /// The restaurant begins with one person, who is not very good.
  factory Roster.starter() => Roster(
    employees: [
      Staff(
        id: 1,
        name: 'Sam',
        stats: {Stat.cooking: 4, Stat.speed: 4, Stat.service: 3, Stat.charm: 3},
        potential: {
          Stat.cooking: 6,
          Stat.speed: 6,
          Stat.service: 5,
          Stat.charm: 5,
        },
        traits: [Trait.loyal],
        known: {Trait.loyal},
      ),
    ],
  );

  final List<Staff> employees;
  List<Staff> candidates;

  /// The day the candidates answered, and how many adverts were placed that
  /// day. Nobody applies until an advert has been paid for.
  int candidateDay = 0;
  int refreshes = 0;
  int nextId = 100;

  /// Wages for the whole team.
  int get wages => employees.fold(0, (a, s) => a + s.salary);

  /// Makes a new pool of people to answer [ad]. Better restaurants draw
  /// better applicants (the level and rating lift what is on offer), and a
  /// dearer advert reaches better people still.
  void rollCandidates(int day, int level, double rating, Ad ad) {
    final def = adDefs[ad]!;
    final rng = math.Random(
      day * 7919 + refreshes * 104729 + ad.index * 1299709 + 17,
    );
    final taken = {for (final e in employees) e.name};
    final out = <Staff>[];
    final mean = 2.2 + level * 0.45 + rating * 0.35 + def.bonus;
    while (out.length < def.count) {
      final name = _names[rng.nextInt(_names.length)];
      if (taken.contains(name)) continue;
      taken.add(name);
      final stats = <Stat, int>{};
      final caps = <Stat, int>{};
      for (final s in Stat.values) {
        final v = (mean + (rng.nextDouble() - 0.5) * 4.5).round().clamp(1, 8);
        stats[s] = v;
        caps[s] = (v + 1 + rng.nextInt(3 + (level ~/ 2))).clamp(
          v,
          Staff.maxStat,
        );
      }
      // Now and then, someone with a real gift.
      if (rng.nextDouble() < def.gift) {
        final s = Stat.values[rng.nextInt(Stat.values.length)];
        stats[s] = (stats[s]! + 2).clamp(1, 9);
        caps[s] = (caps[s]! + 2).clamp(stats[s]!, Staff.maxStat);
      }
      final traits = _rollTraits(rng);
      if (traits.contains(Trait.lateBloomer)) {
        // Weak now, strong later.
        for (final s in Stat.values) {
          stats[s] = (stats[s]! - 1).clamp(1, 10);
          caps[s] = (caps[s]! + 2).clamp(stats[s]!, Staff.maxStat);
        }
      }
      // Some come knowing a dish the restaurant may want to make.
      final skilled = [
        for (final r in recipes.values)
          if (r.skilled && r.unlock <= level + 1) r.dish,
      ];
      final specialty = skilled.isNotEmpty && rng.nextDouble() < def.specialist
          ? skilled[rng.nextInt(skilled.length)]
          : null;
      out.add(
        Staff(
          id: nextId++,
          name: name,
          stats: stats,
          potential: caps,
          traits: traits,
          // You find out about the first one at the interview.
          known: traits.isEmpty ? {} : {traits.first},
          specialty: specialty,
        ),
      );
    }
    // Anyone who walked in off the street today is still here.
    final walkIns = candidateDay == day
        ? [
            for (final s in candidates)
              if (s.walkIn) s,
          ]
        : <Staff>[];
    candidates = [...walkIns, ...out];
    candidateDay = day;
  }

  /// Someone who walks in asking for work on [day]: a person like any who
  /// might answer a small advert, but they came without being asked.
  Staff walkInApplicant(int day, int level, double rating) {
    final pool = Roster(employees: employees)
      ..nextId = nextId
      ..refreshes = 41;
    pool.rollCandidates(day, level, rating, Ad.values.first);
    final s = pool.candidates.first;
    nextId = pool.nextId;
    return Staff(
      id: s.id,
      name: s.name,
      stats: s.stats,
      potential: s.potential,
      traits: s.traits,
      known: s.known,
      specialty: s.specialty,
      walkIn: true,
    );
  }

  /// Zero, one or two quirks. Good ones are the more common, and a good one
  /// often comes with a flaw, so nobody is simply the best.
  static List<Trait> _rollTraits(math.Random rng) {
    final good = [
      for (final t in Trait.values)
        if (traitInfo[t]!.tone == Tone.good) t,
    ];
    final bad = [
      for (final t in Trait.values)
        if (traitInfo[t]!.tone != Tone.good) t,
    ];
    final r = rng.nextDouble();
    if (r < 0.2) return [];
    final first = r < 0.75
        ? good[rng.nextInt(good.length)]
        : bad[rng.nextInt(bad.length)];
    final second = rng.nextDouble() < 0.5;
    if (!second) return [first];
    final pool = traitInfo[first]!.tone == Tone.good ? bad : good;
    final other = pool[rng.nextInt(pool.length)];
    return other == first ? [first] : [first, other];
  }

  /// Anyone who answered an earlier day's advert has found something else.
  void dropStale(int day) {
    if (candidateDay == day) return;
    candidates = [];
    refreshes = 0;
    candidateDay = day;
  }

  Map<String, Object?> toJson() => {
    'employees': [for (final s in employees) s.toJson()],
    'candidates': [for (final s in candidates) s.toJson()],
    'cday': candidateDay,
    'refreshes': refreshes,
    'nid': nextId,
  };

  static Roster fromJson(Object? raw) {
    if (raw is! Map) return Roster.starter();
    final r = Roster(
      employees: [
        for (final e in (raw['employees'] as List?) ?? const [])
          ?Staff.fromJson(e),
      ],
      candidates: [
        for (final e in (raw['candidates'] as List?) ?? const [])
          ?Staff.fromJson(e),
      ],
    );
    r.candidateDay = (raw['cday'] as int?) ?? 0;
    r.refreshes = (raw['refreshes'] as int?) ?? 0;
    r.nextId = math.max((raw['nid'] as int?) ?? 100, 100);
    return r;
  }
}
