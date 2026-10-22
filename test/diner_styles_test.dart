// Wallpapers and floors: some free, some bought with gems.
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/diner/city.dart';
import 'package:hex/diner/diner.dart';
import 'package:hex/diner/diner_art.dart';
import 'package:hex/diner/styles.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';

void main() {
  group('the list', () {
    test('has a free default for each, and ids that do not repeat', () {
      expect(styleById(StyleKind.wall, wallDefault)!.free, isTrue);
      expect(styleById(StyleKind.floor, floorDefault)!.free, isTrue);
      final keys = {for (final s in styles) '${s.kind.name}:${s.id}'};
      expect(keys.length, styles.length);
    });

    test('some are free and some cost gems', () {
      expect(styles.where((s) => s.free).length, greaterThan(3));
      expect(styles.where((s) => !s.free).length, greaterThan(5));
      expect(styles.every((s) => s.gems >= 0), isTrue);
    });

    test('the default has no suffix, the rest name their sprite', () {
      expect(styleById(StyleKind.wall, wallDefault)!.suffix, '');
      expect(styleById(StyleKind.floor, floorDefault)!.suffix, '');
      expect(styleById(StyleKind.floor, 'mint')!.suffix, '_s_mint');
      expect(styleById(StyleKind.wall, 'rose')!.suffix, '_s_rose');
    });

    testWidgets('every style has its pictures', (tester) async {
      await tester.runAsync(() async {
        await PixelAssets.load();
        await DinerArt.load();
      });
      final art = DinerArt.instance!;
      for (final s in styles) {
        if (s.kind == StyleKind.wall) {
          for (final n in const [
            'wall_a',
            'wall_a_window',
            'wall_a_board',
            'wall_b',
            'wall_b_window',
            'wall_corner',
          ]) {
            expect(
              art.sprite('$n${s.suffix}'),
              isNotNull,
              reason: '$n ${s.id}',
            );
          }
        } else {
          expect(art.sprite('floor_a${s.suffix}'), isNotNull, reason: s.id);
          expect(art.sprite('floor_b${s.suffix}'), isNotNull, reason: s.id);
        }
      }
    });
  });

  group('owning', () {
    Diner diner() => Diner(coins: 0)..gems = 100;

    test('free ones are always usable, paid ones are not yet', () {
      final d = diner();
      expect(d.owns(styleById(StyleKind.wall, 'cream')!), isTrue);
      expect(d.owns(styleById(StyleKind.wall, 'rose')!), isFalse);
      expect(d.useStyle(styleById(StyleKind.wall, 'rose')!), isFalse);
      expect(d.wallStyle, wallDefault);
    });

    test('buying takes the gems, once, and the style is kept', () {
      final d = diner();
      final rose = styleById(StyleKind.wall, 'rose')!;
      expect(d.buyStyle(rose), PlaceResult.ok);
      expect(d.gems, 70);
      expect(d.buyStyle(rose), PlaceResult.taken);
      expect(d.gems, 70);
      expect(d.useStyle(rose), isTrue);
      expect(d.wallStyle, 'rose');
    });

    test('too few gems buys nothing', () {
      final d = Diner(coins: 0)..gems = 10;
      expect(
        d.buyStyle(styleById(StyleKind.floor, 'wood')!),
        PlaceResult.broke,
      );
      expect(d.gems, 10);
      expect(d.ownedStyles, isEmpty);
    });

    test('a wall and a floor with the same id are two styles', () {
      final d = diner();
      d.buyStyle(styleById(StyleKind.floor, 'mint')!);
      expect(d.owns(styleById(StyleKind.floor, 'mint')!), isTrue);
      expect(d.owns(styleById(StyleKind.wall, wallDefault)!), isTrue);
    });

    test('they are saved, and what is not owned is not applied', () {
      final d = diner();
      d.buyStyle(styleById(StyleKind.wall, 'brick')!);
      d.useStyle(styleById(StyleKind.wall, 'brick')!);
      d.useStyle(styleById(StyleKind.floor, 'slate')!);
      final back = Diner.fromJson(d.toJson());
      expect(back.gems, 50);
      expect(back.wallStyle, 'brick');
      expect(back.floorStyle, 'slate');
      final j = d.toJson();
      j['floor'] = 'checker';
      expect(Diner.fromJson(j).floorStyle, floorDefault, reason: 'not bought');
      j['styles'] = ['floor:checker', 'wall:nothing', 'junk'];
      final loaded = Diner.fromJson(j);
      expect(loaded.floorStyle, 'checker');
      expect(loaded.ownedStyles, {'floor:checker'});
    });

    test('a game with none saves nothing extra', () {
      final j = Diner(coins: 0).toJson();
      for (final k in ['gems', 'styles', 'wall', 'floor']) {
        expect(j.containsKey(k), isFalse, reason: k);
      }
    });
  });

  group('the room', () {
    test('the floor and walls follow the style', () {
      final d = Diner(coins: 0)..gems = 100;
      expect(groundTile(d, const Cell(3, 5)), 'floor_a');
      d.buyStyle(styleById(StyleKind.floor, 'wood')!);
      d.useStyle(styleById(StyleKind.floor, 'wood')!);
      expect(groundTile(d, const Cell(3, 5)), 'floor_a_s_wood');
    });
  });
}
