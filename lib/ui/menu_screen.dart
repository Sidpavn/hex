import 'package:flutter/material.dart';

import '../data/storage.dart';
import '../game/campaign.dart';
import '../game/config.dart';
import '../game/models.dart';
import 'campaign_screen.dart';
import 'game_screen.dart';
import 'setup_screen.dart';
import 'stats_screen.dart';
import 'zone_screen.dart';
import 'widgets.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  Future<void> _open(Widget page) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted) setState(() {});
  }

  void _locked(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
      );
  }

  Future<void> _skip() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Skip the tutorial?'),
        content: const Text(
          'Unlocks Skirmish, Hot-seat and the main campaign right away. '
          'The lessons stay available in the Campaign.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Skip it'),
          ),
        ],
      ),
    );
    if (ok == true) {
      Storage.skipTutorial();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = <_Item>[
      _Item(
        'flag',
        'Campaign',
        '${campaignLevels.length} levels, :star: ${Storage.totalStars}/${campaignLevels.length * 3}',
        () => _open(const CampaignScreen()),
      ),
      _Item(
        'swords',
        'Skirmish',
        Storage.skirmishUnlocked
            ? 'Fight the AI on your terms'
            : ':lock: Finish all $lessonCount lessons (${Storage.lessonsDone}/$lessonCount)',
        Storage.skirmishUnlocked
            ? () => _open(const SetupScreen(mode: GameMode.skirmish))
            : () => _locked(
                'Finish all $lessonCount training lessons to unlock Skirmish.',
              ),
        locked: !Storage.skirmishUnlocked,
      ),
      _Item(
        'people',
        'Hot-seat',
        Storage.hotseatUnlocked
            ? 'Two players, one device'
            : ':lock: Finish lesson $hotseatLessons (${Storage.lessonsDone}/$hotseatLessons)',
        Storage.hotseatUnlocked
            ? () => _open(const SetupScreen(mode: GameMode.hotseat))
            : () => _locked(
                'Finish the first $hotseatLessons lessons to unlock Hot-seat.',
              ),
        locked: !Storage.hotseatUnlocked,
      ),
      _Item(
        'tree',
        'Explore',
        'Prototype: wander the world',
        () => _open(const ZoneScreen()),
      ),
      _Item(
        'chart',
        'Stats',
        'Records and progress',
        () => _open(const StatsScreen()),
      ),
    ];
    return Scaffold(
      backgroundColor: Pal.bgTop,
      body: Backdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Logo(),
                    const SizedBox(height: 22),
                    for (var i = 0; i < items.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Entrance(
                          index: i + 2,
                          child: _MenuCard(item: items[i]),
                        ),
                      ),
                    if (!Storage.skirmishUnlocked || !Storage.hotseatUnlocked)
                      TextButton(
                        onPressed: _skip,
                        child: const Text(
                          'Already know how to play? Skip the tutorial',
                          style: TextStyle(color: Pal.dim, fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Item {
  const _Item(
    this.icon,
    this.title,
    this.subtitle,
    this.onTap, {
    this.locked = false,
  });
  final bool locked;
  final String icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.item});

  final _Item item;

  @override
  Widget build(BuildContext context) {
    return Panel(
      dim: item.locked,
      onTap: item.onTap,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        children: [
          HexBadge(
            size: 40,
            color: item.locked ? Pal.dimmer : Pal.gold,
            child: PxIcon(item.locked ? 'lock' : item.icon),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 22,
                    color: Pal.text,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                PxText(
                  item.subtitle,
                  style: const TextStyle(color: Pal.dim, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Title lockup: a line-up of the cast, then the name.
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    const cast = [
      UnitType.knight,
      UnitType.archer,
      UnitType.hero,
      UnitType.mage,
      UnitType.golem,
    ];
    final u = PixelUi.unit(context);
    return Entrance(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final t in cast)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: UnitPortrait(t, mult: 2, animated: true),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'HEX TACTICS',
            style: TextStyle(
              fontSize: 40,
              height: 1,
              color: Pal.gold,
              shadows: [Shadow(color: Pal.ink, offset: Offset(u, u))],
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Summon, cast, conquer.',
            style: TextStyle(color: Pal.dim, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

/// Opens a game with the player's saved hero and deck.
Route<void> gameRoute(GameConfig config) =>
    MaterialPageRoute(builder: (_) => GameScreen(config: config));
