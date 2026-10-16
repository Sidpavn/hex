import 'dart:async';

import 'package:flutter/material.dart';

import '../data/storage.dart';
import '../ui/widgets.dart';
import 'diner.dart';
import 'diner_art.dart';
import 'room.dart';
import 'service.dart';
import 'staff_room.dart';
import 'terminal_screen.dart';

/// The staff room, on a page of its own. Tap the computer to run the
/// restaurant from it. Between days, Edit lets the room be arranged: things
/// can be moved, turned, bought and sold, like the dining room.
class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key, required this.diner, this.sim});

  final Diner diner;

  /// The day in progress, if there is one: it shows who is resting, and the
  /// computer is locked.
  final DinerSim? sim;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  Diner get diner => widget.diner;
  StaffRoom get room => diner.room;
  bool get _service => widget.sim != null;

  bool _edit = false;
  RoomItem? _selected;
  RoomItem? _moving;
  RoomKind? _placing;
  Cell? _hover;
  Dir _facing = Dir.sw;
  String _note = '';
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // A day in progress keeps moving behind this page.
    if (_service) {
      _tick = Timer.periodic(
        const Duration(milliseconds: 400),
        (_) => mounted ? setState(() {}) : null,
      );
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _save() => Storage.saveDiner(diner);

  bool get _aiming => _placing != null;

  RoomResult? get _result {
    final kind = _placing;
    final at = _hover;
    if (kind == null || at == null) return null;
    return room.check(kind, at, sofas: diner.loungeLevel, ignore: _moving);
  }

  List<Rester> get _resters => [
    for (final w in widget.sim?.workers ?? const <Worker>[])
      if (w.state == WorkState.resting)
        Rester(w.sprite, w.staff.name, w.energy.round()),
  ];

  // -------------------------------------------------------------- taps

  Cell _cellAt(Offset local, double unit, DinerArt art) {
    final c = StaffRoomPainter.cellAt(art, local / unit);
    // A tall thing is tapped above its own tile: prefer what is just in front.
    final front = Cell(c.x + 1, c.y + 1);
    return room.inside(front) && room.objectAt(front) != null ? front : c;
  }

  Future<void> _tap(Cell c) async {
    if (_aiming) {
      setState(() {
        _hover = c;
        _note = '';
      });
      return;
    }
    final hit = room.pickAt(c);
    if (!_edit) {
      if (hit?.kind == RoomKind.computer) await _useComputer();
      return;
    }
    setState(() {
      _selected = hit == _selected ? null : hit;
      _note = '';
    });
  }

  Future<void> _useComputer() async {
    if (_service) {
      setState(() => _note = 'The computer is for between days.');
      return;
    }
    final app = await Navigator.of(context).push<DeskApp>(
      MaterialPageRoute(builder: (_) => TerminalScreen(diner: diner)),
    );
    if (!mounted) return;
    if (app != null) {
      Navigator.of(context).pop(app);
    } else {
      setState(() {});
    }
  }

  // ------------------------------------------------------------ editing

  void _pick(RoomKind kind) {
    final def = roomDefs[kind]!;
    final spot = room.freeSpot(kind, sofas: diner.loungeLevel);
    setState(() {
      _selected = null;
      _moving = null;
      _placing = kind;
      _facing = Dir.sw;
      _hover = spot ?? const Cell(1, 2);
      _note = spot == null && kind == RoomKind.sofa
          ? RoomResult.full.message
          : def.info;
    });
  }

  void _startMove() {
    final sel = _selected;
    if (sel == null) return;
    setState(() {
      _moving = sel;
      _placing = sel.kind;
      _facing = sel.facing;
      _hover = sel.at;
      _selected = null;
      _note = '';
    });
  }

  void _turn() {
    final sel = _selected;
    if (_aiming) {
      setState(() => _facing = _facing.cw);
      return;
    }
    if (sel == null || !sel.def.turns) return;
    setState(() => sel.facing = sel.facing.cw);
    _save();
  }

  void _commit() {
    final kind = _placing;
    final at = _hover;
    if (kind == null || at == null) return;
    final moving = _moving;
    final r = moving != null
        ? diner.roomMove(moving, at, _facing)
        : diner.roomPlace(kind, at, _facing);
    setState(() {
      if (r == RoomResult.ok) {
        _note = moving != null ? '' : '${roomDefs[kind]!.name} placed';
        _placing = null;
        _moving = null;
        _hover = null;
        _selected = null;
      } else {
        _note = r.message;
      }
    });
    if (r == RoomResult.ok) _save();
  }

  void _cancel() => setState(() {
    _placing = null;
    _moving = null;
    _hover = null;
    _note = '';
  });

  void _sell() {
    final sel = _selected;
    if (sel == null) return;
    setState(() {
      diner.roomSell(sel);
      _selected = null;
      _note = '';
    });
    _save();
  }

  // -------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final art = DinerArt.instance;
    return ScreenFrame(
      title: 'Staff room',
      subtitle: _service
          ? 'The day is running'
          : _edit
          ? 'Arranging the room'
          : 'Tap the computer',
      trailing: PxText(
        ':coin: ${diner.coins}',
        style: const TextStyle(color: Pal.text, fontSize: 20),
      ),
      child: Column(
        children: [
          Expanded(
            child: art == null
                ? const SizedBox.shrink()
                : LayoutBuilder(
                    builder: (context, c) => _scene(art, c.biggest),
                  ),
          ),
          _panel(),
        ],
      ),
    );
  }

  Widget _scene(DinerArt art, Size area) {
    final size = StaffRoomPainter.size(art);
    final dpr = MediaQuery.of(context).devicePixelRatio;
    // The largest whole number of device pixels per art pixel that fits.
    final k = ((area.width / size.width) * dpr)
        .floor()
        .clamp(1, 12)
        .clamp(1, ((area.height / size.height) * dpr).floor().clamp(1, 12));
    final unit = k / dpr;
    final w = size.width * unit;
    final h = size.height * unit;
    final at = _hover;
    final kind = _placing;
    return Center(
      child: SizedBox(
        key: const ValueKey('room-scene'),
        width: w,
        height: h,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _tap(_cellAt(d.localPosition, unit, art)),
          child: CustomPaint(
            painter: StaffRoomPainter(
              art: art,
              room: room,
              resters: _resters,
              unit: unit,
              selected: _selected,
              moving: _moving,
              ghost: kind != null && at != null
                  ? RoomGhost(kind, at, _facing, _result == RoomResult.ok)
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _panel() {
    final sel = _selected;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_infoLine() != '') ...[
            PxText(
              _infoLine(),
              key: const ValueKey('room-info'),
              style: TextStyle(
                color: _result != null && _result != RoomResult.ok
                    ? Pal.red
                    : Pal.dim,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (_service) ..._energies(),
          if (_aiming)
            _aimRow()
          else if (sel != null)
            _selectedRow(sel)
          else if (_edit)
            _shelf()
          else
            _normalRow(),
        ],
      ),
    );
  }

  String _infoLine() {
    if (_note.isNotEmpty) return _note;
    final r = _result;
    if (_aiming) {
      return r == null || r == RoomResult.ok
          ? 'Tap a tile to aim, then ${_moving == null ? 'Place' : 'Put down'}.'
          : r.message;
    }
    final sofas = room.sofaCount;
    final n = _resters.length;
    if (_service) {
      return n == 0
          ? '$sofas ${sofas == 1 ? 'sofa' : 'sofas'}, nobody resting'
          : '$n of $sofas ${sofas == 1 ? 'sofa' : 'sofas'} in use: '
                '${_resters.map((r) => r.name).join(', ')}';
    }
    if (_edit) return 'Tap something in the room to move or turn it.';
    return sofas == 0
        ? 'No sofas yet. Staff sofas is in Upgrades, on the computer.'
        : '$sofas ${sofas == 1 ? 'sofa' : 'sofas'}. Tired staff rest here.';
  }

  List<Widget> _energies() => [
    for (final w in widget.sim!.workers) _energy(w),
    const SizedBox(height: 8),
  ];

  /// A person and how much they have left, as a short bar.
  Widget _energy(Worker w) {
    final e = (w.energy / 100).clamp(0.0, 1.0);
    final colour = w.isTired ? Pal.red : (e < 0.6 ? Pal.gold : Pal.green);
    return Padding(
      key: ValueKey('energy-${w.staff.id}'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: PxText(
              w.staff.name,
              style: const TextStyle(color: Pal.text, fontSize: 14),
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 8,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (e > 0)
                    Expanded(
                      flex: (e * 100).round().clamp(1, 100),
                      child: ColoredBox(color: colour),
                    ),
                  Expanded(
                    flex: ((1 - e) * 100).round().clamp(1, 100),
                    child: const ColoredBox(color: Pal.panelLo),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: PxText(
              w.state == WorkState.resting
                  ? 'resting'
                  : w.isTired
                  ? 'tired'
                  : '${w.energy.round()}%',
              key: ValueKey('energy-text-${w.staff.id}'),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: w.isTired ? Pal.red : Pal.dim,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _normalRow() => Row(
    children: [
      if (!_service) ...[
        Expanded(
          child: GoldButton(
            key: const ValueKey('room-edit'),
            label: 'Edit room',
            filled: false,
            color: Pal.text,
            onTap: () => setState(() {
              _edit = true;
              _note = '';
            }),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GoldButton(
            key: const ValueKey('move-door'),
            label: 'Move the door',
            filled: false,
            color: Pal.text,
            onTap: () => Navigator.of(context).pop(DeskApp.moveDoor),
          ),
        ),
        const SizedBox(width: 8),
      ],
      Expanded(
        child: GoldButton(
          key: const ValueKey('room-done'),
          label: 'Leave',
          onTap: () => Navigator.of(context).pop(),
        ),
      ),
    ],
  );

  Widget _shelf() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          for (final kind in [RoomKind.sofa, RoomKind.plant, RoomKind.rug]) ...[
            Expanded(child: _shelfTile(kind)),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: GoldButton(
              key: const ValueKey('room-finish'),
              label: 'Done',
              onTap: () => setState(() {
                _edit = false;
                _note = '';
              }),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _shelfTile(RoomKind kind) {
    final def = roomDefs[kind]!;
    final left = kind == RoomKind.sofa
        ? diner.loungeLevel - room.sofaCount
        : null;
    final label = switch (kind) {
      RoomKind.sofa => 'Sofa ${left! > 0 ? '($left)' : ''}',
      _ => '${def.name} ${def.cost}',
    };
    final blocked = kind == RoomKind.sofa ? left! <= 0 : diner.coins < def.cost;
    return GoldButton(
      key: ValueKey('room-pick-${kind.name}'),
      label: label.trim(),
      filled: false,
      color: blocked ? Pal.dim : Pal.text,
      onTap: blocked ? null : () => _pick(kind),
    );
  }

  Widget _selectedRow(RoomItem sel) => Row(
    children: [
      Expanded(
        child: GoldButton(
          key: const ValueKey('room-move'),
          label: 'Move',
          filled: false,
          color: Pal.text,
          onTap: _startMove,
        ),
      ),
      if (sel.def.turns) ...[
        const SizedBox(width: 8),
        Expanded(
          child: GoldButton(
            key: const ValueKey('room-turn'),
            label: 'Turn',
            filled: false,
            color: Pal.text,
            onTap: _turn,
          ),
        ),
      ],
      if (sel.def.refund > 0) ...[
        const SizedBox(width: 8),
        Expanded(
          child: GoldButton(
            key: const ValueKey('room-sell'),
            label: 'Sell +${sel.def.refund}',
            filled: false,
            color: Pal.dim,
            onTap: _sell,
          ),
        ),
      ],
      const SizedBox(width: 8),
      Expanded(
        child: GoldButton(
          key: const ValueKey('room-deselect'),
          label: 'Done',
          onTap: () => setState(() => _selected = null),
        ),
      ),
    ],
  );

  Widget _aimRow() => Row(
    children: [
      if (roomDefs[_placing]!.turns) ...[
        Expanded(
          child: GoldButton(
            key: const ValueKey('room-turn'),
            label: 'Turn',
            filled: false,
            color: Pal.text,
            onTap: _turn,
          ),
        ),
        const SizedBox(width: 8),
      ],
      Expanded(
        child: GoldButton(
          key: const ValueKey('room-cancel'),
          label: 'Cancel',
          filled: false,
          color: Pal.dim,
          onTap: _cancel,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: GoldButton(
          key: const ValueKey('room-place'),
          label: _moving == null ? 'Place' : 'Put down',
          onTap: _result == RoomResult.ok ? _commit : null,
        ),
      ),
    ],
  );
}
