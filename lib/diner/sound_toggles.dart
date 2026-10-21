import 'package:flutter/material.dart';

import '../audio/sound.dart';
import '../ui/widgets.dart';

/// The two sound switches: effects and music, each on or off.
class SoundToggles extends StatefulWidget {
  const SoundToggles({super.key});

  @override
  State<SoundToggles> createState() => _SoundTogglesState();
}

class _SoundTogglesState extends State<SoundToggles> {
  Sound get _sound => Sound.instance;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Choice(
          key: const ValueKey('toggle-sfx'),
          label: 'Sound ${_sound.effectsOn ? 'on' : 'off'}',
          selected: _sound.effectsOn,
          onTap: () => setState(() => _sound.setEffects(!_sound.effectsOn)),
        ),
        Choice(
          key: const ValueKey('toggle-music'),
          label: 'Music ${_sound.musicOn ? 'on' : 'off'}',
          selected: _sound.musicOn,
          onTap: () => setState(() => _sound.setMusic(!_sound.musicOn)),
        ),
      ],
    );
  }
}
