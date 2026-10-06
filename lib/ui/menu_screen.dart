import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/storage.dart';
import '../game/campaign.dart';
import '../game/config.dart';
import 'campaign_screen.dart';
import 'game_screen.dart';
import 'setup_screen.dart';
import 'stats_screen.dart';
import 'widgets.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, _, _) => page,
        transitionsBuilder: (_, a, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0.06, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
      ),
    );
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
        backgroundColor: const Color(0xFF14211D),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0x66FFE082)),
        ),
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
        '🚩',
        'Campaign',
        '${campaignLevels.length} levels  •  ★ ${Storage.totalStars}/${campaignLevels.length * 3}',
        Pal.gold,
        () => _open(const CampaignScreen()),
      ),
      _Item(
        '⚔️',
        'Skirmish',
        Storage.skirmishUnlocked
            ? 'Fight the AI on your terms'
            : '🔒 Finish all $lessonCount lessons (${Storage.lessonsDone}/$lessonCount)',
        Pal.red,
        Storage.skirmishUnlocked
            ? () => _open(const SetupScreen(mode: GameMode.skirmish))
            : () => _locked(
                'Finish all $lessonCount training lessons to unlock Skirmish.',
              ),
        locked: !Storage.skirmishUnlocked,
      ),
      _Item(
        '👥',
        'Hot-seat',
        Storage.hotseatUnlocked
            ? 'Two players, one device'
            : '🔒 Finish lesson $hotseatLessons (${Storage.lessonsDone}/$hotseatLessons)',
        Pal.blue,
        Storage.hotseatUnlocked
            ? () => _open(const SetupScreen(mode: GameMode.hotseat))
            : () => _locked(
                'Finish the first $hotseatLessons lessons to unlock Hot-seat.',
              ),
        locked: !Storage.hotseatUnlocked,
      ),
      _Item(
        '📊',
        'Stats',
        'Records and progress',
        Pal.green,
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
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12.5,
                          ),
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
    this.emoji,
    this.title,
    this.subtitle,
    this.color,
    this.onTap, {
    this.locked = false,
  });
  final bool locked;
  final String emoji;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.item});

  final _Item item;

  @override
  Widget build(BuildContext context) {
    return Panel(
      glow: item.locked ? null : item.color,
      dim: item.locked,
      onTap: item.onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          HexBadge(
            size: 56,
            color: item.color,
            glow: true,
            child: Text(item.emoji, style: const TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.subtitle,
                  style: const TextStyle(color: Colors.white60, fontSize: 12.5),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: item.color),
        ],
      ),
    );
  }
}

/// Title lockup: a ring of bobbing units around a glowing hexagon.
class _Logo extends StatefulWidget {
  const _Logo();

  @override
  State<_Logo> createState() => _LogoState();
}

class _LogoState extends State<_Logo> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const cast = ['🧙', '🤺', '🏹', '🗿', '🐎', '🔮'];
    return Entrance(
      child: Column(
        children: [
          SizedBox(
            height: 150,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final t = _c.value * math.pi * 2;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.rotate(
                      angle: t * 0.5,
                      child: CustomPaint(
                        size: const Size(130, 130),
                        painter: _RingPainter(0.5 + 0.5 * math.sin(t * 2)),
                      ),
                    ),
                    for (var i = 0; i < cast.length; i++)
                      Transform.translate(
                        offset: Offset(
                          math.cos(t + i * math.pi / 3) * 62,
                          math.sin(t + i * math.pi / 3) * 62 +
                              math.sin(t * 3 + i) * 3,
                        ),
                        child: Text(
                          cast[i],
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                    const Text(
                      '⬡',
                      style: TextStyle(fontSize: 44, color: Pal.goldLight),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          ShaderMask(
            shaderCallback: (r) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Pal.goldLight, Pal.gold],
            ).createShader(r),
            child: const Text(
              'HEX TACTICS',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w900,
                letterSpacing: 5,
                color: Colors.white,
                shadows: [Shadow(color: Color(0x88FFC400), blurRadius: 22)],
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'SUMMON  •  CAST  •  CONQUER',
            style: TextStyle(
              color: Colors.white54,
              letterSpacing: 3,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.pulse);
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawPath(
      hexPath(c, 52 + 3 * pulse),
      Paint()
        ..color = Pal.gold.withValues(alpha: 0.3 + 0.2 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawPath(
      hexPath(c, 50),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Pal.goldLight.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.pulse != pulse;
}

/// Opens a game with the player's saved hero and deck.
Route<void> gameRoute(GameConfig config) =>
    MaterialPageRoute(builder: (_) => GameScreen(config: config));
