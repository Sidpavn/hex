import 'package:flutter/material.dart';

import '../data/gem_shop.dart';
import '../ui/pixel_dialog.dart';
import '../ui/widgets.dart';
import 'diner.dart';
import 'diner_sprite.dart';
import 'styles.dart';

/// Choosing a wallpaper and a floor. The ones that come free are used with a
/// tap; the rest ask first, and cost gems.
class StylePopup extends StatefulWidget {
  const StylePopup({
    super.key,
    required this.diner,
    required this.onChanged,
    required this.shop,
  });

  final Diner diner;

  /// Told after anything changes, so the game can redraw and save.
  final VoidCallback onChanged;

  /// Opens the gem shop; returns when it is closed.
  final Future<void> Function() shop;

  @override
  State<StylePopup> createState() => _StylePopupState();
}

class _StylePopupState extends State<StylePopup> {
  StyleKind _tab = StyleKind.wall;
  String _note = '';

  Diner get d => widget.diner;

  bool _inUse(Style s) =>
      s.kind == StyleKind.wall ? d.wallStyle == s.id : d.floorStyle == s.id;

  Future<void> _tap(Style s) async {
    if (d.owns(s)) {
      if (d.useStyle(s)) {
        widget.onChanged();
        setState(() => _note = '');
      }
      return;
    }
    if (d.gems < s.gems) {
      setState(
        () => _note = '${s.name} costs ${s.gems} gems. You have ${d.gems}.',
      );
      return;
    }
    final ok = await askPixel(
      context,
      title: '${s.name} ${s.kind == StyleKind.wall ? 'walls' : 'floor'}',
      body: 'Unlock for ${s.gems} gems? You keep it for good.',
      yes: 'Unlock for ${s.gems} gems',
      no: 'Not now',
      yesKey: const ValueKey('confirm-style'),
    );
    if (!ok || !mounted) return;
    if (d.buyStyle(s) == PlaceResult.ok) {
      d.useStyle(s);
      widget.onChanged();
      setState(() => _note = '${s.name} unlocked.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: size.height * 0.8),
        child: PixelBox(
          key: const ValueKey('style-popup'),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: PxText(
                      'Style',
                      style: TextStyle(color: Pal.gold, fontSize: 22),
                    ),
                  ),
                  PxText(
                    ':gem: ${d.gems}',
                    key: const ValueKey('gem-count'),
                    style: const TextStyle(color: Pal.text, fontSize: 18),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Choice(
                    key: const ValueKey('style-tab-wall'),
                    label: 'Walls',
                    selected: _tab == StyleKind.wall,
                    onTap: () => setState(() => _tab = StyleKind.wall),
                  ),
                  Choice(
                    key: const ValueKey('style-tab-floor'),
                    label: 'Floors',
                    selected: _tab == StyleKind.floor,
                    onTap: () => setState(() => _tab = StyleKind.floor),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: LayoutBuilder(
                  builder: (_, box) {
                    final w = ((box.maxWidth - 16) / 3).floorToDouble();
                    return SingleChildScrollView(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in stylesOf(_tab))
                            SizedBox(
                              width: w,
                              child: _StyleTile(
                                key: ValueKey('style-${s.kind.name}-${s.id}'),
                                style: s,
                                inUse: _inUse(s),
                                owned: d.owns(s),
                                onTap: () => _tap(s),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              if (_note.isNotEmpty) ...[
                const SizedBox(height: 8),
                PxText(
                  _note,
                  key: const ValueKey('style-note'),
                  style: const TextStyle(color: Pal.dim, fontSize: 14),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: GoldButton(
                      key: const ValueKey('get-gems'),
                      label: 'Get gems',
                      filled: false,
                      color: Pal.text,
                      onTap: () async {
                        await widget.shop();
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GoldButton(
                      key: const ValueKey('style-close'),
                      label: 'Close',
                      onTap: () => Navigator.pop(context),
                    ),
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

class _StyleTile extends StatelessWidget {
  const _StyleTile({
    super.key,
    required this.style,
    required this.inUse,
    required this.owned,
    required this.onTap,
  });

  final Style style;
  final bool inUse;
  final bool owned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = style.kind == StyleKind.wall
        ? 'wall_a${style.suffix}'
        : 'floor_a${style.suffix}';
    final status = inUse
        ? 'In use'
        : style.free
        ? 'Free'
        : owned
        ? 'Unlocked'
        : ':gem: ${style.gems}';
    return Panel(
      onTap: onTap,
      dim: !owned,
      glow: inUse ? Pal.gold : null,
      padding: const EdgeInsets.all(6),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 44,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: DinerSprite(name),
              ),
            ),
            const SizedBox(height: 4),
            PxText(
              style.name,
              style: const TextStyle(color: Pal.text, fontSize: 13),
            ),
            PxText(
              status,
              style: TextStyle(color: inUse ? Pal.gold : Pal.dim, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// Buying gems: each pack, what it holds and what it costs.
class GemShopPopup extends StatefulWidget {
  const GemShopPopup({super.key, required this.shop});

  final GemShop shop;

  @override
  State<GemShopPopup> createState() => _GemShopPopupState();
}

class _GemShopPopupState extends State<GemShopPopup> {
  Map<String, String>? _prices;
  String _note = '';

  @override
  void initState() {
    super.initState();
    widget.shop.store.prices().then((p) {
      if (mounted) setState(() => _prices = p);
    });
  }

  Future<void> _buy(GemPack p) async {
    final started = await widget.shop.store.buy(p.id);
    if (!mounted) return;
    setState(
      () => _note = started
          ? 'Thank you. Your gems arrive in a moment.'
          : 'That did not go through. Nothing was charged.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final prices = _prices;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: PixelBox(
        key: const ValueKey('gem-shop'),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PxText(
              'Get gems',
              style: TextStyle(color: Pal.gold, fontSize: 22),
            ),
            const SizedBox(height: 4),
            const PxText(
              'Gems unlock wallpapers and floors. They do not change how the '
              'diner runs.',
              style: TextStyle(color: Pal.dim, fontSize: 14),
            ),
            const SizedBox(height: 12),
            if (prices == null)
              const PxText(
                'Asking the store...',
                style: TextStyle(color: Pal.dim, fontSize: 14),
              )
            else if (prices.isEmpty)
              const PxText(
                key: ValueKey('gem-unavailable'),
                'Buying is not available on this device right now.',
                style: TextStyle(color: Pal.dim, fontSize: 14),
              )
            else
              for (final p in gemPacks)
                if (prices.containsKey(p.id)) ...[
                  GoldButton(
                    key: ValueKey('pack-${p.id}'),
                    label: '${p.gems} gems   ${prices[p.id]}',
                    filled: false,
                    color: Pal.text,
                    onTap: () => _buy(p),
                  ),
                  const SizedBox(height: 8),
                ],
            if (_note.isNotEmpty) ...[
              PxText(
                _note,
                key: const ValueKey('gem-note'),
                style: const TextStyle(color: Pal.dim, fontSize: 14),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
            GoldButton(
              key: const ValueKey('gem-close'),
              label: 'Close',
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}
