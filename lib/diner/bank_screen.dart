import 'package:flutter/material.dart';

import '../data/storage.dart';
import '../ui/widgets.dart';
import 'bank.dart';
import 'diner.dart';

/// The bank: borrow once, pay a fifth back each night, or pay it all off early.
class BankScreen extends StatefulWidget {
  const BankScreen({super.key, required this.diner});

  final Diner diner;

  @override
  State<BankScreen> createState() => _BankScreenState();
}

class _BankScreenState extends State<BankScreen> {
  Diner get diner => widget.diner;
  String _note = '';

  void _borrow(LoanOffer o) {
    setState(() {
      final ok = diner.borrow(o);
      _note = ok ? 'Borrowed ${o.amount}. You owe ${diner.loan}.' : '';
    });
    Storage.saveDiner(diner);
  }

  void _repay(int n) {
    setState(() {
      final paid = diner.repay(n);
      _note = paid == 0
          ? 'Not enough coins'
          : diner.loan == 0
          ? 'Paid off.'
          : 'Paid $paid. You owe ${diner.loan}.';
    });
    Storage.saveDiner(diner);
  }

  @override
  Widget build(BuildContext context) {
    final owe = diner.loan;
    return ScreenFrame(
      title: 'Bank',
      subtitle: owe == 0 ? 'You owe nothing' : 'You owe $owe',
      trailing: PxText(
        ':coin: ${diner.coins}',
        style: const TextStyle(color: Pal.text, fontSize: 20),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          if (owe > 0) ...[
            Panel(
              key: const ValueKey('debt'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PxText(
                    'You owe $owe',
                    key: const ValueKey('owed'),
                    style: const TextStyle(color: Pal.gold, fontSize: 22),
                  ),
                  PxText(
                    '${Bank.due(owe)} comes out each night, after the wages. '
                    'Miss it and the bank adds 5% to what you owe, and your '
                    'rating drops.',
                    key: const ValueKey('terms'),
                    style: const TextStyle(color: Pal.dim, fontSize: 14),
                  ),
                  if (diner.loanLate > 0)
                    PxText(
                      'Missed ${diner.loanLate} '
                      '${diner.loanLate == 1 ? 'night' : 'nights'} in a row.',
                      key: const ValueKey('late'),
                      style: const TextStyle(color: Pal.red, fontSize: 14),
                    ),
                  const SizedBox(height: 8),
                  GoldButton(
                    key: const ValueKey('repay-some'),
                    label: 'Pay back ${Bank.due(owe)}',
                    filled: false,
                    color: Pal.text,
                    onTap: diner.coins >= Bank.due(owe)
                        ? () => _repay(Bank.due(owe))
                        : null,
                  ),
                  const SizedBox(height: 8),
                  GoldButton(
                    key: const ValueKey('repay-all'),
                    label: 'Pay off all $owe',
                    onTap: diner.coins >= owe ? () => _repay(owe) : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_note.isNotEmpty) ...[
            PxText(
              _note,
              key: const ValueKey('bank-note'),
              style: const TextStyle(color: Pal.text, fontSize: 14),
            ),
            const SizedBox(height: 12),
          ],
          const Eyebrow('Borrow'),
          for (final o in Bank.offers) ...[
            _offer(o),
            const SizedBox(height: 8),
          ],
          const PxText(
            'One loan at a time. The bank charges a flat 15%, paid back a '
            'little each night.',
            style: TextStyle(color: Pal.dim, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _offer(LoanOffer o) {
    final why = diner.whyNotLend(o);
    return Panel(
      key: ValueKey('loan-${o.amount}'),
      dim: why != null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PxText(
                  'Borrow ${o.amount}',
                  style: const TextStyle(color: Pal.text, fontSize: 17),
                ),
                PxText(
                  why ??
                      'Pay back ${o.owed}: ${Bank.due(o.owed)} a night, '
                          '${Bank.feeOn(o)} for the bank',
                  key: ValueKey('loan-${o.amount}-terms'),
                  style: TextStyle(
                    color: why == null ? Pal.dim : Pal.red,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 96,
            child: GoldButton(
              key: ValueKey('borrow-${o.amount}'),
              label: 'Borrow',
              onTap: why == null ? () => _borrow(o) : null,
            ),
          ),
        ],
      ),
    );
  }
}
