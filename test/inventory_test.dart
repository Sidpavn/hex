import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/ui/inventory_ui.dart';
import 'package:hex/ui/pixel/pixel_assets.dart';
import 'package:hex/ui/widgets.dart';
import 'package:hex/world/world_state.dart';

void main() {
  testWidgets('a spell with no free slot waits under spare spells, and can be '
      'put in a slot', (tester) async {
    await tester.runAsync(() => PixelAssets.load());
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // Fireball and Mend fill the two slots; Shield has nowhere to go.
    final w = WorldState()
      ..learn('mend')
      ..learn('shield');
    expect(w.spellSlots, ['fireball', 'mend']);

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Stack(
            children: [
              InventoryOverlay(
                world: w,
                atCamp: false,
                onChanged: () {},
                onClose: () {},
                onUse: (_) => false,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Spare spells'), findsOneWidget);
    final spare = find.byWidgetPredicate(
      (x) => x is ItemSlot && x.icon == 'shield',
    );
    expect(spare, findsOneWidget);

    await tester.tap(spare);
    await tester.pump();
    expect(find.text('Put it in a spell slot to use it:'), findsOneWidget);
    await tester.tap(find.widgetWithText(GoldButton, 'Spell 2'));
    await tester.pump();
    expect(w.spellSlots, ['fireball', 'shield']);
    // Mend is now the spare one.
    expect(find.text('Spare spells'), findsOneWidget);
    expect(
      find.byWidgetPredicate((x) => x is ItemSlot && x.icon == 'heal'),
      findsWidgets,
    );
  });

  testWidgets('no spare spells, no section', (tester) async {
    await tester.runAsync(() => PixelAssets.load());
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final w = WorldState();
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Stack(
            children: [
              InventoryOverlay(
                world: w,
                atCamp: false,
                onChanged: () {},
                onClose: () {},
                onUse: (_) => false,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Spare spells'), findsNothing);
  });
}
