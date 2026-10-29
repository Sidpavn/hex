import 'package:flutter/material.dart';

import '../ui/widgets.dart';
import 'diner.dart';
import 'guide.dart';
import 'settings_screen.dart';
import 'sound_toggles.dart';

/// What the player chose from the pause menu, if anything but carrying on.
enum PauseChoice { title }

/// The menu a game can be stopped with: carry on, switch sound or music on or
/// off, open the settings or the guide, or (between days) go back to the
/// title. During a day the clock is held while it is open.
class PauseMenu extends StatelessWidget {
  const PauseMenu({super.key, required this.diner, required this.inService});

  final Diner diner;

  /// Whether a day is running. Leaving the game is only offered between days,
  /// so a day is never lost half way.
  final bool inService;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: PixelBox(
        key: const ValueKey('pause-menu-box'),
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PxText(
                inService ? 'Paused' : 'Game menu',
                key: const ValueKey('pause-title'),
                style: const TextStyle(color: Pal.gold, fontSize: 22),
              ),
              const SizedBox(height: 4),
              PxText(
                inService
                    ? 'The day is held until you carry on.'
                    : 'Day ${diner.progress.day}',
                style: const TextStyle(color: Pal.dim, fontSize: 14),
              ),
              const SizedBox(height: 12),
              GoldButton(
                key: const ValueKey('pause-resume'),
                label: inService ? 'Carry on' : 'Close',
                onTap: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 12),
              const SoundToggles(),
              const SizedBox(height: 8),
              ButtonRow(
                children: [
                  GoldButton(
                    key: const ValueKey('pause-settings'),
                    label: ':gear: Settings',
                    filled: false,
                    color: Pal.text,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SettingsScreen(diner: diner),
                      ),
                    ),
                  ),
                  GoldButton(
                    key: const ValueKey('pause-guide'),
                    label: 'How to play',
                    filled: false,
                    color: Pal.text,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const GuideScreen(),
                      ),
                    ),
                  ),
                  if (!inService)
                    GoldButton(
                      key: const ValueKey('pause-title-button'),
                      label: 'Back to the title screen',
                      filled: false,
                      color: Pal.dim,
                      onTap: () =>
                          Navigator.of(context).pop(PauseChoice.title),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
