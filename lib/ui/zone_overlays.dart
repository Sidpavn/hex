import 'package:flutter/material.dart';

import '../world/lore.dart';
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
    required this.onPack,
    required this.onClose,
  });

  final WorldState world;
  final VoidCallback onRest;
  final VoidCallback onPack;
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
                const SizedBox(height: 8),
                GoldButton(
                  label: 'Open pack (upgrade weapons)',
                  filled: false,
                  onTap: onPack,
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

/// Quests, what you are carrying, and where to go next.
class QuestLogOverlay extends StatelessWidget {
  const QuestLogOverlay({
    super.key,
    required this.world,
    required this.onClose,
    required this.onRead,
  });

  final WorldState world;
  final VoidCallback onClose;

  /// Open the scroll with this id.
  final void Function(String id) onRead;

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
                for (final q in quests.where((q) => q.isListed(world)))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _QuestEntry(
                      info: q,
                      stage: q.isDone(world) ? q.doneStage : q.stage(world),
                      objective: q.objective(world),
                    ),
                  ),
                if (world.scrolls.isNotEmpty) ...[
                  const Text(
                    'Scrolls',
                    style: TextStyle(color: Pal.gold, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  for (final id in world.scrolls)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onRead(id),
                        child: PixelBox(
                          color: Pal.panelLo,
                          shadow: false,
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            children: [
                              const PxIcon('scroll'),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  loreDefs[id]?.title ?? 'Scroll',
                                  style: const TextStyle(
                                    color: Pal.text,
                                    fontSize: 15,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                ],
                PxText(
                  ':token: ${world.tokens} tokens'
                  '${_carried(world).isEmpty ? '' : '   Carrying: ${_carried(world)}'}',
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

/// Quest items in the bag, for the journal.
String _carried(WorldState w) => [
  for (final s in w.bag)
    if (s != null && s.def.isQuest) s.def.name,
].join(', ');

class _QuestEntry extends StatelessWidget {
  const _QuestEntry({
    required this.info,
    required this.stage,
    required this.objective,
  });

  final Quest info;
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

/// A scroll's text, in full.
class ScrollOverlay extends StatelessWidget {
  const ScrollOverlay({super.key, required this.id, required this.onClose});

  final String id;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final lore = loreDefs[id];
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
                Row(
                  children: [
                    const PxIcon('scroll', mult: 2),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        lore?.title ?? 'Scroll',
                        style: const TextStyle(
                          color: Pal.gold,
                          fontSize: 22,
                          height: 1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final line in lore?.lines ?? const <String>[])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      line,
                      style: const TextStyle(
                        color: Pal.text,
                        fontSize: 15,
                        height: 1.05,
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                GoldButton(label: 'Close', filled: false, onTap: onClose),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
