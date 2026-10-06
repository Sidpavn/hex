import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../data/storage.dart';
import '../game/campaign.dart';
import '../game/config.dart';
import '../game/game_controller.dart';
import '../game/hex.dart';
import '../game/models.dart';
import 'board_painter.dart';
import 'card_view.dart';
import 'fx_layer.dart';
import 'widgets.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.config = const GameConfig()});

  final GameConfig config;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  late final GameController game = GameController(config: widget.config);
  late final FxLayer fx = FxLayer(game);
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  String? _banner;
  int _bannerId = 0;
  bool _recorded = false;
  GameResult _result = const GameResult();

  @override
  void initState() {
    super.initState();
    game.fx = fx.handle;
    fx.onBanner = (text) {
      if (!mounted) return;
      setState(() {
        _banner = text;
        _bannerId++;
      });
    };
    game.addListener(_onGameChanged);
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) => game.announceTurn());
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    fx.update(dt);
  }

  /// Saves the outcome to the profile the first time the game ends.
  void _onGameChanged() {
    final w = game.winner;
    if (w == null || _recorded) return;
    _recorded = true;
    final hot = widget.config.hotseat;
    final r = Storage.recordGame(
      widget.config,
      won: hot || w == Team.player,
      rounds: game.round,
    );
    _result = hot ? const GameResult() : r;
  }

  @override
  void dispose() {
    game.removeListener(_onGameChanged);
    _ticker.dispose();
    game.dispose();
    super.dispose();
  }

  void _restart() {
    _recorded = false;
    _result = const GameResult();
    fx.reset();
    game.newGame();
    game.announceTurn();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12231F),
      body: Stack(
        children: [
          Column(
            children: [
              SafeArea(bottom: false, child: _hud()),
              Expanded(child: _board()),
              _coach(),
              _controls(),
              _hand(),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 4),
            ],
          ),
          if (_banner != null) _bannerOverlay(),
          ListenableBuilder(
            listenable: game,
            builder: (context, _) => game.winner != null
                ? _gameOver()
                : game.passing
                ? _passOverlay()
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── board ─────────────────────────

  Widget _board() {
    return LayoutBuilder(
      builder: (context, cons) {
        final size = Size(cons.maxWidth, cons.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            final h = BoardLayout.fit(size).fromPixel(d.localPosition);
            HapticFeedback.selectionClick();
            game.tapHex(h);
          },
          child: CustomPaint(size: size, painter: BoardPainter(game, fx)),
        );
      },
    );
  }

  // ───────────────────────── coach ─────────────────────────

  Widget _coach() {
    return ListenableBuilder(
      listenable: game,
      builder: (context, _) {
        final step = game.coachStep;
        return AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: step == null || game.passing
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  child: Container(
                    key: ValueKey(game.coachIndex),
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                    decoration: BoxDecoration(
                      color: const Color(0xE60B1512),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Pal.goldLight, width: 1.5),
                      boxShadow: const [
                        BoxShadow(color: Color(0x55FFC400), blurRadius: 14),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text('🎓', style: TextStyle(fontSize: 24)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            step.text,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              height: 1.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (step.until == CoachEvent.next)
                          FilledButton(
                            onPressed: game.coachNext,
                            style: FilledButton.styleFrom(
                              backgroundColor: Pal.gold,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                            child: const Text(
                              'Got it',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          )
                        else
                          IconButton(
                            tooltip: 'Hide tips',
                            visualDensity: VisualDensity.compact,
                            onPressed: game.hideCoach,
                            icon: const Icon(
                              Icons.close,
                              size: 18,
                              color: Colors.white54,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  // ───────────────────────── HUD ─────────────────────────

  Widget _hud() {
    return ListenableBuilder(
      listenable: game,
      builder: (context, _) {
        final ph = game.heroOf(Team.player);
        final eh = game.heroOf(Team.enemy);
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              _heroBar(ph?.emoji ?? '💀', ph, const Color(0xFF6FA3FF)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'ROUND ${game.round}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      game.objectiveText,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFFFE082),
                        fontSize: 10.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _energy(),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _heroBar(eh?.emoji ?? '💀', eh, const Color(0xFFFF7A7A)),
            ],
          ),
        );
      },
    );
  }

  Widget _heroBar(String emoji, Unit? hero, Color color) {
    final frac = hero == null ? 0.0 : hero.hp / hero.stats.maxHp;
    return SizedBox(
      width: 86,
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 4),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: frac, end: frac),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
                builder: (_, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 10,
                  backgroundColor: Colors.black38,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _energy() {
    final n = game.energy;
    final shown = math.max(n, 3);
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('⚡', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 4),
          for (var i = 0; i < shown; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.elasticOut,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: i < n ? 16 : 12,
              height: i < n ? 16 : 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < n ? const Color(0xFFFFE082) : Colors.white12,
                // Keep blur constant: elasticOut overshoots t>1, and lerping
                // a shadow to/from null would make blurRadius negative.
                boxShadow: [
                  BoxShadow(
                    color: i < n
                        ? const Color(0xAAFFC400)
                        : const Color(0x00FFC400),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ───────────────────────── controls + hand ─────────────────────────

  Widget _controls() {
    return ListenableBuilder(
      listenable: game,
      builder: (context, _) {
        final enabled = game.isPlayerTurn;
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
          child: Row(
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    game.hint,
                    key: ValueKey(game.hint),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: enabled ? 1 : 0.4,
                child: Pulse(
                  active: enabled && (game.coachStep?.endTurn ?? false),
                  radius: 40,
                  child: FilledButton(
                    onPressed: enabled ? game.endTurn : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE0A030),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                    ),
                    child: const Text(
                      'End turn',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _hand() {
    return ListenableBuilder(
      listenable: game,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, cons) {
            final n = math.max(game.hand.length, 4);
            final cardW = ((cons.maxWidth - 16) / n - 6).clamp(60.0, 92.0);
            return SizedBox(
              height: cardW * 1.5 + 34,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < game.hand.length; i++)
                    Padding(
                      key: ValueKey(game.hand[i].id),
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Pulse(
                        active: game.coachStep?.card == game.hand[i].type,
                        child: CardView(
                          card: game.hand[i],
                          width: cardW,
                          index: i,
                          count: game.hand.length,
                          selected: game.selectedCard == game.hand[i],
                          affordable: game.canAfford(game.hand[i]),
                          onTap: () {
                            HapticFeedback.lightImpact();
                            game.selectCard(game.hand[i]);
                          },
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ───────────────────────── overlays ─────────────────────────

  Widget _bannerOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            key: ValueKey(_bannerId),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 1700),
            builder: (context, t, _) {
              final fadeIn = Curves.easeOut.transform(
                (t / 0.18).clamp(0.0, 1.0),
              );
              final fadeOut =
                  1 -
                  Curves.easeIn.transform(((t - 0.78) / 0.22).clamp(0.0, 1.0));
              final slide = (1 - fadeIn) * -80 + (1 - fadeOut) * 80;
              return Opacity(
                opacity: math.min(fadeIn, fadeOut),
                child: Transform.translate(
                  offset: Offset(slide, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xCC0B1512),
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(
                        color: const Color(0xFFFFE082),
                        width: 2,
                      ),
                      boxShadow: const [
                        BoxShadow(color: Color(0x66FFC400), blurRadius: 24),
                      ],
                    ),
                    child: Text(
                      _banner!,
                      style: const TextStyle(
                        color: Color(0xFFFFE082),
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _passOverlay() {
    final next = GameController.teamName(game.turn);
    final color = game.turn == Team.player
        ? const Color(0xFF6FA3FF)
        : const Color(0xFFFF7A7A);
    return Positioned.fill(
      child: Material(
        color: const Color(0xFF0B1512),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('📱', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 12),
              Text(
                'Pass to $next',
                style: TextStyle(
                  color: color,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Round ${game.round}  •  your hand is hidden until you tap',
                style: const TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: game.confirmPass,
                style: FilledButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 14,
                  ),
                ),
                child: const Text(
                  "I'm ready",
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gameOver() {
    final hot = widget.config.hotseat;
    final won = hot || game.winner == Team.player;
    final levelIdx = widget.config.level;
    final hasNext =
        won && levelIdx != null && levelIdx + 1 < campaignLevels.length;
    final title = hot
        ? '${GameController.teamName(game.winner!).toUpperCase()} WINS'
        : won
        ? 'VICTORY'
        : 'DEFEAT';
    final accent = hot
        ? (game.winner == Team.player
              ? const Color(0xFF6FA3FF)
              : const Color(0xFFFF7A7A))
        : won
        ? const Color(0xFFFFE082)
        : const Color(0xFFFF7A7A);
    return Positioned.fill(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOut,
        builder: (context, t, child) => Container(
          color: Colors.black.withValues(alpha: 0.6 * t),
          child: Opacity(opacity: t, child: child),
        ),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.3, end: 1),
            duration: const Duration(milliseconds: 1100),
            curve: Curves.elasticOut,
            builder: (context, s, child) =>
                Transform.scale(scale: s, child: child),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(won ? '🏆' : '💀', style: const TextStyle(fontSize: 72)),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: accent,
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  game.winReason,
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
                if (_result.stars > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${'★' * _result.stars}${'☆' * (3 - _result.stars)}',
                    style: const TextStyle(
                      color: Color(0xFFFFD54F),
                      fontSize: 36,
                      letterSpacing: 4,
                    ),
                  ),
                ],
                if (_result.newBest)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'New personal best!',
                      style: TextStyle(color: Color(0xFF69F0AE)),
                    ),
                  ),
                for (final c in _result.newCards)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Unlocked card: ${cardInfo[c]!.emoji} ${cardInfo[c]!.name}',
                      style: const TextStyle(color: Color(0xFFD1A3FF)),
                    ),
                  ),
                for (final m in _result.newModes)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Mode unlocked: $m',
                      style: const TextStyle(
                        color: Pal.green,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                for (final h in _result.newHeroes)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Unlocked hero: ${unitStats[h]!.name}',
                      style: const TextStyle(color: Color(0xFFD1A3FF)),
                    ),
                  ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    if (hasNext)
                      FilledButton(
                        onPressed: () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => GameScreen(
                              config: Storage.configFor(
                                campaignLevels[levelIdx + 1],
                              ),
                            ),
                          ),
                        ),
                        style: _bigButton,
                        child: const Text('Next level'),
                      ),
                    FilledButton(
                      onPressed: _restart,
                      style: hasNext ? _ghostButton : _bigButton,
                      child: Text(won && !hasNext ? 'Play again' : 'Retry'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      style: _ghostButton,
                      child: const Text('Menu'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static final ButtonStyle _bigButton = FilledButton.styleFrom(
    backgroundColor: const Color(0xFFE0A030),
    foregroundColor: Colors.black,
    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
    textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
  );

  static final ButtonStyle _ghostButton = FilledButton.styleFrom(
    backgroundColor: Colors.white12,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
    textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
  );
}
