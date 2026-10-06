import 'package:flutter/material.dart';

import '../game/models.dart';
import '../world/quests.dart';
import '../world/world_state.dart';
import '../world/zone.dart';
import 'widgets.dart';

/// Dim backdrop that swallows taps so the world underneath stays still.
class ModalFrame extends StatelessWidget {
  const ModalFrame({
    super.key,
    required this.child,
    this.alignment = Alignment.center,
    this.onDismiss,
  });

  final Widget child;
  final Alignment alignment;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onDismiss,
        child: ColoredBox(
          color: const Color(0x991A1C2C),
          child: SafeArea(
            child: Align(
              alignment: alignment,
              // Taps on the box itself shouldn't dismiss it.
              child: GestureDetector(onTap: () {}, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// A conversation, one line per tap, then the answers (if any).
class DialogueOverlay extends StatefulWidget {
  const DialogueOverlay({
    super.key,
    required this.npc,
    required this.dialogue,
    required this.onClose,
  });

  final NpcSpawn npc;
  final Dialogue dialogue;

  /// Called when the conversation ends, with the chosen answer (if any).
  final void Function(DialogueChoice? choice) onClose;

  @override
  State<DialogueOverlay> createState() => _DialogueOverlayState();
}

class _DialogueOverlayState extends State<DialogueOverlay> {
  int _line = 0;

  bool get _last => _line >= widget.dialogue.lines.length - 1;

  void _next() {
    if (!_last) {
      setState(() => _line++);
    } else if (widget.dialogue.choices.isEmpty) {
      widget.onClose(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.dialogue;
    return ModalFrame(
      alignment: Alignment.bottomCenter,
      onDismiss: _next,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _next,
          child: PixelBox(
            border: Pal.gold,
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    UnitPortrait(widget.npc.unit, mult: 2),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.speaker,
                            style: const TextStyle(
                              color: Pal.gold,
                              fontSize: 20,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          PxText(
                            d.lines[_line],
                            style: const TextStyle(
                              color: Pal.text,
                              fontSize: 15,
                              height: 1.05,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_last && d.choices.isNotEmpty)
                  for (final c in d.choices)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: GoldButton(
                        label: c.label,
                        filled: c == d.choices.first,
                        onTap: () => widget.onClose(c),
                      ),
                    )
                else
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      _last ? 'Tap to close' : 'Tap to continue',
                      style: const TextStyle(color: Pal.dim, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The campfire: rest, save, and spend tokens on your weapons.
class CampOverlay extends StatelessWidget {
  const CampOverlay({
    super.key,
    required this.world,
    required this.onRest,
    required this.onUpgrade,
    required this.onClose,
  });

  final WorldState world;
  final VoidCallback onRest;
  final void Function(WeaponKind) onUpgrade;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ModalFrame(
      onDismiss: onClose,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: PixelBox(
            border: Pal.gold,
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    PxIcon('campfire', mult: 2),
                    SizedBox(width: 10),
                    Text(
                      'Campfire',
                      style: TextStyle(
                        color: Pal.gold,
                        fontSize: 26,
                        height: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Rest to heal and set your respawn here. Slain enemies '
                  'return when you rest.',
                  style: TextStyle(color: Pal.dim, fontSize: 14),
                ),
                const SizedBox(height: 12),
                GoldButton(label: 'Rest here', onTap: onRest),
                const SizedBox(height: 14),
                PxText(
                  'Upgrades  :token: ${world.tokens}',
                  style: const TextStyle(color: Pal.gold, fontSize: 16),
                ),
                const SizedBox(height: 6),
                for (final k in WeaponKind.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _UpgradeRow(
                      world: world,
                      kind: k,
                      onTap: () => onUpgrade(k),
                    ),
                  ),
                const SizedBox(height: 4),
                GoldButton(label: 'Leave', filled: false, onTap: onClose),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UpgradeRow extends StatelessWidget {
  const _UpgradeRow({
    required this.world,
    required this.kind,
    required this.onTap,
  });

  final WorldState world;
  final WeaponKind kind;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final w = weapons[kind]!;
    final maxed = world.upgrades[kind]! >= WorldState.maxUpgrade;
    final dmg = world.damageOf(kind);
    return Row(
      children: [
        PxIcon(w.icon),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${w.name}  dmg $dmg${maxed ? '  (max)' : ' > ${dmg + 1}'}',
            style: const TextStyle(color: Pal.text, fontSize: 14),
          ),
        ),
        SizedBox(
          width: 96,
          child: GoldButton(
            label: maxed ? 'Maxed' : ':token: ${world.upgradeCost(kind)}',
            filled: !maxed && world.canUpgrade(kind),
            onTap: world.canUpgrade(kind) ? onTap : null,
          ),
        ),
      ],
    );
  }
}

/// Quests, what you are carrying, and where to go next.
class QuestLogOverlay extends StatelessWidget {
  const QuestLogOverlay({
    super.key,
    required this.world,
    required this.onClose,
  });

  final WorldState world;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final objective = currentObjective(world);
    return ModalFrame(
      onDismiss: onClose,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: PixelBox(
            border: Pal.gold,
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    PxIcon('book', mult: 2),
                    SizedBox(width: 10),
                    Text(
                      'Journal',
                      style: TextStyle(
                        color: Pal.gold,
                        fontSize: 26,
                        height: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final q in questList)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _QuestEntry(
                      info: q,
                      stage: questStage(world, q.id),
                      objective: objective,
                    ),
                  ),
                PxText(
                  ':token: ${world.tokens} tokens'
                  '${world.inventory.isEmpty ? '' : '   Carrying: ${world.inventory.join(', ')}'}',
                  style: const TextStyle(color: Pal.dim, fontSize: 14),
                ),
                const SizedBox(height: 12),
                GoldButton(label: 'Close', filled: false, onTap: onClose),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuestEntry extends StatelessWidget {
  const _QuestEntry({
    required this.info,
    required this.stage,
    required this.objective,
  });

  final QuestInfo info;
  final int stage;
  final QuestObjective? objective;

  @override
  Widget build(BuildContext context) {
    final status = switch (stage) {
      0 => 'Not started. Talk to ${info.giver}.',
      1 => 'In progress',
      _ => 'Done',
    };
    final color = stage >= 2 ? Pal.green : (stage == 1 ? Pal.gold : Pal.dim);
    return PixelBox(
      color: Pal.panelLo,
      shadow: false,
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            info.title,
            style: TextStyle(color: color, fontSize: 18, height: 1),
          ),
          const SizedBox(height: 4),
          Text(status, style: const TextStyle(color: Pal.dim, fontSize: 13)),
          if (stage >= 1) ...[
            const SizedBox(height: 4),
            Text(
              info.summary,
              style: const TextStyle(color: Pal.text, fontSize: 14),
            ),
            if (objective != null) ...[
              const SizedBox(height: 4),
              PxText(
                ':star: ${objective!.text}',
                style: const TextStyle(color: Pal.gold, fontSize: 14),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// A small action button for the bottom bar.
class ActionButton extends StatelessWidget {
  const ActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.enabled = true,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: PixelBox(
          color: selected ? Pal.panelHi : Pal.panel,
          border: selected ? Pal.gold : Pal.ink,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon == 'archer' || icon == 'knight'
                  ? UnitPortrait(
                      icon == 'archer' ? UnitType.archer : UnitType.knight,
                      mult: 1,
                    )
                  : PxIcon(icon),
              const SizedBox(width: 6),
              PxText(
                label,
                style: TextStyle(
                  color: selected ? Pal.gold : Pal.text,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
