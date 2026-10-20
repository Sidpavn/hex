import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/pixel_hearts.dart';
import '../ui/pixel_pie.dart';
import '../ui/widgets.dart';
import 'build_screen.dart' show DinerSprite;
import 'contracts.dart';
import 'crowd.dart';
import 'diner.dart';
import 'events.dart';
import 'guests.dart';
import 'recipes.dart';
import 'regulars.dart';

/// The one thing worth saying about who comes, or null if there is not
/// enough to go on. Looks at who spends and who walks out.
String? crowdNote(Crowd c) {
  if (c.total < 10) return null;
  final spenders = Wallet.values.toList()
    ..sort((a, b) => c.ofWallet(b).total.compareTo(c.ofWallet(a).total));
  final top = spenders.first;
  final share = (100 * c.ofWallet(top).total / c.total).round();
  final label = switch (top) {
    Wallet.thrifty => 'thrifty guests',
    Wallet.regular => 'regular spenders',
    Wallet.wealthy => 'big spenders',
  };
  // Who leaves hungry most often, if it is a real difference.
  Wallet? worst;
  var worstRate = 0.3;
  for (final w in Wallet.values) {
    final t = c.ofWallet(w);
    if (t.total < 5) continue;
    final rate = t.lost / t.total;
    if (rate > worstRate) {
      worst = w;
      worstRate = rate;
    }
  }
  final who = worst == null
      ? ''
      : ' ${switch (worst) {
          Wallet.thrifty => 'Thrifty guests',
          Wallet.regular => 'Regular spenders',
          Wallet.wealthy => 'Big spenders',
        }} leave without eating most often (${(worstRate * 100).round()}%).';
  return 'Most of your guests are $label ($share%).$who';
}

/// What the menu is doing: what sells most and what earns most, if they are
/// not the same dish, and what is being thrown away.
String? dishNote(Crowd c, double Function(Dish) price) {
  final sold = c.bestSellers();
  if (sold.fold(0, (a, d) => a + c.ofDish(d).served) < 10) return null;
  final top = sold.first;
  // What a portion earns, for dishes sold often enough to tell.
  Dish? earner;
  var best = -1e9;
  for (final d in sold) {
    final t = c.ofDish(d);
    if (t.served < 5) continue;
    final per = t.profit / t.served;
    if (per > best) {
      best = per;
      earner = d;
    }
  }
  final parts = <String>[];
  if (earner != null && earner != top) {
    parts.add(
      '${recipes[top]!.name} sells most. ${recipes[earner]!.name} earns the '
      'most a portion (${best.toStringAsFixed(1)}).',
    );
  } else {
    parts.add('${recipes[top]!.name} is your best seller and best earner.');
  }
  final waste = sold.where((d) => c.ofDish(d).lost >= 5).toList()
    ..sort((a, b) => c.ofDish(b).lost.compareTo(c.ofDish(a).lost));
  if (waste.isNotEmpty) {
    final w = waste.first;
    parts.add(
      '${c.ofDish(w).lost} ${recipes[w]!.name.toLowerCase()} were thrown '
      'away.',
    );
  }
  return parts.join(' ');
}

/// How the days have gone: the best, the worst and the average, and how
/// event days compare with plain ones.
String? daysNote(List<DayLog> log) {
  if (log.length < 3) return null;
  final kept = log.map((d) => d.kept);
  final avg = (kept.reduce((a, b) => a + b) / log.length).round();
  final parts = <String>[
    'Best day +${kept.reduce(math.max)}, worst '
        '${kept.reduce(math.min)}, average $avg.',
  ];
  final ev = log.where((d) => d.event.isNotEmpty).toList();
  final plain = log.where((d) => d.event.isEmpty).toList();
  if (ev.length >= 2 && plain.length >= 2) {
    int mean(List<DayLog> l) =>
        (l.map((d) => d.kept).reduce((a, b) => a + b) / l.length).round();
    parts.add('Event days kept ${mean(ev)}, plain days ${mean(plain)}.');
  }
  return parts.join(' ');
}

/// When the doors are busiest, in words.
String busiestTime(Crowd c) {
  if (c.hours.every((h) => h == 0)) return 'No arrivals counted yet.';
  var best = 0;
  for (var i = 1; i < c.hours.length; i++) {
    if (c.hours[i] > c.hours[best]) best = i;
  }
  final when = best <= 2
      ? 'early in the day'
      : best <= 4
      ? 'around midday'
      : 'late in the day';
  return 'Busiest $when.';
}

/// When catering orders come, and whether they are coming now.
String cateringLine(double rating) {
  const min = ContractBook.minRating;
  return rating >= min
      ? 'Catering orders come to you at ${min.toStringAsFixed(1)} stars and '
            'above. Some days have one.'
      : 'Catering orders start at ${min.toStringAsFixed(1)} stars. You are '
            '${(((min - rating) * 10).ceil() / 10).toStringAsFixed(1)} short.';
}

enum _Tab {
  guests('Guests'),
  dishes('Dishes'),
  regulars('Regulars'),
  days('Days');

  const _Tab(this.label);
  final String label;
}

/// Numbers for making decisions: who comes and when, what sells and what
/// earns, and how the days have gone.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, required this.diner});

  final Diner diner;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  _Tab _tab = _Tab.guests;
  bool _lastDay = false;

  Diner get diner => widget.diner;

  Crowd get _crowd => _lastDay ? (diner.lastCrowd ?? Crowd()) : diner.crowd;

  @override
  Widget build(BuildContext context) {
    final c = _crowd;
    return ScreenFrame(
      title: 'Stats',
      subtitle: switch (_tab) {
        _Tab.regulars =>
          '${diner.regulars.people.length} of '
              '${RegularBook.cap(diner.progress.level)} regulars',
        _Tab.days =>
          diner.history.isEmpty
              ? 'No days yet'
              : 'The last ${math.min(diner.history.length, _days)} days',
        _ =>
          c.isEmpty
              ? 'Nobody yet'
              : '${c.total} guests, ${c.served} fed, ${c.lost} left without '
                    'eating',
      },
      trailing: PxText(
        ':coin: ${diner.coins}',
        style: const TextStyle(color: Pal.text, fontSize: 20),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in _Tab.values)
                Choice(
                  key: ValueKey('tab-${t.name}'),
                  label: t.label,
                  selected: _tab == t,
                  onTap: () => setState(() => _tab = t),
                ),
            ],
          ),
          if (_tab != _Tab.days && _tab != _Tab.regulars) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                Choice(
                  key: const ValueKey('crowd-all'),
                  label: 'All days',
                  selected: !_lastDay,
                  onTap: () => setState(() => _lastDay = false),
                ),
                Choice(
                  key: const ValueKey('crowd-last'),
                  label: 'Last day',
                  selected: _lastDay,
                  onTap: () => setState(() => _lastDay = true),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          ...switch (_tab) {
            _Tab.guests => _guests(c),
            _Tab.dishes => _dishes(c),
            _Tab.regulars => _regulars(),
            _Tab.days => _daysTab(),
          },
        ],
      ),
    );
  }

  Widget _empty(String key, String text) => PxText(
    text,
    key: ValueKey(key),
    style: const TextStyle(color: Pal.dim, fontSize: 14),
  );

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: PxText(
      text,
      key: const ValueKey('note'),
      style: const TextStyle(color: Pal.text, fontSize: 14),
    ),
  );

  // ----------------------------------------------------------- guests

  static const _genderColours = {
    Gender.woman: Pal.gold,
    Gender.man: Pal.blue,
    Gender.nonbinary: Pal.purple,
  };

  /// More gold the more they spend.
  static const _walletColours = {
    Wallet.thrifty: Pal.dimmer,
    Wallet.regular: Pal.blue,
    Wallet.wealthy: Pal.gold,
  };

  List<Widget> _guests(Crowd c) {
    if (c.isEmpty) {
      return [
        _empty('crowd-empty', 'No guests yet. Run a day and this fills in.'),
      ];
    }
    final note = crowdNote(c);
    return [
      if (note != null) _note(note),
      const Eyebrow('Who comes'),
      _chart('by-gender', [
        for (final g in Gender.values)
          (
            'gender-${g.name}',
            g.label,
            c.ofGender(g).total,
            _genderColours[g]!,
            '${c.ofGender(g).total} guests',
          ),
      ], c.total),
      const SizedBox(height: 12),
      const Eyebrow('How they spend'),
      _chart('by-wallet', [
        for (final w in Wallet.values)
          (
            'wallet-${w.name}',
            w.label,
            c.ofWallet(w).total,
            _walletColours[w]!,
            c.ofWallet(w).served > 0
                ? '${c.ofWallet(w).total} guests, '
                      '${c.ofWallet(w).average.toStringAsFixed(1)} each'
                : '${c.ofWallet(w).total} guests',
          ),
      ], c.total),
      const SizedBox(height: 12),
      const Eyebrow('When they come'),
      Panel(
        key: const ValueKey('by-time'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: PixelColumns(values: c.hours, width: 10, gap: 3)),
            const SizedBox(height: 4),
            Row(
              children: const [
                Expanded(
                  child: PxText(
                    'Opening',
                    style: TextStyle(color: Pal.dim, fontSize: 13),
                  ),
                ),
                PxText(
                  'Closing',
                  style: TextStyle(color: Pal.dim, fontSize: 13),
                ),
              ],
            ),
            PxText(
              busiestTime(c),
              key: const ValueKey('busiest'),
              style: const TextStyle(color: Pal.text, fontSize: 14),
            ),
          ],
        ),
      ),
    ];
  }

  /// A pie with a key beside it: each slice's colour, name and share, and a
  /// line under the name.
  Widget _chart(
    String key,
    List<(String, String, int, Color, String)> slices,
    int all,
  ) {
    return Panel(
      key: ValueKey(key),
      child: Row(
        children: [
          PixelPie(
            key: ValueKey('$key-pie'),
            values: [for (final s in slices) s.$3],
            colors: [for (final s in slices) s.$4],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final s in slices) _key(s.$1, s.$2, s.$3, s.$4, s.$5, all),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _key(
    String key,
    String label,
    int n,
    Color colour,
    String detail,
    int all,
  ) {
    final share = all == 0 ? 0 : (100 * n / all).round();
    return Padding(
      key: ValueKey(key),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(width: 8, height: 8, child: ColoredBox(color: colour)),
              const SizedBox(width: 8),
              Expanded(
                child: PxText(
                  label,
                  style: const TextStyle(color: Pal.text, fontSize: 15),
                ),
              ),
              PxText(
                '$share%',
                key: ValueKey('$key-share'),
                style: const TextStyle(color: Pal.text, fontSize: 15),
              ),
            ],
          ),
          PxText(
            detail,
            key: ValueKey('$key-detail'),
            style: const TextStyle(color: Pal.dim, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------- dishes

  static const _dishColours = [
    Pal.gold,
    Pal.blue,
    Pal.green,
    Pal.purple,
    Pal.red,
  ];

  List<Widget> _dishes(Crowd c) {
    final sold = c.bestSellers();
    if (sold.isEmpty) {
      return [
        _empty(
          'dishes-empty',
          'Nothing sold yet. Run a day and this fills in.',
        ),
      ];
    }
    final note = dishNote(c, diner.sellPrice);
    final top = sold.take(_dishColours.length).toList();
    final rest = sold
        .skip(top.length)
        .fold(0, (a, d) => a + c.ofDish(d).served);
    final portions = sold.fold(0, (a, d) => a + c.ofDish(d).served);
    return [
      if (note != null) _note(note),
      const Eyebrow('What sells'),
      _chart('by-dish', [
        for (final (i, d) in top.indexed)
          (
            'share-${d.name}',
            recipes[d]!.name,
            c.ofDish(d).served,
            _dishColours[i],
            '${c.ofDish(d).served} sold',
          ),
        if (rest > 0) ('share-other', 'Other', rest, Pal.dimmer, '$rest sold'),
      ], portions),
      const SizedBox(height: 12),
      const Eyebrow('What earns'),
      Panel(
        key: const ValueKey('best-sellers'),
        child: Column(
          children: [for (final (i, d) in sold.indexed) _dishRow(i + 1, d, c)],
        ),
      ),
    ];
  }

  Widget _dishRow(int rank, Dish d, Crowd c) {
    final t = c.ofDish(d);
    final per = t.served == 0 ? 0.0 : t.profit / t.served;
    return Padding(
      key: ValueKey('seller-${d.name}'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: PxText(
              '$rank',
              style: const TextStyle(color: Pal.gold, fontSize: 15),
            ),
          ),
          SizedBox(width: 32, child: DinerSprite('ico_${d.name}', mult: 3)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PxText(
                  recipes[d]!.name,
                  style: const TextStyle(color: Pal.text, fontSize: 15),
                ),
                PxText(
                  '${t.served} sold, '
                  '${per >= 0 ? '+' : ''}${per.toStringAsFixed(1)} a portion'
                  '${t.lost > 0 ? ', ${t.lost} thrown away' : ''}',
                  key: ValueKey('seller-${d.name}-detail'),
                  style: TextStyle(
                    // Red only when a real share of it went in the bin.
                    color: t.lost >= 5 && t.lost * 4 > t.served
                        ? Pal.red
                        : Pal.dim,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          PxText(
            '${t.profit >= 0 ? '+' : ''}${t.profit}',
            key: ValueKey('seller-${d.name}-profit'),
            style: TextStyle(
              color: t.profit >= 0 ? Pal.green : Pal.red,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------- regulars

  List<Widget> _regulars() {
    final list = [...diner.regulars.people]
      ..sort((a, b) {
        final h = b.points.compareTo(a.points);
        return h != 0 ? h : a.name.compareTo(b.name);
      });
    final cap = RegularBook.cap(diner.progress.level);
    if (list.isEmpty) {
      return [
        _empty(
          'regulars-empty',
          'No regulars yet. A guest who leaves happy may come back for good. '
              'There is room for $cap.',
        ),
      ];
    }
    return [
      _note(
        '${list.length} of $cap regulars. Each heart brings someone in a '
        'little more often, tipping a little more and waiting a little '
        'longer. Fail them and they drift away.',
      ),
      Panel(
        key: const ValueKey('regulars-list'),
        child: Column(children: [for (final r in list) _regularRow(r)]),
      ),
    ];
  }

  Widget _regularRow(Regular r) {
    final today = r.lastDay == diner.progress.day;
    return Padding(
      key: ValueKey('regular-${r.id}'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: DinerSprite('ico_${r.favourite.name}', mult: 3),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PxText(
                  r.name,
                  style: const TextStyle(color: Pal.text, fontSize: 15),
                ),
                PxText(
                  'Likes ${recipes[r.favourite]!.name.toLowerCase()}. '
                  '${r.visits} ${r.visits == 1 ? 'visit' : 'visits'}'
                  '${r.lastDay == 0
                      ? ''
                      : today
                      ? ', here today'
                      : ', last day ${r.lastDay}'}.',
                  key: ValueKey('regular-${r.id}-detail'),
                  style: const TextStyle(color: Pal.dim, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _hearts(r),
        ],
      ),
    );
  }

  /// Five hearts, red for each they have.
  Widget _hearts(Regular r) =>
      PixelHearts(key: ValueKey('hearts-${r.id}'), filled: r.hearts);

  // ------------------------------------------------------------- days

  static const _days = 14;

  List<Widget> _daysTab() {
    final log = diner.history;
    if (log.isEmpty) {
      return [
        _empty('days-empty', 'No days yet. Finish a day and this fills in.'),
      ];
    }
    final shown = log.length > _days ? log.sublist(log.length - _days) : log;
    final note = daysNote(log);
    final rating = shown.last.rating - shown.first.rating;
    return [
      if (note != null) _note(note),
      const Eyebrow('What was kept each day'),
      Panel(
        key: const ValueKey('by-day'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: PixelColumns(
                values: [for (final d in shown) d.kept],
                up: Pal.green,
                down: Pal.red,
                width: 7,
                gap: 2,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: PxText(
                    'Day ${shown.first.day}',
                    style: const TextStyle(color: Pal.dim, fontSize: 13),
                  ),
                ),
                PxText(
                  'Day ${shown.last.day}',
                  style: const TextStyle(color: Pal.dim, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      const Eyebrow('Rating'),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Stars((shown.last.rating / 20).round(), of: 5),
                const SizedBox(width: 8),
                Expanded(
                  child: PxText(
                    shown.length < 2
                        ? (shown.last.rating / 20).toStringAsFixed(1)
                        : '${(shown.last.rating / 20).toStringAsFixed(1)}, '
                              '${rating == 0 ? 'no change' : '${rating > 0 ? 'up' : 'down'} '
                                        '${(rating.abs() / 20).toStringAsFixed(1)}'} '
                              'over ${shown.length} days',
                    key: const ValueKey('rating-trend'),
                    style: TextStyle(
                      color: rating > 0
                          ? Pal.green
                          : rating < 0
                          ? Pal.red
                          : Pal.text,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            PxText(
              cateringLine(diner.progress.rating),
              key: const ValueKey('catering-rule'),
              style: TextStyle(
                color: diner.progress.rating >= ContractBook.minRating
                    ? Pal.green
                    : Pal.dim,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      const Eyebrow('Recent days'),
      Panel(
        key: const ValueKey('recent-days'),
        child: Column(
          children: [for (final d in shown.reversed.take(5)) _dayRow(d)],
        ),
      ),
    ];
  }

  Widget _dayRow(DayLog d) {
    final event = DayEvent.values.where((e) => e.name == d.event).firstOrNull;
    return Padding(
      key: ValueKey('day-${d.day}'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: PxText(
              'Day ${d.day}',
              style: const TextStyle(color: Pal.text, fontSize: 15),
            ),
          ),
          Expanded(
            child: PxText(
              '${d.served} fed, ${d.walkouts} left'
              '${event == null ? '' : ', ${event.label.toLowerCase()}'}',
              style: const TextStyle(color: Pal.dim, fontSize: 13),
            ),
          ),
          PxText(
            '${d.kept >= 0 ? '+' : ''}${d.kept}',
            style: TextStyle(
              color: d.kept >= 0 ? Pal.green : Pal.red,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
