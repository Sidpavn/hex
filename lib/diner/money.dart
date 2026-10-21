import 'crowd.dart';
import 'service.dart';
import 'suppliers.dart';

/// "Took 140, costs 95": what came in and what went out, to read beside what
/// was kept.
String profitLine(DayReport r) =>
    'Took ${r.earned}, costs ${r.ingredients + r.wages}';

/// What the last few days add up to.
class MoneyView {
  MoneyView(Iterable<DayLog> days)
    : days = [
        for (final d in days)
          if (d.detailed) d,
      ];

  /// The days with their money broken down.
  final List<DayLog> days;

  bool get isEmpty => days.isEmpty;

  int _sum(int Function(DayLog) f) => days.fold(0, (a, d) => a + f(d));

  int get income => _sum((d) => d.income);
  int get ingredients => _sum((d) => d.ingredients);
  int get wages => _sum((d) => d.wages);
  int get leftover => _sum((d) => d.leftover);
  int get spoiled => _sum((d) => d.spoiled);
  int get kept => income - ingredients - wages;

  int _avg(int total) => days.isEmpty ? 0 : (total / days.length).round();
  int get incomeAvg => _avg(income);
  int get costsAvg => _avg(ingredients + wages);
  int get keptAvg => _avg(kept);

  /// Share of takings that went on [n], as a whole percentage.
  int share(int n) => income <= 0 ? 0 : (100 * n / income).round();

  /// Where savings could come from, biggest first, each said plainly with
  /// what it comes to. At most [limit] of them. Empty when nothing stands out.
  List<String> savings({int limit = 3}) {
    if (days.length < 2 || income <= 0) return const [];
    final n = days.length;
    final out = <(int, String)>[];
    final wageShare = share(wages);
    if (wageShare >= 45) {
      out.add((
        wages,
        'Wages are $wageShare% of takings. On a quiet day a smaller team '
            'costs less, but only let someone go if nobody is left waiting.',
      ));
    }
    final foodShare = share(ingredients);
    if (foodShare >= 40) {
      out.add((
        ingredients,
        'Ingredients are $foodShare% of takings. A higher price on the dish '
            'that sells most brings this down without losing guests.',
      ));
    }
    if (leftover >= 10 && leftover * 10 >= ingredients) {
      out.add((
        leftover,
        'Food worth $leftover was thrown away over $n days. Prepare fewer '
            "portions in Today's portions.",
      ));
    }
    if (spoiled >= n) {
      out.add((
        spoiled * 6,
        '$spoiled portions arrived spoiled over $n days. The usual supplier '
            'sends none spoiled.',
      ));
    }
    out.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final o in out.take(limit)) o.$2];
  }
}

/// A word about the supplier after a day, with what it came to, or null when
/// there is nothing worth saying. [seen] is the tips already given, and
/// [farmSeen] says whether the Farm delivery tip has been shown yet.
String? supplierHint(
  DayReport r,
  Supplier supplier,
  int level, {
  required bool farmSeen,
}) {
  final costs = r.ingredients + r.wages;
  final kept = r.earned - costs;
  switch (supplier) {
    case Supplier.market:
      if (r.spoiled >= 2) {
        final portions = r.served + r.wasted + r.spoiled;
        final lost = (r.ingredients * r.spoiled / portions).round();
        final extra = (r.ingredients / Supplier.market.costMul - r.ingredients)
            .round();
        return '${r.spoiled} portions arrived spoiled, worth about $lost. The '
            'usual supplier would have cost about $extra more, with none '
            '${lost > extra ? 'spoiled, so it would have paid for itself.' : 'spoiled. Budget still comes out ahead.'}';
      }
    case Supplier.standard:
      if (kept < 0 && r.ingredients >= 10) {
        final save = (r.ingredients - r.ingredients * Supplier.market.costMul)
            .round();
        return 'The day lost money. The budget market would have cut '
            'ingredients by about $save, though some portions arrive spoiled.';
      }
      if (level >= Supplier.farm.unlock && !farmSeen) {
        final cost = (r.ingredients * (Supplier.farm.costMul - 1)).round();
        final tips = (r.tips * (Supplier.farm.tipMul - 1)).round();
        return 'Farm delivery is open. On today\'s numbers it costs about '
            '$cost more and brings about $tips more in tips. Change supplier '
            "in Today's portions.";
      }
    case Supplier.farm:
      final cost = (r.ingredients * (1 - 1 / Supplier.farm.costMul)).round();
      final tips = (r.tips * (1 - 1 / Supplier.farm.tipMul)).round();
      if (cost - tips >= 5) {
        return 'Farm food cost about $cost more than the usual supplier, and '
            'brought about $tips more in tips. The usual supplier would have '
            'kept about ${cost - tips} more.';
      }
  }
  return null;
}
