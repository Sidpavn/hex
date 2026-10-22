import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hex/diner/catalog.dart';
import 'package:hex/diner/diner.dart';

/// Opens the build popup, on the group [kind] is in. The Build button on the
/// board's edge opens it, so this only taps when it is not already showing.
Future<void> openShelf(WidgetTester tester, [Kind? kind]) async {
  if (find.byKey(const ValueKey('shelf-popup')).evaluate().isEmpty) {
    final button = find.byKey(const ValueKey('build-mode'));
    if (button.evaluate().isEmpty) return;
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
  if (kind != null) {
    final tab = find.byKey(ValueKey('shelf-tab-${categoryOf[kind]!.name}'));
    await tester.tap(tab);
    await tester.pump();
  }
}
