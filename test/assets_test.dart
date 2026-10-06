import 'package:flutter_test/flutter_test.dart';
import 'package:hex/game/models.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';

void main() {
  testWidgets('missing art draws nothing instead of crashing', (tester) async {
    late PixelAssets art;
    await tester.runAsync(() async => art = await PixelAssets.load());
    // Things that are not in the sheet (as after a hot reload that kept the
    // old sheet) come back as a blank pixel, never a null-check error.
    expect(art.sprite('no_such_sprite').width, 1);
    expect(art.mask('no_such_mask').width, 1);
    expect(art.icon('no_such_icon'), isNotNull);
    expect(art.unit(UnitType.knight, Team.enemy, 'nope'), isNotNull);
    // And real art is the real thing.
    expect(art.sprite('bridge').width, 24);
    expect(art.mask('cliffSE2').width, 24);
  });
}
