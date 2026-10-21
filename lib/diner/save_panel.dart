import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/cloud_save.dart';
import '../data/save_sync.dart';
import '../ui/pixel_dialog.dart';
import '../ui/widgets.dart';
import 'diner.dart';

/// Keeping the save safe: its whole text can be copied to somewhere the player
/// trusts (a note, a message to themselves), and pasted back on another phone
/// or after a reinstall.
class SavePanel extends StatefulWidget {
  const SavePanel({
    super.key,
    required this.diner,
    this.onLoad,
    this.store,
    this.onSave,
    this.onTitle,
  });

  /// The game being kept, or null for an empty place that can only be filled.
  final Diner? diner;

  /// Called with the diner read from a code the player has chosen to load.
  final ValueChanged<Diner>? onLoad;

  /// Where the save can also be kept off the phone, if anywhere.
  final CloudStore? store;

  /// Writes the game to this phone now. Shown as "Save now" when given.
  final VoidCallback? onSave;

  /// Goes back to the title screen. Shown when given.
  final VoidCallback? onTitle;

  @override
  State<SavePanel> createState() => _SavePanelState();
}

class _SavePanelState extends State<SavePanel> {
  String _note = '';
  bool _bad = false;
  bool _syncing = false;

  Future<void> _copy() async {
    await Clipboard.setData(
      ClipboardData(text: SaveCode.encode(widget.diner!)),
    );
    if (!mounted) return;
    setState(() {
      _bad = false;
      _note =
          'Copied. Paste it somewhere safe: a note, or a message to yourself.';
    });
  }

  Future<void> _saveNow() async {
    widget.onSave!();
    final store = widget.store;
    final d = widget.diner;
    setState(() {
      _bad = false;
      _note = store == null ? 'Saved on this phone.' : 'Saved on this phone...';
    });
    if (store == null || d == null) return;
    final cloud = await SaveSync(store).quiet(d);
    if (!mounted) return;
    setState(() {
      _note = cloud == null
          ? 'Saved on this phone.'
          : 'Saved on this phone. $cloud.';
    });
  }

  Future<void> _sync() async {
    final store = widget.store!;
    setState(() {
      _syncing = true;
      _bad = false;
      _note = 'Talking to ${store.name}...';
    });
    String note;
    var bad = false;
    Diner? next;
    try {
      final r = await SaveSync(store).run(
        widget.diner,
        ask: (mine, theirs) async => await askPixel(
          context,
          title: 'Which save to keep?',
          body:
              'On this phone: ${mine.summary}.\n'
              'In ${store.name}: ${theirs.summary}.',
          yes: 'Use ${store.name}',
          no: 'Use this phone',
          yesKey: const ValueKey('use-cloud'),
        ),
      );
      note = r.message;
      bad =
          r.action == SyncAction.nothing && r.message.contains('not available');
      next = r.diner;
    } catch (_) {
      note = 'Could not reach ${store.name}. Try again in a moment.';
      bad = true;
    }
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _bad = bad;
      _note = note;
    });
    if (next != null) widget.onLoad?.call(next);
  }

  Future<void> _load() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    final Diner found;
    try {
      found = SaveCode.decode(text);
    } on SaveCodeError catch (e) {
      if (!mounted) return;
      setState(() {
        _bad = true;
        _note = '${e.message} Copy the whole code, then try again.';
      });
      return;
    }
    if (!mounted) return;
    final here = widget.diner == null
        ? 'nothing yet'
        : SaveInfo.of(widget.diner!).summary;
    final there = SaveInfo.of(found).summary;
    final ok = await askPixel(
      context,
      title: 'Replace this diner?',
      body:
          'On this phone: $here.\nIn the code: $there.\nLoading the code '
          'replaces what is on this phone.',
      yes: 'Load it',
      no: 'Keep mine',
      yesKey: const ValueKey('confirm-load'),
    );
    if (!ok || !mounted) return;
    widget.onLoad?.call(found);
  }

  @override
  Widget build(BuildContext context) {
    return Panel(
      key: const ValueKey('save-panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PxText(
            widget.diner == null ? 'Empty' : SaveInfo.of(widget.diner!).summary,
            key: const ValueKey('save-summary'),
            style: const TextStyle(color: Pal.text, fontSize: 16),
          ),
          const PxText(
            'Your restaurant is kept on this phone. Copy a save code to keep '
            'a copy somewhere else, and paste it back to carry on from it.',
            style: TextStyle(color: Pal.dim, fontSize: 14),
          ),
          const SizedBox(height: 8),
          if (widget.onSave != null) ...[
            GoldButton(
              key: const ValueKey('save-now'),
              label: widget.store == null ? 'Save now' : 'Save now and back up',
              onTap: _saveNow,
            ),
            const SizedBox(height: 8),
          ],
          if (widget.diner != null)
            GoldButton(
              key: const ValueKey('copy-save'),
              label: 'Copy save code',
              filled: false,
              color: Pal.text,
              onTap: _copy,
            ),
          if (widget.store != null) ...[
            const SizedBox(height: 8),
            GoldButton(
              key: const ValueKey('sync-save'),
              label: widget.diner == null
                  ? 'Restore from ${widget.store!.name}'
                  : 'Back up with ${widget.store!.name}',
              onTap: _syncing ? null : _sync,
            ),
          ],
          if (widget.onLoad != null) ...[
            const SizedBox(height: 8),
            GoldButton(
              key: const ValueKey('load-save'),
              label: 'Load a save code',
              filled: false,
              color: Pal.text,
              onTap: _load,
            ),
          ],
          if (widget.onTitle != null) ...[
            const SizedBox(height: 8),
            GoldButton(
              key: const ValueKey('to-title'),
              label: 'Save and go to the title screen',
              filled: false,
              color: Pal.text,
              onTap: widget.onTitle,
            ),
          ],
          if (_note.isNotEmpty) ...[
            const SizedBox(height: 8),
            PxText(
              _note,
              key: const ValueKey('save-note'),
              style: TextStyle(color: _bad ? Pal.red : Pal.green, fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }
}
