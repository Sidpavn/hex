// Dev tool: renders the board to a PNG so the pixel art can be eyeballed.
// Run with PIXEL_PREVIEW=/path/out.png flutter test test/pixel_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:hex/game/game_controller.dart';
import 'package:hex/ui/board_painter.dart';
import 'package:hex/ui/fx_layer.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';

void main() {
  final out = Platform.environment['PIXEL_PREVIEW'];

  testWidgets('render board preview', (tester) async {
    await tester.runAsync(() async {
      await PixelAssets.load();
      final game = GameController(seed: 3, aiDelayScale: 0);
      final fx = FxLayer(game);
      for (var i = 0; i < 40; i++) {
        fx.update(0.1);
      }
      const size = ui.Size(390, 560);
      const dpr = 3.0;
      final rec = ui.PictureRecorder();
      final canvas = ui.Canvas(rec)..scale(dpr);
      BoardPainter(game, fx).paint(canvas, size);
      final img = await rec.endRecording().toImage(
        (size.width * dpr).round(),
        (size.height * dpr).round(),
      );
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      File(out!).writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }, skip: out == null);
}
