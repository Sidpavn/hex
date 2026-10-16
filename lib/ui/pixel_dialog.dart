import 'package:flutter/material.dart';

import 'widgets.dart';

/// Asks a yes or no question in the game's own style. Returns true for yes.
/// [yesKey] marks the confirming button, for tests.
Future<bool> askPixel(
  BuildContext context, {
  required String title,
  required String body,
  required String yes,
  required String no,
  Key? yesKey,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0xAA000000),
    builder: (c) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: PixelBox(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PxText(
              title,
              style: const TextStyle(color: Pal.gold, fontSize: 22),
            ),
            const SizedBox(height: 8),
            PxText(body, style: const TextStyle(color: Pal.text, fontSize: 14)),
            const SizedBox(height: 16),
            GoldButton(
              key: yesKey,
              label: yes,
              filled: false,
              color: Pal.red,
              onTap: () => Navigator.pop(c, true),
            ),
            const SizedBox(height: 8),
            GoldButton(label: no, onTap: () => Navigator.pop(c, false)),
          ],
        ),
      ),
    ),
  );
  return ok == true;
}

/// Tells the player something in the middle of the screen and waits for them
/// to read it. [button] marks the one way out; [buttonKey] is for tests.
Future<void> noticePixel(
  BuildContext context, {
  required String title,
  required String body,
  required String button,
  Key? buttonKey,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  barrierColor: const Color(0xAA000000),
  builder: (c) => Dialog(
    backgroundColor: Colors.transparent,
    elevation: 0,
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
    child: PixelBox(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PxText(title, style: const TextStyle(color: Pal.gold, fontSize: 22)),
          const SizedBox(height: 8),
          PxText(body, style: const TextStyle(color: Pal.text, fontSize: 14)),
          const SizedBox(height: 16),
          GoldButton(
            key: buttonKey,
            label: button,
            onTap: () => Navigator.pop(c),
          ),
        ],
      ),
    ),
  ),
);
