import 'package:flutter/material.dart';

import '../data/storage.dart';
import '../ui/widgets.dart';
import 'diner.dart';
import 'vending.dart';

/// What comes up when a vending machine on the street is tapped: what it
/// sells, what a usual day brings, and a switch to turn it off if keeping it
/// stocked costs more than it is worth.
class VendingDialog extends StatefulWidget {
  const VendingDialog({super.key, required this.diner});

  final Diner diner;

  @override
  State<VendingDialog> createState() => _VendingDialogState();
}

class _VendingDialogState extends State<VendingDialog> {
  Diner get diner => widget.diner;

  void _sells(Vend v) {
    setState(() => diner.vend = v);
    Storage.saveDiner(diner);
  }

  void _collect() {
    setState(diner.collectVending);
    Storage.saveDiner(diner);
  }

  void _power() {
    setState(() => diner.vendingOn = !diner.vendingOn);
    Storage.saveDiner(diner);
  }

  @override
  Widget build(BuildContext context) {
    final n = diner.vendingMachines;
    final on = diner.vendingOn;
    final day = Vending.forecast(
      machines: n,
      product: diner.vend,
      rating: diner.progress.rating,
    );
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: PixelBox(
        key: const ValueKey('vending-dialog'),
        padding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: PxText(
                      n == 1 ? 'Vending machine' : 'Vending machines',
                      style: const TextStyle(color: Pal.gold, fontSize: 22),
                    ),
                  ),
                  PxText(
                    on ? 'On' : 'Off',
                    key: const ValueKey('vend-state'),
                    style: TextStyle(
                      color: on ? Pal.green : Pal.dim,
                      fontSize: 17,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Panel(
                key: const ValueKey('vend-box'),
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PxText(
                      'In the coin box: ${diner.vendCash} of '
                      '${diner.vendCashLimit}',
                      key: const ValueKey('vend-cash'),
                      style: TextStyle(
                        color: diner.vendCash >= diner.vendCashLimit
                            ? Pal.red
                            : Pal.text,
                        fontSize: 16,
                      ),
                    ),
                    PxText(
                      diner.vendCash >= diner.vendCashLimit
                          ? 'The box is full. Anything more is lost until you '
                                'collect.'
                          : 'The takings stay in the machine until you come '
                                'for them.',
                      key: const ValueKey('vend-box-note'),
                      style: const TextStyle(color: Pal.dim, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    GoldButton(
                      key: const ValueKey('vend-collect'),
                      label: diner.vendCash > 0
                          ? 'Collect ${diner.vendCash}'
                          : 'Nothing to collect',
                      onTap: diner.vendCash > 0 ? _collect : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const PxText(
                'What they sell',
                style: TextStyle(color: Pal.text, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final v in Vend.values)
                    Choice(
                      key: ValueKey('vend-${v.name}'),
                      label: v.label,
                      selected: diner.vend == v,
                      onTap: () => _sells(v),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              PxText(
                diner.vend.blurb,
                key: const ValueKey('vend-blurb'),
                style: const TextStyle(color: Pal.dim, fontSize: 14),
              ),
              const SizedBox(height: 8),
              PxText(
                on
                    ? 'A usual day: about ${day.sold} sold at '
                          '${diner.vend.price} each, ${day.restock} for '
                          'stock: ${day.net >= 0 ? '+' : ''}${day.net}. Now '
                          'and then one breaks down and costs '
                          '${Vending.repairCost} to fix.'
                    : 'Switched off. Nothing is stocked and nothing sold, '
                          'and a breakdown costs nothing.',
                key: const ValueKey('vend-forecast'),
                style: const TextStyle(color: Pal.text, fontSize: 14),
              ),
              const SizedBox(height: 12),
              GoldButton(
                key: const ValueKey('vend-power'),
                label: on ? 'Switch off' : 'Switch on',
                filled: !on,
                color: on ? Pal.text : Pal.gold,
                onTap: _power,
              ),
              const SizedBox(height: 8),
              GoldButton(
                key: const ValueKey('vend-close'),
                label: 'Close',
                filled: false,
                color: Pal.text,
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
