import 'package:flutter/material.dart';

import '../ui/pixel/palette.dart';
import '../ui/pixel/pixel_ui.dart';
import 'bank.dart';
import 'bank_screen.dart';
import 'diner.dart';
import 'goals.dart';
import 'goals_screen.dart';
import 'menu_screen.dart';
import 'staff_room.dart';
import 'staff_screen.dart';
import 'stats_screen.dart';
import 'upgrade_screen.dart';

/// Sixteen by sixteen one-colour pictures for the programs on the computer.
/// A '#' is lit, anything else is dark.
const Map<DeskApp, List<String>> terminalIcons = {
  DeskApp.menu: [
    '................',
    '..############..',
    '..#..........#..',
    '..#.########.#..',
    '..#..........#..',
    '..#.######...#..',
    '..#..........#..',
    '..#.########.#..',
    '..#..........#..',
    '..#.#####....#..',
    '..#..........#..',
    '..#.########.#..',
    '..#..........#..',
    '..############..',
    '................',
    '................',
  ],
  DeskApp.staff: [
    '................',
    '....####........',
    '...######..###..',
    '...######.#####.',
    '...######.#####.',
    '....####...###..',
    '..########.####.',
    '.##########.###.',
    '.##########.###.',
    '.#.######.#.###.',
    '.#.######.#.###.',
    '...##..##....#..',
    '...##..##....#..',
    '................',
    '................',
    '................',
  ],
  DeskApp.stats: [
    '................',
    '.#..............',
    '.#..............',
    '.#..........##..',
    '.#..........##..',
    '.#....##....##..',
    '.#....##....##..',
    '.#.##.##....##..',
    '.#.##.##.##.##..',
    '.#.##.##.##.##..',
    '.#.##.##.##.##..',
    '.#.##.##.##.##..',
    '.##############.',
    '................',
    '................',
    '................',
  ],
  DeskApp.goals: [
    '................',
    '..#.............',
    '..#######.......',
    '..#########.....',
    '..###########...',
    '..#########.....',
    '..#######.......',
    '..#.............',
    '..#.............',
    '..#.............',
    '..#.............',
    '..#.............',
    '.####...........',
    '................',
    '................',
    '................',
  ],
  DeskApp.upgrades: [
    '................',
    '.##############.',
    '.#............#.',
    '.#.....##.....#.',
    '.#....####....#.',
    '.#...######...#.',
    '.#..########..#.',
    '.#.....##.....#.',
    '.#.....##.....#.',
    '.#.....##.....#.',
    '.#............#.',
    '.##############.',
    '................',
    '................',
    '................',
    '................',
  ],
  DeskApp.expand: [
    '................',
    '.#####....#####.',
    '.#............#.',
    '.#............#.',
    '.#...##..##...#.',
    '.#............#.',
    '.#............#.',
    '.#............#.',
    '.#............#.',
    '.#...##..##...#.',
    '.#............#.',
    '.#............#.',
    '.#####....#####.',
    '................',
    '................',
    '................',
  ],
  DeskApp.bank: [
    '................',
    '.......##.......',
    '.....######.....',
    '...##########...',
    '.##############.',
    '................',
    '..##..##..##..#.',
    '..##..##..##..#.',
    '..##..##..##..#.',
    '..##..##..##..#.',
    '..##..##..##..#.',
    '.##############.',
    '.##############.',
    '................',
    '................',
    '................',
  ],
};

/// What a program is called on the screen, and what to say beside it.
class _Entry {
  const _Entry(this.app, this.label, {this.warn = false, this.lock});

  final DeskApp app;
  final String label;
  final bool warn;

  /// Why it cannot be opened, if it cannot.
  final String? lock;
}

/// The computer in the staff room: a green-on-dark screen with a window of
/// programs, one for each part of running the restaurant, and a note window
/// for what needs doing. Opening a program shows its page; Expand and Start
/// over go back to the restaurant and are returned to whoever opened this.
class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key, required this.diner});

  final Diner diner;

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  Diner get diner => widget.diner;
  String _status = '';

  List<_Entry> get _entries {
    final short = diner.coins < diner.roster.wages;
    return [
      const _Entry(DeskApp.menu, 'Menu'),
      _Entry(DeskApp.staff, short ? 'Staff !' : 'Staff', warn: short),
      const _Entry(DeskApp.stats, 'Stats'),
      const _Entry(DeskApp.goals, 'Goals'),
      const _Entry(DeskApp.upgrades, 'Upgrades'),
      const _Entry(DeskApp.expand, 'Expand'),
      _Entry(
        DeskApp.bank,
        diner.loan > 0 ? 'Bank !' : 'Bank',
        warn: diner.loan > 0 && diner.loanLate > 0,
        lock: diner.progress.level < DeskApp.bank.level
            ? 'The bank opens at level ${DeskApp.bank.level}'
            : null,
      ),
    ];
  }

  Future<void> _open(_Entry e) async {
    if (e.lock != null) {
      setState(() => _status = e.lock!);
      return;
    }
    setState(() => _status = '');
    final nav = Navigator.of(context);
    Widget? page;
    switch (e.app) {
      case DeskApp.menu:
        page = MenuScreen(diner: diner);
      case DeskApp.staff:
        page = StaffScreen(diner: diner);
      case DeskApp.stats:
        page = StatsScreen(diner: diner);
      case DeskApp.upgrades:
        page = UpgradeScreen(diner: diner);
      case DeskApp.bank:
        page = BankScreen(diner: diner);
      case DeskApp.goals:
        var startOver = false;
        await nav.push(
          MaterialPageRoute<void>(
            builder: (_) =>
                GoalsScreen(diner: diner, onReset: () => startOver = true),
          ),
        );
        if (!mounted) return;
        if (startOver) {
          nav.pop(DeskApp.reset);
        } else {
          setState(() {});
        }
        return;
      case DeskApp.expand:
        nav.pop(DeskApp.expand);
        return;
      case DeskApp.reset:
      case DeskApp.moveDoor:
        return;
    }
    await nav.push(MaterialPageRoute<void>(builder: (_) => page!));
    if (mounted) setState(() {});
  }

  /// What needs looking at, a line each, most pressing first.
  List<String> get _notes {
    final out = <String>[];
    final wages = diner.roster.wages;
    if (diner.coins < wages) {
      out.add('Wages tonight are $wages. Only ${diner.coins} in the till.');
    }
    if (diner.loan > 0) {
      out.add('You owe ${diner.loan}. ${Bank.due(diner.loan)} is due tonight.');
    }
    final today = diner.today;
    out.add(
      today.label == 'Ordinary day'
          ? 'Day ${diner.progress.day}: nothing unusual.'
          : 'Day ${diner.progress.day}: ${today.label}. ${today.blurb}',
    );
    final goal = diner.currentGoal;
    if (goal != null) out.add('Next goal: ${goal.title}.');
    return out.take(4).toList();
  }

  @override
  Widget build(BuildContext context) {
    final u = PixelUi.unit(context);
    final entries = _entries;
    return Scaffold(
      backgroundColor: Pal.bgTop,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(u * 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _statusBar(),
              SizedBox(height: u * 3),
              Expanded(
                flex: 3,
                child: _Window(
                  key: const ValueKey('programs'),
                  title: 'Programs',
                  onClose: () => Navigator.of(context).maybePop(),
                  child: LayoutBuilder(
                    builder: (context, c) => SingleChildScrollView(
                      child: Wrap(
                        alignment: WrapAlignment.spaceEvenly,
                        runSpacing: u * 4,
                        children: [
                          for (final e in entries)
                            SizedBox(
                              width: c.maxWidth / 3 - 1,
                              child: _Icon(entry: e, onTap: () => _open(e)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: u * 3),
              Expanded(
                flex: 2,
                child: _Window(
                  key: const ValueKey('notes'),
                  title: 'Notes',
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_status.isNotEmpty)
                          PxText(
                            '> $_status',
                            key: const ValueKey('terminal-status'),
                            style: const TextStyle(
                              color: Pal.gold,
                              fontSize: 15,
                            ),
                          ),
                        for (final n in _notes)
                          PxText(
                            '> $n',
                            style: const TextStyle(
                              color: Pal.green,
                              fontSize: 15,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBar() => Row(
    key: const ValueKey('terminal-bar'),
    children: [
      const Expanded(
        child: PxText(
          'OFFICE',
          style: TextStyle(color: Pal.green, fontSize: 20),
        ),
      ),
      PxText(
        'Day ${diner.progress.day}   :coin: ${diner.coins}',
        key: const ValueKey('terminal-clock'),
        style: const TextStyle(color: Pal.green, fontSize: 18),
      ),
    ],
  );
}

/// A window with a ruled title bar: a square to close it at the left, the
/// name in the middle, and a double border.
class _Window extends StatelessWidget {
  const _Window({
    super.key,
    required this.title,
    required this.child,
    this.onClose,
  });

  final String title;
  final Widget child;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final u = PixelUi.unit(context);
    Widget line() => Container(height: u, color: Pal.green);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Pal.green, width: u * 2),
      ),
      padding: EdgeInsets.all(u * 2),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Pal.green, width: u),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.all(u * 2),
              child: Row(
                children: [
                  GestureDetector(
                    key: ValueKey('close-${title.toLowerCase()}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: onClose,
                    child: Container(
                      width: u * 6,
                      height: u * 6,
                      margin: EdgeInsets.all(u * 2),
                      decoration: BoxDecoration(
                        border: Border.all(color: Pal.green, width: u),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        line(),
                        SizedBox(height: u * 2),
                        line(),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: u * 4),
                    child: PxText(
                      title,
                      style: const TextStyle(color: Pal.green, fontSize: 17),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        line(),
                        SizedBox(height: u * 2),
                        line(),
                      ],
                    ),
                  ),
                  SizedBox(width: u * 10),
                ],
              ),
            ),
            Container(height: u, color: Pal.green),
            Expanded(
              child: Padding(padding: EdgeInsets.all(u * 4), child: child),
            ),
          ],
        ),
      ),
    );
  }
}

/// One program on the desktop: its picture and name. Pressed, it turns light
/// on dark.
class _Icon extends StatefulWidget {
  const _Icon({required this.entry, required this.onTap});

  final _Entry entry;
  final VoidCallback onTap;

  @override
  State<_Icon> createState() => _IconState();
}

class _IconState extends State<_Icon> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final u = PixelUi.unit(context);
    final e = widget.entry;
    final ink = e.lock != null
        ? Pal.dimmer
        : e.warn
        ? Pal.red
        : Pal.green;
    final fg = _down ? Pal.bgTop : ink;
    return GestureDetector(
      key: ValueKey('app-${e.app.name}'),
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: _down ? ink : Colors.transparent,
            padding: EdgeInsets.all(u * 2),
            child: CustomPaint(
              size: Size(u * 3 * 16, u * 3 * 16),
              painter: _IconPainter(terminalIcons[e.app]!, fg, u * 3),
            ),
          ),
          SizedBox(height: u * 2),
          Container(
            color: _down ? ink : Colors.transparent,
            padding: EdgeInsets.symmetric(horizontal: u * 2),
            child: PxText(
              e.label,
              key: ValueKey('app-label-${e.app.name}'),
              style: TextStyle(color: fg, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.rows, this.colour, this.px);

  final List<String> rows;
  final Color colour;
  final double px;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colour
      ..isAntiAlias = false;
    for (var y = 0; y < rows.length; y++) {
      for (var x = 0; x < rows[y].length; x++) {
        if (rows[y][x] == '#') {
          canvas.drawRect(Rect.fromLTWH(x * px, y * px, px, px), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.colour != colour || old.px != px || old.rows != rows;
}
