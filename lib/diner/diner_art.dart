import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One sprite: its image, where its origin sits in the image, and the box
/// that actually has pixels in it.
class Spr {
  const Spr(this.image, this.ax, this.ay, this.trim);

  final ui.Image image;

  /// The sprite's origin in image pixels. For fixtures it is the top vertex of
  /// their first cell; for people, the point between their feet.
  final int ax;
  final int ay;

  /// The opaque part of the image, for thumbnails.
  final ui.Rect trim;

  /// A stand-in for missing art: nothing to draw.
  bool get blank => trim.isEmpty;

  int get width => image.width;
  int get height => image.height;
}

/// Every diner sprite, drawn by `tools/gen_diner_art.py` into `assets/diner/`
/// and baked once into small images. They are blitted with nearest-neighbour
/// sampling, never scaled by a fraction.
class DinerArt {
  DinerArt._(this._sprites);

  static DinerArt? _instance;

  /// Null until [load] completes.
  static DinerArt? get instance => _instance;

  final Map<String, Spr> _sprites;

  static Future<DinerArt> load([AssetBundle? bundle]) async {
    final b = bundle ?? rootBundle;
    // Not cached in debug, so a restart sees regenerated art.
    final manifest = await b.loadString(
      'assets/diner/manifest.txt',
      cache: !kDebugMode,
    );
    Future<MapEntry<String, Spr>> decode(List<String> p) async {
      final data = await b.load('assets/diner/${p[0]}.png');
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      return MapEntry(
        p[0],
        Spr(
          frame.image,
          int.parse(p[3]),
          int.parse(p[4]),
          ui.Rect.fromLTWH(
            double.parse(p[5]),
            double.parse(p[6]),
            double.parse(p[7]),
            double.parse(p[8]),
          ),
        ),
      );
    }

    // All of them at once: they are tiny, and loading one at a time made
    // startup wait on 127 round trips.
    final sprites = Map.fromEntries(
      await Future.wait([
        for (final line in manifest.split('\n'))
          if (line.isNotEmpty && !line.startsWith('#')) decode(line.split(' ')),
      ]),
    );
    return _instance = DinerArt._(sprites);
  }

  /// A sprite by name. Missing art is a 1 pixel blank rather than a crash.
  Spr sprite(String name) => _sprites[name] ?? _missing(name);

  bool has(String name) => _sprites.containsKey(name);

  final Set<String> _reported = {};
  Spr? _blank;

  Spr _missing(String name) {
    if (_reported.add(name)) {
      debugPrint('DinerArt: missing "$name"; run tools/gen_diner_art.py.');
    }
    return _blank ??= Spr(
      _sprites.values.first.image,
      0,
      0,
      const ui.Rect.fromLTWH(0, 0, 0, 0),
    );
  }
}
