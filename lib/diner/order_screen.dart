import 'package:flutter/material.dart';

import '../data/storage.dart';
import '../ui/widgets.dart';
import 'build_screen.dart' show DinerSprite;
import 'contracts.dart';
import 'diner.dart';
import 'recipes.dart';

/// A catering order: what is wanted, what it pays, and who will cook it. Taken,
/// it is cooked while the day runs by whoever is set aside for it, who do not
/// serve customers until it has gone out. Or the doors can be shut for the
/// day and everyone works on it.
class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key, required this.diner});

  final Diner diner;

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  Diner get diner => widget.diner;

  late final Set<int> _crew;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    final team = diner.roster.employees;
    _crew = diner.takenContract != null
        ? {...diner.crewIds}
        // To begin with, half the team, and at least one.
        : {
            for (final s in team.take((team.length / 2).ceil().clamp(1, 99)))
              s.id,
          };
    _closed = diner.closedForOrder;
  }

  Contract? get _contract => diner.takenContract ?? diner.offer;

  void _save() => Storage.saveDiner(diner);

  void _take() {
    final c = _contract;
    if (c == null) return;
    setState(() => diner.takeContract(c, _crew, closed: _closed));
    _save();
    if (diner.takenContract != null) Navigator.of(context).pop();
  }

  void _pass() {
    setState(diner.passContract);
    _save();
    Navigator.of(context).pop();
  }

  void _cancel() {
    setState(diner.cancelContract);
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final c = _contract;
    if (c == null) {
      return const ScreenFrame(
        title: 'Catering order',
        child: Padding(
          padding: EdgeInsets.all(12),
          child: PxText(
            'No order today.',
            key: ValueKey('no-order'),
            style: TextStyle(color: Pal.dim, fontSize: 15),
          ),
        ),
      );
    }
    final taken = diner.takenContract != null;
    final cost = c.ingredients(diner);
    final why = taken ? null : diner.whyNotTake(c, _crew, closed: _closed);
    return ScreenFrame(
      title: 'Catering order',
      subtitle: 'For ${c.client}',
      trailing: PxText(
        ':coin: ${diner.coins}',
        style: const TextStyle(color: Pal.text, fontSize: 20),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          Panel(
            key: const ValueKey('order'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in c.lines.entries)
                  Padding(
                    key: ValueKey('line-${e.key.name}'),
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 32,
                          child: DinerSprite('ico_${e.key.name}', mult: 3),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: PxText(
                            recipes[e.key]!.name,
                            style: const TextStyle(
                              color: Pal.text,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        PxText(
                          '${e.value}',
                          style: const TextStyle(color: Pal.gold, fontSize: 18),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                PxText(
                  'Pays ${c.reward}',
                  key: const ValueKey('reward'),
                  style: const TextStyle(color: Pal.gold, fontSize: 20),
                ),
                PxText(
                  'Ingredients $cost, paid when the day starts. It has to be '
                  'out by closing time, or the order is lost and so is the '
                  'food.',
                  key: const ValueKey('terms'),
                  style: const TextStyle(color: Pal.dim, fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (taken) ..._takenView(c) else ..._chooseView(c, why),
        ],
      ),
    );
  }

  List<Widget> _chooseView(Contract c, String? why) => [
    const Eyebrow('Who cooks it'),
    Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final s in diner.roster.employees)
          Choice(
            key: ValueKey('crew-${s.id}'),
            label: s.name,
            selected: _closed || _crew.contains(s.id),
            onTap: _closed
                ? null
                : () => setState(() {
                    if (!_crew.remove(s.id)) _crew.add(s.id);
                  }),
          ),
      ],
    ),
    const SizedBox(height: 8),
    PxText(
      _closed
          ? 'Everyone is on it.'
          : 'They cook the order and do not serve customers until it has gone '
                'out. Everyone else runs the restaurant as usual.',
      key: const ValueKey('crew-note'),
      style: const TextStyle(color: Pal.dim, fontSize: 14),
    ),
    const SizedBox(height: 12),
    const Eyebrow('The doors'),
    Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        Choice(
          key: const ValueKey('doors-open'),
          label: 'Stay open',
          selected: !_closed,
          onTap: () => setState(() => _closed = false),
        ),
        Choice(
          key: const ValueKey('doors-shut'),
          label: 'Close for the day',
          selected: _closed,
          onTap: () => setState(() => _closed = true),
        ),
      ],
    ),
    const SizedBox(height: 8),
    PxText(
      _closed
          ? 'No customers today and no takings but this. Everyone works on '
                'the order, and the day ends when it goes out.'
          : 'Customers still come. The kitchen is shared, so the order and '
                'the restaurant compete for the same machines.',
      key: const ValueKey('doors-note'),
      style: const TextStyle(color: Pal.dim, fontSize: 14),
    ),
    const SizedBox(height: 16),
    if (why != null) ...[
      PxText(
        why,
        key: const ValueKey('why-not'),
        style: const TextStyle(color: Pal.red, fontSize: 14),
      ),
      const SizedBox(height: 8),
    ],
    GoldButton(
      key: const ValueKey('take-order'),
      label: 'Take the order, pays ${c.reward}',
      onTap: why == null ? _take : null,
    ),
    const SizedBox(height: 8),
    GoldButton(
      key: const ValueKey('pass-order'),
      label: 'Not today',
      filled: false,
      color: Pal.dim,
      onTap: _pass,
    ),
  ];

  List<Widget> _takenView(Contract c) => [
    PxText(
      diner.closedForOrder
          ? 'Taken. The doors will be shut when you start the day, and everyone '
                'works on it.'
          : 'Taken. ${diner.crew.map((s) => s.name).join(', ')} will cook it '
                'when the day starts.',
      key: const ValueKey('taken-note'),
      style: const TextStyle(color: Pal.green, fontSize: 15),
    ),
    const SizedBox(height: 16),
    GoldButton(
      key: const ValueKey('cancel-order'),
      label: 'Change my mind',
      filled: false,
      color: Pal.text,
      onTap: _cancel,
    ),
  ];
}
