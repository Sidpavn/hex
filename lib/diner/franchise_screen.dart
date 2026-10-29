import 'package:flutter/material.dart';

import '../data/storage.dart';
import '../ui/widgets.dart';
import 'diner.dart';
import 'franchise.dart';

// ── franchise list ────────────────────────────────────────────────────────────

class FranchiseScreen extends StatefulWidget {
  const FranchiseScreen({super.key, required this.diner});

  final Diner diner;

  @override
  State<FranchiseScreen> createState() => _FranchiseScreenState();
}

class _FranchiseScreenState extends State<FranchiseScreen> {
  Diner get diner => widget.diner;

  void _save() => Storage.saveDiner(diner);

  FranchiseDef? get _nextOpportunity {
    for (final def in franchiseDefs) {
      if (!diner.franchises.any((f) => f.defId == def.id)) return def;
    }
    return null;
  }

  bool get _locked =>
      diner.franchises.isEmpty && diner.progress.level < 15;

  @override
  Widget build(BuildContext context) {
    final owned = diner.franchises;
    final total = diner.totalFranchiseIncome;
    return ScreenFrame(
      title: 'Investments',
      subtitle: _locked
          ? 'Unlocks at level 15'
          : owned.isEmpty
          ? 'Back your first place'
          : '+$total/day across ${owned.length} place${owned.length == 1 ? '' : 's'}',
      child: _locked ? _lockedBody() : ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          const SizedBox(height: 8),
          for (final f in owned) ...[
            _ownedCard(f),
            const SizedBox(height: 8),
          ],
          if (_nextOpportunity != null) _opportunityCard(_nextOpportunity!),
        ],
      ),
    );
  }

  Widget _lockedBody() {
    final level = diner.progress.level;
    final remaining = 15 - level;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 24),
      child: Panel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const PxText(
              'Not yet open',
              style: TextStyle(color: Pal.text, fontSize: 17),
            ),
            const SizedBox(height: 8),
            PxText(
              'Reach level 15 to back outside restaurants. '
              'They run themselves — you put money in and collect at day end.',
              style: const TextStyle(color: Pal.dim, fontSize: 14),
            ),
            const SizedBox(height: 12),
            PxText(
              '$remaining level${remaining == 1 ? '' : 's'} to go',
              style: const TextStyle(color: Pal.gold, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ownedCard(OwnedFranchise f) {
    final hasDecision = f.pendingEvent != null && !f.eventDecided;
    return Panel(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => FranchiseDetailScreen(diner: diner, franchise: f),
          ),
        );
        setState(() {});
        _save();
      },
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: PxText(
                  f.def.name,
                  style: const TextStyle(color: Pal.text, fontSize: 17),
                ),
              ),
              PxText(
                '+${f.lastIncome}/day',
                style: const TextStyle(color: Pal.gold, fontSize: 14),
              ),
              if (hasDecision) ...[
                const SizedBox(width: 8),
                Container(width: 8, height: 8, color: Pal.red),
              ],
            ],
          ),
          const SizedBox(height: 4),
          PxText(
            f.def.tagline,
            style: const TextStyle(color: Pal.dim, fontSize: 14),
          ),
          const SizedBox(height: 6),
          PxBar(value: f.reputation / 100.0, color: Pal.teal),
        ],
      ),
    );
  }

  Widget _opportunityCard(FranchiseDef def) {
    final locked = diner.progress.level < def.unlockLevel;
    final canAfford = !locked && diner.coins >= def.openCost;
    // Base income: all upgrades 0, reputation 50 (rep factor = 1.0)
    final baseDaily = def.baseIncome;
    // Max income: all upgrades 5 → upgradeFactor = 1 + 5*5*0.15 = 4.75, rep 100 → repFactor 1.5
    final maxDaily = (def.baseIncome * 4.75 * 1.5).round();
    return Panel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PxText(
                      def.name,
                      style: TextStyle(
                        color: locked ? Pal.dim : Pal.text,
                        fontSize: 17,
                      ),
                    ),
                    PxText(
                      def.tagline,
                      style: const TextStyle(color: Pal.dim, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (locked)
                PxText(
                  'Level ${def.unlockLevel}',
                  style: const TextStyle(color: Pal.dim, fontSize: 14),
                )
              else
                GoldButton(
                  key: ValueKey('open-${def.id}'),
                  label: ':coin: ${def.openCost}',
                  filled: canAfford,
                  color: canAfford ? Pal.gold : Pal.dim,
                  onTap: canAfford ? () => _open(def) : null,
                ),
            ],
          ),
          if (!locked) ...[
            const SizedBox(height: 8),
            PxText(
              'Starts at +$baseDaily/day — up to +$maxDaily/day fully upgraded',
              style: const TextStyle(color: Pal.gold, fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }

  void _open(FranchiseDef def) {
    setState(() => diner.openFranchise(def.id));
    _save();
  }
}

// ── franchise detail ──────────────────────────────────────────────────────────

class FranchiseDetailScreen extends StatefulWidget {
  const FranchiseDetailScreen({
    super.key,
    required this.diner,
    required this.franchise,
  });

  final Diner diner;
  final OwnedFranchise franchise;

  @override
  State<FranchiseDetailScreen> createState() => _FranchiseDetailScreenState();
}

class _FranchiseDetailScreenState extends State<FranchiseDetailScreen> {
  Diner get diner => widget.diner;
  OwnedFranchise get f => widget.franchise;

  String _note = '';

  @override
  Widget build(BuildContext context) {
    final event = f.pendingEvent;
    return ScreenFrame(
      title: f.def.name,
      subtitle: '+${f.dailyIncome()} coins/day',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          const SizedBox(height: 8),
          const Eyebrow('Today'),
          Panel(
            padding: const EdgeInsets.all(12),
            child: event != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PxText(
                        event.title,
                        style: const TextStyle(color: Pal.text, fontSize: 17),
                      ),
                      const SizedBox(height: 12),
                      for (final option in event.options) ...[
                        _optionButton(option),
                        const SizedBox(height: 8),
                      ],
                      if (_note.isNotEmpty)
                        PxText(
                          _note,
                          style: const TextStyle(
                            color: Pal.dim,
                            fontSize: 14,
                          ),
                        ),
                    ],
                  )
                : const PxText(
                    'No decisions today',
                    style: TextStyle(color: Pal.dim, fontSize: 14),
                  ),
          ),
          const SizedBox(height: 12),
          const Eyebrow('Upgrades'),
          Panel(
            child: Column(
              children: [
                for (final u in FranchiseUpgrade.values) _upgradeRow(u),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Eyebrow('Record'),
          Panel(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _statRow('Yesterday', '+${f.lastIncome} coins'),
                _statRow('Total earned', '${f.totalEarned} coins'),
                _statRow('Reputation', '${f.reputation}/100'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _optionButton(FranchiseOption option) {
    final decided = f.eventDecided;
    final canAfford = option.coinCost <= 0 || diner.coins >= option.coinCost;
    String label = option.label;
    if (option.coinCost > 0) {
      label = '$label  :coin: ${option.coinCost}';
    } else if (option.coinCost < 0) {
      label = '$label  +${-option.coinCost} coins';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GoldButton(
          label: label,
          filled: false,
          color: decided || !canAfford ? Pal.dim : Pal.text,
          onTap: !decided && canAfford ? () => _decide(option) : null,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 2),
          child: PxText(
            option.tag,
            style: const TextStyle(color: Pal.dim, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _upgradeRow(FranchiseUpgrade u) {
    final level = f.upgradeLevel(u);
    final maxed = level >= maxUpgradeLevel;
    final cost = f.upgradeCost(u);
    final canAfford = !maxed && diner.coins >= cost;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: PxText(
              upgradeNames[u]!,
              style: const TextStyle(color: Pal.dim, fontSize: 14),
            ),
          ),
          Expanded(
            child: PxBar(
              value: level / maxUpgradeLevel,
              color: Pal.gold,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: GoldButton(
              label: maxed ? 'Maxed out' : ':coin: $cost',
              filled: false,
              color: maxed || !canAfford ? Pal.dim : Pal.text,
              onTap: canAfford ? () => _upgrade(u) : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: PxText(
              label,
              style: const TextStyle(color: Pal.dim, fontSize: 14),
            ),
          ),
          PxText(value, style: const TextStyle(color: Pal.text, fontSize: 14)),
        ],
      ),
    );
  }

  void _decide(FranchiseOption option) {
    setState(() {
      diner.decideFranchise(f.defId, option);
      _note = option.tag;
    });
    Storage.saveDiner(diner);
  }

  void _upgrade(FranchiseUpgrade u) {
    setState(() => diner.upgradeFranchise(f.defId, u));
    Storage.saveDiner(diner);
  }
}
