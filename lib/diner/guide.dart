import 'package:flutter/material.dart';

import '../ui/widgets.dart';
import 'build_screen.dart' show DinerSprite;
import 'clock.dart';
import 'diner.dart';
import 'diner_art.dart';
import 'diner_painter.dart';
import 'iso.dart';
import 'recipes.dart';
import 'service.dart';

/// What each page shows above its words.
enum GuidePicture {
  day,
  place,
  change,
  seats,
  counter,
  machines,
  staff,
  menu,
  run,
  grow,
}

/// One page of the guide: a picture, a title and up to three short lines.
class GuidePage {
  const GuidePage(this.picture, this.title, this.lines);

  final GuidePicture picture;
  final String title;
  final List<String> lines;
}

/// How the game works, in the order a new player needs it.
const guidePages = [
  GuidePage(GuidePicture.day, 'How a day works', [
    'Guests queue outside, sit down, order, eat and pay.',
    'Serve them quickly, and spend less than you take.',
    'You set the room up first, then press Start day.',
  ]),
  GuidePage(GuidePicture.place, 'Placing a fixture', [
    'Pick a fixture from the shelf at the bottom of the screen.',
    'Tap the floor to aim it. Green fits, red does not.',
    'Nudge it, turn it with Rotate, then press Place.',
  ]),
  GuidePage(GuidePicture.change, 'Changing what is there', [
    'Tap a fixture to Rotate it, Move it, or Sell it back.',
    'Select picks several to move or copy together.',
    'Undo takes back your last change, coins and all.',
  ]),
  GuidePage(GuidePicture.seats, 'Tables and chairs', [
    'A chair next to a table, facing it, is one seat.',
    'A table with no chair beside it seats nobody.',
    'More seats means more guests fed at once.',
  ]),
  GuidePage(GuidePicture.counter, 'The counter', [
    'Guests pay at the counter, one at a time.',
    'They stand on the tile in front of it, so keep that tile free.',
    'Near the door means a shorter queue.',
  ]),
  GuidePage(GuidePicture.machines, 'The kitchen', [
    'Grills, fryers and other machines each cook certain dishes.',
    'Staff work from the tile in front of a machine. Keep it free.',
    'Put them near the tables, so food has a short walk.',
  ]),
  GuidePage(GuidePicture.staff, 'Staff and duties', [
    'Open Staff to hire people. A dearer advert finds better ones.',
    'Open a person to give them a duty: a machine, clearing tables, '
        'or anywhere.',
    'Wages are paid at the end of each day.',
  ]),
  GuidePage(GuidePicture.menu, 'Menu and ingredients', [
    'Menu sets your prices and how many portions to prepare today.',
    'Too few and dishes sell out. Too many are thrown away.',
    'The supplier changes what food costs, and how fresh it is.',
  ]),
  GuidePage(GuidePicture.run, 'Running the day', [
    'Start day opens the doors. The speed buttons make it faster.',
    'Tap a waiting guest to rush their order.',
    'The summary shows what you took, spent and kept.',
  ]),
  GuidePage(GuidePicture.grow, 'Growing the restaurant', [
    'Expand buys more floor. Upgrades add machines and staff places.',
    'Goals show what to try next. Stats show who comes and why.',
    'You can open this guide again from Goals.',
  ]),
];

/// The guide, one page at a time. [intro] is true the first time, from a new
/// game: the last button then starts playing.
class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key, this.intro = false});

  final bool intro;

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  int _page = 0;

  bool get _last => _page == guidePages.length - 1;

  void _go(int to) =>
      setState(() => _page = to.clamp(0, guidePages.length - 1));

  @override
  Widget build(BuildContext context) {
    final page = guidePages[_page];
    return Scaffold(
      backgroundColor: Pal.bgTop,
      body: Backdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: PxText(
                        'Step ${_page + 1} of ${guidePages.length}',
                        key: const ValueKey('guide-step'),
                        style: const TextStyle(color: Pal.dim, fontSize: 14),
                      ),
                    ),
                    if (!_last)
                      GestureDetector(
                        key: const ValueKey('guide-skip'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.of(context).pop(),
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: PxText(
                            'Skip the guide',
                            style: TextStyle(color: Pal.dim, fontSize: 14),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  flex: 3,
                  child: ClipRect(
                    key: ValueKey('guide-picture-${page.picture.name}'),
                    child: _picture(page.picture),
                  ),
                ),
                const SizedBox(height: 16),
                // The words scroll if a small screen cannot hold them.
                Flexible(
                  flex: 2,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PxText(
                          page.title,
                          key: const ValueKey('guide-title'),
                          style: const TextStyle(
                            color: Pal.gold,
                            fontSize: 26,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final line in page.lines) ...[
                          PxText(
                            line,
                            style: const TextStyle(
                              color: Pal.text,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (var i = 0; i < guidePages.length; i++) ...[
                      SizedBox(
                        key: ValueKey('guide-dot-$i'),
                        width: 8,
                        height: 8,
                        child: ColoredBox(
                          color: i == _page ? Pal.gold : Pal.dimmer,
                        ),
                      ),
                      if (i < guidePages.length - 1) const SizedBox(width: 6),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (_page > 0) ...[
                      Expanded(
                        child: GoldButton(
                          key: const ValueKey('guide-back'),
                          label: 'Back',
                          filled: false,
                          color: Pal.text,
                          onTap: () => _go(_page - 1),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      flex: 2,
                      child: GoldButton(
                        key: const ValueKey('guide-next'),
                        label: _last
                            ? (widget.intro ? 'Start playing' : 'Done')
                            : 'Next',
                        onTap: _last
                            ? () => Navigator.of(context).pop()
                            : () => _go(_page + 1),
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

  Widget _picture(GuidePicture p) {
    switch (p) {
      case GuidePicture.day:
        return GuideScene(diner: Diner.starter());
      case GuidePicture.place:
        return GuideScene(
          diner: Diner.starter(),
          placing: Kind.plant,
          hover: const Cell(4, 7),
          grid: true,
        );
      case GuidePicture.change:
        final d = Diner.starter();
        return GuideScene(diner: d, selected: d.objectAt(const Cell(5, 5)));
      case GuidePicture.seats:
        final d = Diner(coins: 100000);
        d.place(Kind.table, const Cell(3, 5));
        d.place(Kind.chair, const Cell(2, 5), Dir.se);
        d.place(Kind.chair, const Cell(4, 5), Dir.nw);
        d.place(Kind.table, const Cell(5, 3));
        return GuideScene(diner: d, showProblems: true);
      case GuidePicture.counter:
        final d = Diner.starter();
        return GuideScene(diner: d, selected: d.objectAt(const Cell(2, 3)));
      case GuidePicture.machines:
        final d = Diner.starter();
        return GuideScene(diner: d, selected: d.objectAt(const Cell(1, 3)));
      case GuidePicture.staff:
        return const _StaffPicture();
      case GuidePicture.menu:
        return const _MenuPicture();
      case GuidePicture.run:
        return GuideScene(diner: Diner.starter(), running: true);
      case GuidePicture.grow:
        final d = Diner.starter();
        return GuideScene(diner: d, expanding: true);
    }
  }
}

/// A small picture of the restaurant, drawn the way the game draws it: the
/// room alone, still, with whatever the page is about marked.
class GuideScene extends StatefulWidget {
  const GuideScene({
    super.key,
    required this.diner,
    this.placing,
    this.hover,
    this.grid = false,
    this.selected,
    this.showProblems = false,
    this.running = false,
    this.expanding = false,
  });

  final Diner diner;
  final Kind? placing;
  final Cell? hover;
  final bool grid;
  final Placed? selected;
  final bool showProblems;

  /// Show the restaurant mid-day, with its people.
  final bool running;

  /// Show the land that could be bought.
  final bool expanding;

  @override
  State<GuideScene> createState() => _GuideSceneState();
}

class _GuideSceneState extends State<GuideScene> {
  DinerSim? _sim;
  TickClock? _clock;

  @override
  void initState() {
    super.initState();
    if (widget.running) {
      final sim = DinerSim(widget.diner, seed: 7);
      // Far enough in that there are guests at the tables.
      for (var i = 0; i < 160 && !sim.finished; i++) {
        sim.tick();
      }
      _sim = sim;
      _clock = TickClock(() {});
    }
  }

  @override
  void dispose() {
    _clock?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final art = DinerArt.instance;
    if (art == null) return const SizedBox.shrink();
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return LayoutBuilder(
      builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        final d = widget.diner;
        final base = BoardFit.of(d, size, dpr, whole: widget.expanding);
        // Come in close on the room, unless the page is about the land.
        final fit = widget.expanding
            ? base
            : BoardFit.of(
                d,
                size,
                dpr,
                k: base.kFit + 2 > base.kMax ? base.kMax : base.kFit + 2,
                focus: IsoView(d).vertex(3.5, 5.5),
              );
        return CustomPaint(
          size: size,
          painter: DinerPainter(
            diner: d,
            art: art,
            fit: fit,
            placing: widget.placing,
            hover: widget.hover,
            grid: widget.grid,
            selected: widget.selected,
            showProblems: widget.showProblems,
            expanding: widget.expanding,
            sim: _sim,
            clock: _clock,
          ),
        );
      },
    );
  }
}

/// A person, and the choices for what they look after, as they are on a
/// person's page.
class _StaffPicture extends StatelessWidget {
  const _StaffPicture();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: SingleChildScrollView(
        child: Panel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const DinerSprite('chef_sw_0', mult: 3),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: PxText(
                      'Sam, cook',
                      style: TextStyle(color: Pal.text, fontSize: 18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Eyebrow('Works'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Choice(label: 'Anywhere', selected: false, onTap: null),
                  Choice(label: 'Grill', selected: true, onTap: null),
                  Choice(label: 'Fryer', selected: false, onTap: null),
                  Choice(label: 'Clears tables', selected: false, onTap: null),
                ],
              ),
              const SizedBox(height: 8),
              const PxText(
                'Sam looks after the grill first, and helps elsewhere when it '
                'needs nothing.',
                style: TextStyle(color: Pal.dim, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The menu's prices and portions, as the Menu page lists them.
class _MenuPicture extends StatelessWidget {
  const _MenuPicture();

  @override
  Widget build(BuildContext context) {
    final dishes = [Dish.burger, Dish.fries, Dish.soda];
    return Align(
      alignment: Alignment.center,
      child: SingleChildScrollView(
        child: Panel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Eyebrow('Today'),
              for (final d in dishes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: PxText(
                          recipes[d]!.name,
                          style: const TextStyle(color: Pal.text, fontSize: 17),
                        ),
                      ),
                      PxText(
                        ':coin: ${recipes[d]!.price}',
                        style: const TextStyle(color: Pal.gold, fontSize: 17),
                      ),
                      const SizedBox(width: 16),
                      const PxText(
                        '20 portions',
                        style: TextStyle(color: Pal.dim, fontSize: 14),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
