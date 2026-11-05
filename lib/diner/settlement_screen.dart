import 'package:flutter/material.dart';

import '../ui/widgets.dart';
import 'home_card.dart';
import 'diner.dart';
import 'recipes.dart';
import 'service.dart';
import 'suppliers.dart';

/// The end-of-day panel on the cream receipt card: shows what was earned,
/// lets the player choose which staff to pay and which supplier to use
/// tomorrow, then starts the next day.
class SettlementPanel extends StatefulWidget {
  const SettlementPanel({
    super.key,
    required this.report,
    required this.diner,
    required this.onConfirm,
  });

  final DayReport report;
  final Diner diner;
  final void Function(Map<int, bool> paid, Supplier supplier) onConfirm;

  @override
  State<SettlementPanel> createState() => _SettlementPanelState();
}

class _SettlementPanelState extends State<SettlementPanel> {
  late final Map<int, bool> _paid;
  late Supplier _supplier;

  DayReport get r => widget.report;
  Diner get diner => widget.diner;

  @override
  void initState() {
    super.initState();
    _paid = {for (final w in r.pendingWages) w.id: true};
    _supplier = diner.supplier;
  }

  int get _wagesToPay =>
      r.pendingWages.fold(0, (a, w) => a + (_paid[w.id] == true ? w.salary : 0));

  int get _carryForward => diner.coins - _wagesToPay;

  /// Dishes that will be tier-capped if the player switches to [_supplier].
  List<String> get _downgradedDishes {
    final newMaxIdx = switch (_supplier) {
      Supplier.farm => Tier.premium.index,
      Supplier.standard => Tier.standard.index,
      Supplier.market => Tier.budget.index,
    };
    return [
      for (final d in diner.menu())
        if ((diner.tiers[d] ?? Tier.standard).index > newMaxIdx)
          recipes[d]!.name,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final available = diner.coins;
    final verdictColor = _verdictColor(r.stars);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Day header
        Row(
          children: [
            Expanded(
              child: PxText(
                'Day ${r.day}',
                style: const TextStyle(color: Pal.teal, fontSize: 17),
              ),
            ),
            PxText(
              _verdict(r.stars),
              style: TextStyle(color: verdictColor, fontSize: 17),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _divider(),
        const SizedBox(height: 4),

        // Rep change
        Builder(builder: (context) {
          final delta = r.reputation - r.reputationBefore;
          if (delta == 0) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: PxText(
              delta > 0
                  ? 'Reputation +$delta (${(r.reputation / 20).toStringAsFixed(1)} stars)'
                  : 'Reputation $delta (${(r.reputation / 20).toStringAsFixed(1)} stars)',
              style: TextStyle(
                color: delta > 0 ? Pal.teal : Pal.rust,
                fontSize: 13,
              ),
            ),
          );
        }),

        // Money recap
        LedgerLine(
          label: 'Earned',
          value: '+${r.earned}',
          ink: Pal.inkWarm,
          dim: Pal.creamDim,
        ),
        LedgerLine(
          label: 'Ingredients',
          value: '-${r.ingredients}',
          ink: Pal.inkWarm,
          dim: Pal.creamDim,
        ),
        if (r.leftover > 0)
          LedgerLine(
            label: 'Thrown away',
            value: '-${r.leftover}',
            ink: Pal.creamDim,
            dim: Pal.creamDim,
          ),
        _divider(),
        LedgerLine(
          label: 'Available',
          value: '$available',
          ink: available > 0 ? Pal.inkWarm : Pal.rust,
          dim: Pal.creamDim,
        ),
        const SizedBox(height: 12),

        // Staff wages
        if (r.pendingWages.isNotEmpty) ...[
          _sectionLabel('Staff wages'),
          const SizedBox(height: 6),
          for (final w in r.pendingWages) _wageRow(w),
          const SizedBox(height: 12),
        ],

        // Supplier choice
        _sectionLabel('Supply tomorrow'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in Supplier.values)
              Choice(
                key: ValueKey('supplier-${s.name}'),
                label: s.label,
                selected: _supplier == s,
                locked: s.unlock > diner.progress.level,
                onTap: () => setState(() => _supplier = s),
              ),
          ],
        ),
        const SizedBox(height: 6),
        PxText(
          _supplier.blurb,
          style: const TextStyle(color: Pal.creamDim, fontSize: 13),
        ),
        if (Supplier.values.any((s) => s.unlock > diner.progress.level)) ...[
          const SizedBox(height: 2),
          PxText(
            'Farm opens at level ${Supplier.farm.unlock}.',
            style: const TextStyle(color: Pal.creamDim, fontSize: 13),
          ),
        ],
        Builder(
          builder: (context) {
            final downgraded = _downgradedDishes;
            if (downgraded.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: PxText(
                'Switching will cap ${downgraded.join(', ')} to a lower tier.',
                style: const TextStyle(color: Pal.rust, fontSize: 13),
              ),
            );
          },
        ),
        const SizedBox(height: 12),

        // Carry forward
        _divider(),
        const SizedBox(height: 4),
        LedgerLine(
          label: 'Wages',
          value: _wagesToPay > 0 ? '-$_wagesToPay' : '—',
          ink: _wagesToPay > 0 ? Pal.inkWarm : Pal.creamDim,
          dim: Pal.creamDim,
        ),
        LedgerLine(
          key: const ValueKey('carry-forward'),
          label: 'Carry forward',
          value: '$_carryForward',
          ink: _carryForward >= 0 ? Pal.teal : Pal.rust,
          dim: Pal.creamDim,
        ),
        if (r.xp > 0)
          LedgerLine(
            label: 'XP gained',
            value: '+${r.xp}',
            ink: Pal.teal,
            dim: Pal.creamDim,
          ),
        if (r.spoiled > 0) ...[
          const SizedBox(height: 4),
          PxText(
            '${r.spoiled} portions arrived spoiled from the market.',
            style: const TextStyle(color: Pal.rust, fontSize: 13),
          ),
        ],
        const SizedBox(height: 12),

        DinerButton(
          key: const ValueKey('start-next-day'),
          label: 'Start day ${r.day + 1}',
          onTap: () => widget.onConfirm(_paid, _supplier),
        ),
      ],
    );
  }

  Widget _divider() => Container(height: 1, color: Pal.creamDark);

  Widget _sectionLabel(String text) => PxText(
    text,
    style: const TextStyle(color: Pal.teal, fontSize: 14),
  );

  Widget _wageRow(PendingWage w) {
    final paying = _paid[w.id] == true;
    final willQuit = w.willQuitIfUnpaid && !paying;
    return GestureDetector(
      onTap: () => setState(() => _paid[w.id] = !paying),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            // Checkbox: filled teal = paying, outlined = skipping
            Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: paying ? Pal.teal : Colors.transparent,
                border: Border.all(
                  color: paying ? Pal.teal : Pal.creamDim,
                  width: 1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PxText(
                w.name,
                style: TextStyle(
                  color: paying ? Pal.inkWarm : Pal.creamDim,
                  fontSize: 14,
                ),
              ),
            ),
            if (willQuit)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: PxText(
                  'may quit',
                  style: const TextStyle(color: Pal.rust, fontSize: 12),
                ),
              ),
            PxText(
              paying ? '-${w.salary}' : '${w.salary} skipped',
              style: TextStyle(
                color: paying ? Pal.inkWarm : Pal.creamDim,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _verdict(int stars) => switch (stars) {
    3 => 'Great day',
    2 => 'Good day',
    1 => 'Rough day',
    _ => 'Bad day',
  };

  Color _verdictColor(int stars) => switch (stars) {
    3 || 2 => Pal.teal,
    1 => Pal.goldDark,
    _ => Pal.rust,
  };
}
