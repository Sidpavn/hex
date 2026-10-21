import 'package:flutter/material.dart';

import '../audio/sound.dart';
import '../data/leaderboards.dart';
import '../data/storage.dart';
import '../ui/widgets.dart';
import 'diner.dart';
import 'guide.dart';
import 'home_screen.dart' show CloudFor, CloudLine, defaultCloudFor;
import 'sound_toggles.dart';

/// The game's version, as shown at the foot of the settings.
const gameVersion = '1.0.0';

/// Sound, backup and help in one place. Opened from the title screen, and
/// from the pause menu during a game.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.diner,
    this.cloudFor = defaultCloudFor,
    this.scores,
  });

  /// The game being played, if one is, so the backup line is about it.
  final Diner? diner;

  final CloudFor cloudFor;

  /// The leaderboards (tests). By default Play Games on Android.
  final ScoreBoard? scores;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _levels = ['Low', 'Mid', 'High'];

  Sound get _sound => Sound.instance;

  Widget _level(String key, String label, int now, void Function(int) set) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PxText(label, style: const TextStyle(color: Pal.dim, fontSize: 14)),
        const SizedBox(height: 4),
        Row(
          children: [
            for (var i = 0; i < _levels.length; i++) ...[
              Expanded(
                child: Choice(
                  key: ValueKey('$key-$i'),
                  label: _levels[i],
                  selected: now == i,
                  onTap: () => setState(() => set(i)),
                ),
              ),
              if (i < _levels.length - 1) const SizedBox(width: 6),
            ],
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final slot = Storage.slot;
    final scores = widget.scores ?? defaultScoreBoard();
    final store = widget.cloudFor(slot);
    final diner = widget.diner ?? Storage.slotDiner(slot);
    return ScreenFrame(
      title: 'Settings',
      subtitle: 'Sound, backup and help',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          const Eyebrow('Sound'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SoundToggles(),
                const SizedBox(height: 12),
                _level(
                  'sfx-level',
                  'Effects volume',
                  Storage.effectsLevel,
                  _sound.setEffectsLevel,
                ),
                const SizedBox(height: 8),
                _level(
                  'music-level',
                  'Music volume',
                  Storage.musicLevel,
                  _sound.setMusicLevel,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Eyebrow('Backup'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (store == null)
                  const PxText(
                    'Your games are kept on this phone. Copy a save code from '
                    'a game page in Saved games to keep a copy elsewhere.',
                    key: ValueKey('no-cloud'),
                    style: TextStyle(color: Pal.dim, fontSize: 14),
                  )
                else ...[
                  CloudLine(
                    key: ValueKey('settings-cloud-$slot-${diner?.savedAt}'),
                    store: store,
                    diner: diner,
                    onRestore: (d) {
                      Storage.saveSlot(slot, d);
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 8),
                  Choice(
                    key: const ValueKey('toggle-autobackup'),
                    label: 'Auto backup ${Storage.autoBackup ? 'on' : 'off'}',
                    selected: Storage.autoBackup,
                    onTap: () => setState(
                      () => Storage.autoBackup = !Storage.autoBackup,
                    ),
                  ),
                  const SizedBox(height: 4),
                  PxText(
                    Storage.autoBackup
                        ? 'The game sends its save up after each day, and '
                              'when you leave it.'
                        : 'Nothing is sent unless you press Back up now.',
                    key: const ValueKey('autobackup-help'),
                    style: const TextStyle(color: Pal.dim, fontSize: 14),
                  ),
                ],
              ],
            ),
          ),
          if (scores != null && scores.any) ...[
            const SizedBox(height: 16),
            const Eyebrow('Leaderboards'),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Choice(
                    key: const ValueKey('toggle-scores'),
                    label: 'Post scores ${Storage.postScores ? 'on' : 'off'}',
                    selected: Storage.postScores,
                    onTap: () => setState(
                      () => Storage.postScores = !Storage.postScores,
                    ),
                  ),
                  const SizedBox(height: 4),
                  PxText(
                    Storage.postScores
                        ? "After each day your best day's profit and your "
                              'total coins are sent, if they beat your last.'
                        : 'No scores are sent.',
                    key: const ValueKey('scores-help'),
                    style: const TextStyle(color: Pal.dim, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  GoldButton(
                    key: const ValueKey('settings-leaderboards'),
                    label: ':trophy: View leaderboards',
                    filled: false,
                    color: Pal.text,
                    onTap: () => scores.show(),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          const Eyebrow('Help'),
          GoldButton(
            key: const ValueKey('settings-guide'),
            label: 'How to play',
            filled: false,
            color: Pal.text,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const GuideScreen()),
            ),
          ),
          const SizedBox(height: 24),
          const PxText(
            'Tiny Diner Tycoon $gameVersion',
            key: ValueKey('version'),
            style: TextStyle(color: Pal.dimmer, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
