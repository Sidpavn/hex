import 'package:flutter/material.dart';

import '../ui/pixel_dialog.dart';
import '../ui/widgets.dart';
import 'diner.dart';
import 'franchise.dart';

/// Shows franchise events one at a time before the day starts.
/// Returns after all pending decisions have been made.
Future<void> showFranchiseEvents(BuildContext context, Diner diner) async {
  for (final f in diner.franchises) {
    if (f.pendingEvent == null || f.eventDecided) continue;
    if (!context.mounted) return;
    await popupPixel<void>(
      context,
      (_) => _FranchiseEventPopup(diner: diner, franchise: f),
      barrierDismissible: false,
    );
  }
}

class _FranchiseEventPopup extends StatefulWidget {
  const _FranchiseEventPopup({
    required this.diner,
    required this.franchise,
  });

  final Diner diner;
  final OwnedFranchise franchise;

  @override
  State<_FranchiseEventPopup> createState() => _FranchiseEventPopupState();
}

class _FranchiseEventPopupState extends State<_FranchiseEventPopup> {
  Diner get diner => widget.diner;
  OwnedFranchise get f => widget.franchise;

  String _tag = '';
  bool _decided = false;

  void _pick(FranchiseOption option) {
    if (_decided) return;
    final canAfford = option.coinCost <= 0 || diner.coins >= option.coinCost;
    if (!canAfford) return;
    setState(() {
      diner.decideFranchise(f.defId, option);
      _tag = option.tag;
      _decided = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final event = f.pendingEvent!;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: PixelBox(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── header ──────────────────────────────────────────────
            PxText(
              f.def.name,
              style: const TextStyle(color: Pal.gold, fontSize: 18),
            ),
            const SizedBox(height: 2),
            PxText(
              f.def.tagline,
              style: const TextStyle(color: Pal.dim, fontSize: 13),
            ),
            const SizedBox(height: 12),
            // ── event ────────────────────────────────────────────────
            PxText(
              event.title,
              style: const TextStyle(color: Pal.text, fontSize: 17),
            ),
            const SizedBox(height: 12),
            // ── options ──────────────────────────────────────────────
            for (final option in event.options) ...[
              _OptionButton(
                option: option,
                diner: diner,
                decided: _decided,
                onTap: () => _pick(option),
              ),
              const SizedBox(height: 6),
            ],
            // ── outcome / continue ───────────────────────────────────
            if (_decided) ...[
              const SizedBox(height: 4),
              PxText(
                _tag,
                style: const TextStyle(color: Pal.dim, fontSize: 13),
              ),
              const SizedBox(height: 12),
              GoldButton(
                key: const ValueKey('event-continue'),
                label: 'Continue',
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.option,
    required this.diner,
    required this.decided,
    required this.onTap,
  });

  final FranchiseOption option;
  final Diner diner;
  final bool decided;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final canAfford = option.coinCost <= 0 || diner.coins >= option.coinCost;
    final active = !decided && canAfford;

    String label = option.label;
    if (option.coinCost > 0) label = '$label  :coin: ${option.coinCost}';
    if (option.coinCost < 0) label = '$label  +${-option.coinCost} coins';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GoldButton(
          label: label,
          filled: false,
          color: active ? Pal.text : Pal.dim,
          onTap: active ? onTap : null,
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
}
