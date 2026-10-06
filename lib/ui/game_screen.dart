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
      backgroundColor: Pal.bgTop,
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
        if (step == null || game.passing) {
          return const SizedBox(width: double.infinity);
        }
        return Padding(
          key: ValueKey(game.coachIndex),
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: PixelBox(
            color: Pal.panel,
            border: Pal.gold,
            padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
            child: Row(
              children: [
                const PxIcon('book', mult: 2),
                const SizedBox(width: 10),
                Expanded(
                  child: PxText(
                    step.text,
                    style: const TextStyle(
                      color: Pal.text,
                      fontSize: 14,
                      height: 1.1,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                if (step.until == CoachEvent.next)
                  SizedBox(
                    width: 84,
                    child: GoldButton(label: 'Got it', onTap: game.coachNext),
                  )
                else
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: game.hideCoach,
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: PxIcon('close'),
                    ),
                  ),
              ],
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
              _heroBar(ph, Team.player, Pal.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Round ${game.round}',
                      style: const TextStyle(
                        color: Pal.text,
                        fontSize: 16,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    PxText(
                      game.objectiveText,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Pal.goldLight,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _energy(),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _heroBar(eh, Team.enemy, Pal.red),
            ],
          ),
        );
      },
    );
  }

  Widget _heroBar(Unit? hero, Team team, Color color) {
    final frac = hero == null ? 0.0 : hero.hp / hero.stats.maxHp;
    return SizedBox(
      width: 92,
      child: Row(
        children: [
          hero == null
              ? const PxIcon('skull')
              : UnitPortrait(hero.type, team: team, mult: 1),
          const SizedBox(width: 4),
          Expanded(
            child: PxBar(value: frac, color: color),
          ),
        ],
      ),
    );
  }

  Widget _energy() {
    final n = game.energy;
    final shown = math.max(n, 3);
    final u = PixelUi.unit(context);
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const PxIcon('bolt'),
          const SizedBox(width: 4),
          for (var i = 0; i < shown; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 6 * u,
              height: 6 * u,
              decoration: BoxDecoration(
                color: i < n ? Pal.gold : Pal.panelLo,
                border: Border.all(color: Pal.ink, width: u),
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
                child: PxText(
                  game.hint,
                  key: ValueKey(game.hint),
                  style: const TextStyle(color: Pal.dim, fontSize: 13),
                ),
              ),
              const SizedBox(width: 10),
              Pulse(
                active: enabled && (game.coachStep?.endTurn ?? false),
                child: SizedBox(
                  width: 136,
                  child: GoldButton(
                    label: 'End turn',
                    onTap: enabled ? game.endTurn : null,
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
            // Cards keep one readable size. When the hand outgrows the row
            // they overlap like a held hand, and the selected card lifts to
            // the front.
            const cardW = 84.0;
            const gap = 6.0;
            final hand = game.hand;
            final n = hand.length;
            final avail = cons.maxWidth - 16;
            final fits = n * cardW + (n - 1) * gap <= avail;
            final step = n <= 1
                ? 0.0
                : fits
                ? cardW + gap
                : (avail - cardW) / (n - 1);
            final total = n == 0 ? 0.0 : cardW + step * (n - 1);
            final start = (cons.maxWidth - total) / 2;

            Widget card(int i) => Positioned(
              key: ValueKey(hand[i].id),
              left: start + step * i,
              bottom: 0,
              child: Pulse(
                active: game.coachStep?.card == hand[i].type,
                child: CardView(
                  card: hand[i],
                  width: cardW,
                  index: i,
                  count: n,
                  selected: game.selectedCard == hand[i],
                  affordable: game.canCast(hand[i]),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    game.selectCard(hand[i]);
                  },
                ),
              ),
            );

            final selected = [
              for (var i = 0; i < n; i++)
                if (game.selectedCard == hand[i]) i,
            ];
            return SizedBox(
              height: cardW * 1.5 + 34,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < n; i++)
                    if (!selected.contains(i)) card(i),
                  for (final i in selected) card(i),
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
    final u = PixelUi.unit(context);
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            key: ValueKey(_bannerId),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 1700),
            builder: (context, t, _) {
              // Eased slide in and out, snapped to whole UI pixels; no fade.
              final inP = Curves.easeOutCubic.transform(
                (t / 0.18).clamp(0.0, 1.0),
              );
              final outP = Curves.easeInCubic.transform(
                ((t - 0.78) / 0.22).clamp(0.0, 1.0),
              );
              if (t < 0.02 || t > 0.99) return const SizedBox.shrink();
              final slide =
                  (-(1 - inP) * 140).roundToDouble() * u +
                  (outP * 140).roundToDouble() * u;
              return Transform.translate(
                offset: Offset(slide, 0),
                child: PixelBox(
                  color: Pal.panel,
                  border: Pal.gold,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 8,
                  ),
                  child: PxText(
                    _banner!,
                    style: const TextStyle(
                      color: Pal.gold,
                      fontSize: 26,
                      height: 1,
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
    final color = game.turn == Team.player ? Pal.blue : Pal.red;
    return Positioned.fill(
      child: Material(
        color: Pal.ink,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PxIcon('phone', mult: 3),
              const SizedBox(height: 14),
              Text(
                'Pass to $next',
                style: TextStyle(color: color, fontSize: 34, height: 1),
              ),
              const SizedBox(height: 6),
              Text(
                'Round ${game.round}. Your hand is hidden until you tap.',
                style: const TextStyle(color: Pal.dim, fontSize: 14),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 200,
                child: GoldButton(
                  label: "I'm ready",
                  color: color,
                  onTap: game.confirmPass,
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
        ? '${GameController.teamName(game.winner!)} wins'
        : won
        ? 'Victory'
        : 'Defeat';
    final accent = hot
        ? (game.winner == Team.player ? Pal.blue : Pal.red)
        : won
        ? Pal.gold
        : Pal.red;
    Widget line(String text, Color color) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: PxText(text, style: TextStyle(color: color, fontSize: 15)),
    );
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xCC1A1C2C),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PxIcon(won ? 'trophy' : 'skull', mult: 4),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: TextStyle(color: accent, fontSize: 44, height: 1),
                ),
                const SizedBox(height: 4),
                Text(
                  game.winReason,
                  style: const TextStyle(color: Pal.dim, fontSize: 15),
                ),
                if (_result.stars > 0) ...[
                  const SizedBox(height: 10),
                  Stars(_result.stars, mult: 2),
                ],
                if (_result.newBest) line('New personal best!', Pal.green),
                for (final c in _result.newCards)
                  line(
                    'Unlocked card: :${cardInfo[c]!.icon}: ${cardInfo[c]!.name}',
                    Pal.purple,
                  ),
                for (final m in _result.newModes)
                  line('Mode unlocked: $m', Pal.green),
                for (final h in _result.newHeroes)
                  line('Unlocked hero: ${unitStats[h]!.name}', Pal.purple),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    if (hasNext)
                      SizedBox(
                        width: 140,
                        child: GoldButton(
                          label: 'Next level',
                          onTap: () => Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => GameScreen(
                                config: Storage.configFor(
                                  campaignLevels[levelIdx + 1],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    SizedBox(
                      width: 140,
                      child: GoldButton(
                        label: won && !hasNext ? 'Play again' : 'Retry',
                        filled: !hasNext,
                        onTap: _restart,
                      ),
                    ),
                    SizedBox(
                      width: 140,
                      child: GoldButton(
                        label: 'Menu',
                        filled: false,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
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
}
